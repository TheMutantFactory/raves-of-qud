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
##   topdown         a live camera looking straight down at the world, in the panel
const SRC_KEY := "minimap_source"
const TOPDOWN_SPAN := 26.0   # cells shown vertically; a corridor reads at about this
const TOPDOWN_H := 60.0      # eye height — well above any wall, so nothing occludes the floor
## WRITE-THROUGH TO Settings, off in tests. The toggle saves, and a headless run that presses it
## puts a fixture's choice into the developer's own settings.json — which this test did, once,
## before this existed. The drone panel has the same flag for the same reason.
var persist := true
var _svc: SubViewportContainer
var _sv: SubViewport
var _tcam: Camera3D
## THE NODE THE ZONE IS DRAWN UNDER, set by MainFrame. The camera lives in the SubViewport, not in
## that subtree, so a cell coordinate is NOT a world coordinate: the renderer carries a z-stretch
## (see ZoneRenderer's `zs`), and placing the camera at a raw cell put it somewhere with nothing in
## it. Everything the map aims at goes through this transform.
var world_ref: Node3D
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
	_map_margin.add_child(_rect)

	# THE TOP-DOWN SOURCE, sharing the game's own World3D exactly as the camera selector's panes do
	# — one world, many cameras. Built here rather than lazily so switching the setting is a
	# visibility flip and not a first-use stall.
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	_svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_svc.visible = false
	_map_margin.add_child(_svc)
	_sv = SubViewport.new()
	# THE WORLD IS BOUND LAZILY, not here. Panels are built before they are in the tree, so
	# get_viewport() at this point can hand back something that is not the game's viewport — and a
	# SubViewport with no world quietly renders its OWN empty one, which looks exactly like a
	# camera pointed at nothing. Bound on first show, when being in the tree is certain.
	_sv.transparent_bg = false
	_svc.add_child(_sv)
	_tcam = Camera3D.new()
	_tcam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_tcam.size = TOPDOWN_SPAN
	# NO FOG FROM ABOVE. The sight area is a lid when seen from overhead — underground it covers the
	# whole zone, so the first version of this showed a dark sheet and nothing else. Dropping its
	# layer leaves exactly what has been built: the geometry you have explored.
	_tcam.cull_mask &= ~ZoneRenderer.DARK_LAYER
	_sv.add_child(_tcam)
	_tcam.current = true

## Swap between the painted texture and the live camera. Both live in _map_margin; exactly one is
## visible, and the viewport stops rendering entirely when it is not — a second camera on the game's
## own world is not something to leave running behind a panel nobody is looking at.
func _show_topdown(on: bool) -> void:
	if _svc == null:
		return
	if on and _sv.world_3d == null:
		var vp := get_viewport()
		if vp != null:
			_sv.world_3d = vp.find_world_3d()
	_svc.visible = on
	_rect.visible = not on
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## Point the top-down camera at the player. NORTH IS THE UP VECTOR, the same one CameraRig hands
## its own top-down mode — a map whose north disagreed with the game's would be worse than no map.
func _aim_topdown(data: Dictionary) -> void:
	if _tcam == null:
		return
	var p: Dictionary = data.get("player", {})
	var px := float(p.get("x", -1))
	var py := float(p.get("y", -1))
	if px < 0.0 or py < 0.0:
		return
	var ground := Vector3(px, 0.0, py)
	var up := Vector3(0, 0, -1)
	if is_instance_valid(world_ref):
		ground = world_ref.global_transform * ground
		# The stretch is on z, so "north" is stretched with it — take the direction through the
		# same basis rather than assuming it survived.
		up = (world_ref.global_transform.basis * Vector3(0, 0, -1)).normalized()
	_tcam.position = ground + Vector3(0, TOPDOWN_H, 0)
	_tcam.look_at(ground, up)


## MainFrame calls this each snapshot with the full data (needs cells + player + zone dims + palette).
func set_snapshot(data: Dictionary) -> void:
	_last_data = data
	var pal: Dictionary = data.get("palette", {})
	if not pal.is_empty():
		_palette = pal
	_tiles.palette = _palette
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
		_rect.custom_minimum_size = Vector2(MAP_W_1TO1, MAP_H_1TO1) if on else Vector2(0, 0)
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
	_show_topdown(src == "topdown")
	_refresh_toggle()   # Options can change this key too; the button must not disagree with it
	if src == "topdown":
		_aim_topdown(data)
		return
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
	var z: Dictionary = data.get("zone", {})
	var w := int(z.get("width", 0))
	var h := int(z.get("height", 0))
	if w <= 0 or h <= 0:
		return
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
const SOURCES := ["full", "minimal", "qud", "topdown"]
const SOURCE_LABEL := {"full": "full", "minimal": "minimal", "qud": "qud", "topdown": "top-down"}

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
