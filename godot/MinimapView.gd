extends PanelContainer

## Minimap view — its own scene in MainFrame's row-3 side column. A low-res top-down map of the
## CURRENT zone, built CLIENT-SIDE from the snapshot's cells (no mod data): one pixel per cell, with
## the player marked, scaled up nearest-neighbour to fill.
##
## Two modes, toggled in the title bar:
##   FULL (default): every cell tinted by its topmost object's colour — a rich, painterly map.
##   MINIMAL (Qud-style): walls drawn PRONOUNCED (brightened), everything else dimmed to a faint hint,
##                        so the built structure of the zone reads at a glance.

const BG := Color(0.05, 0.06, 0.08)
const PLAYER := Color(1, 1, 1)

const MODE_FULL := 0
const MODE_MINIMAL := 1

# MINIMAL mode tuning: walls are lifted toward white; other objects are knocked down toward BG.
const WALL_LIFT := 0.45     # how far a wall's colour is lerped toward white
const NONWALL_DIM := 0.30   # how much of a non-wall object's colour survives (rest -> BG)

var _tiles: RefCounted   # shared colour resolution (QudTiles), set in _ready
var _palette := {}
var _rect: TextureRect
var _map_margin: MarginContainer   # 1:1 left inset for the map image
var _vbox: VBoxContainer
var _tex: ImageTexture   # reused across snapshots; only reallocated when the zone size changes
var _toggle: Button
var _title: Label      # header — "Minimap" (user) or the zone name (1:1, Qud-style)
var _mode := MODE_FULL
## WHICH MAP. Daniel: "Let's have a Raves setting for minimap 1:1, or top-down camera. That should
## help navigate in the underworld." Two of these already existed behind the panel's own toggle and
## one is new; the setting names all four in one place so the choice is somewhere you can find it.
##   full / minimal  the painted and structural client-side maps (the old toggle)
##   qud             Qud's OWN minimap, which until now only parity mode could reach
##   tiles           the zone composited from Qud's OWN tile art, one sprite per cell
const SRC_KEY := "minimap_source"
## THE TILE MAP'S CELL SIZE, in map pixels — Qud's own art size, so sprites keep their shape and
## the TextureRect scales the whole thing nearest-neighbour like every other source here.
const TILE_W := 16
const TILE_H := 24
## WRITE-THROUGH TO Settings, off in tests. The toggle saves, and a headless run that presses it
## puts a fixture's choice into the developer's own settings.json — which this test did, once,
## before this existed. The drone panel has the same flag for the same reason.
var persist := true
var world_ref: Node3D   # unused; kept so MainFrame's late-bind does not need unpicking
var probe := {}         # last tile-map pass, for control.py minimapdump
var _last_data := {}   # last snapshot, so a mode toggle re-renders without waiting for a new one

func _ready() -> void:
	_tiles = load("res://QudTiles.gd").new()
	_apply_panel_box()

	_vbox = VBoxContainer.new()
	var v := _vbox
	v.add_theme_constant_override("separation", 4)
	add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	_title = Label.new()
	_title.text = "Minimap"
	_title.add_theme_font_size_override("font_size", UiFont.px(get_viewport(), "title"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_toggle = Button.new()
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.pressed.connect(_toggle_mode)
	head.add_child(_toggle)
	_refresh_toggle()

	# the map sits inset from the panel's content edge in 1:1 (Qud: content 1641, map 1658)
	_map_margin = MarginContainer.new()
	v.add_child(_map_margin)
	_rect = TextureRect.new()
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixels, no blur
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# IGNORE_SIZE: the rect's min size is 0 (not the tiny 80x25 texture), so EXPAND_FILL actually grows
	# it to fill the panel height — otherwise the image stays a small centred strip and the panel's
	# min-height just adds dead space below it.
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# AT BUILD TIME, not only on a mode change. set_one_to_one returns early when the mode has not
	# changed, and user mode is the DEFAULT — so on a normal launch nothing ever gave the map a
	# height at all.
	_rect.custom_minimum_size = Vector2(0, MAP_H_USER)
	_map_margin.add_child(_rect)


## MainFrame calls this each snapshot with the full data (needs cells + player + zone dims + palette).
func set_snapshot(data: Dictionary) -> void:
	_last_data = data
	var pal: Dictionary = data.get("palette", {})
	if not pal.is_empty():
		_palette = pal
	_tiles.palette = _palette
	# ...AND WHERE THE ART LIVES. The painted map only ever asked QudTiles for COLOURS, which need
	# no directory, so this line was never missed. texture_for does need it, and without it every
	# lookup returns null and the tile map composites a blank image — which looks exactly like a
	# camera pointed at nothing, the failure this replaced.
	_tiles.tiles_dir = String(data.get("tilesDir", _tiles.tiles_dir))
	if _one_to_one:
		_update_title_1to1()   # Qud puts the zone name atop the minimap; keep it live as we travel
	_rerender()

## 1:1 header: the zone/terrain name (Qud's sidebar header), from the snapshot's stats. Falls back to
## "Minimap" so the header is never blank before the first stats arrive.
func _update_title_1to1() -> void:
	if _title == null:
		return
	var nm := QudText.strip(String(_last_data.get("stats", {}).get("terrain", "")))
	_title.text = nm if nm != "" else "Minimap"

## 1:1 (parity) mode: render the Qud-faithful minimap — the MINIMAL (structural) map, no FULL/MINIMAL
## toggle (Qud has none), and the header shows the zone name instead of "Minimap". Reverting restores
## the QoL header + toggle.
var _one_to_one := false
var _saved_mode := MODE_FULL   # user's FULL/MINIMAL choice, restored when leaving 1:1
func set_one_to_one(on: bool) -> void:
	if on == _one_to_one:
		return
	_one_to_one = on
	if _toggle != null:
		_toggle.visible = not on
	# Give the map image a real height. Setting it on the TextureRect (content-min) reliably grows the
	# panel — the panel's own custom_minimum_size wasn't translating into a taller image (the rect stayed
	# a short strip).
	#
	# 1:1 is Qud's MEASURED rect: 240x104 (confirmed against the live RectTransform), which is aspect
	# 2.31 while the texture is 80x50 = 1.60 — Qud STRETCHES the map, it does not fit it. Raves was
	# aspect-fitting into 190x119, so every feature sat at the wrong scale.
	if _rect != null:
		# USER MODE NEEDS A HEIGHT TOO. This was (0, 0), which was harmless only because user mode
		# never reached this panel: with no QoL feature the minimap was Qud's shape in BOTH modes,
		# so the 1:1 branch always won and always set a size. Giving the panel a feature made user
		# mode reachable for the first time and the map area collapsed to nothing — a composite
		# with 43,080 lit pixels in it, drawn into zero height.
		_rect.custom_minimum_size = Vector2(MAP_W_1TO1, MAP_H_1TO1) if on else Vector2(0, MAP_H_USER)
		_rect.stretch_mode = TextureRect.STRETCH_SCALE if on else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if on else Control.SIZE_EXPAND_FILL
		_rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if on else Control.SIZE_EXPAND_FILL
	if _map_margin != null:
		_map_margin.add_theme_constant_override("margin_left", MAP_X_1TO1 if on else 0)
	# Qud's header glyphs and ours land on the same rows, but its map starts 4px higher — the gap
	# under the heading is smaller than the QoL one. Measured: Qud map top y114, ours y118.
	if _vbox != null:
		_vbox.add_theme_constant_override("separation", 0 if on else 4)
	if on:
		_saved_mode = _mode
		_mode = MODE_MINIMAL     # Qud's structural overview, not the painterly per-cell FULL map
		_update_title_1to1()
	else:
		_mode = _saved_mode      # restore the user's map style
		if _title != null:
			_title.text = "Minimap"
		_refresh_toggle()
	# the heading is Qud's dim grey-teal at the log's 0.76x body, as on the two panels below
	if _title != null:
		if on:
			_title.add_theme_font_size_override("font_size",
				int(round(UiFont.px(get_viewport(), "body") * LOG_FONT_FRAC_1TO1)))
			_title.add_theme_color_override("font_color", TITLE_COLOR_1TO1)
		else:
			_title.add_theme_font_size_override("font_size", UiFont.px(get_viewport(), "title"))
			_title.remove_theme_color_override("font_color")
	_apply_panel_box()
	queue_redraw()
	_rerender()

## 1:1: Qud's OWN minimap, from the mod's `minimap` block (Cell.RefreshMinimapColor per cell).
##
## Geometry is Qud's: its texture is 80x50 for a 25-row zone — EACH ZONE ROW WRITES TWO TEXTURE
## ROWS (ActionManager.UpdateMinimap: `(24 - i) * 2` and `+ 1`), which also flips the map so row 0
## is at the bottom. Point-filtered. Reproducing the doubling rather than stretching a 80x25 image
## keeps the two textures directly comparable if Qud's own ever renders.
##
## Colours carry ALPHA (unexplored 32, unlit 128, lit 164, features 230) so the panel background
## washes through — this is a translucent overlay, not opaque pixels.
func _render_qud_minimap(mm: Dictionary) -> bool:
	var w := int(mm.get("width", 0))
	var h := int(mm.get("height", 0))
	var cells := String(mm.get("cells", ""))
	var pal: Array = mm.get("palette", [])
	if w <= 0 or h <= 0 or cells.length() < w * h or pal.is_empty():
		return false
	var cols: Array[Color] = []
	for p in pal:
		var s := String(p)
		if s.length() < 8:
			cols.append(Color(0, 0, 0, 0))
			continue
		cols.append(Color8(("0x" + s.substr(0, 2)).hex_to_int(), ("0x" + s.substr(2, 2)).hex_to_int(),
			("0x" + s.substr(4, 2)).hex_to_int(), ("0x" + s.substr(6, 2)).hex_to_int()))
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.modulate = Color.WHITE
	var img := Image.create(w, h * 2, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var idx := QUD_MM_ALPHABET.find(cells[y * w + x])
			var c: Color = cols[idx] if idx >= 0 and idx < cols.size() else Color(0, 0, 0, 0)
			# Row doubling only — NO vertical flip. Qud's `(24 - i) * 2` looks like a flip but is
			# compensation for UNITY textures being bottom-up (y=0 at the bottom); Godot's Image is
			# top-down, so copying that arithmetic here flipped the map a second time. Measured:
			# correlation against Qud went 0.083 as-was, 0.745 with the flip removed.
			var ty := y * 2
			img.set_pixel(x, ty, c)
			img.set_pixel(x, ty + 1, c)
	if _tex != null and _tex.get_width() == w and _tex.get_height() == h * 2:
		_tex.update(img)
	else:
		_tex = ImageTexture.create_from_image(img)
		_rect.texture = _tex
	return true

## Qud's minimap rect, measured off its live RectTransform + the rendered frame at 1080:
## 240x104 at x1658 (content origin 1641 -> 17 in), map top y114.
## The map's height in user mode. Qud's own is 104 against its fixed sidebar; the Raves column is
## wider and resizable, so this only sets a floor and the rect grows with the panel.
## How far the tile map is lifted. Enough to read a cave at panel size without blowing out the
## lit cells — the player's own white mark is already at full.
const TILE_LIFT := Color(2.2, 2.2, 2.2)
const MAP_H_USER := 120.0
const MAP_W_1TO1 := 240.0
const MAP_H_1TO1 := 104.0
const MAP_X_1TO1 := 17

const QUD_MM_ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

# ── 1:1 chrome, shared with the two panels below it so the sidebar reads as one column ──────────
const LOG_FONT_FRAC_1TO1 := 0.76
const TITLE_COLOR_1TO1 := Color8(59, 89, 107)
const SEP_MARGIN_1TO1 := 20
## Qud's movable-window backdrop: a dot every 16px, one shade off the panel fill (measured
## (19,23,26) against the (17,33,38) chrome).
const DOT_PITCH_1TO1 := 16
var DOT_COLOR_1TO1 := QudChrome.q8(19, 23, 26)
var SEP_OUTER := QudChrome.q8(68, 99, 112)
var SEP_CENTER := QudChrome.q8(30, 57, 72)

func _apply_panel_box() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = QudChrome.q8(17, 33, 38) if _one_to_one else QudPalette.CHROME
	sb.content_margin_left = SEP_MARGIN_1TO1 if _one_to_one else 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0 if _one_to_one else 6
	sb.content_margin_bottom = 6
	if not _one_to_one:
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.12)
		sb.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", sb)

## 1:1 only: the ||| grab-bar (continuing the log's, centre column 2px wide — see MessageLog) and
## Qud's dotted window backdrop behind the map.
func _draw() -> void:
	if not _one_to_one:
		return
	var h := size.y
	for y in range(0, int(h), DOT_PITCH_1TO1):
		for x in range(SEP_MARGIN_1TO1, int(size.x), DOT_PITCH_1TO1):
			draw_rect(Rect2(x, y, 1, 1), DOT_COLOR_1TO1)
	draw_rect(Rect2(2, 0, 1, h), SEP_OUTER)
	draw_rect(Rect2(6, 0, 2, h), SEP_CENTER)
	draw_rect(Rect2(11, 0, 1, h), SEP_OUTER)

func _rerender() -> void:
	var data := _last_data
	if data.is_empty():
		return
	# PARITY STILL WINS. In 1:1 the minimap is Qud's, whatever the user picked — the setting is a
	# user-mode choice and 1:1 is the mode that has no choices.
	var src := "qud" if _one_to_one else String(Settings.get_value(SRC_KEY, "full"))
	# RECORDED ON EVERY PASS, not just inside the tile branch. The first version only wrote the
	# probe once the tile path ran, so "never ran" and "ran with a different source" both read as
	# an empty dict — the one distinction worth having.
	probe = {"renders": int(probe.get("renders", 0)) + 1, "src": src, "one_to_one": _one_to_one,
		"has_data": not data.is_empty(), "tiles_dir": _tiles.tiles_dir,
		"zone_w": int(data.get("zone", {}).get("width", 0)),
		"zone_h": int(data.get("zone", {}).get("height", 0)),
		"cells": (data.get("cells", []) as Array).size()}
	_refresh_toggle()   # Options can change this key too; the button must not disagree with it
	# 1:1 renders QUD's map when the mod ships it; anything else falls back to the QoL map below.
	if src == "qud":
		var mm: Variant = data.get("minimap", null)
		if mm is Dictionary and _render_qud_minimap(mm):
			return
		# ...and if the mod shipped none, fall through to the client-side map rather than leaving
		# the panel blank: a minimap that vanishes reads as broken, not as unavailable.
	elif src == "minimal":
		_mode = MODE_MINIMAL
	elif src == "full":
		_mode = MODE_FULL
	if src == "tiles":
		var zt: Dictionary = data.get("zone", {})
		var tw := int(zt.get("width", 0))
		var th := int(zt.get("height", 0))
		if tw > 0 and th > 0 and _render_tiles(data, tw, th):
			return
	var z: Dictionary = data.get("zone", {})
	var w := int(z.get("width", 0))
	var h := int(z.get("height", 0))
	if w <= 0 or h <= 0:
		return
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # one pixel per cell: keep it crisp
	_rect.modulate = Color.WHITE
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for cell in data.get("cells", []):
		var x := int(cell.get("x", -1))
		var y := int(cell.get("y", -1))
		if x < 0 or y < 0 or x >= w or y >= h:
			continue
		img.set_pixel(x, y, _cell_color(cell))
	var p: Dictionary = data.get("player", {})
	var px := int(p.get("x", -1))
	var py := int(p.get("y", -1))
	if px >= 0 and py >= 0 and px < w and py < h:
		img.set_pixel(px, py, PLAYER)
	# Reuse one texture: update its pixels in place, only reallocating if the zone size changed. This
	# avoids a per-turn GPU texture alloc/free that would otherwise churn during the risky viewport
	# enable window.
	if _tex != null and _tex.get_width() == w and _tex.get_height() == h:
		_tex.update(img)
	else:
		_tex = ImageTexture.create_from_image(img)
		_rect.texture = _tex

## Colour of one cell, per mode.
## THE ZONE IN QUD'S OWN TILES. Daniel: "is it possible to just load the zone tilesets from Qud?
## That's what I would be looking at. No 'camera' needed."
##
## He was right, and it retires a camera that never drew anything. A top-down view of a 3D world
## has to be aimed, framed, transformed out of cell space and told which layers to ignore — four
## chances to be wrong, and I was wrong at least three times. The tiles are already loaded, already
## recoloured per object, and already keyed by the same cell data this panel reads: the map is a
## composite, not a render.
##
## THE SAME OBJECT THE PAINTED MAP PICKS, so the two sources agree about what is in a cell and
## differ only in how much of it they show.
func _render_tiles(data: Dictionary, w: int, h: int) -> bool:
	# WHAT THIS PASS ACTUALLY SAW, for `control.py minimapdump`. Two blind fixes in a row failed
	# here; every one of them would have been a one-line read with this.
	probe["tile_pass"] = true
	probe["rect_visible"] = _rect.visible
	probe["with_objs"] = 0
	probe["tex_ok"] = 0
	probe["tex_null"] = 0
	var img := Image.create(w * TILE_W, h * TILE_H, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for cell in data.get("cells", []):
		var x := int(cell.get("x", -1))
		var y := int(cell.get("y", -1))
		if x < 0 or y < 0 or x >= w or y >= h:
			continue
		var objs: Array = cell.get("objs", [])
		if objs.is_empty():
			continue
		probe["with_objs"] += 1
		var tex: Texture2D = _tiles.texture_for(objs[objs.size() - 1], true)
		if tex == null:
			probe["tex_null"] += 1
			continue
		probe["tex_ok"] += 1
		var ti := tex.get_image()
		if ti == null:
			probe["img_null"] = int(probe.get("img_null", 0)) + 1
			continue
		if ti.get_format() != Image.FORMAT_RGBA8:
			ti.convert(Image.FORMAT_RGBA8)
		# BLENDED, not blitted: the art is mostly transparent and a straight copy would punch the
		# background out around every sprite, leaving each tile in its own black box.
		img.blend_rect(ti, Rect2i(Vector2i.ZERO, ti.get_size()),
			Vector2i(x * TILE_W, y * TILE_H))
	var p: Dictionary = data.get("player", {})
	var px := int(p.get("x", -1))
	var py := int(p.get("y", -1))
	if px >= 0 and py >= 0 and px < w and py < h:
		# The player as a box rather than his own sprite: at this size the map is about WHERE he is,
		# and his tile is one more sprite among two thousand.
		_mark_player(img, px, py)
	# WHAT ENDED UP IN THE PICTURE. tex_ok counts textures that RESOLVED, which says nothing about
	# whether their pixels reached the map — the difference between a compositing failure and a
	# display one, and the only thing three rebuilds have not been able to tell apart.
	var ink := 0
	for yy in range(0, img.get_height(), 4):
		for xx in range(0, img.get_width(), 4):
			var c := img.get_pixel(xx, yy)
			if absf(c.r - BG.r) > 0.03 or absf(c.g - BG.g) > 0.03 or absf(c.b - BG.b) > 0.03:
				ink += 1
	probe["ink"] = ink
	probe["sampled"] = int(img.get_height() / 4) * int(img.get_width() / 4)
	# LINEAR, FOR THIS SOURCE ONLY. Every other map here is one pixel per cell and wants crisp
	# nearest-neighbour; this one is 1280x600 of sprite art squeezed into a panel a quarter that
	# wide, and NEAREST samples a single pixel per tile — usually one of the transparent ones,
	# since tile art is mostly empty. That is what made a composite of 2000 successfully resolved
	# tiles read as a blank panel: the pixels were there and the filter threw them away.
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# LIFTED, because the art is dark and the panel is darker. Measured on a subterranean canyon:
	# the composite drew correctly all along — 145 distinct colours, luminance 16 to 255 — and read
	# as an empty panel because its median pixel sat at 51. The painted map already brightens for
	# the same reason (WALL_LIFT); this does it with modulate so the composite stays honest.
	_rect.modulate = TILE_LIFT
	var want := Vector2i(w * TILE_W, h * TILE_H)
	if _tex != null and _tex.get_size() == Vector2(want):
		_tex.update(img)
	else:
		_tex = ImageTexture.create_from_image(img)
		_rect.texture = _tex
	# THE LAST GAP: a picture with ink in it, a visible rect, and still nothing on screen. These
	# say whether the texture reached the control and whether the control has any room to draw it.
	probe["rect_size"] = [_rect.size.x, _rect.size.y]
	probe["rect_min"] = [_rect.custom_minimum_size.x, _rect.custom_minimum_size.y]
	probe["margin_size"] = [_map_margin.size.x, _map_margin.size.y] if _map_margin != null else []
	probe["tex_on_rect"] = _rect.texture != null
	probe["tex_size"] = [_tex.get_width(), _tex.get_height()]
	probe["panel_size"] = [size.x, size.y]
	return true


## A hollow box around the player's cell — hollow so his own tile still reads inside it.
func _mark_player(img: Image, px: int, py: int) -> void:
	var x0 := px * TILE_W
	var y0 := py * TILE_H
	for i in TILE_W:
		img.set_pixel(x0 + i, y0, PLAYER)
		img.set_pixel(x0 + i, y0 + TILE_H - 1, PLAYER)
	for j in TILE_H:
		img.set_pixel(x0, y0 + j, PLAYER)
		img.set_pixel(x0 + TILE_W - 1, y0 + j, PLAYER)


func _cell_color(cell: Dictionary) -> Color:
	var objs: Array = cell.get("objs", [])
	if objs.is_empty():
		return BG
	if _mode == MODE_MINIMAL:
		return _cell_color_minimal(objs)
	return _tiles.main_color(objs[objs.size() - 1], BG)   # FULL: top of the stack

## MINIMAL: a wall in the cell wins and is lifted toward white (pronounced, Qud-style); otherwise the
## topmost object is dimmed to a faint structural hint. (BG is the fallback so colourless cells recede.)
func _cell_color_minimal(objs: Array) -> Color:
	for i in range(objs.size() - 1, -1, -1):
		if bool(objs[i].get("wall", false)):
			return _tiles.main_color(objs[i], BG).lerp(Color.WHITE, WALL_LIFT)
	return BG.lerp(_tiles.main_color(objs[objs.size() - 1], BG), NONWALL_DIM)

## THE BUTTON AND THE SETTING ARE THE SAME THING. This used to flip a local _mode, which the
## setting would then overwrite on the next snapshot — the button would appear to work and undo
## itself a fraction of a second later. It cycles the SOURCE now, so the panel and Options are two
## views of one value.
const SOURCES := ["full", "minimal", "qud", "tiles"]
const SOURCE_LABEL := {"full": "full", "minimal": "minimal", "qud": "qud", "tiles": "tiles"}

func _toggle_mode() -> void:
	var i: int = SOURCES.find(String(Settings.get_value(SRC_KEY, "full")))
	var nxt: String = SOURCES[(maxi(i, 0) + 1) % SOURCES.size()]
	Settings.set_value(SRC_KEY, nxt)
	if persist:
		Settings.save()
	_refresh_toggle()
	_rerender()

func _refresh_toggle() -> void:
	if _toggle == null:
		return
	var src := String(Settings.get_value(SRC_KEY, "full"))
	_toggle.text = String(SOURCE_LABEL.get(src, src))
	var i: int = SOURCES.find(src)
	var nxt: String = SOURCES[(maxi(i, 0) + 1) % SOURCES.size()]
	_toggle.tooltip_text = "Switch to the %s minimap" % String(SOURCE_LABEL.get(nxt, nxt))

## The strip MainFrame grabs to reorder this panel in the side column. The HEADING, because it is
## the one part of the panel that is not already something clickable, scrollable or drawn on.
func drag_handle() -> Control:
	return _title
