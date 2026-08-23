#!/usr/bin/env python3
"""pool_tiling_audit — a torch's ground pool is made of WHOLE CELLS, aligned to the grid.

Daniel: "it would look better if it was integer tiled, rather than a circular gradient." The pool
is a quad wearing a radial texture; tiling it means one texel per CELL and no filtering. Both
halves matter and neither is visible in a screenshot on its own -- linear filtering would blend the
texels straight back into the gradient and look almost exactly like the old picture.

ALIGNMENT IS A PARITY ARGUMENT, which is the part worth a test. A quad of D units centred on cell
(cx, cy) puts texel i's centre at cx - D/2 + i + 0.5. With D ODD that is cx - (D-1)/2 + i, an
integer offset from the cell centre, so texels land on cells. With D EVEN every texel straddles two
cells and the whole pool sits half a cell out in both axes -- which looks like a rendering bug and
is very hard to recognise as an off-by-one.

Mirrors _pool_cells and _make_radial from ZoneRenderer.gd, and reads the material's filter mode out
of the source so the two cannot drift. Stdlib only; no daemon, no apps, no Qud.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "godot", "ZoneRenderer.gd")
src = open(SRC, encoding="utf-8").read()
fails = []


def check(ok, label, detail=""):
    print("  %-4s %-54s %s" % ("ok" if ok else "FAIL", label, detail))
    if not ok:
        fails.append(label)


def pool_cells(d):
    n = int(round(d))
    if n % 2 == 0:
        n += 1
    return max(3, n)


def make_radial(n):
    c = (n - 1) * 0.5
    return [[max(0.0, min(1.0, 1.0 - (((x - c) ** 2 + (y - c) ** 2) ** 0.5) / c))
             for x in range(n)] for y in range(n)]


print("the quad snaps to whole cells")
for d in (1.6, 2.0, 2.8, 4.2, 6.4, 9.6, 12.0):
    n = pool_cells(d)
    check(n % 2 == 1 and n >= 3, "%.1f units -> %d cells (odd, >= 3)" % (d, n))

print()
print("one texel per cell, and the sampler must not blend them")
# The quad's size and its texture must come from the SAME n, or the tiling is off by a scale
# factor. Checked as properties rather than as exact source lines -- the first version of this
# audit pinned the literal text and broke the moment the call grew a mask argument, which is a
# test failing for the wrong reason and trains you to ignore it.
check(re.search(r"var n := _pool_cells\(d\)", src) is not None, "the quad's n comes from _pool_cells")
check(re.search(r"gm\.size = Vector2\(n, n\)", src) is not None, "the quad is n cells square")
pool_calls = re.findall(r"_fx_material\(_pool_texture\([^)]*\)\s*,\s*(\w+)\)", src)
check(len(pool_calls) >= 1, "the pool's material comes from _pool_texture", "%d call(s)" % len(pool_calls))
check(all(a == "true" for a in pool_calls), "EVERY pool call asks _fx_material for NEAREST",
      "found %s" % (pool_calls or "none"))
check("TEXTURE_FILTER_NEAREST" in src, "_fx_material can actually do NEAREST",
      "linear would blend the tiling back into a gradient")

print()
print("the pool stops where Qud says the light stops")
check("const LIGHT_LIT := 200" in src, "LIGHT_LIT is Qud's LightLevel.Light")
check(re.search(r">= LIGHT_LIT", src) is not None,
      "the lit set is built from LIGHT_LIT, not LIGHT_NONE",
      "> LIGHT_NONE would count darkvision cells and fill the screen")
check(re.search(r"func _pool_mask", src) is not None, "a pool carries a per-cell lit mask")
check(re.search(r"func _shape_pools", src) is not None,
      "and the mask is refreshed per turn, not baked once",
      "a zone entered at noon bakes an all-lit mask")
# the refresh must not be hidden behind the `any_dark` gate the sprite relight uses
m = re.search(r"_was_dark = any_dark\s*\n(.*?)\n\tif not _wall_cutaway", src, re.S)
check(m is not None and "_shape_pools(cells)" in m.group(1),
      "_shape_pools runs unconditionally each turn")

# the mask itself: a wall cell inside the radius must go dark
def pool_mask(lit, cx, cy, n):
    half = (n - 1) // 2
    return "".join("1" if (cx - half + i, cy - half + j) in lit else "0"
                   for j in range(n) for i in range(n))

n = 5
allcells = {(x, y) for x in range(-2, 3) for y in range(-2, 3)}
blocked = allcells - {(1, 0), (2, 0)}          # a wall clipping the eastern arm
m_open = pool_mask(allcells, 0, 0, n)
m_wall = pool_mask(blocked, 0, 0, n)
check(m_open.count("1") == n * n, "open ground: every cell in the pool is lit")
check(m_wall.count("1") == n * n - 2, "a blocked cell drops out of the mask",
      "%d lit vs %d" % (m_wall.count("1"), m_open.count("1")))
check(m_open != m_wall, "...so the two shapes get different textures, not one shared one")

print()
print("the falloff still reads as a disc, one flat value per cell")
for n in (5, 11):
    g = make_radial(n)
    mid = g[n // 2]
    levels = sorted({round(a, 3) for a in mid}, reverse=True)
    check(g[n // 2][n // 2] == 1.0, "%2d cells: the light's own cell is full brightness" % n)
    check(len(levels) >= 3, "%2d cells: %d distinct steps across the centre row" % (n, len(levels)))
    check(all(g[0][x] == 0.0 for x in range(n)) and all(g[y][0] == 0.0 for y in range(n)),
          "%2d cells: the outer ring is empty, so no square edge shows" % n)
    corner = g[n // 2 - 1][n // 2 - 1]
    edge = g[n // 2][n // 2 - 1]
    check(corner < edge, "%2d cells: corners dimmer than edges (a disc, not a square)" % n,
          "corner %.2f < edge %.2f" % (corner, edge))

print()
if fails:
    print("%d check(s) failed" % len(fails))
    sys.exit(1)
print("all good (0 checks failed)")
