extends Node

## A CONTROL IS ONLY CHROME WHERE IT CAN ACTUALLY DRAW — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/feedback_clip.tscn
##
## Daniel: "When I hover the mouse, I don't see the boot icon. When I see you hover, I DO." The
## probe set the cell directly; his pointer goes through _playfield_cell, which asks
## FeedbackTool.claims() whether the point belongs to UI chrome.
##
## The minimap is a texture in a CLIPPING box — panned and zoomed by hand, so its TextureRect is
## sized to the ZOOMED MAP, thousands of pixels wide at his zoom, and reaches most of the way
## across the window while painting nothing there. The hit test asked get_global_rect().has_point()
## and answered "chrome" for all of it, so the verb cursor, click-to-walk and Ctrl+click inspection
## all went dead over the middle of the playfield. Nothing was wrong with the cursor.

var _failed: Array[String] = []


func _ready() -> void:
	# outer clips; inner is much larger than it, the way a zoomed map is larger than its panel
	var outer := Control.new()
	outer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	outer.position = Vector2(0, 0)
	outer.size = Vector2(100, 100)
	outer.clip_contents = true
	add_child(outer)
	var inner := ColorRect.new()
	inner.set_anchors_preset(Control.PRESET_TOP_LEFT)
	inner.position = Vector2(0, 0)
	inner.size = Vector2(900, 900)
	outer.add_child(inner)
	await get_tree().process_frame

	# the fixture has to be the shape the bug needs, or the checks below are about nothing
	_check("the inner control really does overhang its parent",
		inner.get_global_rect().has_point(Vector2(400, 400))
			and not outer.get_global_rect().has_point(Vector2(400, 400)))

	_check("a point inside the clip is claimed",
		FeedbackTool._deepest_control_at(Vector2(50, 50)) == inner,
		str(FeedbackTool._deepest_control_at(Vector2(50, 50))))
	_check("...and a point the parent clips away is NOT",
		FeedbackTool._deepest_control_at(Vector2(400, 400)) != inner,
		"the overhang of a clipped child still counted as chrome")
	# claims() is what _playfield_cell actually calls, and it is the answer that matters: a point
	# nothing paints must fall through to the playfield.
	_check("...so claims() lets the playfield have it",
		not FeedbackTool.claims(Vector2(400, 400)))

	# ...AND CLIPPING IS WHAT DOES IT, not the size. With the parent not clipping, the same
	# overhang is genuinely visible and must still be claimed — otherwise this "fix" would just be
	# a hole punched in the hit test.
	# NO await PAST THIS POINT. A running Raves viewer holds the instance lock and quits this
	# process after a frame or two, so a check that waits for a second frame simply never runs —
	# and prints nothing, which reads exactly like a passing test that stopped early.
	outer.clip_contents = false
	_check("an UNCLIPPED overhang is still chrome",
		FeedbackTool._deepest_control_at(Vector2(400, 400)) == inner,
		str(FeedbackTool._deepest_control_at(Vector2(400, 400))))

	# ...and the clip is INHERITED, not just checked one level up: a grandchild of a clipping box
	# is clipped by it too.
	outer.clip_contents = true
	var mid := Control.new()
	mid.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mid.size = Vector2(900, 900)
	inner.add_child(mid)
	var deep := ColorRect.new()
	deep.set_anchors_preset(Control.PRESET_TOP_LEFT)
	deep.size = Vector2(900, 900)
	mid.add_child(deep)
	mid.force_update_transform()
	deep.force_update_transform()
	_check("a grandchild inherits the clip",
		FeedbackTool._deepest_control_at(Vector2(400, 400)) != deep,
		str(FeedbackTool._deepest_control_at(Vector2(400, 400))))
	_check("...while still answering inside it",
		FeedbackTool._deepest_control_at(Vector2(50, 50)) == deep,
		str(FeedbackTool._deepest_control_at(Vector2(50, 50))))

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _check(what: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		_failed.append(what)
		print("  FAIL %s%s" % [what, ("  (%s)" % detail) if detail != "" else ""])
