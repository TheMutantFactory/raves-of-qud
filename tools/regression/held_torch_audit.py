#!/usr/bin/env python3
"""held_torch_audit — the fire sits on the torch's own burning pixels.

"When they're lit, let's hold them in our player hand and have the fire effects clamped to the
burning part of the torch."

The clamp is arithmetic on the ART, and it is the kind of arithmetic that is wrong by half a sprite
without looking obviously wrong: tile rows run DOWN and world Y runs UP, so the flame's base is the
row BELOW its last bright row, not its first. Get the sign backwards and the fire hangs off the
bottom of the stick, which reads as "the torch is upside down" rather than as an off-by-one.

Mirrors _flame_band and the placement maths in ZoneRenderer._place_held_light, against the real
tiles when they are present. Stdlib + PIL; no daemon, no apps, no Qud.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "godot", "ZoneRenderer.gd")
TILES = os.path.expanduser("~/Library/Application Support/RavesOfQud/tiles")
src = open(SRC, encoding="utf-8").read()
fails = []


def const(name, default=None):
    m = re.search(r"^const %s := ([0-9.]+)" % name, src, re.M)
    if m:
        return float(m.group(1))
    if default is None:
        fails.append("constant %s not found" % name)
    return default


def check(ok, label, detail=""):
    print("  %-4s %-52s %s" % ("ok" if ok else "FAIL", label, detail))
    if not ok:
        fails.append(label)


PIXEL_SIZE = const("PIXEL_SIZE")
HELD_SCALE = const("HELD_SCALE")
HELD_GRIP = const("HELD_GRIP")
FIRE_RISE = const("FIRE_RISE")
FIRE_LIFETIME = const("FIRE_LIFETIME")

print("the source says what it should")
check("_flame_band" in src, "there is a flame-band reader")
check(re.search(r'String\(_held_light\.get\("type", ""\)\) != "Hand"', src) is not None,
      "only a HAND slot is drawn", "a lantern on the Back is a light, not a held thing")
check("_held_light_fallback" in src, "there is an inventory.json fallback for an un-restarted Qud")
check(re.search(r'pc\.has\("heldLight"\)', src) is not None,
      "the snapshot field wins when the mod provides it")
check(re.search(r"no_flame", src) is not None,
      "the pool and the flame are placed separately",
      "a per-turn rig must not pile into _lights")

check(re.search(r"func _grip_px", src) is not None,
      "the grip point is READ off the art, not assumed")
check(re.search(r"var side: float = HELD_SIDE", src) is not None,
      "the torch goes on the RIGHT-most hand", "the diagonal art lies across the chest on the left")
check("flame_dx" in src, "the fire is clamped across the stick as well as up it")

print()
print("the clamp arithmetic")


def band(px, w, h, bright):
    first = last = -1
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= 128 and (((r + g + b) / 3 > 128) == bright):
                if first < 0:
                    first = y
                last = y
                break
    return first, last


tile = os.path.join(TILES, "Items_sw_torch_lit.png")
if not os.path.exists(tile):
    print("  --   torch art not exported here; arithmetic checked on a synthetic band")
    top, bot, bt, bb = 3, 20, 3, 12
else:
    from PIL import Image
    im = Image.open(tile).convert("RGBA")
    w, h = im.size
    px = im.load()
    top, bot = band(px, w, h, None) if False else (None, None)
    # opaque extent
    of = ol = -1
    for y in range(h):
        if any(px[x, y][3] >= 128 for x in range(w)):
            ol = y
            if of < 0:
                of = y
    top, bot = of, ol
    bt, bb = band(px, w, h, True)
    check(bt >= 0, "the lit torch art has bright (flame) pixels", "rows %d..%d" % (bt, bb))
    check(bt == top, "the flame starts at the TOP of the art", "flame %d, art %d" % (bt, top))
    check(bb < bot, "and the shaft runs on below it", "flame ends %d, art ends %d" % (bb, bot))

shown = bot - top + 1
band_n = bb - bt + 1
ps = PIXEL_SIZE * HELD_SCALE
pband = 19.0                      # the player's own band, rows 3..21
grip = PIXEL_SIZE * pband * HELD_GRIP
base_y = grip + ps * shown * 0.5
band_top_world = base_y + ps * shown * 0.5
band_bot_world = base_y - ps * shown * 0.5
flame_base = band_top_world - ps * ((bt - top) + band_n)
flame_h = ps * band_n

check(abs((band_bot_world) - grip) < 1e-6, "the torch's bottom lands in the hand",
      "%.3f == %.3f" % (band_bot_world, grip))
check(flame_base >= band_bot_world - 1e-6, "the flame's base is ON the torch, not below it",
      "%.3f >= %.3f" % (flame_base, band_bot_world))
check(flame_base + flame_h <= band_top_world + 1e-6, "and its top does not overshoot the tip",
      "%.3f <= %.3f" % (flame_base + flame_h, band_top_world))
# The flame's CENTRE, not its base. A flame that is 56% of the stick has its base below the
# midpoint by construction, so testing the base asks the geometry to be something it never was --
# the check failed on correct code, which is the failure mode that teaches you to ignore a suite.
check(flame_base + flame_h * 0.5 > (band_bot_world + band_top_world) * 0.5,
      "the fire's CENTRE is on the upper half — the burning end",
      "centre %.3f vs mid %.3f" % (flame_base + flame_h * 0.5, (band_bot_world + band_top_world) * 0.5))
check(0.2 < flame_h / (ps * shown) < 0.8, "the flame is a fraction of the stick, not all of it",
      "%.0f%% of it" % (100 * flame_h / (ps * shown)))
k = flame_h / (FIRE_RISE * FIRE_LIFETIME)
check(0.3 < k < 3.0, "the emitter scale is sane", "%.2f" % k)
check(ps * shown < PIXEL_SIZE * pband, "a held torch is shorter than the person holding it",
      "%.2f < %.2f" % (ps * shown, PIXEL_SIZE * pband))

if os.path.exists(tile):
    # the grip and the flame pull the sprite in OPPOSITE directions across the art, and the fire
    # has to end up over the flame pixels rather than over the middle of the sprite
    w2 = im.size[0]
    bottom_cols = [x for x in range(w2) if px[x, bot][3] >= 128]
    grip_col = bottom_cols[len(bottom_cols) // 2]
    fl_cols = [x for x in range(w2) for y in range(h)
               if px[x, y][3] >= 128 and sum(px[x, y][:3]) / 3 > 128]
    fx0, fx1 = min(fl_cols), max(fl_cols)
    grip_dx = (w2 - 1) * 0.5 - grip_col
    flame_dx = (fx0 + (fx1 - fx0 + 1) * 0.5 - 0.5) - (w2 - 1) * 0.5
    check(grip_dx > 0, "the grip correction pushes the sprite AWAY from the hand",
          "grip col %d, +%.1f px" % (grip_col, grip_dx))
    check(flame_dx > 0, "the flame sits to the same side as the lean",
          "flame cols %d..%d, %+.1f px" % (fx0, fx1, flame_dx))
    # with both applied, the fire lands within the flame's own columns
    fire_col = grip_col + grip_dx + flame_dx
    check(fx0 - 0.5 <= fire_col <= fx1 + 0.5,
          "the fire lands INSIDE the flame's columns",
          "%.1f in [%d, %d]" % (fire_col, fx0, fx1))

print()
print("the plume covers the painted flame")
LEAN = const("HELD_FIRE_LEAN_DEG")
SPREAD = const("HELD_FIRE_SPREAD")
AMOUNT = const("HELD_FIRE_AMOUNT")
check(re.search(r"fpm\.emission_box_extents = Vector3\(float\(band\.size\.x\)", src) is not None,
      "the emission box is as wide as the flame is PAINTED",
      "the stock 0.05 box threads through a 9-column flame")
check(re.search(r"fpm\.initial_velocity_min = flame_h / FIRE_LIFETIME", src) is not None,
      "and the rise is set from the flame's height, not a node scale",
      "one scale factor cannot serve a width and a height that differ")
# scoped to _place_held_light: _place_light still scales ITS emitter, which is correct there --
# a file-wide search for `pf.scale` failed on the sconce rig and had nothing to do with the torch.
_held_body = ""
_m = re.search(r"func _place_held_light\(.*?\n(?=\n?##|\nfunc )", src, re.S)
if _m:
    _held_body = _m.group(0)
check(bool(_held_body), "the held-torch function is findable")
check("pf.scale" not in _held_body,
      "the held emitter is NOT node-scaled", "that shrank the tongues along with the plume")
check(0 < LEAN < 45, "the lean is a lean, not a topple", "%.0f deg" % LEAN)
check(SPREAD > 8.0, "the fan is wider than the stock torch's", "%.0f deg vs 8" % SPREAD)
check(AMOUNT >= 12, "there are enough tongues to fill it", "%d" % AMOUNT)
check(re.search(r"ParticleProcessMaterial\)\.direction = \(r \* sin\(lean\)", src) is not None,
      "the lean is aimed in WORLD space, per frame",
      "local_coords=false means `direction` ignores the node basis")

print()
if fails:
    print("%d check(s) failed" % len(fails))
    sys.exit(1)
print("all good (0 checks failed)")
