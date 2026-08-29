extends Node

## THE PANEL IS LOCKED UNDERGROUND, and comes back exactly as it was on the way up.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/locations_depth.tscn
##
## WHY IT EXISTS. Daniel: "Locations should be off in the subterranean. They should only be on when
## the user is on the surface." Every place the panel lists is a WORLD-MAP landmark measured in
## parasangs across the overworld, so underground the beacons would stand in a cave pointing through
## rock at a village overhead.
##
## The lock was NOT written fresh — Qud's Lost effect already suspended this panel the same way, so
## depth became a second reason for the one lock. That sharing is the thing most worth a test: two
## flags, one collapse, one restore. Handled per-flag, the second lock saves the first lock's
## collapsed state as the state to return to, and a player who went down a stair while lost comes
## back up to a panel shut for good — with nothing on screen to say why, and no way to reopen it.

var _failed: Array[String] = []

const SURFACE := 10


func _ready() -> void:
	var panel = load("res://LocationsPanel.gd").new()
	add_child(panel)
	panel.metrics_cb = func(mx: int, _my: int) -> Dictionary:
		return {"para": float(mx), "dir": "N"}
	panel._entries = [{"id": "a", "name": "near", "mx": 1, "my": 0, "category": "Ruins"}]
	panel._on = {"a": true}
	# THE FIXTURE OWNS THE PIN. _ready reads it from Settings, and this machine had it OFF — which
	# emptied _emit on every check, so "underground: no beacons" passed while proving nothing. A
	# test whose subject can be switched off by the tester's own saved preferences is not a test.
	panel._armed = true

	# ── the plain case: down, and back up ─────────────────────────────────────
	panel._expanded = true
	_snap(panel, SURFACE)
	_check("surface: open", panel.locked_reason() == "" and panel._expanded,
		"reason=%s expanded=%s" % [panel.locked_reason(), panel._expanded])
	_check("surface: beacons emit", _emitted(panel).size() == 1,
		"got %d" % _emitted(panel).size())

	_snap(panel, SURFACE + 1)
	_check("underground: locked", panel.locked_reason() == "underground",
		"reason=%s" % panel.locked_reason())
	_check("underground: collapsed", not panel._expanded, "still expanded")
	# THE POINT OF THE WHOLE CHANGE. Anything else here and the beacons are still standing.
	_check("underground: no beacons", _emitted(panel).is_empty(),
		"emitted %d" % _emitted(panel).size())
	_check("underground: the pin will not arm", panel.toggle_beacons() == panel._armed,
		"toggle_beacons flipped a locked panel")

	_snap(panel, SURFACE)
	_check("back up: unlocked", panel.locked_reason() == "", panel.locked_reason())
	_check("back up: reopened", panel._expanded, "stayed collapsed")
	_check("back up: beacons return", _emitted(panel).size() == 1,
		"got %d" % _emitted(panel).size())

	# ── one lock, two reasons ─────────────────────────────────────────────────
	# The bug a per-flag _pre_expanded would have: lost on the surface (collapse, remember OPEN),
	# then walk downstairs (collapse again — and remember CLOSED). Becoming found leaves the panel
	# shut, and coming up finds it shut too.
	panel._expanded = true
	_snap(panel, SURFACE, true)
	_check("lost: locked", panel.locked_reason() == "lost", panel.locked_reason())
	_snap(panel, SURFACE + 1, true)
	_check("lost underground: still says lost", panel.locked_reason() == "lost",
		"the stranger state should win: " + panel.locked_reason())
	_snap(panel, SURFACE + 1, false)
	_check("found, still deep: stays locked", panel.locked_reason() == "underground",
		panel.locked_reason())
	_check("found, still deep: stays collapsed", not panel._expanded, "reopened underground")
	_snap(panel, SURFACE, false)
	_check("out of both: reopened", panel._expanded and panel.locked_reason() == "",
		"expanded=%s reason=%s" % [panel._expanded, panel.locked_reason()])

	# ── the signal MainFrame dresses the nav pin from ──────────────────────────
	var seen: Array[String] = []
	panel.lock_changed.connect(func(r: String) -> void: seen.append(r))
	_snap(panel, SURFACE + 2)
	_snap(panel, SURFACE + 3)      # deeper is not a NEW lock; the pin must not be re-dressed
	_snap(panel, SURFACE)
	_check("lock_changed fires on the edges only", seen == ["underground", ""],
		str(seen))

	_report()


## One snapshot at a stratum. The panel reads zone.z — the same field SkyGrade and ZoneRenderer do.
func _snap(panel, z: int, lost := false) -> void:
	panel.set_snapshot({
		"zone": {"id": "JoppaWorld.11.22.1.0.%d" % z, "z": z},
		"player": {"x": 40, "y": 12, "lost": lost},
	})


## What the beacons were last told to stand. _emit is the only producer, so asking it directly is
## asking what Main would have been handed.
func _emitted(panel) -> Array:
	# MUTATE, DON'T REBIND. GDScript lambdas capture locals BY VALUE, so `out = t` sets the
	# closure's own copy and the caller sees an empty array every time — which reads exactly like
	# "the panel emitted nothing", the very thing this file is here to detect.
	var out: Array = []
	var c := func(t: Array) -> void: out.assign(t)
	panel.beacons_changed.connect(c)
	panel._emit()
	panel.beacons_changed.disconnect(c)
	return out


func _check(what: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		_failed.append(what)
		print("  FAIL %s%s" % [what, ("  (%s)" % detail) if detail != "" else ""])


func _report() -> void:
	if _failed.is_empty():
		print("all good (0 checks failed)")
	else:
		print("%d checks failed:" % _failed.size())
		for f in _failed:
			print("  - %s" % f)
	get_tree().quit(0 if _failed.is_empty() else 1)
