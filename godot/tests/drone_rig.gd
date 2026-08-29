extends Node

## THE SCRUB AND THE GLIDE, headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/drone_rig.tscn
##
## WHY IT EXISTS. The list and the playhead are two pieces of state that index each other, and
## every editing operation can put them out of agreement: delete a shot ahead of the playhead and
## t points at a different shot than the one on screen; delete the last one and t is past the end.
## None of that is visible in a screenshot — the camera simply ends up somewhere else than the row
## you are looking at — so it is tested here where the numbers are readable.

var _failed: Array[String] = []

const D = preload("res://Drone.gd")


func _ready() -> void:
	var pts: Array = [
		{"name": "a", "drone": Vector3i(0, 4, 0),  "target": Vector3i(0, 0, 0),  "zoom": 1.0},
		{"name": "b", "drone": Vector3i(10, 4, 0), "target": Vector3i(10, 0, 0), "zoom": 2.0},
		{"name": "c", "drone": Vector3i(10, 8, 6), "target": Vector3i(4, 0, 6),  "zoom": 1.0},
	]

	# ── the glide ─────────────────────────────────────────────────────────────
	var p0 := D.at(pts, 0.0)
	_check("t=0 is the first shot exactly",
		p0["drone"] == Vector3(0, 4, 0) and is_equal_approx(p0["zoom"], 1.0), str(p0))
	var pend := D.at(pts, 2.0)
	_check("t=last is the last shot exactly", pend["drone"] == Vector3(10, 8, 6), str(pend))
	var mid := D.at(pts, 0.5)
	_check("halfway down a leg is the midpoint",
		mid["drone"] == Vector3(5, 4, 0) and is_equal_approx(mid["zoom"], 1.5), str(mid))
	# ONE LEG PER UNIT OF t, so t=1.5 is halfway along the SECOND leg, not 3/4 of the way through
	# the list. Adding a shot must not restretch the legs before it.
	var mid2 := D.at(pts, 1.5)
	_check("t=1.5 is halfway along the second leg", mid2["drone"] == Vector3(10, 6, 3), str(mid2))
	_check("past the end clamps to the last shot", D.at(pts, 99.0)["drone"] == Vector3(10, 8, 6))
	_check("before the start clamps to the first", D.at(pts, -99.0)["drone"] == Vector3(0, 4, 0))
	# THE EMPTY LIST IS NOT AN ORIGIN. A camera that jumps to (0,0,0) when you delete your last
	# shot is worse than one that just stops taking direction from the list.
	_check("an empty list poses nothing", D.at([], 0.0).is_empty())

	# ── scrolling ─────────────────────────────────────────────────────────────
	_check("a notch moves a quarter leg", is_equal_approx(D.scrub(0.0, 1.0, 3), 0.25))
	_check("four notches is one whole leg", is_equal_approx(D.scrub(0.0, 4.0, 3), 1.0))
	_check("invert flips the direction",
		is_equal_approx(D.scrub(1.0, 1.0, 3, true), 0.75))
	# CLAMPED, NOT WRAPPED — scrolling off the end must not cut back to the first shot.
	_check("scrolling past the end stops there", is_equal_approx(D.scrub(2.0, 5.0, 3), 2.0))
	_check("scrolling before the start stops there", is_equal_approx(D.scrub(0.0, -5.0, 3), 0.0))
	_check("one point has nowhere to scrub", is_equal_approx(D.scrub(0.0, 9.0, 1), 0.0))
	_check("no points has nowhere to scrub", is_equal_approx(D.scrub(0.0, 9.0, 0), 0.0))

	# ── editing, and what it does to the playhead ─────────────────────────────
	# A LONGER LIST FIRST, and deliberately: on a three-point list the final clamp to size-1
	# happens to produce the right answer whether or not the playhead is adjusted at all, so every
	# check below it passes with the adjustment deleted. Five points with the playhead at 3.0 is
	# the shortest case where the clamp cannot cover for it.
	var five: Array = []
	for i in 5:
		five.append({"name": "p%d" % i, "drone": Vector3i(i, 4, 0),
			"target": Vector3i(i, 0, 0), "zoom": 1.0})
	var rl := D.remove(five, 0, 3.0)
	_check("deleting before a mid-list playhead follows the shot",
		is_equal_approx(rl["t"], 2.0), "t=%s (clamp alone would give 3.0)" % rl["t"])
	var rf := D.remove(five, 0, 2.5)
	_check("...and it keeps the fraction inside the leg", is_equal_approx(rf["t"], 1.5), str(rf["t"]))
	# The shot under the playhead must be the SAME shot afterwards — the index moved, not the shot.
	_check("the playhead is still on the shot it was on",
		rl["points"][2]["name"] == five[3]["name"],
		"%s vs %s" % [rl["points"][2]["name"], five[3]["name"]])

	var r := D.remove(pts, 0, 2.0)
	_check("deleting BEFORE the playhead keeps its shot",
		r["points"].size() == 2 and is_equal_approx(r["t"], 1.0),
		"t=%s size=%d" % [r["t"], r["points"].size()])
	var r2 := D.remove(pts, 2, 2.0)
	_check("deleting the shot AT the end pulls the playhead back",
		is_equal_approx(r2["t"], 1.0), str(r2["t"]))
	var r3 := D.remove(pts, 1, 0.5)
	_check("deleting AFTER the playhead leaves it alone",
		is_equal_approx(r3["t"], 0.5), str(r3["t"]))
	var r4 := D.remove([pts[0]], 0, 0.0)
	_check("deleting the only shot empties the list",
		r4["points"].is_empty() and is_equal_approx(r4["t"], 0.0))
	_check("deleting nothing that exists changes nothing",
		D.remove(pts, 9, 1.0)["points"].size() == 3)

	# ── drag to reorder ───────────────────────────────────────────────────────
	var ro := D.reorder(pts, 0, 2)
	_check("reorder moves the row", ro[2]["name"] == "a", str(ro.map(func(p): return p["name"])))
	_check("...and keeps the others in order",
		ro[0]["name"] == "b" and ro[1]["name"] == "c",
		str(ro.map(func(p): return p["name"])))
	# THE SOURCE ARRAY IS NOT TOUCHED: the panel rebuilds from the result, and mutating in place
	# while a row is mid-drag reorders the thing the mouse is holding.
	_check("reorder does not mutate the original", pts[0]["name"] == "a")
	_check("reorder ignores an out-of-range index", D.reorder(pts, 0, 9).size() == 3)

	# ── the grid ──────────────────────────────────────────────────────────────
	_check("a drag snaps to whole tiles", D.snap(Vector3(3.4, 2.6, -1.4)) == Vector3i(3, 3, -1),
		str(D.snap(Vector3(3.4, 2.6, -1.4))))
	# HALF ROUNDS AWAY FROM ZERO, which is what GDScript's roundf does and what a grid wants:
	# symmetric about the origin, so -1.5 and 1.5 land the same distance out rather than both
	# drifting one way.
	_check("a half-tile rounds away from zero",
		D.snap(Vector3(1.5, 0.0, -1.5)) == Vector3i(2, 0, -2), str(D.snap(Vector3(1.5, 0.0, -1.5))))

	_report()


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
