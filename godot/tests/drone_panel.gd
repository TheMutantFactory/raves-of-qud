extends Node

## THE SHOT LIST AS A PANEL — rows, the bin, the drag, the checkbox — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/drone_panel.tscn
##
## WHY IT EXISTS, separately from drone_rig. That file tests the arithmetic; this one tests that
## the panel actually CALLS it and rebuilds afterwards. The failure it is aimed at is the one the
## Locations panel already shipped once: a path that edits the data and forgets the tail, so the
## list on screen and the list in memory disagree and only a screenshot shows it.

var _failed: Array[String] = []


func _ready() -> void:
	var panel = load("res://DronePanel.gd").new()
	# BEFORE add_child, so _ready's own load/save cannot touch the real settings file.
	panel.persist = false
	add_child(panel)
	panel.set_expanded(true)
	# THE FIXTURE OWNS THE SAVED STATE. _ready loads points and the invert flag from Settings, so
	# on a machine that has used the panel this test would start with somebody's real shot list.
	panel._points = []
	panel._t = 0.0
	panel._invert = false
	panel._rebuild()

	var emitted: Array = []
	panel.points_changed.connect(func(p: Array) -> void: emitted.assign(p))

	_check("starts empty", _rows(panel).is_empty())
	_check("...and says so", panel._empty.visible)

	panel.add_point(Vector3i(0, 4, 0), Vector3i(0, 0, 0), 1.0)
	panel.add_point(Vector3i(9, 4, 0), Vector3i(9, 0, 0), 1.0)
	panel.add_point(Vector3i(9, 8, 6), Vector3i(4, 0, 6), 2.0)
	_check("a shot per + press", _rows(panel).size() == 3, "%d rows" % _rows(panel).size())
	_check("the empty note goes away", not panel._empty.visible)
	_check("adding announces the new path", emitted.size() == 3, "%d emitted" % emitted.size())
	_check("shots are named, not numbered", _name(panel, 0) == "shot 1", _name(panel, 0))

	# ── the bin ───────────────────────────────────────────────────────────────
	panel.remove_point(1)
	_check("the bin removes its own row", _rows(panel).size() == 2, "%d rows" % _rows(panel).size())
	_check("...and it removes the RIGHT one",
		_name(panel, 0) == "shot 1" and _name(panel, 1) == "shot 3",
		"%s, %s" % [_name(panel, 0), _name(panel, 1)])

	# ── drag to reorder ───────────────────────────────────────────────────────
	panel.move_point(0, 1)
	_check("a drag reorders the rows",
		_name(panel, 0) == "shot 3" and _name(panel, 1) == "shot 1",
		"%s, %s" % [_name(panel, 0), _name(panel, 1)])
	# THE ROWS ARE REBUILT, not just the array — this is the tail the Locations panel once skipped.
	_check("the rebuilt rows match the data",
		_rows(panel).size() == panel.points().size())

	# ── scrolling, and the checkbox that reverses it ──────────────────────────
	panel._t = 0.0
	panel._invert = false
	var t1: float = panel.scroll_by(1.0)
	_check("a notch moves the playhead forward", t1 > 0.0, str(t1))
	panel._t = 1.0
	panel._invert = true
	var t2: float = panel.scroll_by(1.0)
	_check("inverted, the same notch goes back", t2 < 1.0, str(t2))
	# A CHECKBOX THAT ONLY CHANGES A LABEL IS THE FAILURE HERE: assert on the playhead, not on
	# the box's own pressed state, which is true either way.
	_check("invert actually reverses, not merely toggles",
		is_equal_approx(t1, 0.25) and is_equal_approx(t2, 0.75), "%s / %s" % [t1, t2])

	# ── the playhead is visible in the list ───────────────────────────────────
	panel._invert = false
	panel._t = 0.0
	panel._paint_playhead()
	_check("the shot under the playhead is lit",
		_lit(panel, 0) and not _lit(panel, 1), "row0 lit=%s row1 lit=%s" % [_lit(panel, 0), _lit(panel, 1)])

	# ── settings round-trip, which is where the vectors nearly died ───────────
	# Settings goes through JSON and JSON has no Vector3i: a saved shot comes back as three
	# numbers in an array. If _load_points did not rebuild them, every restored shot would point
	# the drone at (0,0,0) — and only after a restart, which is the worst time to find out.
	var saved := [{"name": "x", "drone": [3, 4, 5], "target": [1, 0, 2], "zoom": 1.5}]
	# set_value alone is memory-only — Settings.save() is what writes the file, and this test
	# never calls it. The read below is the whole point: JSON has no Vector3i.
	Settings.set_value(panel.POINTS_KEY, saved)
	var back: Array = panel._load_points()
	_check("a saved shot comes back as vectors",
		back.size() == 1 and back[0]["drone"] == Vector3i(3, 4, 5)
			and back[0]["target"] == Vector3i(1, 0, 2),
		str(back))
	_check("...with its zoom", is_equal_approx(float(back[0]["zoom"]), 1.5))

	_report()


func _rows(panel) -> Array:
	var out: Array = []
	for c in panel._rows.get_children():
		if c is HBoxContainer:
			out.append(c)
	return out


func _name(panel, i: int) -> String:
	var rows := _rows(panel)
	if i >= rows.size():
		return "<none>"
	var l: Label = rows[i].get_node_or_null("Name")
	return l.text if l != null else "<no label>"


func _lit(panel, i: int) -> bool:
	var rows := _rows(panel)
	if i >= rows.size():
		return false
	var l: Label = rows[i].get_node_or_null("Name")
	return l != null and l.get_theme_color("font_color").a > 0.9


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
