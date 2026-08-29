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
	panel._by_list = {"drone": {"points": [], "t": 0.0}, "look": {"points": [], "t": 0.0}}
	panel._list = "drone"
	panel._points = []
	panel._t = 0.0
	panel._invert = false
	panel._rebuild()

	var emitted: Array = []
	var emitted_list := [""]
	panel.points_changed.connect(func(l: String, p: Array) -> void:
		emitted_list[0] = l
		emitted.assign(p))

	_check("starts empty", _rows(panel).is_empty())
	_check("...and says so", panel._empty.visible)

	panel.add_point(Vector3i(0, 4, 0), Vector3i(0, 0, 0), 1.0)
	panel.add_point(Vector3i(9, 4, 0), Vector3i(9, 0, 0), 1.0)
	panel.add_point(Vector3i(9, 8, 6), Vector3i(4, 0, 6), 2.0)
	_check("a shot per + press", _rows(panel).size() == 3, "%d rows" % _rows(panel).size())
	_check("the empty note goes away", not panel._empty.visible)
	_check("adding announces the new path", emitted.size() == 3, "%d emitted" % emitted.size())
	_check("...and says which list it was", emitted_list[0] == "drone", emitted_list[0])
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
	# set_value alone is memory-only — Settings.save() is what writes the file, and this test
	# never calls it.
	Settings.set_value(panel.POINTS_KEY, {
		"drone": [{"name": "x", "drone": [3, 4, 5], "target": [1, 0, 2], "zoom": 1.5}],
		"look": [{"name": "y", "drone": [7, 1, 2], "target": [0, 0, 1], "zoom": 1.0}],
	})
	var back: Dictionary = panel._load_points()
	var dl: Array = back["drone"]["points"]
	_check("a saved shot comes back as vectors",
		dl.size() == 1 and dl[0]["drone"] == Vector3i(3, 4, 5)
			and dl[0]["target"] == Vector3i(1, 0, 2),
		str(dl))
	_check("...with its zoom", is_equal_approx(float(dl[0]["zoom"]), 1.5))
	_check("...and the look list loads beside it",
		back["look"]["points"].size() == 1
			and back["look"]["points"][0]["drone"] == Vector3i(7, 1, 2),
		str(back["look"]["points"]))
	# THE OLD ONE-LIST SHAPE. This file shipped a bare Array for a day; it is read as the drone's
	# so an early saved list is not silently dropped on upgrade.
	Settings.set_value(panel.POINTS_KEY,
		[{"name": "old", "drone": [1, 1, 1], "target": [2, 2, 2], "zoom": 1.0}])
	var legacy: Dictionary = panel._load_points()
	_check("a list saved in the old flat shape becomes the drone's",
		legacy["drone"]["points"].size() == 1 and legacy["look"]["points"].is_empty(),
		str(legacy))

	# ── the second list ───────────────────────────────────────────────────────
	# Daniel: "Create a separate look mode list of views." SEPARATE is the claim under test — a
	# list that came back holding the other one's shots, or scrubbed to the other one's playhead,
	# is one list wearing two names.
	panel._t = 0.75
	var drone_names := [_name(panel, 0), _name(panel, 1)]
	panel.set_list("look")
	_check("look mode starts with its own empty list", _rows(panel).is_empty(),
		"%d rows" % _rows(panel).size())
	_check("...and its own playhead", is_equal_approx(panel.scrub_t(), 0.0), str(panel.scrub_t()))
	_check("the swap announces the list it moved to", emitted_list[0] == "look", emitted_list[0])

	panel.add_point(Vector3i(1, 2, 3), Vector3i(0, 0, 0), 1.0)
	_check("look mode takes its own shots", _rows(panel).size() == 1)

	panel.set_list("drone")
	_check("the drone list comes back intact",
		_rows(panel).size() == 2 and _name(panel, 0) == drone_names[0]
			and _name(panel, 1) == drone_names[1],
		"%d rows: %s" % [_rows(panel).size(), [_name(panel, 0), _name(panel, 1)]])
	# THE PLAYHEAD IS PART OF THE LIST. Parking the points but not t is the version of this bug
	# that looks fine until you scrub.
	_check("...and so does its playhead", is_equal_approx(panel.scrub_t(), 0.75),
		str(panel.scrub_t()))
	panel.set_list("look")
	_check("the look list is still there too", _rows(panel).size() == 1)

	# Both lists are written, not just the one that happened to be showing — asked of the encode
	# step, which is pure, so proving it cannot save them over the developer's own settings.
	panel._by_list[panel._list] = {"points": panel.points(), "t": panel.scrub_t()}
	var raw: Dictionary = panel._encode(panel._by_list)
	_check("both lists are written",
		raw.has("drone") and raw.has("look")
			and raw["drone"].size() == 2 and raw["look"].size() == 1,
		str(raw))

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
