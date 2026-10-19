"""Auto-correct: checks a read tab against the song's tab found online.

The app sends the event's text tab and the song's name. Claude (with web
search and web fetch) finds the song's tab, on the popular tab sites first,
compares it with the reading and answers with corrections, each naming a
note of the reading by its id (n1, n2, ...), which parse() gives every note
here, so a correction can't land on the wrong column. Each correction is
checked against the reading before the app sees it; the app shows them per
note, and the user accepts or rejects each.

Only corrections come back, never the tab found online.
"""
import os
import re
import time
from dataclasses import dataclass

MODEL = os.environ.get("AUTOCORRECT_MODEL", "claude-opus-5-5")
MAX_TEXT = 20_000
MAX_SONG = 200
MAX_CORRECTIONS = 300
DEADLINE = 270  # seconds; the function times out at 300

# What a note may be written with: frets and techniques.
NOTE_CHARS = r"0-9hpbrxXtsv/\\~()<>.^=*"
NOTE = re.compile(rf"^[{NOTE_CHARS}]{{1,6}}$")
# A string line: an optional string name, then dashes, bars and notes.
LABEL = re.compile(r"^\s*([A-Ga-g][#b]?)?\s*[|:]?")
BODY = re.compile(rf"^[-|:{NOTE_CHARS}\s]*$")
TOKEN = re.compile(r"[^-|:\s]+")


@dataclass(frozen=True)
class Note:
    id: str
    line: int  # 0-based
    column: int  # 0-based
    text: str


@dataclass
class Reading:
    lines: list
    tab_lines: set
    notes: dict  # id -> Note
    body_start: dict  # line -> column where its dashes start


def parse(text):
    """The reading's string lines and their notes, numbered in order."""
    lines = text.split("\n")
    tab_lines, notes, body_start = set(), {}, {}
    for i, line in enumerate(lines):
        start = LABEL.match(line).end()
        body = line[start:]
        if body.count("-") < 3 or not BODY.match(body):
            continue
        tab_lines.add(i)
        body_start[i] = start
        for m in TOKEN.finditer(body):
            nid = f"n{len(notes) + 1}"
            notes[nid] = Note(nid, i, start + m.start(), m.group())
    return Reading(lines, tab_lines, notes, body_start)


def describe(reading):
    """The reading as Claude sees it: each line, and each string line's
    notes with their ids and columns."""
    out = []
    by_line = {}
    for n in reading.notes.values():
        by_line.setdefault(n.line, []).append(n)
    for i, line in enumerate(reading.lines):
        if i in reading.tab_lines:
            out.append(f"line {i} (tab): {line}")
            notes = by_line.get(i, [])
            if notes:
                out.append("  notes: " + "; ".join(f'{n.id}@{n.column} "{n.text}"' for n in notes))
        elif line.strip():
            out.append(f"line {i} (text): {line}")
    return "\n".join(out)


def check(reading, proposed):
    """The corrections that make sense for this reading, as the app takes
    them: {id, line, column, old, new, reason}. Others are dropped."""
    out, taken = [], {}

    def free(line, col, width):
        return all(not (c < col + width and col < c + w) for c, w in taken.get(line, []))

    for c in proposed[:MAX_CORRECTIONS]:
        kind, text = c.get("kind"), (c.get("text") or "").strip()
        reason = (c.get("reason") or "")[:200]
        if kind in ("replace", "delete"):
            note = reading.notes.get(c.get("note") or "")
            if note is None:
                continue
            new = "" if kind == "delete" else text
            if new == note.text or (new and not NOTE.match(new)):
                continue
            line, col, old = note.line, note.column, note.text
        elif kind == "insert":
            line, col, old, new = c.get("line"), c.get("column"), "", text
            if not (isinstance(line, int) and isinstance(col, int)) or line not in reading.tab_lines:
                continue
            row = reading.lines[line]
            # On dashes, and not touching a note (it would read as one).
            if not NOTE.match(new) or col <= reading.body_start[line] or \
                    row[col - 1:col + len(new) + 1] != "-" * (len(new) + 2):
                continue
        else:
            continue
        width = max(len(old), len(new), 1)
        if not free(line, col, width):
            continue
        taken.setdefault(line, []).append((col, width))
        out.append({"id": f"c{len(out) + 1}", "line": line, "column": col,
                    "old": old, "new": new, "reason": reason})
    out.sort(key=lambda c: (c["line"], c["column"]))
    return out


SYSTEM = """\
You check guitar and bass tabs read by OCR from a photo of a page. The \
reading has OCR mistakes: wrong digits (8 for 3, 1 for 7), notes dropped or \
split, stray marks read as notes. Find the song's published tab online and \
use it to correct the reading.

Search the popular tablature sites first (Ultimate Guitar, Songsterr, \
911Tabs, GuitarTabs.cc, AZ Chords, e-chords), then the wider web. Pick the \
version that best matches the reading (same key, tuning, section order and \
note shapes); a reading may cover only part of the song. If you can't find \
the song, or no version matches, say so and propose nothing.

Propose a correction only where the published tab clearly disagrees with \
the reading at that spot. Refer to the reading's notes by their ids. \
Changing a note: kind "replace" with its id and the new text. A note that \
isn't in the published tab: kind "delete" with its id. A missing note: kind \
"insert" with the line, the column in that line, and the note's text. Keep \
the reading's layout; don't move notes or rewrite whole lines. Each \
correction carries a short reason.

Answer only through the submit_corrections tool. Never copy the published \
tab itself into your answer: only the corrections, the song and where you \
found it."""

SUBMIT = {
    "name": "submit_corrections",
    "description": "Hands back the song found and the corrections to the reading. Call it once, at the end.",
    "strict": True,
    "input_schema": {
        "type": "object",
        "properties": {
            "found": {"type": "boolean", "description": "Whether a matching tab was found online"},
            "title": {"type": "string"},
            "artist": {"type": "string"},
            "sources": {"type": "array", "items": {"type": "string"},
                        "description": "URLs of the tabs compared with"},
            "summary": {"type": "string", "description": "One or two sentences for the user"},
            "corrections": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "kind": {"type": "string", "enum": ["replace", "delete", "insert"]},
                        "note": {"type": "string", "description": "The note's id (replace, delete); empty for insert"},
                        "line": {"type": "integer", "description": "The line (insert); the note's line otherwise"},
                        "column": {"type": "integer", "description": "The column (insert); the note's column otherwise"},
                        "text": {"type": "string", "description": "The note's new text (replace, insert); empty for delete"},
                        "reason": {"type": "string"},
                    },
                    "required": ["kind", "note", "line", "column", "text", "reason"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["found", "title", "artist", "sources", "summary", "corrections"],
        "additionalProperties": False,
    },
}

TOOLS = [
    {"type": "web_search_20260209", "name": "web_search", "max_uses": 6},
    # A page's content is capped: a tab page fits, a huge one doesn't fill
    # every later turn's input.
    {"type": "web_fetch_20260209", "name": "web_fetch", "max_uses": 6,
     "max_content_tokens": 30000},
    SUBMIT,
]


class NotSetUp(Exception):
    pass


class Corrector:
    """Asks Claude; the client is made on first use (the key comes from
    Secrets Manager), and tests pass their own."""

    def __init__(self, client=None, clock=time.monotonic):
        self._client = client
        self._clock = clock

    @property
    def client(self):
        if self._client is None:
            from . import claude
            try:
                self._client = claude.client()
            except claude.NotSetUp as e:
                raise NotSetUp(str(e)) from e
        return self._client

    def correct(self, text, song=""):
        """{found, title, artist, sources, summary, corrections, ...}."""
        reading = parse(text)
        if not reading.notes:
            return {"found": False, "title": "", "artist": "", "sources": [],
                    "summary": "No tab lines to check.", "corrections": [], "notes": 0}
        answer, usage = self._ask(reading, song)
        corrections = check(reading, answer.get("corrections") or [])
        return {
            "found": bool(answer.get("found")),
            "title": str(answer.get("title") or "")[:MAX_SONG],
            "artist": str(answer.get("artist") or "")[:MAX_SONG],
            "sources": [u for u in answer.get("sources") or [] if isinstance(u, str)
                        and u.startswith("https://")][:5],
            "summary": str(answer.get("summary") or "")[:500],
            "corrections": corrections,
            "proposed": len(answer.get("corrections") or []),
            "notes": len(reading.notes),
            "usage": usage,
        }

    def _ask(self, reading, song):
        start = self._clock()
        prompt = (
            f"The song, as the user named it: {song.strip() or '(not named)'}\n\n"
            "The reading, line by line, with its notes (id@column \"text\"):\n\n"
            f"{describe(reading)}"
        )
        messages = [{"role": "user", "content": prompt}]
        usage = {"input": 0, "output": 0, "searches": 0, "turns": 0}
        nudged = False
        for _ in range(8):
            left = DEADLINE - (self._clock() - start)
            if left < 10:
                raise TimeoutError("auto-correct ran out of time")
            with self.client.beta.messages.stream(
                model=MODEL,
                max_tokens=32000,
                system=SYSTEM,
                messages=messages,
                tools=TOOLS,
                thinking={"type": "adaptive"},
                output_config={"effort": "medium"},
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
                timeout=left,
            ) as stream:
                r = stream.get_final_message()
            usage["turns"] += 1
            usage["input"] += r.usage.input_tokens
            usage["output"] += r.usage.output_tokens
            stu = getattr(r.usage, "server_tool_use", None)
            usage["searches"] += getattr(stu, "web_search_requests", 0) or 0
            if r.stop_reason == "refusal":
                return {"found": False, "summary": "Couldn't check this one."}, usage
            for block in r.content:
                if block.type == "tool_use" and block.name == SUBMIT["name"]:
                    return dict(block.input), usage
            if r.stop_reason == "pause_turn":
                messages = [messages[0], {"role": "assistant", "content": r.content}]
                continue
            if nudged:
                break
            nudged = True
            messages = [messages[0], {"role": "assistant", "content": r.content},
                        {"role": "user", "content": "Answer with submit_corrections now."}]
        return {"found": False, "summary": "Couldn't find a matching tab."}, usage
