#!/usr/bin/env python3
"""Mirror a MagicaVoxel .vox on one axis, preserving colours exactly.

Daniel drew a wall in an external editor and it came back with the faces reversed
left-to-right. That is a whole-model mirror, not a repaint: every voxel keeps its palette
index and only its position moves, so a round trip through here is lossless and reversible
(mirror twice and you have the original, byte-identical voxel set).

    python3 tools/capture/vox_mirror.py in.vox out.vox           # x (left-right)
    python3 tools/capture/vox_mirror.py in.vox out.vox --axis y   # depth
    python3 tools/capture/vox_mirror.py in.vox out.vox --axis z   # up/down

AXIS NAMES ARE THE FILE'S, not the editor's. MagicaVoxel is z-up, so a "left-to-right" flip
in the viewport is x here; if the model came out of a y-up tool the same gesture may be y.
The tool prints how many voxels moved and how many were already symmetric, which is the
cheapest way to tell you picked the wrong axis: a model that is symmetric on the axis you
chose reports 0 moved and nothing will look different.

Writes MAIN{ SIZE, XYZI, RGBA } at version 150 — the same shape wall2vox writes and VoxFile.gd
reads. The palette is copied VERBATIM including its alpha bytes: vengi stores per-material
data there, and rewriting it as 255 (as a naive copy does) silently flattens it.
"""
import argparse
import os
import struct
import sys


def read_vox(path):
    """-> (version, [ (dims,[(x,y,z,i)]) ... ], rgba_bytes_or_None, other_chunks_raw)"""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"VOX ":
        sys.exit("%s is not a .vox (no VOX magic)" % path)
    version = struct.unpack("<i", data[4:8])[0]
    models, rgba = [], None
    pos, dims = 8, None
    while pos + 12 <= len(data):
        cid = data[pos:pos + 4]
        n, m = struct.unpack("<ii", data[pos + 4:pos + 12])
        body = data[pos + 12:pos + 12 + n]
        if cid == b"SIZE":
            dims = struct.unpack("<iii", body[:12])
        elif cid == b"XYZI":
            cnt = struct.unpack("<i", body[:4])[0]
            vox = [struct.unpack("<BBBB", body[4 + i * 4:8 + i * 4]) for i in range(cnt)]
            models.append((dims, vox))
        elif cid == b"RGBA":
            rgba = body[:1024]
        pos += 12 + n            # MAIN's children follow inline; walk them too
    return version, models, rgba


def write_vox(path, version, models, rgba):
    def chunk(cid, content, children=b""):
        return cid + struct.pack("<ii", len(content), len(children)) + content + children

    body = b""
    for dims, vox in models:
        body += chunk(b"SIZE", struct.pack("<iii", *dims))
        body += chunk(b"XYZI", struct.pack("<i", len(vox))
                      + b"".join(struct.pack("<BBBB", *v) for v in vox))
    if rgba:
        body += chunk(b"RGBA", rgba)
    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<i", version) + chunk(b"MAIN", b"", body))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--axis", default="x", choices=["x", "y", "z"])
    a = ap.parse_args()

    version, models, rgba = read_vox(a.src)
    if not models:
        sys.exit("no models in %s" % a.src)
    ax = "xyz".index(a.axis)

    out = []
    symmetric = True
    for dims, vox in models:
        span = dims[ax]
        flipped = []
        for v in vox:
            p = list(v)
            p[ax] = span - 1 - p[ax]
            flipped.append(tuple(p))
        # DOES THE FLIP CHANGE THE MODEL? Not "did each voxel move" — on an EVEN span nothing
        # maps to itself (x=7 -> x=8), so a per-voxel identity test reports 100% moved for every
        # model ever, including a perfectly symmetric one. The question is whether the flipped
        # SET differs from the original, which is the only thing that shows on screen.
        if set(flipped) != set(vox):
            symmetric = False
        out.append((dims, flipped))
    write_vox(a.dst, version, out, rgba)

    print("%s -> %s" % (os.path.basename(a.src), os.path.basename(a.dst)))
    for i, ((dims, vox), (_d, orig)) in enumerate(zip(out, models)):
        print("  model %d  dims %s  %d voxels" % (i, "x".join(map(str, dims)), len(vox)))
    if symmetric:
        print("  WARNING: the model is MIRROR-SYMMETRIC on %s — this flip changes nothing you can"
              " see. Wrong axis?" % a.axis)
    else:
        print("  mirrored on %s: the voxel set changed, so the flip is real" % a.axis)
    print("  palette copied verbatim (%d bytes)" % (len(rgba) if rgba else 0))


if __name__ == "__main__":
    main()
