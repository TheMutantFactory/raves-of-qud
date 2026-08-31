extends Node

## A HAND-AUTHORED WALL MODEL IS DECLARED BY NAME, NOT BY HEIGHT — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/wall_vox_model.tscn
##
## Daniel dropped a 16x16x10 model into godot/art and asked for it on the rock walls. The runtime
## wall-vox path took a model only when it was exactly WALL_VOX_LAYERS (24) tall — the number being
## the declaration, which told a hand-drawn wall from a wall2vox EXPORT of the band grammar. That
## proxy held while 24 was the only hand-authored size and would have rejected this model, and
## rejected it the expensive way: silently, back to stock art, which is the metal family's
## hardest-won lesson repeated on a new path.
##
## `-model-` in the filename says the same thing and cannot be written by wall2vox, so the shape is
## free. The mesh divides WALL_H by the model's own z, so 10 layers stretch to the tile.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")
const ART := "res://art"
const TILE := "Assets_Content_Textures_Tiles_wall_rock-10000000"


func _ready() -> void:
	var r = Z.new()
	add_child(r)

	# THE FILE IS THERE AND IS WHAT IT CLAIMS. A check that only exercised the lookup would pass
	# just as well against a missing model, which is the failure being guarded.
	var found := ""
	for f in DirAccess.get_files_at(ART):
		if f.begins_with(TILE + "-model-") and f.ends_with(".vox"):
			found = ART.path_join(f)
	_check("the declared model is in res://art", found != "", "none matching %s-model-*.vox" % TILE)
	if found == "":
		_report()
		return

	var v: Dictionary = load("res://VoxFile.gd").read(found)
	var ms: Array = v.get("models", [])
	_check("...and it parses as a vox model", not ms.is_empty())
	if ms.is_empty():
		_report()
		return
	var d: Vector3i = ms[0]["dims"]
	_check("...at 16x16x10, which is NOT the 24-layer opt-in",
		d == Vector3i(16, 16, 10) and d.z != r.WALL_VOX_LAYERS, str(d))

	# THE LOOKUP, for the exact signature and for a diagonal one that projects onto it. Qud reports
	# diagonal-flavoured signatures nobody authors a model for; matching only the exact name would
	# leave this model covering a handful of cells.
	r._tiles_dir = "/tmp/no-such-tiles"     # so only the res://art path can answer
	_check("the exact signature finds it", r._wall_vox_declared(TILE + ".bmp") == found,
		r._wall_vox_declared(TILE + ".bmp"))
	# 11000000 IS N+NE — the bits run N,NE,E,SE,S,SW,W,NW, so the DIAGONALS are the odd indices.
	# My first version used 10100000, which is N+E: two cardinals, already its own projection, and
	# the check failed against correct code. Worth keeping the note — the bit order is the whole
	# reason this projection exists and it is easy to read the wrong way round.
	_check("...and a diagonal signature projects onto it",
		r._wall_vox_declared("Assets_Content_Textures_Tiles_wall_rock-11000000.bmp") == found,
		r._wall_vox_declared("Assets_Content_Textures_Tiles_wall_rock-11000000.bmp"))
	# ── every OTHER signature in the family borrows it ───────────────────────
	# This check used to assert the opposite ("a different cardinal does not borrow it"), guarding
	# against one model silently becoming every wall. Daniel asked for exactly that, and he is
	# right that it is safe: a wall's shape comes from the NEIGHBOUR BITS handed to the mesher,
	# which drops the faces that abut a wall. The signature in a model's name records which cell
	# it was drawn against, not which cells it can serve. Joppa alone asks for 16 cardinal
	# signatures under 136 diagonal-flavoured names; without this, one of them wore his art and
	# 135 fell back to stock. "I only see one that has been replaced."
	for sig in ["01000000", "00000000", "10101010", "00100010"]:
		var tname := "Assets_Content_Textures_Tiles_wall_rock-%s.bmp" % sig
		_check("signature %s borrows the family model" % sig,
			r._wall_vox_declared(tname) == found, r._wall_vox_declared(tname))
	# ...AND IT SAYS SO. A borrow reported as if the signature had a model of its own is how the
	# stock fallback stayed invisible long enough to cost the metal family a session.
	var note := String(r._wall_vox_files.get(
		"Assets_Content_Textures_Tiles_wall_rock-00000000", ""))
	_check("...and zonereport calls it a BORROW", note.contains("BORROWED"), note)
	_check("...while the signature that owns the model is not called a borrow",
		not String(r._wall_vox_files.get(TILE, "")).contains("BORROWED"),
		String(r._wall_vox_files.get(TILE, "")))

	# THE FAMILY IS THE FENCE. A rock model must not turn up on metal or brinestalk walls, and a
	# tile with no signature at all must never borrow — otherwise dropping one model in res://art
	# would replace every wall in the game, which is a much bigger claim than the one being made.
	for outsider in ["Assets_Content_Textures_Tiles_wall_metal-01000000.bmp",
			"Assets_Content_Textures_Tiles_wall_rock_hewn-01000000.bmp",
			"Assets_Content_Textures_Tiles_wall_rockery-01000000.bmp",
			"Terrain_sw_statue1.bmp", "Assets_Content_Textures_Tiles_wall_rock-notabits.bmp"]:
		_check("%s does not borrow it" % outsider.get_basename(),
			r._wall_vox_declared(outsider) == "", r._wall_vox_declared(outsider))

	# ...and the fence itself, in the direction res://art cannot currently exercise: the outsiders
	# above are all LONGER family names than the one file, so removing the dash from the match
	# would not have shown up there. A shorter one claiming a longer one's model is the direction
	# that actually bites.
	var FAM := "Assets_Content_Textures_Tiles_wall_rock"
	_check("the family match takes its own family's model",
		Z._family_match(FAM + "-10000000-model-16x16x10.vox", FAM))
	for stranger in [FAM + "ery-10000000-model-16x16x10.vox", FAM + "_hewn-00-model-x.vox"]:
		_check("...and not %s" % stranger, not Z._family_match(stranger, FAM))
	_check("...and not a file that declares no model at all",
		not Z._family_match(FAM + "-10000000.vox", FAM))
	_check("...and not a non-vox file", not Z._family_match(FAM + "-10000000-model-x.png", FAM))

	# ...and the two signatures land on the SAME model, which is what lets one mesh serve both.
	# The mesh cache keys on the model's source path for this reason: keyed by variant, 136
	# signatures would each re-mesh identical geometry at ~20ms.
	var a: Dictionary = r._wall_vox_model(TILE + ".bmp")
	var b: Dictionary = r._wall_vox_model("Assets_Content_Textures_Tiles_wall_rock-00000000.bmp")
	_check("two signatures resolve to one model, by source path",
		not a.is_empty() and a.get("src", "") == b.get("src", "?") and a.get("src", "") == found,
		"%s vs %s" % [a.get("src", "none"), b.get("src", "none")])

	# ...AND THE WALL PATH ACTUALLY ASKS. Everything above calls the lookup directly, so cutting
	# _wall_vox_model's use of it changed nothing and the wall would quietly render stock art —
	# the exact failure this whole path is trying not to repeat.
	var picked: Dictionary = r._wall_vox_model(TILE + ".bmp")
	_check("the wall path picks the declared model up", not picked.is_empty(),
		"_wall_vox_model returned {} with tiles_dir pointing nowhere")
	_check("...and it is the 16x16x10 one", not picked.is_empty()
		and (picked["model"]["dims"] as Vector3i) == Vector3i(16, 16, 10),
		str(picked.get("model", {}).get("dims", "none")))

	# ── the model is not mirrored ────────────────────────────────────────────
	# A voxel (vx,vy,vz) is placed at world (vx, vz, vy): two axes EXCHANGED, which flips
	# handedness, so every model this project meshed came out mirrored. Nothing showed it until a
	# wall with distinct sides. Daniel, with the file open in vengi: "the sides are flipped
	# left-to-right."
	var one := {"dims": Vector3i(4, 2, 2), "vox": [[Vector3i(0, 0, 0), 1], [Vector3i(3, 1, 1), 2]]}
	var mir: Dictionary = Z.mirror_x(one)
	_check("mirror_x sends x=0 to the far side", (mir["vox"][0][0] as Vector3i) == Vector3i(3, 0, 0),
		str(mir["vox"][0][0]))
	_check("...and x=max to the near side", (mir["vox"][1][0] as Vector3i) == Vector3i(0, 1, 1),
		str(mir["vox"][1][0]))
	_check("...leaving y and z alone, since north/south is already right",
		(mir["vox"][1][0] as Vector3i).y == 1 and (mir["vox"][1][0] as Vector3i).z == 1)
	_check("...and the palette index with its voxel", int(mir["vox"][0][1]) == 1
		and int(mir["vox"][1][1]) == 2)
	_check("...without disturbing the original", (one["vox"][0][0] as Vector3i) == Vector3i(0, 0, 0),
		"mirror_x must not edit the model it was handed — it is cached and shared")
	# TWICE IS THE IDENTITY, which is what makes it a mirror rather than a shuffle.
	var back: Dictionary = Z.mirror_x(mir)
	_check("mirroring twice returns the model", (back["vox"][0][0] as Vector3i) == Vector3i(0, 0, 0)
		and (back["vox"][1][0] as Vector3i) == Vector3i(3, 1, 1))

	# ...and the wall path applies it, so the model on screen is the one drawn in vengi.
	# THE VOXEL SET, not its bounds. A 16-wide wall spans 0..15 either way, so comparing min/max x
	# passed with the mirror deleted — the bounds are symmetric even when the model is not.
	var raw: Dictionary = load("res://VoxFile.gd").read(found)["models"][0]
	var loaded: Dictionary = r._read_wall_vox(found, true)
	var W: int = (raw["dims"] as Vector3i).x
	var raw_set := {}
	var want := {}
	for e in raw["vox"]:
		var q: Vector3i = e[0]
		raw_set[q] = true
		want[Vector3i(W - 1 - q.x, q.y, q.z)] = true
	var loaded_set := {}
	for e in loaded["model"]["vox"]:
		loaded_set[e[0] as Vector3i] = true
	# ...and the model must actually BE asymmetric, or "mirrored" and "not mirrored" are the same
	# picture and the check cannot fail.
	var asym := false
	for q in raw_set:
		if not want.has(q):
			asym = true
			break
	_check("the model is asymmetric, so a mirror is visible at all", asym,
		"an x-symmetric model would make the check below vacuous")
	_check("the wall reader hands back the mirrored voxel set", loaded_set == want,
		"%d voxels loaded, %d expected" % [loaded_set.size(), want.size()])

	# THE HEIGHT GATE IS LIFTED ONLY FOR A DECLARED FILE.
	var got: Dictionary = r._read_wall_vox(found, true)
	_check("a declared model is read at its own height", not got.is_empty(), str(got.keys()))
	_check("...and the SAME file is refused when not declared",
		r._read_wall_vox(found, false).is_empty(),
		"a 10-layer file must still be ignored on the undeclared path")

	# ...and the model reaches the mesher, which is where a shape that loads but draws nothing
	# would still look exactly like the silent stock fallback.
	var mesh: ArrayMesh = r._wall_vox_mesh(got, {})
	_check("it meshes to real geometry", mesh != null and mesh.get_surface_count() > 0
		and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 0,
		"surfaces %d" % (mesh.get_surface_count() if mesh != null else -1))
	# ...and it fills the tile's height rather than a tenth of it: the mesh divides WALL_H by the
	# model's own z, so a 10-layer model must span the same height a 24-layer one does.
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := -9.0
	for p in verts:
		top = maxf(top, p.y)
	_check("...spanning the full tile height, stretched from 10 layers",
		absf(top - r.WALL_H) < 0.001, "top %.3f vs WALL_H %.3f" % [top, r.WALL_H])

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
