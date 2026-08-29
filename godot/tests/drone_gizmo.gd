extends Node

## THE GIZMOS, headless — where they sit and, mostly, WHICH CAMERA CAN SEE THEM.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/drone_gizmo.tscn
##
## WHY IT EXISTS. The cull is the fragile half and this codebase has already had it wrong once:
## ZoneRenderer._tag_layer records that `layers |= bit` leaves a node on layer 1 as well, so a
## camera dropping that bit still draws it — the mechanism LOOKS right for exactly as long as the
## marker happens to be out of frame. Here it never is: the drone's camera sits inside the drone.

var _failed: Array[String] = []

const GZ = preload("res://DroneGizmo.gd")


func _ready() -> void:
	var g = GZ.new()
	add_child(g)

	# ── placement ─────────────────────────────────────────────────────────────
	g.place(Vector3(10, 6, 4), Vector3(14, 0, 9))
	_check("the body sits at the drone", g._body.position == Vector3(10, 6, 4), str(g._body.position))
	_check("the ring sits on the target", g._target.position == Vector3(14, 0, 9),
		str(g._target.position))
	# THE AIM LINE IS BUILT IN THE BODY'S OWN SPACE, so it starts at the drone and ends at the
	# target. Built in world space instead it would draw from the origin, which on a zone whose
	# corner is (0,0) looks almost right.
	_check("the aim line starts at the drone", g._aim.position == Vector3(10, 6, 4),
		str(g._aim.position))
	_check("...and reaches the target", g._aim.mesh.get_surface_count() == 1,
		"%d surfaces" % g._aim.mesh.get_surface_count())
	var verts: PackedVector3Array = g._aim.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check("...as a segment between the two",
		verts.size() == 2 and (g._aim.position + verts[1]).is_equal_approx(Vector3(14, 0, 9)),
		str(verts))
	# A drone sitting exactly on its target has no line to draw, and asking for a zero-length
	# segment is how a mesh build throws.
	g.place(Vector3(3, 0, 3), Vector3(3, 0, 3))
	_check("a zero-length aim draws nothing rather than throwing",
		g._aim.mesh.get_surface_count() == 0)

	# THE TARGET HAS TO READ FROM A LEVEL VIEW. The elevation looks along the ground by
	# construction, so a purely flat ring is seen edge-on and draws as a dash — in the one view
	# whose job is showing where the target is. Assert the mesh actually leaves the floor.
	var tv: PackedVector3Array = g._target.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var high := 0.0
	for p in tv:
		high = maxf(high, p.y)
	_check("the target stands up out of the floor, not just on it", high >= 1.0,
		"tallest vertex y=%f" % high)

	# ── the cull ──────────────────────────────────────────────────────────────
	# MOVED, not OR'd: the body must be on the drone layer ONLY, or a camera dropping that bit
	# still sees it on layer 1 and the drone fills with the inside of its own marker.
	_check("the body is on the drone layer alone", g._body.layers == GZ.BODY_LAYER,
		"layers=%d wanted=%d" % [g._body.layers, GZ.BODY_LAYER])
	_check("...and specifically not still on layer 1", (g._body.layers & 1) == 0,
		"layers=%d" % g._body.layers)
	# The target ring is NOT hidden from the drone: it is what that pane is aimed at.
	_check("the target ring stays visible to every camera", (g._target.layers & 1) != 0,
		"layers=%d" % g._target.layers)
	_check("so does the aim line", (g._aim.layers & 1) != 0, "layers=%d" % g._aim.layers)

	# ── shown only when you are working the rig ───────────────────────────────
	# ADDED TO THE TREE FIRST, the way Main builds it: `visible = false` is set in _ready, so a
	# bare .new() is still visible and asking a node that has never been readied proves nothing
	# about the node the game actually holds.
	var fresh = GZ.new()
	add_child(fresh)
	_check("hidden until asked for", not fresh.visible)
	g.set_shown(true)
	_check("shown on request", g.visible)
	g.set_shown(false)
	_check("...and hidden again", not g.visible)

	# ── the marker reads at night ─────────────────────────────────────────────
	# A gizmo that dims with the sun is one you cannot place after dusk, and this session already
	# learned to measure dark scenes rather than trust the eye.
	var mat: StandardMaterial3D = g._body.material_override
	_check("the body is unshaded",
		mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, str(mat.shading_mode))
	# ...but it does NOT draw through the world. Daniel on the look cursor: "It's showing above
	# the Dromad, which means it's not on the floor it's over everything?"
	_check("and it does not draw over everything", not mat.no_depth_test)

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
