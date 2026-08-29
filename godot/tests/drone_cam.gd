extends Node

## THE DRONE RIG'S GEOMETRY AND ITS STEPS, headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/drone_cam.tscn
##
## WHY IT EXISTS. Two things here fail silently. The control view stands PERPENDICULAR to the
## player-drone line, and the one arrangement a user reaches first — the drone straight overhead —
## has no horizontal direction to be perpendicular to; Godot returns zero rather than NaN from
## normalising that, so the camera lands exactly on its subject and the pane just looks broken.
## And the ring's compass steps have to agree with the world's, which is why the drone is stepped
## through the rig's OWN compass table rather than a second one written beside it.

var _failed: Array[String] = []

const R = preload("res://CameraRig.gd")


func _ready() -> void:
	var player := Vector3(40, 0, 12)

	# ── the control view ──────────────────────────────────────────────────────
	var drone := Vector3(46, 6, 12)
	var el: Array = R.drone_ctrl_eye_look(player, drone)
	_check("it looks at the midpoint of the pair", el[1].is_equal_approx((player + drone) * 0.5),
		str(el[1]))
	var flat := Vector3(drone.x - player.x, 0.0, drone.z - player.z).normalized()
	var off := Vector3(el[0].x - el[1].x, 0.0, el[0].z - el[1].z).normalized()
	_check("it stands square to the player-drone line", absf(off.dot(flat)) < 0.001,
		"dot=%f" % off.dot(flat))
	# LEVEL: tilt it and height stops reading as height, and height is what the ▲▼ buttons change.
	_check("it is level with the pair", is_equal_approx(el[0].y, el[1].y),
		"%f vs %f" % [el[0].y, el[1].y])
	var over: Array = R.drone_ctrl_eye_look(player, Vector3(40, 8, 12))
	_check("a drone straight overhead still gets a camera off its own subject",
		over[0].distance_to(over[1]) > 1.0, str(over[0].distance_to(over[1])))
	_check("a drone almost on top of you keeps the standoff floor",
		R.drone_ctrl_eye_look(player, Vector3(40.5, 0.5, 12))[0].distance_to(
			R.drone_ctrl_eye_look(player, Vector3(40.5, 0.5, 12))[1]) >= R.CTRL_MIN - 0.001)

	# ── the ring's steps ──────────────────────────────────────────────────────
	var rig = R.new()
	add_child(rig)
	rig._drone = Vector3(20, 5, 20)
	rig.step_drone("N")
	_check("north is -z, as the rig's own NORTH says", rig.drone_pos() == Vector3(20, 5, 19),
		str(rig.drone_pos()))
	rig.step_drone("E")
	_check("east is +x", rig.drone_pos() == Vector3(21, 5, 19), str(rig.drone_pos()))
	rig.step_drone("SW")
	_check("the diagonals move both axes", rig.drone_pos() == Vector3(20, 5, 20),
		str(rig.drone_pos()))
	# A step never changes height — that is what the ▲▼ pair is for, and a ring that also drifted
	# the altitude would make the two controls fight.
	_check("a lateral step leaves the height alone", is_equal_approx(rig.drone_pos().y, 5.0))
	_check("an unknown direction moves nothing", _same(rig, ""))

	# ── up and down ───────────────────────────────────────────────────────────
	rig.nudge_drone(Vector3(0, 1, 0))
	_check("up raises it a tile", is_equal_approx(rig.drone_pos().y, 6.0), str(rig.drone_pos()))
	rig.nudge_drone(Vector3(0, -1, 0))
	_check("down lowers it a tile", is_equal_approx(rig.drone_pos().y, 5.0), str(rig.drone_pos()))
	# THE FLOOR AND THE CEILING. A drone dragged into the ground films dirt, and one taken to
	# infinity is unrecoverable without a reset the user has not been given.
	for i in 40:
		rig.nudge_drone(Vector3(0, -1, 0))
	_check("it cannot be driven into the floor", rig.drone_pos().y >= R.DRONE_MIN_H,
		str(rig.drone_pos().y))
	for i in 200:
		rig.nudge_drone(Vector3(0, 1, 0))
	_check("...nor out of sight", rig.drone_pos().y <= R.DRONE_MAX_H, str(rig.drone_pos().y))

	# ── the panes are in the picker ───────────────────────────────────────────
	var mv = load("res://Multiview.gd")
	_check("both panes are in the selector",
		mv.MODES.has(mv.DRONE_CONTROL) and mv.MODES.has(mv.DRONECAM), str(mv.MODES))
	var names: Dictionary = load("res://Main.gd")._MODE_NAMES
	_check("and both are captioned",
		String(names.get(mv.DRONE_CONTROL, "")) != "" and String(names.get(mv.DRONECAM, "")) != "")

	_report()


func _same(rig, dir: String) -> bool:
	var before = rig.drone_pos()
	rig.step_drone(dir)
	return rig.drone_pos() == before


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
