extends Node

## A CAVE HAS NO SUN, and the renderer has to be told — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/cave_daylight.tscn
##
## SkyGrade.set_daylight() reaches the renderer only from _update_sky, and _update_time returns to
## _apply_cave_lighting before it ever gets there. So underground the renderer went on holding the
## daylight of the last SURFACE zone: descend at noon and every campfire's ground pool was gated
## off (_fire_glow_mul is zero above 0.25 daylight), restart the app down there and _daylight came
## back 0.0 and they all lit again. The visible state of firelight in a cave depended on where you
## last stood outside, and on whether the process had been restarted since.

var _failed: Array[String] = []


func _ready() -> void:
	var sky = load("res://SkyGrade.gd").new()
	add_child(sky)
	var spy := Spy.new()
	# setup(), NOT a hand-set _renderer: the sun and moon nodes are built here, and _update_sky
	# returns early while _sun is null — so a test that skipped it would find the surface never
	# told anything and mistake that for the bug it is looking for.
	sky.setup(true, spy)

	# NOON ON THE SURFACE first, so the value underground has something to be stale FROM. A cave
	# tested from a fresh renderer would read 0.0 whether or not anything set it.
	var noon := {"segment": 6000, "segmentsPerDay": 12000, "startOfDay": 3250,
		"startOfNight": 10000}
	sky.update(noon, sky.SURFACE_Z, Vector3.ZERO)
	_check("the surface still gets its daylight", spy.got > 0.5, "%.2f" % spy.got)

	# ...and now down one stratum, at the same hour.
	sky.update(noon, sky.SURFACE_Z + 1, Vector3.ZERO)
	_check("a cave is told there is no sun", is_equal_approx(spy.got, 0.0), "%.2f" % spy.got)

	# Deeper, and at an hour that is unambiguously night, so neither answer can be an accident of
	# the clock.
	var night := {"segment": 11500, "segmentsPerDay": 12000, "startOfDay": 3250,
		"startOfNight": 10000}
	sky.update(night, sky.SURFACE_Z + 9, Vector3.ZERO)
	_check("...at any depth", is_equal_approx(spy.got, 0.0), "%.2f" % spy.got)

	# BACK UP: the cave must not have pinned it. A fix that simply stopped the value moving would
	# pass both checks above and leave the surface permanently dark.
	sky.update(noon, sky.SURFACE_Z, Vector3.ZERO)
	_check("surfacing at noon brings the daylight back", spy.got > 0.5, "%.2f" % spy.got)

	# THE POINT OF ALL THIS, asked of the renderer rather than of SkyGrade: a fire's pool is
	# darkness-gated, so a stale noon underground is the difference between a lit campfire and an
	# unlit one.
	var r = load("res://ZoneRenderer.gd").new()
	add_child(r)
	r.set_daylight(1.0)
	_check("a fire's pool is gated off in daylight", is_equal_approx(r._fire_glow_mul(), 0.0),
		"%.2f" % r._fire_glow_mul())
	r.set_daylight(0.0)
	_check("...and full in the dark", r._fire_glow_mul() > 0.99, "%.2f" % r._fire_glow_mul())

	_report()


class Spy extends Node:
	var got := -1.0
	func set_daylight(v: float) -> void:
		got = v


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
