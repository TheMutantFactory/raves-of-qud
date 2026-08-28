extends Node

## WHICH COMMAND OWNS THE DIGIT ROW, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/qud_binds_digits.tscn
##
## WHY IT EXISTS. Qud binds the bare digit THREE times over, in three layers: CmdMoveSW (numpad 1),
## CmdAltFire1 (targeting) and CmdAbility1 (the ability bar). Its display strings render all three
## as "1", so Raves matched a bare digit against both the numpad and the digit row and gave the row
## to whichever the export listed first — CmdMoveSW. The whole ability bar was unreachable, and
## pressing 1 walked the player southwest. Measured in play: 1 moved (45,20) -> (44,21).
##
## The fixture is the real shape of the export, in the real order, with the real collision in it.
## An ordering that cannot collide would pass no matter what this file did.

var _failed: Array[String] = []


func _ready() -> void:
	var dir := "user://test_binds"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("bindings.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"categories": [
		# Qud's own order: movement first, targeting second, the ability bar last.
		{"name": "Basic Move / Attack", "commands": [
			{"id": "CmdMoveSW", "b1": "1", "b2": "", "b3": "", "b4": "", "keys": ["numpad1", "shift+leftArrow"], "layer": "AdventureNav"},
			{"id": "CmdMoveN",  "b1": "8", "b2": "", "b3": "", "b4": "", "keys": ["numpad8", "upArrow"], "layer": "AdventureNav"},
		]},
		{"name": "Targeting", "commands": [
			{"id": "CmdAltFire1", "b1": "1", "b2": "", "b3": "", "b4": "", "keys": ["1"], "layer": "Targeting"},
		]},
		{"name": "Ability Bar", "commands": [
			{"id": "CmdAbility1", "b1": "1", "b2": "", "b3": "", "b4": "", "keys": ["1"], "layer": "Adventure"},
			{"id": "CmdAbility8", "b1": "8", "b2": "", "b3": "", "b4": "", "keys": ["8"], "layer": "Adventure"},
			# A command Raves cannot spell — no `keys` (a rebind lives in the keymap, not
			# Commands.xml). It must still match SOMETHING rather than disappear.
			{"id": "CmdAbility9", "b1": "9", "b2": "", "b3": "", "b4": "", "keys": [], "layer": "Adventure"},
		]},
		{"name": "Adventuring", "commands": [
			{"id": "CmdTalk", "b1": "C", "b2": "", "b3": "", "b4": "", "keys": ["c"], "layer": "Adventure"},
		]},
	]}))
	f.close()

	var b := QudBinds.new()
	b.setup(ProjectSettings.globalize_path(dir))

	# THE DIGIT ROW BELONGS TO THE ABILITY BAR, even though movement claimed "1" first.
	# CmdAltFire1 holds digit-row 1 too, and legitimately — it is simply a bind from a screen this
	# fallback is never reached on.
	_check("a Targeting bind does not claim the row", b.match_event(_k(KEY_1)) != "CmdAltFire1",
		"the targeting layer took it")
	_check("digit-row 1 fires ability 1", b.match_event(_k(KEY_1)) == "CmdAbility1",
		"got %s" % b.match_event(_k(KEY_1)))
	_check("digit-row 8 fires ability 8", b.match_event(_k(KEY_8)) == "CmdAbility8",
		"got %s" % b.match_event(_k(KEY_8)))
	# ...and the numpad still moves. Raves intercepts the numpad before this map is consulted, but
	# the map must not have handed those keys away either.
	_check("numpad 1 still moves southwest", b.match_event(_k(KEY_KP_1)) == "CmdMoveSW",
		"got %s" % b.match_event(_k(KEY_KP_1)))
	_check("numpad 8 still moves north", b.match_event(_k(KEY_KP_8)) == "CmdMoveN",
		"got %s" % b.match_event(_k(KEY_KP_8)))
	# A bind with no unambiguous spelling keeps the old both-ways behaviour rather than vanishing.
	_check("an unspellable digit still matches on the row",
		b.match_event(_k(KEY_9)) == "CmdAbility9", "got %s" % b.match_event(_k(KEY_9)))
	_check("...and on the numpad", b.match_event(_k(KEY_KP_9)) == "CmdAbility9",
		"got %s" % b.match_event(_k(KEY_KP_9)))
	# Non-digits are untouched by any of this.
	_check("letters are unaffected", b.match_event(_k(KEY_C)) == "CmdTalk",
		"got %s" % b.match_event(_k(KEY_C)))
	# A modifier makes it a different combo, and nothing claims Shift+1 — which is exactly why the
	# camera modes moved there.
	_check("shift+1 is unclaimed (the camera's new home)", b.match_event(_k(KEY_1, true)) == "",
		"got %s" % b.match_event(_k(KEY_1, true)))

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _k(code: int, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	return e


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
