extends Node

## A DOOR IN A NORTH/SOUTH WALL IS THE EAST/WEST ONE TURNED, NOT MIRRORED — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/door_vox_turn.tscn
##
## _vox_face used to reach the N-S orientation by exchanging world x and z: (span, height, depth)
## became (depth, height, span). Exchanging two axes of a right-handed basis flips handedness — the
## same reflection the wall models carried — so the two orientations disagreed with EACH OTHER and
## one of them drew every door mirrored. A knob modelled on one side sat on the other depending on
## which way its wall ran, and the leaf's pivot carried a `-1.0 if not ew` sign to undo the flip on
## the swing, which is the kind of compensation a reflection leaves scattered behind it.
##
## The check does not need to know which orientation was "right": a turn about the vertical axis is
## the ONLY relationship the two placements may have, and a mirror is not one.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")

# An L, so nothing about it survives a mirror unnoticed: 2 wide in span, 1 deep, 3 tall, with a
# single voxel hanging off the +span side at the bottom.
const MODEL := {
	"dims": Vector3i(4, 2, 4),
	"vox": [
		[Vector3i(1, 0, 0), 1], [Vector3i(1, 0, 1), 1], [Vector3i(1, 0, 2), 1],
		[Vector3i(2, 0, 0), 1],
	],
}


func _ready() -> void:
	var r = Z.new()
	add_child(r)
	var pal := PackedColorArray([Color(0, 0, 0, 0), Color(0.8, 0.7, 0.2)])

	var ew := _verts(r._vox_model_mesh(MODEL, pal, "&y", 0.25, 0.25, true, 0.0, 1.0, 1.0, null))
	var ns := _verts(r._vox_model_mesh(MODEL, pal, "&y", 0.25, 0.25, false, 0.0, 1.0, 1.0, null))
	_check("both orientations build geometry", ew.size() > 0 and ns.size() == ew.size(),
		"ew %d verts, ns %d" % [ew.size(), ns.size()])

	# THE MODEL MUST BE ASYMMETRIC IN THE PLANE, or a mirror and a turn are the same picture and
	# every check below passes on the broken code.
	var mirrored := {}
	for v in ew:
		mirrored[Vector3(-v.x, v.y, v.z).snappedf(0.0001)] = true
	_check("the fixture is asymmetric, so a mirror is visible at all", not _same(ew, mirrored),
		"an x-symmetric model would make this test vacuous")

	# ── the turn ─────────────────────────────────────────────────────────────
	# Rotating the E-W placement 90 degrees about the vertical: X' = Z, Y' = Y, Z' = -X.
	var turned := {}
	for v in ew:
		turned[_turn(v).snappedf(0.0001)] = true
	_check("a N-S door is the E-W one turned 90 degrees about the vertical", _same(ns, turned),
		"%d of %d vertices land on the turn" % [_hits(ns, turned), ns.size()])

	# ...AND NOT THE SWAP IT USED TO BE. Swapping x and z is a reflection; it and the turn differ,
	# so passing the check above while also matching this would mean the fixture said nothing.
	var swapped := {}
	for v in ew:
		swapped[Vector3(v.z, v.y, v.x).snappedf(0.0001)] = true
	_check("...and not the axis swap, which is a mirror", not _same(ns, swapped),
		"the N-S placement still exchanges world x and z")

	# ── the leaf's hinge rides the same turn ─────────────────────────────────
	# The pivot is placed at +hx for E-W and must be at -hx for N-S, because span maps to world -z
	# there. Left at +hx the leaf hangs off the wrong edge of its own frame.
	var lf := r._vox_model_mesh(MODEL, pal, "&y", 0.25, 0.25, false, 1.0, 1.0, 1.0, null)
	var lv := _verts(lf)
	var zmin := 9.0
	var zmax := -9.0
	for v in lv:
		zmin = minf(zmin, v.z)
		zmax = maxf(zmax, v.z)
	# x_off=1 puts the model's span origin at the hinge, and the turn sends +span to -z, so the
	# body of the leaf must hang on the NEGATIVE z side of the pivot.
	_check("with the hinge at span 1, a N-S leaf hangs to -z", zmax <= 0.0001 and zmin < 0.0,
		"z spans [%.3f %.3f]" % [zmin, zmax])

	# ...and the PIVOT NODE takes the same turn, which is a separate line of code and was the one
	# the mirror used to hide: with the geometry swapped rather than turned, +hx looked right for
	# the wrong reason.
	_check("the hinge pivot is the E-W offset, turned",
		Z.door_pivot(0.3, false) == _turn(Z.door_pivot(0.3, true)),
		"%s vs %s" % [str(Z.door_pivot(0.3, false)), str(_turn(Z.door_pivot(0.3, true)))])
	_check("...and it is not zero, so the comparison says something",
		Z.door_pivot(0.3, true) != Vector3.ZERO)

	# ── the normals turn with the faces ──────────────────────────────────────
	# A face pointing the wrong way is lit the wrong way, and vertices alone would never say so.
	# PAIRED WITH THE VERTEX THEY BELONG TO, not compared as a set. My first version compared the
	# normal SETS, and a box emits +x, -x, +z and -z alike — a set symmetric under both the turn
	# and the swap, so the check passed with the swap left in. It graded nothing.
	var ewm := r._vox_model_mesh(MODEL, pal, "&y", 0.25, 0.25, true, 0.0, 1.0, 1.0, null)
	var nsm := r._vox_model_mesh(MODEL, pal, "&y", 0.25, 0.25, false, 0.0, 1.0, 1.0, null)
	var want := _turned_pairs(_verts(ewm), _norms(ewm))
	var got := _pairs(_verts(nsm), _norms(nsm))
	var miss := 0
	for k in got:
		if not want.has(k):
			miss += 1
	_check("each face keeps its own normal through the turn", miss == 0 and got.size() > 0,
		"%d of %d vertex/normal pairs are not the turn of an E-W one" % [miss, got.size()])
	var lateral := false
	for v in _norms(ewm):
		if absf(v.x) > 0.5 or absf(v.z) > 0.5:
			lateral = true
	_check("...and some normals are lateral, so the turn moves them", lateral)

	_report()


## 90 degrees about the vertical — the only relationship the two door placements may have.
func _turn(v: Vector3) -> Vector3:
	return Vector3(v.z, v.y, -v.x)


## Vertex/normal pairs, so a normal is checked ON THE FACE IT BELONGS TO.
func _pairs(v: PackedVector3Array, n: PackedVector3Array) -> Dictionary:
	var o := {}
	for i in v.size():
		o[[v[i].snappedf(0.0001), n[i].snappedf(0.0001)]] = true
	return o


func _turned_pairs(v: PackedVector3Array, n: PackedVector3Array) -> Dictionary:
	var o := {}
	for i in v.size():
		o[[_turn(v[i]).snappedf(0.0001), _turn(n[i]).snappedf(0.0001)]] = true
	return o


func _norms(mi: MeshInstance3D) -> PackedVector3Array:
	if mi == null or mi.mesh == null or (mi.mesh as ArrayMesh).get_surface_count() == 0:
		return PackedVector3Array()
	return (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]


func _verts(mi: MeshInstance3D) -> PackedVector3Array:
	if mi == null or mi.mesh == null or (mi.mesh as ArrayMesh).get_surface_count() == 0:
		return PackedVector3Array()
	return (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _hits(got: PackedVector3Array, want: Dictionary) -> int:
	var n := 0
	for v in got:
		if want.has(v.snappedf(0.0001)):
			n += 1
	return n


func _same(got: PackedVector3Array, want: Dictionary) -> bool:
	return got.size() > 0 and _hits(got, want) == got.size()


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
