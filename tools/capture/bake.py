#!/usr/bin/env python3
"""Bake Qud zones into compact chunk files for 2Caves2Qud's overland mode
(see 2Caves2Qud/docs/overland.md; the mod side is mod/BakeExporter.cs).

    bake.py --center 11.22 --radius 1        # the 3x3 parasangs round Joppa: 81 surface zones
    bake.py --parasangs 11.22,12.22          # named parasangs
    bake.py --zones JoppaWorld.11.22.1.1.10  # named zones
    bake.py --force ...                      # re-bake zones whose chunk file already exists

Needs Qud IN-GAME with the bridge up (any save: the world is that game's). Nothing moves
the player; ZoneManager.GetZone builds each zone into the cache and the mod releases it.

PACED BY CONFIRMATION, NOT TIMERS (stations.py's lesson: zone generation takes as long as
it takes, and a burst of requests on a guessed sleep deadlocked Qud). One parasang goes out
per request; the next goes out when its nine chunk files exist, or the ceiling passes. The
bridge connection tends to drop while zones build; the request is already server-side, so
the poll carries on and reconnects for the next one.

Writes reports/bake-<stamp>.md (per-zone ms / bytes / objects from the mod's own log lines
in Player.log, the failures, the throughput) — the bake is a re-runnable script with a
report, so a second run on another day compares.
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import control
import plat

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REPORTS = os.path.join(REPO, "reports")
LOG_LINE = re.compile(r"\[raves\] bake: (\S+) (ok|FAILED) (\d+)ms(?: (\d+)B objs=(\d+))?(.*)")


def player_log():
    """Qud's Player.log (Unity's persistentDataPath on this OS)."""
    if sys.platform.startswith("win"):
        return os.path.join(plat.qud_data_dir(), "Player.log")
    return os.path.expanduser("~/Library/Logs/Freehold Games/CavesOfQud/Player.log")


def zone_list(args):
    zones = []
    if args.zones:
        zones = [z.strip() for z in args.zones.split(",") if z.strip()]
    paras = []
    if args.parasangs:
        for p in args.parasangs.split(","):
            wx, wy = p.strip().split(".")
            paras.append((int(wx), int(wy)))
    if args.center:
        cx, cy = (int(v) for v in args.center.split("."))
        r = args.radius
        for wy in range(cy - r, cy + r + 1):
            for wx in range(cx - r, cx + r + 1):
                if 0 <= wx < 80 and 0 <= wy < 25:
                    paras.append((wx, wy))
    for (wx, wy) in paras:
        for zy in range(3):
            for zx in range(3):
                zones.append("JoppaWorld.%d.%d.%d.%d.%d" % (wx, wy, zx, zy, args.z))
    seen = set()
    return [z for z in zones if not (z in seen or seen.add(z))]


def connect(tries=30):
    last = None
    for _ in range(tries):
        try:
            return control.Bridge(timeout=10)
        except OSError as e:
            last = e
            time.sleep(1.0)
    raise SystemExit("no bridge on 127.0.0.1:%d (%s) — is Qud in-game with the mod?" % (control.PORT, last))


def game_id(b, timeout=45):
    """The live game's id from a snapshot. A freshly loaded save sits on a MESSAGE popup
    (Joppa's arrival text) that parks the turn thread, so no snapshot comes until it is
    answered: dismiss message popups on the way (the bridge announces them as `popup`
    frames and answers only those)."""
    b.send("wait")
    t0 = time.time()
    popup_up = False
    snap = None
    while time.time() - t0 < timeout:
        d = _read_any(b, timeout - (time.time() - t0))
        if d is None:
            break
        if d.get("type") == "popup":
            popup_up = bool(d.get("active", True))
            if popup_up and (d.get("kind") == "message" or d.get("options") == []):
                print("bake: dismissing popup %s (%s)" % (d.get("id"), str(d.get("message", ""))[:60].replace("\n", " ")))
                b.send("popup", action="button", btn="Accept", id=str(d.get("id", "")))
                b.send("wait")
            continue
        if d.get("type") == "snapshot":
            snap = d
        # a snapshot can arrive while the popup is still closing; the bridge REFUSES a bake
        # sent then ("Qud is on PopupMessage"). Proceed only once the popup has reported
        # itself inactive (or never existed), then let the view settle.
        if snap is not None and not popup_up:
            gid = snap.get("gameId", "")
            if not gid:
                raise SystemExit("the snapshot carries no gameId (mod build %s)" % snap.get("mod"))
            time.sleep(1.5)
            return gid, snap
    raise SystemExit("no snapshot within %ds — is a game loaded, and no popup up that this cannot answer?" % timeout)


def _read_any(b, timeout):
    """The next framed message of ANY type (control.Bridge.read_frame filters by kind)."""
    import json as _json
    import socket as _socket
    import struct as _struct
    deadline = time.time() + timeout
    while True:
        while len(b.buf) >= 4:
            n = _struct.unpack(">I", b.buf[:4])[0]
            if len(b.buf) < 4 + n:
                break
            body, b.buf = b.buf[4:4 + n], b.buf[4 + n:]
            return _json.loads(body.decode("utf-8", "replace"))
        left = deadline - time.time()
        if left <= 0:
            return None
        b.sock.settimeout(max(0.05, min(left, 1.0)))
        try:
            chunk = b.sock.recv(65536)
        except _socket.timeout:
            continue
        if not chunk:
            raise ConnectionError("bridge closed")
        b.buf += chunk


def wait_files(paths, ceiling, poll=0.5, kick=None, kick_every=4.0):
    """Block until every path exists, or the ceiling passes. `kick` is a bridge to send a
    `wait` on every `kick_every` seconds (see main: the turn kick that applies commands)."""
    t0 = time.time()
    last_kick = time.time()
    while time.time() - t0 < ceiling:
        if all(os.path.exists(p) for p in paths):
            return True
        if kick is not None and time.time() - last_kick >= kick_every:
            last_kick = time.time()
            try:
                kick.send("wait")
            except OSError:
                pass
        time.sleep(poll)
    return False


def batches(zones, size):
    for i in range(0, len(zones), size):
        yield zones[i:i + size]


def read_log_lines(path, since_pos):
    out = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            f.seek(since_pos)
            for line in f:
                m = LOG_LINE.search(line)
                if m:
                    out.append(m)
    except OSError:
        pass
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--center", help="parasang wx.wy at the centre of a square region")
    ap.add_argument("--radius", type=int, default=1, help="parasangs each way from --center (1 = 3x3)")
    ap.add_argument("--parasangs", help="comma list of wx.wy")
    ap.add_argument("--zones", help="comma list of zone ids")
    ap.add_argument("--z", type=int, default=10, help="stratum (10 = surface)")
    ap.add_argument("--batch", type=int, default=9, help="zones per bridge request")
    ap.add_argument("--ceiling", type=float, default=300.0, help="seconds to wait for one batch's files")
    ap.add_argument("--force", action="store_true", help="re-bake zones whose chunk exists")
    ap.add_argument("--report", help="report path (default reports/bake-<stamp>.md)")
    args = ap.parse_args(argv)

    zones = zone_list(args)
    if not zones:
        ap.error("nothing to bake: give --center, --parasangs or --zones")

    b = connect()
    gid, snap = game_id(b)
    out_dir = os.path.join(plat.support_dir(), "chunks", gid)
    os.makedirs(out_dir, exist_ok=True)
    path_of = lambda z: os.path.join(out_dir, z + ".json")
    if args.force:
        for z in zones:
            if os.path.exists(path_of(z)):
                os.remove(path_of(z))
    todo = [z for z in zones if not os.path.exists(path_of(z))]
    print("bake: game %s (%s) mod %s -> %s" % (gid, snap.get("zone", {}).get("id", "?"), snap.get("mod", "?"), out_dir))
    print("bake: %d zones asked, %d already baked, %d to build" % (len(zones), len(zones) - len(todo), len(todo)))

    log_path = player_log()
    log_pos = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    t_start = time.time()
    batch_rows = []
    missing = []
    for batch in batches(todo, args.batch):
        t0 = time.time()
        try:
            b.send("bake", zones=",".join(batch))
        except OSError:
            b = connect()
            b.send("bake", zones=",".join(batch))
        # The bridge APPLIES commands on the turn thread (Bridge.TickAction / TickRender), and
        # an UNFOCUSED Qud renders no frames: a queued `bake` sat for two minutes doing nothing
        # until the window came forward. A `wait` is a turn kick (Keyboard.PushCommand from the
        # socket thread), which fires TickAction focused or not — so kick once after the request
        # and again every few seconds while polling (a Wander save; a turn costs nothing).
        b.send("wait")
        ok = wait_files([path_of(z) for z in batch], args.ceiling, kick=b)
        dt = time.time() - t0
        got = [z for z in batch if os.path.exists(path_of(z))]
        batch_rows.append((batch[0], batch[-1], len(got), len(batch), dt))
        missing += [z for z in batch if z not in got]
        print("bake: %s .. %s  %d/%d files in %.1fs%s" % (batch[0], batch[-1], len(got), len(batch), dt, "" if ok else "  CEILING"))
        # the socket often drops while zones build; make sure the next send has a live one
        try:
            b.sock.settimeout(0.2)
            b.send("wait")
        except OSError:
            b = connect()
    total = time.time() - t_start

    # the mod's own accounting, from Player.log
    rows = {}
    fails = []
    for m in read_log_lines(log_path, log_pos):
        zid, state, ms = m.group(1), m.group(2), int(m.group(3))
        if state == "ok":
            rows[zid] = (ms, int(m.group(4) or 0), int(m.group(5) or 0))
        else:
            fails.append((zid, ms, m.group(6).strip()))

    # what is on disk
    sizes = {}
    bad = []
    for z in zones:
        p = path_of(z)
        if not os.path.exists(p):
            continue
        sizes[z] = os.path.getsize(p)
        try:
            with open(p, encoding="utf-8") as f:
                d = json.load(f)
            if len(d.get("ground", [])) != d.get("w", 80) * d.get("h", 25):
                bad.append((z, "ground has %d cells" % len(d.get("ground", []))))
        except (OSError, ValueError) as e:
            bad.append((z, "unreadable: %s" % e))

    stamp = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")
    report = args.report or os.path.join(REPORTS, "bake-%s.md" % stamp)
    os.makedirs(os.path.dirname(report), exist_ok=True)
    built = [z for z in todo if z in sizes]
    with open(report, "w", encoding="utf-8") as f:
        f.write("# Bake %s\n\n" % stamp)
        f.write("game `%s`, mod %s, out `%s`\n\n" % (gid, snap.get("mod", "?"), out_dir))
        f.write("- asked %d zones, built %d, already had %d, missing %d, failed %d, bad files %d\n"
                % (len(zones), len(built), len(zones) - len(todo), len(missing), len(fails), len(bad)))
        f.write("- wall time %.1f s for %d zones = %.2f s/zone; %d batches of up to %d\n"
                % (total, len(todo), total / max(1, len(todo)), len(batch_rows), args.batch))
        if sizes:
            f.write("- chunk size min %d, mean %d, max %d bytes\n" % (min(sizes.values()), sum(sizes.values()) // len(sizes), max(sizes.values())))
        f.write("\n| zone | build ms | bytes | objects |\n|---|---|---|---|\n")
        for z in zones:
            if z in rows:
                ms, by, objs = rows[z]
                f.write("| %s | %d | %d | %d |\n" % (z, ms, by, objs))
            elif z in sizes:
                f.write("| %s | (earlier) | %d | |\n" % (z, sizes[z]))
            else:
                f.write("| %s | MISSING | | |\n" % z)
        if fails:
            f.write("\n## Failures\n\n")
            for zid, ms, why in fails:
                f.write("- %s after %d ms: %s\n" % (zid, ms, why))
        if bad:
            f.write("\n## Bad files\n\n")
            for z, why in bad:
                f.write("- %s: %s\n" % (z, why))
        f.write("\n## Batches\n\n| first | last | files | seconds |\n|---|---|---|---|\n")
        for a, z, n, k, dt in batch_rows:
            f.write("| %s | %s | %d/%d | %.1f |\n" % (a, z, n, k, dt))
    print("bake: %d built, %d missing, %d failed, %d bad; %.1f s; report %s" % (len(built), len(missing), len(fails), len(bad), total, report))
    return 0 if not (missing or fails or bad) else 1


if __name__ == "__main__":
    sys.exit(main())
