#!/usr/bin/env python3
"""A SETTING MUST REACH THE THING IT CONTROLS.

THE SEAM THIS CLOSES
--------------------
Three bugs in one session, all the same shape: the value was stored perfectly and the thing it
controls was never told.

  - a QoL row read `get_value(key, false)` whatever the feature shipped as, so a default-ON
    feature drew unchecked and the first click "turned it on" to the value it already had
  - the firelight gate was read during the relight, which runs once per snapshot, so throwing
    the switch and looking at an unchanged world WAS the experience of using it
  - a feature owning a panel's shape reached the panel only when the master 1:1 switch moved or
    at launch, so the minimap stayed Qud's until the next restart

Daniel found every one of them by using a control and seeing nothing happen. None of them looked
broken in the code: each read the right key and each was gated correctly. What none of them had
was a path from "the value changed" to "the thing changed".

WHAT THIS REPORTS
-----------------
For every key the options screen can write, where it is READ, and how soon that read happens:

  LIVE      read per frame (_process/_input) or applied by Settings.apply_global
  PER-TURN  read while a snapshot is rendered — takes effect on the next step
  ON BUILD  read only while geometry/panels are built — takes effect on the next zone or restart
  DEAD      written by the options screen and read by nothing at all

DEAD is a hard failure: a switch that gates nothing. ON BUILD is reported, not failed — plenty of
settings legitimately apply at build time (they change geometry), and the question this audit
exists to raise is whether the user is told, not whether the code is wrong. The three bugs above
would have shown up here as ON BUILD on a control that looks instant.
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "godot")
LIVE_FUNCS = {"_process", "_physics_process", "_input", "_unhandled_input", "_gui_input", "_draw"}
# The gates themselves. Reading `feature` inside qol_on/qud_shape is the definition of the
# question, not an answer to it — but apply_global asking qud_shape("titlebar") IS a real read,
# and excluding the whole of Settings.gd to skip the former reported the latter as dead.
GATE_FUNCS = {"qol_on", "qud_shape", "clone_of_qud", "_fx_on"}
# HAND-MAINTAINED, and it has to be: these are the functions an options change actually calls, and
# no amount of regex infers that from the source. Without them every setting with a working live
# path (the minimap source, the cutaway radius, the walk rate, the panel features) is reported as
# needing a restart, and a report that cries wolf on two dozen healthy settings gets ignored —
# which is how the three real ones would be missed again.
ON_CHANGE_FUNCS = {"apply_global", "apply_cutaway", "_set_panels_one_to_one", "_rerender",
                   "_toggle_mode", "_refresh_toggle", "_walk_step", "_hold_step",
                   "set_camera_mode", "_apply_flat_2d", "_relight_now", "_refresh_crt", "refresh_fog_setting"}
TURN_FUNCS = {"render_snapshot", "set_snapshot", "_on_snapshot", "_rebuild_dynamics",
              "_relight_static_sprites", "_relight_now", "_build_darkness", "_live_cell_tone",
              "_refresh_fx_flags", "_apply_fx_flags", "_shape_pools", "set_daylight"}


def gd_files():
    for dirpath, _dirs, files in os.walk(ROOT):
        if os.sep + "tests" in dirpath:
            continue
        for f in sorted(files):
            if f.endswith(".gd"):
                yield os.path.join(dirpath, f)


def call_graph(files):
    """Who calls whom, one entry per file:func. Shallow and good enough: a read sitting in a
    helper is as live as the thing that calls it, and matching function NAMES against a hand-list
    reported _smoke_on (called every turn from set_daylight) and _sync_neighbors (called from
    render_snapshot) as build-time. A list of names cannot know that; the call graph can."""
    callers = {}
    for path in files:
        lines = open(path, encoding="utf-8").read().split("\n")
        for i, ln in enumerate(lines):
            here = func_at(lines, i)
            # METHOD CALLS COUNT. Excluding `.`-preceded names dropped `_cam_rig.process(...)`
            # and every other call through an object — which is most of them — and left half the
            # codebase looking like it called nothing.
            for callee in re.findall(r'(?<![A-Za-z_0-9"])([A-Za-z_][A-Za-z_0-9]*)\s*\(', ln):
                callers.setdefault(callee, set()).add(here)
    return callers


def reaches(fn, roots, callers, depth=4):
    """Is `fn` called, within `depth` hops, from any of `roots`?"""
    seen, frontier = set(), {fn}
    for _ in range(depth):
        nxt = set()
        for f in frontier:
            if f in roots:
                return True
            for up in callers.get(f, ()):  # who calls f
                if up not in seen:
                    seen.add(up)
                    nxt.add(up)
        frontier = nxt
        if not frontier:
            break
    return bool(frontier & roots)


def func_at(lines, idx):
    """The function a line sits in — the nearest `func` above it."""
    for i in range(idx, -1, -1):
        m = re.match(r"^func\s+([A-Za-z_0-9]+)", lines[i])
        if m:
            return m.group(1)
    return "(top level)"


def main():
    settings = os.path.join(ROOT, "Settings.gd")
    src = open(settings, encoding="utf-8").read()

    # every key the options screen can write: DEFAULTS, the qol_ features, and OptionsScreen's rows
    qol = re.search(r"const QOL_FEATURES := \{(.*?)\n\}", src, re.S)
    feats = set(re.findall(r'^\t"([a-z0-9_]+)":', qol.group(1), re.M)) if qol else set()
    # DEFAULTS only — the QOL_FEATURES block sits in the same file and matches the same pattern,
    # and counting its FEATURE names as setting keys reported all twenty of them "read by nothing"
    # while their qol_ keys were read perfectly well. An audit's first duty is not to invent work.
    dflt = re.search(r"const DEFAULTS := \{(.*?)\n\}", src, re.S)
    keys = set(re.findall(r'^\t"([a-z0-9_]+)":', dflt.group(1), re.M)) if dflt else set()
    opts = open(os.path.join(ROOT, "OptionsScreen.gd"), encoding="utf-8").read()
    keys |= set(re.findall(r'\{"key": "([a-z0-9_]+)"', opts))
    keys -= {"mode"}                      # written by the mode switch itself, not a control
    applied_live = set(re.findall(r'get_value\("([a-z0-9_]+)"',
                                  re.search(r"func apply_global.*?(?=\nfunc )", src, re.S).group(0)))

    reads = {k: [] for k in keys}
    freads = {f: [] for f in feats}
    for path in gd_files():
        name = os.path.basename(path)
        text = open(path, encoding="utf-8").read()
        lines = text.split("\n")
        # A KEY IS OFTEN A CONSTANT, not a literal at the call site: MinimapView reads
        # get_value(SRC_KEY, ...), and a literal-only scan calls minimap_source dead.
        consts = dict(re.findall(r'^(?:const|var)\s+([A-Z_0-9]+)\s*:?=\s*"([a-z0-9_]+)"',
                                 text, re.M))
        # ...and a FEATURE is often a variable: MainFrame gates panels on qud_shape(feat), where
        # feat came from _panel_feature. Those sites are where the feature is really read, so
        # attribute every feature named as a literal in this file to this file's dynamic gates.
        dynamic = []
        for i, ln in enumerate(lines):
            if re.search(r'(?:qol_on|qud_shape|_fx_on)\(\s*(?!")[A-Za-z_]', ln):
                dynamic.append((name, func_at(lines, i)))
        for i, ln in enumerate(lines):
            for k in re.findall(r'get_value\("([a-z0-9_]+)"', ln):
                if k in reads and name != "OptionsScreen.gd":
                    reads[k].append((name, func_at(lines, i)))
            for cname in re.findall(r'get_value\(([A-Z_0-9]+)\s*,', ln):
                k = consts.get(cname)
                if k in reads and name != "OptionsScreen.gd":
                    reads[k].append((name, func_at(lines, i)))
            for f in re.findall(r'(?:qol_on|qud_shape|_fx_on)\("([a-z0-9_]+)"\)', ln):
                if f in freads and name != "OptionsScreen.gd" \
                        and func_at(lines, i) not in GATE_FUNCS:
                    freads[f].append((name, func_at(lines, i)))
        dynamic = [d for d in dynamic if d[1] not in GATE_FUNCS]
        if dynamic and name not in ("OptionsScreen.gd", "Settings.gd"):
            for f in feats:
                if re.search(r'"%s"' % re.escape(f), text):
                    freads[f].extend(dynamic)

    callers = call_graph(list(gd_files()))

    def verdict(sites, key):
        if key in applied_live:
            return "LIVE"
        if not sites:
            return "DEAD"
        fns = {f for _n, f in sites}
        if fns & LIVE_FUNCS or any(reaches(f, LIVE_FUNCS, callers) for f in fns):
            return "LIVE"
        if fns & TURN_FUNCS or any(reaches(f, TURN_FUNCS, callers) for f in fns):
            return "PER-TURN"
        if fns & ON_CHANGE_FUNCS or any(reaches(f, ON_CHANGE_FUNCS, callers) for f in fns):
            return "ON CHANGE"
        return "ON BUILD"

    rows = []
    for k in sorted(keys):
        if k.startswith("qol_"):
            continue                       # the features are listed once, below
        rows.append((verdict(reads[k], k), k, reads[k]))
    for f in sorted(feats):
        rows.append((verdict(freads[f], "qol_" + f), "qol_" + f, freads[f]))

    seen = set()
    out = []
    for v, k, sites in rows:
        if k in seen:
            continue
        seen.add(k)
        out.append((v, k, sites))

    dead = [r for r in out if r[0] == "DEAD"]
    build = [r for r in out if r[0] == "ON BUILD"]
    for label in ("DEAD", "ON BUILD", "ON CHANGE", "PER-TURN", "LIVE"):
        group = [r for r in out if r[0] == label]
        if not group:
            continue
        print("\n%s (%d)" % (label, len(group)))
        for _v, k, sites in group:
            where = ", ".join(sorted({"%s:%s" % s for s in sites})[:3]) or "read by nothing"
            print("   %-26s %s" % (k, where))

    print()
    if dead:
        print("FAIL: %d setting(s) the options screen writes and nothing reads:" % len(dead))
        for _v, k, _s in dead:
            print("    %s" % k)
        return 1
    print("settings_reach: every option the screen writes is read somewhere "
          "(%d live, %d on change, %d per-turn, %d on build)"
          % (sum(1 for r in out if r[0] == "LIVE"), sum(1 for r in out if r[0] == "ON CHANGE"),
             sum(1 for r in out if r[0] == "PER-TURN"), len(build)))
    if build:
        print("      the ON BUILD ones take effect on the next zone or restart — check that each")
        print("      is a setting whose control does not look instant.")
    return 0


sys.exit(main())
