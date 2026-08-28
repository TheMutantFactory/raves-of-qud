class_name TradeOverlay
extends CanvasLayer

## Mirrors Qud's TRADE SCREEN (Qud.UI.TradeScreen), forwarded by the mod's TradeBridge.
##
## Daniel: "We need to implement the trading menu. There's a dromad in joppa if you need a quick way
## of finding someone."
##
## Like the item picker, this is a Qud SCREEN rather than a PopupMessage, so the popup mirror is
## structurally blind to it: Qud put the board up and Raves showed the playfield with nothing on it.
##
## THE ROWS ARE QUD'S OWN, in Qud's order, with Qud's categories and collapse state -- the mod sends
## listItems[side] rather than the raw inventories. So the sort mode, the grouping and the prices are
## the game's, and this file only has to draw them and send back which row was clicked.
##
## SELECTION IS A COUNT, NOT A FLAG, because a stack of 49 shotgun shells is one row and you may want
## six of them. A left click adds one, a right click takes one back, and shift does the whole stack;
## the number that comes back on the next frame is Qud's answer, not our optimistic guess, so a
## refused change (an important item you declined to sell) simply does not appear.
##
## LAYER 128 puts it UNDER the picker (129) and the popup (130), and that ordering is load-bearing:
## selling something flagged important raises a real confirm popup, which has to draw on top of the
## board it is asking about.

signal act(payload: Dictionary)

const LAYER := 128
const PAD := 14.0
const COL_GAP := 12.0
const ROW_H := 26.0
const CAT_H := 22.0
const FOOT_H := 74.0
const HEAD_H := 30.0
const ICON := Vector2(16, 24)

## Qud's own chrome tones, the same ones the other mirrored screens use.
const BG := Color8(0x0a, 0x1c, 0x1c, 0xf2)
const FRAME := Color8(0x15, 0x53, 0x52)
const HEAD_COL := Color8(0xcf, 0xc0, 0x41)
const DIM := Color8(0x77, 0xbf, 0xcf)
const SEL_BG := Color8(0x15, 0x53, 0x52, 0xcc)
const MONEY := Color8(0x00, 0xc4, 0x20)
const OWED := Color8(0xd7, 0x42, 0x00)

var _palette := {}
var _tiles: RefCounted = null
var _data := {}
var _built := false
var _root: Control
var _cols: Array = []          # [side] -> {list: VBoxContainer, scroll: ScrollContainer, head: RichTextLabel}
var _foot: RichTextLabel
var _title: RichTextLabel
var tiles_dir := ""


func _ready() -> void:
	layer = LAYER
	visible = false

## The mod's trade frame. Rebuilds the board; an inactive frame closes it.
func set_state(d: Dictionary, palette: Dictionary, dir: String) -> void:
	if not palette.is_empty():
		_palette = palette
	if dir != "":
		tiles_dir = dir
	if not bool(d.get("active", false)):
		visible = false
		_data = {}
		return
	_data = d
	_ensure_built()
	_paint()
	visible = true

func active() -> bool:
	return visible

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	if _tiles == null:
		_tiles = load("res://QudTiles.gd").new()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP     # the board owns its own screen
	add_child(_root)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60; panel.offset_right = -60
	panel.offset_top = 60; panel.offset_bottom = -60
	panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	_title = _label(HEAD_COL)
	_title.custom_minimum_size.y = HEAD_H
	outer.add_child(_title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(COL_GAP))
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)
	for side in 2:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var head := _label(HEAD_COL)
		head.custom_minimum_size.y = 24
		box.add_child(head)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 1)
		scroll.add_child(list)
		cols.add_child(box)
		_cols.append({"list": list, "scroll": scroll, "head": head})

	_foot = _label(DIM)
	_foot.custom_minimum_size.y = FOOT_H
	outer.add_child(_foot)

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG
	s.border_color = FRAME
	s.set_border_width_all(2)
	s.set_content_margin_all(PAD)
	return s

func _label(col: Color) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("default_color", col)
	return l

func _paint() -> void:
	var trader := QudText.strip(String(_data.get("trader", "")))
	_title.text = "[b]%s[/b]   [color=#%s]%s[/color]" % [
		trader, DIM.to_html(false),
		"prices x%s" % String(_data.get("mult", "1"))]
	for side in 2:
		var sd: Dictionary = _side(side)
		var c: Dictionary = _cols[side]
		c.head.text = "[b]%s[/b]" % ("Theirs" if side == 0 else "Yours")
		_fill(c.list, sd.get("rows", []), side)
	_paint_foot()

func _side(i: int) -> Dictionary:
	var sides: Array = _data.get("sides", [])
	return sides[i] if i < sides.size() else {}

## The running account, in the words Qud uses: a NEGATIVE difference is what you are owed.
func _paint_foot() -> void:
	var diff := int(_data.get("difference", 0))
	var drams := int(_data.get("drams", 0))
	var theirs := int(_side(0).get("total", 0))
	var yours := int(_side(1).get("total", 0))
	var col := (MONEY if diff <= 0 else OWED).to_html(false)
	var verdict := ("they owe you %d" % absi(diff)) if diff < 0 else \
		(("you owe %d" % diff) if diff > 0 else "even")
	_foot.text = ("theirs [b]%d[/b]    yours [b]%d[/b]    [color=#%s]%s[/color]\n"
		+ "you carry [b]%d[/b] drams\n"
		+ "[color=#%s]click adds one · right-click removes one · shift for the whole stack"
		+ " · [b]Enter[/b] offer · [b]Esc[/b] leave[/color]") % [
			theirs, yours, col, verdict, drams, DIM.to_html(false)]

func _fill(list: VBoxContainer, rows: Array, side: int) -> void:
	for c in list.get_children():
		c.queue_free()
	for r in rows:
		var row: Dictionary = r
		if String(row.get("kind", "")) == "Category":
			var cat := _label(HEAD_COL)
			cat.custom_minimum_size.y = CAT_H
			cat.text = "[b]%s[/b]" % QudText.strip(String(row.get("name", "")))
			list.add_child(cat)
			continue
		list.add_child(_item_row(row, side))

## One tradeable line: its tile, its name, how many you have picked, and what it costs.
func _item_row(row: Dictionary, side: int) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size.y = ROW_H
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var sel := int(row.get("selected", 0))
	if sel > 0:
		var st := StyleBoxFlat.new()
		st.bg_color = SEL_BG
		btn.add_theme_stylebox_override("normal", st)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	btn.add_child(h)

	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tiles != null:
		_tiles.tiles_dir = tiles_dir
		_tiles.palette = _palette
		icon.texture = _tiles.texture_for(row, true)
	h.add_child(icon)

	var name_l := _label(Color.WHITE)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# QUD'S OWN MARKUP, rendered rather than stripped: the colours in an item's name are how you
	# tell a steel arrow from a wooden one at a glance, and this list is nothing but such choices.
	name_l.text = QudText.to_bbcode(String(row.get("name", "")), _palette)
	h.add_child(name_l)

	if sel > 0:
		var pick := _label(HEAD_COL)
		pick.text = "[b]x%d[/b]" % sel
		pick.custom_minimum_size.x = 46
		h.add_child(pick)
	var price := _label(MONEY)
	price.text = "[right]%s[/right]" % String(row.get("price", ""))
	price.custom_minimum_size.x = 72
	h.add_child(price)

	var idx := int(row.get("idx", -1))
	var count := int(row.get("count", 1))
	btn.gui_input.connect(func(e: InputEvent) -> void: _row_input(e, side, idx, sel, count))
	return btn

func _row_input(e: InputEvent, side: int, idx: int, sel: int, count: int) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or idx < 0:
		return
	var want := want_for(mb.button_index, mb.shift_pressed, sel, count)
	if want < 0 or want == sel:
		return
	act.emit({"do": "select", "side": side, "idx": idx, "n": want})

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		act.emit({"do": "cancel"})
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		act.emit({"do": "offer"})
		get_viewport().set_input_as_handled()

## How many of a row a click asks for. -1 means "not a click this board answers".
##
## A STACK IS ONE ROW, so this is a count and not a toggle: 49 shotgun shells are a single line and
## six of them is a perfectly ordinary thing to want. Left adds one and right takes one back, both
## clamped, with shift for the whole stack either way -- which is the fast path for the case that is
## actually common, selling everything of a kind.
static func want_for(button: int, shift: bool, sel: int, count: int) -> int:
	if button == MOUSE_BUTTON_LEFT:
		return count if shift else mini(sel + 1, count)
	if button == MOUSE_BUTTON_RIGHT:
		return 0 if shift else maxi(sel - 1, 0)
	return -1
