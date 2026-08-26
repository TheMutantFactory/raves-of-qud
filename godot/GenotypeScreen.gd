extends "res://ChargenCardScreen.gd"

## CHARACTER CREATION — GENOTYPE (Qud's ":choose genotype:"). Same card-row template as the game-mode
## screen — two cards, Mutated Human / True Kin — reused for both the tutorial and normal chargen.
##
## Set `crumbs` before adding to the tree to control the top-left breadcrumb (e.g. the tutorial trail
## Tutorial → Choose Genotype → Pregens); left unset it shows just "Choose Genotype".

## Optional breadcrumb override — [{label, current}], left→right. Empty = the default trail.
var crumbs: Array = []

## The game mode already chosen ("Classic"…), so the breadcrumb can show the trail rather than just
## this screen. Qud's genotype breadcrumb reads "Classic | New | Choose Genotype" — captured, not
## assumed. Empty (e.g. entering the flow mid-way) simply drops the crumb.
var mode_name := ""

## The chartype leg of the trail ("New"), now that Raves HAS that screen. Empty = not shown, so
## a flow entered mid-way still never claims a choice the player did not make.
var chartype_title := ""

## Fallback genotypes (perk bullets verbatim from Qud), used until chargen.json is slurped.
const GENOTYPES := [
	{"name": "Mutated Human", "hotkey": "A", "extraInfo": ["Mutations", "Moderate starting attributes", "-600 reputation with the {{playerReputation|Putus Templar}}"]},
	{"name": "True Kin", "hotkey": "B", "extraInfo": ["Cybernetics", "High starting attributes", "+600 reputation with the {{playerReputation|Putus Templar}}"]},
]

func _screen_node_name() -> String: return "GenotypeScreen"
func _subtitle() -> String: return ":choose genotype:"
func _default_index() -> int: return 0   # Mutated Human

## THE TUTORIAL'S GENOTYPE IS FIXED. Set this to the one genotype the lane can actually deliver
## and every other card is SHOWN BUT REFUSED — the warning under the row, and the red X on the
## confirm. Deliberately not PregenScreen's `force_name`, which filters its list down to one: the
## player came to this screen to choose, so the card they cannot have is worth showing with a
## reason attached. Empty (normal chargen) blocks nothing.
##
## It matters because the tutorial's pick was already being ignored: _on_tutorial_genotype takes
## whatever was chosen and then forces the Marsh Taur pregen regardless, so picking True Kin
## handed the player a mutated human without a word about it.
var forced_name := ""

func _card_blocked(item_name: String) -> String:
	if forced_name == "" or item_name == forced_name:
		return ""
	# Daniel's wording, verbatim. It names True Kin outright because True Kin is the only card
	# this lane refuses — keep it in step with `forced_name` if a third genotype ever appears.
	return "Mom says you can't do the tutorial with a True Kin"

## Qud: "Classic | New | Choose Genotype". The "New" leg comes from the chartype screen the
## player actually passed through (ChartypeScreen, 2026-08-10) — still never faked: entering
## the flow mid-way leaves `chartype_title` empty and the crumb absent.
func _breadcrumb_crumbs() -> Array:
	if not crumbs.is_empty():
		return crumbs
	var out: Array = []
	if mode_name != "":
		out.append({"label": mode_name, "current": false,
			"tile": _chargen_tile("gameModes", mode_name)})
	if chartype_title != "":
		out.append({"label": chartype_title, "current": false})
	out.append({"label": "Choose Genotype", "current": true})
	return out

func _load_items() -> Array:
	var raw := _load_genotypes()
	var out: Array = []
	var keys := ["A", "B", "C", "D", "E"]
	for i in range(raw.size()):
		var g: Dictionary = raw[i]
		var extra: Array = g.get("extraInfo", [])
		var lines := PackedStringArray()
		for x in extra:
			lines.append("· " + str(x))
		out.append({
			"name": str(g.get("name", "?")),
			"display": str(g.get("display", g.get("name", "?"))),
			"hotkey": g.get("hotkey", keys[i] if i < keys.size() else ""),
			"tile": str(g.get("tile", "")),
			"desc": "\n".join(lines),
		})
	return out

func _load_genotypes() -> Array:
	var path := InputModel.support_dir().path_join("chargen.json")
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary and data.get("genotypes", null) is Array and not data["genotypes"].is_empty():
				return data["genotypes"]
	return GENOTYPES.duplicate(true)

## Qud renders the genotype card icons the same neutral grey-teal as the mode icons (Mutated Human
## selected measures ~rgb(156,182,182)), brightness for selection — so the base default two-tone
## recolour is exactly right, and this screen doesn't override _card_icon.
