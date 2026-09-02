extends Node

## HOW MANY RINGS OF REMEMBERED ZONES RENDER — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/visible_zone_ring.tscn
##
## Daniel: "let's widen the visible ring past the 3x3 and add that as a radius setting."
##
## _zone_beyond_ramp is the ONE predicate the whole far path turns on — _sync_neighbors hides the
## zone, _build_darkness bakes it as a single flat rectangle instead of 2000 per-cell quads, and the
## crossing's re-bake skip leaves it alone. It used to be a CELL distance, which read as "the 3x3"
## because the second ring starts a whole zone width out. Now it asks for the ring directly.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")
const W := 80
const H := 25


func _ready() -> void:
	var r = Z.new()
	add_child(r)
	r._live_w = float(W)
	r._live_h = float(H)

	# ── the ring arithmetic ──────────────────────────────────────────────────
	for c in [[Vector2i(0, 0), 0], [Vector2i(W, 0), 1], [Vector2i(-W, 0), 1],
			[Vector2i(0, H), 1], [Vector2i(W, H), 1], [Vector2i(2 * W, 0), 2],
			[Vector2i(-2 * W, H), 2], [Vector2i(2 * W, 3 * H), 3]]:
		var off: Vector2i = c[0]
		var want: int = c[1]
		_check("%s is ring %d" % [str(off), want], r._zone_ring(off) == want,
			"got %d" % r._zone_ring(off))

	# CEIL, NOT FLOOR, and it needs a non-multiple to say so. Real zone offsets are always whole
	# zones, so floor and ceil agree on every offset the game produces and swapping them passed
	# the whole suite. The rule is still ceil on purpose — any part of a zone past the boundary
	# puts it in the next ring out — and a fractional offset is the only thing that can hold that
	# in place if the neighbour set ever stops being zone-aligned.
	_check("a partial offset rounds OUT to the next ring",
		r._zone_ring(Vector2i(W / 2, 0)) == 1, "got %d" % r._zone_ring(Vector2i(W / 2, 0)))
	_check("...and a hair past a whole zone is the ring after it",
		r._zone_ring(Vector2i(W + 1, 0)) == 2, "got %d" % r._zone_ring(Vector2i(W + 1, 0)))

	# ── the default is the old behaviour, offset for offset ──────────────────
	# THE CHECK THIS FILE EXISTS FOR. The old predicate was a cell distance against
	# penumbra_radius; the new one is a ring count. They must agree everywhere at radius 1, or the
	# default view quietly changed while nobody was looking at it.
	r.visible_zone_radius = 1
	var disagreed := 0
	var saw_true := false
	var saw_false := false
	for ry in range(-3, 4):
		for rx in range(-3, 4):
			var off := Vector2i(rx * W, ry * H)
			var old := _old_beyond_ramp(off, r.penumbra_radius)
			var new_answer: bool = r._zone_beyond_ramp(off)
			if old != new_answer:
				disagreed += 1
			if new_answer: saw_true = true
			else: saw_false = true
	_check("at radius 1 the new gate matches the old one on every offset", disagreed == 0,
		"%d offsets disagree" % disagreed)
	_check("...and the sweep saw both answers, so agreement means something",
		saw_true and saw_false)

	# ── and the knob actually widens it ──────────────────────────────────────
	var ring2 := Vector2i(2 * W, 0)
	var ring3 := Vector2i(0, 3 * H)
	r.visible_zone_radius = 1
	_check("at radius 1 the second ring is far", r._zone_beyond_ramp(ring2))
	r.visible_zone_radius = 2
	_check("at radius 2 the second ring renders for real", not r._zone_beyond_ramp(ring2))
	_check("...and the third is still far", r._zone_beyond_ramp(ring3))
	r.visible_zone_radius = 3
	_check("at radius 3 the third ring renders too", not r._zone_beyond_ramp(ring3))
	_check("...and the live zone is never 'far' at any radius",
		not r._zone_beyond_ramp(Vector2i(0, 0)))

	# ── it no longer answers to the FADE slider ──────────────────────────────
	# The old gate read penumbra_radius, which is the ramp's width in CELLS and had nothing to say
	# about zones — it only ever looked like it did because every value under a zone-width gave the
	# same answer.
	r.visible_zone_radius = 1
	var at_default: bool = r._zone_beyond_ramp(ring2)
	r.penumbra_radius = 16
	_check("the ramp width does not move the ring boundary",
		r._zone_beyond_ramp(ring2) == at_default)

	# ── the setting is registered and defaults to the old view ───────────────
	_check("visible_zone_radius is a real setting", Settings.DEFAULTS.has("visible_zone_radius"))
	_check("...defaulting to 1, which is the 3x3 the renderer has always drawn",
		int(Settings.DEFAULTS.get("visible_zone_radius", -1)) == 1,
		str(Settings.DEFAULTS.get("visible_zone_radius", "absent")))

	_report()


## The predicate as it stood before this change, kept here so the two can be compared rather than
## trusted: nearest CELL of the neighbour, against the ramp width.
func _old_beyond_ramp(off: Vector2i, penumbra: int) -> bool:
	var dx := 0
	if off.x + W - 1 < 0:
		dx = -(off.x + W - 1)
	elif off.x > W - 1:
		dx = off.x - (W - 1)
	var dy := 0
	if off.y + H - 1 < 0:
		dy = -(off.y + H - 1)
	elif off.y > H - 1:
		dy = off.y - (H - 1)
	return maxi(dx, dy) >= penumbra + 1


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
