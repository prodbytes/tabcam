"""The OCR engines the pipeline votes between, each reading one line strip.

Tesseract (single line, tab characters only), PaddleOCR and RapidOCR: the
combination that read tabs best in the OCR bench. Models load once per
container (a Lambda cold start) and are reused.

Each engine returns the line as text. Box engines place each word at the
column its x position implies, from where the line's dashes start, so the
gaps (dashes the engines drop) keep their width.
"""
import os
from functools import cache

import cv2

from .pipeline import _LABEL

# No string names: they come from the line's place in its staff, and with
# 'e' allowed Tesseract 5 reads runs of dashes as e's.
TAB_CHARS = "|-~0123456789bprshx/()"


def place(boxes, line):
    """[boxes]: (text, x in the strip). The line as text, gaps as spaces."""
    out = ""
    for text, bx in sorted(boxes, key=lambda b: b[1]):
        x = bx + line.x0
        if x < line.dash_x0 - line.cw / 2:  # the string label and bar
            m = _LABEL.match(text)
            text = text[m.end():] if m else text.lstrip("|")
            x = line.dash_x0
        col = max(0, round((x - line.dash_x0) / line.cw))
        if col > len(out):
            out += " " * (col - len(out))
        elif out and not out.endswith(" "):
            out += " "
        out += text
    return "|" + out


def _padded(strip):
    """The strip in a white margin, as BGR: PaddleOCR's detector misses text
    that fills the image edge to edge. Returns the image and the x offset."""
    pad = strip.shape[0]
    img = cv2.copyMakeBorder(strip, pad, pad, pad, pad, cv2.BORDER_CONSTANT, value=255)
    return cv2.cvtColor(img, cv2.COLOR_GRAY2BGR), pad


def tesseract(strip, line):
    import pytesseract
    cfg = f"--psm 7 -c preserve_interword_spaces=1 -c tessedit_char_whitelist={TAB_CHARS}"
    return pytesseract.image_to_string(strip, config=cfg)


@cache
def _paddle():
    from paddleocr import PaddleOCR
    # oneDNN off: on x86 Linux, Paddle 3.3's new executor fails with it
    # ("ConvertPirAttribute2RuntimeAttribute not support").
    return PaddleOCR(lang="en", use_doc_orientation_classify=False,
                     use_doc_unwarping=False, use_textline_orientation=False,
                     enable_mkldnn=False)


def paddle(strip, line):
    img, pad = _padded(strip)
    res = _paddle().predict(img)[0]
    return place([(t, b[0] - pad) for t, b in zip(res["rec_texts"], res["rec_boxes"])], line)


@cache
def _rapid():
    from rapidocr_onnxruntime import RapidOCR
    return RapidOCR()


def rapid(strip, line):
    # Unlike PaddleOCR's, RapidOCR's detector reads these strips better bare.
    found, _ = _rapid()(cv2.cvtColor(strip, cv2.COLOR_GRAY2BGR))
    return place([(t, min(p[0] for p in q)) for q, t, _ in found or []], line)


def read_crop(ink):
    """One number on drawn staff lines ([ink]: 1 = ink, the number alone),
    read by RapidOCR's recognizer (no detection: the crop is the text)."""
    padded = cv2.copyMakeBorder((255 - ink * 255).astype("uint8"), 12, 12, 12, 12,
                                cv2.BORDER_CONSTANT, value=255)
    bgr = cv2.cvtColor(padded, cv2.COLOR_GRAY2BGR)
    found, _ = _rapid()(bgr, use_det=False, use_cls=False, use_rec=True)
    text = found[0][0] if found else ""
    from .staves import fret
    if fret(text) is None:
        # A second opinion: PaddleOCR's, on the same number.
        res = _paddle().predict(bgr)[0]
        other = "".join(res["rec_texts"])
        if fret(other) is not None:
            return other
    return text


def read_page(gray):
    """A whole grayscale page's text, for the notations around the tab:
    (text, x0, y0, x1, y1, score) per box RapidOCR finds."""
    found, _ = _rapid()(cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR))
    return [(t, min(p[0] for p in q), min(p[1] for p in q),
             max(p[0] for p in q), max(p[1] for p in q), float(s))
            for q, t, s in found or []]


def default():
    """The engines, in tie-breaking order (the best alone first)."""
    names = os.environ.get("LOCR_ENGINES", "tesseract,paddle,rapid").split(",")
    every = {"tesseract": tesseract, "paddle": paddle, "rapid": rapid}
    return {n: every[n] for n in names}


def load():
    """Loads the models now (at cold start, or at image build to fetch them)."""
    _paddle()
    _rapid()
