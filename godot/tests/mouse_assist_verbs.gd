extends Node

## The mouse-assist VERB TABLE, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/mouse_assist_verbs.tscn
##
## WHY IT EXISTS. Two of the five verbs can be checked by hovering the live game — boots over open
## ground, the hand over a creature — and the other three cannot be summoned on demand: the zone has
## to contain stairs, or a talker, or a wall where you want one. That is exactly the shape of thing
## that ships half-tested and is found later by someone standing on a staircase.
##
## verb_at is a pure function of the cell's objects, so it can be asked directly. The fixtures are
## the wire's own shape — `tile`, `talks`, `wall`, `ground` — not a tidied-up version of it.

const MA = preload("res://MouseAssist.gd")
var _failed: Array[String] = []


func _ready() -> void:
	var ma = load("res://MouseAssist.gd").new()
	add_child(ma)

	var cells := {
		"walk over bare ground":        [[_ground()], "walk"],
		"use, over a thing on the floor": [[_ground(), _thing()], "use"],
		"use, over a creature with nothing to say": [[_ground(), _creature(false)], "use"],
		"talk, over one that has":      [[_ground(), _creature(true)], "talk"],
		"down, over stairs down":       [[_ground(), _stairs("Tiles2/sw_stairsdown.bmp")], "down"],
		"up, over stairs up":           [[_ground(), _stairs("Tiles2/sw_stairsup.bmp")], "up"],
		"nothing over a wall":          [[_ground(), _wall()], ""],
		"nothing over an unseen cell":  [[], ""],
		# A PUDDLE IS SCENERY YOU WADE THROUGH. It used to answer "use", and since the click
		# ACTION reads the same verb, a left click on shallow water tried to interact with the
		# water instead of walking into it.
		"walk over a puddle":           [[_ground(), _pool()], "walk"],
		"walk over deep water too":     [[_ground(), _pool("Liquids/Water/deep-00100010.png")], "walk"],
		# ...AND IT MUST NOT SWALLOW WHAT IS STANDING IN IT. This is the mistake that would be
		# harder to notice than the one being fixed: an item lost behind a walk icon.
		"use, over a thing in a puddle": [[_ground(), _pool(), _thing()], "use"],
		"talk, over someone in a puddle": [[_ground(), _pool(), _creature(true)], "talk"],
		"nothing over a flooded wall":  [[_ground(), _pool(), _wall()], ""],
		# A WATERSKIN HAS A LiquidVolume. On the `liquid` flag alone it would read as ground and
		# the item would disappear from the cursor — which is why is_pool wants the tile too.
		"use, over a dropped waterskin": [[_ground(), _waterskin()], "use"],
	}
	var i := 0
	for name in cells:
		var objs: Array = cells[name][0]
		var want: String = cells[name][1]
		ma.set_snapshot({"cells": [{"x": i, "y": 0, "objs": objs}]})
		var got: String = ma.verb_at(Vector2i(i, 0))
		_check(name, got == want, "wanted %s, got %s" % [want, got])
		i += 1

	# THE TALKER WINS OVER THE THING IT IS STANDING ON, because a cell is usually both: a farmer
	# stands on painted ground beside his own dropped basket, and the cursor has to pick one.
	ma.set_snapshot({"cells": [{"x": 50, "y": 0, "objs": [_ground(), _thing(), _creature(true)]}]})
	_check("a talker outranks the clutter under it", ma.verb_at(Vector2i(50, 0)) == "talk",
		"got %s" % ma.verb_at(Vector2i(50, 0)))
	# ...and a person standing ON the stairs is still someone to speak to — you were not going to
	# walk through them. Asserted in BOTH object orders, because the first version of verb_at
	# returned on the first match and this answer depended on which way round the mod listed them.
	for order in [[_ground(), _creature(true), _stairs("Tiles2/sw_stairsdown.bmp")],
			[_ground(), _stairs("Tiles2/sw_stairsdown.bmp"), _creature(true)]]:
		ma.set_snapshot({"cells": [{"x": 51, "y": 0, "objs": order}]})
		_check("a talker on the stairs is a talker, whichever order the cell lists",
			ma.verb_at(Vector2i(51, 0)) == "talk", "got %s" % ma.verb_at(Vector2i(51, 0)))

	# is_pool wants BOTH signals, asserted directly because each half alone is a real object in
	# the game: a waterskin carries the flag, and Liquids/ art is drawn without one by the
	# renderer's own splash paths.
	_check("a pool is a LiquidVolume drawn from Liquids/", MA.is_pool(_pool()))
	_check("...not the flag alone", not MA.is_pool(_waterskin()))
	_check("...and not the tile alone",
		not MA.is_pool({"tile": "Liquids/Water/shallow-10001000.png"}))
	_check("...case and separator do not matter",
		MA.is_pool({"liquid": true, "tile": "LIQUIDS\\Water\\shallow-1.png"}))

	# ── the mark carries its own contrast ────────────────────────────────────
	# "The walk boots aren't showing when I hover over water." They were: pale-and-blue boots on
	# pale-and-blue ripples. A dark rim is what lets any verb sit on any ground.
	var art := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	art.fill(Color(0, 0, 0, 0))
	art.set_pixel(1, 1, Color(1, 1, 1, 1))
	var rim: Image = ma._outlined(ImageTexture.create_from_image(art)).get_image()
	_check("the rim grows the art by a pixel on every side",
		rim.get_width() == 6 and rim.get_height() == 6, "%dx%d" % [rim.get_width(), rim.get_height()])
	_check("...the art itself is untouched", rim.get_pixel(2, 2).is_equal_approx(Color(1, 1, 1, 1)),
		str(rim.get_pixel(2, 2)))
	_check("...its neighbours become opaque rim", rim.get_pixel(1, 1).a > 0.5
		and rim.get_pixel(3, 3).a > 0.5 and rim.get_pixel(2, 1).a > 0.5)
	_check("...and the rim is DARK, or it is not contrast", rim.get_pixel(1, 1).v < 0.25,
		str(rim.get_pixel(1, 1)))
	_check("...while a pixel away from the art stays clear", rim.get_pixel(5, 5).a < 0.5,
		str(rim.get_pixel(5, 5)))
	# ...AND _icon_for APPLIES IT. Checked on "use", whose art is drawn in code and needs no
	# exported tiles — otherwise this test would only pass on a machine that has run Qud.
	var plain: Texture2D = ma._look_tex()
	var iconed: Texture2D = ma._icon_for("use")
	_check("every verb's icon goes out rimmed", plain != null and iconed != null
		and iconed.get_size() == plain.get_size() + Vector2(2, 2),
		"%s vs %s" % [str(iconed.get_size() if iconed else null), str(plain.get_size() if plain else null)])

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _ground() -> Dictionary:
	return {"tile": "Tiles/tile-dirt1.png", "ground": true}

## The wire's own shape for a liquid pool: the mod sets `liquid` from go.LiquidVolume != null.
func _pool(tile := "Liquids/Water/shallow-10001000.png") -> Dictionary:
	return {"tile": tile, "display": "puddle of dilute salt", "liquid": true}

## A container that HOLDS liquid — same flag, ordinary item art.
func _waterskin() -> Dictionary:
	return {"tile": "Items/sw_waterskin.bmp", "display": "waterskin", "liquid": true}

func _thing() -> Dictionary:
	return {"tile": "Items/sw_basket.bmp", "display": "wicker basket"}

func _creature(talks: bool) -> Dictionary:
	return {"tile": "Creatures/sw_farmer.bmp", "display": "watervine farmer",
		"creature": true, "talks": talks}

func _stairs(tile: String) -> Dictionary:
	return {"tile": tile, "display": "stairs"}

func _wall() -> Dictionary:
	return {"tile": "Walls/sw_rock.bmp", "display": "rock wall", "wall": true, "occluding": true}


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s  — %s" % [name, detail])
