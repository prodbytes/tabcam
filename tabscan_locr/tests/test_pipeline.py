"""The pipeline's own logic, without OCR engines: a fake engine reads each
strip as the line it is (from the made-up riff), so this checks finding the
lines, staves, labels, widths and the vote."""
from locr import pipeline, selftest


def test_finds_every_string_line_and_staff():
    gray = pipeline.prepare(pipeline.decode(selftest.page_photo()))
    lines = pipeline.find_lines(gray)
    assert len(lines) == 12
    groups = pipeline.staves(lines)
    assert [len(g) for g in groups] == [6, 6]
    widths = {max(l.cols for l in g) for g in groups}
    assert all(abs(w - 37) <= 2 for w in widths), widths


def test_transcribes_with_perfect_engines():
    riff = [l for l in selftest.RIFF.splitlines() if l]
    seen = iter(riff * 2)

    def perfect(strip, line):
        return next(seen)

    r = pipeline.transcribe(selftest.page_photo(), {"a": perfect})
    assert r.staves == 2 and r.lines == 12
    assert selftest.score(selftest.RIFF, r.text) == 1.0


def test_rebuild_fills_gaps_and_labels():
    assert pipeline.rebuild("B l --3  5h7", "B", 12) == "B|--3--5h7----|"
    assert pipeline.rebuild("", "E", 4) == "E|----|"
    assert pipeline.rebuild("|-1O-", "", 4) == "|-10-|"


def test_vote_takes_the_reading_most_like_the_others():
    assert pipeline.vote(["e|-3-|", "e|-8-|", "e|-3-|"]) == "e|-3-|"
    assert pipeline.vote(["e|-1-|", "e|-2-|"]) == "e|-1-|"  # tie: first engine
