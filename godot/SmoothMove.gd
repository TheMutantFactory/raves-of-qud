extends RefCounted

## THE WALK BETWEEN CELLS — Qud moves in whole tiles, Raves draws the space between them.
##
## Daniel: "When the user holds the movement key, the user clicks a walk-to-tile, or uses the walk
## action and walks in a direction: let's add a max speed and a smooth movement. It should look more
## like a Final Fantasy walk."
##
## Qud is turn-based and its answer is always a CELL: the player was at 40,12 and now they are at
## 41,12. Nothing in the game has a position between the two. So this owns a second, purely visual
## position that chases the real one at a walking pace, and everything that follows the player —
## the sprite, the camera, the light they carry — reads THAT instead.
##
## THE PACE IS THE ONE THE KEYS ALREADY USE. auto_walk_rate is how many steps a second a held
## direction key produces (6 by default), so gliding at the same rate means a held key produces
## continuous motion rather than a sprite that lurches and waits. Pick a slower glide and the walk
## visibly falls behind the input; pick a faster one and each step arrives early and stops dead.
##
## IT CATCHES UP RATHER THAN ACCUMULATING LAG. Click-to-travel and auto-explore resolve turns as
## fast as Qud can, which is faster than any walking pace — so the further behind the visual falls,
## the faster it moves, and a burst of steps ends with the sprite where the player actually is
## instead of metres behind. A fixed speed would drift further behind for as long as the burst
## lasted and then crawl to catch up.
##
## AND SOME MOVES ARE NOT WALKS. A zone crossing, a teleport, or the player being put somewhere by
## the game are all "the position changed" as far as the snapshot is concerned, and sliding across
## them would draw the player skating over ground they never crossed. Past SNAP_CELLS it stops
## pretending and cuts.

## Cells per second at a one-cell lag — the walk itself. Read from auto_walk_rate by the caller.
const DEFAULT_SPEED := 6.0
## How much faster it may go per extra cell of lag. At 2 cells behind it moves at 2x, at 3 at 3x.
const CATCHUP := 1.0
## ...AND THE CEILING ON THAT. Daniel: "reduce the top speed to 0.5 the current top walk speed."
##
## The catch-up had no ceiling: at the snap boundary it reached eight times the walking pace, and
## the fastest the walk was ever observed doing real work was about four (a click-to-travel peaked
## at 3.96 cells of lag). So the top was set by the snap distance rather than by any decision about
## how fast a person may be drawn moving. Four is half of that eight, and still above everything a
## measured travel asked for — the cap trims the theoretical peak, not the ordinary case.
const MAX_FACTOR := 4.0
## Beyond this the move was not a walk.
##
## MEASURED, NOT CHOSEN. At 2.6 — enough for a diagonal step (1.41) and a step taken while already a
## cell behind (2.41) — a click-to-travel across the zone cut instead of gliding: Qud resolves travel
## at about twelve steps a second and Raves coalesces the snapshots it cannot draw, so the target
## routinely jumps three or four cells between frames. Those are still a WALK; only the arithmetic
## made them look like teleports. Eight clears a coalesced burst while staying far below the tens of
## cells a real teleport or a zone re-anchor moves, and the catch-up above closes the gap in a few
## frames rather than dawdling across it.
const SNAP_CELLS := 8.0

## THE LONGEST FRAME THE WALK WILL BELIEVE.
##
## This is the one that makes or breaks the effect, and it is not obvious: the frame a snapshot
## lands on is the frame that REBUILDS the zone's creatures, which is the most expensive frame
## there is. So the step arrives on a frame whose dt is an order of magnitude longer than usual —
## measured, a whole cell was covered in a single frame at 12 cells/second, meaning dt was past 80ms
## — and the walk was over before it was seen. Every step looked instant while the arithmetic was
## perfectly correct.
##
## Clamping to 1/30 costs a hitchy frame some ground, which the catch-up above then makes up.
const MAX_DT := 1.0 / 30.0

## THE PATH, NOT THE DESTINATION — the whole reason this file has a queue in it.
##
## Daniel: "if you click on a tile that is on the other side of a wall, the Raves character moves in
## a direct line through the wall. We need to follow the actual path travelled by the main player in
## Qud."
##
## Qud walks the route, one cell per turn, and publishes a snapshot for each. BridgeClient then
## COALESCES them — one zone rebuild per frame, or the Metal allocator crashes — and everything but
## the newest was thrown away. The walk was handed only the endpoints of a burst and eased between
## them in a straight line, which is a straight line through whatever the route went around.
##
## The cells were never missing, only discarded. They are kept as breadcrumbs now and this queue
## walks them in order, so the drawn player goes where the real one went.
##
## HOW MANY WAYPOINTS ARE WORTH KEEPING. A burst can be long — auto-explore resolves turns as fast
## as Qud can — and following every cell at a walking pace would leave the sprite metres behind. Past
## the cap the OLDEST waypoints are dropped, so the sprite jumps FORWARD ALONG THE ROUTE rather than
## across it: still never through a wall, and the lag stays bounded. The catch-up speed below closes
## what is left.
const PATH_MAX := 24

## Add a snapshot's worth of movement to the queue: the cells that were coalesced away, in order,
## then the cell Qud is actually on. Pure, so the queue rule can be tested without a game.
static func extend_path(path: Array, crumbs: Array, target: Vector2) -> Array:
	var out: Array = path.duplicate()
	for c in crumbs:
		var v := c as Vector2
		if out.is_empty() or not out[out.size() - 1].is_equal_approx(v):
			out.append(v)
	if out.is_empty() or not out[out.size() - 1].is_equal_approx(target):
		out.append(target)
	# DROPPED FROM THE FRONT, never the back: the back is where the player IS, and losing it would
	# leave the sprite walking to a cell Qud has already left.
	if out.size() > PATH_MAX:
		out = out.slice(out.size() - PATH_MAX)
	return out


## How far the drawn player still has to walk: this leg plus every leg after it. The catch-up reads
## THIS rather than the current leg, or a queue of one-cell hops would never exceed 1x and the
## sprite would fall further behind for as long as a burst lasted.
static func path_lag(from: Vector2, path: Array) -> float:
	if path.is_empty():
		return 0.0
	var total: float = (path[0] as Vector2).distance_to(from)
	for i in range(1, path.size()):
		total += (path[i] as Vector2).distance_to(path[i - 1] as Vector2)
	return total


## ONE FRAME ALONG THE WHOLE QUEUE, with a single distance budget spent across it.
##
## The obvious loop — call step() per waypoint until one is not reached — hands every leg a FULL
## frame of movement, so a frame that clears three waypoints moves three times as far as a frame
## that clears none. The budget is computed once here and spent, which is what makes the pace the
## same whether the route arrived as one snapshot or ten.
##
## Returns {pos, path}: the new drawn position and what is left of the queue.
static func advance(from: Vector2, path: Array, dt: float, speed := DEFAULT_SPEED,
		snap := SNAP_CELLS) -> Dictionary:
	var out: Array = path.duplicate()
	if out.is_empty() or dt <= 0.0:
		return {"pos": from, "path": out}
	var v: float = maxf(speed, 0.001) \
		* minf(1.0 + CATCHUP * maxf(0.0, path_lag(from, out) - 1.0), MAX_FACTOR)
	var budget: float = v * minf(dt, MAX_DT)
	var pos := from
	while not out.is_empty() and budget > 0.0:
		var leg: Vector2 = out[0]
		var d := leg - pos
		var dist := d.length()
		# NOT A WALK. A leg longer than the snap is a teleport or a re-anchor, not a step — cut to
		# it and drop the budget, because easing across one is the slide through the wall this
		# whole file exists to avoid.
		if dist > snap:
			pos = leg
			out.pop_front()
			break
		if dist <= 0.0001:
			out.pop_front()
			continue
		if budget >= dist:
			pos = leg
			budget -= dist
			out.pop_front()
		else:
			pos += d / dist * budget
			budget = 0.0
	return {"pos": pos, "path": out}


## One frame of the walk. Pure: the caller keeps the position, this only says where it goes next.
## `lag` is how far there is left to go along the whole path; -1 means "just the leg in front".
static func step(from: Vector2, to: Vector2, dt: float, speed := DEFAULT_SPEED,
		snap := SNAP_CELLS, lag := -1.0) -> Vector2:
	var d := to - from
	var dist := d.length()
	if dist <= 0.0001:
		return to
	# NOT A WALK. Cut, and do not ease into it: an eased teleport is a slide through the wall.
	if dist > snap:
		return to
	if dt <= 0.0:
		return from
	var behind: float = dist if lag < 0.0 else lag
	var v: float = maxf(speed, 0.001) * minf(1.0 + CATCHUP * maxf(0.0, behind - 1.0), MAX_FACTOR)
	var move: float = v * minf(dt, MAX_DT)
	# NEVER OVERSHOOT. Landing past the cell and easing back is a visible wobble at every step, and
	# at low frame rates the overshoot can exceed a whole cell.
	if move >= dist:
		return to
	return from + d / dist * move
