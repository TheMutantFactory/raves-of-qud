extends RefCounted
# (no class_name: fresh global classes need an editor rescan to resolve; the two users
#  preload this file under the same local name instead, which works everywhere)

## Qud BUILD-CODE decoder (docs/new-game-plan.md slice 5): base64 -> gzip -> JSON, the format
## the pregens (and one day the Library) carry their builds in. Returns a flat, screen-friendly
## dictionary; {} on any failure, so callers degrade to the interim summary data.
##
##   { "genotype": String, "subtype": String,
##     "attributes": {stat: purchased_points},        # final stat = genotype min + purchased
##     "mutations": [{"name": String, "count": int}] }

## ── ENCODE ─────────────────────────────────────────────────────────────────────────
## The mirror of decode(), producing a code Qud itself accepts. The wrapper strings are
## Qud's own, read off a decoded pregen code rather than guessed: module types carry the
## running game's version, so we take `gameversion` from the catalog when we can and fall
## back to the version this format was captured at.
const FALLBACK_GAMEVERSION := "2.0.202.44"

static func _module_type(short_name: String, gamever: String) -> String:
	return "XRL.CharacterBuilds.Qud.%s, Assembly-CSharp, Version=%s, Culture=neutral, PublicKeyToken=null" % [
		short_name, gamever]

static func _data_type(short_name: String) -> String:
	return "XRL.CharacterBuilds.%s, Assembly-CSharp" % short_name

## `build` is the flat dictionary the chargen flow carries:
##   {genotype, subtype, purchased:{stat: points}, ap_spent:int,
##    mutations:[{name,count}], cybernetics:[{blueprint,slot}], lp:int}
static func encode(build: Dictionary, gamever := "") -> String:
	var gv := gamever if gamever != "" else FALLBACK_GAMEVERSION
	var modules: Array = []
	if str(build.get("genotype", "")) != "":
		modules.append({"moduleType": _module_type("QudGenotypeModule", gv),
			"data": {"$type": _data_type("QudGenotypeModuleData"),
				"Genotype": str(build["genotype"]), "version": "1.0.0"}})
	if str(build.get("subtype", "")) != "":
		modules.append({"moduleType": _module_type("QudSubtypeModule", gv),
			"data": {"$type": _data_type("QudSubtypeModuleData"),
				"Subtype": str(build["subtype"]), "version": "1.0.0"}})
	var purchased: Dictionary = build.get("purchased", {})
	if not purchased.is_empty():
		var spent := int(build.get("ap_spent", 0))
		modules.append({"moduleType": _module_type("QudAttributesModule", gv),
			"data": {"$type": _data_type("QudAttributesModuleData"),
				"PointsPurchased": purchased, "apSpent": -spent,
				"apRemaining": int(build.get("ap_remaining", 0)),
				"baseAp": int(build.get("base_ap", spent)), "version": "1.0.0"}})
	var muts: Array = build.get("mutations", [])
	if not muts.is_empty():
		var sel: Array = []
		for m in muts:
			sel.append({"Mutation": str(m.get("name", "")),
				"Count": int(m.get("count", 1)), "Variant": 0})
		modules.append({"moduleType": _module_type("QudMutationsModule", gv),
			"data": {"$type": _data_type("QudMutationsModuleData"),
				"lp": int(build.get("mp_remaining", 0)), "selections": sel, "version": "1.0.0"}})
	var cyb: Array = build.get("cybernetics", [])
	if not cyb.is_empty():
		var csel: Array = []
		for c in cyb:
			csel.append({"Cybernetic": str(c.get("blueprint", "")),
				"Count": 1, "Variant": str(c.get("slot", ""))})
		modules.append({"moduleType": _module_type("QudCyberneticsModule", gv),
			"data": {"$type": _data_type("QudCyberneticsModuleData"),
				"lp": int(build.get("lp", 0)), "selections": csel, "version": "1.0.0"}})
	var doc := {"gameversion": gv, "buildversion": "1.0.0", "modules": modules}
	var raw := JSON.stringify(doc).to_utf8_buffer()
	return Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP))

## The game version the player's own catalog reports, so an exported code matches their
## install rather than the version this format was captured at. "" when unknowable.
static func catalog_gameversion() -> String:
	var path := InputModel.support_dir().path_join("chargen.json")
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return ""
	for pg in parsed.get("pregens", []):
		var code := str(pg.get("code", ""))
		if code == "":
			continue
		var raw := Marshalls.base64_to_raw(code)
		if raw.is_empty():
			continue
		var bytes := raw.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_GZIP)
		if bytes.is_empty():
			continue
		var d: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if d is Dictionary and str(d.get("gameversion", "")) != "":
			return str(d["gameversion"])
	return ""

## ── THE LIBRARY ────────────────────────────────────────────────────────────────────
## Saved builds live beside the other Raves data as build_library.json:
##   [{name, genotype, subtype, code, saved}]
static func library_path() -> String:
	return InputModel.support_dir().path_join("build_library.json")

static func library() -> Array:
	var p := library_path()
	if not FileAccess.file_exists(p):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Array else []

static func library_save(entry: Dictionary) -> void:
	var lib := library()
	lib.append(entry)
	var f := FileAccess.open(library_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(lib, "  "))
		f.close()

static func decode(code: String) -> Dictionary:
	if code.strip_edges() == "":
		return {}
	var raw := Marshalls.base64_to_raw(code.strip_edges())
	if raw.is_empty():
		return {}
	var bytes := raw.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_GZIP)
	if bytes.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {}
	var out := {"genotype": "", "subtype": "", "attributes": {}, "mutations": []}
	for mod in parsed.get("modules", []):
		var data: Variant = mod.get("data")
		if not (data is Dictionary):
			continue
		if data.has("Genotype"):
			out["genotype"] = str(data["Genotype"])
		if data.has("Subtype"):
			out["subtype"] = str(data["Subtype"])
		if data.has("PointsPurchased") and data["PointsPurchased"] is Dictionary:
			out["attributes"] = data["PointsPurchased"]
		if data.has("selections") and data["selections"] is Array:
			for sel in data["selections"]:
				if sel is Dictionary and sel.has("Mutation"):
					out["mutations"].append({"name": str(sel["Mutation"]),
						"count": int(sel.get("Count", 1))})
	return out
