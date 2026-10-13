"""The pipeline's own logic, without OCR engines: a fake engine reads each
strip as the line it is (from the made-up riff), so this checks finding the
lines, staves, labels, widths and the vote."""
import cv2

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


def test_align_measures_a_staff_from_one_start():
    def line(dash_x0, cw, cols):
        return pipeline.Line(0, 10, 0, 500, 5, cols, cw, dash_x0)
    # The B line starts with a fret, so its dashes start a column late.
    group = pipeline.align([line(100, 20, 30), line(120, 21, 29), line(100, 20, 30)])
    assert {(l.dash_x0, l.cw, l.cols) for l in group} == {(100, 20.0, 30)}


def test_even_ends_a_staffs_lines_together():
    assert pipeline.even(["e|-3--|", "B|-1--------|", "G|-0"], 5) == [
        "e|-3---|", "B|-1---|", "G|-0---|"]
    assert pipeline.even(["e|-3-|", "B|-1----5|"], 3) == ["e|-3-----|", "B|-1----5|"]


def test_vote_takes_the_reading_most_like_the_others():
    assert pipeline.vote(["e|-3-|", "e|-8-|", "e|-3-|"]) == "e|-3-|"
    assert pipeline.vote(["e|-1-|", "e|-2-|"]) == "e|-1-|"  # tie: first engine


def test_keeps_the_notations_around_the_tab():
    riff = [l for l in selftest.RIFF.splitlines() if l]
    seen = iter(riff * 2)
    gray = pipeline.prepare(pipeline.decode(selftest.page_photo()))
    groups = pipeline.staves(pipeline.find_lines(gray))
    first = groups[0][0]
    staff_top = min(l.y0 for l in groups[0])

    def read_page(half):
        # The staves are blanked out before the page is read.
        assert (half[first.y0 // 2 + 2:first.y1 // 2 - 2] == 255).all()
        y = staff_top / 2 - 60
        x = (first.dash_x0 + 3 * first.cw) / 2  # the tab's 6th column
        return [(selftest.TITLE, 30, y - 40, 300, y - 25, 0.9),
                ("Am", x, y, x + 20, y + 15, 0.95),
                ("https://tabs.example.com", 30, 1300, 300, 1315, 0.9),
                ("garbled", 30, 1400, 300, 1415, 0.2)]

    r = pipeline.transcribe(selftest.page_photo(), {"a": lambda strip, line: next(seen)},
                            read_page=read_page)
    lines = r.text.splitlines()
    assert lines[0] == selftest.TITLE
    assert lines[1] == "     Am"
    assert lines[2].startswith("e|")
    assert "https" not in r.text and "garbled" not in r.text
    assert selftest.score(selftest.RIFF, r.text) == 1.0
    assert "page" in r.timings


def test_notations_and_their_columns():
    assert pipeline.is_notation("Am  G  C")
    assert pipeline.is_notation("Chorus (play twice)")
    assert not pipeline.is_notation("www.tabs.example.com")
    assert not pipeline.is_notation("Page 2 of 3")
    assert not pipeline.is_notation("--3--5--x-")
    assert not pipeline.is_notation("123")
    assert pipeline.place_words([("G", 8), ("Am", 2)]) == "  Am    G"
    assert pipeline.place_words([("Am", 0), ("G", 1)]) == "Am G"
    assert pipeline.join([("text", "Intro"), ("staff", "e|-|"), ("staff", "e|-|"),
                          ("text", "la")]) == "Intro\ne|-|\n\ne|-|\n\nla"


def _pdf_of(*jpgs):
    """A PDF whose pages are these photos (a scanned document)."""
    import io
    import numpy as np
    from PIL import Image
    images = [Image.fromarray(cv2.imdecode(np.frombuffer(j, np.uint8), cv2.IMREAD_COLOR)[..., ::-1])
              for j in jpgs]
    out = io.BytesIO()
    images[0].save(out, format="PDF", save_all=True, append_images=images[1:], resolution=150)
    return out.getvalue()


def test_a_pdf_is_read_as_its_pages_photographed():
    riff = [l for l in selftest.RIFF.splitlines() if l]
    seen = iter(riff * 4)
    pdf = _pdf_of(selftest.page_photo(), selftest.page_photo())
    pages = pipeline.pdf_pages(pdf)
    assert len(pages) == 2 and pages[0].shape[1] == pipeline.PDF_RENDER_WIDTH
    r = pipeline.transcribe_pdf(pdf, {"a": lambda strip, line: next(seen)})
    assert (r.staves, r.lines) == (4, 24)
    # Both pages read back the whole riff, one after the other.
    assert r.text.count("e|") == 4
    assert selftest.score(selftest.RIFF + selftest.RIFF, r.text) == 1.0


def test_not_a_pdf_is_an_error():
    import pytest
    with pytest.raises(ValueError):
        pipeline.pdf_pages(b"not a pdf")
