extends "res://ChargenCardScreen.gd"

## CHARACTER CREATION — CUSTOMIZE CHARACTER (docs/new-game-plan.md slice 3): Qud's two-row form
## on the shared chrome. "Name: <random>" edits inline (empty = Qud rolls a name at embark);
## "Pet: <none>" is a cycle row whose only option is <none> until a pets export exists (the pet
## list lives in code, not EmbarkModules.xml — the mod side already honours a pet blueprint, so
## the row lights up the moment the export lands). [R] rerolls to <random>, [Delete] resets the
## row, [9] advances to Choose Starting Location.

signal customized(cname: String, pet: String)

var mode_name := ""
var chartype_title := ""
var genotype_name := ""
var subtype_name := ""

var _row := 0                 # 0 = Name, 1 = Pet
var _cname := ""              # empty = <random>
var _pet := ""                # empty = <none>
var _row_labels: Array = []
var _edit: LineEdit = null

func _screen_node_name() -> String: return "CustomizeScreen"
## Row-profiled off Qud: this screen sits its deco high, right under its two prompt rows.
func _y_deco() -> float: return 0.4935
func _subtitle() -> String: return ":customize character:"
func _load_items() -> Array: return []
func _next_enabled() -> bool: return true
## ROW-PROFILED against Qud's own capture (tools/capture/parity_rows.py), not eyeballed —
## the method ChargenCardScreen's layout notes set out. Qud's customize screen inks at
## 1920x1080: title 423-440, subtitle 448-459, Name 478-488, Pet 500-510, deco 527-539,
## the [R] line 985-998. A Label's ink starts ~0.008 of viewport height below the y it is
## positioned at (font ascent), so each hook below is Qud's ink fraction LESS that offset;
## the deco is ColorRects and takes Qud's fraction directly.
func _y_title() -> float: return 0.3838     # ink 0.3917
func _y_subtitle() -> float: return 0.4074  # ink 0.4148

func _breadcrumb_crumbs() -> Array:
	var out: Array = []
	if mode_name != "":
		out.append({"label": mode_name, "current": false,
			"tile": _chargen_tile("gameModes", mode_name)})
	if chartype_title != "":
		out.append({"label": chartype_title, "current": false})
	if genotype_name != "":
		out.append({"label": genotype_name, "current": false,
			"tile": _chargen_tile("genotypes", genotype_name)})
	out.append({"label": "Customize", "current": true})
	return out

func _build_body(vp: Vector2) -> void:
	var mark := _body_mark()
	_row_labels.clear()
	for i in 2:
		var rl := _rich("", "body")
		rl.anchor_left = 0.0
		rl.anchor_right = 1.0
		rl.position.y = vp.y * (0.4376 + i * 0.0204)   # ink 0.4426 / 0.4630 — Qud's own step
		add_child(rl)
		_row_labels.append(rl)
	_refresh_rows()
	# the two prompt rows are all there is above the deco here
	_body_bot = vp.y * (0.4376 + 2.0 * 0.0204)
	_body_claim(mark, vp.y * 0.4376)
	_make_deco()   # created here, PLACED by the cascade (see _y_deco / _place_deco)
	var foot := _rich("[center][color=#%s][lb]R[rb][/color][color=#%s] Randomize Selection  [/color][color=#%s][lb]Delete[rb][/color][color=#%s] Reset Selection[/color][/center]" % [
		SEL_GOLD.to_html(false), MUTED.to_html(false), SEL_GOLD.to_html(false), MUTED.to_html(false)], "body")
	foot.anchor_left = 0.0; foot.anchor_right = 1.0
	foot.position.y = vp.y * 0.9073   # ink 0.9120
	add_child(foot)
	var hint := _rich("", "caption")
	hint.anchor_left = 0.0; hint.anchor_right = 1.0
	hint.position.y = vp.y * 0.965
	var ih := int(round(UiFont.px(get_viewport(), "caption") * 1.15))
	hint.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	var icon := QudChrome.nav_icon(ih, SEL_GOLD)
	hint.add_image(icon, icon.get_width(), icon.get_height())
	hint.append_text("[color=#%s] navigate      [/color][color=#%s][lb]Space[rb][/color][color=#%s] select[/color]" % [
		MUTED.to_html(false), SEL_GOLD.to_html(false), MUTED.to_html(false)])
	hint.pop()
	add_child(hint)

func _refresh_rows() -> void:
	var vals := ["<random>" if _cname == "" else _cname, "<none>" if _pet == "" else _pet]
	var names := ["Name", "Pet"]
	for i in 2:
		var caret := "[color=#%s]›[/color]" % SEL_GOLD.to_html(false) if i == _row else " "
		var col := NAME_SEL if i == _row else MUTED
		_row_labels[i].text = "[center]%s[color=#%s]%s: %s[/color][/center]" % [
			caret, col.to_html(false), names[i], vals[i]]

func _begin_name_edit() -> void:
	var vp := get_viewport_rect().size
	_edit = LineEdit.new()
	_edit.text = _cname
	_edit.max_length = 60
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.position = Vector2(vp.x * 0.40, vp.y * 0.444)
	_edit.size = Vector2(vp.x * 0.20, UiFont.px(get_viewport(), "body") * 1.6)
	_edit.add_theme_color_override("font_color", NAME_SEL)
	add_child(_edit)
	_edit.grab_focus()
	_edit.text_submitted.connect(func(t: String):
		_cname = t.strip_edges()
		_end_name_edit())
	_edit.focus_exited.connect(_end_name_edit)

func _end_name_edit() -> void:
	if _edit != null and is_instance_valid(_edit):
		_edit.queue_free()
	_edit = null
	_refresh_rows()
	customized.emit(_cname, _pet)

func _unhandled_input(e: InputEvent) -> void:
	if _edit != null:
		if e.is_action_pressed("ui_cancel"):
			_end_name_edit(); accept_event()
		return   # the LineEdit owns the keys while editing
	if e.is_action_pressed("ui_down") or e.is_action_pressed("ui_up"):
		_row = 1 - _row
		_refresh_rows(); accept_event(); return
	if e.is_action_pressed("ui_accept"):
		if _row == 0:
			_begin_name_edit()
		# Pet: the one option is <none> until the pets export lands — nothing to cycle
		accept_event(); return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_R:
			if _row == 0: _cname = ""
			else: _pet = ""
			_refresh_rows(); customized.emit(_cname, _pet); accept_event(); return
		if e.keycode == KEY_DELETE or e.keycode == KEY_BACKSPACE:
			if _row == 0: _cname = ""
			else: _pet = ""
			_refresh_rows(); customized.emit(_cname, _pet); accept_event(); return
	super._unhandled_input(e)   # Esc closes, 9 advances — the template's own handling
