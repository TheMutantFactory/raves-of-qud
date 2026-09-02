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
	var dim_unseen := {"explored": true, "visible": false, "light": 100}

	# ── the ask ──────────────────────────────────────────────────────────────
	_check("a lit floor you cannot see matches one you can",
		r._live_cell_tone(lit_unseen, true) == r._live_cell_tone(lit_seen, true),
		"%.3f vs %.3f" % [r._live_cell_tone(lit_unseen, true), r._live_cell_tone(lit_seen, true)])
	_check("...and that tone is NO film at all in full light",
		absf(r._live_cell_tone(lit_unseen, true)) < 0.0001,
		"%.3f" % r._live_cell_tone(lit_unseen, true))

	# ── and the half he rejected the first time ──────────────────────────────
	# A dim cell must still be dim out of sight. The old branch returned a flat 0.0 here, so an
	# unlit floor you could not see sat at full daylight next to a dark one you could.
	_check("a DIM floor you cannot see is still dim",
		r._live_cell_tone(dim_unseen, true) == r._live_cell_tone(dim_seen, true),
		"%.3f vs %.3f" % [r._live_cell_tone(dim_unseen, true), r._live_cell_tone(dim_seen, true)])
	_check("...and dim really is darker than lit, or the checks above are free",
		r._live_cell_tone(dim_seen, true) > r._live_cell_tone(lit_seen, true),
		"dim %.3f vs lit %.3f" % [r._live_cell_tone(dim_seen, true),
			r._live_cell_tone(lit_seen, true)])

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
	var off := {"explored": true, "visible": false, "light": 0, "lit": 200}
	_check("a switched-off cell still takes the deepest tone",
		absf(r._live_cell_tone(off, true) - 1.0) < 0.0001, "%.3f" % r._live_cell_tone(off, true))
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
