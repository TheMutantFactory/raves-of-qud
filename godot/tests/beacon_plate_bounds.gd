extends Node

## WHERE A BEACON'S BEARING LEAVES THE ZONE, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/beacon_plate_bounds.tscn
##
## The name-plate for a place eight parasangs off was landing over the rooftops of the town the
## player is standing in — a HUD label placed from an unprojected world point, with nothing to stop
## it. The rule that fixes it is this: the plate may not be drawn below the row where its own
## bearing crosses out of the zone.
##
## Worth pinning down because it fails QUIETLY. A wrong exit point does not throw or vanish; the
## plate just settles somewhere plausible a few cells inside the zone, which is the same symptom as
## having no rule at all.

const W := 80.0
const H := 25.0

var _failed: Array[String] = []


func _ready() -> void:
	var B = load("res://LocationBeacons.gd")
	var mid := Vector2(40.0, 12.0)

	# The four cardinals leave through the face they point at.
	_near("east leaves the east face", B.zone_exit(mid, Vector2(1, 0), W, H), Vector2(80, 12))
	_near("west leaves the west face", B.zone_exit(mid, Vector2(-1, 0), W, H), Vector2(0, 12))
	_near("north leaves the north face", B.zone_exit(mid, Vector2(0, -1), W, H), Vector2(40, 0))
	_near("south leaves the south face", B.zone_exit(mid, Vector2(0, 1), W, H), Vector2(40, 25))

	# A ZONE IS 80x25, so a 45-degree bearing does NOT leave through the corner — it runs out of
	# north long before it runs out of east. Taking the wrong axis is the mistake this catches.
	_near("a diagonal leaves through the SHORT axis",
		B.zone_exit(mid, Vector2(1, 1), W, H), Vector2(53, 25))

	# From hard against a face, pointing out, the crossing is where you already stand.
	_near("standing on the edge, facing out", B.zone_exit(Vector2(0, 12), Vector2(-1, 0), W, H),
		Vector2(0, 12))
	# ...and pointing back in, it is the far face.
	_near("standing on the edge, facing in", B.zone_exit(Vector2(0, 12), Vector2(1, 0), W, H),
		Vector2(80, 12))

	# Degenerate inputs must give the caller its own point back, which _edge_row reads as "no answer"
	# rather than as a boundary at the origin.
	_same("no direction, no crossing", B.zone_exit(mid, Vector2.ZERO, W, H), mid)
	_same("no zone, no crossing", B.zone_exit(mid, Vector2(1, 0), 0.0, 0.0), mid)

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _near(name: String, got: Vector2, want: Vector2) -> void:
	_check(name, got.distance_to(want) < 0.5, "got %s wanted %s" % [got, want])

func _same(name: String, got: Vector2, want: Vector2) -> void:
	_check(name, got.is_equal_approx(want), "got %s wanted %s" % [got, want])

func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
