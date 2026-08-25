extends "res://ChargenCardScreen.gd"
const BuildCode := preload("res://BuildCode.gd")

## CHARACTER CREATION — BUILD SUMMARY (docs/new-game-plan.md, slice 1): the hub every chargen
## lane funnels into before embarking. Three panels on the shared card-screen chrome — an
## Attributes band left, the portrait + identity column centre, a Mutations/Cybernetics band
## right — with the Export/Save footer affordances (stubs until the Library slice) and the
## standard nav hint. Layout fractions are FIRST-PASS reads off Daniel's capture
## ("mutated human - build summary.png"); the parity screenshot pass refines them the usual way.
##
## INTERIM DATA, stated plainly: until the pregens/attribute-picker slices land, attributes are
## genotype stat minimums plus the subtype's statBonuses, and the right band lists the subtype's
## own grants (its GetChargenInfo lines, stat-bonus lines dropped since the left panel shows
## them). A pregen build (slice 5) replaces both with exact numbers.

var mode_name := ""
var chartype_title := ""
var genotype_name := ""
var subtype_name := ""
## The Presets lane (slice 5): the chosen pregen's record {name,tile,fg,detail,desc,code}.
## Non-empty flips the panels to the DECODED build — exact attributes and mutations.
var pregen := {}
## Explicit final values from the attributes screen (slice 7), stat -> value. Non-empty wins
## over both the pregen decode and the genotype-minimum interim.
var attributes := {}
## Explicit picks from the mutations screen (slice 7): [{name, count}]. Non-empty wins over
## the subtype grant lines, the way the pregen decode does.
var mutations: Array = []
var _decoded := {}

func _decoded_build() -> Dictionary:
	if not pregen.is_empty() and _decoded.is_empty():
		_decoded = BuildCode.decode(str(pregen.get("code", "")))
	return _decoded

## The Random lane sets this so [R] can respin the build in place (Qud's own "[R] Randomize
## Selection" affordance, which the summary otherwise has nothing to randomize).
signal reroll

func _screen_node_name() -> String: return "SummaryScreen"
func _subtitle() -> String: return ":build summary:"
func _load_items() -> Array: return []
func _next_enabled() -> bool: return true

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
	if not pregen.is_empty():
		out.append({"label": str(pregen.get("name", "")), "current": false,
			"tile": str(pregen.get("tile", ""))})
	elif subtype_name != "":
		out.append({"label": subtype_name, "current": false, "tile": str(_subtype().get("tile", ""))})
	out.append({"label": "Summary", "current": true})
	return out

# ── data ────────────────────────────────────────────────────────────────────────

func _chargen_data() -> Dictionary:
	var path := InputModel.support_dir().path_join("chargen.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _genotype() -> Dictionary:
	for g in _chargen_data().get("genotypes", []):
		if str(g.get("name", "")) == genotype_name:
			return g
	return {}

func _subtype() -> Dictionary:
	for sc in _chargen_data().get("subtypeClasses", []):
		for cat in sc.get("categories", []):
			for st in cat.get("subtypes", []):
				if str(st.get("name", "")) == subtype_name:
					return st
	return {}

## Attribute rows: genotype minimum + this subtype's bonus, in Qud's canonical order.
func _attribute_rows() -> Array:
	var rows: Array = []
	if not attributes.is_empty():
		for st0 in _genotype().get("stats", []):
			var n0 := str(st0.get("name", ""))
			rows.append([n0, int(attributes.get(n0, int(st0.get("min", 10))))])
		return rows
	# a pregen's build code carries the EXACT purchase per stat: final = genotype min + points
	var purchased: Dictionary = _decoded_build().get("attributes", {}) if not pregen.is_empty() else {}
	var bonus := {}
	for b in _subtype().get("statBonuses", []):
		bonus[str(b.get("name", ""))] = int(b.get("bonus", 0))
	for st in _genotype().get("stats", []):
		var n := str(st.get("name", ""))
		if not purchased.is_empty():
			rows.append([n, int(st.get("min", 10)) + int(purchased.get(n, 0))])
		else:
			rows.append([n, int(st.get("min", 10)) + int(bonus.get(n, 0))])
	return rows

## The right band's entries: the subtype's own grant lines, minus plain stat bonuses (the left
## panel already carries those numbers).
func _grant_lines() -> Array:
	if not mutations.is_empty():
		var picked: Array = []
		for m in mutations:
			var nm := str(m.get("name", ""))
			if int(m.get("count", 1)) > 1:
				nm += " x%d" % int(m.get("count", 1))
			picked.append(nm)
		return picked
	# a pregen lists its DECODED mutations — the capture's right panel, exactly
	if not pregen.is_empty():
		var out2: Array = []
		for m in _decoded_build().get("mutations", []):
			var nm := str(m.get("name", ""))
			if int(m.get("count", 1)) > 1:
				nm += " x%d" % int(m.get("count", 1))
			out2.append(nm)
		return out2
	var out: Array = []
	var stats := {}
	for st in _genotype().get("stats", []):
		stats[str(st.get("name", ""))] = true
	for line in _subtype().get("info", []):
		var plain := str(line)
		var is_stat := false
		for n in stats:
			if plain.contains(n):
				is_stat = true
				break
		if not is_stat:
			out.append(plain)
	return out

# ── body ────────────────────────────────────────────────────────────────────────

const SUMMARY_BAND_W := 0.156   # each band rule's width fraction (measured off the capture)

func _unhandled_input(e: InputEvent) -> void:
	if chartype_title == "Random" and e is InputEventKey and e.pressed and not e.echo \
			and e.keycode == KEY_R:
		reroll.emit(); accept_event(); return
	super._unhandled_input(e)

func _build_body(vp: Vector2) -> void:
	_summary_band(vp, 0.345, "Attributes")
	_summary_band(vp, 0.6625, "Mutations" if bool(_genotype().get("isMutant", true)) else "Cybernetics")
	var body_px := UiFont.px(get_viewport(), "body")
	var step := body_px * 1.32
	# attributes, left column
	var y0 := vp.y * 0.532
	var ax := vp.x * 0.298
	var rows := _attribute_rows()
	for i in rows.size():
		var l := _text("%s: %d" % [rows[i][0], rows[i][1]], NAME_SEL, "body")
		l.position = Vector2(ax, y0 + i * step)
		add_child(l)
	# grants, right column (Qud markup honoured)
	var gx := vp.x * 0.615
	var lines := _grant_lines()
	for i in mini(lines.size(), 10):
		var rl := _rich(QudText.to_bbcode(str(lines[i]), _palette), "body")
		rl.position = Vector2(gx, y0 + i * step)
		rl.custom_minimum_size.x = vp.x * 0.24
		add_child(rl)
	# portrait + identity, centre column
	var tile := str(pregen.get("tile", "")) if not pregen.is_empty() else str(_subtype().get("tile", ""))
	if tile != "":
		var icons := _card_icon(tile, subtype_name)
		var tex: Texture2D = icons.get("colored")
		if tex != null:
			var pr := TextureRect.new()
			pr.texture = tex
			pr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pr.stretch_mode = TextureRect.STRETCH_SCALE
			pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var pw := vp.y * 0.052
			pr.size = Vector2(pw, pw * 1.5)
			pr.position = Vector2(vp.x * 0.5 - pw * 0.5, vp.y * 0.502)
			add_child(pr)
	var idy := vp.y * 0.567
	var top_line := str(pregen.get("name", "")) if not pregen.is_empty() else subtype_name
	for line in [top_line, _genotype().get("display", genotype_name), "Humanoid"]:
		var il := _text(str(line), NAME_SEL, "body")
		il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		il.anchor_left = 0.0; il.anchor_right = 1.0
		il.position.y = idy
		add_child(il)
		idy += step
	# the three-dot deco, higher than the card screens put it (capture: ~0.695)
	var ks: int = maxi(3, int(round(vp.y * 0.0046)))
	var dx: int = maxi(2, int(round(vp.x * 0.0047)))
	var dy: int = maxi(1, int(round(vp.y * 0.0037)))
	for off in [Vector2(0, -dy), Vector2(-dx, dy), Vector2(dx, dy)]:
		var k := ColorRect.new()
		k.color = DECO_KNOB
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.position = Vector2(vp.x * 0.5 + off.x - ks * 0.5, vp.y * 0.695 + off.y - ks * 0.5)
		k.size = Vector2(ks, ks)
		add_child(k)
	# footer affordances — stubs until the Library slice wires them
	if chartype_title == "Random":
		var rr := _rich("[center][color=#%s][lb]R[rb][/color][color=#%s] Randomize Selection[/color][/center]" % [
			SEL_GOLD.to_html(false), MUTED.to_html(false)], "body")
		rr.anchor_left = 0.0; rr.anchor_right = 1.0
		rr.position.y = vp.y * 0.86
		add_child(rr)
	var foot := _text("Export Code to Clipboard  Save Build To Library", MUTED, "body")
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.anchor_left = 0.0; foot.anchor_right = 1.0
	foot.position.y = vp.y * 0.899
	add_child(foot)
	# the standard nav hint
	var hint := _rich("", "caption")
	hint.anchor_left = 0.0; hint.anchor_right = 1.0
	hint.position.y = vp.y * 0.965
	var ih := int(round(UiFont.px(get_viewport(), "caption") * 1.15))
	hint.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	var icon := QudChrome.nav_icon(ih, SEL_GOLD)
	hint.add_image(icon, icon.get_width(), icon.get_height())
	hint.append_text("[color=#%s] navigate      [/color][color=#%s][lb]Space[rb][/color][color=#%s] select[/color]" % [
		MUTED.to_html(false), SEL_GOLD.to_html(false), MUTED.to_html(false)])
	hint.pop()
	add_child(hint)

## One dashed band rule with its gold label, |—— label ——| style. First-pass geometry;
## refined against the capture in the parity pass.
func _summary_band(vp: Vector2, cx: float, label: String) -> void:
	var w := vp.x * SUMMARY_BAND_W
	var y := vp.y * 0.508
	var rule_h: int = maxi(1, int(round(vp.y * 0.0019)))
	var lab := _text(label, CC_GOLD, "body")
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.position = Vector2(vp.x * cx - w * 0.5, y - UiFont.px(get_viewport(), "body") * 0.62)
	lab.custom_minimum_size.x = w
	add_child(lab)
	# dashes either side of the label, with end caps
	var lab_w := w * 0.42
	for side in [-1, 1]:
		var seg_x := vp.x * cx + (lab_w * 0.5 if side > 0 else -w * 0.5)
		var seg_w := (w - lab_w) * 0.5
		var xx := seg_x
		while xx < seg_x + seg_w - 2.0:
			var dash := ColorRect.new()
			dash.color = BAND_RULE
			dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dash.position = Vector2(xx, y)
			dash.size = Vector2(maxf(2.0, vp.x * 0.0031), rule_h)
			add_child(dash)
			xx += vp.x * 0.0052
		# end cap: a short vertical tick at the outer end
		var cap := ColorRect.new()
		cap.color = BAND_RULE
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap_x := (seg_x if side < 0 else seg_x + seg_w - 2.0)
		cap.position = Vector2(cap_x, y - rule_h * 2.5)
		cap.size = Vector2(maxf(2.0, vp.x * 0.0016), rule_h * 6.0)
		add_child(cap)
