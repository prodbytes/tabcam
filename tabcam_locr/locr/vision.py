"""Reading a page a vision model's way: a handwritten tab on drawn staff
lines, which the OCR engines read poorly (staves.py: about two frets in
three right), is read whole by a model on Amazon Bedrock, into the app's
plain-text tab with the page's other notations (title, section names,
repeat marks).

The model is VISION_MODEL (a Bedrock model or inference profile ID; unset:
off). The stack sets Moonshot's Kimi K3.1 (us.moonshotai.kimi-k3.1), the
one model the account can call that reads these pages (specs/cloud-ocr.md,
"Verified captures"). It thinks before it answers, with most of
VISION_MAX_TOKENS, and reads worse with less.
"""
import os
import re

import cv2

MODEL = os.environ.get("VISION_MODEL", "")
MAX_TOKENS = int(os.environ.get("VISION_MAX_TOKENS", "16000"))
# Bedrock's service tier: flex costs half the default's and read the pages
# as well, as fast (measured 2026-11-13), but it's served last when Bedrock
# is busy: then the reading goes to the default tier at once. Empty: the
# model's own default, no tier asked.
TIER = os.environ.get("VISION_TIER", "flex")
# The page as the model was measured on it.
MAX_WIDTH, MAX_HEIGHT = 1600, 2400
NO_TAB = "NO TAB"

PROMPT = """\
This image is a page of handwritten guitar tablature on staff lines, \
scanned or photographed. Transcribe it into an ASCII text tab.

How to read the page:
- Each staff is six horizontal lines: the six strings, from the top line \
down e, B, G, D, A, E (the handwritten 1 to 6 at the left edge of some \
staves number the strings; they are not notes). A staff of four lines is a \
bass's: G, D, A, E.
- A number is a fret. It belongs to the line it is written on, or sits just \
above. People write a run of notes on neighbouring strings as a little \
staircase: look carefully at which line each number touches. Numbers \
stacked in one column are a chord.
- Frets go from 0 to 24: two digits close together are one number (10, 12, \
13), two digits apart are two notes (7 5).
- A short dash or stroke between two numbers on a string is a slide: write \
`/` when the second is higher, `\\` when lower. An arc or an underline \
joining numbers is a slur: write `_` between them. A number in brackets \
after a note is a bend target: write it as on the page, `7(9)`. A wavy line \
after a note is vibrato: `~`.
- A vertical stroke across the staff is a bar line: `|` on all six lines.
- Ignore faint grey print showing through from the back of the sheet, empty \
staves, and a scanner app's footer.
- Keep titles, section names and marks like "2x" as a text line above the \
staff they belong to.

Output format: for each staff with notes, six lines, in page order, a blank \
line between staves:

e|--------------|
B|---8-8--------|
G|-5-7/9----9---|
D|--------------|
A|--------------|
E|--------------|

Every line of a staff has the same length; notes played one after another \
are in different columns, left to right as on the page; notes of a chord \
share a column. Fill with `-`. Output only the tab text, nothing else. If \
the page has no tablature, output only: """ + NO_TAB


class NotSetUp(Exception):
    pass


_client = None


def client():
    """The Bedrock runtime client, made on first use."""
    global _client
    if _client is None:
        import boto3
        from botocore.config import Config
        # A page takes the model about a minute. Throttles are waited out
        # in read_tab; botocore retries the rest once.
        _client = boto3.client("bedrock-runtime", config=Config(
            connect_timeout=10, read_timeout=CALL_SECONDS,
            retries={"max_attempts": 2, "mode": "standard"}))
    return _client


# The account's tokens per minute run out with a dozen pages at once (each
# reserves its maxTokens): a throttle is waited out, the next minute's
# tokens come, up to WAITS times (the worker has 15 minutes); then the
# engines' reading stands.
WAITS = (20, 40, 60)
CALL_SECONDS = 180  # a reading takes about 55 s
BUSY = {"ThrottlingException", "ServiceUnavailableException", "ModelNotReadyException"}


class TooLate(Exception):
    """No time left for a reading before the worker's deadline."""


def _attempts():
    """(tier, seconds to wait first) of each try: the cheaper tier once,
    then the default tier at once and after each of WAITS."""
    first = [(TIER, 0)] if TIER and TIER != "default" else []
    return first + [("default" if TIER else "", 0)] + [("default" if TIER else "", w) for w in WAITS]


def _busy(e):
    return getattr(e, "response", {}).get("Error", {}).get("Code") in BUSY


def _jpeg(img):
    h, w = img.shape[:2]
    scale = min(1.0, MAX_WIDTH / w, MAX_HEIGHT / h)
    if scale < 1:
        img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    ok, data = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 85])
    if not ok:
        raise ValueError("couldn't encode the page")
    return data.tobytes()


def read_tab(img, client_=None, sleep=None, deadline=None):
    """[img]: the page (grayscale or BGR). (its tab as text, the tokens
    used): the text "" when the model finds no tab, or its answer isn't a
    whole one. TooLate when a reading (and its wait) couldn't end before
    [deadline] (time.monotonic())."""
    if not MODEL:
        raise NotSetUp("no vision model configured")
    import random
    import time
    ask = dict(
        modelId=MODEL,
        messages=[{"role": "user", "content": [
            {"image": {"format": "jpeg", "source": {"bytes": _jpeg(img)}}},
            {"text": PROMPT},
        ]}],
        inferenceConfig={"maxTokens": MAX_TOKENS},
    )
    def time_for(seconds):
        if deadline is not None and time.monotonic() + seconds > deadline:
            raise TooLate(f"under {seconds:.0f} s left")

    attempts = _attempts()
    for i, (tier, wait) in enumerate(attempts):
        if wait:
            wait += random.uniform(0, 10)
            time_for(wait + CALL_SECONDS)
            (sleep or time.sleep)(wait)
        time_for(CALL_SECONDS)
        try:
            r = (client_ or client()).converse(
                **ask, **({"serviceTier": {"type": tier}} if tier else {}))
            break
        except Exception as e:
            if i == len(attempts) - 1 or not _busy(e):
                raise
    # The tier that served it, for the log.
    usage = {**r.get("usage", {}), "tier": (r.get("serviceTier") or {}).get("type")}
    if r.get("stopReason") != "end_turn":
        return "", usage  # cut short (max_tokens), filtered: not a whole reading
    answer = "".join(b.get("text", "") for b in r["output"]["message"]["content"])
    return clean(answer), usage


_STRING = re.compile(r"^\s*([eBGDAE])\s*\|(.*)$")
_THINKING = re.compile(r"<think(ing)?>.*?</think(ing)?>", re.S)


def clean(answer):
    """The model's answer as the app's tab text: its staves' lines all one
    length and closed by a bar, a bar line written on some of a staff's
    lines put on all of them, the text lines kept above their staves (page
    furniture left out), a blank line after each staff. "" when it has no
    staff with a fret."""
    from .pipeline import is_notation, join
    lines = [l.rstrip() for l in _THINKING.sub("", answer).splitlines()
             if not l.strip().startswith("```")]
    pieces, staff = [], []

    def end():
        if len(staff) >= 4:
            pieces.append(("staff", "\n".join(_even(staff))))
        staff.clear()

    for line in lines:
        m = _STRING.match(line)
        if m:
            staff.append((m.group(1), m.group(2)))
            continue
        end()
        if line.strip() and line.strip() != NO_TAB and is_notation(line):
            pieces.append(("text", line))
    end()
    # Staves without notes go.
    pieces = [(kind, text) for kind, text in pieces if kind == "text" or frets(text)]
    if not any(kind == "staff" for kind, _ in pieces):
        return ""
    return join(pieces) + "\n"


def _even(staff):
    """[(label, body)] of a staff as its lines, ending together."""
    bodies = [re.sub(r"\s", "-", body.rstrip()).rstrip("|") for _, body in staff]
    width = max(len(b) for b in bodies)
    bodies = [list(b.ljust(width, "-")) for b in bodies]
    # A bar line on some lines is one across the staff, where the others
    # have room for it.
    for col in range(width):
        marked = [b[col] == "|" for b in bodies]
        if any(marked) and all(m or b[col] == "-" for m, b in zip(marked, bodies)):
            for b in bodies:
                b[col] = "|"
    return [f"{label}|{''.join(b)}|" for (label, _), b in zip(staff, bodies)]


def frets(text):
    """How many fret numbers [text]'s string lines have."""
    return sum(len(re.findall(r"\d+", m.group(2)))
               for m in map(_STRING.match, text.splitlines()) if m)
