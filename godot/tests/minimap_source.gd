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
	func texture_for(_obj: Dictionary, _full: bool) -> Texture2D:
		var im := Image.create(16, 24, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		for y in range(6, 18):
			for x in range(4, 12):
				im.set_pixel(x, y, ART)
		return ImageTexture.create_from_image(im)


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

	_report()


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
