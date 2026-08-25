#!/usr/bin/env python3
"""ROW-PROFILE a chargen screen, Qud's capture against Raves', so layout fractions are
MEASURED rather than eyeballed — the method ChargenCardScreen's layout notes describe
("comparing bands of lit rows between the two screenshots, because 'the title looks a bit
low' is how a layout constant ends up carrying a guess").

    parity_rows.py QUD.png RAVES.png [--cols x0 x1]

Prints each image's ink BANDS (contiguous runs of rows carrying ink) as start-end rows and
as fractions of the content height, then pairs them up and reports the delta in pixels and
in fractions — the number to add to the offending _y_* hook.

Daniel's captures carry a window frame; the content rect is detected by trimming the border
rather than assumed, so a capture taken another way still lines up.
"""
import sys
from PIL import Image

BG_MAX = 90          # a pixel this dark on every channel is background, not ink
INK_MIN_PER_ROW = 3  # rows with fewer lit pixels than this are blank (kills stray dust)


def content_rect(im):
    """Trim a window FRAME — a uniform border whose colour is NOT the screen's background.

    Trimming every uniform border would eat a frameless screenshot's own empty rows (Raves'
    captures are full-bleed), which silently shortens the image and throws every fraction
    off. So the background colour is sampled from the middle first, and only borders that
    differ from it are frame.
    """
    w, h = im.size
    px = im.load()
    bg = px[w // 2, h // 2]
    from collections import Counter
    c = Counter(px[x, y] for y in range(h // 4, h * 3 // 4, 11)
                for x in range(w // 4, w * 3 // 4, 11))
    if c:
        bg = c.most_common(1)[0][0]
    def near_bg(p):
        return all(abs(p[i] - bg[i]) <= 12 for i in range(3))
    def row_frame(y):
        first = px[0, y]
        if near_bg(first):
            return False
        return all(px[x, y] == first for x in range(0, w, 7))
    def col_frame(x):
        first = px[x, 0]
        if near_bg(first):
            return False
        return all(px[x, y] == first for y in range(0, h, 7))
    top = 0
    while top < h // 4 and row_frame(top):
        top += 1
    bot = h - 1
    while bot > h * 3 // 4 and row_frame(bot):
        bot -= 1
    left = 0
    while left < w // 4 and col_frame(left):
        left += 1
    right = w - 1
    while right > w * 3 // 4 and col_frame(right):
        right -= 1
    return left, top, right + 1, bot + 1


def bands(path, cols=None):
    im = Image.open(path).convert("RGB")
    x0, y0, x1, y1 = content_rect(im)
    im = im.crop((x0, y0, x1, y1))
    w, h = im.size
    px = im.load()
    cx0, cx1 = (cols if cols else (0, w))
    cx0 = max(0, min(cx0, w)); cx1 = max(cx0 + 1, min(cx1, w))
    lit = []
    for y in range(h):
        n = 0
        for x in range(cx0, cx1, 2):
            r, g, b = px[x, y]
            if r > BG_MAX or g > BG_MAX or b > BG_MAX:
                n += 1
        lit.append(n)
    out = []
    y = 0
    while y < h:
        if lit[y] >= INK_MIN_PER_ROW:
            s = y
            while y < h and lit[y] >= INK_MIN_PER_ROW:
                y += 1
            out.append((s, y - 1))
        else:
            y += 1
    return out, (w, h)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    cols = None
    if "--cols" in argv:
        i = argv.index("--cols")
        cols = (int(argv[i + 1]), int(argv[i + 2]))
        argv = argv[:i] + argv[i + 3:]
    qb, (qw, qh) = bands(argv[1], cols)
    rb, (rw, rh) = bands(argv[2], cols)
    print("QUD   content %dx%d — %d bands" % (qw, qh, len(qb)))
    for s, e in qb:
        print("   rows %4d-%4d   y=%.4f..%.4f" % (s, e, s / qh, e / qh))
    print("RAVES content %dx%d — %d bands" % (rw, rh, len(rb)))
    for s, e in rb:
        print("   rows %4d-%4d   y=%.4f..%.4f" % (s, e, s / rh, e / rh))
    # PAIR BY PROXIMITY, not by index: the two screens rarely split their ink into the same
    # NUMBER of bands (one wraps a line, the other does not), and an in-order pairing then
    # reports every band after the first mismatch as wildly off — noise that hides the real
    # deltas. Each Qud band takes the nearest unclaimed Raves band within TOL, and anything
    # left over is named rather than silently paired.
    TOL = 70
    used = set()
    print("\nPAIRED by proximity (tolerance %dpx):" % TOL)
    for i, (qs, qe) in enumerate(qb):
        want = qs * rh / qh
        best, bestd = -1, 1e9
        for jj, (rs, _re) in enumerate(rb):
            if jj in used:
                continue
            d = abs(rs - want)
            if d < bestd:
                best, bestd = jj, d
        if best < 0 or bestd > TOL:
            print("   qud %4d-%4d  ->  (no Raves band within %dpx)" % (qs, qe, TOL))
            continue
        used.add(best)
        rs, re = rb[best]
        dpx = rs - want
        print("   qud %4d-%4d  raves %4d-%4d   delta %+.1fpx  %+.4f of height"
              % (qs, qe, rs, re, dpx, dpx / rh))
    for jj, (rs, re) in enumerate(rb):
        if jj not in used:
            print("   (extra Raves band %4d-%4d  y=%.4f — nothing in Qud near it)"
                  % (rs, re, rs / rh))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
