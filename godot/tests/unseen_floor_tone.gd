extends Node

## THE GROUND DOES NOT KNOW WHETHER YOU CAN SEE IT — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/unseen_floor_tone.tscn
##
## Daniel, on the fog: "the floor in obscured tiles should be the same colour as the floor with
## shown tiles. The obscured sprites are the correct colour." He said the opposite once before, and
## the two verdicts are about different things — FOG (line of sight) and LIGHT (time of day). The
## old `lit_floor` branch dropped both at once, which is why it read flat at night and was left off.
##
## The rule now: an out-of-sight cell's ground takes the same tone a visible cell with the same
## LIGHT would take. Same light, same floor, whether or not you can see it.

var _failed: Array[String] = []
const Z = preload("res://ZoneRenderer.gd")


func _ready() -> void:
	var r = Z.new()
	add_child(r)

	# `explored` and `visible` are the wire's own flag names — see ZoneRenderer.cell_is_*.
	var lit_seen := {"explored": true, "visible": true, "light": 200}
	var lit_unseen := {"explored": true, "visible": false, "light": 200}
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
			absf(r._live_cell_tone(c, true)) < 0.0001, "%.3f" % r._live_cell_tone(c, true))
	# ...and the ground you CAN see still answers to its light, or "all the same colour" would
	# have meant deleting the lighting rather than the fog.
	_check("ground you can see still darkens with its own light",
		r._live_cell_tone(dim_seen, true) > r._live_cell_tone(lit_seen, true),
		"dim %.3f vs lit %.3f" % [r._live_cell_tone(dim_seen, true),
			r._live_cell_tone(lit_seen, true)])
	_check("...and a lit cell you can see takes no film either, so the two sides MATCH",
		absf(r._live_cell_tone(lit_seen, true)) < 0.0001,
		"%.3f" % r._live_cell_tone(lit_seen, true))

	# ── the flag still buys the old behaviour back ───────────────────────────
	_check("lit_floor off restores the memory film",
		absf(r._live_cell_tone(lit_unseen, false) - (1.0 - r.MEMORY_GROUND)) < 0.0001,
		"%.3f" % r._live_cell_tone(lit_unseen, false))
	_check("...and it is ON by default now",
		bool(Settings.DEFAULTS.get("lit_floor", false)),
		str(Settings.DEFAULTS.get("lit_floor", "absent")))

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
		absf(r._live_cell_tone(off, true) - 1.0) < 0.0001, "%.3f" % r._live_cell_tone(off, true))
	Z.fire_dark = false
	var never := {"explored": false, "visible": false, "light": 200}
	_check("an unexplored cell is still fog, not floor",
		absf(r._live_cell_tone(never, true) - (1.0 - r.FOG_GROUND)) < 0.0001,
		"%.3f" % r._live_cell_tone(never, true))

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
