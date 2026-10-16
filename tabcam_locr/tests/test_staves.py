"""Tabs on drawn staff lines, without OCR engines: a made-up riff's frets
set on drawn lines (selftest.drawn_page), each number "read" by a fake
that knows what the riff has there."""
import re

import numpy as np

from locr import pipeline, selftest, staves


def expected_numbers(riff=selftest.DRAWN_RIFF):
    """The riff's numbers in the order the reader meets them: staff by
    staff, left to right, top to bottom in a column."""
    out = []
    for block in riff.strip().split("\n\n"):
        notes = []
        for string, line in enumerate(block.splitlines()):
            for m in re.finditer(r"[0-9x]+", line[2:]):
                notes.append((m.start(), string, m.group()))
        out += [t for _, _, t in sorted(notes)]
    return out


def gray():
    return pipeline.prepare(pipeline.decode(selftest.drawn_page()))


def test_the_staves_are_found():
    found, _ = staves.find_staves(gray())
    assert [len(ys) for ys, _, _ in found] == [6, 6]
    gaps = np.diff(found[0][0])
    assert gaps.max() - gaps.min() < 4


def test_each_number_is_found_on_its_string():
    g = gray()
    found, mask = staves.find_staves(g)
    ink = staves.erase_lines(g, mask)
    strings = [s for s, _, _, _ in staves.numbers(ink, found[0])]
    riff = selftest.DRAWN_RIFF.split("\n\n")[0].splitlines()
    want = sorted((m.start(), i) for i, line in enumerate(riff)
                  for m in re.finditer(r"[0-9x]+", line[2:]))
    assert strings == [i for _, i in want]


def test_the_page_reads_back_as_its_riff():
    said = iter(expected_numbers())
    r = pipeline.transcribe(selftest.drawn_page(), {"a": lambda s, l: ""},
                            read_crop=lambda crop: next(said))
    assert r.staves == 2
    assert selftest.score(selftest.DRAWN_RIFF, r.text) == 1.0


def test_misreadings_are_fixed_and_runs_split():
    assert staves.fret("S") == "5" and staves.fret("g") == "9" and staves.fret("l0") == "10"
    assert staves.fret("(9)") == "(9)" and staves.fret("X") == "x"
    assert staves.fret("hello") is None and staves.fret("123") is None
    assert [f for _, f in staves.frets("S 7-9", 0, 30)] == ["5", "7", "9"]
    assert [f for _, f in staves.frets("55", 0, 20)] == ["5", "5"]  # past the last fret
    assert [f for _, f in staves.frets("12", 0, 20)] == ["12"]


def test_columns_line_up():
    rows = staves.layout(6, [(0, 10, "3"), (1, 11, "1"), (5, 40, "12")], unit=10)
    assert rows[0].index("3") == rows[1].index("1")
    assert len({len(r) for r in rows}) == 1
    assert rows[5].startswith("E|") and "12" in rows[5]


def test_a_page_without_staves_or_numbers_has_none():
    blank = np.full((1200, 900), 255, np.uint8)
    assert staves.read(blank, lambda c: "5") == ([], [])


def test_frets_around_a_bracketed_one_and_more_misreadings():
    assert [f for _, f in staves.frets("$(6)5", 0, 30)] == ["5", "(6)", "5"]
    assert staves.fret("C") == "6" and staves.fret("$") == "5"
