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
    sys.exit(0 if s >= args.min and title >= 0.8 else 1)


if __name__ == "__main__":
    main()
