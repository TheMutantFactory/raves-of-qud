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
