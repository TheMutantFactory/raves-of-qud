extends Node

## BOTH VIEWS OWE THE SAME CLOSING WORK, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/locations_views.tscn
##
## WHY IT EXISTS. The sorted view was added by branching inside _rebuild and RETURNING early, which
## skipped the three steps the tail does: _paint_metrics, the empty-state label and _emit. The
## visible loss was the distance column — missing from the one view that is sorted BY distance —
## and it took a screenshot to notice, because a list of places with no numbers beside them looks
## like a list, not like a bug.
##
## So this builds the panel for real and asks both views the same questions. It is a heavier test
## than the pure-function ones next to it, and that is the point: the fault was not in a function,
## it was in a path that forgot to finish.

var _failed: Array[String] = []


func _ready() -> void:
	var panel = load("res://LocationsPanel.gd").new()
	add_child(panel)
	# The distance the panel would get from the live camera, stubbed off the fixture so the test
	# needs no zone, no beacons and no player.
	panel.metrics_cb = func(mx: int, _my: int) -> Dictionary:
		return {"para": float(mx), "dir": "N"}
	panel._player = Vector2i(0, 0)
	panel._entries = [
		{"id": "a", "name": "near", "mx": 1, "my": 0, "category": "Ruins"},
		{"id": "b", "name": "far", "mx": 9, "my": 0, "category": "Ruins"},
		{"id": "c", "name": "mid", "mx": 4, "my": 0, "category": "Lairs"},
	]

	for grouped in [true, false]:
		var label := "tree" if grouped else "sorted"
		panel._grouped = grouped
		panel._rebuild()
		var rows := _item_rows(panel)
		_check("%s: every place has a row" % label, rows.size() == 3,
			"got %d" % rows.size())
		# THE COLUMN THAT WENT MISSING. A "Far" label that exists but was never painted still reads
		# as empty on screen, so the test is on its TEXT, not on the node.
		var blank := 0
		for r in rows:
			var far: Label = r.get_node_or_null("Far")
			if far == null or far.text.strip_edges() == "":
				blank += 1
		_check("%s: every row shows its distance" % label, blank == 0,
			"%d of %d rows had no distance" % [blank, rows.size()])

	# ...and the sorted view is actually sorted, which is the claim its icon makes.
	panel._grouped = false
	panel._rebuild()
	var order: Array = []
	for r in _item_rows(panel):
		order.append(int(r.get_meta("mx", -1)))
	_check("sorted: nearest first", order == [1, 4, 9], "got %s" % [order])

	# The tree keeps Qud's categories, so its row count includes the headers the flat view has none
	# of — the two views are not the same list with a flag on it.
	panel._grouped = true
	panel._rebuild()
	_check("tree adds category headers", panel._row_count > _item_rows(panel).size(),
		"row_count %d vs %d item rows" % [panel._row_count, _item_rows(panel).size()])

	# THE HEADING CARRIES NO STATE. It used to read "Locations (beacons off)" and grey itself, which
	# is the eye's job now — and a second indicator is one that can disagree. Checked in BOTH armed
	# states so re-adding a suffix fails here rather than surviving as a quiet duplicate.
	for armed in [true, false]:
		panel._armed = armed
		panel._lost = false
		panel._refresh_title()
		_check("heading is just the name (armed=%s)" % armed, panel._title.text == "Locations",
			"got %s" % panel._title.text)
	# ...but LOST still speaks, because that is the game disabling the panel and nothing in the
	# header row can turn it back on.
	panel._lost = true
	panel._refresh_title()
	_check("lost still says so", panel._title.text.contains("lost"), "got %s" % panel._title.text)

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


## The place rows, told from the category headers by carrying a cell to point at.
func _item_rows(panel) -> Array:
	var out: Array = []
	for c in panel._rows.get_children():
		if c.has_meta("mx"):
			out.append(c)
	return out

func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
