extends "res://ChargenCardScreen.gd"

## CHARACTER CREATION — CHOOSE STARTING LOCATION (docs/new-game-plan.md slice 2). The same card
## carousel as every stage, with each card's icon a composited 5x3 world-map tile GRID from the
## startingLocations export (mod ChargenExporter reads EmbarkModules.xml from the player's own
## install). Selecting a card hands its id to the embark spec's `start`, which the mod's
## QudChooseStartingLocationModuleData already honours. Tutorial-set locations are excluded —
## they belong to the Tutorial lane (slice 9).

var mode_name := ""
var chartype_title := ""
var genotype_name := ""
var subtype_name := ""
## Tutorial (slice 9): show only locations in this Set — "Tutorial" surfaces the sunken
## caravanserai the normal lane hides. Empty = the ordinary, non-Tutorial roster.
var force_set := ""

var _grids := {}    # item name -> grid array, stashed by _load_items for _card_icon

func _screen_node_name() -> String: return "LocationScreen"
func _subtitle() -> String: return ":choose starting location:"
## The map cards are wider than the figure cards (Qud draws them ~180px at 1920): 5 map tiles
## across, plus the dashed frame's breathing room.
func _card_w_frac() -> float: return 0.094
func _card_gap_frac() -> float: return 0.020
## ROW-PROFILED (parity_rows.py): Qud's location cards ink from 0.4843 at 1920x1080 —
## HIGHER than the figure-card screens' shared 0.483 lands them, because these cards are
## twice as tall and Qud lifts the row to keep the description beneath it in place. The
## chrome above (emblem, title, subtitle) needs no override; it measured within 1px.
func _y_cards() -> float: return 0.4655

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
	out.append({"label": "Location", "current": true})
	return out

func _load_items() -> Array:
	var path := InputModel.support_dir().path_join("chargen.json")
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return []
	var out: Array = []
	var hotkeys := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for loc in parsed.get("startingLocations", []):
		if force_set != "":
			if str(loc.get("set", "")) != force_set:
				continue
		elif str(loc.get("set", "")) == "Tutorial":
			continue   # the Tutorial lane's forced start, never offered here (Qud hides it too)
		var disp := QudText.strip(str(loc.get("display", loc.get("id", ""))))
		# `tile` is a SENTINEL: _resolve_icons skips empty tiles entirely, and our icons come
		# from the stashed grid, not from any single tile — any non-empty string unlocks the
		# _card_icon call, which ignores it.
		out.append({"name": str(loc.get("id", "")), "display": disp,
			"hotkey": hotkeys[out.size() % hotkeys.length()],
			"tile": "grid:" + str(loc.get("id", "")), "desc": str(loc.get("desc", ""))})
		_grids[str(loc.get("id", ""))] = loc.get("grid", [])
	return out

## Composite the location's 5x3 world-map grid into one card icon. `colored` renders each tile
## in its own fg colour; `neutral` is the same picture dimmed — the resting cards on Qud's
## capture keep their map colours, just quieter.
func _card_icon(_tile: String, item_name: String) -> Dictionary:
	var grid: Array = _grids.get(item_name, [])
	if grid.is_empty():
		return {"colored": null, "neutral": null}
	var cell := 16
	var img := Image.create(cell * 5, cell * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for g in grid:
		var pos := str(g.get("pos", ""))
		if pos.length() < 2:
			continue
		var cx := int(pos.substr(0, 1))
		var cy := int(pos.substr(1, 1))
		var fg := str(g.get("fg", "y"))
		var det := str(g.get("detail", ""))
		var main: Color = QUD_COLORS.get(fg, QUD_COLORS["y"])
		var detail: Color = QUD_COLORS.get(det, Color(0.05, 0.13, 0.13)) if det != "" \
			else Color(0.05, 0.13, 0.13)
		var t := _recolor_tile(str(g.get("tile", "")), main, detail)
		if t == null:
			continue
		var ti := t.get_image()
		if ti.get_width() != cell:
			ti.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		img.blit_rect(ti, Rect2i(0, 0, cell, cell), Vector2i(cx * cell, cy * cell))
	var colored := ImageTexture.create_from_image(img)
	var dim := img.duplicate()
	for y in dim.get_height():
		for x in dim.get_width():
			var px: Color = dim.get_pixel(x, y)
			dim.set_pixel(x, y, Color(px.r * 0.45, px.g * 0.45, px.b * 0.45, px.a))
	return {"colored": colored, "neutral": ImageTexture.create_from_image(dim)}
