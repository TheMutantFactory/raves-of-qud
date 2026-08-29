extends Node

## WHERE THE WIND BLOWS — the whole dust decision, asked without a renderer.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/dust_zones.tscn
##
## WHY IT EXISTS. Daniel: "I'm in a subterranean desert canyon. There is no dust blowing
## underground." The zone's NAME picks the wind, and Qud goes on calling a place a desert canyon at
## every stratum beneath it — so the name alone blew dust through a cave with no sky above it. The
## name is necessary and was never sufficient.

var _failed: Array[String] = []

const Z = preload("res://ZoneRenderer.gd")


func _ready() -> void:
	# THE DESERT PROPER — open, bare, exposed. The name still decides.
	for t in ["salt dunes", "sandy wastes", "scrubland", "salt flats", "the desert"]:
		_check("surface: %s blows" % t, Z.dust_wanted(t, false, false, false, false))

	# ...and the places that are not it. Wet ones, as before —
	for t in ["salt marsh, surface", "river ford", "watery cave"]:
		_check("surface: %s stays still" % t, not Z.dust_wanted(t, false, false, false, false))

	# — and now the canyons. Daniel: "The canyons are oasis of life. No dust."
	#
	# THE CHECK THAT MATTERS IS THE FIRST ONE, and it is why DUST_NEVER exists as its own list
	# instead of "canyon" simply being absent from DUST_TERRAIN. Qud calls the place a "desert
	# canyon": the name still contains "desert", so an absence changes nothing and the wind keeps
	# blowing. The exclusion has to WIN, not merely abstain.
	for t in ["desert canyon", "canyon", "desert canyon, surface"]:
		_check("surface: %s stays still" % t, not Z.dust_wanted(t, false, false, false, false))

	# Depth, tested on terrain that genuinely blows — using a canyon here would pass for the
	# canyon rule and prove nothing about the stratum.
	for t in ["salt dunes", "sandy wastes", "scrubland", "salt flats"]:
		_check("underground: %s does not blow" % t, not Z.dust_wanted(t, true, false, false, false))

	# The other three suppressors still hold, so neither new rule replaced them.
	_check("1:1 blows nothing", not Z.dust_wanted("salt dunes", false, true, false, false))
	_check("flat 2D blows nothing", not Z.dust_wanted("salt dunes", false, false, true, false))
	_check("world map blows nothing", not Z.dust_wanted("salt dunes", false, false, false, true))

	# An unnamed zone is not dusty by default — a missing terrain string must not become weather.
	_check("no terrain, no wind", not Z.dust_wanted("", false, false, false, false))

	_report()


func _check(what: String, ok: bool) -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		_failed.append(what)
		print("  FAIL %s" % what)


func _report() -> void:
	if _failed.is_empty():
		print("all good (0 checks failed)")
	else:
		print("%d checks failed:" % _failed.size())
		for f in _failed:
			print("  - %s" % f)
	get_tree().quit(0 if _failed.is_empty() else 1)
