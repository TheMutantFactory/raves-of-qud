#!/usr/bin/env python3
"""Contact sheet of every prop-*.vox — crude isometric, the GAME's read rules.

One picture of all the statues without walking Qud to each. Deliberately reimplements the game's
palette handling (convention scoring + the alpha rule), because that is what caught the tie bug:
the first statue writer padded unused palette slots with OPAQUE black, the scorer tied, ties read
straight, and every generated statue would have worn black shoulders in-game. On the sheet it was
visible in one glance.

    python3 tools/capture/statue_sheet.py            # -> ~/Downloads/statue_sheet.png
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vox_mirror import read_vox
from PIL import Image, ImageDraw

VOX = os.path.expanduser("~/Library/Application Support/RavesOfQud/vox")
S = 5


def render(path):
    _, models, rgba = read_vox(path)
    dims, vox = models[0]

    def pal(pos):
        o = pos * 4
        return tuple(rgba[o:o + 4])

    straight = sum(1 for v in vox if pal(v[3])[3] >= 250)
    spec = sum(1 for v in vox if v[3] >= 1 and pal(v[3] - 1)[3] >= 250)
    shift = 1 if spec > straight else 0
    W = 32 * S + 8
    H = 16 * S + 24 * S + 16
    im = Image.new("RGB", (W, H), (10, 26, 30))
    dr = ImageDraw.Draw(im)

    def iso(x, y, z):
        return (4 + (x - y + 16) * S, H - 8 - z * S - (x + y) * S // 2)

    for (x, y, z, i) in sorted(vox, key=lambda v: (v[0] + v[1], v[2])):
        c = pal(i - shift)
        if c[3] < 128:
            continue
        r, g, b = c[:3]
        px, py = iso(x, y, z)
        dr.polygon([(px, py - S), (px + S, py - S - S // 2), (px + S, py - S // 2), (px, py)], fill=(r, g, b))
        dr.polygon([(px, py - S), (px - S, py - S - S // 2), (px - S, py - S // 2), (px, py)],
                   fill=(r * 70 // 100, g * 70 // 100, b * 70 // 100))
        dr.polygon([(px, py - S), (px + S, py - S - S // 2), (px, py - 2 * S), (px - S, py - S - S // 2)],
                   fill=(min(255, r * 115 // 100), min(255, g * 115 // 100), min(255, b * 115 // 100)))
    return im


def main():
    files = sorted(glob.glob(os.path.join(VOX, "prop-*.vox")))
    if not files:
        raise SystemExit("no prop-*.vox models")
    tiles = []
    for f in files:
        name = os.path.basename(f)[5:-4]
        for pre in ("Terrain_sw_", "Furniture_", "creatures_sw_"):
            name = name.replace(pre, "")
        tiles.append((name, render(f)))
    cols = 7
    tw, th = tiles[0][1].size
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + 14)), (6, 16, 20))
    dr = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(tiles):
        cx, cy = (i % cols) * tw, (i // cols) * (th + 14)
        sheet.paste(im, (cx, cy))
        dr.text((cx + 4, cy + th), name[:26], fill=(180, 200, 195))
    out = os.path.expanduser("~/Downloads/statue_sheet.png")
    sheet.save(out)
    print("%d props -> %s" % (len(tiles), out))


if __name__ == "__main__":
    main()
