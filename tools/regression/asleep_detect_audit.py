#!/usr/bin/env python3
"""asleep_detect_audit — ZoneRenderer._is_asleep, mirrored in Python.

Asleep is the OTHER colour-only render schedule: where burning flashes the cell background white
and back, Asleep floods it CYAN and back. The real capture (long held by the burning audit as its
false-positive case) is `60|0=;&c^c;|10=;;|20=;&c^c;`. Daniel: "get rid of the sleep animation.
Some sort of blue flashing" — detection gates both the flash suppression and the lying-down pose,
so a false POSITIVE lays a healthy creature on the floor and a false NEGATIVE leaves the flash.

Keep in step with ZoneRenderer._is_asleep. Stdlib only; no daemon, no apps, no Qud.
"""
import sys

FIRE_BG_FLASH = "W"
FIRE_BG_BASE = "K"


def _entries(spec):
    out = []
    for part in spec.split("|")[1:]:
        kv = part.split("=")
        if len(kv) != 2:
            continue
        axes = kv[1].split(";")
        if len(axes) != 3:
            continue
        out.append(axes)
    return out


def is_burning(spec):
    if not spec or "^" not in spec:
        return False
    seen = set()
    for axes in _entries(spec):
        if axes[0] != "":
            return False
        col = axes[1]
        i = col.find("^")
        if i >= 0 and i + 1 < len(col):
            seen.add(col[i + 1].upper())
    return FIRE_BG_FLASH.upper() in seen and FIRE_BG_BASE.upper() in seen


def is_asleep(spec):
    # NO caret precondition: the z-glyph-alone sweep has no ^ anywhere in it. Keeping the guard
    # here after removing it from the GDScript is exactly the drift this mirror exists to catch.
    if not spec or is_burning(spec):
        return False
    floods = zglyphs = 0
    for axes in _entries(spec):
        if axes[0] != "":
            if axes[0].startswith("Text/"):
                zglyphs += 1        # the floating "z" frame
            else:
                return False        # a real art swap: some other animation
        col = axes[1]
        i = col.find("^")
        if i >= 0 and i + 1 < len(col) and col[i + 1].lower() == "c":
            floods += 1
    return floods + zglyphs >= 1


CASES = [
    # The LIVE capture — a watervine farmer asleep in his bed, 2026-08-23. The detector's first
    # cut was written to the archived shape below and this one walked straight through it:
    # "He's standing and flashing."
    ("the LIVE farmer capture (one flood + z glyph)",
     "60|0=;;|11=;&C^c;|25=;;|36=Text/95.bmp;&c;|45=;;", True),
    ("the archived Asleep capture", "60|0=;&c^c;|10=;;|20=;&c^c;", True),
    # The THIRD real shape — the same farmer minutes after matching the flood+glyph capture: the
    # sweep window caught only the z frame. Tightening to phase counts is how the detector lost
    # to the same creature twice; the rule is the program's ALPHABET, not its phases.
    ("the SAME farmer's later sweep (z glyph alone)", "60|0=;;|36=Text/95.bmp;&c;|45=;;", True),
    ("burning is burning, not sleeping", "60|0=;&r^k;|7=;&r^W;|12=;&r^k;", False),
    # A window can catch the flood ON for its whole span — this is a sweep alias of sleep, and
    # it was originally written here as a NEGATIVE on the guess that a steady tint must be some
    # other effect. No such effect has ever been captured; the guess lost to evidence twice.
    ("a full-window cyan flood (sweep alias of sleep)", "60|0=;&c^c;", True),
    ("a NON-Text tile swap with ^c colours", "60|0=zz.bmp;&c^c;|20=;&c^c;", False),
    ("^C uppercase floods still count", "60|0=;&y^C;|30=;&y^C;", True),
    ("hologram fg cycle, no backgrounds", "60|0=;&C;|15=;&b;|30=;&c;", False),
    ("empty schedule", "", False),
    ("no carets at all", "60|0=;&c;|10=;;", False),
]

fails = 0
for label, spec, want in CASES:
    got = is_asleep(spec)
    ok = got == want
    print("  %-4s %-48s -> %s" % ("ok" if ok else "FAIL", label, got))
    if not ok:
        fails += 1
print()
if fails:
    print("%d check(s) failed" % fails)
    sys.exit(1)
print("all good (0 checks failed)")
