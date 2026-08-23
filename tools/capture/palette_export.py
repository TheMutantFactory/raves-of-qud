#!/usr/bin/env python3
"""palette_export — write Qud's 18-colour palette as a Lospec-style JSON palette.

For the voxel editor. Raves' props are carved from Qud's own art, so the voxels want Qud's own
colours; picking them off a screenshot gets you the colour AFTER the scene's lighting multiply, not
the palette entry (see docs/gotchas.md — compare RATIOS, not values).

THE SOURCE IS THE GAME, not a table in our code. `colors.json` is written by the mod from Qud's live
palette; ZoneRenderer.COLORS is only a fallback for when that file is absent, and it is visibly
wrong in places (its `k` and `K` are both 0.10 grey, where Qud's are the #0f3b3a/#155352 memory
pair the whole fog treatment is built on). Reading the wire's copy means the palette cannot drift
from what the renderer actually draws.

ORDER IS QUD'S OWN: r R g G b B c C m M w W o O y Y k K -- dark/bright pairs, the order the colour
codes are written in. Swatch N in the editor is then the same colour as `&<code>` in a tile, which
is the only ordering that makes an index worth memorising.

    python3 tools/capture/palette_export.py                    # -> ~/Downloads/Caves of Qud.json
    python3 tools/capture/palette_export.py --out other.json
"""
import argparse
import json
import os
import sys

SUPPORT = os.path.expanduser("~/Library/Application Support/RavesOfQud")
# Qud writes them keyed by colour CODE; this is the order they are conventionally listed in.
ORDER = ["r", "R", "g", "G", "b", "B", "c", "C", "m", "M",
         "w", "W", "o", "O", "y", "Y", "k", "K"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--colors", default=os.path.join(SUPPORT, "colors.json"))
    ap.add_argument("--out", default=os.path.expanduser("~/Downloads/Caves of Qud.json"))
    a = ap.parse_args()

    if not os.path.exists(a.colors):
        sys.exit("no palette at %s — run the game once so the mod exports it" % a.colors)
    pal = json.load(open(a.colors))

    missing = [c for c in ORDER if c not in pal]
    extra = [c for c in pal if c not in ORDER]
    # NAME THE GAPS rather than silently shipping a short palette: a missing entry would shift every
    # swatch after it, and an index that moved is worse than one that is absent.
    if missing:
        print("WARNING: %d code(s) absent from colors.json: %s" % (len(missing), " ".join(missing)))
    if extra:
        print("note: %d code(s) present that this tool does not list: %s" % (len(extra), " ".join(extra)))

    colors = []
    for code in ORDER:
        if code not in pal:
            continue
        hexv = str(pal[code]).strip().lower()
        if not hexv.startswith("#"):
            hexv = "#" + hexv
        if len(hexv) != 7:
            sys.exit("colour %r is %r, not #rrggbb" % (code, hexv))
        colors.append(hexv)

    out = {
        "name": "Caves of Qud",
        "author": "Freehold Games",
        "source": "https://www.cavesofqud.com/",
        "colors": colors,
    }
    with open(a.out, "w") as f:
        json.dump(out, f, indent="\t")
        f.write("\n")
    print("wrote %d colours -> %s" % (len(colors), a.out))
    for code, hexv in zip([c for c in ORDER if c in pal], colors):
        print("   %2d  &%s  %s" % (colors.index(hexv), code, hexv))


if __name__ == "__main__":
    main()
