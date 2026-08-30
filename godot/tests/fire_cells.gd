extends Node

## TURNING OFF THE LIGHT A FIRE CASTS ON THE ROOM — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/fire_cells.tscn
##
## Daniel: "How do I disable the current campfire/sconce floor lighting?" Qud sends one light byte
## per cell and no account of what lit it, so nothing downstream could tell a campfire's light from
## the torch in your hand. The sources DO arrive — every campfire and sconce is an object with a
## lightRadius — so the attribution is reconstructed once a turn and written on the cell.
##
## The fixture is the zone Daniel was standing in when he asked, read off the wire: Techlights at
## radius 6, Campfires at radius 3, and a light byte that is binary (1 or 200) rather than a ramp.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")


func _ready() -> void:
	Z.fire_dark = false

	var data := _zone()
	var marked: int = Z.mark_fire_lit(data)
	_check("the fire-lit cells are found", marked > 0, "%d marked" % marked)

	# WHAT IS AND IS NOT A FIRE'S DOING.
	_check("a cell beside the campfire is attributed to it", _lit(data, 25, 11))
	_check("a cell beside the sconce is attributed to it", _lit(data, 36, 7))
	# THE LIGHT YOU CARRY IS NOT A CAMPFIRE, and both of these cells are inside the sconce's radius
	# too — so the only thing keeping them lit is the guard.
	_check("the cell you are standing in is not", not _lit(data, 30, 8))
	_check("...nor one your own torch is lighting", not _lit(data, 33, 8))
	# NEVER MARKS WHAT QUD DID NOT LIGHT. A radius is a circle and Qud's light is not; this can
	# darken a cell Qud lit, never light one it did not.
	_check("an unlit cell inside a fire's radius is left alone", not _lit(data, 25, 10))
	# Daylight, or anything else Qud lit with no fire near it, is untouched.
	_check("a lit cell with no fire near it is left alone", not _lit(data, 70, 20))
	# A glowfish carries a lightRadius and is nobody's campfire.
	_check("a creature's own glow is not a campfire", not _lit(data, 60, 5))

	# ── the switch ────────────────────────────────────────────────────────────
	Z.fire_dark = false
	_check("switched on, a fire-lit cell reads lit", Z.cell_light(_c(data, 25, 11)) >= Z.LIGHT_LIT,
		str(Z.cell_light(_c(data, 25, 11))))
	_check("...and counts as seen", Z.cell_is_seen(_c(data, 25, 11)))

	Z.fire_dark = true
	_check("switched off, a fire-lit cell reads dark",
		Z.cell_light(_c(data, 25, 11)) <= Z.LIGHT_NONE, str(Z.cell_light(_c(data, 25, 11))))
	# REMEMBERED, NOT ERASED: it is still explored, so it draws as Qud's memory ghost rather than
	# as a hole in the map. Switching a light off should look like a dark room, not like a room
	# that was never there.
	_check("...but is still explored, so it draws as memory", Z.cell_is_explored(_c(data, 25, 11)))
	_check("...and no longer counts as seen", not Z.cell_is_seen(_c(data, 25, 11)))
	_check("your own torch still lights your cell", Z.cell_light(_c(data, 30, 8)) >= Z.LIGHT_LIT,
		str(Z.cell_light(_c(data, 30, 8))))
	_check("...and the far lit cell is untouched", Z.cell_light(_c(data, 70, 20)) >= Z.LIGHT_LIT,
		str(Z.cell_light(_c(data, 70, 20))))

	# ONE ANSWER FOR THE MAP AND THE ROOM. cell_is_seen is what the minimap's fog reads; if it did
	# not go through the same switch, the map would show a room lit that the world drew dark.
	Z.fire_dark = true
	var r = Z.new()
	add_child(r)
	# _light_frac IS THE BRIGHTNESS EVERY TILE IS MULTIPLIED BY, and it is a separate reader from
	# cell_is_seen. Left going straight to the raw byte it would draw the room at full colour while
	# the fog said the room was dark — the switch half-applied, which is worse than not at all.
	Z.fire_dark = false
	var bright: float = r._light_frac(_c(data, 25, 11))
	Z.fire_dark = true
	var dark: float = r._light_frac(_c(data, 25, 11))
	_check("the tile brightness follows the switch too", dark < bright,
		"on=%.2f off=%.2f" % [bright, dark])
	_check("the world and the map agree about a darkened cell",
		r._cell_seen(_c(data, 25, 11)) == Z.cell_is_seen(_c(data, 25, 11)))
	_check("...and about your own cell",
		r._cell_seen(_c(data, 30, 8)) == Z.cell_is_seen(_c(data, 30, 8)))

	# ── the mark is recomputed, not accumulated ──────────────────────────────
	# A fire is lit, carried and put out. Marks left over from last turn would darken a room whose
	# campfire went out three turns ago, and nothing would ever bring it back.
	Z.fire_dark = true
	var doused := _zone()
	for c in doused["cells"]:
		for o in c.get("objs", []):
			o.erase("lightRadius")
	Z.mark_fire_lit(doused)
	_check("a zone with the fires out marks nothing", _count(doused) == 0, "%d marked" % _count(doused))
	# ...and the same dictionaries, marked once, cleared on the next pass.
	Z.mark_fire_lit(data)
	var before: int = _count(data)
	for c in data["cells"]:
		for o in c.get("objs", []):
			o.erase("lightRadius")
	Z.mark_fire_lit(data)
	_check("the marks are cleared when the fires go out, not left on the cells",
		before > 0 and _count(data) == 0, "before=%d after=%d" % [before, _count(data)])

	Z.fire_dark = false
	_report()


## The zone Daniel was in: a sconce, a campfire, a carried torch, an unlit cell inside a fire's
## radius, a far lit cell no fire reaches, and a glowfish.
func _zone() -> Dictionary:
	var cells: Array = []
	var add := func(x: int, y: int, light: int, objs: Array) -> void:
		cells.append({"x": x, "y": y, "light": light, "explored": true, "objs": objs})
	# THE PLAYER STANDS ALL BUT ON THE SCONCE, because he did: the wire put him at (30,8) with
	# Techlights at (30,7) and (30,8). Parked somewhere quiet instead, his cells fall outside every
	# radius and the guard that protects your own light can be deleted with every check still
	# passing — which is what happened the first time this was written.
	add.call(30, 8, 200, [])           # the player's cell, inside the sconce's radius AND his own
	add.call(33, 8, 200, [])           # his torch reaches here; so does the sconce
	# an arc sconce and its room
	add.call(30, 7, 200, [{"tile": "sconce", "lightRadius": 6}])
	add.call(36, 7, 200, [])           # the sconce reaches; his torch does not
	# a campfire and its room
	add.call(27, 9, 200, [{"tile": "campfire", "lightRadius": 3, "onFire": true}])
	add.call(25, 11, 200, [])          # the campfire reaches; his torch does not (5.8 away)
	# INSIDE the campfire's radius and OUTSIDE the torch's: sat inside the torch's reach it was
	# the player guard rejecting it, not the light check, and the light check could be deleted.
	add.call(25, 10, 1, [])
	# lit, and nowhere near a fire
	add.call(70, 20, 200, [])
	# a glowfish, which carries a light and is not a campfire
	add.call(60, 5, 200, [{"tile": "glowfish", "lightRadius": 4, "creature": true}])
	return {
		"zone": {"width": 80, "height": 25},
		"player": {"x": 30, "y": 8, "heldLight": {"radius": 5}},
		"cells": cells,
	}


func _c(data: Dictionary, x: int, y: int) -> Dictionary:
	for c in data["cells"]:
		if int(c["x"]) == x and int(c["y"]) == y:
			return c
	return {}


func _lit(data: Dictionary, x: int, y: int) -> bool:
	return bool(_c(data, x, y).get("firelit", false))


func _count(data: Dictionary) -> int:
	var n := 0
	for c in data["cells"]:
		if bool(c.get("firelit", false)):
			n += 1
	return n


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
