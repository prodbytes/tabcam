"""From a photographed or scanned tab page to plain-text tab.

The pipeline that read tabs best in the OCR bench:

1. prepare: find the page (photos; scans already are one) and flatten it,
   drop red ink (the red channel, then what's still red becomes paper),
   even out the light, level it (deskew), scale to WIDTH.
2. find_lines: each tab string line is a row of dashes (small, flat ink
   marks at one height); lines a pitch apart make a staff.
3. Each line is cut into a strip and read by several engines (engines.py).
   Whole-page OCR drops dash runs, so reading line by line keeps the
   columns: gaps between the words an engine finds become dashes.
4. vote: per line, the reading closest to the others' (the medoid of the
   fret tokens) wins.
5. page_text: the rest of the page (the staves blanked out) is read whole,
   for the notations around the tab: chord names, lyrics, section names.
   They go between the staves where they are on the page, chord names at
   the tab's columns.
"""
import re
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field, replace

import cv2
import numpy as np
from rapidfuzz.distance import Levenshtein

WIDTH = 2800
MAX_PIXELS = 60_000_000
MIN_DASHES = 10
LABELS = {6: "eBGDAE", 4: "GDAE"}


@dataclass
class Line:
    y0: int
    y1: int
    x0: int
    x1: int
    cy: float
    cols: int  # columns between the bars, from the dash pitch
    cw: float  # one column's width in pixels
    dash_x0: int  # where the first dash starts


@dataclass
class Result:
    text: str  # the tab, staves separated by a blank line; "" when none
    staves: int = 0
    lines: int = 0
    seconds: float = 0.0
    readings: dict = field(default_factory=dict)  # engine -> its lines
    timings: dict = field(default_factory=dict)  # engine -> seconds


class TooLarge(ValueError):
    pass


def decode(data):
    img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("not an image")
    if img.shape[0] * img.shape[1] > MAX_PIXELS:
        raise TooLarge("image too large")
    return img


def _order(pts):
    s, d = pts.sum(1), np.diff(pts, axis=1).ravel()
    return np.float32([pts[s.argmin()], pts[d.argmin()], pts[s.argmax()], pts[d.argmax()]])


def _page(img):
    """The page, flattened, when the photo shows one on a darker background;
    else the whole image (a scan is already the page)."""
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    mask = ((hsv[..., 1] < 60) & (hsv[..., 2] > 120)).astype(np.uint8) * 255
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8))
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return img
    c = max(cnts, key=cv2.contourArea)
    area = cv2.contourArea(c) / (img.shape[0] * img.shape[1])
    if area < 0.2 or area > 0.9:
        return img
    quad = cv2.approxPolyDP(cv2.convexHull(c), 0.02 * cv2.arcLength(c, True), True)
    if len(quad) != 4:
        return img
    tl, tr, br, bl = _order(quad.reshape(-1, 2).astype(np.float32))
    w = int(max(np.linalg.norm(tr - tl), np.linalg.norm(br - bl)))
    h = int(max(np.linalg.norm(bl - tl), np.linalg.norm(br - tr)))
    m = cv2.getPerspectiveTransform(np.float32([tl, tr, br, bl]),
                                    np.float32([[0, 0], [w, 0], [w, h], [0, h]]))
    return cv2.warpPerspective(img, m, (w, h), flags=cv2.INTER_CUBIC)


def skew(gray):
    """The page's tilt in degrees: the angle (within 4 either way) at which
    its rows of ink are sharpest (staff lines and text lines straight
    across)."""
    small = cv2.resize(gray, (700, max(int(gray.shape[0] * 700 / gray.shape[1]), 1)),
                       interpolation=cv2.INTER_AREA)
    ink = (small < 160).astype(np.float32)
    h, w = ink.shape
    best, angle = -1.0, 0.0
    for a in np.arange(-4, 4.01, 0.1):
        m = cv2.getRotationMatrix2D((w / 2, h / 2), a, 1)
        rows = cv2.warpAffine(ink, m, (w, h)).sum(1)
        if rows.var() > best:
            best, angle = rows.var(), float(a)
    return angle


def deskew(gray):
    """[gray] turned level (skew), on white; as is when nearly level."""
    angle = skew(gray)
    if abs(angle) < 0.5:  # turning blurs fine strokes: only when it pays
        return gray
    h, w = gray.shape
    m = cv2.getRotationMatrix2D((w / 2, h / 2), angle, 1)
    return cv2.warpAffine(gray, m, (w, h), flags=cv2.INTER_CUBIC, borderValue=255)


def prepare(img):
    """Grayscale page WIDTH wide: red ink gone, light even."""
    page = _page(img)
    # The light is evened at half width (the kernels are tuned for it), then
    # the page is doubled: small print reads better upscaled.
    half = WIDTH // 2
    scale = half / page.shape[1]
    page = cv2.resize(page, None, fx=scale, fy=scale,
                      interpolation=cv2.INTER_CUBIC if scale > 1 else cv2.INTER_AREA)
    gray = page[..., 2].copy()  # red ink is nearly as bright as paper here
    bg = cv2.GaussianBlur(cv2.dilate(gray, np.ones((21, 21), np.uint8)), (0, 0), 25)
    gray = cv2.normalize(cv2.divide(gray, bg, scale=255), None, 0, 255, cv2.NORM_MINMAX)
    # Nearly: what's left of it is a grey ghost over the notes. Where the ink
    # is red (red well above green and blue, and not dark: black ink under
    # it stays), it becomes paper.
    bgr = page.astype(np.int16)
    red = (bgr[..., 2] - bgr[..., :2].max(2) > 30) & (bgr[..., 2] > 120)
    red = cv2.dilate(red.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    gray[red] = np.maximum(gray[red], np.percentile(gray, 80))
    gray = deskew(gray)
    return cv2.resize(gray, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)


def find_lines(gray):
    ink = (gray < 140).astype(np.uint8)
    _, _, stats, cent = cv2.connectedComponentsWithStats(ink, connectivity=8)
    x, y, w, h = (stats[1:, i] for i in range(4))
    dash = (w >= 2 * h) & (h <= 12) & (w >= 8) & (w <= 60)
    if dash.sum() < MIN_DASHES:
        return []
    ys = np.sort(cent[1:, 1][dash])
    groups, cur = [], [ys[0]]
    for v in ys[1:]:
        if v - cur[-1] > 8:
            groups.append(cur)
            cur = []
        cur.append(v)
    groups.append(cur)
    centres = [float(np.median(g)) for g in groups if len(g) >= MIN_DASHES]
    if not centres:
        return []
    pitch = float(np.median(np.diff(centres))) if len(centres) > 1 else 60.0
    lines = []
    for cy in centres:
        sel = dash & (np.abs(cent[1:, 1] - cy) < 8)
        xs = np.sort(x[sel])
        cw = float(np.median(np.diff(xs))) if len(xs) > 1 else 25.0
        # A tab line's dashes come a column apart; a drawn line broken up by
        # a poor scan or photo gives flat marks too, but not evenly spaced.
        steps = np.diff(xs)
        if ((steps > 0.8 * cw) & (steps < 1.2 * cw)).sum() < MIN_DASHES:
            continue
        x_end = int((x[sel] + w[sel]).max())
        lines.append(Line(
            y0=max(int(cy - 0.5 * pitch), 0), y1=min(int(cy + 0.5 * pitch), gray.shape[0]),
            x0=max(int(xs[0] - 1.2 * pitch), 0), x1=min(x_end + 30, gray.shape[1]),
            cy=cy, cols=int(round((x_end - xs[0]) / cw)), cw=cw, dash_x0=int(xs[0])))
    return lines


def staves(lines):
    """Lines a pitch apart, in groups: one group per staff."""
    if not lines:
        return []
    gaps = np.diff([l.cy for l in lines])
    pitch = float(np.median(gaps)) if len(gaps) else 0
    out = [[lines[0]]]
    for gap, line in zip(gaps, lines[1:]):
        if gap > 1.6 * pitch:
            out.append([])
        out[-1].append(line)
    return out


def align(group):
    """A staff's lines measured alike, so a chord's notes land in one
    column on every line: from the staff's first dash (the median of where
    its lines' dashes start: a line starting with a fret starts its dashes
    late), in its column width (the median), to its last column (the
    most)."""
    x0 = int(np.median([l.dash_x0 for l in group]))
    cw = float(np.median([l.cw for l in group]))
    cols = max(l.cols for l in group)
    return [replace(l, dash_x0=x0, cw=cw, cols=cols) for l in group]


def even(block, width):
    """A staff's tab lines (`e|...|`) ending together: trailing dashes
    trimmed, then every line padded with dashes to [width] columns, or to
    the line whose notes go furthest."""
    parts = [(l[:l.index("|") + 1], l[l.index("|") + 1:].rstrip("|").rstrip("-"))
             for l in block]
    width = max([width] + [len(body) for _, body in parts])
    return [f"{label}{body.ljust(width, '-')}|" for label, body in parts]


def tokens(line):
    """A tab line's musical tokens (15b17, 2s4, x, ...): what's between dashes."""
    body = re.sub(r"^[eBGDAE]?\|?", "", line).strip("|")
    return [t for t in re.split(r"[-|]+", body) if t]


_LABEL = re.compile(r"^\s*([eBGDAE])?\s*[|Il1!\]\[]\s*")


def rebuild(text, label, width):
    """An engine's reading of one line, as a tab line: the label we know
    (or the one read), the bars, and dashes in the gaps and to [width]."""
    rows = [r.rstrip() for r in text.splitlines() if r.strip()]
    line = max(rows, key=len) if rows else ""
    line = re.sub("[‐‑‒–—―−_]", "-", line)
    m = _LABEL.match(line)
    if m:
        label = label or (m.group(1) or "")
        line = line[m.end():]
    line = re.sub(r"[|Il1!\]]\s*$", "", line.strip())
    line = re.sub(r"(?<=[\d\-])[Oo]|[Oo](?=\d)", "0", line)
    line = line.replace(" ", "-")
    line += "-" * max(width - len(line), 0)
    return f"{label}|{line}|"


def note_spans(strip, line):
    """Where a string line's notes are, from the ink itself: [(x0, x1)] in
    page x, left to right. Engines drop and double dashes, so the columns
    they imply drift; the image doesn't. The dashes (flat, filled marks on
    the line), the label and bar before the first dash, the bar after the
    last and specks are left out; the rest is grouped by gaps of most of
    a column (within a number the gaps are narrower, even around a 1)."""
    ink = (strip < 140).astype(np.uint8)
    n, _, st, cen = cv2.connectedComponentsWithStats(ink, connectivity=8)
    cy, half = line.cy - line.y0, (line.y1 - line.y0) / 2
    spans = []
    for i in range(1, n):
        x, y, w, h, area = (int(v) for v in st[i])
        x += line.x0
        if max(w, h) < 0.4 * line.cw or x + w <= line.dash_x0 - 0.3 * line.cw or x >= line.x1 - 32:
            continue
        if w >= 1.8 * h and h <= 0.35 * line.cw and w <= 1.2 * line.cw and abs(cen[i][1] - cy) < 8:
            continue  # a dash
        if abs(y + h / 2 - cy) > 0.6 * half:
            continue  # a neighbour line's ink
        spans.append([x, x + w])
    spans.sort()
    out = []
    for s in spans:
        if out and s[0] - out[-1][1] < 0.9 * line.cw:
            out[-1][1] = max(out[-1][1], s[1])
        else:
            out.append(s)
    return [tuple(s) for s in out]


def place_tokens(reading, spans, line, width):
    """[reading] (a rebuilt tab line) with its tokens moved to the columns
    the ink says ([spans], note_spans), when there are as many of each;
    else as read."""
    toks = tokens(reading)
    if not toks or len(toks) != len(spans):
        return reading
    body = ""
    for tok, (x0, _) in zip(toks, spans):
        col = max(round((x0 - line.dash_x0) / line.cw), len(body) + (1 if body else 0))
        body = body.ljust(col, "-") + tok
    return f"{reading[:reading.index('|')]}|{body.ljust(width, '-')}|"


def vote(readings):
    """The reading closest to all the others (fewest token edits); ties go
    to the first engine."""
    toks = [tokens(r) for r in readings]
    cost = [sum(Levenshtein.distance(t, u) for u in toks) for t in toks]
    return readings[cost.index(min(cost))]


_URL = re.compile(r"https?://|www\.|\.(com|net|org|br)\b"
                  r"|camscanner|scanned with|digitalizado com|escaneado con", re.I)
_PAGE_NUMBER = re.compile(r"^(page\s*)?\d+(\s*(/|of)\s*\d+)?$", re.I)
_ODD = re.compile(r"[^A-Za-z0-9\u00c0-\u00ff\s#/()'\u2019,.!?:;&+\-]")


def is_notation(text):
    """A line of text worth keeping beside the tab (chord names, lyrics, a
    section's name), not noise: a web address, a page number, a garbled tab
    line, stray marks. As the app's isNotation (tab_layout.dart)."""
    text = text.strip()
    if not text or _URL.search(text) or _PAGE_NUMBER.match(text):
        return False
    if not re.search(r"[A-Za-z\u00c0-\u00ff]", text):
        return False
    if text.count("-") >= len(text) * 0.3:
        return False
    return len(_ODD.findall(text)) <= len(text) * 0.2


def place_words(words):
    """[(text, column)] as one line, each word at its column, at least a
    space apart."""
    out = ""
    for text, col in sorted(words, key=lambda w: w[1]):
        gap = col - len(out)
        out += " " * max(gap, 1 if out else 0) + text
    return out


def text_lines(words, groups):
    """[words]: (text, x0, y0, x1, y1, score) read off the staves. Their
    lines, (y, text), each word at the column of the nearest staff it lines
    up with (its first dash is column 2, after `e|`)."""
    words = [w for w in words if w[5] >= 0.5 and w[0].strip()]
    if not words:
        return []
    height = float(np.median([w[4] - w[2] for w in words]))
    rows = []
    for w in sorted(words, key=lambda w: (w[2] + w[4]) / 2):
        cy = (w[2] + w[4]) / 2
        if rows and abs(cy - rows[-1][0]) <= 0.6 * height:
            row = rows[-1]
            row[1].append(w)
            row[0] = float(np.mean([(v[2] + v[4]) / 2 for v in row[1]]))
        else:
            rows.append([cy, [w]])
    out = []
    for cy, row in rows:
        ref = min((g[0] for g in groups), key=lambda l: abs(l.cy - cy))
        text = place_words([(w[0].strip(), max(0, round((w[1] - ref.dash_x0) / ref.cw) + 2))
                            for w in row])
        if is_notation(text):
            out.append((cy, text.rstrip()))
    return out


def page_text(gray, groups, read_page, full=False, pad=None):
    """The page's text off the staves, as text_lines. The staves are
    blanked out ([pad] around them: a quarter of a line's band, unless
    given) and the page read at half size (big enough for print), or at
    full size ([full]: handwriting)."""
    page = gray.copy()
    for g in groups:
        p = pad if pad is not None else (g[0].y1 - g[0].y0) // 4
        page[max(0, int(min(l.y0 for l in g) - p)):int(max(l.y1 for l in g) + p), :] = 255
    if full:
        # Handwriting: each strip between staves read on its own, full
        # size (a mostly blank page throws the detector off).
        words, top = [], 0
        bands = sorted((int(min(l.y0 for l in g)), int(max(l.y1 for l in g))) for g in groups)
        for y0, y1 in bands + [(page.shape[0], page.shape[0])]:
            if y0 - top > 20:
                words += [(t, a, b + top, c, d + top, sc)
                          for t, a, b, c, d, sc in read_page(page[top:y0])]
            top = max(top, y1)
        # And the whole page: each way finds words the other misses.
        words = _merge_words(words, read_page(page))
        return text_lines(words, groups)
    half = cv2.resize(page, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
    words = [(t, x0 * 2, y0 * 2, x1 * 2, y1 * 2, score)
             for t, x0, y0, x1, y1, score in read_page(half)]
    return text_lines(words, groups)


def _area(w):
    return (w[3] - w[1]) * (w[4] - w[2])


def _merge_words(a, b):
    """Words read two ways: all of them; of two that overlap, the one much
    bigger (more of the line), else the surer."""
    def overlap(u, v):
        ix = max(0, min(u[3], v[3]) - max(u[1], v[1]))
        iy = max(0, min(u[4], v[4]) - max(u[2], v[2]))
        smaller = min((u[3] - u[1]) * (u[4] - u[2]), (v[3] - v[1]) * (v[4] - v[2])) or 1
        return ix * iy / smaller
    out = list(a)
    for w in b:
        clash = [i for i, o in enumerate(out) if overlap(w, o) > 0.3]
        if not clash:
            out.append(w)
        elif all(_area(w) > 1.5 * _area(out[i]) or w[5] > out[i][5] for i in clash):
            out = [o for i, o in enumerate(out) if i not in clash] + [w]
    return out


def join(pieces):
    """[(kind, text)], top to bottom, kind "staff" or "text", as one text: a
    blank line between staves and after a staff, none before a staff
    (chord names and labels sit right above it). As the app's."""
    out = ""
    for i, (kind, text) in enumerate(pieces):
        if i:
            out += "\n\n" if pieces[i - 1][0] == "staff" else "\n"
        out += text
    return out


MAX_PDF_PAGES = 10
PDF_RENDER_WIDTH = 2000  # pixels; prepare() scales to WIDTH from there


def pdf_pages(data, max_pages=MAX_PDF_PAGES):
    """A PDF's pages as images (BGR), as if each had been photographed:
    rendered on white, PDF_RENDER_WIDTH wide. At most [max_pages]."""
    import pypdfium2 as pdfium
    try:
        pdf = pdfium.PdfDocument(data)
    except pdfium.PdfiumError as e:
        raise ValueError(f"not a PDF: {e}") from e
    try:
        pages = []
        for i in range(min(len(pdf), max_pages)):
            page = pdf[i]
            scale = PDF_RENDER_WIDTH / max(page.get_width(), 1)
            if page.get_height() * scale * PDF_RENDER_WIDTH > MAX_PIXELS:
                scale = (MAX_PIXELS / (page.get_width() * page.get_height())) ** 0.5
            rgb = np.asarray(page.render(scale=scale, fill_color=(255, 255, 255, 255)).to_pil()
                             .convert("RGB"))
            pages.append(rgb[..., ::-1].copy())
        return pages
    finally:
        pdf.close()


def transcribe_pdf(data, engines, read_page=None, vision=None, read_crop=None):
    """A PDF's tab: each page read as a photo of it would be (transcribe),
    the pages' tabs joined by a blank line."""
    start = time.monotonic()
    results = [transcribe_image(img, engines, read_page, vision, read_crop)
               for img in pdf_pages(data)]
    found = [r for r in results if r.text]
    timings = {}
    for r in results:
        for k, v in r.timings.items():
            timings[k] = round(timings.get(k, 0) + v, 2)
    return Result("\n".join(r.text for r in found), staves=sum(r.staves for r in results),
                  lines=sum(r.lines for r in results), seconds=round(time.monotonic() - start, 2),
                  timings=timings)


def transcribe(data, engines, read_page=None, vision=None, read_crop=None):
    """[data]: an image file's bytes. [engines]: name -> read(strip, line),
    each returning the line's text as read (engines.py). [read_page]: reads
    a whole (grayscale) page into words with their boxes, for the
    notations around the tab; None leaves them out. [vision]: reads a page
    the engines find no tab lines on (a handwritten tab, drawn staff
    lines), image -> its tab text ("" for none); None: no tab."""
    return transcribe_image(decode(data), engines, read_page, vision, read_crop)


def _drawn(gray, read_crop, read_page):
    """The tab on drawn staff lines (staves.py), with the notations off
    them, or None when there's none."""
    from . import staves
    blocks, found = staves.read(gray, read_crop)
    if not blocks:
        return None
    pieces = [(y, "staff", t) for y, t in blocks]
    if read_page:
        # Stand-in lines, for blanking the staves and placing chord names.
        groups = []
        for ys, x0, x1 in found:
            gap = (ys[-1] - ys[0]) / (len(ys) - 1)
            groups.append([Line(int(y - gap / 2), int(y + gap / 2), x0, x1, y,
                                int((x1 - x0) / gap), gap, x0) for y in ys])
        # Full size: handwriting reads better; the staff itself only blanked.
        pieces += [(y, "text", t) for y, t in page_text(gray, groups, read_page, full=True,
                                                      pad=0)]
    pieces.sort(key=lambda p: p[0])
    lines = sum(len(f[0]) for f in found)
    return Result(join([(k, t) for _, k, t in pieces]) + "\n", staves=len(blocks), lines=lines)


def transcribe_image(img, engines, read_page=None, vision=None, read_crop=None):
    """transcribe, for an image already decoded (BGR)."""
    start = time.monotonic()
    gray = prepare(img)
    # Fewer than four lines isn't a staff (as in the app): stray rows of
    # dashes, or drawn lines in pieces.
    groups = [align(g) for g in staves(find_lines(gray)) if len(g) >= 4]
    jobs = [(line, gray[line.y0:line.y1, line.x0:line.x1]) for g in groups for line in g]
    if not jobs and read_crop is not None:
        # No dash lines: frets on drawn staff lines (handwritten, typeset)?
        t = time.monotonic()
        drawn = _drawn(gray, read_crop, read_page)
        if drawn is not None:
            drawn.timings["drawn"] = round(time.monotonic() - t, 2)
            drawn.seconds = round(time.monotonic() - start, 2)
            return drawn
    if not jobs:
        if vision is None:
            return Result("", seconds=time.monotonic() - start)
        # Nothing the engines read: Claude's, where it's switched on.
        t = time.monotonic()
        text = vision(img)
        staves_read = len([b for b in text.split("\n\n") if "|" in b])
        return Result(text, staves=staves_read,
                      seconds=round(time.monotonic() - start, 2),
                      timings={"claude": round(time.monotonic() - t, 2)})

    def run(read):
        t = time.monotonic()
        out = [read(strip, line) for line, strip in jobs]
        return out, round(time.monotonic() - t, 2)

    with ThreadPoolExecutor(max_workers=len(engines)) as pool:
        ran = dict(zip(engines, pool.map(run, engines.values())))
    raw = {name: out for name, (out, _) in ran.items()}
    timings = {name: t for name, (_, t) in ran.items()}

    blocks, readings, i = [], {name: [] for name in engines}, 0
    for g in groups:
        labels = LABELS.get(len(g), "")
        width = max(l.cols for l in g)
        block = []
        for j, _ in enumerate(g):
            label = labels[j] if labels else ""
            spans = note_spans(jobs[i][1], jobs[i][0])
            options = [place_tokens(rebuild(raw[name][i], label, width), spans, jobs[i][0], width)
                       for name in engines]
            for name, o in zip(engines, options):
                readings[name].append(o)
            block.append(vote(options))
            i += 1
        blocks.append((g[0].y0, "staff", "\n".join(even(block, width))))
    if read_page:
        t = time.monotonic()
        blocks += [(y, "text", text) for y, text in page_text(gray, groups, read_page)]
        timings["page"] = round(time.monotonic() - t, 2)
    blocks.sort(key=lambda b: b[0])
    text = join([(kind, text) for _, kind, text in blocks])
    return Result(text + "\n", staves=len(groups), lines=len(jobs),
                  seconds=round(time.monotonic() - start, 2), readings=readings,
                  timings=timings)
