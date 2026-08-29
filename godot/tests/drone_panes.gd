extends Node

## THE TWO PANES' GEOMETRY, headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/drone_panes.tscn
##
## WHY IT EXISTS. The elevation view stands PERPENDICULAR to the line between the player and the
## drone, and the one arrangement that breaks that is the one a user reaches first: fly the drone
## straight up. There is then no horizontal direction to be perpendicular to, and normalising that
## zero vector is how a camera ends up at NaN pointing nowhere — a black pane, with nothing in any
## log to say why.

var _failed: Array[String] = []

const R = preload("res://CameraRig.gd")


func _ready() -> void:
	var player := Vector3(40, 0, 12)

	# ── the ordinary case: the drone off to one side and up ───────────────────
	var drone := Vector3(46, 6, 12)
	var el: Array = R.drone_side_eye_look(player, drone)
	var eye: Vector3 = el[0]
	var look: Vector3 = el[1]
	_check("it looks at the midpoint of the pair", look.is_equal_approx((player + drone) * 0.5),
		str(look))
	# PERPENDICULAR IS THE CLAIM. Along the pair's own axis the two subjects overlap and the gap
	# you are placing is exactly what you cannot see.
	var flat := Vector3(drone.x - player.x, 0.0, drone.z - player.z).normalized()
	var off := Vector3(eye.x - look.x, 0.0, eye.z - look.z).normalized()
	_check("it stands square to the player-drone line", absf(off.dot(flat)) < 0.001,
		"dot=%f" % off.dot(flat))
	_check("...far enough back to hold both",
		eye.distance_to(look) >= player.distance_to(drone) * 0.5, str(eye.distance_to(look)))
	# AN ELEVATION IS LEVEL. Tilt it and height stops reading as height, which is the one
	# measurement this view exists to show.
	_check("it is level with the pair, so height reads as height",
		is_equal_approx(eye.y, look.y), "eye.y=%f look.y=%f" % [eye.y, look.y])

	# ── the degenerate case: straight overhead ────────────────────────────────
	var over := Vector3(40, 8, 12)
	var el2: Array = R.drone_side_eye_look(player, over)
	var eye2: Vector3 = el2[0]
	_check("a drone straight overhead still gets a camera",
		is_finite(eye2.x) and is_finite(eye2.y) and is_finite(eye2.z), str(eye2))
	_check("...and it is not standing on its own subject",
		eye2.distance_to(el2[1]) > 1.0, str(eye2.distance_to(el2[1])))

	# ── close in, where the standoff floor does the work ──────────────────────
	var near := Vector3(40.5, 0.5, 12)
	var el3: Array = R.drone_side_eye_look(player, near)
	_check("a drone almost on top of you does not put the camera inside it",
		el3[0].distance_to(el3[1]) >= R.DRONE_SIDE_MIN - 0.001,
		str(el3[0].distance_to(el3[1])))

	# ── the pane's own yaw still turns it ─────────────────────────────────────
	var turned: Array = R.drone_side_eye_look(player, drone, PI * 0.5)
	_check("Q/E spins the standoff", not turned[0].is_equal_approx(eye), str(turned[0]))
	_check("...without moving what it looks at", turned[1].is_equal_approx(look), str(turned[1]))

	# ── where it starts ───────────────────────────────────────────────────────
	# Daniel: "The drone starts off where the compass camera is."
	var seed: Array = R.drone_seed(Vector3(43.4, 5.6, 9.2), Vector3(40.2, 0.0, 12.7))
	_check("it starts at the compass camera, on the grid",
		seed[0] == Vector3(43, 6, 9), str(seed[0]))
	_check("...aimed at the player, on the ground", seed[1] == Vector3(40, 0, 13), str(seed[1]))
	# THE FLOOR. The compass camera drops toward eye level as you zoom in, so at the closest zoom
	# its rounded height is 0 — a drone buried in the floor, and a side view framing a zero-height
	# gap, which reads as broken rather than as close.
	var low: Array = R.drone_seed(Vector3(41.0, 0.2, 12.0), Vector3(40.0, 0.0, 12.0))
	_check("a compass camera at eye level still puts the drone above ground",
		low[0].y >= 1.0, str(low[0]))

	# ── the modes are wired into the selector ─────────────────────────────────
	var mv = load("res://Multiview.gd")
	_check("the selector carries both drone panes",
		mv.MODES.has(int(R.CamMode.DRONE)) and mv.MODES.has(int(R.CamMode.DRONE_SIDE)),
		str(mv.MODES))
	# A PANE WITH NO CAPTION reads as a broken cell, and the caption comes from Main's table.
	# THE SCRIPT, NOT AN INSTANCE. _MODE_NAMES is a const, so it reads straight off the GDScript
	# resource — instantiating Main here builds a whole game object and leaks it at exit.
	var names: Dictionary = load("res://Main.gd")._MODE_NAMES
	_check("both panes are named",
		String(names.get(int(R.CamMode.DRONE), "")) != ""
			and String(names.get(int(R.CamMode.DRONE_SIDE), "")) != "",
		str(names.get(int(R.CamMode.DRONE), "<none>")))

	_report()


func is_finite(f: float) -> bool:
	return not (is_nan(f) or is_inf(f))


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
