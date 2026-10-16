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


def test_notes_go_where_the_ink_is_when_engines_drop_dashes():
    """An engine that reads every run of dashes as one dash still gives the
    riff's columns: they come from the notes' ink, not from the dashes."""
    import re
    riff = [l for l in selftest.RIFF.splitlines() if l]
    seen = iter(riff * 2)

    def careless(strip, line):
        return re.sub("-+", "-", next(seen))

    r = pipeline.transcribe(selftest.page_photo(), {"a": careless})
    assert selftest.score(selftest.RIFF, r.text) == 1.0
    got = [l for l in r.text.splitlines() if "|" in l]
    for want, line in zip(riff, got):
        assert [m.start() for m in re.finditer(r"[^-|]+", want[2:])] == \
            [m.start() for m in re.finditer(r"[^-|]+", line[2:])], line


def test_place_tokens_keeps_the_reading_when_counts_differ():
    line = pipeline.Line(0, 10, 0, 100, 5, 10, 10.0, 0)
    assert pipeline.place_tokens("B|-3-5-|", [(20, 25)], line, 6) == "B|-3-5-|"
    assert pipeline.place_tokens("B|-3-5-|", [(20, 25), (50, 55)], line, 8) == "B|--3--5--|"


def test_a_tilted_page_is_levelled():
    import numpy as np
    page = np.full((1400, 1000), 255, np.uint8)
    for y in range(300, 1200, 60):
        cv2.line(page, (100, y), (900, y), 0, 3)
    m = cv2.getRotationMatrix2D((500, 700), 2.0, 1)
    tilted = cv2.warpAffine(page, m, (1000, 1400), borderValue=255)
    assert abs(pipeline.skew(tilted) + 2.0) <= 0.2
    assert abs(pipeline.skew(pipeline.deskew(tilted))) <= 0.2
    assert pipeline.deskew(page) is page  # level already: untouched


def test_red_ink_leaves_no_ghost():
    import numpy as np
    img = np.full((800, 600, 3), (200, 210, 220), np.uint8)  # paper (BGR)
    cv2.line(img, (300, 100), (300, 700), (100, 100, 180), 12)  # a red pen stroke
    gray = pipeline.prepare(img)
    assert gray[:, gray.shape[1] // 2 - 30:gray.shape[1] // 2 + 30].min() > 200


def test_a_note_the_engines_dont_agree_on_is_doubtful():
    a, b, c = "B|-5-7-10-|", "B|-5-7-12-|", "B|-5-1-12-|"
    assert pipeline.doubtful(b, [a, b, c]) == [False, False, False]
    assert pipeline.doubtful(c, [a, b, c]) == [False, True, False]
    assert pipeline.doubtful(a, [a]) == [False, False, False]  # one engine: no say


def test_marked_notes_come_out_as_doubts_where_they_are():
    line = pipeline.mark("B|-5-7-10-|", [False, True, True])
    text, doubts = pipeline.unmark("Verse\n" + line + "\n")
    assert text == "Verse\nB|-5-7-10-|\n"
    assert doubts == [[1, 5, "7"], [1, 7, "10"]]


def test_doubts_point_at_the_notes_engines_disagree_on():
    """Three engines, one misreading a note of the riff: the text keeps
    the majority's note and has no doubts; when two misread it differently,
    the note is doubtful, at its place in the text."""
    riff = [l for l in selftest.RIFF.splitlines() if l]

    def engine(change):
        seen = iter(riff * 2)

        def read(strip, line):
            text = next(seen)
            return text.replace("5h7", change) if "5h7" in text else text
        return read

    agree = pipeline.transcribe(selftest.page_photo(),
                                {"a": engine("5h7"), "b": engine("5h7"), "c": engine("6h7")})
    assert agree.doubts == []
    split = pipeline.transcribe(selftest.page_photo(),
                                {"a": engine("5h7"), "b": engine("6h7"), "c": engine("8h7")})
    assert len(split.doubts) == 1
    line, col, note = split.doubts[0]
    assert note == "5h7" and split.text.splitlines()[line][col:col + 3] == "5h7"


def test_a_pdf_s_doubts_count_the_lines_of_the_pages_before():
    import numpy as np
    first = pipeline.Result("e|-1-|\nB|-2-|\n", doubts=[[0, 3, "1"]])
    second = pipeline.Result("e|-3-|\n", doubts=[[0, 3, "3"]])
    pages = iter([first, second])
    orig_pages, orig_image = pipeline.pdf_pages, pipeline.transcribe_image
    pipeline.pdf_pages = lambda data: [np.zeros(1), np.zeros(1)]
    pipeline.transcribe_image = lambda *a, **k: next(pages)
    try:
        r = pipeline.transcribe_pdf(b"", {})
    finally:
        pipeline.pdf_pages, pipeline.transcribe_image = orig_pages, orig_image
    assert r.text.splitlines()[3] == "e|-3-|"
    assert r.doubts == [[0, 3, "1"], [3, 3, "3"]]
