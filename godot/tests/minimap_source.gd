extends Node

## WHICH MAP THE MINIMAP DRAWS — headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/minimap_source.tscn
##
## Daniel: "Let's have a Raves setting for minimap 1:1, or top-down camera." Then, after a camera
## that would not draw: "is it possible to just load the zone tilesets from Qud? That's what I
## would be looking at. No 'camera' needed."
##
## TWO FAILURES ARE UNDER TEST. The first is two controls for one value: the header button used to
## flip a local field that the setting then overwrote on the next snapshot — a button that appears
## to work and undoes itself a moment later. The second is a source that draws NOTHING, which is
## how the top-down camera failed three times while every check around it passed.

var _failed: Array[String] = []

## A STUB TILE SOURCE, so the composite is testable without exported art. Headless, QudTiles
## resolves nothing — tiles_dir points at a support directory the test has no business reading —
## so the real one hands back null for every object and the map is legitimately blank. That is a
## fixture fact, not a defect, and it would have made every check here vacuous.
##
## MAGENTA, because nothing else in this panel is: BG is near-black, the player's mark is white,
## and a colour that could be either proves nothing about which drew.
class FakeTiles:
	extends RefCounted
	var tiles_dir := ""
	var palette := {}
	const ART := Color(1, 0, 1, 1)
	## TRANSPARENT AROUND THE EDGES, like every real tile. A solid stub makes blit and blend
	## indistinguishable, so the check that the background survives around a sprite would pass on
	## code that punches a black box out of the map for every cell.
	## The painted and 1:1 paths ask for COLOURS, not art. Without this the stub throws the moment
	## a check touches any source but "tiles".
	func main_color(_obj: Dictionary, fallback := Color.WHITE) -> Color:
		return fallback
	## image_for, not texture_for: the composite takes PIXELS now, because get_image() per cell was
	## a GPU readback and cost the panel 545ms a turn.
	func image_for(_obj: Dictionary, _full: bool) -> Image:
		var im := Image.create(16, 24, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		for y in range(6, 18):
			for x in range(4, 12):
				im.set_pixel(x, y, ART)
		return im


func _ready() -> void:
	var m = load("res://MinimapView.gd").new()
	# BEFORE add_child, so nothing in _ready can reach the settings file either.
	m.persist = false
	add_child(m)
	m._tiles = FakeTiles.new()
	Settings.set_value(m.SRC_KEY, "full")
	m._refresh_toggle()

	_check("the button shows the live source", m._toggle.text == "full", m._toggle.text)

	# ── the button and the setting are one value ──────────────────────────────
	m._toggle_mode()
	_check("pressing it moves the SETTING, not a local field",
		String(Settings.get_value(m.SRC_KEY, "")) == "minimal",
		String(Settings.get_value(m.SRC_KEY, "")))
	_check("...and the button says so", m._toggle.text == "minimal", m._toggle.text)
	var seen: Array = []
	for i in 4:
		seen.append(String(Settings.get_value(m.SRC_KEY, "")))
		m._toggle_mode()
	seen.sort()
	_check("every source is reachable from the button",
		seen == ["full", "minimal", "qud", "tiles"], str(seen))

	# Options can set it behind the button's back; the button must not disagree.
	Settings.set_value(m.SRC_KEY, "tiles")
	m._last_data = _fixture()
	m._rerender()
	_check("a change made in Options re-letters the button", m._toggle.text == "tiles",
		m._toggle.text)

	# ── the tile map ──────────────────────────────────────────────────────────
	# A composite of Qud's own art, one sprite per cell. It retired a top-down camera that had to
	# be aimed, framed, transformed out of cell space and told which layers to skip — four chances
	# to be wrong, and it drew nothing through three attempts at them.
	_check("the tile map draws into the panel's own texture", m._rect.texture != null)
	_check("...at Qud's art size, one sprite per cell",
		m._rect.texture.get_width() == 4 * m.TILE_W
			and m._rect.texture.get_height() == 3 * m.TILE_H,
		str(m._rect.texture.get_size()))
	# NOT BLANK. An all-background image passes every check above this one, and drawing nothing at
	# all is exactly how the camera failed.
	var im: Image = m._rect.texture.get_image()
	# ASKED OF A CELL THAT IS NOT THE PLAYER'S. "Not empty" over the whole image is satisfied by the
	# player's own marker, so it would pass on a map where no tile art was placed at all — the
	# precise failure this file exists to catch.
	_check("...and a cell with art in it actually has art",
		_has_in(im, FakeTiles.ART, 0, 0, m.TILE_W, m.TILE_H),
		"cell (0,0) holds none of the tile's colour")
	_check("...while an empty cell stays empty",
		_non_bg_in(im, m.BG, 1 * m.TILE_W, 2 * m.TILE_H, m.TILE_W, m.TILE_H) == 0,
		"something was drawn in a cell with no objects")
	_check("the player's cell is marked", _has(im, m.PLAYER), "no player mark")
	# BLENDED, NOT BLITTED. Tile art is mostly transparent; a straight copy would carry that
	# transparency into the map and leave every sprite sitting in its own hole.
	_check("the background survives around a sprite",
		_non_bg_in(im, m.BG, 0, 0, 2, 2) == 0,
		"the corner of a tiled cell is no longer the map's background")

	# THE ART DIRECTORY COMES FROM THE SNAPSHOT. The painted map only asked for colours, which need
	# no directory, so this was never set — and texture_for returns null without it, which drew a
	# blank map in the real game while every check here passed against a stub.
	m._tiles = FakeTiles.new()
	m.set_snapshot({"tilesDir": "/tmp/some/tiles", "palette": {}, "player": {"x": 1, "y": 1},
		"zone": {"width": 4, "height": 3}, "cells": []})
	_check("the tile source is told where the art lives",
		m._tiles.tiles_dir == "/tmp/some/tiles", m._tiles.tiles_dir)

	# ── parity still wins ─────────────────────────────────────────────────────
	Settings.set_value(m.SRC_KEY, "tiles")
	m._one_to_one = true
	m._last_data = _fixture()
	m._rerender()
	# In 1:1 the map is Qud's, so it is one pixel per cell (row-doubled) — emphatically not the
	# tile composite, which is a Raves surface.
	_check("1:1 overrides the setting", m._rect.texture.get_width() != 4 * m.TILE_W,
		str(m._rect.texture.get_size()))

	# ── zoom, pan, and the resize strip ───────────────────────────────────────
	# Daniel: "make the minimap bottom border draggable, to make more room ... add scroll-zoom to
	# the minimap, as well as a pan/drag." The widgets are three lines each; all of the ways this
	# goes wrong are in the arithmetic, so that is what is tested.
	var M = load("res://MinimapView.gd")

	# ZOOM IS MULTIPLICATIVE, so a notch means the same PROPORTION at every zoom. An additive step
	# crawls when you are close in and leaps when you are far out.
	_check("a notch zooms in", M.zoom_step(1.0, 1.0) > 1.0)
	_check("...and the step is proportional, not fixed",
		absf((M.zoom_step(2.0, 1.0) - 2.0) - 2.0 * (M.zoom_step(1.0, 1.0) - 1.0)) < 0.001,
		"%f vs %f" % [M.zoom_step(2.0, 1.0) - 2.0, M.zoom_step(1.0, 1.0) - 1.0])
	_check("it cannot zoom out past fit", is_equal_approx(M.zoom_step(1.0, -20.0), M.ZOOM_MIN))
	_check("...nor in past the ceiling", is_equal_approx(M.zoom_step(1.0, 99.0), M.ZOOM_MAX))
	# A round trip returns exactly, so wheeling back and forth does not drift the view.
	_check("in then out returns to where it was",
		is_equal_approx(M.zoom_step(M.zoom_step(2.0, 1.0), -1.0), 2.0))

	# PAN IS CLAMPED so the map always covers the view. Without this you can throw it off the edge
	# and be left looking at an empty panel with no way back.
	var view := Vector2(300, 120)
	var big := Vector2(900, 360)
	_check("the map cannot be dragged off to the right",
		M.clamp_pan(Vector2(500, 0), big, view).x <= 0.0,
		str(M.clamp_pan(Vector2(500, 0), big, view)))
	_check("...nor off to the left",
		M.clamp_pan(Vector2(-5000, 0), big, view).x >= view.x - big.x,
		str(M.clamp_pan(Vector2(-5000, 0), big, view)))
	# ...and a map SMALLER than the view is centred, because there is nothing to pan to.
	var small := Vector2(100, 40)
	var c: Vector2 = M.clamp_pan(Vector2(999, -999), small, view)
	_check("a map smaller than its box is centred, not pinned to a corner",
		is_equal_approx(c.x, (view.x - small.x) * 0.5) and is_equal_approx(c.y, (view.y - small.y) * 0.5),
		str(c))

	# ZOOM HOLDS THE POINT UNDER THE CURSOR. Zooming about the CENTRE is what everyone writes
	# first, and it walks the thing you are closing in on off the screen.
	var focus := Vector2(200, 50)
	var pan0 := Vector2(-40, -10)
	var pan1: Vector2 = M.zoom_about(pan0, focus, 1.0, 2.0)
	# The texture point under `focus` before must still be under `focus` after.
	var before := (focus - pan0) / 1.0
	var after := (focus - pan1) / 2.0
	_check("the cell under the cursor stays under the cursor",
		before.is_equal_approx(after), "%s vs %s" % [before, after])
	_check("...and zooming by nothing moves nothing",
		M.zoom_about(pan0, focus, 2.0, 2.0).is_equal_approx(pan0))

	# THE RESIZE STRIP is bounded at both ends: dragged to nothing it would vanish with no way to
	# get it back, and unbounded it would push the whole side column off the screen.
	_check("the panel has a draggable bottom border", m._grab != null)
	_check("...and it is the only thing wearing the resize cursor",
		m._grab.mouse_default_cursor_shape == Control.CURSOR_VSIZE)
	m._map_h = 10000.0
	m._map_h = clampf(m._map_h, M.MAP_H_MIN, M.MAP_H_MAX)
	_check("the map cannot be dragged taller than the ceiling", m._map_h <= M.MAP_H_MAX)
	m._map_h = clampf(-500.0, M.MAP_H_MIN, M.MAP_H_MAX)
	_check("...nor shrunk to nothing", m._map_h >= M.MAP_H_MIN)

	# 1:1 has none of it: Qud's sidebar map does not zoom, pan or resize.
	m._zoom = 3.0
	m._pan = Vector2(50, 50)
	# FROM USER MODE, deliberately: set_one_to_one returns early when the mode has not changed, and
	# an earlier check above left this panel in 1:1 — so calling it again proved nothing.
	m._one_to_one = false
	m.set_one_to_one(true)
	# ZOOM RETURNS TO FIT and the user's offset is dropped. The pan does NOT come back as zero:
	# _layout_map runs on the way out and CENTRES content narrower than its box, which is the
	# correct resting place — asserting ZERO here was asserting my first guess at the arithmetic
	# rather than the behaviour.
	_check("parity resets the zoom to fit", is_equal_approx(m._zoom, 1.0), str(m._zoom))
	_check("...and drops the pan the user had set", m._pan != Vector2(50, 50), str(m._pan))
	_check("...and takes the resize handle away", not m._grab.visible)

	# ── the pan tool, the centre button, and clicking tiles ───────────────────
	# Daniel: "add a pan icon to the minimap tiles titlebar. While the pan tool is enabled, the
	# minimap pans ... Now that the clicks are free when the pan tool is disabled, let's add the
	# ability to left and right click tiles on the minimap, just like the playfield."
	m._one_to_one = false
	m.set_one_to_one(false)
	Settings.set_value(m.SRC_KEY, "tiles")
	m._last_data = _fixture()
	m._rerender()
	m._view.size = Vector2(4 * m.TILE_W, 3 * m.TILE_H)
	m._zoom = 1.0
	m._pan = Vector2.ZERO
	m._layout_map()

	_check("the titlebar has a pan tool", m._pan_btn != null)
	_check("...and a centre button", m._center_btn != null)

	# A CLICK IS A CELL. The inverse of the layout, which is the only reason a click on the map can
	# mean a tile — get it wrong and every click acts on the wrong square, silently.
	var mid: Vector2 = m._rect.position + Vector2(2.5 * m.TILE_W, 1.5 * m.TILE_H) * (m._rect.size / m._rect.texture.get_size())
	_check("a click resolves to the cell under it", m.cell_at(mid) == Vector2i(2, 1),
		str(m.cell_at(mid)))
	_check("a click outside the map resolves to nothing",
		m.cell_at(Vector2(-50, -50)) == Vector2i(-1, -1), str(m.cell_at(Vector2(-50, -50))))

	# THE CLICKS REACH THE WORLD when the pan tool is off...
	var travelled: Array = []
	var interacted: Array = []
	m.tile_travel.connect(func(c: Vector2i) -> void: travelled.append(c))
	m.tile_interact.connect(func(c: Vector2i) -> void: interacted.append(c))
	m._set_pan_tool(false)
	_click(m, mid, MOUSE_BUTTON_LEFT)
	_check("left click orders travel to that cell", travelled == [Vector2i(2, 1)], str(travelled))
	_click(m, mid, MOUSE_BUTTON_RIGHT)
	_check("right click interacts with that cell", interacted == [Vector2i(2, 1)], str(interacted))

	# ...AND DO NOT while it is on. This is the whole point of the tool being a mode: a drag and a
	# click are the same gesture at different speeds, so one of them has to be claimed explicitly.
	travelled.clear()
	m._set_pan_tool(true)
	_click(m, mid, MOUSE_BUTTON_LEFT)
	_check("with the pan tool on, a click does not order a walk", travelled.is_empty(),
		str(travelled))

	# A DRAG IS NOT A CLICK, even with the tool off — a sloppy press must not walk you somewhere.
	travelled.clear()
	m._set_pan_tool(false)
	# THE RELEASE MUST LAND ON A REAL CELL, one cell over — released off the map there is nothing
	# to emit either way, and the check passes without testing anything. (It did: removing the
	# click-versus-drag rule left this green until the endpoint was brought back on to the map.)
	var one_cell: Vector2 = Vector2(m.TILE_W, 0) * (m._rect.size / m._rect.texture.get_size())
	_check("the drag's endpoint is on the map", m.cell_at(mid + one_cell).x >= 0,
		str(m.cell_at(mid + one_cell)))
	_drag_click(m, mid, mid + one_cell)
	_check("a drag is not treated as a click", travelled.is_empty(), str(travelled))

	# THE CENTRE BUTTON puts the player in the middle of the box.
	m._zoom = 3.0
	m._pan = Vector2(-500, -500)
	m._layout_map()
	var sc0: Vector2 = m._rect.size / m._rect.texture.get_size()
	var before_d: float = (m._rect.position + Vector2(1.5 * m.TILE_W, 1.5 * m.TILE_H) * sc0) \
		.distance_to(m._view.size * 0.5)
	m.center_on_player()
	var sc: Vector2 = m._rect.size / m._rect.texture.get_size()
	var player_on_map: Vector2 = m._rect.position + Vector2(1.5 * m.TILE_W, 1.5 * m.TILE_H) * sc
	var after_d: float = player_on_map.distance_to(m._view.size * 0.5)
	# AS CENTRED AS THE CLAMP ALLOWS, which is the honest claim. A player near a zone edge CANNOT
	# sit in the middle without the map pulling away from its own border and showing empty margin,
	# and clamp_pan rightly refuses that — asserting dead-centre here was asserting a behaviour the
	# pan rules forbid, not one the button owes.
	_check("centre brings the player toward the middle", after_d < before_d,
		"%.0f -> %.0f" % [before_d, after_d])
	_check("...and lands dead centre when the map has the room, or against its edge",
		after_d < 1.0 or is_equal_approx(m._rect.position.x, 0.0)
			or is_equal_approx(m._rect.position.y, 0.0)
			or is_equal_approx(m._rect.position.x, m._view.size.x - m._rect.size.x)
			or is_equal_approx(m._rect.position.y, m._view.size.y - m._rect.size.y),
		"player %.0fpx off centre with the map at %s" % [after_d, m._rect.position])

	# ── the zoom is remembered ────────────────────────────────────────────────
	# Daniel: "Can we make the minimap tiles zoom be a user setting? I'd like it to stay from
	# session to session."
	Settings.set_value(m.ZOOM_KEY, 1.0)
	m._zoom = 1.0
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(10, 10)
	m._on_map_input(wheel)
	_check("a wheel notch writes the zoom setting",
		float(Settings.get_value(m.ZOOM_KEY, 0.0)) > 1.0,
		str(Settings.get_value(m.ZOOM_KEY, 0.0)))
	_check("...and it is the zoom the map is at",
		is_equal_approx(float(Settings.get_value(m.ZOOM_KEY, 0.0)), m._zoom))

	# CLAMPED ON LOAD. A saved zoom outlives the code that wrote it, and an out-of-range value
	# would otherwise restore a map you cannot get back from.
	Settings.set_value(m.ZOOM_KEY, 999.0)
	var m2 = load("res://MinimapView.gd").new()
	m2.persist = false
	add_child(m2)
	_check("a saved zoom past the ceiling loads clamped", m2._zoom <= m2.ZOOM_MAX, str(m2._zoom))
	Settings.set_value(m.ZOOM_KEY, -5.0)
	var m3 = load("res://MinimapView.gd").new()
	m3.persist = false
	add_child(m3)
	_check("...and one below the floor too", m3._zoom >= m3.ZOOM_MIN, str(m3._zoom))
	Settings.set_value(m.ZOOM_KEY, 2.5)
	var m4 = load("res://MinimapView.gd").new()
	m4.persist = false
	add_child(m4)
	_check("a legal saved zoom is restored as-is", is_equal_approx(m4._zoom, 2.5), str(m4._zoom))

	# ── follow mode ───────────────────────────────────────────────────────────
	# Daniel: "When the user clicks on the 'center on character' button, this should be a toggle
	# that then makes the minimap update to center on character whenever the character moves."
	m._set_pan_tool(false)
	m._set_follow(false)
	# NO SIZE SET HERE. _view.size is container-managed: assigning it is overwritten, and the
	# earlier attempts to pin it were fighting Godot's layout rather than testing anything. The
	# checks below use whatever box the panel has and a zone big enough to pan inside it.
	m._zoom = 3.0
	m._layout_map()

	# WITH FOLLOW OFF the map stays where it was put, even as the player moves.
	m._pan = Vector2(-40, -30)
	m._layout_map()
	var parked: Vector2 = m._rect.position
	m._last_data = _fixture_at(34, 16)
	m._rerender()
	_check("with follow off, walking does not move the map",
		m._rect.position.is_equal_approx(parked), "%s -> %s" % [parked, m._rect.position])

	# WITH IT ON, every snapshot re-centres.
	# NO HEADLESS CHECK FOR "A RENDER RE-CENTRES", deliberately. Every version I wrote compared
	# two map positions through clamp_pan, and at the zoom and box size this fixture ends up with,
	# the centred position sits ON the clamp boundary — so a shoved map and a followed map land in
	# the same place and the check passes whether or not following happens at all. Mutating it
	# proved that: deleting the re-centre left the check green.
	#
	# The two checks around it DO bite (switching on centres; dragging stops following), and the
	# per-turn behaviour is verified in the app instead. A green check that cannot fail is worse
	# than no check, because it is read as coverage.

	# SWITCHING IT ON CENTRES AT ONCE — otherwise the toggle reads "on" while showing somewhere
	# else until the next turn happens to arrive.
	m._set_follow(false)
	m._pan = Vector2(-400, -400)
	m._layout_map()
	var before_on: Vector2 = m._rect.position
	m._set_follow(true)
	_check("switching follow on centres immediately",
		not m._rect.position.is_equal_approx(before_on), str(m._rect.position))

	# ...AND A DRAG TAKES THE WHEEL BACK. With follow on, the next snapshot would undo the drag —
	# the map would fight the hand holding it.
	m._set_pan_tool(true)
	m._set_follow(true)
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.position = Vector2(20, 20)
	m._on_map_input(dn)
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(60, 20)
	m._on_map_input(mv)
	_check("dragging the map stops it following", not m._follow)
	_check("...and the button says so", not m._center_btn.button_pressed)

	_report()


## A ZONE BIG ENOUGH TO PAN INSIDE, with the player somewhere specific.
##
## The 4x3 fixture cannot answer "did the map follow him": at any useful zoom its content is barely
## larger than the box, so clamp_pan pins every position to the same corner and two different
## players give the same answer — for correct reasons that say nothing about following.
func _fixture_at(px: int, py: int) -> Dictionary:
	var cells: Array = []
	for y in 20:
		for x in 40:
			cells.append({"x": x, "y": y,
				"objs": [{"tile": "Terrain/sw_wall.bmp", "color": "&y", "wall": true}]})
	return {"player": {"x": px, "y": py}, "zone": {"width": 40, "height": 20}, "cells": cells}


## A press and release at one spot — a click.
func _click(m, at: Vector2, btn: int) -> void:
	var d := InputEventMouseButton.new()
	d.button_index = btn
	d.pressed = true
	d.position = at
	m._on_map_input(d)
	var u := InputEventMouseButton.new()
	u.button_index = btn
	u.pressed = false
	u.position = at
	m._on_map_input(u)


## Press here, release there — a drag.
func _drag_click(m, from: Vector2, to: Vector2) -> void:
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = from
	m._on_map_input(d)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = to
	m._on_map_input(u)


## A tiny zone with something in three of its cells, so the composite has art to place.
func _fixture() -> Dictionary:
	return {
		"player": {"x": 1, "y": 1},
		"zone": {"width": 4, "height": 3},
		"cells": [
			{"x": 0, "y": 0, "objs": [{"tile": "Terrain/sw_wall.bmp", "color": "&y", "wall": true}]},
			{"x": 2, "y": 1, "objs": [{"tile": "Terrain/sw_wall.bmp", "color": "&c", "wall": true}]},
			{"x": 3, "y": 2, "objs": [{"tile": "Terrain/sw_wall.bmp", "color": "&r", "wall": true}]},
		],
	}


## WITH A TOLERANCE, and that is not fussiness. BG is a float colour and the image is RGBA8, so
## 0.05 stores as 13/255 = 0.0510 and is_equal_approx calls every single pixel different — which
## made "the map is not empty" true of a blank image and "an empty cell is empty" false of one.
## Both checks passed or failed for a reason that had nothing to do with the map.
const NEAR := 0.03

static func _non_bg_in(im: Image, bg: Color, x0: int, y0: int, w: int, h: int) -> int:
	var n := 0
	for y in range(y0, mini(y0 + h, im.get_height())):
		for x in range(x0, mini(x0 + w, im.get_width())):
			var c := im.get_pixel(x, y)
			if absf(c.r - bg.r) > NEAR or absf(c.g - bg.g) > NEAR or absf(c.b - bg.b) > NEAR:
				n += 1
	return n


static func _has_in(im: Image, c: Color, x0: int, y0: int, w: int, h: int) -> bool:
	for y in range(y0, mini(y0 + h, im.get_height())):
		for x in range(x0, mini(x0 + w, im.get_width())):
			var p := im.get_pixel(x, y)
			if absf(p.r - c.r) <= NEAR and absf(p.g - c.g) <= NEAR and absf(p.b - c.b) <= NEAR:
				return true
	return false


static func _has(im: Image, c: Color) -> bool:
	for y in im.get_height():
		for x in im.get_width():
			var p := im.get_pixel(x, y)
			if absf(p.r - c.r) <= NEAR and absf(p.g - c.g) <= NEAR and absf(p.b - c.b) <= NEAR:
				return true
	return false


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
