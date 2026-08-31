extends Node

## EVERY CELL WEARS QUD'S FIELD — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/ground_field.tscn
##
## Daniel, after six rounds of this: "It looks the same." He was right every time, and every
## measurement I made was true and beside the point. Qud paints the field colour in EVERY cell and
## draws glyphs on it, so its ground is never a hole; Raves painted a black film over unexplored
## cells to hide their floor art and left a void. Sampling a remembered cell said 42.5 against
## Qud's 45.7 — a fine match, and a small part of the picture — while the rest of the map, the part
## that dominates what you actually see, was near-black.
##
## Measured on the whole view after the change: Raves' dominant colour is (17,52,51) lum 41.4 over
## 354k pixels against Qud's (15,59,58) lum 45.7, and it is the DOMINANT colour now, as in Qud.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")


func _ready() -> void:
	Z.fire_dark = false
	Z.torch_dark = false

	var seen := {"x": 0, "y": 0, "light": 200, "visible": true, "explored": true, "objs": []}
	var remembered := {"x": 1, "y": 0, "light": 1, "visible": false, "explored": true, "objs": []}
	var never := {"x": 2, "y": 0, "light": 1, "visible": false, "explored": false, "objs": []}

	_check("a cell you can see wears no field — its own art shows",
		Z.ground_cover(seen) == Z.COVER_NONE, str(Z.ground_cover(seen)))
	_check("a remembered cell wears the field, with a trace of floor through it",
		Z.ground_cover(remembered) == Z.COVER_MEMORY, str(Z.ground_cover(remembered)))
	# THE ONE THAT WAS A VOID. The black film here was hiding floor art, which the field does too —
	# in Qud's colour instead of a hole.
	_check("a cell you have NEVER seen wears the field outright",
		Z.ground_cover(never) == Z.COVER_FULL, str(Z.ground_cover(never)))

	# UNEXPLORED OUTRANKS UNSEEN. A cell can be both, and the answer must be the full field rather
	# than the memory wash — memory is for a place you have been.
	var both := {"x": 3, "y": 0, "light": 1, "visible": false, "explored": false, "objs": []}
	_check("never-seen beats merely-unseen", Z.ground_cover(both) == Z.COVER_FULL)

	# ...and the firelight switch reaches this too: a cell whose only light was a fire you have
	# switched off is no longer SEEN, so it falls back to memory rather than staying at full art.
	var firelit := {"x": 4, "y": 0, "light": 200, "visible": true, "explored": true,
		"firelit": true, "objs": []}
	_check("with firelight on, a fire-lit cell is seen", Z.ground_cover(firelit) == Z.COVER_NONE)
	Z.fire_dark = true
	_check("...and with it off, it wears the memory field",
		Z.ground_cover(firelit) == Z.COVER_MEMORY, str(Z.ground_cover(firelit)))
	Z.fire_dark = false

	# THE THREE ANSWERS ARE DISTINCT. A decision that collapsed two of them would pass every check
	# above that only names one.
	_check("the three covers are three different answers",
		Z.COVER_NONE != Z.COVER_MEMORY and Z.COVER_MEMORY != Z.COVER_FULL
			and Z.COVER_NONE != Z.COVER_FULL)

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
