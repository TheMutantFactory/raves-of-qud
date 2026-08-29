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
## How much faster it may go per extra cell of lag. At 2 cells behind it moves at 2x, at 3 at 3x:
## enough to clear a burst quickly without the sprite visibly rocketing.
const CATCHUP := 1.0
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

## One frame of the walk. Pure: the caller keeps the position, this only says where it goes next.
static func step(from: Vector2, to: Vector2, dt: float, speed := DEFAULT_SPEED,
		snap := SNAP_CELLS) -> Vector2:
	var d := to - from
	var dist := d.length()
	if dist <= 0.0001:
		return to
	# NOT A WALK. Cut, and do not ease into it: an eased teleport is a slide through the wall.
	if dist > snap:
		return to
	if dt <= 0.0:
		return from
	var v: float = maxf(speed, 0.001) * (1.0 + CATCHUP * maxf(0.0, dist - 1.0))
	var move: float = v * minf(dt, MAX_DT)
	# NEVER OVERSHOOT. Landing past the cell and easing back is a visible wobble at every step, and
	# at low frame rates the overshoot can exceed a whole cell.
	if move >= dist:
		return to
	return from + d / dist * move
