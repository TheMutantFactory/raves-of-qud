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

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _ground() -> Dictionary:
	return {"tile": "Tiles/tile-dirt1.png", "ground": true}

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
