extends Node

## THE WALK BETWEEN CELLS, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/smooth_move.tscn
##
## Every rule here has a way of failing that looks like a rendering glitch rather than a wrong
## number: overshoot reads as a wobble at every step, a missing snap reads as the player skating
## through a wall on a zone change, and no catch-up reads as the sprite drifting further behind the
## longer an auto-explore runs. So they are asserted as arithmetic instead of watched for.

var _failed: Array[String] = []


func _ready() -> void:
	var S = load("res://SmoothMove.gd")

	# A PLAIN STEP TAKES THE PACE IT WAS GIVEN: at 6 cells/sec a sixtieth of a second covers a
	# tenth of a cell. Timed INSIDE MAX_DT, because past that the clamp is the answer and this
	# check would be measuring the clamp instead of the pace.
	var p: Vector2 = S.step(Vector2.ZERO, Vector2(1, 0), 1.0 / 60.0, 6.0)
	_check("one cell at 6/sec", is_equal_approx(snappedf(p.x, 0.001), 0.1), "got %.3f" % p.x)

	# IT NEVER OVERSHOOTS. A frame that would carry further than the cell must land ON it, not past
	# it and back — asserted with a dt inside the clamp, so it is the overshoot guard being tested
	# and not MAX_DT doing the work.
	p = S.step(Vector2(0.9, 0), Vector2(1, 0), 1.0 / 30.0, 6.0)
	_check("a frame past the cell lands on it", p == Vector2(1, 0), "got %s" % p)

	# A LONG FRAME DOES NOT SWALLOW THE STEP. The frame a snapshot lands on is the frame that
	# rebuilds the zone, so it is the slowest one there is — and at 12 cells/sec an 80ms frame
	# covers a whole cell, which is how every step came out instant while the arithmetic was right.
	p = S.step(Vector2.ZERO, Vector2(1, 0), 0.120, 12.0)
	_check("a slow frame does not cover a whole cell", p.x < 0.999, "got %.3f" % p.x)

	# ...and arriving is exact, so the sprite settles instead of jittering on the last hundredth.
	p = S.step(Vector2(0.999, 0), Vector2(1, 0), 0.5, 6.0)
	_check("it arrives exactly", p == Vector2(1, 0), "got %s" % p)

	# THE CATCH-UP. Two cells behind must cover more ground in the same frame than one cell behind,
	# or a burst of turns leaves the walk permanently trailing.
	var near: float = S.step(Vector2.ZERO, Vector2(1, 0), 0.05, 6.0).x
	var far: float = S.step(Vector2.ZERO, Vector2(2, 0), 0.05, 6.0).x
	_check("further behind moves faster", far > near * 1.5, "near %.3f far %.3f" % [near, far])

	# A DIAGONAL STEP IS STILL A STEP. 1.41 cells must glide, or every diagonal move snaps and the
	# walk only looks smooth on the cardinals.
	p = S.step(Vector2.ZERO, Vector2(1, 1), 0.01, 6.0)
	_check("a diagonal glides", p != Vector2(1, 1) and p.length() > 0.0, "got %s" % p)

	# ...and so does a step taken while ALREADY a cell behind — 2.41 cells, the worst case a real
	# walk produces, and the number SNAP_CELLS was chosen to clear.
	p = S.step(Vector2.ZERO, Vector2(2.41, 0), 0.01, 6.0)
	_check("a step taken while behind still glides", p.x > 0.0 and p.x < 2.41, "got %.3f" % p.x)

	# BUT A CROSSING CUTS. Anything past the snap is not a walk, and easing it draws the player
	# skating over ground they never crossed.
	p = S.step(Vector2.ZERO, Vector2(40, 0), 0.01, 6.0)
	_check("a teleport cuts", p == Vector2(40, 0), "got %s" % p)

	# Degenerate frames must not move anything or divide by zero.
	# WITHIN the snap, so this tests dt and not the cut. The first version used a 6-cell gap, which
	# snaps before dt is ever looked at — and snapping on a zero-length frame is correct, because a
	# cut is not motion. The assertion was wrong, not the rule.
	_check("a zero frame stays put", S.step(Vector2(3, 3), Vector2(4, 3), 0.0, 6.0) == Vector2(3, 3),
		"moved on dt=0")
	_check("already there is already there",
		S.step(Vector2(5, 5), Vector2(5, 5), 0.1, 6.0) == Vector2(5, 5), "drifted off the cell")

	# A WALK CONVERGES. Stepping repeatedly at a plausible frame rate must actually arrive — a rule
	# that eases by a fraction of the remainder never does.
	var at := Vector2.ZERO
	var n := 0
	while at != Vector2(1, 0) and n < 600:
		at = S.step(at, Vector2(1, 0), 1.0 / 60.0, 6.0)
		n += 1
	_check("a step completes", at == Vector2(1, 0) and n < 20, "took %d frames, at %s" % [n, at])

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
