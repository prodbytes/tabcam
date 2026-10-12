"""Renders a made-up riff as a photographed page and reads it back.

    python -m locr.selftest [--engines tesseract,paddle,rapid] [--min 0.8]

Run at image build (it also fetches and loads the models) and by
scripts/test-image.sh. Exits 1 when fewer than --min of the riff's tokens
come back. The riff is invented: tests never use published songs' tabs.
"""
import argparse
import os
import re
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from rapidfuzz.distance import Levenshtein

RIFF = """\
e|-----------0-------3-----------0-----|
B|-------1-------1-------1-----1-------|
G|---2-------------2-------2b4r2-------|
D|-2-----------------------------------|
A|-------------------------------------|
E|-------------------------------------|

e|--------------------------12~~-------|
B|-----5h7-7p5----------10---------x---|
G|---7----------9b11---------------x---|
D|-------------------------------------|
A|-------------------------------------|
E|-0-----------------------------------|
"""

# A monospace font like printed tabs' (Courier-like); DejaVu Sans Mono's
# thin dashes read worse than real printouts do.
FONTS = ("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
         "/System/Library/Fonts/Menlo.ttc", "/Library/Fonts/Courier New.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")


def page_photo(text=RIFF):
    """The riff printed on a page, photographed: on a wooden-ish background,
    slightly turned, with a red pen stroke across it."""
    font = ImageFont.truetype(next(f for f in FONTS if os.path.exists(f)), 22)
    page = Image.new("RGB", (900, 1200), "white")
    draw = ImageDraw.Draw(page)
    draw.text((60, 50), TITLE, fill="black", font=font)
    for i, line in enumerate(text.splitlines()):
        draw.text((60, 120 + i * 34), line, fill="black", font=font)
    draw.line([(480, 100), (500, 700)], fill=(200, 20, 60), width=6)
    page = np.array(page)[..., ::-1]
    bg = np.full((1500, 1200, 3), (60, 100, 150), np.uint8)
    m = cv2.getRotationMatrix2D((450, 600), 2.0, 1.0)
    m[:, 2] += (150, 150)
    cv2.warpAffine(page, m, (1200, 1500), dst=bg, borderMode=cv2.BORDER_TRANSPARENT)
    ok, jpg = cv2.imencode(".jpg", bg, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return jpg.tobytes()


TITLE = "Made-up riff for tests"


def _tab(text):
    return [l for l in text.splitlines() if re.match(r"^[eBGDAE]?\|", l)]


# A made-up riff for drawn staff lines: frets only (no dashes are drawn).
DRAWN_RIFF = """\
e|-----0-------3-------0-----|
B|---1-------1-------1-----1-|
G|-2-------2-------2---------|
D|---------------------------|
A|-------3---------------3---|
E|-3-------------3-----------|

e|---------------12----------|
B|-----5---7---10-----8------|
G|---7---9------------7------|
D|-5-----------------------x-|
A|---------------------------|
E|---------------------------|
"""


def drawn_page(text=DRAWN_RIFF):
    """[text]'s frets set on drawn staff lines (a book's or Guitar Pro's
    tab), photographed as page_photo is."""
    font = ImageFont.truetype(next(f for f in FONTS if os.path.exists(f)), 26)
    page = Image.new("RGB", (900, 1200), "white")
    draw = ImageDraw.Draw(page)
    draw.text((60, 50), TITLE, fill="black", font=font)
    staves = [b.splitlines() for b in text.strip().split("\n\n")]
    col = 22  # pixels per column of the text
    for si, staff in enumerate(staves):
        top = 160 + si * 260
        for li, line in enumerate(staff):
            y = top + li * 30
            draw.line([(60, y), (60 + col * (len(line) - 1), y)], fill="black", width=2)
            body = line[2:]
            for m in re.finditer(r"[0-9x]+", body):
                x = 60 + col * (m.start() + 2)
                w = draw.textlength(m.group(), font=font)
                draw.rectangle([x - 3, y - 13, x + w + 3, y + 13], fill="white")
                draw.text((x, y - 15), m.group(), fill="black", font=font)
    page = np.array(page)[..., ::-1]
    ok, jpg = cv2.imencode(".jpg", page, [cv2.IMWRITE_JPEG_QUALITY, 90])
    return jpg.tobytes()


def score(expected, got):
    """The share of the riff's notes read right, on the tab lines only."""
    from .pipeline import tokens
    want = [t for l in _tab(expected) for t in tokens(l)]
    have = [t for l in _tab(got) for t in tokens(l)]
    return 1 - Levenshtein.distance(want, have) / len(want)


def main():
    from . import engines, pipeline
    ap = argparse.ArgumentParser()
    ap.add_argument("--engines", default=None)
    ap.add_argument("--min", type=float, default=0.8)
    args = ap.parse_args()
    if args.engines:
        os.environ["LOCR_ENGINES"] = args.engines
    r = pipeline.transcribe(page_photo(), engines.default(), read_page=engines.read_page)
    s = score(RIFF, r.text)
    # The page's title, read off the staves, comes first.
    first = r.text.splitlines()[0] if r.text else ""
    title = Levenshtein.normalized_similarity(first.strip().lower(), TITLE.lower())
    print(r.text)
    print(f"staves={r.staves} lines={r.lines} seconds={r.seconds} notes={s:.1%} "
          f"title={title:.0%} timings={r.timings}")
    for name, lines in r.readings.items():
        print(f"  {name}: notes={score(RIFF, chr(10).join(lines)):.1%}")
    # The same page in a PDF (a scanned document) reads the same.
    from PIL import Image
    import io
    jpg = cv2.imdecode(np.frombuffer(page_photo(), np.uint8), cv2.IMREAD_COLOR)
    pdf = io.BytesIO()
    Image.fromarray(jpg[..., ::-1]).save(pdf, format="PDF", resolution=150)
    p = pipeline.transcribe_pdf(pdf.getvalue(), engines.default(), read_page=engines.read_page)
    pdf_score = score(RIFF, p.text)
    print(f"pdf: notes={pdf_score:.1%} seconds={p.seconds}")
    # Frets on drawn staff lines (no dashes): the drawn-staves reading.
    d = pipeline.transcribe(drawn_page(), engines.default(), read_page=engines.read_page,
                            read_crop=engines.read_crop)
    drawn_score = score(DRAWN_RIFF, d.text)
    print(d.text)
    print(f"drawn: notes={drawn_score:.1%} staves={d.staves} seconds={d.seconds}")
    sys.exit(0 if s >= args.min and title >= 0.8 and pdf_score >= args.min
             and drawn_score >= args.min else 1)


if __name__ == "__main__":
    main()
