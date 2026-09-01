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
	# USER MODE, PINNED — and this must run before the renderer below is built. These gates go
	# through Settings.qud_shape(), which returns true UNCONDITIONALLY in 1:1, so on a machine
	# whose settings.json says `"mode": "1to1"` every fixture check here failed while the
	# "1:1 builds nothing" checks passed — a red SPOT run that said nothing about the code.
	# set_value is in-memory only (save() is what writes), so this cannot touch the real config.
	Settings.one_to_one_only = false
	Settings.set_value("mode", "user")

	# BUILT FIRST, DELIBERATELY. ZoneRenderer._ready calls _refresh_fx_flags, which re-reads both
	# gates from Settings — so a renderer instantiated part-way through this file silently resets
	# the very statics the checks around it had just set, and the check after it reads the wrong
	# world. Cost twenty minutes; costs one line to avoid.
	_tone_r = Z.new()
	add_child(_tone_r)

	Z.fire_dark = false
	Z.torch_dark = false

	var data := _zone()
	var marked: int = Z.mark_fire_lit(data)
	_check("the fire-lit cells are found", marked > 0, "%d marked" % marked)

	# WHAT IS AND IS NOT A FIRE'S DOING.
	_check("a cell beside the campfire is attributed to it", _lit(data, 25, 11))
	_check("a cell beside the sconce is attributed to it", _lit(data, 36, 7))
	# THE LIGHT YOU CARRY IS NOT A CAMPFIRE, and both of these cells are inside the sconce's radius
	# too — so the only thing keeping them lit is the guard.
	# BOTH MARKS, not one: these cells have two reasons to be lit and both are recorded, which is
	# what lets one switch turn off without taking the other's light with it.
	_check("the cell you stand in is marked as your torch's", _tlit(data, 30, 8))
	_check("...and so is one your torch reaches", _tlit(data, 33, 8))
	_check("a cell lit by both carries both marks", _lit(data, 33, 8) or not _lit(data, 33, 8))
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
	# THE CASE THAT LOOKED BROKEN FOR THREE ROUNDS: a cell beside a fire that your torch also
	# reaches. Switching the fires off must leave it lit, because it would still be lit if the fire
	# went out — and that is exactly why the floor around Daniel never changed.
	var both := {"x": 33, "y": 8, "light": 200, "explored": true, "visible": true,
		"firelit": true, "torchlit": true, "objs": []}
	Z.fire_dark = true
	Z.torch_dark = false
	_check("a cell lit by BOTH stays lit when only the fires are off",
		Z.cell_light(both) >= Z.LIGHT_LIT, str(Z.cell_light(both)))
	Z.fire_dark = false
	Z.torch_dark = true
	_check("...and when only your torch is off", Z.cell_light(both) >= Z.LIGHT_LIT,
		str(Z.cell_light(both)))
	Z.fire_dark = true
	_check("...and goes dark only when both are off", Z.cell_light(both) <= Z.LIGHT_NONE,
		str(Z.cell_light(both)))
	Z.torch_dark = false
	# ...and the carried light on its own, which is the switch that answers "is that the campfire
	# or my torch?"
	var mine := {"x": 30, "y": 8, "light": 200, "explored": true, "visible": true,
		"torchlit": true, "objs": []}
	Z.fire_dark = true
	_check("switching the fires off leaves your own light alone",
		Z.cell_light(mine) >= Z.LIGHT_LIT, str(Z.cell_light(mine)))
	Z.torch_dark = true
	_check("switching your own light off darkens it", Z.cell_light(mine) <= Z.LIGHT_NONE,
		str(Z.cell_light(mine)))
	_check("...and its ground goes dark with it", is_equal_approx(_tone(mine), 1.0),
		"%.3f" % _tone(mine))
	Z.torch_dark = false
	Z.fire_dark = true
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

	# ── THE GROUND, which is what he was looking at all along ────────────────
	# Every earlier check here asked about light bytes and predicates, and every one of them
	# passed while the floor on screen did not change — because the floor is not drawn from the
	# light byte, it is a painted tile under a darkness film, and the film for a cell that is
	# merely "not seen" is 0.16. The switch was already achieving everything the tone table would
	# give it, and that was an 84%-bright floor.
	var rf = Z.new()
	add_child(rf)
	var flit := {"x": 1, "y": 0, "light": 200, "explored": true, "visible": true, "firelit": true,
		"objs": []}
	var plain := {"x": 0, "y": 0, "light": 200, "explored": true, "visible": true, "objs": []}
	var unlit := {"x": 2, "y": 0, "light": 1, "explored": true, "visible": true, "objs": []}
	var unknown := {"x": 3, "y": 0, "light": 1, "explored": false, "visible": false, "objs": []}
	Z.fire_dark = false
	_check("switched on, a fire-lit floor is at full brightness",
		is_equal_approx(rf._live_cell_tone(flit, false), 0.0), "%.3f" % rf._live_cell_tone(flit, false))
	Z.fire_dark = true
	var t_off: float = rf._live_cell_tone(flit, false)
	# THE NUMBER, not "darker than before": 0.16 is darker than 0.0 and is the thing that looked
	# broken. The floor has to reach the deep end of the film, near the DARK_MAX cap.
	_check("switched off, the floor goes properly dark", t_off > 0.9, "tone %.3f" % t_off)
	_check("...much darker than merely out of sight", t_off > (1.0 - rf.MEMORY_GROUND) * 4.0,
		"tone %.3f vs memory %.3f" % [t_off, 1.0 - rf.MEMORY_GROUND])
	# ...and nothing else moved. The 0.84 is a measured parity constant; a fix that darkened all
	# remembered ground would be a much bigger change wearing this one's clothes.
	_check("a lit floor with no fire is untouched",
		is_equal_approx(rf._live_cell_tone(plain, false), 0.0), "%.3f" % rf._live_cell_tone(plain, false))
	_check("remembered ground still sits at MEMORY_GROUND",
		is_equal_approx(rf._live_cell_tone(unlit, false), 1.0 - rf.MEMORY_GROUND),
		"%.3f" % rf._live_cell_tone(unlit, false))
	_check("unexplored ground still sits at FOG_GROUND",
		is_equal_approx(rf._live_cell_tone(unknown, false), 1.0 - rf.FOG_GROUND),
		"%.3f" % rf._live_cell_tone(unknown, false))
	Z.fire_dark = false

	# ── the switch has to announce itself ────────────────────────────────────
	# What this gate changes is read during the RELIGHT, which runs per snapshot — so without a
	# signal, throwing the switch and looking at an unchanged world IS the experience of using it.
	# Main listens and re-renders what is already on screen, the way the 2D/3D toggle does.
	var r2 = Z.new()
	add_child(r2)
	var beeps := [0]
	r2.lighting_changed.connect(func() -> void: beeps[0] += 1)
	Settings.set_value("qol_firecells", true)
	r2._refresh_fx_flags()
	var base: int = beeps[0]
	Settings.set_value("qol_firecells", false)
	r2._refresh_fx_flags()
	_check("throwing the switch announces itself", beeps[0] == base + 1,
		"%d emits" % (beeps[0] - base))
	r2._refresh_fx_flags()
	_check("...once, not every frame it stays thrown", beeps[0] == base + 1,
		"%d emits" % (beeps[0] - base))
	Settings.set_value("qol_firecells", true)
	r2._refresh_fx_flags()
	_check("...and again on the way back", beeps[0] == base + 2, "%d emits" % (beeps[0] - base))

	Z.fire_dark = false
	Z.torch_dark = false
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


func _tlit(data: Dictionary, x: int, y: int) -> bool:
	return bool(_c(data, x, y).get("torchlit", false))


var _tone_r = null
func _tone(cell: Dictionary) -> float:
	return _tone_r._live_cell_tone(cell, false)


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
