extends Node

## THE GROUND DOES NOT KNOW WHETHER YOU CAN SEE IT — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/unseen_floor_tone.tscn
##
## Daniel, twice: "the floor in obscured tiles should be the same colour as the floor with shown
## tiles. The obscured sprites are the correct colour", then "you are currently adding a shadow onto
## the floor tiles of blocked line-of-sight. Don't add that. Just have all the ground the same
## colour. The sprite shading will do the work."
##
## The rule: ground you cannot see takes NO film of any kind. Not the memory film, and not the
## cell's light either — a blocked cell is usually unlit, so that reached the same shadow by
## another route. Line of sight is carried entirely by the sprites.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")


func _ready() -> void:
	var r = Z.new()
	add_child(r)

	# `explored` and `visible` are the wire's own flag names — see ZoneRenderer.cell_is_*.
	var lit_seen := {"explored": true, "visible": true, "light": 200}
	var dim_seen := {"explored": true, "visible": true, "light": 100}

	# ── the ask ──────────────────────────────────────────────────────────────
	# "Don't add that. Just have all the ground the same colour. The sprite shading will do the
	# work." No film of any kind on ground you cannot see — not the memory film, and not the
	# light term either, which was my compromise and reached the same shadow by another route
	# (a blocked cell is usually unlit, so `1 - _light_frac` darkened it anyway).
	for name in ["lit", "dim", "dark"]:
		var c := {"explored": true, "visible": false,
			"light": {"lit": 200, "dim": 100, "dark": 2}[name]}
		_check("blocked line of sight puts NO film on %s ground" % name,
			absf(r._live_cell_tone(c)) < 0.0001, "%.3f" % r._live_cell_tone(c))
	# ...and the ground you CAN see still answers to its light, or "all the same colour" would
	# have meant deleting the lighting rather than the fog.
	_check("ground you can see still darkens with its own light",
		r._live_cell_tone(dim_seen) > r._live_cell_tone(lit_seen),
		"dim %.3f vs lit %.3f" % [r._live_cell_tone(dim_seen),
			r._live_cell_tone(lit_seen)])
	_check("...and a lit cell you can see takes no film either, so the two sides MATCH",
		absf(r._live_cell_tone(lit_seen)) < 0.0001,
		"%.3f" % r._live_cell_tone(lit_seen))

	# ── AND NO SETTING CAN PUT THE FILM BACK ─────────────────────────────────
	# `lit_floor` used to gate this. It defaulted off, was not in the Options screen, and — since
	# get_value reads the stored file BEFORE the default — a settings.json that already carried
	# the key pinned it false forever. Two commits that "fixed" the floor were inert on Daniel's
	# own machine for exactly that reason, and all he could see was "It looks the same". The check
	# is that the key is gone, not that it defaults the right way.
	_check("lit_floor is gone from the settings registry",
		not Settings.DEFAULTS.has("lit_floor"), "still registered")

	# ── nothing else moved ───────────────────────────────────────────────────
	# A cell the firelight switch turned off is the deepest the live zone goes, seen or not, and a
	# never-explored cell is fog — neither is a floor question.
	# A REAL switched-off fixture: Qud lit it (raw light 200) and the firelight FEATURE turned it
	# off, so cell_light() reads NONE. My first version set light 0 outright, which is not
	# "switched off" at all — it is an unlit cell, and it passed for the wrong reason under the
	# previous rule. Both flags are needed, and the check is worthless without the precondition.
	Z.fire_dark = true
	var off := {"explored": true, "visible": false, "light": 200, "firelit": true}
	_check("the fixture really is switched off, not merely dark", Z.switched_off(off))
	_check("...and a switched-off cell still takes the deepest tone",
		absf(r._live_cell_tone(off) - 1.0) < 0.0001, "%.3f" % r._live_cell_tone(off))
	Z.fire_dark = false
	var never := {"explored": false, "visible": false, "light": 200}
	_check("an unexplored cell is still fog, not floor",
		absf(r._live_cell_tone(never) - (1.0 - r.FOG_GROUND)) < 0.0001,
		"%.3f" % r._live_cell_tone(never))

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
