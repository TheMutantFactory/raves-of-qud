#!/usr/bin/env python3
"""Derive EVERY cardinal wall-context model from the platonic .vox.

Daniel's platonic is a complete fence PANEL: 3-column end posts at both x edges, a 2-row slat
face on both y sides, an 8-periodic slat/checker pattern between (interior x=3..12), and a k
core. His markup over a screenshot says what a JOIN should look like instead of two posts
meeting: the magenta area (roof) "should be an extension of the checkerboard pattern", the
orange area (face column) "should mimic the other columns that have a dark green background and
cross beams" — i.e. a CONNECTED edge continues the pattern, an OPEN edge keeps the post.

So, per cardinal signature (nesw bits at even positions):

  - E/W connected  -> that 3-column post band is replaced by the interior pattern shifted one
    period (x=0..2 := x=8..10, x=13..15 := x=5..7). Cell A's x=15 is then interior column 7 and
    its neighbour's x=0 is column 8 — consecutive, so the join is seamless BY CONSTRUCTION.
  - N/S connected  -> the same treatment through the TRANSPOSE (the derive_runs turn, preserving
    seam phase).
  - Mixed signatures (corners, Ts, the cross) are the FIRST-WINS UNION of an E-W piece and a N-S
    piece, each with its connected edges continued, its open edges posted, and its face rows
    REMOVED on sides where the other piece takes over (a corner's south face would otherwise
    stand inside the joint). The outer corner comes free: the E-W piece's north face and the
    N-S piece's west face union into an L.
  - 00000000 (isolated) is the platonic verbatim — posts both ends is exactly its design.

The pristine drawing lives at <family>-platonic.vox (never overwritten; re-copy your editor save
there). This tool overwrites all 16 <family>-<bits>.vox, INCLUDING 00100010 — the both-connected
variant continues at both edges, which is no longer the panel-with-posts Daniel drew.

Bands and periods are MEASURED off the file, with the spec/alpha rules the game itself reads by
(a voxel on a sub-half-alpha palette slot is not part of the structure). Assertions fail loudly
if a future platonic breaks the 8-period or the post detection.

    python3 tools/capture/derive_wallvox.py wall_brinestalk
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vox_mirror import read_vox, write_vox

VOXDIR = os.path.expanduser("~/Library/Application Support/RavesOfQud/vox")
PERIOD = 8


def load_platonic(family):
    for stem in ("%s-platonic" % family, "%s-00100010" % family):
        p = os.path.join(VOXDIR, stem + ".vox")
        if os.path.exists(p):
            version, models, rgba = read_vox(p)
            if models:
                return p, version, models[0], rgba
    sys.exit("no platonic model for %s" % family)


def structure(dims, vox, rgba):
    """-> (post_band, face_rows), measured with the game's own read rules."""
    W, D, H = dims
    def opaque(i):
        pos = i - 1                       # spec indexing (vengi wrote this file)
        return pos >= 0 and rgba[pos * 4 + 3] >= 128
    grid = {(x, y, z): i for (x, y, z, i) in vox if opaque(i)}
    def xslab(x):
        return frozenset((y, z, i) for (xx, y, z), i in grid.items() if xx == x)
    band = None
    for b in range(W // 2):
        pairs = [x for x in range(b, PERIOD) if x + PERIOD < W - b]
        if pairs and all(xslab(x) == xslab(x + PERIOD) for x in pairs):
            band = b
            break
    assert band is not None, "no x-band makes the interior %d-periodic" % PERIOD
    # face rows: leading y rows with NO core-k. k is whatever colour dominates the middle rows.
    from collections import Counter
    mid = Counter()
    for (x, y, z), i in grid.items():
        if D // 2 - 1 <= y <= D // 2:
            mid[i] += 1
    k = mid.most_common(1)[0][0]
    face = 0
    while face < D // 2 and not any(i == k for (x, y, z), i in grid.items() if y == face):
        face += 1
    assert 1 <= face <= 4, "face band %d is not believable" % face
    return band, face


def continue_x(v, dims, west, east, band):
    """Replace post bands with the interior pattern, one period over.

    West: x=0..band-1 := the voxels at x=PERIOD..PERIOD+band-1, shifted left one period.
    East: x=W-band..W-1 := the voxels at x=W-band-PERIOD..W-1-PERIOD, shifted right.
    Cell A's last column is then interior column W-1-PERIOD and its neighbour's first is
    PERIOD — consecutive interior columns, so the join continues by construction."""
    W = dims[0]
    out = [(x, y, z, i) for (x, y, z, i) in v
           if not (west and x < band) and not (east and x >= W - band)]
    if west:
        out += [(x - PERIOD, y, z, i) for (x, y, z, i) in v if PERIOD <= x < PERIOD + band]
    if east:
        out += [(x + PERIOD, y, z, i) for (x, y, z, i) in v if W - band - PERIOD <= x < W - PERIOD]
    return out


def strip_face(v, dims, north, south, face):
    D = dims[1]
    return [(x, y, z, i) for (x, y, z, i) in v
            if not (north and y < face) and not (south and y >= D - face)]


def transpose(v):
    return [(y, x, z, i) for (x, y, z, i) in v]


def main():
    family = sys.argv[1] if len(sys.argv) > 1 else "wall_brinestalk"
    src, version, model, rgba = load_platonic(family)
    dims, vox = model          # read_vox models are (dims, vox) tuples
    assert dims[0] == dims[1], "footprint must be square for the transpose"
    band, face = structure(dims, vox, rgba)
    print("%s: platonic %s  post band %d  face rows %d  period %d" % (family, os.path.basename(src), band, face, PERIOD))

    def ew_piece(e, w, strip_n, strip_s):
        v = continue_x(vox, dims, west=w, east=e, band=band)
        return strip_face(v, dims, north=strip_n, south=strip_s, face=face)

    def ns_piece(n, s, strip_e, strip_w):
        # result-N <- platonic-W, result-S <- platonic-E; result-E face <- platonic-S rows,
        # result-W face <- platonic-N rows. Build in platonic space, then transpose.
        v = continue_x(vox, dims, west=n, east=s, band=band)
        v = strip_face(v, dims, north=strip_w, south=strip_e, face=face)
        return transpose(v)

    wrote = 0
    for sig in range(16):
        n, e, s, w = (sig >> 3) & 1, (sig >> 2) & 1, (sig >> 1) & 1, sig & 1
        bits = "%d0%d0%d0%d0" % (n, e, s, w)
        pieces = []
        if e or w:
            pieces.append(ew_piece(e=bool(e), w=bool(w), strip_n=bool(n), strip_s=bool(s)))
        if n or s:
            pieces.append(ns_piece(n=bool(n), s=bool(s), strip_e=bool(e), strip_w=bool(w)))
        if not pieces:
            pieces = [list(vox)]
        merged = {}
        for piece in pieces:
            for (x, y, z, i) in piece:
                merged.setdefault((x, y, z), i)
        out_vox = [(x, y, z, i) for (x, y, z), i in sorted(merged.items())]
        out = os.path.join(VOXDIR, "%s-%s.vox" % (family, bits))
        write_vox(out, version, [(dims, out_vox)], rgba)
        wrote += 1
        tag = ("isolated" if sig == 0 else
               "run" if bits in ("00100010", "10001000", "00100000", "00000010", "10000000", "00001000") else
               "junction")
        print("  %s  %5d voxels  %s" % (bits, len(out_vox), tag))
    print("wrote %d cardinal models" % wrote)


if __name__ == "__main__":
    main()
