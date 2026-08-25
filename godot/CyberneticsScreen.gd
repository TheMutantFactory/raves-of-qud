extends "res://ChargenCardScreen.gd"

## CHARACTER CREATION — CYBERNETICS (docs/new-game-plan.md slice 7c): True Kin's implant picker,
## two dash-ruled panels as in Qud's capture. LEFT is the licensed catalog — one row per
## blueprint-and-slot, checkbox first, slot in parens, ending in a "<none>" row that clears the
## lot. RIGHT is the selected implant: its name and slot as the panel title, its tile, the
## description, then the behaviour blurb in cyan.
##
## Licence POINTS, not a count: each implant costs 1-2 and the genotype grants
## cyberLicensePoints (True Kin: 2). One implant per SLOT — Qud's own restriction — so picking
## a second Face implant replaces the first rather than stacking.

signal chose_cybernetics(picks: Array)

const BEHAVIOR_CYAN := Color8(0x4A, 0x9E, 0xB8)

var mode_name := ""
var chartype_title := ""
var genotype_name := ""
var subtype_name := ""

var _all: Array = []
var _row := 0
var _picks := {}                 # slot -> index into _all
var _points := 0
var _base_points := 0
var _list_lbl: RichTextLabel = null
var _detail_lbl: RichTextLabel = null
var _behav_lbl: RichTextLabel = null
var _foot: RichTextLabel = null
var _icon: TextureRect = null
var _title_lbl: RichTextLabel = null
const VISIBLE_ROWS := 17

func _screen_node_name() -> String: return "CyberneticsScreen"
func _subtitle() -> String: return ":choose cybernetic implant:"
func _load_items() -> Array: return []
func _next_enabled() -> bool: return true

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
	if subtype_name != "":
		out.append({"label": subtype_name, "current": false})
	out.append({"label": "Attributes", "current": false})
	out.append({"label": "Cybernetics", "current": true})
	return out

func _build_body(vp: Vector2) -> void:
	var path := InputModel.support_dir().path_join("chargen.json")
	var d: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			d = parsed
	for g in d.get("genotypes", []):
		if str(g.get("name", "")) == genotype_name:
			_base_points = int(g.get("cyberLicensePoints", 2))
	if _base_points <= 0:
		_base_points = 2
	_points = _base_points
	_all = d.get("cybernetics", [])
	# left panel: the catalog
	# ROW-PROFILED (parity_rows.py): Qud's panel header inks at 0.4843 and its first list row
	# at 0.5083 (1920x1080). Raves' panel sat 23px low and its list 27px low; both lift here.
	_panel_rule(vp, 0.252, 0.4909, 0.213, "Cybernetics")
	_list_lbl = _rich("", "body")
	_list_lbl.position = Vector2(vp.x * 0.255, vp.y * 0.5019)
	_list_lbl.size = Vector2(vp.x * 0.21, vp.y * 0.38)
	_list_lbl.custom_minimum_size = _list_lbl.size
	add_child(_list_lbl)
	# right panel: the selected implant
	_title_lbl = _rich("", "body")
	_title_lbl.position = Vector2(vp.x * 0.478, vp.y * 0.482)
	_title_lbl.size = Vector2(vp.x * 0.30, vp.y * 0.03)
	add_child(_title_lbl)
	_icon = TextureRect.new()
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.position = Vector2(vp.x * 0.478, vp.y * 0.524)
	_icon.size = Vector2(vp.y * 0.052, vp.y * 0.052)
	add_child(_icon)
	_detail_lbl = _rich("", "body")
	_detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_lbl.position = Vector2(vp.x * 0.521, vp.y * 0.511)
	_detail_lbl.size = Vector2(vp.x * 0.245, vp.y * 0.07)
	_detail_lbl.custom_minimum_size = _detail_lbl.size
	add_child(_detail_lbl)
	_behav_lbl = _rich("", "body")
	_behav_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_behav_lbl.position = Vector2(vp.x * 0.521, vp.y * 0.584)
	_behav_lbl.size = Vector2(vp.x * 0.245, vp.y * 0.08)
	_behav_lbl.custom_minimum_size = _behav_lbl.size
	add_child(_behav_lbl)
	_foot = _rich("", "body")
	_foot.anchor_left = 0.0; _foot.anchor_right = 1.0
	_foot.position.y = vp.y * 0.905
	add_child(_foot)
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
	_refresh()

## One dashed panel rule with a label at its left end, |- Label ------------|
func _panel_rule(vp: Vector2, x: float, y: float, w: float, label: String) -> void:
	var lab := _text(label, NAME_SEL, "body")
	lab.position = Vector2(vp.x * x, vp.y * y - UiFont.px(get_viewport(), "body") * 0.62)
	add_child(lab)
	var lw := UiFont.px(get_viewport(), "body") * label.length() * 0.62
	var xx := vp.x * x + lw + vp.x * 0.006
	var end := vp.x * (x + w)
	while xx < end:
		var dash := ColorRect.new()
		dash.color = BAND_RULE
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dash.position = Vector2(xx, vp.y * y)
		dash.size = Vector2(maxf(2.0, vp.x * 0.0031), maxi(1, int(round(vp.y * 0.0019))))
		add_child(dash)
		xx += vp.x * 0.0052

func _slot_of(i: int) -> String:
	return str(_all[i].get("slot", ""))

func _picked_index() -> int:
	# which catalog row the cursor is on, or -1 for the <none> row
	return _row if _row < _all.size() else -1

func _toggle() -> void:
	var i := _picked_index()
	if i < 0:
		_picks.clear()
		_points = _base_points
		_refresh()
		return
	var slot := _slot_of(i)
	var cost := int(_all[i].get("cost", 1))
	if _picks.get(slot, -1) == i:
		_picks.erase(slot)          # same row again: take it off
		_points += cost
		_refresh()
		return
	# one implant per slot: refund whatever holds this slot first
	if _picks.has(slot):
		_points += int(_all[int(_picks[slot])].get("cost", 1))
		_picks.erase(slot)
	if cost > _points:
		_refresh()
		return
	_picks[slot] = i
	_points -= cost
	_refresh()

## Implants to the flow, then advance — shared by [9] and the click box.
func _nav_next() -> void:
	var picks: Array = []
	for slot in _picks:
		var m: Dictionary = _all[int(_picks[slot])]
		picks.append({"blueprint": str(m.get("blueprint", "")),
			"display": QudText.strip(str(m.get("display", ""))), "slot": str(slot)})
	chose_cybernetics.emit(picks)
	advance_page.emit()

func _refresh() -> void:
	var total := _all.size() + 1            # + the <none> row
	var lo: int = clampi(_row - VISIBLE_ROWS / 2, 0, maxi(0, total - VISIBLE_ROWS))
	var hi: int = mini(lo + VISIBLE_ROWS, total)
	var out := ""
	for i in range(lo, hi):
		var cursor := "[color=#%s]›[/color]" % SEL_GOLD.to_html(false) if i == _row else " "
		if i >= _all.size():
			var mark_n := "■" if _picks.is_empty() else " "
			out += "%s[color=#%s][lb]%s[rb] <none>[/color]\n" % [
				cursor, (NAME_SEL if i == _row else MUTED).to_html(false), mark_n]
			continue
		var m: Dictionary = _all[i]
		var slot := str(m.get("slot", ""))
		var on: bool = _picks.get(slot, -1) == i
		var col := SEL_GOLD if on else (NAME_SEL if i == _row else MUTED)
		out += "%s[color=#%s][lb]%s[rb] %s[/color][color=#%s] (%s)[/color]\n" % [
			cursor, col.to_html(false), "■" if on else " ",
			QudText.strip(str(m.get("display", ""))), MUTED.to_html(false), slot]
	_list_lbl.text = out
	var i2 := _picked_index()
	if i2 >= 0:
		var m2: Dictionary = _all[i2]
		_title_lbl.text = "[color=#%s]%s[/color][color=#%s] (%s)[/color]" % [
			NAME_SEL.to_html(false), QudText.strip(str(m2.get("display", ""))),
			MUTED.to_html(false), str(m2.get("slot", ""))]
		_detail_lbl.text = QudText.to_bbcode(str(m2.get("desc", "")), _palette)
		_behav_lbl.text = "[color=#%s]%s[/color]" % [
			BEHAVIOR_CYAN.to_html(false), QudText.strip(str(m2.get("behavior", "")))]
		var tex := _recolor_tile(str(m2.get("tile", "")), ICON_MAIN,
			QUD_COLORS.get(str(m2.get("detail", "")), ICON_DETAIL))
		_icon.texture = tex
		_icon.visible = tex != null
	else:
		_title_lbl.text = "[color=#%s]<none>[/color]" % NAME_SEL.to_html(false)
		_detail_lbl.text = "[color=#%s]Start with no cybernetic implants.[/color]" % MUTED.to_html(false)
		_behav_lbl.text = ""
		_icon.visible = false
	_foot.text = "[center][color=#%s]License Points: %d  [/color][color=#%s][lb]Delete[rb][/color][color=#%s] Reset Selection[/color][/center]" % [
		MUTED.to_html(false), _points, SEL_GOLD.to_html(false), MUTED.to_html(false)]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_down"):
		_row = mini(_row + 1, _all.size()); _refresh(); accept_event(); return
	if e.is_action_pressed("ui_up"):
		_row = maxi(_row - 1, 0); _refresh(); accept_event(); return
	if e.is_action_pressed("ui_accept"):
		_toggle(); accept_event(); return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_DELETE, KEY_BACKSPACE:
				_picks.clear(); _points = _base_points; _refresh(); accept_event(); return
			KEY_9, KEY_KP_9:
				_nav_next(); accept_event(); return
	if e.is_action_pressed("ui_cancel"):
		closed.emit(); accept_event(); return
