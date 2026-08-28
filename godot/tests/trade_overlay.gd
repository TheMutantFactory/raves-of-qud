extends Node

## THE TRADE BOARD'S CLICK ARITHMETIC, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/trade_overlay.tscn
##
## A trade row is a STACK, not a checkbox: 49 shotgun shells are one line, and the difference
## between "one" and "all of them" is real money. The rule is small enough to hold in your head and
## exactly the kind that goes wrong off by one -- selecting 50 of 49, or a right-click on an empty
## row wrapping round to the whole stack.

var _failed: Array[String] = []


func _ready() -> void:
	var T = load("res://TradeOverlay.gd")

	_check("left click takes one", T.want_for(MOUSE_BUTTON_LEFT, false, 0, 49) == 1, "")
	_check("...and one more", T.want_for(MOUSE_BUTTON_LEFT, false, 5, 49) == 6, "")
	_check("left click stops at the stack", T.want_for(MOUSE_BUTTON_LEFT, false, 49, 49) == 49,
		"got %d" % T.want_for(MOUSE_BUTTON_LEFT, false, 49, 49))
	_check("shift-left takes the stack", T.want_for(MOUSE_BUTTON_LEFT, true, 0, 49) == 49, "")

	_check("right click gives one back", T.want_for(MOUSE_BUTTON_RIGHT, false, 6, 49) == 5, "")
	# THE ONE THAT WOULD BITE: a right click on a row holding nothing must stay at nothing, not
	# wrap to the whole stack the way a modulo would.
	_check("right click on an empty row stays empty",
		T.want_for(MOUSE_BUTTON_RIGHT, false, 0, 49) == 0,
		"got %d" % T.want_for(MOUSE_BUTTON_RIGHT, false, 0, 49))
	_check("shift-right clears the row", T.want_for(MOUSE_BUTTON_RIGHT, true, 30, 49) == 0, "")

	# A single item is a stack of one, and both directions must terminate on it.
	_check("a lone item picks up", T.want_for(MOUSE_BUTTON_LEFT, false, 0, 1) == 1, "")
	_check("...and cannot be doubled", T.want_for(MOUSE_BUTTON_LEFT, false, 1, 1) == 1, "")

	# Anything else is not this board's click — the middle button must not silently mean "add one".
	_check("the middle button is not an answer", T.want_for(MOUSE_BUTTON_MIDDLE, false, 0, 49) == -1,
		"got %d" % T.want_for(MOUSE_BUTTON_MIDDLE, false, 0, 49))
	_check("the wheel is not an answer", T.want_for(MOUSE_BUTTON_WHEEL_UP, false, 0, 49) == -1, "")

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
