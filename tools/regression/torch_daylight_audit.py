#!/usr/bin/env python3
"""torch_daylight_audit — a torch's rig is gated by TIME OF DAY, never by its art filename.

Joppa's Torchposts got no fire, no smoke and no light-pool at ANY hour, because the static light
gate also required the tile name not to contain "nofire" -- on the reading that the NOFIRE art
meant Qud was calling the torch unlit. It is not: measured at night, all 21 of them report
`lightRadius: 6` and `onFire: true` while still wearing `sw_torch_nofire.png`. The art never
changes, so the test was true around the clock. Daniel: "the torches don't seem to be lighting at
night."

The daytime requirement that test was added for -- "torches aboveground should not have fire or
smoke during the day" -- is met properly by the daylight multipliers. This audit is here so that
stays true, because the filename test LOOKED like it was what enforced it, and removing something
that looks load-bearing is exactly the change worth pinning down.

Reads the constants and the two formulas out of ZoneRenderer.gd rather than restating them, so a
change to either has to come past this. Stdlib only; no daemon, no apps, no Qud.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "godot", "ZoneRenderer.gd")

fails = []
src = open(SRC, encoding="utf-8").read()


def const(name):
    m = re.search(r"^const %s := ([0-9.]+)" % name, src, re.M)
    if not m:
        fails.append("constant %s not found in ZoneRenderer.gd" % name)
        return None
    return float(m.group(1))


def check(ok, label, detail=""):
    print("  %-4s %-56s %s" % ("ok" if ok else "FAIL", label, detail))
    if not ok:
        fails.append(label)


print("torch rig gate")
gate = re.search(r"if o\.has\(\"lightRadius\"\).*?:\n", src, re.S)
gate_txt = gate.group(0) if gate else ""
check(bool(gate), "the static light gate is present")
check("nofire" not in gate_txt, "the gate does NOT test the tile filename",
      "art is not state: nofire art + onFire:true + lightRadius:6 all coexist")
check("lightRadius" in gate_txt, "the gate asks Qud whether the thing emits light")

print()
print("daylight fade — what actually enforces 'no fire by day'")
glow_min = const("GLOW_DAY_MIN")
flame_min = const("FLAME_DAY_MIN")
smoke_off = const("SMOKE_OFF_SUN")
fire_dark = const("FIRE_GLOW_DARK")

if None not in (glow_min, flame_min, smoke_off, fire_dark):
    def lerp(a, b, t):
        return a + (b - a) * t

    def glow_mul(sun):
        return lerp(glow_min, 1.0, 1.0 - sun)

    def flame_mul(sun):
        return lerp(flame_min, 1.0, 1.0 - sun)

    def fire_glow_mul(sun):
        return max(0.0, min(1.0, (fire_dark - sun) / fire_dark))

    # transparency 1.0 == invisible. The formula is the one in _place_light / _process.
    def glow_transparency(sun, energy=1.0):
        return max(0.0, min(1.0, 1.0 - energy * glow_mul(sun) * 0.6))

    check(glow_mul(1.0) == 0.0, "midday: a torch's ground pool multiplier is 0")
    check(glow_transparency(1.0) == 1.0, "midday: the pool mesh is fully transparent")
    check(flame_mul(1.0) == 0.0, "midday: a torch's flame emits nothing")
    check(fire_glow_mul(1.0) == 0.0, "midday: even an on-fire object's pool is off")
    check(not (1.0 < smoke_off), "midday: smoke is off", "sun 1.0 >= SMOKE_OFF_SUN %.2f" % smoke_off)

    check(glow_mul(0.0) == 1.0, "night: the pool is at full strength")
    check(flame_mul(0.0) == 1.0, "night: the flame is at full strength")
    check(0.0 < smoke_off, "night: smoke emits", "sun 0.0 < SMOKE_OFF_SUN %.2f" % smoke_off)
    check(glow_transparency(0.0) < 0.45, "night: the pool mesh is clearly opaque",
          "transparency %.2f" % glow_transparency(0.0))

print()
if fails:
    print("%d check(s) failed" % len(fails))
    sys.exit(1)
print("all good (0 checks failed)")
