extends Node

## A QoL SWITCH MUST SHOW WHAT THE GATE IS DOING — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/qol_toggle_default.tscn
##
## Every QoL feature carries a shipped default in Settings.QOL_FEATURES, and nine of them ship ON.
## The options row read `Settings.get_value(key, false)` regardless, so a feature that had never
## been written to settings.json drew an EMPTY box over a feature that was running — and the first
## click computed `not false`, wrote true, and changed nothing you could see.
##
## It stayed invisible because the nine older default-on features all had their keys written out
## long ago by a preset or an earlier toggle. It surfaced the moment three new ones were
## registered, which is the worst time for it: a switch that does nothing on first use reads as a
## feature that does not work.

var _failed: Array[String] = []


func _ready() -> void:
	var scr = load("res://OptionsScreen.gd")
	# A TOGGLE'S CALLBACK CALLS Settings.save(), and this test presses one. That writes the
	# developer's real settings.json, which a test has no business doing — twice already a run of
	# these has silently rewritten it. Keep the file's bytes and put them back.
	var settings_text := _read_settings()

	# THE INVARIANT: for every registered feature, with nothing written, the box agrees with the
	# gate. Stated over the whole registry rather than over the three new features, because this
	# is a rule about registering a feature at all.
	for fname in Settings.QOL_FEATURES:
		var spec: Array = Settings.QOL_FEATURES[fname]
		var key := "qol_" + str(fname)
		var saved = _unset(key)
		# unset: the row must read the SHIPPED default, which is what the gate falls back to
		var shown := bool(Settings.get_value(key, bool(spec[1])))
		_check("unset `%s` shows as %s, like the gate" % [fname, "on" if spec[1] else "off"],
			shown == Settings.qol_on(str(fname)),
			"box=%s gate=%s" % [shown, Settings.qol_on(str(fname))])
		_restore(key, saved)

	# ...and the row the screen actually builds, for a feature that ships ON with nothing written.
	# THE BOX IS READ OFF THE BUTTON'S OWN TEXT — asking Settings again would only re-ask the
	# question the row is supposed to be answering, and would pass no matter what the row drew.
	var on_feature := _a_feature_defaulting(true)
	_check("the registry has a default-on feature to test with", on_feature != "")
	if on_feature != "":
		var key := "qol_" + on_feature
		var saved = _unset(key)
		var scn = scr.new()
		var row = scn._raves_toggle({"key": key, "label": "x", "type": "toggle", "default": true})
		_check("a default-on row is drawn CHECKED before anything is written",
			_checked(row), row.text)
		var row_off = scn._raves_toggle({"key": "qol_no_such_feature_", "label": "x",
			"type": "toggle", "default": false})
		_check("...and a default-off row is not", not _checked(row_off), row_off.text)
		# THE ROW THE SCREEN ACTUALLY BUILDS, not one hand-assembled here. The spec above could
		# carry the right default while the options column never passed it — which is exactly the
		# shape the bug had.
		var spec_item: Dictionary = scn._qol_item(on_feature)
		_check("the screen's own QoL row carries the registry default",
			bool(spec_item.get("default", false)) == bool(Settings.QOL_FEATURES[on_feature][1]),
			str(spec_item))
		var mismatched: Array[String] = []
		for fname in Settings.QOL_FEATURES:
			var it: Dictionary = scn._qol_item(str(fname))
			if bool(it.get("default", false)) != bool(Settings.QOL_FEATURES[fname][1]):
				mismatched.append(str(fname))
		_check("...for every feature in the registry", mismatched.is_empty(), ", ".join(mismatched))

		# ── THE CLICK ────────────────────────────────────────────────────────
		# The symptom users meet: a default-on feature whose key was never written. The first press
		# has to turn it OFF. Against a hardcoded `false` it computes `not false` and writes TRUE —
		# the box ticks, the feature does not change, and the control looks broken.
		_unset(key)
		var clicker = scn._raves_toggle({"key": key, "label": "x", "type": "toggle",
			"default": true})
		clicker.emit_signal("pressed")
		_check("the first click on a default-on switch turns it OFF",
			not bool(Settings.get_value(key, true)), "now=%s" % Settings.get_value(key, true))
		_check("...and the box clears", not _checked(clicker), clicker.text)
		clicker.free()

		scn.free()
		_restore(key, saved)

	# ── a feature that owns a panel's shape must reach the panel NOW ─────────
	# _set_panels_one_to_one runs on the master 1:1 switch and once at launch, and nothing else.
	# So flipping the minimap feature saved the key and left the panel showing Qud's map until the
	# next restart — a switch that does nothing, which is how it was reported.
	var scn2 = scr.new()
	var rang := [0]
	scn2.apply_live_cb = func() -> void: rang[0] += 1
	var qrow = scn2._raves_toggle(scn2._qol_item("minimap"))
	qrow.emit_signal("pressed")
	_check("flipping a QoL feature tells the panels to re-shape", rang[0] == 1,
		"%d calls" % rang[0])
	# ...and a PLAIN setting does not: the callback re-runs a panel pass, and running it on every
	# checkbox in the screen would be a cost with no reason.
	var prow = scn2._raves_toggle({"key": "fullscreen", "label": "x", "type": "toggle"})
	prow.emit_signal("pressed")
	_check("...and a plain setting does not", rang[0] == 1, "%d calls" % rang[0])
	# ...but a setting that owns a live surface does. The CRT overlay is built once and returns
	# early ever after, so its two switches were read at startup and never again.
	var crow = scn2._raves_toggle({"key": "fx_scanlines", "label": "x", "type": "toggle"})
	crow.emit_signal("pressed")
	_check("a setting owning a live surface tells it too", rang[0] == 2, "%d calls" % rang[0])
	crow.free()
	# UNSET IS SAFE: the title-screen options have no panels and leave the callback empty.
	var scn3 = scr.new()
	var srow = scn3._raves_toggle(scn3._qol_item("minimap"))
	srow.emit_signal("pressed")
	_check("an unset callback is simply skipped", true)
	qrow.free(); prow.free(); srow.free(); scn2.free(); scn3.free()

	_write_settings(settings_text)
	_report()


## The settings file as text, or "" if there is none yet. Restored verbatim at the end of the run:
## reconstructing it from _data would hand back whatever this test left in memory.
func _read_settings() -> String:
	var f := FileAccess.open(Settings._path(), FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _write_settings(text: String) -> void:
	if text == "":
		return
	var f := FileAccess.open(Settings._path(), FileAccess.WRITE)
	if f != null:
		f.store_string(text)


## Take a key back to "never written", the state a freshly-registered feature is in, and hand back
## whatever was there. Settings has no erase, so this reaches into its dictionary — which is the
## honest way to reproduce "unset"; writing a value would test the case that already worked.
func _unset(key: String) -> Variant:
	var had = Settings._data.get(key, null)
	Settings._data.erase(key)
	return had


func _restore(key: String, saved) -> void:
	if saved != null:
		Settings._data[key] = saved


## The button renders its state into its own label, so the mark IS the control's answer.
func _checked(b) -> bool:
	var t := str(b.text)
	return t.contains("■") or t.contains("x]") or t.contains("X]") or t.contains("✓")


func _a_feature_defaulting(want: bool) -> String:
	for fname in Settings.QOL_FEATURES:
		if bool(Settings.QOL_FEATURES[fname][1]) == want:
			return str(fname)
	return ""


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
