#!/usr/bin/env python3
"""Bake an edited MagicaVoxel .vox back into the wall's band grammar.

The LOAD half of the external-editor loop (Daniel: "switch to an external
editor and Raves' ability to save/load voxel files"):

    python3 tools/capture/wall2vox.py 00100010      # save (export)
    <edit <support>/vox/wall_metal-00100010.vox in MagicaVoxel / vengi>
    python3 tools/capture/vox2wall.py 00100010      # load (bake)
    python3 tools/capture/vox2wall.py --watch       # live: bake on every save

Baking writes the variant's tiles_custom .bmp (cap band from the TOP voxel
slab, face band from the exposed skins); the game's custom-art watch then
hot-reloads the wall — no restart. Not every voxel edit is representable in
the band grammar (cap art + face art + carve rules); what cannot round-trip
is COUNTED AND NAMED, never silently dropped:

  interior       a voxel below the surface differs from what the bands imply
  ring-row       cap-layer voxels at z=0/15 derive from the face art, not
                 the cap band; edits there are ignored
  face-conflict  two exposed faces claim the same face-art pixel (the
                 one-direction wrap) and disagree; the canonical dir wins
                 (s > e > n > w)
  face-carrier   face rows baked only for the four run carriers
                 (00100010/00100000/00000010/00000000); other variants'
                 face edits are ignored (family-wide face surface)

After baking, the tool re-exports through wall2vox and reports how many
voxels of the .vox survive the round trip. PIL saves with format="PNG".
"""
import os
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voxwall
import wall2vox
from PIL import Image

CUSTOM = wall2vox.CUSTOM
VOXDIR = wall2vox.OUT
# The family being baked. `wall_metal` is the one the pipeline grew up around; the name is a
# parameter now because a second family (wall_brinestalk, which Qud ships as Walls_*.png rather
# than Tiles_*.bmp) needed the same loop and every "wall_metal" in this file was a wall.
FAMILY = "wall_metal"


def _paths(bits):
    """(vox path, custom-art path) for FAMILY's variant — the extension is the family's own."""
    base, ext = wall2vox.family_base(FAMILY)
    return f"{VOXDIR}/{FAMILY}-{bits}.vox", f"{CUSTOM}/{base}-{bits}{ext}"
RUN_CARRIERS = {"00100010", "00100000", "00000010", "00000000"}
WALL_FACE_ROWS = 10


def read_vox(path):
    """Minimal .vox reader: {(x, y, z): rgb} + dims, single-model files."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"VOX ":
        sys.exit(f"not a .vox file: {path}")
    version = struct.unpack_from("<i", data, 4)[0]
    if version not in (150, 200):
        print(f"  note: vox version {version} (expected 150/200), parsing anyway")
    pos = 8
    dims = None
    raw = []
    pal = [None] * 256
    while pos + 12 <= len(data):
        cid = data[pos:pos + 4]
        size, _child = struct.unpack_from("<ii", data, pos + 4)
        body = pos + 12
        if cid == b"SIZE":
            dims = struct.unpack_from("<iii", data, body)
        elif cid == b"XYZI":
            n = struct.unpack_from("<i", data, body)[0]
            for i in range(n):
                x, y, z, ci = struct.unpack_from("<BBBB", data, body + 4 + i * 4)
                raw.append((x, y, z, ci))
        elif cid == b"RGBA":
            for i in range(256):
                r, g, b, _a = struct.unpack_from("<BBBB", data, body + i * 4)
                pal[i] = (r, g, b)
        if cid == b"MAIN":
            pos = body  # descend into children
        else:
            pos = body + size
    if dims is None:
        sys.exit(f"no SIZE chunk in {path}")
    voxels = {}
    for x, y, z, ci in raw:
        rgb = pal[ci - 1] if ci >= 1 and pal[ci - 1] is not None else (255, 0, 255)
        voxels[(x, y, z)] = rgb
    return voxels, dims


def bake(bits, verbose=True):
    vox_path, bmp_path = _paths(bits)
    if not os.path.exists(vox_path):
        sys.exit(f"no export to bake: {vox_path} (run wall2vox.py {bits} first)")
    if not os.path.exists(bmp_path):
        sys.exit(f"no custom art to bake into: {bmp_path}\n"
                 f"  seed it from the stock tile first: vox2wall.py --seed {bits}")
    voxels, (VW, VD, VR) = read_vox(vox_path)
    im = Image.open(bmp_path).convert("RGBA")
    w, h = im.size
    caph = max(1, h - WALL_FACE_ROWS)
    if (VW, VD) != (w, w):
        sys.exit(f"dims {VW}x{VD} do not match the {w}-wide art grid")

    # THE BASELINE PRINCIPLE: rebuild the volume from the CURRENT art
    # in-memory (the exact forward carve rules, protections and all) and
    # treat only voxels that DIFFER from it as user edits. Inferring
    # "expected" state from the art directly meant re-implementing every
    # forward rule backwards — each one missed (soft gaps, foundation,
    # rim, corner shells) surfaced as phantom edits (measured: 45 phantom
    # band px on an untouched cell).
    cells = wall2vox.cells_for_bits(bits, FAMILY)
    vt = wall2vox.variant_fn(FAMILY)
    v, _expo, farts, cap_art = voxwall.build_cell(vt, cells, (0, 0), FAMILY)
    base = wall2vox.voxel_colors(v, cap_art, farts)

    def solid(x, z, r):
        return voxels.get((x, z, VR - 1 - r))

    diffs = {}
    for r in range(min(v.R, VR)):
        for z in range(w):
            for x in range(w):
                b = base.get((x, z, r))
                u = solid(x, z, r)
                if (b is None) != (u is None) or (b and u and tuple(u) != tuple(b)):
                    diffs[(x, z, r)] = u

    flags = {"interior": 0, "ring-row": 0, "face-conflict": 0, "face-carrier": 0}
    changed = 0
    exposed = [d for d in ("s", "e", "n", "w")
               if (voxwall.DIRS[d][0][0], voxwall.DIRS[d][0][1]) not in cells]
    claimed = {}

    for (x, z, r), c in sorted(diffs.items()):
        new = (c[0], c[1], c[2], 255) if c else (0, 0, 0, 0)
        if r == 0:
            if 1 <= z <= w - 2:
                # cap band: art row = interior voxel row - 1 (identity at 14)
                if im.getpixel((x, z - 1)) != new:
                    im.putpixel((x, z - 1), new)
                    changed += 1
            else:
                flags["ring-row"] += 1
            continue
        # face skin? only depth-0 boundary voxels of an exposed dir bake
        placed = False
        for d in exposed:
            (dx, dz), artx = voxwall.DIRS[d]
            on_edge = (z == w - 1 if dz == 1 else z == 0) if dz else \
                      (x == w - 1 if dx == 1 else x == 0)
            if not on_edge:
                continue
            fr = r - 1
            if fr >= h - caph:
                continue
            if bits not in RUN_CARRIERS:
                flags["face-carrier"] += 1
                placed = True
                break
            ax = artx(x, z, w)
            key = (ax, fr)
            if key in claimed:
                if claimed[key] != new:
                    flags["face-conflict"] += 1
                placed = True
                break
            claimed[key] = new
            if im.getpixel((ax, caph + fr)) != new:
                im.putpixel((ax, caph + fr), new)
                changed += 1
            placed = True
            break
        if not placed:
            flags["interior"] += 1

    # DO NOT TOUCH THE FILE WHEN NOTHING CHANGED. The game watches tiles_custom by MTIME, and a
    # changed mtime means "custom art edited" -> _drop_all_static -> the whole live zone and all
    # eight neighbours rebuild. A --watch left running re-baked this tile every few seconds for
    # EIGHT DAYS, writing byte-identical PNGs, and the renderer dutifully threw away and rebuilt
    # its entire world each time. Daniel: "something is redrawing over and over." Nothing was
    # wrong with the picture; it was simply being rebuilt from scratch forever.
    #
    # Comparing the ENCODED bytes, not the pixels: PIL re-encodes deterministically here, and it
    # is the file the watcher's consumer keys on.
    import io
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    new_bytes = buf.getvalue()
    old_bytes = open(bmp_path, "rb").read() if os.path.exists(bmp_path) else None
    if new_bytes != old_bytes:
        with open(bmp_path, "wb") as fh:
            fh.write(new_bytes)
    elif verbose:
        print(f"  {bits}: identical bake, file left alone (mtime unchanged)")

    # round-trip: rebuild from the baked bands, count surviving voxels
    wall2vox.export(FAMILY, bits)
    rebuilt, _ = read_vox(vox_path)
    lost = sum(1 for k in voxels if k not in rebuilt)
    gained = sum(1 for k in rebuilt if k not in voxels)
    if verbose:
        fl = "  ".join(f"{k}={v}" for k, v in flags.items() if v)
        print(f"baked {bits}: {changed} band px changed; round-trip "
              f"{len(voxels)}->{len(rebuilt)} voxels "
              f"({lost} lost, {gained} regained by carve rules)"
              + (f"  FLAGS: {fl}" if fl else ""))
    return changed


def watch():
    print(f"watching {VOXDIR} — save from your editor to bake (ctrl-c to stop)")
    seen = {}
    while True:
        for f in sorted(os.listdir(VOXDIR)) if os.path.isdir(VOXDIR) else []:
            if not (f.startswith(FAMILY + "-") and f.endswith(".vox")):
                continue
            p = f"{VOXDIR}/{f}"
            m = os.path.getmtime(p)
            if seen.get(p) is None:
                seen[p] = m       # first sighting: baseline, don't bake
                continue
            if m != seen[p]:
                seen[p] = m
                bake(f[len(FAMILY) + 1:-4])
        time.sleep(1)


def selftest():
    """Mock the file shapes real editors save and prove read_vox decodes
    them all identically: plain (our writer), scene-graph (MagicaVoxel /
    vengi wrap the model in nTRN/nGRP/nSHP and add MATL/LAYR chunks — the
    reader must SKIP by chunk size without desyncing), reordered palette
    (editors rewrite palette order; only index->RGBA fidelity matters),
    and a version-200 header. What a mock cannot prove: an editor that
    re-origins XYZI coordinates — confirm with one real save per editor."""
    import struct
    import tempfile

    cells = wall2vox.cells_for_bits("00100010")
    vt = wall2vox.variant_fn(FAMILY)
    v, _e, farts, cap_art = voxwall.build_cell(vt, cells, (0, 0), FAMILY)
    colors = wall2vox.voxel_colors(v, cap_art, farts)
    with tempfile.TemporaryDirectory() as td:
        plain = f"{td}/plain.vox"
        wall2vox.write_vox(plain, (v.W, v.W, v.R), colors)
        want, dims = read_vox(plain)
        raw = open(plain, "rb").read()

        def chunk(cid, content, children=b""):
            return cid + struct.pack("<ii", len(content), len(children)) \
                + content + children

        def vdict(pairs):
            out = struct.pack("<i", len(pairs))
            for k, val in pairs:
                out += struct.pack("<i", len(k)) + k
                out += struct.pack("<i", len(val)) + val
            return out

        # scene-graph mock: same SIZE/XYZI/RGBA plus the wrapper chunks
        body = raw[8:]
        main_len = struct.unpack_from("<ii", body, 4)[1]
        children = body[12:12 + main_len]
        extra = (
            chunk(b"nTRN", struct.pack("<i", 0) + vdict([(b"_name", b"wall")])
                  + struct.pack("<iiii", 1, -1, 0, 1)
                  + vdict([(b"_t", b"0 0 0")]))
            + chunk(b"nGRP", struct.pack("<ii", 1, 0) + struct.pack("<i", 2))
            + chunk(b"nSHP", struct.pack("<i", 2) + vdict([])
                    + struct.pack("<ii", 1, 0) + vdict([]))
            + chunk(b"MATL", struct.pack("<i", 1)
                    + vdict([(b"_type", b"_diffuse")]))
            + chunk(b"LAYR", struct.pack("<i", 0) + vdict([]) + struct.pack("<i", -1))
        )
        scene = f"{td}/scene.vox"
        open(scene, "wb").write(
            b"VOX " + struct.pack("<i", 150) + chunk(b"MAIN", b"", children + extra))

        # reordered-palette mock: shift every colour 50 slots up
        vox2, _ = read_vox(plain)
        pal = {}
        voxels = []
        for (x, y, z), rgb in sorted(vox2.items()):
            if rgb not in pal:
                pal[rgb] = len(pal) + 51   # 1-based, offset 50
            voxels.append((x, y, z, pal[rgb]))
        rgba = bytearray(b"\x00\x00\x00\xff" * 256)
        for rgb, idx in pal.items():
            rgba[(idx - 1) * 4:(idx - 1) * 4 + 3] = bytes(rgb)
        shifted = f"{td}/shifted.vox"
        open(shifted, "wb").write(
            b"VOX " + struct.pack("<i", 150) + chunk(b"MAIN", b"", chunk(
                b"SIZE", struct.pack("<iii", *dims))
                + chunk(b"XYZI", struct.pack("<i", len(voxels))
                        + b"".join(struct.pack("<BBBB", *vx) for vx in voxels))
                + chunk(b"RGBA", bytes(rgba))))

        # version-200 mock
        v200 = f"{td}/v200.vox"
        open(v200, "wb").write(b"VOX " + struct.pack("<i", 200) + raw[8:])

        for name, p in (("scene-graph", scene), ("reordered-palette", shifted),
                        ("version-200", v200)):
            got, gdims = read_vox(p)
            assert gdims == dims, f"{name}: dims {gdims} != {dims}"
            assert got == want, f"{name}: {len(got)} voxels decode differently"
            print(f"selftest {name}: OK ({len(got)} voxels identical)")
    print("selftest: reader handles all mocked editor file shapes")


def seed(bits):
    """Copy a family's STOCK tile into tiles_custom so there is something to bake into.

    A family that has never been customised has no tiles_custom file, and bake() refuses to
    invent one -- deliberately, because the bake works by DIFFING the voxels against a volume
    rebuilt from the current art, and with no art there is no baseline to diff against. Seeding
    with the stock tile makes the first bake mean "here is what changed from vanilla", which is
    the same thing every later bake means.
    """
    base, ext = wall2vox.family_base(FAMILY)
    src = f"{wall2vox.TILES}/{base}-{bits}{ext}"
    dst = f"{CUSTOM}/{base}-{bits}{ext}"
    if not os.path.exists(src):
        sys.exit(f"no stock tile to seed from: {src}")
    if os.path.exists(dst):
        print(f"already customised: {dst}")
        return dst
    os.makedirs(CUSTOM, exist_ok=True)
    Image.open(src).convert("RGBA").save(dst, format="PNG")   # the .bmp extension lies
    print(f"seeded {dst} from stock")
    return dst


def main():
    global FAMILY
    if "--family" in sys.argv:
        FAMILY = sys.argv[sys.argv.index("--family") + 1]
    if "--seed" in sys.argv:
        args = [a for a in sys.argv[1:] if not a.startswith("--")]
        # --family consumes the token after it; --seed takes the LAST bare arg
        seed(args[-1])
        return
    if "--watch" in sys.argv:
        watch()
        return
    if "--selftest" in sys.argv:
        selftest()
        return
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if FAMILY in args:
        args.remove(FAMILY)
    if not args:
        sys.exit("usage: vox2wall.py [--family F] <bits> | --seed <bits> | --watch | --selftest")
    bake(args[0])


if __name__ == "__main__":
    main()
