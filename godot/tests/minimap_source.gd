extends Node

## WHICH MAP THE MINIMAP DRAWS — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/minimap_source.tscn
##
## Daniel: "Let's have a Raves setting for minimap 1:1, or top-down camera." Two of the four
## renderings already existed and were reachable only through the panel's own toggle; the setting
## names all four in one place.
##
## THE FAILURE THIS IS AIMED AT is two controls for one value. The toggle used to flip a local
## field that the setting then overwrote on the next snapshot — a button that appears to work and
## undoes itself a moment later, which is worse than one that does nothing.

var _failed: Array[String] = []


func _ready() -> void:
	var m = load("res://MinimapView.gd").new()
	# BEFORE add_child, so nothing in _ready can reach the settings file either.
	m.persist = false
	add_child(m)
	# The fixture owns the setting: _ready reads it, and on a machine that has used the panel this
	# would otherwise start from somebody's real choice.
	Settings.set_value(m.SRC_KEY, "full")
	m._refresh_toggle()

	_check("the button shows the live source", m._toggle.text == "full", m._toggle.text)

	# ── the button and the setting are one value ──────────────────────────────
	m._toggle_mode()
	_check("pressing it moves the SETTING, not a local field",
		String(Settings.get_value(m.SRC_KEY, "")) == "minimal",
		String(Settings.get_value(m.SRC_KEY, "")))
	_check("...and the button says so", m._toggle.text == "minimal", m._toggle.text)
	# All four are reachable from the button, and it comes back round.
	var seen: Array = []
	for i in 4:
		seen.append(String(Settings.get_value(m.SRC_KEY, "")))
		m._toggle_mode()
	seen.sort()
	_check("every source is reachable from the button",
		seen == ["full", "minimal", "qud", "topdown"], str(seen))

	# Options can set it behind the button's back; the button must not disagree.
	Settings.set_value(m.SRC_KEY, "topdown")
	m._last_data = {"player": {"x": 10, "y": 4}, "zone": {"width": 80, "height": 25}, "cells": []}
	m._rerender()
	_check("a change made in Options re-letters the button", m._toggle.text == "top-down",
		m._toggle.text)

	# ── the top-down camera ───────────────────────────────────────────────────
	_check("top-down shows the camera and hides the painted map",
		m._svc.visible and not m._rect.visible)
	_check("...and the camera is over the player",
		m._tcam.position.x == 10.0 and m._tcam.position.z == 4.0, str(m._tcam.position))
	_check("...looking down from above every wall", m._tcam.position.y >= 20.0,
		str(m._tcam.position.y))
	# NORTH UP, the same up-vector CameraRig's own top-down uses. A map whose north disagreed with
	# the game's would be worse than no map.
	var fwd: Vector3 = -m._tcam.global_transform.basis.z
	_check("...straight down, not tilted", fwd.normalized().dot(Vector3.DOWN) > 0.999,
		str(fwd.normalized()))
	var up: Vector3 = m._tcam.global_transform.basis.y
	_check("...with north up", up.normalized().dot(Vector3(0, 0, -1)) > 0.999, str(up.normalized()))
	# BOUND ON SHOW, not at build: panels are constructed before they are in the tree, and a
	# SubViewport with no world renders its own empty one — indistinguishable from a camera aimed
	# at nothing, which is exactly how this failed the first time.
	_check("it shares the game's world once shown",
		m._sv.world_3d != null and m._sv.world_3d == get_viewport().find_world_3d(),
		str(m._sv.world_3d))
	# A SECOND CAMERA ON THE LIVE WORLD IS NOT FREE. It must stop rendering when not shown.
	_check("the viewport renders while shown",
		m._sv.render_target_update_mode == SubViewport.UPDATE_ALWAYS)

	Settings.set_value(m.SRC_KEY, "full")
	m._rerender()
	_check("switching away hides the camera", not m._svc.visible and m._rect.visible)
	_check("...and stops it rendering",
		m._sv.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		str(m._sv.render_target_update_mode))

	# ── parity still wins ─────────────────────────────────────────────────────
	# The setting is a USER-MODE choice; 1:1 is the mode that has no choices.
	Settings.set_value(m.SRC_KEY, "topdown")
	m._one_to_one = true
	m._rerender()
	_check("1:1 overrides the setting", not m._svc.visible, "top-down leaked into parity mode")

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
