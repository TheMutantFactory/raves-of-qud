extends Node

## ONE TREE WALK PER SWEEP, SAME ANSWERS — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/feedback_batch.tscn
##
## The assist sweep asks FeedbackTool 1152 points and every one used to walk the whole Control
## tree — twice, since _playfield_cell asks claims() again — so a sweep took 22 seconds against a
## 10s wait, and I called that a crash for a session. begin_batch() walks once and every query
## reads that; the tree cannot change between two points of the same frame.
##
## THE ONLY THING THAT MATTERS HERE IS THAT THE ANSWERS DO NOT MOVE. A faster hit test that decides
## differently would take click-to-walk and the verb cursor with it, which is exactly what the last
## bug in this file did.

var _failed: Array[String] = []
var _tool


func _ready() -> void:
	_tool = load("res://FeedbackTool.gd").new()
	add_child(_tool)

	# A little window: chrome on the left, a play hole on the right carrying feedback_skip, and a
	# clipped box whose child reaches far outside what it may paint (the minimap's shape).
	var root := Control.new()
	root.size = Vector2(400, 200)
	add_child(root)
	var chrome := ColorRect.new()
	chrome.position = Vector2(0, 0)
	chrome.size = Vector2(200, 200)
	root.add_child(chrome)
	var hole := ColorRect.new()
	hole.position = Vector2(200, 0)
	hole.size = Vector2(200, 200)
	hole.set_meta("feedback_skip", true)
	root.add_child(hole)
	# ...with something INSIDE it. feedback_skip is inherited, and without a child under the hole
	# nothing in this fixture ever tested that — dropping the inheritance passed the whole file.
	var in_hole := ColorRect.new()
	in_hole.position = Vector2(40, 40)     # PARENT-RELATIVE: the hole starts at x=200, so this is
	                                       # global (240,40). Setting 240 here put it off-window
	                                       # entirely and the walk correctly named the hole instead.
	in_hole.size = Vector2(60, 60)
	hole.add_child(in_hole)
	var clipper := Control.new()
	clipper.position = Vector2(0, 0)
	clipper.size = Vector2(60, 60)
	clipper.clip_contents = true
	root.add_child(clipper)
	var overflow := ColorRect.new()
	overflow.position = Vector2(0, 0)
	overflow.size = Vector2(400, 200)     # reaches the whole window, paints only inside the clipper
	clipper.add_child(overflow)
	await get_tree().process_frame

	var points: Array = []
	for x in range(5, 400, 17):
		for y in range(5, 200, 13):
			points.append(Vector2(x, y))

	# ── unbatched answers are the reference ──────────────────────────────────
	var solo: Array = []
	for p in points:
		var r: Dictionary = _tool.claim_of(p)
		solo.append([bool(r["claimed"]), str(r["node"].get_path()) if r["node"] != null else ""])

	# ── batched must agree on every one ──────────────────────────────────────
	_tool.begin_batch()
	var batched: Array = []
	for p in points:
		var r: Dictionary = _tool.claim_of(p)
		batched.append([bool(r["claimed"]), str(r["node"].get_path()) if r["node"] != null else ""])
	_tool.end_batch()
	var diff := 0
	for i in solo.size():
		if solo[i] != batched[i]:
			diff += 1
	_check("batched and unbatched agree on every point", diff == 0,
		"%d of %d points disagree" % [diff, points.size()])

	# ...and the sample actually contains all three answers, or agreement is free.
	var claimed := 0
	var skipped := 0
	var empty := 0
	for e in solo:
		if e[1] == "": empty += 1
		elif e[0]: claimed += 1
		else: skipped += 1
	_check("...on a sample with chrome, play-hole and empty points in it",
		claimed > 0 and skipped > 0, "claimed %d, skipped %d, empty %d" % [claimed, skipped, empty])
	# THE INHERITANCE ITSELF, named. A control inside the play hole carries no feedback_skip of its
	# own; it is not chrome because its ANCESTOR says so.
	var inside: Dictionary = _tool.claim_of(Vector2(270, 70))
	_check("a control inside the play hole inherits its skip", not bool(inside["claimed"]),
		str(inside["node"]))
	_check("...and it really is that control, not the hole", inside["node"] == in_hole,
		"got %s | hole=%s in_hole=%s" % [inside["node"], hole, in_hole])

	# ── the clip still travels with the walk ─────────────────────────────────
	# The overflow rect covers the window but may only paint inside its 60x60 clipper. A point
	# outside that box must NOT be named as the overflow — this is the bug that killed the pointer
	# path once, and the batch must not lose it.
	_tool.begin_batch()
	var far: Dictionary = _tool.claim_of(Vector2(300, 150))
	var near: Dictionary = _tool.claim_of(Vector2(20, 20))
	_tool.end_batch()
	_check("a clipped control is not named outside what it can paint",
		far["node"] == null or not str(far["node"].get_path()).ends_with("ColorRect2"),
		str(far["node"]))
	_check("...but is named inside it", near["node"] != null
		and str(near["node"].get_path()).contains("Control"), str(near["node"]))

	# ── end_batch really ends it ─────────────────────────────────────────────
	# A stale batch would answer from a tree that no longer exists — worse than a slow walk.
	# NO SECOND `await`. A running Raves viewer holds the instance lock and quits a headless test
	# at its next frame boundary — the checks after it then never run and print NOTHING, which
	# reads exactly like a pass. `visible` takes effect on is_visible_in_tree() immediately, so
	# this needs no frame at all.
	_tool.begin_batch()
	_check("a batch holds entries while it is open",
		bool(_tool._batching) and (_tool._batch as Array).size() > 0,
		"batching=%s n=%d" % [_tool._batching, (_tool._batch as Array).size()])
	_tool.end_batch()
	_check("...and end_batch releases them, so nothing answers from a dead tree",
		not bool(_tool._batching) and (_tool._batch as Array).is_empty(),
		"batching=%s n=%d" % [_tool._batching, (_tool._batch as Array).size()])
	chrome.visible = false
	var after: Dictionary = _tool.claim_of(Vector2(20, 100))
	_check("after end_batch the tree is read live again",
		after["node"] == null or not str(after["node"].get_path()).ends_with("ColorRect"),
		str(after["node"]))

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
