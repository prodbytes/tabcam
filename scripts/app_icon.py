"""Writes the Tabs.cam icon masters and the logo (specs/app-icon.md).

tabcam_app/assets/icon/icon.svg, icon_foreground.svg and logo.svg; the
logo's wordmark is Roboto Medium (the app's font) turned into paths, so
the SVG needs no font. Needs fontTools (pip install fonttools).
Run by scripts/app-icon.sh, which then renders the PNGs.
"""
import os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DARK, CREAM, GOLD, REC = "#1E1A15", "#FBF7EF", "#E0A030", "#E5533B"

# Digits drawn as strokes (no font needed), in a 60 x 86 box.
DIGITS = {
    "3": "M4,12 C12,3 21,0 30,0 C46,0 55,10 55,22 C55,34 45,42 29,42 "
         "C47,42 58,52 58,64 C58,78 46,86 29,86 C18,86 8,82 2,73",
    "5": "M54,0 H10 L5,39 C14,33 23,31 32,31 C48,31 58,43 58,58 "
         "C58,75 46,86 30,86 C18,86 8,81 2,72",
    "7": "M2,0 H58 L22,86",
}

def lens(cx=512, cy=512):
    """The lens: a gold ring round a cream disc with a six-line staff and
    the fret numbers 3, 5, 7 rising across it, and a rec dot on the ring."""
    r_ring, r_disc = 340, 290
    out = [f'<defs><clipPath id="disc"><circle cx="{cx}" cy="{cy}" r="{r_disc}"/></clipPath></defs>',
           f'<circle cx="{cx}" cy="{cy}" r="{r_disc}" fill="{CREAM}"/>',
           '<g clip-path="url(#disc)">']
    ys = [cy - 175 + 70 * i for i in range(6)]
    for y in ys:
        out.append(f'<line x1="{cx - r_disc}" y1="{y}" x2="{cx + r_disc}" y2="{y}" '
                   f'stroke="{DARK}" stroke-width="11" opacity="0.8"/>')
    for d, x, y in (("3", cx - 118, ys[4]), ("5", cx, ys[2]), ("7", cx + 118, ys[0])):
        out.append(f'<rect x="{x - 42}" y="{y - 52}" width="84" height="104" fill="{CREAM}"/>')
        out.append(f'<path transform="translate({x - 30} {y - 43})" d="{DIGITS[d]}" fill="none" '
                   f'stroke="{GOLD}" stroke-width="20" stroke-linecap="round" stroke-linejoin="round"/>')
    out.append('</g>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r_ring}" fill="none" stroke="{GOLD}" stroke-width="64"/>')
    # The rec dot, on the ring at its top right (the takes Cam records).
    dx = round(r_ring * 0.7071)
    out.append(f'<circle cx="{cx + dx}" cy="{cy - dx}" r="58" fill="{REC}" stroke="{DARK}" stroke-width="20"/>')
    return "\n  ".join(out)

def svg(w, h, body, comment):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
            f'  <!-- {comment} -->\n  {body}\n</svg>\n')

icon = svg(1024, 1024, f'<rect width="1024" height="1024" fill="{DARK}"/>\n  ' + lens(),
           "Tabs.cam app icon (specs/app-icon.md): a camera lens showing a line of tab")
fg = svg(1024, 1024, '<g transform="translate(512 512) scale(0.75) translate(-512 -512)">\n  '
         + lens() + '\n  </g>',
         "Android adaptive foreground: the lens alone, at 75%, inside the safe zone")

# The wordmark: the lens, then "tabs" in cream and ".cam" in gold (Roboto Medium, as paths).
font = TTFont(f"{root}/tabcam_app/assets/fonts/Roboto-Medium.ttf")
gs, cmap, hmtx = font.getGlyphSet(), font.getBestCmap(), font["hmtx"]
upm = font["head"].unitsPerEm
size = 260
scale = size / upm
baseline = 330
x = 450
parts = []
for i, ch in enumerate("tabs.cam"):
    name = cmap[ord(ch)]
    pen = SVGPathPen(gs)
    gs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
    color = CREAM if i < 4 else GOLD
    parts.append((pen.getCommands(), color))
    x += hmtx[name][0] * scale
width = round(x + 40)
text = "\n  ".join(f'<path d="{d}" fill="{c}"/>' for d, c in parts)
logo = svg(width, 480,
           '<g transform="translate(240 240) scale(0.4) translate(-512 -512)">\n  '
           + f'<circle cx="512" cy="512" r="372" fill="{DARK}"/>\n  ' + lens() + '\n  </g>\n  ' + text,
           "Tabs.cam logo for dark backgrounds: the lens and the wordmark (Roboto Medium as paths)")

for name, data in (("icon.svg", icon), ("icon_foreground.svg", fg), ("logo.svg", logo)):
    open(f"{root}/tabcam_app/assets/icon/{name}", "w").write(data)
print(width)
