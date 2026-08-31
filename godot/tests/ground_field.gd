extends Node

## EVERY CELL WEARS QUD'S FIELD — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/ground_field.tscn
##
## Daniel, after six rounds of this: "It looks the same." He was right every time, and every
## measurement I made was true and beside the point. Qud paints the field colour in EVERY cell and
## draws glyphs on it, so its ground is never a hole; Raves painted a black film over unexplored
## cells to hide their floor art and left a void. Sampling a remembered cell said 42.5 against
## Qud's 45.7 — a fine match, and a small part of the picture — while the rest of the map, the part
## that dominates what you actually see, was near-black.
##
## Measured on the whole view after the change: Raves' dominant colour is (17,52,51) lum 41.4 over
## 354k pixels against Qud's (15,59,58) lum 45.7, and it is the DOMINANT colour now, as in Qud.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")


func _ready() -> void:
	Z.fire_dark = false
	Z.torch_dark = false

	var seen := {"x": 0, "y": 0, "light": 200, "visible": true, "explored": true, "objs": []}
	var remembered := {"x": 1, "y": 0, "light": 1, "visible": false, "explored": true, "objs": []}
	var never := {"x": 2, "y": 0, "light": 1, "visible": false, "explored": false, "objs": []}

	_check("a cell you can see wears no field — its own art shows",
		Z.ground_cover(seen) == Z.COVER_NONE, str(Z.ground_cover(seen)))
	_check("a remembered cell wears the field, with a trace of floor through it",
		Z.ground_cover(remembered) == Z.COVER_MEMORY, str(Z.ground_cover(remembered)))
	# THE ONE THAT WAS A VOID. The black film here was hiding floor art, which the field does too —
	# in Qud's colour instead of a hole.
	_check("a cell you have NEVER seen wears the field outright",
		Z.ground_cover(never) == Z.COVER_FULL, str(Z.ground_cover(never)))

	# UNEXPLORED OUTRANKS UNSEEN. A cell can be both, and the answer must be the full field rather
	# than the memory wash — memory is for a place you have been.
	var both := {"x": 3, "y": 0, "light": 1, "visible": false, "explored": false, "objs": []}
	_check("never-seen beats merely-unseen", Z.ground_cover(both) == Z.COVER_FULL)

	# ...and the firelight switch reaches this too: a cell whose only light was a fire you have
	# switched off is no longer SEEN, so it falls back to memory rather than staying at full art.
	var firelit := {"x": 4, "y": 0, "light": 200, "visible": true, "explored": true,
		"firelit": true, "objs": []}
	_check("with firelight on, a fire-lit cell is seen", Z.ground_cover(firelit) == Z.COVER_NONE)
	Z.fire_dark = true
	_check("...and with it off, it wears the memory field",
		Z.ground_cover(firelit) == Z.COVER_MEMORY, str(Z.ground_cover(firelit)))
	Z.fire_dark = false

	# THE THREE ANSWERS ARE DISTINCT. A decision that collapsed two of them would pass every check
	# above that only names one.
	_check("the three covers are three different answers",
		Z.COVER_NONE != Z.COVER_MEMORY and Z.COVER_MEMORY != Z.COVER_FULL
			and Z.COVER_NONE != Z.COVER_FULL)

	# ── a remembered WALL is flat K, like a remembered sprite ────────────────
	# The sprite path was corrected to flat K long ago and said why; the wall path kept scaling K
	# by each vertex's own brightness, so a wall made of dark rock stayed dark — measured on screen
	# at (4,25,26) lum 18.8 against a field of 41.4 and Qud's K of 64.3.
	var r = Z.new()
	add_child(r)
	var src := ArrayMesh.new()
	var verts := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	# a bright face and a dark one, as a real wall mesh has
	# ONE VERTEX IS NOT OPAQUE, or "alpha is preserved" cannot fail: every alpha was 1.0 and
	# hard-coding 1.0 passed it.
	var cols := PackedColorArray([Color(0.8, 0.7, 0.6, 0.5), Color(0.2, 0.18, 0.15),
		Color(0.5, 0.45, 0.4)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	src.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var ghost: ArrayMesh = r._ghost_wall_mesh(src)
	var g: PackedColorArray = ghost.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var k: Color = r._qud_color("K")
	_check("every vertex of a remembered wall is the SAME colour",
		absf(g[0].g - g[1].g) < 0.01 and absf(g[1].g - g[2].g) < 0.01,
		"%s %s %s" % [g[0], g[1], g[2]])
	# TOLERANCE, because a mesh's colour array does not store what you handed it exactly — the
	# first version compared for equality and failed on a 0.002 rounding, which says nothing about
	# the rule under test.
	_check("...and that colour is Qud's K",
		absf(g[0].r - k.r) < 0.01 and absf(g[0].g - k.g) < 0.01 and absf(g[0].b - k.b) < 0.01,
		"%s vs K %s" % [g[0], k])
	# THE DARK FACE IS THE ONE THAT MATTERED: under the old rule it came back at a fifth of K.
	_check("a dark face is no darker than a bright one", g[1].g >= g[0].g * 0.999,
		"dark %s bright %s" % [g[1], g[0]])
	# ...and alpha still rides through, or the silhouette is lost. COMPARED AGAINST THE SOURCE AS
	# THE MESH GIVES IT BACK, not against what was handed in: a colour array does not round-trip
	# alpha unchanged, so comparing to the input failed on correct code.
	var src_back: PackedColorArray = src.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_check("alpha is carried through from the source", absf(g[0].a - src_back[0].a) < 0.01,
		"ghost %.3f source %.3f" % [g[0].a, src_back[0].a])

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
