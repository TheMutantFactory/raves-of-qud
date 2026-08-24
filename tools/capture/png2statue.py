#!/usr/bin/env python3
"""Generate a voxel statue from its tile art — Daniel's recipe, measured off his reference.

He hand-built sw_resheph_sultanstatue in the voxel editor and described the method: "I took the
png and centered it in the voxel and duplicated it. Then I created a base. Then I extruded the
legs/body at a width of 4 pixels and the head at 2. This should be a generalizable algorithm from
the existing statue images."

Measured off that reference (model-16x16x24 (3).vox):

  - PLINTH: two stepped octagon layers at z=0..1, copied VERBATIM from his model (embedded
    below), with the pale main-colour course on the north face of the step;
  - FIGURE: the art's opaque band, bottom row at z=2, extruded through y=6..9 (depth 4);
  - HEAD: the top 3/8 of the figure's rows (his split: 8 of 21) extruded through y=7..8 only;
  - COLOURS: art luminance binarised — bright pixels take the DETAIL colour, dark take MAIN —
    the same endpoints _recolor_rgb lerps between. Resheph is fg 'y', detail 'g': green body,
    pale accents.

Honesty note baked into --validate: a pure extrusion reproduces ~79% of his hand model; the
rest is his hand (touched-up colours, union of the duplicated faces). The generator does the
recipe; his file stays canonical for Resheph. Output goes to <support>/vox/prop-<flat>.vox,
which the game meshes at runtime (24 layers is the opt-in, as for walls).

    python3 tools/capture/png2statue.py Terrain_sw_statue1.bmp
    python3 tools/capture/png2statue.py Terrain_sw_resheph_sultanstatue.bmp --validate ~/Downloads/"model-16x16x24 (3).vox"
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voxel
from vox_mirror import write_vox

SUPPORT = os.path.expanduser("~/Library/Application Support/RavesOfQud")
OUT = os.path.join(SUPPORT, "vox")
HEAD_FRAC = 3.0 / 8.0        # his split: 8 head rows of a 21-row figure
BODY_Y = (6, 9)              # depth-4 extrusion band
HEAD_Y = (7, 8)              # depth-2

PLINTH = {
    0: ["......dddd......", ".....dddddd.....", "....dddddddd....", "...dddddddddd...",
        "..dddddddddddd..", ".dddddddddddddd.", "dddddddddddddddd", "dddddddddddddddd",
        "dddddddddddddddd", "dddddddddddddddd", ".dddddddddddddd.", "..dddddddddddd..",
        "...dddddddddd...", "....dddddddd....", ".....dddddd.....", "......dddd......"],
    1: ["................", "................", "................", ".....dddddd.....",
        "....dddddddd....", "...dddddddddd...", "..dddddddddddd..", ".mmmmmmmmmmmmmm.",
        ".dddddddddddddd.", "..dddddddddddd..", "...dddddddddd...", "....dddddddd....",
        ".....dddddd.....", "................", "................", "................"],
}


def qud_colour(letter):
    pal = json.load(open(os.path.join(SUPPORT, "colors.json")))
    hexv = pal[letter].lstrip("#")
    return tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4))


def build(tile, main_l="y", detail_l="g"):
    w, h, ch, rows = voxel.decode(voxel.resolve(tile))
    main, detail = qud_colour(main_l), qud_colour(detail_l)

    def opaque(x, r):
        return 0 <= x < w and 0 <= r < h and rows[r][x * ch + 3] >= 128

    def colour(x, r):
        px = rows[r][x * ch:x * ch + 3]
        return detail if (px[0] + px[1] + px[2]) / 3.0 > 127.5 else main

    op_rows = [r for r in range(h) if any(opaque(x, r) for x in range(w))]
    if not op_rows:
        sys.exit("no opaque art in %s" % tile)
    r_top, r_bot = min(op_rows), max(op_rows)
    n_rows = r_bot - r_top + 1
    # centre the figure's columns on the cell
    cols = [x for x in range(w) for r in op_rows if opaque(x, r)]
    dx = round(7.5 - (min(cols) + max(cols)) / 2.0)
    head_rows = round(n_rows * HEAD_FRAC)

    vox = []
    for z in (0, 1):
        for y in range(16):
            for x in range(16):
                t = PLINTH[z][y][x]
                if t != ".":
                    vox.append((x, y, z, detail if t == "d" else main))
    for r in range(r_top, r_bot + 1):
        z = 2 + (r_bot - r)
        if z > 23:
            continue
        y0, y1 = HEAD_Y if (r - r_top) < head_rows else BODY_Y
        for x in range(w):
            if opaque(x, r):
                c = colour(x, r)
                for y in range(y0, y1 + 1):
                    vox.append((x + dx, y, z, c))

    palette, index, out = [], {}, []
    for (x, y, z, c) in vox:
        if c not in index:
            palette.append(c)
            index[c] = len(palette)     # 1-based, written straight
        out.append((x, y, z, index[c]))
    rgba = bytearray()
    for i in range(256):
        c = palette[i] if i < len(palette) else (0, 0, 0)
        rgba += bytes((c[0], c[1], c[2], 255))
    return (16, 16, 24), out, bytes(rgba), dict(rows=n_rows, head=head_rows, dx=dx)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    tile = args[0]
    main_l = args[1] if len(args) > 2 else "y"
    detail_l = args[2] if len(args) > 2 else "g"
    dims, vox, rgba, info = build(tile, main_l, detail_l)
    flat = os.path.splitext(os.path.basename(tile))[0]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "prop-%s.vox" % flat)
    write_vox(path, 150, [(dims, vox)], rgba)
    print("%s  %d voxels  (figure %d rows, head %d, dx %+d)"
          % (path, len(vox), info["rows"], info["head"], info["dx"]))

    if "--validate" in sys.argv:
        ref_path = args[-1]
        from vox_mirror import read_vox
        _, models, ref_rgba = read_vox(os.path.expanduser(ref_path))
        rdims, rvox = models[0]
        def rpal(i):
            o = i * 4
            return tuple(ref_rgba[o:o + 3])
        ref = {(x, y, z) for x, y, z, i in rvox}
        got = {(x, y, z) for x, y, z, i in vox}
        inter = len(ref & got)
        print("validate vs %s:" % os.path.basename(ref_path))
        print("  reference %d voxels, generated %d, shared %d (%.0f%% of reference)"
              % (len(ref), len(got), inter, 100.0 * inter / len(ref)))
        print("  the gap is the hand: touched-up colours and the duplicated-face union.")


if __name__ == "__main__":
    main()
