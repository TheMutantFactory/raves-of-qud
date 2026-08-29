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

## THE CATEGORY STRIP is Qud's FilterBarCategoryButton, and it is drawn through the SHARED helper
## rather than rebuilt here. Daniel: "Let's switch the trade category carosell with the same carosel
## as the inventory. (Frames, and colors)"
##
## QudFilterBar exists for exactly this: it was lifted out of StatusPaneInventory so the journal's
## carousel would get the same pixels instead of a second, drifting copy — and then this screen went
## and made the third copy anyway, out of StyleBoxFlat borders. It owns the real nine-sliced
## `polat-category-frame` sprite, the 46x41 cell on a 58 pitch, and the 20x30 icon slot with Qud's
## own stretch (the WHOLE 16x24 tile scaled 1.25x, never normalised to the opaque box — a
## distinction that cost the inventory three attempts).
##
## Only the origin is this screen's: x502 y41 off the UiProbe dump, against the inventory's x618
## y177.
const FILTER_Y := 41.0
const FILTER_H := 41.0
const FILT_X := 502.0
## The paging badges either side of the strip, measured off the probe's own "Category Left/Right
## Hotkey Label" nodes: 19.6x26.1 at y48.4, x466.4 and x1434. That is QudFilterBar's 20x27 badge at
## this screen's corners rather than the inventory's, so the positions are taken here and the
## drawing is still the shared one.
const BADGE_L_X := 466.4
const BADGE_R_X := 1434.0
const BADGE_Y := 48.4
## Cell states, Qud's law verbatim — but only as the FALLBACK. The live colour rides on each cell in
## the frame (see the mod), because LateUpdate paints the four states only ON CHANGE: a cell nobody
## has toggled keeps its prefab colour, and which one it shows depends on the save's whole
## interaction history. That is not derivable from outside, so it is read rather than modelled.
const C_BOX := Color8(51, 80, 91)          # the untouched/prefab frame
const C_FILT_ON := Color8(122, 126, 71)    # #858951 — filtered ON
const C_ALL_OFF := Color8(19, 79, 78)      # "*All" has been toggled, so it carries a colour when off
const C_HOVER := Color8(65, 106, 115)      # #4A757E — focused

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
## Qud's scrollbar, measured: a 7-wide track at x117 for a list at x128, with a 3-wide handle inset
## 2. It is drawn nearly the colour of the background -- sampling the live screen over the handle's
## own rows returns the panel tone -- so this draws it quietly rather than inventing a bright one.
const BAR_DX := 11.0
const BAR_W := 7.0
const BAR_HANDLE_W := 3.0

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
## A CATEGORY ROW IS ONE COLOUR FOR ALL ITS PARTS, and this is Qud's own raw value — the same
## Color8(59, 93, 113) StatusPaneInventory measured off a live InventoryLine, where categoryLabel,
## categoryExpandLabel and categoryWeightText all carry RGBA(0.231, 0.365, 0.443) at alpha 1.
##
## Daniel: "Why are the Trade categories not using the same frame and coloring as the inventory
## menu? We've already solved the problem of matching Qud 1:1." Because this file picked a colour
## instead of reusing the one already measured — and picked #40A4B9, which is precisely the "{{c|}}
## cyan" the inventory file warns about by name as "far too bright and too saturated". The work had
## been done and written down one file over.
const CAT_TEXT := Color8(59, 93, 113)
## ...and at the inventory's category size. Qud's trade category box is 32 tall against an item's
## 25, the same split the inventory draws with ROW_FONT over ITEM_FONT.
const CAT_FONT := 22
## Qud's own price blue, taken from TradeLine.setData rather than sampled off a screenshot:
##     rightFloatText.color = new Color(0.2674735f, 0.6836081f, 0.9245283f)
## Daniel: "Change the cost color from green to blue to match Qud." It was green because the first
## pass picked a money colour by eye; Qud's is this.
const PRICE := Color8(0x44, 0xae, 0xec)
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
var _totals: Array = []         # [side] -> RichTextLabel
var _centre: Label
var _offer: Button               # the TRADE [n] cell — pressing it offers
var _money: RichTextLabel
var _purse: RichTextLabel        # the trader's own drams, left of the band
var _legend: HBoxContainer       # Qud's KeyMenuOptionBar: each option its own control
var _strip: Control              # the category filter cells, drawn through QudFilterBar
var _bar: RefCounted = load("res://QudFilterBar.gd").new()
var _filt_rects: Array = []      # [[Rect2, category], …] for hit-testing, rebuilt with the strip
var _filt_hover := -1
var _strip_font: Font
const C_LABEL := Color8(175, 198, 193)   # Qud's flat #afc6c1 on the ALL cell's glyphs
var _bars: Array = []            # [side] -> {scroll, track, handle}: Qud's left-gutter scrollbar
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
		# GODOT'S OWN BAR IS TURNED OFF, and its own bar is the bug. Daniel: "The scrollbar is
		# clipping the prices." Godot hangs a vertical bar on the RIGHT, inside the container, so it
		# sat straight over a price column that runs to the list's right edge. Qud puts its bar in
		# the LEFT GUTTER -- x117 against a list at x128, 7 wide with a 3-wide handle -- which is
		# exactly why its own prices reach 785 uncllipped.
		# SHOW_NEVER, not visible=false: the ScrollContainer re-asserts its bar's visibility on every
		# layout pass, so setting the flag once left it drawing a grey strip down the right edge.
		# The mode is the container's own switch and it survives relayout, while still scrolling.
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		var track := _rect(Rect2(cx - BAR_DX, LIST_Y, BAR_W, LIST_H), FRAME * Color(1, 1, 1, 0.25))
		var handle := _rect(Rect2(cx - BAR_DX + 2.0, LIST_Y, BAR_HANDLE_W, LIST_H), FRAME)
		# ...and it must be ALLOWED to shrink. _rect places through _place, which sets
		# custom_minimum_size as well as size, and a Control's size is clamped to that minimum -- so
		# every computed handle length was silently floored back to the full track. On screen the
		# handle looked like a second border down the gutter and never moved.
		handle.custom_minimum_size = Vector2.ZERO
		# ...and it has to follow the WHEEL, not just a new board. A trade frame only arrives when
		# something changes on Qud's side, so a handle painted from set_state alone would sit still
		# while the list moved under it.
		scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _paint_bars())
		# ...and on `changed`, which is when max/page are set. One deferred paint after set_state is
		# not enough: the VBox does not know its own height yet, max_value still reads as the
		# viewport's, and the handle is drawn full-length as though there were nothing to scroll.
		scroll.get_v_scroll_bar().changed.connect(_paint_bars)
		_bars.append({"scroll": scroll, "track": track, "handle": handle})
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 0)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
		_lists.append({"content": content, "scroll": scroll})

	_rect(Rect2(MID_X, COLS_Y, MID_W, LIST_H + HEAD_H), FRAME * Color(1, 1, 1, 0.18))
	_rect(Rect2(MID_X, HBORDER_Y, MID_W, 1.0), FRAME)

	_strip_font = load("res://fonts/SourceCodePro-Regular.ttf")
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP     # it hit-tests its own cells
	_strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # or every icon comes out smeared
	_place(_strip, Rect2(0.0, FILTER_Y, DESIGN.x, FILTER_H))
	_strip.draw.connect(_draw_strip)
	_strip.gui_input.connect(_strip_input)
	_design.add_child(_strip)

	var tl := _rich(DIM); _place(tl, Rect2(TOTAL_L_X, TOTALS_Y, TOTAL_W, 22.0))
	_design.add_child(tl); _totals.append(tl)
	# The TRADER's own purse, on the left of the band — Qud draws one for each party and only the
	# player's was being shown.
	_purse = _rich(GOLD); _place(_purse, Rect2(CONTENT_X + 10.0, TOTALS_Y, TOTAL_W, 22.0))
	_design.add_child(_purse)
	# 78.7 wide, which is what the probe reported. At TOTAL_W it overlapped both totals either side
	# and printed "e0en" over the left one.
	#
	# AND IT IS A BUTTON. Daniel: "Clicking Trade [0] ... does not initiate a trade." It read as the
	# thing you press to trade and did nothing, because it was a label. It is the only control on
	# the board that names the whole action, so it is the obvious place to click.
	_offer = Button.new()
	_offer.flat = true
	_offer.focus_mode = Control.FOCUS_NONE
	_place(_offer, Rect2(TOTAL_C_X, TOTALS_Y - 8.0, CENTRE_W, 42.0))
	_offer.tooltip_text = "Offer this trade  [O]"
	_offer.pressed.connect(func() -> void: act.emit({"do": "offer"}))
	_design.add_child(_offer)
	_centre = Label.new()
	_centre.add_theme_font_override("font", load("res://fonts/SourceCodePro-Regular.ttf"))
	_centre.add_theme_font_size_override("font_size", FONT_PX)
	_centre.add_theme_color_override("font_color", GOLD)
	_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_centre, Rect2(0.0, 0.0, CENTRE_W, 42.0))
	_centre.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_offer.add_child(_centre)
	var tr := _rich(DIM); _place(tr, Rect2(TOTAL_R_X, TOTALS_Y, TOTAL_W, 22.0))
	_design.add_child(tr); _totals.append(tr)
	_money = _rich(GOLD); _place(_money, Rect2(MONEY_X, TOTALS_Y, MONEY_W, 22.0))
	_design.add_child(_money)
	# THE HOTKEY LINE IS A ROW OF CONTROLS, not a sentence. Qud's own bottom bar is a
	# KeyMenuOptionBar of KeyMenuOptions — the probe has each as its own node with a Prefix and a
	# Title — so the ones that name an action are things you can press. Daniel: "Let's make '[Esc]
	# Close Menu' clickable to close the menu."
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 24)
	_place(_legend, Rect2(CONTENT_X + SEARCH_W + 16.0, LEGEND_Y, 1400.0, 22.0))
	_design.add_child(_legend)
	# ONLY WHAT WORKS, in Qud's own key names. An earlier line advertised "[=] add one" and "[-]
	# remove one" -- real Qud bindings this board does not implement, since they act on the
	# keyboard-highlighted row and there is no keyboard selection here -- and "[Space] offer", which
	# was not a binding at all.
	_legend.add_child(_legend_option("[O] Offer", {"do": "offer"}))
	_legend.add_child(_legend_option("[Esc] Close Menu", {"do": "cancel"}))
	_legend.add_child(_legend_option("[Q]/[E] category", {}))
	_legend.add_child(_legend_option("click add \u00b7 right-click remove \u00b7 shift whole stack", {}))
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
	_paint_filters()
	_paint_totals()
	_paint_bars.call_deferred()

## The handle's length and position, from how much of the list is actually showing. Deferred, because
## a VBox's content height is not known until it has laid its children out.
func _paint_bars() -> void:
	for i in _bars.size():
		var b: Dictionary = _bars[i]
		var sc: ScrollContainer = b.scroll
		if not is_instance_valid(sc) or i >= _lists.size():
			continue
		# THE CONTENT'S OWN HEIGHT, not the scrollbar's max_value. With the bar set to SHOW_NEVER
		# Godot stops maintaining its range, so max_value reads as the viewport's height and every
		# handle came out full-length as though there were nothing to scroll.
		var content: Control = _lists[i].content
		var total: float = maxf(content.size.y, 1.0)
		if total <= LIST_H:
			b.track.visible = false
			b.handle.visible = false
			continue
		var run: float = maxf(LIST_H * (LIST_H / total), 12.0)
		# The handle travels the track MINUS ITS OWN LENGTH — over the whole track it would run off
		# the bottom exactly as the list reached its end.
		var at: float = clampf(float(sc.scroll_vertical) / (total - LIST_H), 0.0, 1.0)
		b.handle.size.y = run
		b.handle.position.y = LIST_Y + (LIST_H - run) * at
		b.track.visible = true
		b.handle.visible = true

## One cell per category, "*All" first — the strip Qud hands its FilterBar, rebuilt from the same
## list. The first cell shows TEXT and the rest show ICONS, which is how Qud's own bar is built
## (the probe's first button carries a `text` child where every other carries an `icon`).
func _paint_filters() -> void:
	if _strip != null:
		_strip.queue_redraw()

## Drawn, not built out of Buttons — QudFilterBar paints Qud's own nine-sliced frame onto a
## CanvasItem, which is how the inventory and the journal both draw this strip.
func _draw_strip() -> void:
	_filt_rects.clear()
	var i := 0
	for f in _data.get("filters", []):
		var cell: Dictionary = f
		var cat := String(cell.get("cat", ""))
		var r := Rect2(Vector2(FILT_X + float(i) * float(_bar.CELL_PITCH), 0.0),
			Vector2(float(_bar.CELL_W), float(_bar.CELL_H)))
		# QUD'S LIVE COLOUR WINS. The four-state law is only the fallback for a cell the frame
		# carries none for — see the note on the constants.
		var col: Color = _filt_state(cell, cat)
		if i == _filt_hover:
			col = C_HOVER            # hover is ours to render, live or not
		_bar.cell(_strip, r, col, C_HOVER, true, Color(0, 0, 0, 0), Vector2(4, 3))
		_filt_rects.append([r, cat])
		if cat == "*All":
			var aw := _strip_font.get_string_size("ALL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			# THE LABEL DOES NOT FOLLOW THE FRAME: selecting *All golds the cell's frame, and Qud's
			# own glyphs stay a flat grey inside it. The inventory learned that one the hard way.
			_strip.draw_string(_strip_font, Vector2(r.position.x + (r.size.x - aw) * 0.5,
				r.position.y + 25.0), "ALL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_LABEL)
		else:
			var icon := String(cell.get("icon", ""))
			# THE FIXED TWO-TONE, not the tile's own colours. SetCategory hands the icon one brass
			# pair for every category, which is why Qud's strip is all one metal — drawing each in
			# its item's colours made a row of mismatched trinkets.
			var main: Color = _bar.ICON_MAIN
			var det: Color = _bar.ICON_DETAIL
			if icon == "":
				icon = String(cell.get("tile", ""))
				main = _tiles.color_of(String(cell.get("color", "")), Color.WHITE)
				det = _tiles.color_of(String(cell.get("detail", "")), Color.WHITE)
			if icon != "":
				var tex: Texture2D = _tiles.texture(icon, main, det)
				if tex != null:
					var isz: Vector2 = _bar.ICON
					_strip.draw_texture_rect(tex, Rect2(
						r.position + Vector2((r.size.x - isz.x) * 0.5, (r.size.y - isz.y) * 0.5),
						isz), false)
		i += 1
	# ...and the paging hotkeys that bound the strip. Q steps the carousel left and E right — Qud's
	# "Category Left"/"Category Right" in the CategoryNav layer, which replace the enabled set with
	# exactly one category and wrap at both ends.
	var green: Color = _tiles.color_of("g", Color(0.1, 0.5, 0.2))
	for spec in [[BADGE_L_X, "Q", "catleft"], [BADGE_R_X, "E", "catright"]]:
		var bx: float = spec[0]
		_bar.badge(_strip, _strip_font, bx, String(spec[1]), C_HOVER, green, BADGE_Y - FILTER_Y)
		var bsz: Vector2 = _bar.BADGE
		_filt_rects.append([Rect2(Vector2(bx, BADGE_Y - FILTER_Y), bsz), String(spec[2])])

## Qud's live colour for a cell, or the four-state law when the frame carries none.
func _filt_state(cell: Dictionary, cat: String) -> Color:
	var hex := String(cell.get("color", ""))
	if hex != "":
		return Color(hex)
	if bool(cell.get("on", false)):
		return C_FILT_ON
	return C_ALL_OFF if cat == "*All" else C_BOX

func _strip_input(e: InputEvent) -> void:
	var mm := e as InputEventMouseMotion
	if mm != null:
		var was := _filt_hover
		_filt_hover = -1
		for i in _filt_rects.size():
			if (_filt_rects[i][0] as Rect2).has_point(mm.position):
				_filt_hover = i
				break
		if was != _filt_hover:
			_strip.queue_redraw()
		return
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for row in _filt_rects:
		if (row[0] as Rect2).has_point(mb.position):
			var what := String(row[1])
			# The badges ride in the same list as the cells, so one hit-test serves both; they are
			# told apart by carrying a verb where a cell carries a category name.
			if what == "catleft" or what == "catright":
				act.emit({"do": what})
			else:
				act.emit({"do": "filter", "cat": what})
			return

func _side(i: int) -> Dictionary:
	var sides: Array = _data.get("sides", [])
	return sides[i] if i < sides.size() else {}

## Qud's own totals line: what each side is putting up, in drams to two places, with the arrows
## pointing the way the goods travel and TRADE [n] between them.
## QUD'S OWN STRINGS, rendered rather than recomposed. UpdateTotals writes every part of this band
## with its own markup and its own arithmetic, and the version that formatted numbers here got the
## cost multiple, the colours, the second purse and the weight all wrong at once.
func _paint_totals() -> void:
	_totals[0].text = "[right]%s[/right]" % QudText.to_bbcode(String(_side(0).get("totalText", "")), _palette)
	_totals[1].text = QudText.to_bbcode(String(_side(1).get("totalText", "")), _palette)
	# TWO LINES, which is how it fits: Qud stacks "TRADE" over the marker in a cell 78.7 wide.
	#
	# AND THE SECOND LINE IS THE OFFER HOTKEY, not a running total. Daniel: "The [0] stays at 0. It
	# does not increment/decrement. It's a hotkey marker." Qud sets it once from
	# getCommandInputFormatted("CmdTradeOffer"), so it reads [O] and follows a rebind. Drawing the
	# trade's DIFFERENCE there looked identical whenever the books balanced — and an O is a zero at
	# a glance in this font, so it passed for a number that was simply stuck.
	_centre.text = "TRADE\n%s" % QudText.strip(String(_data.get("offerKey", "[O]")))
	_centre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_purse.text = QudText.to_bbcode(String(_data.get("traderPurse", "")), _palette)
	_money.text = "[right]%s[/right]" % QudText.to_bbcode(String(_data.get("playerPurse", "")), _palette)

func _fill(content: VBoxContainer, rows: Array, side: int) -> void:
	for c in content.get_children():
		c.queue_free()
	for r in rows:
		var row: Dictionary = r
		if String(row.get("kind", "")) == "Category":
			content.add_child(_cat_row(row, side))
		else:
			content.add_child(_item_row(row, side))

## "Ammo ────────────────" — the label, then a rule running out to the column's edge. The rule is
## what makes Qud's list scannable at a glance and it is the part the first version dropped.
func _cat_row(row: Dictionary, side: int) -> Control:
	# CLICKABLE, because Qud's is. The "[-]" is a control, not a decoration, and a list of a
	# merchant's whole stock is exactly where you want to fold away the four categories you are not
	# shopping for. The flag lives in Qud's own categoryCollapsed dictionary, so folding here folds
	# it in Qud too and neither view can drift.
	var holder := Button.new()
	holder.custom_minimum_size.y = CAT_H
	holder.flat = true
	holder.focus_mode = Control.FOCUS_NONE
	var cat_name := QudText.strip(String(row.get("name", "")))
	holder.pressed.connect(func() -> void:
		act.emit({"do": "category", "side": side, "cat": cat_name}))
	# ONE LABEL, NOT TWO. TradeLine.setData writes the whole thing as a single string --
	#     categoryText.SetText("[" + ("-" or "+") + "] " + category)
	# -- and the separate Expander node the probe reports at x93 is a pooled leftover that never
	# draws there. Rendering it as its own node at a NEGATIVE offset put it outside the scroll
	# container, which clipped it away entirely: the caret simply was not on screen.
	var lab := Label.new()
	lab.text = "[%s] %s" % ["-" if not bool(row.get("collapsed", false)) else "+", cat_name]
	lab.add_theme_font_override("font", load("res://fonts/SourceCodePro-Bold.ttf"))
	lab.add_theme_font_size_override("font_size", CAT_FONT)
	# MUTED, not gold. Qud greys its category headings so the ITEMS carry the colour; drawing them
	# gold made the headings shout over the goods, which is backwards for a list you scan for stock.
	lab.add_theme_color_override("font_color", CAT_TEXT)
	lab.position = Vector2(CAT_TEXT_DX, 4.0)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lab)
	var rule := ColorRect.new()
	# The rule is part of the row, so it carries the row's colour — not the panel's frame tone.
	rule.color = CAT_TEXT
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var x: float = CAT_TEXT_DX + lab.get_theme_font("font").get_string_size(
		lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAT_FONT).x + 12.0
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
		# Qud writes the count as {{W|n}} — the bare number in its bright white. "x3" in gold was
		# the invented version inventing again.
		amt.text = "%d" % sel
		amt.add_theme_font_size_override("font_size", FONT_PX)
		amt.add_theme_color_override("font_color", Color8(0xff, 0xff, 0xff))
		# LINED UP WITH THE EXPANDERS. Daniel: "Let's move the QTY for trade to be horizontally
		# aligned with the category expand/collapse toggles." Right-aligned in its 55-wide box the
		# count floated at ~70, in a column of its own with nothing above or below it; starting it
		# where "[-]" starts puts every mark in the left gutter on one edge.
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		amt.position = Vector2(CAT_TEXT_DX, 2.0)
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
	# The base colour FIRST, then the currency exception — the other order set white and immediately
	# painted over it, which is a bug that looks like a colour that was never applied.
	price.add_theme_color_override("font_color", PRICE)
	if bool(row.get("currency", false)):
		# Qud draws a currency row's price as [{{W|$n}}] — the money itself reads brighter than the
		# goods it buys.
		price.add_theme_color_override("font_color", Color8(0xff, 0xff, 0xff))
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
	if k.keycode == KEY_Q:
		act.emit({"do": "catleft"})
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_E:
		act.emit({"do": "catright"})
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_ESCAPE:
		act.emit({"do": "cancel"})
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_O:
		# O IS QUD'S OWN OFFER KEY -- CmdTradeOffer, <keyboardBind Key="o"/>, confirmed against the
		# player's exported bindings. This was on Enter first (which every mirrored menu above the
		# board accepts with, so a stray one completed a trade by itself) and then on SPACE, which
		# was no better: Space is CmdVendorActions in Qud's Trade layer, and it is why "Nothing to
		# trade" kept appearing unbidden. Reading the binding table instead of picking a key would
		# have got this right the first time.
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


## One entry of the hotkey line. With an action it is a button — flat, so it reads as the same text
## until the pointer is on it — and without one it is plain text, because a hint you cannot press
## should not light up as though you could.
func _legend_option(text: String, action: Dictionary) -> Control:
	if action.is_empty():
		var lab := Label.new()
		lab.text = text
		lab.add_theme_font_override("font", load("res://fonts/SourceCodePro-Regular.ttf"))
		lab.add_theme_font_size_override("font_size", FONT_PX)
		lab.add_theme_color_override("font_color", DIM)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return lab
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", load("res://fonts/SourceCodePro-Regular.ttf"))
	btn.add_theme_font_size_override("font_size", FONT_PX)
	btn.add_theme_color_override("font_color", DIM)
	btn.add_theme_color_override("font_hover_color", GOLD)
	btn.add_theme_color_override("font_pressed_color", GOLD)
	btn.pressed.connect(func() -> void: act.emit(action))
	return btn
