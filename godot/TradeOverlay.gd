class_name TradeOverlay
extends CanvasLayer

## Mirrors Qud's TRADE SCREEN (Qud.UI.TradeScreen), forwarded by the mod's TradeBridge.
##
## Daniel: "We need to implement the trading menu." — then, on the first pass: "Do we already have a
## 1:1 mode trade screen? ... I don't see user mode being different for the trade screen."
##
## THIS SCREEN HAS ONE LAYOUT, AND IT IS QUD'S. The first version invented its own — VBox columns, my
## own spacing and colours — and called the gap "user-mode styling, parity later". That is not how
## this project builds a mirrored screen: PickerOverlay and CyberOverlay carry no mode branching at
## all, and PopupOverlay's only two are a narrow QoL flag. A mirrored Qud screen reproduces Qud's
## layout in both modes, full stop.
##
## SO THE NUMBERS BELOW ARE MEASURED, not chosen. They come from a UiProbe dump of the live screen
## while trading with Tam in Joppa (mod `uiprobe target=TradeScreen`), read as a MODEL rather than as
## pixels — see docs/decisions/1to1-measurement-and-layout.md. Everything is expressed in Qud's own
## 1920x1080 design space and the whole thing is scaled once to fit the window, so each constant
## below is literally the number the probe reported.
##
## THE MODEL, top to bottom:
##   panel        x106 w1708, full height — 106 of margin either side and none top or bottom
##   content      inset 6 to x112 w1696
##   top rule     y21 h20: two 760-wide rules at x112 and x1048 with a 176-wide device between
##   filter bar   y41 h41: category buttons 46x41 on a 58 pitch from x502  (NOT MIRRORED — see below)
##   columns      y90 h872.3: left x128 w800, a 64-wide panel at x928, right x992 w800
##   col header   y90 h32: a 79-wide name box, then a hairline from x216 to the column's end
##   list         y122 h840.3, rows 25 tall
##   totals       y970.3 h42
##   description  y1012.3 h29.7
##   bottom bar   y1042 h24: search box x112 w179, then the hotkey legend
##
## A ROW IS FOUR COLUMNS and the count is on the LEFT, which the invented version had backwards:
##   amount x+15 w55.2 · icon x+63 20x30 · name x+84 · price right-floated, 109.9 wide
##
## A CATEGORY ROW IS A LABEL WITH A RULE RUNNING OFF IT — "Ammo ─────────────" — with the expander
## caret in the gutter at x93, LEFT of the list's own x128. Drawing it as bold text and nothing else
## (the first version) loses the one thing that makes Qud's list scannable.
##
## NOT MIRRORED YET, because the bridge does not carry it: the category FILTER bar, the search box's
## text, and the item description line. The bands are drawn at their measured heights so nothing
## below them shifts, and they are empty rather than faked.

signal act(payload: Dictionary)

const LAYER := 128

# ── Qud's design space ──────────────────────────────────────────────────────────────────────────
const DESIGN := Vector2(1920.0, 1080.0)

# panel + content
const PANEL_X := 106.0
const PANEL_W := 1708.0
const CONTENT_X := 112.0
const CONTENT_W := 1696.0

# top rule
const RULE_Y := 23.0
const RULE_W := 760.0
const DEVICE_X := 872.0
const DEVICE_W := 176.0
const DEVICE_Y := 21.0
const DEVICE_H := 16.0

# the filter band, drawn empty (see the header)
const FILTER_Y := 41.0
const FILTER_H := 41.0

# columns
const COLS_Y := 90.0
const COL_W := 800.0
const COL_L_X := 128.0
const COL_R_X := 992.0
const MID_X := 928.0
const MID_W := 64.0
const HEAD_H := 32.0
const NAME_BOX_W := 79.0
const HBORDER_Y := 105.5
const HBORDER_X0 := 216.0        # the hairline starts after the name box, not at the column edge
const LIST_Y := 122.0
const LIST_H := 840.3
const LIST_W := 785.0

# rows
const ROW_H := 25.0
const CAT_H := 32.0
const AMOUNT_DX := 15.0
const AMOUNT_W := 55.2
const ICON_DX := 63.1
const ICON := Vector2(20.0, 30.0)
const NAME_DX := 84.4
const PRICE_DX := 675.1          # RightFloat x803.1 against the list's x128
const PRICE_W := 109.9
const CAT_TEXT_DX := 16.0
const EXPANDER_DX := -35.0       # x93 against x128: the caret lives in the gutter
const EXPANDER_W := 40.0
const CAT_RULE_H := 1.0

# the bands below
const TOTALS_Y := 970.3
const TOTAL_L_X := 736.6
const TOTAL_C_X := 920.6
const TOTAL_R_X := 1003.4
const TOTAL_W := 180.0
const CENTRE_W := 78.7
const MONEY_X := 1602.9
const MONEY_W := 181.1
const DESC_Y := 1009.1
const LEGEND_Y := 1032.0
const SEARCH_Y := 1043.0
const SEARCH_W := 179.0

const FONT_PX := 20              # every Text node on this screen measures ~20.1 tall

## Qud's own chrome tones, sampled from the same screens the other mirrors use.
const BG := Color8(0x0a, 0x1c, 0x1c, 0xfa)
const FRAME := Color8(0x15, 0x53, 0x52)
const GOLD := Color8(0xcf, 0xc0, 0x41)
const DIM := Color8(0x77, 0xbf, 0xcf)
const CAT_TEXT := Color8(0x40, 0xa4, 0xb9)
const MONEY := Color8(0x00, 0xc4, 0x20)
const OWED := Color8(0xd7, 0x42, 0x00)
const SEL_BG := Color8(0x15, 0x53, 0x52, 0xcc)

var _palette := {}
var _tiles: RefCounted = null
var _data := {}
var _built := false
var _design: Control            # everything below lives in Qud units inside this
var _lists: Array = []          # [side] -> {content: Control, scroll: ScrollContainer}
var _heads: Array = []          # [side] -> Label
var _totals: Array = []         # [side] -> Label
var _centre: Label
var _money: Label
var _legend: Label
var tiles_dir := ""


func _ready() -> void:
	layer = LAYER
	visible = false

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
	_fit()
	_paint()
	visible = true

func active() -> bool:
	return visible

# ── construction ────────────────────────────────────────────────────────────────────────────────

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	if _tiles == null:
		_tiles = load("res://QudTiles.gd").new()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP     # the board owns its screen, like Qud's
	add_child(root)

	_design = Control.new()
	_design.custom_minimum_size = DESIGN
	_design.size = DESIGN
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_design)

	_rect(Rect2(PANEL_X, 0, PANEL_W, DESIGN.y), BG)
	# the top rule: two runs with a device floated between them, not one rule across
	_rect(Rect2(CONTENT_X, RULE_Y, RULE_W, 2), FRAME)
	_rect(Rect2(DEVICE_X, DEVICE_Y, DEVICE_W, DEVICE_H), FRAME * Color(1, 1, 1, 0.55))
	_rect(Rect2(1048.0, RULE_Y, RULE_W, 2), FRAME)

	for side in 2:
		var cx: float = COL_L_X if side == 0 else COL_R_X
		# the column's name box, then its hairline out to the column's far edge
		_rect(Rect2(cx, COLS_Y, NAME_BOX_W, HEAD_H), FRAME * Color(1, 1, 1, 0.35))
		var head := _text(GOLD)
		_place(head, Rect2(cx + 8.0, COLS_Y + 6.0, NAME_BOX_W - 12.0, 20.0))
		_heads.append(head)
		var hb_x: float = cx + (HBORDER_X0 - COL_L_X)
		_rect(Rect2(hb_x, HBORDER_Y, cx + COL_W - hb_x, 1.0), FRAME)

		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		_place(scroll, Rect2(cx, LIST_Y, LIST_W, LIST_H))
		_design.add_child(scroll)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 0)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
		_lists.append({"content": content, "scroll": scroll})

	_rect(Rect2(MID_X, COLS_Y, MID_W, LIST_H + HEAD_H), FRAME * Color(1, 1, 1, 0.18))
	_rect(Rect2(MID_X, HBORDER_Y, MID_W, 1.0), FRAME)

	var tl := _text(DIM); _place(tl, Rect2(TOTAL_L_X, TOTALS_Y, TOTAL_W, 22.0)); _totals.append(tl)
	# 78.7 wide, which is what the probe reported. At TOTAL_W it overlapped both totals either side
	# and printed "e0en" over the left one.
	_centre = _text(GOLD); _place(_centre, Rect2(TOTAL_C_X, TOTALS_Y - 8.0, CENTRE_W, 42.0))
	_centre.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tr := _text(DIM); _place(tr, Rect2(TOTAL_R_X, TOTALS_Y, TOTAL_W, 22.0)); _totals.append(tr)
	_money = _text(MONEY); _place(_money, Rect2(MONEY_X, TOTALS_Y, MONEY_W, 22.0))
	_legend = _text(DIM); _place(_legend, Rect2(CONTENT_X + SEARCH_W + 16.0, LEGEND_Y, 1400.0, 22.0))
	# the search box's outline, drawn empty: the bridge does not carry its text, and an empty box in
	# the right place is honest where a faked one is not
	_rect(Rect2(CONTENT_X + 31.0, SEARCH_Y + 2.0, 146.0, 18.0), FRAME * Color(1, 1, 1, 0.4))

## Scale Qud's 1920x1080 board to whatever window Raves is in, once, uniformly — so every constant
## above stays the number the probe reported instead of being pre-divided by something.
func _fit() -> void:
	var vp := Vector2(get_viewport().size)
	var s: float = minf(vp.x / DESIGN.x, vp.y / DESIGN.y)
	_design.scale = Vector2(s, s)
	_design.position = Vector2((vp.x - DESIGN.x * s) * 0.5, (vp.y - DESIGN.y * s) * 0.5)

func _rect(r: Rect2, col: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = col
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(c, r)
	_design.add_child(c)
	return c

func _place(n: Control, r: Rect2) -> void:
	n.position = r.position
	n.size = r.size
	n.custom_minimum_size = r.size

func _text(col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", load("res://fonts/SourceCodePro-Regular.ttf"))
	l.add_theme_font_size_override("font_size", FONT_PX)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _design != null:
		_design.add_child(l)
	return l

func _rich(col: Color) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.scroll_active = false
	l.add_theme_font_override("normal_font", load("res://fonts/SourceCodePro-Regular.ttf"))
	l.add_theme_font_size_override("normal_font_size", FONT_PX)
	l.add_theme_color_override("default_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ── painting ────────────────────────────────────────────────────────────────────────────────────

func _paint() -> void:
	var trader := QudText.strip(String(_data.get("trader", "")))
	# Qud's own two boxes: the trader's name on the left, yours on the right.
	_heads[0].text = trader.split(",")[0]
	_heads[1].text = QudText.strip(String(_data.get("you", "You"))).split(",")[0]
	for side in 2:
		_fill(_lists[side].content, _side(side).get("rows", []), side)
	_paint_totals()

func _side(i: int) -> Dictionary:
	var sides: Array = _data.get("sides", [])
	return sides[i] if i < sides.size() else {}

## Qud's own totals line: what each side is putting up, in drams to two places, with the arrows
## pointing the way the goods travel and TRADE [n] between them.
func _paint_totals() -> void:
	var diff := int(_data.get("difference", 0))
	_totals[0].text = "%s drams \u2192" % String(_side(0).get("totalText", "0.00"))
	_totals[1].text = "\u2190 %s drams" % String(_side(1).get("totalText", "0.00"))
	_totals[0].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_totals[1].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# TWO LINES, which is how it fits. Qud stacks "TRADE" over "[n]" in a cell 78.7 wide; on one
	# line the text overruns the cell and prints straight through the totals either side of it.
	_centre.text = "TRADE\n[%d]" % diff
	_centre.add_theme_color_override("font_color", MONEY if diff <= 0 else OWED)
	_centre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var carry := String(_data.get("carry", ""))
	_money.text = ("$%d | %s" % [int(_data.get("drams", 0)), carry]) if carry != "" \
		else "$%d" % int(_data.get("drams", 0))
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Qud's own hotkey line, in Qud's order. The mouse verbs are ours and are named after them.
	_legend.text = "[Esc] Close Menu    [=] add one    [-] remove one    [Space] offer" \
		+ "        click add \u00b7 right-click remove \u00b7 shift whole stack"

func _fill(content: VBoxContainer, rows: Array, side: int) -> void:
	for c in content.get_children():
		c.queue_free()
	for r in rows:
		var row: Dictionary = r
		if String(row.get("kind", "")) == "Category":
			content.add_child(_cat_row(row))
		else:
			content.add_child(_item_row(row, side))

## "Ammo ────────────────" — the label, then a rule running out to the column's edge. The rule is
## what makes Qud's list scannable at a glance and it is the part the first version dropped.
func _cat_row(row: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size.y = CAT_H
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caret := Label.new()
	# Qud writes the expander in BRACKETS -- "[-] Ammo" -- and it reads as a control that way rather
	# than as a stray dash.
	caret.text = "[-]" if not bool(row.get("collapsed", false)) else "[+]"
	caret.add_theme_font_size_override("font_size", FONT_PX)
	caret.add_theme_color_override("font_color", DIM)
	caret.position = Vector2(EXPANDER_DX + 4.0, 4.0)
	caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(caret)
	var lab := Label.new()
	lab.text = QudText.strip(String(row.get("name", "")))
	lab.add_theme_font_override("font", load("res://fonts/SourceCodePro-Bold.ttf"))
	lab.add_theme_font_size_override("font_size", FONT_PX)
	# MUTED, not gold. Qud greys its category headings so the ITEMS carry the colour; drawing them
	# gold made the headings shout over the goods, which is backwards for a list you scan for stock.
	lab.add_theme_color_override("font_color", CAT_TEXT)
	lab.position = Vector2(CAT_TEXT_DX, 4.0)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lab)
	var rule := ColorRect.new()
	rule.color = FRAME
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var x: float = CAT_TEXT_DX + lab.get_theme_font("font").get_string_size(
		lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x + 12.0
	rule.position = Vector2(x, CAT_H * 0.5)
	rule.size = Vector2(maxf(LIST_W - x - 8.0, 0.0), CAT_RULE_H)
	holder.add_child(rule)
	return holder

func _item_row(row: Dictionary, side: int) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size.y = ROW_H
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	var sel := int(row.get("selected", 0))
	if sel > 0:
		var st := StyleBoxFlat.new()
		st.bg_color = SEL_BG
		btn.add_theme_stylebox_override("normal", st)

	# THE COUNT IS ON THE LEFT, before the icon — measured, and the opposite of where the invented
	# version put it. It is how Qud shows what you have already picked off a stack.
	if sel > 0:
		var amt := Label.new()
		amt.text = "x%d" % sel
		amt.add_theme_font_size_override("font_size", FONT_PX)
		amt.add_theme_color_override("font_color", GOLD)
		amt.position = Vector2(AMOUNT_DX, 2.0)
		amt.custom_minimum_size = Vector2(AMOUNT_W, ROW_H)
		amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(amt)

	var icon := TextureRect.new()
	icon.position = Vector2(ICON_DX, (ROW_H - ICON.y) * 0.5)
	icon.size = ICON
	icon.custom_minimum_size = ICON
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tiles != null:
		_tiles.tiles_dir = tiles_dir
		_tiles.palette = _palette
		icon.texture = _tiles.texture_for(row, true)
	btn.add_child(icon)

	var name_l := _rich(Color.WHITE)
	name_l.position = Vector2(NAME_DX, 1.0)
	name_l.size = Vector2(PRICE_DX - NAME_DX - 8.0, ROW_H)
	name_l.custom_minimum_size = name_l.size
	# Qud's own markup, rendered rather than stripped: the colours in a name are how you tell a steel
	# arrow from a wooden one, and this list is nothing but such choices.
	name_l.text = QudText.to_bbcode(String(row.get("name", "")), _palette)
	btn.add_child(name_l)

	var price := Label.new()
	# "[$0.71]" — Qud's own form. A bare number in a column of bare numbers does not say drams.
	var p := String(row.get("price", ""))
	price.text = ("[$%s]" % p) if p != "" else ""
	price.add_theme_font_size_override("font_size", FONT_PX)
	price.add_theme_color_override("font_color", MONEY)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.position = Vector2(PRICE_DX, 2.0)
	price.size = Vector2(PRICE_W, ROW_H)
	price.custom_minimum_size = price.size
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(price)

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
	elif k.keycode == KEY_SPACE:
		# SPACE, NOT ENTER. Enter is what every mirrored menu above this one accepts with, and a
		# stray one arriving as the board opened completed a trade on its own -- harmless that time
		# because nothing was selected, and a way to give away your things the next. Qud's own
		# offer is a deliberate control too.
		act.emit({"do": "offer"})
		get_viewport().set_input_as_handled()

## How many of a row a click asks for. -1 means "not a click this board answers".
##
## A STACK IS ONE ROW, so this is a count and not a toggle: 49 shotgun shells are a single line and
## six of them is a perfectly ordinary thing to want. Left adds one and right takes one back, both
## clamped, with shift for the whole stack either way.
static func want_for(button: int, shift: bool, sel: int, count: int) -> int:
	if button == MOUSE_BUTTON_LEFT:
		return count if shift else mini(sel + 1, count)
	if button == MOUSE_BUTTON_RIGHT:
		return 0 if shift else maxi(sel - 1, 0)
	return -1
