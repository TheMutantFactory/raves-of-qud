extends Node

## THE DRAWN PLAYER FOLLOWS QUD'S ROUTE, NOT THE STRAIGHT LINE — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/walk_path.tscn
##
## Daniel: "if you click on a tile that is on the other side of a wall, the Raves character moves in
## a direct line through the wall. We need to follow the actual path travelled by the main player in
## Qud."
##
## Qud walks the route one cell per turn and publishes a snapshot for each. BridgeClient COALESCES
## those frames — one zone rebuild per frame is what stops the Metal allocator crashing — and used
## to discard everything but the newest, so the walk was handed the two ENDPOINTS of a burst. The
## cells were never missing, only thrown away.

var _failed: Array[String] = []
const S = preload("res://SmoothMove.gd")


func _ready() -> void:
	# A route around a wall: east along a corridor, then north, then east again. The straight line
	# from start to finish passes through cells the route deliberately avoids.
	var route: Array = [Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(4, 0),
		Vector2(4, -1), Vector2(4, -2), Vector2(4, -3), Vector2(4, -4)]
	var start := Vector2(0, 0)

	# ── the queue keeps every step of the burst ──────────────────────────────
	var crumbs: Array = route.slice(0, route.size() - 1)
	var path: Array = S.extend_path([], crumbs, route[route.size() - 1])
	_check("a coalesced burst becomes a queue of every cell it walked",
		path.size() == route.size(), "%d waypoints for a %d-cell route" % [path.size(), route.size()])
	_check("...in the order Qud walked them", path[0] == route[0] and path[2] == route[2],
		"%s then %s" % [str(path[0]), str(path[2])])

	# ── walking it never leaves the route ────────────────────────────────────
	# THE CHECK THIS FILE EXISTS FOR. Sample the drawn position every frame of a slow walk and
	# assert each sample sits on a segment of the route — never in the open ground the corridor
	# goes around, which is exactly where a straight line from start to finish would pass.
	var pos := start
	var q: Array = path.duplicate()
	var worst := 0.0
	var frames := 0
	while not q.is_empty() and frames < 600:
		var r: Dictionary = S.advance(pos, q, 1.0 / 60.0, 6.0)
		pos = r["pos"]
		q = r["path"]
		frames += 1
		worst = maxf(worst, _off_route(pos, start, path))
	_check("every drawn position sits on the route", worst < 0.001, "worst %.4f cells off" % worst)
	_check("...and the walk actually finished at the destination",
		pos.is_equal_approx(route[route.size() - 1]), str(pos))
	_check("...having taken real time, not one frame", frames > 10, "%d frames" % frames)
	# ...and the straight line WOULD have left it, or the check above is free. Sampled along the
	# whole chord rather than at its midpoint — my first version took the midpoint of an L whose
	# midpoint happened to BE a waypoint, and the precondition failed on a perfectly good fixture.
	var chord_worst := 0.0
	for i in 21:
		var p: Vector2 = start.lerp(route[route.size() - 1], float(i) / 20.0)
		chord_worst = maxf(chord_worst, _off_route(p, start, path))
	_check("a straight line from start to finish leaves the route", chord_worst > 0.5,
		"the fixture route is too straight to catch anything (worst %.3f)" % chord_worst)

	# ── the pace does not depend on how the route arrived ────────────────────
	# One snapshot per cell vs one snapshot for the whole burst must draw the same distance in the
	# same time, or a laggy frame would make the sprite sprint.
	# ONE FRAME MOVES ONE FRAME'S WORTH, however many waypoints are queued. The budget is what
	# makes that true, and "the same ground either way" did not catch its removal — with the budget
	# never spent, a single frame walked the ENTIRE queue and the comparison still passed. The bound
	# is arithmetic: speed 6 with the catch-up capped at MAX_FACTOR, over one 60Hz frame.
	var cap: float = 6.0 * S.MAX_FACTOR * (1.0 / 60.0)
	var one: Dictionary = S.advance(start, path.duplicate(), 1.0 / 60.0, 6.0)
	var moved: float = (one["pos"] as Vector2).distance_to(start)
	_check("one frame moves at most one frame's worth, whatever is queued", moved <= cap + 0.0001,
		"moved %.3f cells, ceiling %.3f" % [moved, cap])
	_check("...and it did move, so the ceiling is not passing on zero", moved > 0.0)
	# ...AND THE BUDGET IS SPENT AS IT IS USED, checked on a frame big enough to clear WHOLE
	# waypoints. The ceiling above cannot see that: with a 60Hz frame the budget is 0.4 of a cell,
	# less than the first leg, so the code never reaches the line that decrements it and deleting
	# that line changed nothing. At MAX_DT and a brisk pace the frame clears three legs and stops
	# partway through the fourth, which is exactly where the arithmetic says it should stop.
	var big: Dictionary = S.advance(start, path.duplicate(), S.MAX_DT, 24.0)
	var want: float = 24.0 * S.MAX_FACTOR * S.MAX_DT          # 3.2 cells along a route of 1-cell legs
	var went: float = _route_dist(start, path, big["pos"])
	_check("a frame that clears whole waypoints spends the budget once", absf(went - want) < 0.01,
		"walked %.3f cells, budget was %.3f" % [went, want])
	_check("...and stopped short of the end, rather than running the whole queue",
		not (big["path"] as Array).is_empty(), "the queue emptied in one frame")

	# ...and a long queue really does run faster than a short one, which is the catch-up doing its
	# job rather than the budget being ignored.
	var short_q: Dictionary = S.advance(start, [Vector2(1, 0)], 1.0 / 60.0, 6.0)
	_check("a long queue catches up faster than a single step",
		moved > (short_q["pos"] as Vector2).distance_to(start) + 0.0001,
		"long %.4f vs single %.4f" % [moved, (short_q["pos"] as Vector2).distance_to(start)])

	# ── a teleport still cuts ────────────────────────────────────────────────
	var far: Array = [Vector2(60, 40)]
	var r2: Dictionary = S.advance(start, far, 1.0 / 60.0, 6.0)
	_check("a leg past the snap distance cuts instead of sliding",
		(r2["pos"] as Vector2).is_equal_approx(Vector2(60, 40)), str(r2["pos"]))

	# ── the queue is bounded, and bounded from the FRONT ─────────────────────
	var long_route: Array = []
	for i in 100:
		long_route.append(Vector2(i, 0))
	var capped: Array = S.extend_path([], long_route.slice(0, 99), long_route[99])
	_check("a runaway burst is capped", capped.size() == S.PATH_MAX, "%d" % capped.size())
	_check("...dropping the OLDEST, so the queue still ends where Qud is",
		(capped[capped.size() - 1] as Vector2).is_equal_approx(Vector2(99, 0)),
		str(capped[capped.size() - 1]))

	_report()


## Distance from `p` to the nearest segment of the route start->path[0]->path[1]->...
func _off_route(p: Vector2, start: Vector2, path: Array) -> float:
	var best := 1e9
	var prev := start
	for w in path:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, prev, w).distance_to(p))
		prev = w
	return best


## How far along the route `p` is, measured along the segments rather than as the crow flies.
func _route_dist(start: Vector2, path: Array, p: Vector2) -> float:
	var total := 0.0
	var prev := start
	for w in path:
		var seg: float = prev.distance_to(w as Vector2)
		if Geometry2D.get_closest_point_to_segment(p, prev, w as Vector2).distance_to(p) < 0.001:
			return total + prev.distance_to(p)
		total += seg
		prev = w as Vector2
	return total


func _walk_for(from: Vector2, path: Array, frames: int, dt: float) -> Vector2:
	var pos := from
	var q: Array = path
	for i in frames:
		var r: Dictionary = S.advance(pos, q, dt, 6.0)
		pos = r["pos"]
		q = r["path"]
	return pos


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
