#!/usr/bin/env python3
"""Derive the run-set wall MODELS from the platonic .vox (the derive_runs.py of the vox path).

Daniel's model for the band-grammar art: 00100010 (the E-W run piece) IS the design, and every
other run orientation is generated from it. The .vox wall path hit the same wall the art path once
did — "missing sig = silent STOCK fallback" — with 162 brinestalk cells in Joppa's zone and exactly
FIVE wearing the one modelled signature.

    E/W set (verbatim):   00100010 -> 00100000, 00000010
    N/S set (turned 90):  -> 10001000, 10000000, 00001000

The 90-degree turn is a TRANSPOSE — (x, y, z) -> (y, x, z), the mirror across the main diagonal —
for the same reason derive_runs.py transposes the cap interior: unlike a true rotation on an
even-sized grid it PRESERVES the global seam phase, so a period-2 pattern stays continuous at every
wall-to-wall join. The whole volume turns, faces included; a 3D model has no "face band copied
verbatim" escape hatch, and a chiral face design will mirror. If that ever matters, this is the
line to revisit.

Corners, T-junctions and the isolated block are NOT derived — same as the art path, where each was
its own design ("junction platonics" are future authoring, not a rotation of a run). They fall back
to stock art, and zonereport now says so per signature instead of staying quiet.

    python3 tools/capture/derive_wallvox.py wall_brinestalk    # re-run after editing the platonic
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vox_mirror import read_vox, write_vox

VOXDIR = os.path.expanduser("~/Library/Application Support/RavesOfQud/vox")
PLATONIC = "00100010"
EW_SET = ["00100000", "00000010"]
NS_SET = ["10001000", "10000000", "00001000"]


def main():
    family = sys.argv[1] if len(sys.argv) > 1 else "wall_brinestalk"
    src = os.path.join(VOXDIR, "%s-%s.vox" % (family, PLATONIC))
    if not os.path.exists(src):
        sys.exit("no platonic model at %s" % src)
    version, models, rgba = read_vox(src)
    if not models:
        sys.exit("no models in %s" % src)
    dims, vox = models[0]
    if dims[0] != dims[1]:
        sys.exit("footprint %dx%d is not square; a transpose would change the dims" % dims[:2])

    transposed = [(y, x, z, i) for (x, y, z, i) in vox]

    wrote = []
    for bits in EW_SET:
        out = os.path.join(VOXDIR, "%s-%s.vox" % (family, bits))
        write_vox(out, version, [(dims, vox)], rgba)
        wrote.append((bits, "verbatim"))
    for bits in NS_SET:
        out = os.path.join(VOXDIR, "%s-%s.vox" % (family, bits))
        write_vox(out, version, [(dims, transposed)], rgba)
        wrote.append((bits, "transposed"))
    print("%s: derived %d run models from %s (%d voxels)" % (family, len(wrote), PLATONIC, len(vox)))
    for bits, how in wrote:
        print("   %s-%s.vox  (%s)" % (family, bits, how))


if __name__ == "__main__":
    main()
