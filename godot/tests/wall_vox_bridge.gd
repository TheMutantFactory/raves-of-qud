extends Node

## ADJACENT VOX WALLS READ AS ONE MASS — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/wall_vox_bridge.tscn
##
## A drawn wall carries a one-voxel RING of edge decoration around a 14x14 body. That ring is right
## where the wall ENDS and wrong where it does not: two rock cells side by side put ring against
## ring, a two-voxel band of border colour down the seam, and the body pattern restarts in every
## cell. Daniel: "bridge adjacent blocks... basically, the checker pattern repeats."
##
## bridge_edges reflects the ring about the first body row (ring 0 -> body row 2) on every side
## that abuts a wall. CLAMPING (ring <- the first body row) would duplicate that row's parity and
## kill a period-2 pattern at every seam, which is the bug _cap_az was written to fix.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")
const ART := "res://art"
const TILE := "Assets_Content_Textures_Tiles_wall_rock-10000000"


func _ready() -> void:
	var r = Z.new()
	add_child(r)
	r._tiles_dir = "/tmp/no-such-tiles"

	var mv: Dictionary = r._wall_vox_model(TILE + ".bmp")
	if mv.is_empty():
		_check("the rock model loads", false, "nothing under %s" % ART)
		_report()
		return
	var m: Dictionary = mv["model"]
	var d: Vector3i = m["dims"]

	# ── the fixture really has a ring around a relief ────────────────────────
	# Without this, "the ring was replaced" and "nothing happened" are the same picture: a model
	# whose border already matched its body would pass every check below with bridging deleted.
	var occ := _occ(m)
	var topz: int = d.z - 1
	var ring_solid := true
	var ring_uniform := true
	var first: int = -1
	for i in d.x:
		for q in [Vector2i(i, 0), Vector2i(i, d.y - 1), Vector2i(0, i), Vector2i(d.x - 1, i)]:
			var k := Vector3i(q.x, q.y, topz)
			if not occ.has(k):
				ring_solid = false
			else:
				if first < 0:
					first = int(occ[k])
	var body_holes := 0
	for x in range(1, d.x - 1):
		for y in range(1, d.y - 1):
			if not occ.has(Vector3i(x, y, topz)):
				body_holes += 1
	_check("the model's roof ring is solid", ring_solid)
	_check("...around a body that is not", body_holes > 0, "%d holes" % body_holes)

	# ── no neighbours, no bridging ───────────────────────────────────────────
	# An exposed wall must keep the border it was drawn with.
	_check("with no wall neighbours the model is untouched",
		_vset(Z.bridge_edges(m, {})) == _vset(m))
	_check("...and a side with no wall keeps its ring",
		_col(Z.bridge_edges(m, {"n": true}), 0, d.y - 1) == _col(m, 0, d.y - 1),
		"the south ring moved when only the north side abutted a wall")

	# ── each side reflects onto body row 2 ───────────────────────────────────
	for side in [["n", "y", 0, 2], ["s", "y", d.y - 1, d.y - 3],
			["w", "x", 0, 2], ["e", "x", d.x - 1, d.x - 3]]:
		var b: Dictionary = Z.bridge_edges(m, {String(side[0]): true})
		var axis := String(side[1])
		var ring: int = side[2]
		var body: int = side[3]
		var got := _line(b, axis, ring)
		var want := _line(m, axis, body)
		_check("a wall to the %s reflects the ring onto body row %d" % [side[0], body],
			got == want, "%d cells vs %d" % [got.size(), want.size()])
		# ...AND IT IS NOT A CLAMP. Reflecting onto row 2 and clamping onto row 1 are both
		# "the ring got replaced"; only one of them keeps a checker alive across the seam.
		var clamp_to: int = 1 if ring == 0 else (d.y - 2 if axis == "y" else d.x - 2)
		_check("...not clamped onto the first body row", got != _line(m, axis, clamp_to),
			"clamping duplicates the edge parity and kills a period-2 pattern at the seam")
		# ...and the ring it replaced was actually different, or the check above is free.
		_check("...replacing something", want != _line(m, axis, ring))

	# ── corners take both reflections ────────────────────────────────────────
	var nw: Dictionary = Z.bridge_edges(m, {"n": true, "w": true})
	_check("a north-west corner reflects diagonally onto (2,2)",
		_col(nw, 0, 0) == _col(m, 2, 2), "corner column")

	# ── the seam itself: one unbroken pattern across two cells ───────────────
	# THE CHECK THE WHOLE THING EXISTS FOR. Two rock cells stacked north-south, each bridging the
	# edge it shares, laid out in global coordinates: the roof must be one alternating pattern with
	# no doubled row and no gap at the join. A cell is an even 16 across, so local parity IS global
	# parity and every cell reflecting its own ring lands on the same phase.
	# TWO CELLS SHARING ONLY THE NORTH/SOUTH EDGE first, over the BODY columns. The east and west
	# rings are still edge decoration in this case — the wall ENDS there — so they are solid by
	# design and asking them to alternate would be asking for the wrong thing. (My first version
	# swept all 16 columns and failed at x=0 for exactly that reason.)
	var north: Dictionary = Z.bridge_edges(m, {"s": true})   # its south side abuts us
	var south: Dictionary = Z.bridge_edges(m, {"n": true})   # our north side abuts it
	var alt_seen := false
	var d1 := _seam_break(_occ(north), _occ(south), d, topz, 1, d.x - 1)
	_check("the roof alternates across a north/south seam", d1 == "", d1)

	# ...AND A CELL WITH WALLS ON ALL FOUR SIDES, which is what most of a wall run is: now every
	# column across the seam must alternate, ring columns included, because they are no longer
	# edges of anything.
	var all4 := {"n": true, "s": true, "e": true, "w": true}
	var bn := _occ(Z.bridge_edges(m, all4))
	var d2 := _seam_break(bn, bn, d, topz, 0, d.x)
	_check("...and across the seam between two fully-enclosed cells, every column", d2 == "", d2)
	for x in d.x:
		if bn.has(Vector3i(x, d.y - 1, topz)) != bn.has(Vector3i(x, d.y - 2, topz)):
			alt_seen = true
	_check("...and there was an alternation to see", alt_seen)
	# ...and it was BROKEN before, or the check above passes on art that never needed bridging.
	var ro := _occ(m)
	_check("...and the unbridged model does NOT alternate across it",
		_seam_break(ro, ro, d, topz, 1, d.x - 1) != "",
		"the ring would have tiled fine on its own and this whole path is unnecessary")

	# ── the mesher applies it ────────────────────────────────────────────────
	# Everything above calls bridge_edges directly, so cutting _wall_vox_mesh's use of it would
	# change nothing here and the walls would seam exactly as before. Count the ROOF quads sitting
	# over the north ring row: solid ring = one per column, bridged = the body's relief.
	var plain: int = _roof_run(r._wall_vox_mesh(mv, {}), d, 0)
	var brid: int = _roof_run(r._wall_vox_mesh(mv, {"n": true}), d, 0)
	_check("the unbridged north ring roofs every column", plain == d.x, "%d of %d" % [plain, d.x])
	_check("...and the mesh the wall path builds bridges it", brid > 0 and brid < plain,
		"%d roof quads over the north ring, unbridged %d" % [brid, plain])

	_report()


## Where the roof stops alternating across the join between a north cell and a south one, or ""
## if it never does. Reads four global rows — north d.y-2, north d.y-1 | south 0, south 1 — so a
## doubled row lands inside the window rather than on its edge.
func _seam_break(no: Dictionary, so: Dictionary, d: Vector3i, topz: int, x0: int, x1: int) -> String:
	for x in range(x0, x1):
		var col := [no.has(Vector3i(x, d.y - 2, topz)), no.has(Vector3i(x, d.y - 1, topz)),
			so.has(Vector3i(x, 0, topz)), so.has(Vector3i(x, 1, topz))]
		for i in 3:
			if col[i] == col[i + 1]:
				return "x=%d rows %s" % [x, str(col)]
	return ""


## occupancy of a model: Vector3i -> palette index
func _occ(m: Dictionary) -> Dictionary:
	var o := {}
	for e in m["vox"]:
		o[e[0] as Vector3i] = e[1]
	return o


func _vset(m: Dictionary) -> Dictionary:
	var o := {}
	for e in m["vox"]:
		o[[e[0], e[1]]] = true
	return o


## one column of a model, as {z: index}, keyed so two columns compare by content
func _col(m: Dictionary, x: int, y: int) -> Dictionary:
	var o := {}
	for e in m["vox"]:
		var q: Vector3i = e[0]
		if q.x == x and q.y == y:
			o[q.z] = e[1]
	return o


## one ring/body LINE across the model: axis "y" takes the row at that y, "x" the column at that x.
## Keyed by the coordinate that runs along the line plus z, so it compares by content alone.
func _line(m: Dictionary, axis: String, at: int) -> Dictionary:
	var o := {}
	for e in m["vox"]:
		var q: Vector3i = e[0]
		if axis == "y" and q.y == at:
			o[Vector2i(q.x, q.z)] = e[1]
		elif axis == "x" and q.x == at:
			o[Vector2i(q.y, q.z)] = e[1]
	return o


## How many of the row's columns carry a roof quad — an upward face at the very top of the wall,
## inside the depth band of model row `row`. Reads the mesh, not the model.
func _roof_run(mesh: ArrayMesh, d: Vector3i, row: int) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return -1
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sz: float = 1.0 / float(d.y)
	var z0: float = -0.5 + float(row) * sz
	var top := 0.0
	for p in verts:
		top = maxf(top, p.y)
	var cols := {}
	for i in range(0, verts.size(), 3):
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[i + 1]
		var c: Vector3 = verts[i + 2]
		if absf(a.y - top) > 0.001 or absf(b.y - top) > 0.001 or absf(c.y - top) > 0.001:
			continue
		var zc: float = (a.z + b.z + c.z) / 3.0
		if zc < z0 or zc >= z0 + sz:
			continue
		var xc: float = (a.x + b.x + c.x) / 3.0
		cols[int(floor((xc + 0.5) * float(d.x)))] = true
	return cols.size()


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
