extends Node

## THE PLAYER IS DRAWN AT HOME + OFFSET, ALWAYS — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/walk_draw.tscn
##
## WHY IT EXISTS. Daniel, reading a video frame by frame: "the player is moved to the new tile.
## Then the player is moved back to the original tile. Then the camera and the player move to the
## new tile."
##
## Three phases, one missing line. The per-turn rebuild re-seats the player's sprite on its CELL —
## the destination — and the offset that carries it back to where the walk has actually reached
## was not applied until the next frame. So the sprite stood on the destination for one frame,
## snapped a whole cell backwards on the next, and only then eased across. The walk arithmetic was
## right the whole time; the sprite was drawn a frame ahead of itself.
##
## A ONE-FRAME ARTEFACT CANNOT BE CAUGHT BY SCREENSHOTS — 200ms apart, they step straight over a
## 16ms pop, which is why this was found on video and not by any check here. So the property is
## tested where it is decidable: re-seat the sprite and assert it never lands on the bare cell.

var _failed: Array[String] = []


func _ready() -> void:
	var r = load("res://ZoneRenderer.gd").new()
	add_child(r)
	var root := Node3D.new()
	add_child(root)
	r._dynamic_root = root

	# The player's sprite, seated on its cell the way a rebuild leaves it.
	var sprite := Node3D.new()
	sprite.position = Vector3(5, 0, 7)
	root.add_child(sprite)
	r._player_cell = Vector2i(5, 7)

	# Mid-step: the walk has reached a cell back from where Qud says the player is.
	r._walk_off = Vector2(-1, 0)
	r._tag_player_cell()

	_check("the rebuild finds the player's sprite", r._walk_node == sprite)
	_check("...and remembers its CELL as home", r._walk_home == Vector3(5, 0, 7),
		str(r._walk_home))
	# THE CHECK. On the destination cell is exactly the frame Daniel saw.
	_check("...but does not leave it standing on the destination",
		not sprite.position.is_equal_approx(Vector3(5, 0, 7)), str(sprite.position))
	_check("...it is drawn where the walk has reached",
		sprite.position.is_equal_approx(Vector3(4, 0, 7)), str(sprite.position))

	# A settled walk has no offset, and must not be nudged off its cell by this.
	var s2 := Node3D.new()
	s2.position = Vector3(9, 0, 2)
	root.add_child(s2)
	r._player_cell = Vector2i(9, 2)
	r._walk_off = Vector2.ZERO
	r._tag_player_cell()
	_check("a settled player sits exactly on their cell",
		s2.position.is_equal_approx(Vector3(9, 0, 2)), str(s2.position))

	# ...and set_walk_offset still moves it afterwards, from the home just captured.
	r.set_walk_offset(Vector2(0, -0.5))
	_check("the offset still moves it from that home",
		s2.position.is_equal_approx(Vector3(9, 0, 1.5)), str(s2.position))

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
