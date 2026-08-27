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

## Clear whichever row has focus. One implementation, reached by [R], by [Delete], and by a click
## on either — the two keys always did the same thing, in two copies of the same four lines.
func _clear_row() -> void:
	if _row == 0:
		_cname = ""
	else:
		_pet = ""
	_refresh_rows()
	customized.emit(_cname, _pet)

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
	var foot := _rich("[center][url=r][color=#%s][lb]R[rb][/color][color=#%s] Randomize Selection  [/color][/url][url=del][color=#%s][lb]Delete[rb][/color][color=#%s] Reset Selection[/color][/url][/center]" % [
		SEL_GOLD.to_html(false), MUTED.to_html(false), SEL_GOLD.to_html(false), MUTED.to_html(false)], "body")
	foot.anchor_left = 0.0; foot.anchor_right = 1.0
	foot.position.y = vp.y * 0.9073   # ink 0.9120
	_clickable_foot(foot, {"r": _clear_row, "del": _clear_row})
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

## THE NAME FIELD IS PART OF THE LAYOUT NOW. Daniel: "Add the text input box to the 'flexbox' to
## ensure it fits within the dialog box."
##
## It used to be placed at two hardcoded viewport fractions — x 0.40, y 0.444, width 0.20 — which is
## the one thing every other row on these screens stopped doing when the cascade went in. Two things
## follow from that, and both are the report:
##
##   IT DID NOT FIT WHAT IT HELD. max_length is 60 characters and 20% of the viewport is about 40
##   at body pitch, so a long name simply scrolled out of its own box. The field is now sized to
##   the text it is allowed to contain, capped to the row it sits on.
##
##   IT DID NOT FOLLOW THE ROW. 0.444 was where the Name row happened to be BEFORE the cascade
##   could push it; anything that moved that row — a longer subtitle, a different font scale — left
##   the field behind, editing one line while floating over another. It now takes the row's own
##   laid-out rect, which is the whole point of having a layout pass.
func _begin_name_edit() -> void:
	var row: Control = _row_labels[0]
	_edit = LineEdit.new()
	_edit.text = _cname
	_edit.max_length = 60
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var px := UiFont.px(get_viewport(), "body")
	var f := get_theme_default_font()
	# The font's own advance, measured the way the popup measures Qud's: ten characters over ten,
	# so a proportional fallback face cannot make this a guess about "M" or "i".
	var pitch: float = (f.get_string_size("AAAAAAAAAA", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x / 10.0) \
		if f != null else float(px) * 0.6
	var w: float = minf(pitch * float(_edit.max_length + 2), maxf(row.size.x - 2.0 * px, pitch * 12.0))
	var h: float = float(px) * 1.6
	_edit.size = Vector2(w, h)
	_edit.position = Vector2(row.position.x + (row.size.x - w) * 0.5,
		row.position.y + (maxf(row.size.y, h) - h) * 0.5)
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
			_clear_row(); accept_event(); return
		if e.keycode == KEY_DELETE or e.keycode == KEY_BACKSPACE:
			_clear_row(); accept_event(); return
	super._unhandled_input(e)   # Esc closes, 9 advances — the template's own handling
