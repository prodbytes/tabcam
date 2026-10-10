"""From a photographed or scanned tab page to plain-text tab.

The pipeline that read tabs best in the OCR bench:

1. prepare: find the page (photos; scans already are one) and flatten it,
   drop red ink (the red channel), even out the light, scale to WIDTH.
2. find_lines: each tab string line is a row of dashes (small, flat ink
   marks at one height); lines a pitch apart make a staff.
3. Each line is cut into a strip and read by several engines (engines.py).
   Whole-page OCR drops dash runs, so reading line by line keeps the
   columns: gaps between the words an engine finds become dashes.
4. vote: per line, the reading closest to the others' (the medoid of the
   fret tokens) wins.
"""
import re
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field

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


def prepare(img):
    """Grayscale page WIDTH wide: red ink gone, light even."""
    page = _page(img)
    # The light is evened at half width (the kernels are tuned for it), then
    # the page is doubled: small print reads better upscaled.
    half = WIDTH // 2
    scale = half / page.shape[1]
    page = cv2.resize(page, None, fx=scale, fy=scale,
                      interpolation=cv2.INTER_CUBIC if scale > 1 else cv2.INTER_AREA)
    gray = page[..., 2].copy()  # red ink is as bright as paper here
    bg = cv2.GaussianBlur(cv2.dilate(gray, np.ones((21, 21), np.uint8)), (0, 0), 25)
    gray = cv2.normalize(cv2.divide(gray, bg, scale=255), None, 0, 255, cv2.NORM_MINMAX)
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


def vote(readings):
    """The reading closest to all the others (fewest token edits); ties go
    to the first engine."""
    toks = [tokens(r) for r in readings]
    cost = [sum(Levenshtein.distance(t, u) for u in toks) for t in toks]
    return readings[cost.index(min(cost))]


def transcribe(data, engines):
    """[data]: an image file's bytes. [engines]: name -> read(strip, line),
    each returning the line's text as read (engines.py)."""
    start = time.monotonic()
    gray = prepare(decode(data))
    groups = staves(find_lines(gray))
    jobs = [(line, gray[line.y0:line.y1, line.x0:line.x1]) for g in groups for line in g]
    if not jobs:
        return Result("", seconds=time.monotonic() - start)

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
            options = [rebuild(raw[name][i], label, width) for name in engines]
            for name, o in zip(engines, options):
                readings[name].append(o)
            block.append(vote(options))
            i += 1
        blocks.append("\n".join(block))
    return Result("\n\n".join(blocks) + "\n", staves=len(groups), lines=len(jobs),
                  seconds=round(time.monotonic() - start, 2), readings=readings,
                  timings=timings)
