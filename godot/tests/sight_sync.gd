extends Node

## THE SIGHT AREA WAITS FOR THE PLAYER — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/sight_sync.tscn
##
## Daniel: "The player and the area of sight are not in sync." The fog is built from the snapshot's
## cells, so it took the new field of view the instant Qud resolved the turn while its owner was
## still a fifth of a second behind it. It is double-buffered now: this turn's fog waits, hidden,
## until the walk is more than half way, then cuts in under the player.
##
## THE INVARIANT UNDER TEST IS "EXACTLY ONE VISIBLE". Everything that can go wrong here is a
## counting error — both hidden and the zone flashes fully lit, both shown and the fog draws twice.

var _failed: Array[String] = []


func _ready() -> void:
	var r = load("res://ZoneRenderer.gd").new()
	add_child(r)
	r._dark_root = Node3D.new()
	add_child(r._dark_root)

	# FIRST FOG EVER: nothing to wait behind, so it shows at once. Entering a zone must not spend
	# half a step fully lit.
	var d0: Node3D = r._swap_dark()
	_check("the first sight area shows immediately", d0.visible)
	_check("...and it is the only one", _shown(r) == 1, "%d shown" % _shown(r))

	# A STEP: the new fog waits, the old one holds the screen.
	r._walk_off = Vector2(0, -0.9)
	var d1: Node3D = r._swap_dark()
	r.set_walk_offset(Vector2(0, -0.9))
	_check("a step leaves the new sight area waiting", not d1.visible)
	_check("...with the old one still on screen", d0.visible and _shown(r) == 1,
		"%d shown" % _shown(r))

	# Not yet half way.
	r.set_walk_offset(Vector2(0, -0.6))
	_check("still waiting at 0.6 of a cell out", not d1.visible)

	# Past half way: it cuts in, under the player.
	r.set_walk_offset(Vector2(0, -0.4))
	_check("it cuts in past the half way point", d1.visible)
	_check("...and the old one goes", _shown(r) == 1, "%d shown" % _shown(r))

	# STEPPING AGAIN BEFORE THE SWAP — what holding a direction does. The naive version promotes a
	# fog that was never shown into the "on screen" slot, leaving BOTH hidden and the zone lit.
	r._walk_off = Vector2(0, -0.9)
	var d2: Node3D = r._swap_dark()
	r.set_walk_offset(Vector2(0, -0.9))
	_check("second step: the new one waits", not d2.visible)
	var d3: Node3D = r._swap_dark()
	r.set_walk_offset(Vector2(0, -0.9))
	_check("a THIRD step still leaves exactly one on screen", _shown(r) == 1,
		"%d shown" % _shown(r))
	_check("...and it is not the one still waiting", not d3.visible)
	r.set_walk_offset(Vector2(0, 0.0))
	_check("arriving shows the newest", d3.visible and _shown(r) == 1, "%d shown" % _shown(r))

	# STANDING STILL: no walk, so a new turn's fog is current at once.
	var d4: Node3D = r._swap_dark()
	r.set_walk_offset(Vector2.ZERO)
	_check("standing still, the sight area is never behind", d4.visible and _shown(r) == 1,
		"%d shown" % _shown(r))

	_report()


## How many sight-area buffers are on screen. Counts live children, so a freed one does not count.
func _shown(r) -> int:
	var n := 0
	for c in r._dark_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion() and (c as Node3D).visible:
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
