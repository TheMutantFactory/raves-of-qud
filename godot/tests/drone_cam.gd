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

	# ── the dronecam's aim ────────────────────────────────────────────────────
	# THE SIDE VIEW IS GONE. Daniel: "Let's drop the drone control view and just have the dronecam
	# view." Two rounds of reversal bugs went with it — it took the camera's heading from the
	# drone's own position, so flying the drone turned the camera. A camera you look THROUGH
	# cannot do that, and the checks below are what keeps it that way.

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

	# ── it stays in the zone ──────────────────────────────────────────────────
	# "I've placed the drone on the ground. It's stuck in an adjacent zone." Nothing bounded x/z.
	rig.set_zone_cells(Vector2(80, 25))
	rig._drone = Vector3(2, 5, 2)
	for i in 20:
		rig.step_drone("W")
		rig.step_drone("N")
	_check("it cannot be walked off the west or north edge",
		rig.drone_pos().x >= 0.0 and rig.drone_pos().z >= 0.0, str(rig.drone_pos()))
	for i in 200:
		rig.step_drone("E")
		rig.step_drone("S")
	_check("nor off the east or south edge",
		rig.drone_pos().x <= 79.0 and rig.drone_pos().z <= 24.0, str(rig.drone_pos()))
	# AND IT CAN COME BACK. A clamp that pinned it to the wall would leave it just as stranded.
	rig.step_drone("W")
	_check("...and it can be walked back in", rig.drone_pos().x < 79.0, str(rig.drone_pos()))

	# ── the dronecam does not spin either ─────────────────────────────────────
	# Daniel: "I try moving into the zone and then the controls reverse." Fixing the CONTROL pane
	# was not enough: the dronecam aimed AT the player, so its heading flipped from (0,0,-1) to
	# (0,0,+1) the instant the drone crossed them — and the dronecam is the shot you are
	# composing, so that is the pane you steer by. Same feedback loop, other pane.
	#
	# Sweep the drone right around the player and assert the heading is identical everywhere.
	var rig2 = R.new()
	add_child(rig2)
	rig2._player = player
	var heads: Array = []
	for deg in range(0, 360, 15):
		var a2 := deg_to_rad(float(deg))
		rig2._drone = player + Vector3(6.0 * cos(a2), 5.0, 6.0 * sin(a2))
		var e2: Array = rig2.eye_look_for(R.CamMode.DRONECAM)
		var f2: Vector3 = e2[1] - e2[0]
		f2.y = 0.0
		heads.append(f2.normalized())
	var turned2 := 0
	for v in heads:
		if v.distance_to(heads[0]) > 0.001:
			turned2 += 1
	_check("the dronecam holds its heading wherever the drone is", turned2 == 0,
		"%d of %d positions turned it" % [turned2, heads.size()])
	# ...INCLUDING straight over the player, which is where it used to invert.
	rig2._drone = player + Vector3(0, 5, 0)
	var onTop: Vector3 = rig2.eye_look_for(R.CamMode.DRONECAM)[1] - rig2.eye_look_for(R.CamMode.DRONECAM)[0]
	onTop.y = 0.0
	_check("...and directly above them", onTop.normalized().distance_to(heads[0]) < 0.001,
		str(onTop.normalized()))
	# It looks DOWN at the ground: level from six tiles up is horizon and sky.
	rig2._drone = Vector3(40, 6, 12)
	var el2: Array = rig2.eye_look_for(R.CamMode.DRONECAM)
	_check("it looks down at the ground, not at the horizon", el2[1].y < el2[0].y - 0.5,
		"eye.y=%f look.y=%f" % [el2[0].y, el2[1].y])
	# The pane's rotate buttons are the only thing that turns it.
	var spun2: Array = rig2.eye_look_for(R.CamMode.DRONECAM, {"yaw": PI * 0.5})
	var fs: Vector3 = spun2[1] - spun2[0]
	fs.y = 0.0
	_check("the rotate buttons aim it", fs.normalized().distance_to(heads[0]) > 0.1,
		str(fs.normalized()))
	# Zoom pulls the eye back along the aim rather than bending the lens.
	var z1: Array = rig2.eye_look_for(R.CamMode.DRONECAM, {"zoom": 2.0})
	_check("zoom pulls the eye back along the aim", not z1[0].is_equal_approx(el2[0]), str(z1[0]))

	# ── the panes are in the picker ───────────────────────────────────────────
	var mv = load("res://Multiview.gd")
	_check("the dronecam is in the selector", mv.MODES.has(mv.DRONECAM), str(mv.MODES))
	# ...and the side view is NOT. A mode left in MODES with no branch in eye_look_for renders a
	# pane from whatever the match falls through to, which looks like a camera rather than a
	# leftover.
	_check("the side view is gone from it", mv.MODES.size() == 9, str(mv.MODES))
	var names: Dictionary = load("res://Main.gd")._MODE_NAMES
	_check("the dronecam is captioned", String(names.get(mv.DRONECAM, "")) != "")
	_check("...and nothing is captioned past it", not names.has(9), str(names.keys()))

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
