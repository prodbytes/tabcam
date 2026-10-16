"""Tabs on drawn staff lines: handwritten, or typeset (books, Guitar Pro
printouts), where the frets sit on the lines and there are no dashes.

1. find_staves: long horizontal strokes (gaps in them bridged: a scan's
   thin lines come dotted) are staff lines (a line slightly skewed shows
   as rows a few pixels apart: one line); lines about a gap apart, six of
   them (four for bass, five when the page cuts the last), are a staff.
2. erase_lines: the lines' pixels go, but not where a pen stroke crosses
   them (ink just above and below), so the numbers stay whole.
3. numbers: the ink left near each staff (handwritten frets often sit
   above their line, so the band reaches further up), in marks
   (connected components) of a digit's size; pieces of a digit the line
   cut through (a 3's middle) are one mark again; flat strokes (slurs,
   braces' tails) are left out. Marks side by side at about the same
   height are one number (10, 12, (9)), on the string nearest its middle.
   Marks at the staff's very start (handwritten string numbers, the TAB
   clef) are left out.
4. Each number's crop (made a little bolder when the pen is fine) is read
   by a recognizer (read_crop: PaddleOCR's, then RapidOCR's), and kept
   if, with the usual misreadings fixed (S 5, g 9, o 0, l 1, B 8, C 6,
   ...), it's a fret: one or two digits, maybe in brackets, or x.
5. layout: numbers about the same x are one column (a chord); columns go
   left to right with dashes before each, by the distance from the last,
   as the app lays out a typeset tab (tab_layout.dart typesetTab).
"""
import re

import cv2
import numpy as np

LABELS = {6: "eBGDAE", 5: "eBGDA", 4: "GDAE"}
# OCR's usual misreadings of handwritten digits.
FIX = str.maketrans({"S": "5", "s": "5", "$": "5", "g": "9", "q": "9", "o": "0", "O": "0", "D": "0",
                     "l": "1", "I": "1", "i": "1", "|": "1", "!": "1", "Z": "2", "z": "2",
                     "B": "8", "&": "8", "b": "6", "G": "6", "C": "6", "A": "4", "T": "7", "?": "7",
                     "（": "(", "）": ")", "[": "(", "]": ")", "X": "x"})
FRET = re.compile(r"^(\(?\d{1,2}\)?|x)$")


def fret(text):
    """[text] as a fret, misreadings fixed; None when it isn't one."""
    t = re.sub(r"[\s.,:;'`\"_-]", "", (text or "").translate(FIX))
    return t if FRET.match(t) else None


MAX_FRET = 24


def frets(text, x0, x1):
    """[(x, fret)] in what was read from a crop from [x0] to [x1]: one
    fret, or several written close together ("5 7-9"), each at its share
    of the crop's width. A "number" past the last fret (55, 97) is two
    frets side by side."""
    parts = [p for p in re.split(r"[\s\-_~/]+", (text or "").translate(FIX)) if p]
    # Frets written together around a bracketed one: "5(6)5".
    parts = [q for p in parts for q in (re.findall(r"\(\d{1,2}\)|[^()]+", p) or [p])]
    out = []
    for p in parts:
        f = fret(p)
        if f is None:
            continue
        digits = f.strip("()")
        if digits.isdigit() and len(digits) == 2 and int(digits) > MAX_FRET:
            out += [digits[0], digits[1]]
        else:
            out.append(f)
    if not out:
        return []
    step = (x1 - x0) / len(out)
    return [(x0 + step * (i + 0.5), f) for i, f in enumerate(out)]


def find_staves(gray):
    """[(ys of the lines, x0, x1)] of each staff, top to bottom."""
    h, w = gray.shape
    ink = (gray < 160).astype(np.uint8)
    # A scan's thin lines come broken up (dotted, faded): the gaps are
    # bridged before the long strokes are kept, and only ink is a line.
    bridged = cv2.morphologyEx(ink, cv2.MORPH_CLOSE,
                               cv2.getStructuringElement(cv2.MORPH_RECT, (15, 1)))
    mask = cv2.morphologyEx(bridged, cv2.MORPH_OPEN,
                            cv2.getStructuringElement(cv2.MORPH_RECT, (max(w // 10, 20), 1))) & ink
    rows = np.where(mask.sum(1) > 0.15 * w)[0]
    runs = []
    for y in rows:
        if runs and y - runs[-1][-1] <= 3:
            runs[-1].append(int(y))
        else:
            runs.append([int(y)])
    ys = [sum(r) / len(r) for r in runs]
    if len(ys) < 4:
        return [], mask
    # Rows closer than a third of the usual gap are one (skewed) line.
    gaps = np.diff(ys)
    usual = float(np.median(gaps[gaps > 15])) if (gaps > 15).any() else 0
    lines = []
    for y in ys:
        if lines and y - lines[-1][-1] < usual / 3:
            lines[-1].append(y)
        else:
            lines.append([y])
    ys = [sum(l) / len(l) for l in lines]
    gaps = np.diff(ys)
    gap = float(np.median(gaps)) if len(gaps) else 0
    staves = []
    for y in ys:
        if staves and abs(y - staves[-1][-1] - gap) < gap * 0.3 and len(staves[-1]) < 6:
            staves[-1].append(y)
        else:
            staves.append([y])
    out = []
    for s in staves:
        if len(s) not in LABELS:
            continue
        band = mask[int(s[0]) - 2:int(s[-1]) + 3]
        xs = np.where(band.any(0))[0]
        out.append((s, int(xs.min()), int(xs.max())))
    return out, mask


def erase_lines(gray, mask):
    """The ink without the staff lines, but with the strokes crossing them."""
    ink = (gray < 160).astype(np.uint8)
    reach = 4
    above = np.zeros_like(ink); above[reach:] = ink[:-reach]
    below = np.zeros_like(ink); below[:-reach] = ink[reach:]
    crossing = (above > 0) & (below > 0)
    lines = cv2.dilate(mask, np.ones((3, 1), np.uint8)) > 0
    out = ink.copy()
    out[lines & ~crossing] = 0
    return cv2.morphologyEx(out, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))


def numbers(ink, staff):
    """[(string index, x0, x1, crop)] of the numbers on [staff]."""
    ys, x0, x1 = staff
    gap = (ys[-1] - ys[0]) / (len(ys) - 1)
    # Handwritten frets often sit above their line, not on it: the band
    # reaches higher above the top line, so they're whole, than below the
    # bottom one (where the next staff's top frets are).
    top, bottom = int(max(ys[0] - gap * 1.2, 0)), int(ys[-1] + gap * 0.8)
    band = ink[top:bottom]
    n, _, stats, _ = cv2.connectedComponentsWithStats(band, connectivity=8)
    # A line through a digit's horizontal stroke (a 3's middle, a 5's top)
    # takes the stroke with it, leaving the digit in pieces one above the
    # other: they're one mark again.
    parts = sorted([int(v) for v in stats[i][:4]] for i in range(1, n) if stats[i][4] >= gap * 0.3)
    pieces = []
    for x, y, cw, ch in parts:
        box = [x, y, x + cw, y + ch]
        for p in pieces:
            over = min(p[2], box[2]) - max(p[0], box[0])
            apart = max(p[1], box[1]) - min(p[3], box[3])
            small = max(p[3] - p[1], box[3] - box[1]) < gap * 0.6  # neither a digit
            if small and over > 0.5 * min(p[2] - p[0], box[2] - box[0]) and apart < gap * 0.25:
                p[:] = [min(p[0], box[0]), min(p[1], box[1]), max(p[2], box[2]), max(p[3], box[3])]
                break
        else:
            pieces.append(box)
    marks = []
    for x0_, y0_, x1_, y1_ in pieces:
        x, y, cw, ch = x0_, y0_, x1_ - x0_, y1_ - y0_
        area = int(band[y:y1_, x:x1_].sum())
        if ch < gap * 0.3 or ch > gap * 1.6 or cw > gap * 2.5 or area < gap * 0.6:
            continue
        if x + cw / 2 < x0 + gap * 1.2:  # string numbers, the clef
            continue
        if cw > 1.6 * ch and ch < gap * 0.6:  # a flat stroke: a slur, a brace's tail
            continue
        marks.append([x, y, x + cw, y + ch])
    marks.sort()
    groups = []
    for m in marks:
        g = groups[-1] if groups else None
        if g:
            gy = (min(v[1] for v in g) + max(v[3] for v in g)) / 2
            near = m[0] - max(v[2] for v in g) < gap * 0.4
            level = abs((m[1] + m[3]) / 2 - gy) < gap * 0.45
            if near and level:
                g.append(m)
                continue
        groups.append([m])
    out = []
    for g in groups:
        gx0, gy0 = min(v[0] for v in g), min(v[1] for v in g)
        gx1, gy1 = max(v[2] for v in g), max(v[3] for v in g)
        cy = (gy0 + gy1) / 2 + top
        string = int(np.argmin([abs(cy - ly) for ly in ys]))
        out.append((string, gx0, gx1, band[gy0:gy1, gx0:gx1]))
    # Left to right; a chord's notes top to bottom.
    out.sort(key=lambda n: (round(n[1] / (gap * 0.5)), n[0]))
    return out


def layout(n_strings, notes, unit):
    """[(string, x, fret, doubtful)] as one staff's text lines (typesetTab's
    way), doubtful frets wrapped in pipeline.OPEN and CLOSE."""
    from .pipeline import OPEN, CLOSE
    notes = sorted(notes, key=lambda n: n[1])
    columns = []
    for n in notes:
        if columns and n[1] - columns[-1][0][1] < unit * 0.5:
            columns[-1].append(n)
        else:
            columns.append([n])
    rows = ["-"] * n_strings
    last = None
    for col in columns:
        x = col[0][1]
        width = max(len(n[2]) for n in col)
        spacing = 1 if last is None else int(min(max(round((x - last) / unit), 1), 8))
        last = x
        cells = ["-" * width] * n_strings
        for s, _, f, doubt in col:
            cells[s] = (f"{OPEN}{f}{CLOSE}" if doubt else f) + "-" * (width - len(f))
        rows = [r + "-" * spacing + c for r, c in zip(rows, cells)]
    labels = LABELS.get(n_strings, " " * n_strings)
    return [f"{labels[i]}|{rows[i]}--|" for i in range(n_strings)]


def stroke(marks, found):
    """The pen's stroke width on the page, in line gaps: twice the mean
    distance from ink to paper, the median over the numbers ([marks], per
    staff of [found])."""
    widths = []
    for nums, (ys, _, _) in zip(marks, found):
        gap = (ys[-1] - ys[0]) / (len(ys) - 1)
        for *_, crop in nums:
            d = cv2.distanceTransform(crop.astype(np.uint8), cv2.DIST_L2, 3)
            if (d > 0).any():
                widths.append(2 * d[d > 0].mean() / gap)
    return float(np.median(widths)) if widths else 1.0


def read(gray, read_crop):
    """The tab on [gray]'s drawn staves: (blocks [(top y, staff text)],
    staves) — blocks empty when no number is read. [read_crop]: a number's
    ink crop (1 = ink) -> its text, or (text, sure): an unsure read's frets
    are doubtful."""
    found, mask = find_staves(gray)
    if not found:
        return [], []
    ink = erase_lines(gray, mask)
    marks = [numbers(ink, staff) for staff in found]
    thin = stroke(marks, found) < 0.1
    blocks = []
    for staff, nums in zip(found, marks):
        ys = staff[0]
        gap = (ys[-1] - ys[0]) / (len(ys) - 1)
        notes = []
        for string, x0, x1, crop in nums:
            if thin:  # a fine pen's digits read better a little bolder
                crop = cv2.dilate(crop, np.ones((2, 2), np.uint8))
            said = read_crop(crop)
            text, sure = said if isinstance(said, tuple) else (said, True)
            for x, f in frets(text, x0, x1):
                notes.append((string, x, f, not sure))
        if notes:
            blocks.append((ys[0], "\n".join(layout(len(ys), notes, gap))))
    return blocks, found
