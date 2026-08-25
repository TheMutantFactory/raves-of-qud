extends "res://ChargenCardScreen.gd"

## CHARACTER CREATION — ATTRIBUTES (docs/new-game-plan.md slice 7b): Qud's six stat steppers.
## Each card carries the stat's short name, its value, [+]/[-] affordances, the derived MODIFIER
## and the cost of the next point; the footer tracks points remaining. Left/Right pick a stat,
## Up/Down (or +/-) buy and refund, [R] rolls a spread, [Delete] resets, [9] advances — with
## Qud's "You have unspent attribute points." confirmation when any remain.
##
## The costs and the modifier are COMPUTED, from rules stated here rather than exported:
##   modifier = floor((value - 16) / 2)     — checked against the capture (12 -> -2, 16 -> 0)
##   next point costs 1 below RAISED_COST, 2 at or above it — the capture shows [1pts] at 12
## If Qud's curve ever disagrees, this is the one place to correct; the cost display and the
## spend arithmetic both read this function, so they cannot drift apart.

signal chose_attributes(values: Dictionary, spent: int)

const RAISED_COST := 18          # at/above this value the next point costs 2
const SHORT := {"Strength": "STR", "Agility": "AGI", "Toughness": "TOU",
	"Intelligence": "INT", "Willpower": "WIL", "Ego": "EGO"}
const VAL_CYAN := Color8(0x4A, 0x9E, 0xB8)
const MOD_GREEN := Color8(0x5A, 0xA9, 0x5C)

var mode_name := ""
var chartype_title := ""
var genotype_name := ""
var subtype_name := ""

var _stats: Array = []            # [{name, min, max, desc}]
var _val := {}                    # name -> current value
var _stat_sel := 0   # which stat card is active (the parent's _sel is the card-row cursor)
var _points := 0
var _base_points := 0
var _cards_ui: Array = []
var _foot: RichTextLabel = null
var _desc_lbl: RichTextLabel = null
var _unspent_box: Control = null

func _screen_node_name() -> String: return "AttributesScreen"
func _subtitle() -> String: return ":choose attributes:"
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
	out.append({"label": "Attributes", "current": true})
	return out

func _genotype() -> Dictionary:
	var path := InputModel.support_dir().path_join("chargen.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	for g in parsed.get("genotypes", []):
		if str(g.get("name", "")) == genotype_name:
			return g
	return {}

## What the NEXT point into `v` costs. See the header note.
static func point_cost(v: int) -> int:
	return 2 if v >= RAISED_COST else 1

static func modifier(v: int) -> int:
	return int(floor((v - 16) / 2.0))

func _build_body(vp: Vector2) -> void:
	var g := _genotype()
	_base_points = int(g.get("statPoints", 44))
	_points = _base_points
	_stats.clear()
	_val.clear()
	for st in g.get("stats", []):
		var n := str(st.get("name", ""))
		_stats.append({"name": n, "min": int(st.get("min", 10)), "max": int(st.get("max", 24)),
			"desc": str(st.get("desc", ""))})
		_val[n] = int(st.get("min", 10))
	var cw := vp.x * 0.068
	var ch := vp.y * 0.105
	# the frame textures live in the parent's DEFAULT body, which this screen replaces —
	# build them here or every card draws frameless
	_border_tex = _dashed_border_tex(int(cw), int(ch))
	_frame_tex = _load_card_frame()
	_frame_extracted = _frame_tex != null
	var gap := vp.x * 0.0115
	var total := _stats.size() * cw + maxi(0, _stats.size() - 1) * gap
	var x := vp.x * 0.5 - total * 0.5
	for i in _stats.size():
		var card := Control.new()
		card.position = Vector2(x + i * (cw + gap), vp.y * 0.497)
		card.size = Vector2(cw, ch)
		add_child(card)
		var np := NinePatchRect.new()
		np.set_anchors_preset(Control.PRESET_FULL_RECT)
		_apply_card_frame(np)
		card.add_child(np)
		var nm := _text(str(SHORT.get(_stats[i]["name"], _stats[i]["name"])), NAME_SEL, "body")
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.anchor_left = 0.0; nm.anchor_right = 0.72
		nm.position.y = ch * 0.10
		card.add_child(nm)
		var vl := _text("", VAL_CYAN, "body")
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.anchor_left = 0.0; vl.anchor_right = 0.72
		vl.position.y = ch * 0.36
		card.add_child(vl)
		var md := _text("", MOD_GREEN, "caption")
		md.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		md.anchor_left = 0.0; md.anchor_right = 0.72
		md.position.y = ch * 0.66
		card.add_child(md)
		var cst := _text("", MUTED, "caption")
		cst.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cst.anchor_left = 0.0; cst.anchor_right = 1.0
		cst.position.y = ch * 1.02
		card.add_child(cst)
		# the [+] / [-] stepper column, right side of the card
		var plus := _text("+", SEL_GOLD, "body")
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.anchor_left = 0.72; plus.anchor_right = 1.0
		plus.position.y = ch * 0.14
		card.add_child(plus)
		var minus := _text("-", SEL_GOLD, "body")
		minus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		minus.anchor_left = 0.72; minus.anchor_right = 1.0
		minus.position.y = ch * 0.52
		card.add_child(minus)
		_cards_ui.append({"card": card, "np": np, "name": nm, "val": vl,
			"mod": md, "cost": cst, "plus": plus, "minus": minus})
	_desc_lbl = _rich("", "body")
	_desc_lbl.position = Vector2(vp.x * 0.36, vp.y * 0.645)
	# _rich defaults to AUTOWRAP_OFF (the card screens' one-line descriptions want that), so a
	# paragraph column has to ask for wrapping AND a width to wrap into
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.size = Vector2(vp.x * 0.30, vp.y * 0.12)
	_desc_lbl.custom_minimum_size = _desc_lbl.size
	add_child(_desc_lbl)
	var ks: int = maxi(3, int(round(vp.y * 0.0046)))
	var dx: int = maxi(2, int(round(vp.x * 0.0047)))
	var dy: int = maxi(1, int(round(vp.y * 0.0037)))
	for off in [Vector2(0, -dy), Vector2(-dx, dy), Vector2(dx, dy)]:
		var k := ColorRect.new()
		k.color = DECO_KNOB
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.position = Vector2(vp.x * 0.5 + off.x - ks * 0.5, vp.y * 0.75 + off.y - ks * 0.5)
		k.size = Vector2(ks, ks)
		add_child(k)
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

func _refresh() -> void:
	for i in _cards_ui.size():
		var n := str(_stats[i]["name"])
		var v := int(_val[n])
		var ui: Dictionary = _cards_ui[i]
		ui["val"].text = str(v)
		var m := modifier(v)
		ui["mod"].text = "[%s%d]" % ["+" if m > 0 else "", m]
		ui["cost"].text = "[%dpts]" % point_cost(v)
		var on := i == _stat_sel
		ui["name"].add_theme_color_override("font_color", NAME_SEL if on else MUTED)
		ui["val"].add_theme_color_override("font_color", VAL_CYAN if on else MUTED)
		ui["plus"].visible = on
		ui["minus"].visible = on
	if _desc_lbl != null:
		_desc_lbl.text = QudText.to_bbcode(str(_stats[_stat_sel]["desc"]), _palette)
	if _foot != null:
		_foot.text = "[center][color=#%s]Points Remaining: %d  [/color][color=#%s][lb]R[rb][/color][color=#%s] Randomize Selection  [/color][color=#%s][lb]Delete[rb][/color][color=#%s] Reset Selection[/color][/center]" % [
			MUTED.to_html(false), _points, SEL_GOLD.to_html(false), MUTED.to_html(false),
			SEL_GOLD.to_html(false), MUTED.to_html(false)]

func _buy(delta: int) -> void:
	var n := str(_stats[_stat_sel]["name"])
	var v := int(_val[n])
	if delta > 0:
		if v >= int(_stats[_stat_sel]["max"]):
			return
		var c := point_cost(v)
		if c > _points:
			return
		_val[n] = v + 1
		_points -= c
	else:
		if v <= int(_stats[_stat_sel]["min"]):
			return
		_val[n] = v - 1
		_points += point_cost(v - 1)   # refund what THAT step cost, not the next one's
	_refresh()

func _reset() -> void:
	for st in _stats:
		_val[str(st["name"])] = int(st["min"])
	_points = _base_points
	_refresh()

## Spend the pool at random, one affordable point at a time — Qud's [R].
func _roll() -> void:
	_reset()
	var guard := 0
	while _points > 0 and guard < 500:
		guard += 1
		var i := randi() % _stats.size()
		var n := str(_stats[i]["name"])
		var v := int(_val[n])
		if v >= int(_stats[i]["max"]):
			continue
		var c := point_cost(v)
		if c > _points:
			# nothing affordable anywhere? stop rather than spin
			var any := false
			for j in _stats.size():
				if point_cost(int(_val[str(_stats[j]["name"])])) <= _points \
						and int(_val[str(_stats[j]["name"])]) < int(_stats[j]["max"]):
					any = true
					break
			if not any:
				break
			continue
		_val[n] = v + 1
		_points -= c
	_refresh()

func _advance() -> void:
	chose_attributes.emit(_val.duplicate(), _base_points - _points)
	advance_page.emit()

## Qud's unspent-points confirmation, drawn as its own small modal.
func _ask_unspent() -> void:
	var vp := get_viewport_rect().size
	_unspent_box = Control.new()
	_unspent_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_unspent_box)
	var w := vp.x * 0.203
	var h := vp.y * 0.145
	var box := ColorRect.new()
	box.color = BG
	box.position = Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.43)
	box.size = Vector2(w, h)
	_unspent_box.add_child(box)
	for e in [[0, 0, w, 2], [0, h - 2, w, 2], [0, 0, 2, h], [w - 2, 0, 2, h]]:
		var b := ColorRect.new()
		b.color = MUTED
		b.position = box.position + Vector2(e[0], e[1])
		b.size = Vector2(e[2], e[3])
		_unspent_box.add_child(b)
	var t := _text("Warning!", CC_GOLD, "body")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.anchor_left = 0.0; t.anchor_right = 1.0
	t.position.y = box.position.y + h * 0.16
	_unspent_box.add_child(t)
	var m := _text("You have unspent attribute points.", NAME_SEL, "body")
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.anchor_left = 0.0; m.anchor_right = 1.0
	m.position.y = box.position.y + h * 0.40
	_unspent_box.add_child(m)
	var q := _text("Continue anyway?", NAME_SEL, "body")
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.anchor_left = 0.0; q.anchor_right = 1.0
	q.position.y = box.position.y + h * 0.60
	_unspent_box.add_child(q)
	var yn := _rich("[center][color=#%s]> Yes[/color][color=#%s]    No[/color][/center]" % [
		SEL_GOLD.to_html(false), MUTED.to_html(false)], "body")
	yn.anchor_left = 0.0; yn.anchor_right = 1.0
	yn.position.y = box.position.y + h * 0.80
	_unspent_box.add_child(yn)

func _unhandled_input(e: InputEvent) -> void:
	if _unspent_box != null:
		if e.is_action_pressed("ui_accept"):
			_unspent_box.queue_free(); _unspent_box = null
			_advance(); accept_event(); return
		if e.is_action_pressed("ui_cancel"):
			_unspent_box.queue_free(); _unspent_box = null
			accept_event(); return
		return
	if e.is_action_pressed("ui_right"):
		_stat_sel = mini(_stat_sel + 1, _stats.size() - 1); _refresh(); accept_event(); return
	if e.is_action_pressed("ui_left"):
		_stat_sel = maxi(_stat_sel - 1, 0); _refresh(); accept_event(); return
	if e.is_action_pressed("ui_up"):
		_buy(1); accept_event(); return
	if e.is_action_pressed("ui_down"):
		_buy(-1); accept_event(); return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_buy(1); accept_event(); return
			KEY_MINUS, KEY_KP_SUBTRACT:
				_buy(-1); accept_event(); return
			KEY_R:
				_roll(); accept_event(); return
			KEY_DELETE, KEY_BACKSPACE:
				_reset(); accept_event(); return
			KEY_9, KEY_KP_9:
				if _points > 0:
					_ask_unspent()
				else:
					_advance()
				accept_event(); return
	if e.is_action_pressed("ui_cancel"):
		closed.emit(); accept_event(); return
