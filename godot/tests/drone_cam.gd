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
	rig.set_zone_cells(Vector2(80, 25))
	rig._player = Vector3(0, 0, 0)
	rig._drone_off = Vector3(20, 5, 20)
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
	rig._player = Vector3(0, 0, 0)
	rig._drone_off = Vector3(2, 5, 2)
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
	# AND IT COMES BACK ON THE FIRST PRESS. A clamp applied only where the drone is DRAWN lets the
	# offset wind up invisibly at the wall, so 200 wasted presses cost 200 presses to undo. This
	# is the check that catches that, and it needs the over-driving above to mean anything.
	rig.step_drone("W")
	_check("...and one press back moves it immediately", rig.drone_pos().x < 79.0,
		str(rig.drone_pos()))

	# ── the dronecam does not spin either ─────────────────────────────────────
	# Daniel: "I try moving into the zone and then the controls reverse." Fixing the CONTROL pane
	# was not enough: the dronecam aimed AT the player, so its heading flipped from (0,0,-1) to
	# (0,0,+1) the instant the drone crossed them — and the dronecam is the shot you are
	# composing, so that is the pane you steer by. Same feedback loop, other pane.
	#
	# Sweep the drone right around the player and assert the heading is identical everywhere.
	var rig2 = R.new()
	add_child(rig2)
	rig2.set_zone_cells(Vector2(80, 25))
	rig2._player = player
	rig2.set_drone_target(R.DroneTarget.FIRST)
	var heads: Array = []
	for deg in range(0, 360, 15):
		var a2 := deg_to_rad(float(deg))
		rig2._drone_off = Vector3(6.0 * cos(a2), 5.0, 6.0 * sin(a2))
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
	rig2._drone_off = Vector3(0, 5, 0)
	var onTop: Vector3 = rig2.eye_look_for(R.CamMode.DRONECAM)[1] - rig2.eye_look_for(R.CamMode.DRONECAM)[0]
	onTop.y = 0.0
	_check("...and directly above them", onTop.normalized().distance_to(heads[0]) < 0.001,
		str(onTop.normalized()))
	# It looks DOWN at the ground: level from six tiles up is horizon and sky.
	rig2._drone_off = Vector3(0, 6, 0)
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

	# ── it follows the player ─────────────────────────────────────────────────
	# Daniel: "make it so after you select drone cam, it follows the player in that relative
	# offset." The drone is an OFFSET now, so walking must carry it along unchanged.
	var rig3 = R.new()
	add_child(rig3)
	rig3.set_zone_cells(Vector2(80, 25))
	rig3._player = Vector3(40, 0, 12)
	rig3._drone_off = Vector3(-4, 6, 3)
	var p0: Vector3 = rig3.drone_pos()
	_check("the drone sits at the player plus the offset", p0 == Vector3(36, 6, 15), str(p0))
	rig3._player = Vector3(50, 0, 8)
	_check("...and it moves WITH the player", rig3.drone_pos() == Vector3(46, 6, 11),
		str(rig3.drone_pos()))
	_check("...keeping the same offset", rig3.drone_offset() == Vector3(-4, 6, 3),
		str(rig3.drone_offset()))
	# THE ZONE CLAMP APPLIES TO THE POSITION, NOT THE OFFSET. Clamping the offset would mean
	# walking toward a wall permanently shortened your framing, and you would re-fly the drone
	# every time you approached one.
	rig3._player = Vector3(1, 0, 12)
	_check("it noses against the zone edge", rig3.drone_pos().x >= 0.0, str(rig3.drone_pos()))
	rig3._player = Vector3(40, 0, 12)
	_check("...and springs back to the shot you set", rig3.drone_pos() == Vector3(36, 6, 15),
		str(rig3.drone_pos()))

	# ── the four targets ──────────────────────────────────────────────────────
	# "Target (Player-head, Player-center, Player floor, drone-1st)"
	rig3._drone_off = Vector3(-6, 5, 0)
	var heights := {}
	for t in [R.DroneTarget.HEAD, R.DroneTarget.CENTER, R.DroneTarget.FLOOR]:
		rig3.set_drone_target(t)
		heights[t] = rig3.eye_look_for(R.CamMode.DRONECAM)[1].y
	_check("head, centre and feet aim at three different heights",
		heights[R.DroneTarget.HEAD] > heights[R.DroneTarget.CENTER]
			and heights[R.DroneTarget.CENTER] > heights[R.DroneTarget.FLOOR], str(heights))
	# They are the rig's OWN head/waist constants, not a second pair invented here — a camera that
	# disagreed with the rest of the rig about where the head is frames differently from every
	# other mode.
	_check("head is the rig's own head height",
		is_equal_approx(heights[R.DroneTarget.HEAD], R.HEAD_LOOK_H), str(heights[R.DroneTarget.HEAD]))
	_check("centre is the rig's own waist height",
		is_equal_approx(heights[R.DroneTarget.CENTER], R.WAIST_LOOK_H))
	_check("feet is the floor", is_equal_approx(heights[R.DroneTarget.FLOOR], 0.0))
	# A player target actually points AT the player — the thing the whole feature is for.
	rig3.set_drone_target(R.DroneTarget.CENTER)
	var pl: Array = rig3.eye_look_for(R.CamMode.DRONECAM)
	_check("a player target looks at the player, not past them",
		absf(pl[1].x - rig3._player.x) < 0.001 and absf(pl[1].z - rig3._player.z) < 0.001, str(pl[1]))
	# ...and it does NOT spin, because the offset cannot cross the player. This is the bug that
	# ate two rounds; a fixed offset is what makes a player-facing aim safe at all.
	var aims: Array = []
	for deg in range(0, 360, 15):
		var a3 := deg_to_rad(float(deg))
		rig3._player = Vector3(40 + 3.0 * cos(a3), 0, 12 + 3.0 * sin(a3))
		var e3: Array = rig3.eye_look_for(R.CamMode.DRONECAM)
		var f3: Vector3 = e3[1] - e3[0]
		f3.y = 0.0
		aims.append(f3.normalized())
	var moved := 0
	for v in aims:
		if v.distance_to(aims[0]) > 0.001:
			moved += 1
	_check("walking the player around does not spin the aim", moved == 0,
		"%d of %d positions turned it" % [moved, aims.size()])
	# drone-1st ignores the player entirely.
	rig3.set_drone_target(R.DroneTarget.FIRST)
	var f0: Array = rig3.eye_look_for(R.CamMode.DRONECAM)
	rig3._player = Vector3(10, 0, 20)
	var f1: Array = rig3.eye_look_for(R.CamMode.DRONECAM)
	var d0: Vector3 = (f0[1] - f0[0]).normalized()
	var d1: Vector3 = (f1[1] - f1[0]).normalized()
	_check("drone-1st looks where the drone points, wherever the player is",
		d0.distance_to(d1) < 0.001, "%s vs %s" % [d0, d1])

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
