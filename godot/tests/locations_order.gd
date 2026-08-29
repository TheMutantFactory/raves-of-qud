extends Node

## HOW THE LOCATIONS PANEL ARRANGES ITSELF, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/locations_order.tscn
##
## order_by_distance is the arrangement BOTH of the panel's views are built on: the tree groups this
## order into categories, and the sorted view shows it as-is. Neither re-sorts, so if this is wrong
## both views are wrong in the same way — and wrong QUIETLY, since a mis-ordered list of places you
## have never been looks exactly like a correctly ordered one.
##
## The fixtures carry the two rules that are easy to lose: the dedupe keeps the NEAREST of a
## repeated visited name (a walk across a marsh visits five parasangs all called "salt marsh"), and
## journal entries are never collapsed at all, because Qud wrote those and two notes sharing a name
## are still two notes.

var _failed: Array[String] = []

const VISITED := "Visited"


func _ready() -> void:
	var P = load("res://LocationsPanel.gd")
	# distance comes off the fixture itself, so a test never depends on a live camera or a zone
	var dist := func(e: Dictionary) -> float: return float(e.get("d", 0.0))

	# NEAREST FIRST.
	var out: Array = P.order_by_distance([
		{"name": "far", "d": 9.0, "category": "Ruins"},
		{"name": "near", "d": 1.0, "category": "Ruins"},
		{"name": "mid", "d": 4.0, "category": "Ruins"},
	], dist)
	_check("nearest first", _names(out) == ["near", "mid", "far"], "got %s" % [_names(out)])

	# A REPEATED VISITED NAME COLLAPSES TO THE NEAREST — and it is the nearest that survives, not
	# whichever happened to be listed first.
	out = P.order_by_distance([
		{"name": "salt marsh", "d": 7.0, "category": VISITED},
		{"name": "salt marsh", "d": 2.0, "category": VISITED},
		{"name": "salt marsh", "d": 5.0, "category": VISITED},
	], dist)
	_check("one row per visited name", out.size() == 1, "got %d rows" % out.size())
	_check("...and it is the nearest", float(out[0].get("d", -1)) == 2.0,
		"kept the one at %s" % out[0].get("d"))

	# JOURNAL NOTES ARE NEVER COLLAPSED, even sharing a name. The test is the CATEGORY, not the
	# presence of art — journal notes carry sprites now, and testing art would collapse Qud's notes.
	out = P.order_by_distance([
		{"name": "the lair", "d": 3.0, "category": "Lairs", "art": {"tile": "x"}},
		{"name": "the lair", "d": 8.0, "category": "Lairs", "art": {"tile": "x"}},
	], dist)
	_check("two journal notes with one name stay two", out.size() == 2, "got %d" % out.size())

	# ...and a visited row does not collapse a journal row that shares its name.
	out = P.order_by_distance([
		{"name": "Joppa", "d": 5.0, "category": "Settlements"},
		{"name": "Joppa", "d": 1.0, "category": VISITED},
	], dist)
	_check("visited and journal rows are different rows", out.size() == 2, "got %d" % out.size())

	# EQUAL DISTANCES KEEP THEIR ORDER. sort_custom is not stable, and two places the same distance
	# off would otherwise swap rows on every repaint — a list that flickers while you read it.
	var same: Array = []
	# SIXTY-FOUR, not eight: Godot's sort_custom is introsort, which leaves a small run alone and
	# only starts reordering equal keys once the input is big enough to partition. At eight this
	# check passed with the tie-break REMOVED — it could not fail, which is worse than not having it.
	for i in 64:
		same.append({"name": "p%02d" % i, "d": 3.0, "category": "Ruins"})
	var first: Array = _names(P.order_by_distance(same, dist))
	var again: Array = _names(P.order_by_distance(same, dist))
	_check("ties keep their order", first == again and first[0] == "p00",
		"got %s… then %s…" % [first.slice(0, 6), again.slice(0, 6)])

	# Degenerate input must come back empty rather than throw — the panel calls this before the
	# journal has loaded.
	_check("no entries, no rows", P.order_by_distance([], dist).is_empty(), "invented a row")

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _names(a: Array) -> Array:
	var out: Array = []
	for e in a:
		out.append(String(e.get("name", "")))
	return out

func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
