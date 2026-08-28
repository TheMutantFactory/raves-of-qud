extends Node

## THE TARGET CURSOR'S TWO PURE PARTS, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/target_cursor.tscn
##
## The prompt Qud hands over is written for its own text console, in two different markups at once,
## and the strings are real ones read off the wire: Flaming Ray's and the missile weapon's.
## The path preview is Bresenham, and it has to agree with the reticle at both ends or it is drawing
## a shot the player is not about to take.

var _failed: Array[String] = []


func _ready() -> void:
	var tc = load("res://TargetCursor.gd").new()
	add_child(tc)

	# THE REAL STRINGS. The second one is why this file exists: {{hotkey|Space}} is a NAMED tag, not
	# a colour code, and it reached the screen with its braces on.
	var cases := {
		"&W&yFlaming Ray &K| &WSpace&y-select &K| &yunlock (&WF1&y)":
			"Flaming Ray | Space-select | unlock (F1)",
		# THE ONE OFF THE WIRE, nested exactly as Qud sends it: a colour span around a hotkey span.
		# Read with control.py rather than off the rendered label, which is how the nesting was
		# missed the first time -- the screen was showing the leftover, not the source.
		"{{W|{{hotkey|Space}}}}-select | unlock ({{hotkey|F1}}) | Fire Missile Weapon":
			"Space-select | unlock (F1) | Fire Missile Weapon",
		"{{W|space}} {{W|5}}-End Wall {{C|3}} squares left  {{W|Escape}}-Clear":
			"space 5-End Wall 3 squares left  Escape-Clear",
		"plain text": "plain text",
		"": "",
	}
	for raw in cases:
		var got: String = tc._strip(raw)
		_check("strip: %s" % (raw if raw != "" else "(empty)"), got == cases[raw],
			"got %s" % [got])
	# An UNCLOSED tag must not eat the rest of the line, or a truncated prompt shows nothing at all.
	_check("an unclosed tag keeps its text", tc._strip("{{W|abc") == "abc",
		"got %s" % tc._strip("{{W|abc"))
	# A pipe in the BODY is text, not a separator — the prompt itself is full of them.
	_check("a pipe in the body survives", tc._strip("{{W|a | b}}") == "a | b",
		"got %s" % tc._strip("{{W|a | b}}"))

	# THE PATH RUNS END TO END. Both endpoints present, and the count is the Chebyshev distance
	# plus one -- the same step count Qud walks a line in.
	var line: Array = tc._bresenham(Vector2i(15, 24), Vector2i(25, 24))
	_check("the path starts at the shooter", line[0] == Vector2i(15, 24), "got %s" % line[0])
	_check("the path ends at the target", line[-1] == Vector2i(25, 24), "got %s" % line[-1])
	_check("one cell per step", line.size() == 11, "got %d" % line.size())
	var diag: Array = tc._bresenham(Vector2i(0, 0), Vector2i(5, 5))
	_check("a diagonal is 5 steps, not 10", diag.size() == 6, "got %d" % diag.size())
	_check("aiming at yourself is one cell", tc._bresenham(Vector2i(3, 3), Vector2i(3, 3)).size() == 1,
		"got %d" % tc._bresenham(Vector2i(3, 3), Vector2i(3, 3)).size())
	# THE CAP IS A BACKSTOP, not a limit anyone should reach: this runs off a cursor, and a stale
	# origin from a zone change must not spin the frame away.
	var far: Array = tc._bresenham(Vector2i(0, 0), Vector2i(100000, 0))
	_check("a runaway line is capped", far.size() <= 400, "got %d" % far.size())

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
