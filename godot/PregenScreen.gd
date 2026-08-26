extends "res://ChargenCardScreen.gd"

## CHARACTER CREATION — CHOOSE PRESET (docs/new-game-plan.md slice 5, Qud's "Pregens" window):
## the card carousel of prebuilt characters for the chosen genotype, portrait cards in each
## pregen's own detail colour, the description below. Selecting one hands the SUMMARY its
## decoded build (exact attributes + mutations from the build code), and the embark goes
## through the driver's existing Pregen path.

var mode_name := ""
var genotype_name := ""
## Tutorial (slice 9): show ONLY this pregen, so the lane's forced choice is visible and
## confirmable rather than skipped past. Empty = the whole genotype's roster.

var _detail_by_name := {}
var _tile_by_name := {}
var _by_name := {}

func _screen_node_name() -> String: return "PregenScreen"
func _subtitle() -> String: return ":choose preset:"

func _breadcrumb_crumbs() -> Array:
	var out: Array = []
	if mode_name != "":
		out.append({"label": mode_name, "current": false,
			"tile": _chargen_tile("gameModes", mode_name)})
	out.append({"label": "Presets", "current": false})
	if genotype_name != "":
		out.append({"label": genotype_name, "current": false,
			"tile": _chargen_tile("genotypes", genotype_name)})
	out.append({"label": "Pregens", "current": true})
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
	for pg in parsed.get("pregens", []):
		if genotype_name != "" and str(pg.get("genotype", "")) != genotype_name:
			continue
		var nm := str(pg.get("name", ""))
		out.append({"name": nm, "display": nm,
			"hotkey": hotkeys[out.size() % hotkeys.length()],
			"tile": str(pg.get("tile", "")), "desc": str(pg.get("desc", ""))})
		_detail_by_name[nm] = str(pg.get("detail", ""))
		_tile_by_name[str(pg.get("tile", ""))] = nm
		_by_name[nm] = pg
	return out

## The pregen's own record (tile/fg/detail/code), for the summary hand-off.
func pregen(nm: String) -> Dictionary:
	return _by_name.get(nm, {})

## Selected card in the pregen's own detail colour, resting cards two-tone — the caste recipe.
func _card_icon(tile: String, item_name: String) -> Dictionary:
	var neutral := _recolor_tile(tile, ICON_MAIN, ICON_DETAIL)
	var code := str(_detail_by_name.get(_tile_by_name.get(tile, item_name), ""))
	if code == "" or not QUD_COLORS.has(code):
		return {"colored": neutral, "neutral": neutral}
	return {"colored": _recolor_tile(tile, ICON_MAIN, QUD_COLORS[code]), "neutral": neutral}
