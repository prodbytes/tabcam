"""Reading a page Claude's way: when the OCR engines find no tab on a page
(a handwritten tab, or one on drawn staff lines, which they don't read),
Claude (vision) transcribes the image into the app's plain-text tab, with
the page's other notations (title, chord names, section names, lyrics).
Off while the Claude API key isn't set up."""
import base64
import json
import os

import cv2

MODEL = os.environ.get("VISION_MODEL", "claude-opus-5-5")
MAX_SIDE = 1800

PROMPT = """\
This is a page of guitar or bass tablature: printed, typeset or \
handwritten, maybe on drawn staff lines, maybe photographed or scanned. \
Transcribe it into plain-text tab, as written on the page.

- Each staff: one line per string, high to low, `e|`, `B|`, `G|`, `D|`, \
`A|`, `E|` (bass: `G|`, `D|`, `A|`, `E|`), the notes at their columns with \
dashes between, `|` for bar lines; the staff's lines all the same length. \
Strings numbered on the page count from the highest (1 = e).
- Keep the notes in order and notes played together in the same column; \
keep techniques as written (h, p, b, r, /, \\, ~, x, and a fret in \
parentheses).
- Text around the tab goes where it is: the title first, section names \
(Intro, Chorus, ...) and repeat marks (2x) above their staff, chord names \
on a line right above the staff at the columns they're over, lyrics under \
it. Leave out page furniture (scanner watermarks, page numbers, web \
addresses).
- Separate staves with a blank line.
- If the page has no tablature, say so (found false, empty text)."""

SCHEMA = {
    "type": "object",
    "properties": {
        "found": {"type": "boolean"},
        "text": {"type": "string", "description": "The plain-text tab"},
    },
    "required": ["found", "text"],
    "additionalProperties": False,
}


def _jpeg(img):
    h, w = img.shape[:2]
    scale = min(1.0, MAX_SIDE / max(h, w))
    if scale < 1:
        img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    ok, data = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 85])
    if not ok:
        raise ValueError("couldn't encode the page")
    return base64.b64encode(data.tobytes()).decode()


def read_tab(img, client=None):
    """[img]: the page (BGR). Its tab as text, or "" when it has none."""
    from . import claude
    client = client or claude.client()
    r = client.messages.create(
        model=MODEL,
        max_tokens=16000,
        thinking={"type": "adaptive"},
        output_config={"effort": "high",
                       "format": {"type": "json_schema", "schema": SCHEMA}},
        messages=[{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                         "data": _jpeg(img)}},
            {"type": "text", "text": PROMPT},
        ]}],
    )
    if r.stop_reason == "refusal":
        return ""
    text = next((b.text for b in r.content if b.type == "text"), "")
    try:
        answer = json.loads(text)
    except ValueError:
        return ""
    tab = (answer.get("text") or "").strip()
    return tab + "\n" if answer.get("found") and tab else ""
