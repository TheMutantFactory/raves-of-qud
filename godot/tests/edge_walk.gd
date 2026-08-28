extends Node

## WHICH WAY OUT OF THE ZONE A CLICK POINTS, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/edge_walk.tscn
##
## Raves draws the neighbouring zones, so a click can land in one, and the only thing standing
## between that click and a walk is this rule. It is worth pinning down because a wrong answer has
## no symptom: the player walks off in a plausible direction that is simply not the one they
## pointed at, and that reads as Qud's pathing being odd rather than as a bug here.
##
## A ZONE IS 80x25, which is the whole point. Three cells past the south edge and three past the
## east edge is not a tie -- it is an eighth of the way down a zone against a twenty-sixth of the
## way across one -- so the axes are compared as FRACTIONS. Counting raw cells sends that click
## east, which is the mistake this file exists to catch.

const W := 80
const H := 25

var _failed: Array[String] = []


func _ready() -> void:
	var M = load("res://Main.gd")

	# Inside the zone is not an edge click at all — every corner and both boundaries.
	for c in [Vector2i(0, 0), Vector2i(79, 24), Vector2i(40, 12), Vector2i(0, 24), Vector2i(79, 0)]:
		_check("inside the zone: %s" % c, M.edge_dir_for(c, W, H) == "",
			"got %s" % M.edge_dir_for(c, W, H))

	# One cell past each boundary.
	_check("one past the north edge", M.edge_dir_for(Vector2i(40, -1), W, H) == "N", "")
	_check("one past the south edge", M.edge_dir_for(Vector2i(40, 25), W, H) == "S", "")
	_check("one past the west edge", M.edge_dir_for(Vector2i(-1, 12), W, H) == "W", "")
	_check("one past the east edge", M.edge_dir_for(Vector2i(80, 12), W, H) == "E", "")

	# THE CASE THAT DECIDES THE RULE. Equal overflow in CELLS, and the answer is the short axis.
	_check("equal cell overflow goes the short way (S, not E)",
		M.edge_dir_for(Vector2i(83, 28), W, H) == "S",
		"got %s" % M.edge_dir_for(Vector2i(83, 28), W, H))
	_check("...and to the north-west corner, N",
		M.edge_dir_for(Vector2i(-3, -3), W, H) == "N",
		"got %s" % M.edge_dir_for(Vector2i(-3, -3), W, H))
	# ...but a click far enough along the LONG axis still goes that way.
	_check("far east, barely south, goes east",
		M.edge_dir_for(Vector2i(120, 26), W, H) == "E",
		"got %s" % M.edge_dir_for(Vector2i(120, 26), W, H))

	# A zone whose size has not arrived yet must not produce a direction out of nothing.
	_check("no zone size, no direction", M.edge_dir_for(Vector2i(90, 30), 0, 0) == "",
		"invented a direction")

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
