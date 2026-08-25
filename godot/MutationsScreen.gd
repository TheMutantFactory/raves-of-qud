extends "res://ChargenCardScreen.gd"

## CHARACTER CREATION — MUTATIONS (docs/new-game-plan.md slice 7a): the mutant point-buy. Two
## columns — the catalog (grouped by Qud's own categories) and the current selections — with
## the mutation's description below and the point pool in the footer. Space toggles a mutation
## (or buys another rank of a multi-rank one), Up/Down walk the catalog, Left/Right switch
## column, [Delete] resets, [9] advances.
##
## DEFECTS GIVE points back (their cost is negative in Qud's data), which is the whole reason
## the pool can exceed the genotype's mutationPoints. Exclusions are honoured as Qud states
## them: a mutation whose Exclusions name a chosen class cannot be taken alongside it.

signal chose_mutations(picks: Array, spent: int)

var mode_name := ""
var chartype_title := ""
var genotype_name := ""
var subtype_name := ""

var _cat: Array = []              # [{name, entries: [idx,...]}] in catalog order
var _all: Array = []              # every mutation record
var _rows: Array = []             # flattened display rows: {kind: "cat"|"mut", text, idx}
var _row := 0
var _picks := {}                  # mutation name -> rank count
var _points := 0
var _base_points := 0
var _list_lbl: RichTextLabel = null
var _pick_lbl: RichTextLabel = null
var _desc_lbl: RichTextLabel = null
var _foot: RichTextLabel = null
## Rows the catalog column shows at once. Sized so the list cannot run into the description
## beneath it: 12 rows at the body size clears 0.475 -> ~0.76 of viewport height.
const VISIBLE_ROWS := 12

func _screen_node_name() -> String: return "MutationsScreen"
func _subtitle() -> String: return ":choose mutations:"
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
	if subtype_name != "":
		out.append({"label": subtype_name, "current": false})
	out.append({"label": "Mutations", "current": true})
	return out

func _chargen() -> Dictionary:
	var path := InputModel.support_dir().path_join("chargen.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _build_body(vp: Vector2) -> void:
	var d := _chargen()
	for g in d.get("genotypes", []):
		if str(g.get("name", "")) == genotype_name:
			_base_points = int(g.get("mutationPoints", 12))
	_points = _base_points
	_all = d.get("mutations", [])
	# group into Qud's categories, in first-seen order
	var order: Array = []
	var by_cat := {}
	for i in _all.size():
		var c := str(_all[i].get("category", ""))
		if not by_cat.has(c):
			by_cat[c] = []
			order.append(c)
		by_cat[c].append(i)
	for c in order:
		_cat.append({"name": c, "entries": by_cat[c]})
	_rebuild_rows()
	_list_lbl = _rich("", "body")
	_list_lbl.position = Vector2(vp.x * 0.215, vp.y * 0.475)
	_list_lbl.size = Vector2(vp.x * 0.30, vp.y * 0.36)
	_list_lbl.custom_minimum_size = _list_lbl.size
	add_child(_list_lbl)
	_pick_lbl = _rich("", "body")
	_pick_lbl.position = Vector2(vp.x * 0.565, vp.y * 0.475)
	_pick_lbl.size = Vector2(vp.x * 0.25, vp.y * 0.36)
	_pick_lbl.custom_minimum_size = _pick_lbl.size
	add_child(_pick_lbl)
	_desc_lbl = _rich("", "body")
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.position = Vector2(vp.x * 0.215, vp.y * 0.80)
	_desc_lbl.size = Vector2(vp.x * 0.57, vp.y * 0.11)
	_desc_lbl.custom_minimum_size = _desc_lbl.size
	add_child(_desc_lbl)
	_foot = _rich("", "body")
	_foot.anchor_left = 0.0; _foot.anchor_right = 1.0
	_foot.position.y = vp.y * 0.905
	add_child(_foot)
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
	_refresh()

func _rebuild_rows() -> void:
	_rows.clear()
	for c in _cat:
		_rows.append({"kind": "cat", "text": str(c["name"]), "idx": -1})
		for i in c["entries"]:
			_rows.append({"kind": "mut", "text": str(_all[i].get("name", "")), "idx": int(i)})
	# start on the first selectable row
	if _row == 0:
		for i in _rows.size():
			if str(_rows[i]["kind"]) == "mut":
				_row = i
				break

func _cur() -> Dictionary:
	if _row < 0 or _row >= _rows.size():
		return {}
	var r: Dictionary = _rows[_row]
	if str(r["kind"]) != "mut":
		return {}
	return _all[int(r["idx"])]

## Is `m` blocked by something already chosen (or does something chosen exclude it)?
func _excluded(m: Dictionary) -> bool:
	var ex := str(m.get("exclusions", ""))
	for nm in _picks:
		if ex != "" and ex.contains(str(nm)):
			return true
		for o in _all:
			if str(o.get("name", "")) == str(nm) and str(o.get("exclusions", "")).contains(str(m.get("name", ""))):
				return true
	return false

func _toggle() -> void:
	var m := _cur()
	if m.is_empty():
		return
	var nm := str(m.get("name", ""))
	var cost := int(m.get("cost", 0))
	var have := int(_picks.get(nm, 0))
	var maxlv := maxi(1, int(m.get("maxLevel", 1)))
	if have >= maxlv:
		# fully bought: clicking again refunds the whole stack (Qud's toggle-off)
		_points += cost * have
		_picks.erase(nm)
		_refresh()
		return
	if have == 0 and _excluded(m):
		_refresh()
		return
	if cost > _points:
		_refresh()
		return
	_picks[nm] = have + 1
	_points -= cost
	_refresh()

func _reset() -> void:
	_picks.clear()
	_points = _base_points
	_refresh()

func _refresh() -> void:
	# the catalog column, windowed around the cursor
	var lo: int = clampi(_row - VISIBLE_ROWS / 2, 0, maxi(0, _rows.size() - VISIBLE_ROWS))
	var hi: int = mini(lo + VISIBLE_ROWS, _rows.size())
	var out := ""
	for i in range(lo, hi):
		var r: Dictionary = _rows[i]
		if str(r["kind"]) == "cat":
			out += "[color=#%s]%s[/color]\n" % [CC_GOLD.to_html(false), str(r["text"])]
			continue
		var m: Dictionary = _all[int(r["idx"])]
		var nm := str(m.get("name", ""))
		var cost := int(m.get("cost", 0))
		var have := int(_picks.get(nm, 0))
		var col := NAME_SEL if i == _row else MUTED
		if have > 0:
			col = SEL_GOLD
		elif _excluded(m):
			col = DIM_BORDER
		var mark := "  "
		if i == _row:
			mark = "[color=#%s]› [/color]" % SEL_GOLD.to_html(false)
		var rank := (" x%d" % have) if have > 1 else ""
		out += "%s[color=#%s]%s[/color][color=#%s]  (%d)%s[/color]\n" % [
			mark, col.to_html(false), nm, MUTED.to_html(false), cost, rank]
	_list_lbl.text = out
	# the selections column
	var picked := "[color=#%s]Selected[/color]\n" % CC_GOLD.to_html(false)
	if _picks.is_empty():
		picked += "[color=#%s]  (none)[/color]" % MUTED.to_html(false)
	else:
		for nm in _picks:
			var n := int(_picks[nm])
			picked += "[color=#%s]  %s%s[/color]\n" % [
				NAME_SEL.to_html(false), str(nm), (" x%d" % n) if n > 1 else ""]
	_pick_lbl.text = picked
	var cm := _cur()
	_desc_lbl.text = QudText.to_bbcode(str(cm.get("desc", "")), _palette) if not cm.is_empty() else ""
	_foot.text = "[center][color=#%s]Points Remaining: %d  [/color][color=#%s][lb]Delete[rb][/color][color=#%s] Reset Selection[/color][/center]" % [
		MUTED.to_html(false), _points, SEL_GOLD.to_html(false), MUTED.to_html(false)]

## The picks go to the flow BEFORE the advance — the click box calls this too, so a mouse
## Next can no longer drop them (see the parent's note on _nav_next).
func _nav_next() -> void:
	var picks: Array = []
	for nm in _picks:
		picks.append({"name": str(nm), "count": int(_picks[nm])})
	chose_mutations.emit(picks, _base_points - _points)
	advance_page.emit()

func _step(d: int) -> void:
	var i := _row + d
	while i >= 0 and i < _rows.size() and str(_rows[i]["kind"]) != "mut":
		i += d
	if i >= 0 and i < _rows.size():
		_row = i
		_refresh()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_down"):
		_step(1); accept_event(); return
	if e.is_action_pressed("ui_up"):
		_step(-1); accept_event(); return
	if e.is_action_pressed("ui_accept"):
		_toggle(); accept_event(); return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_DELETE, KEY_BACKSPACE:
				_reset(); accept_event(); return
			KEY_9, KEY_KP_9:
				_nav_next(); accept_event(); return
	if e.is_action_pressed("ui_cancel"):
		closed.emit(); accept_event(); return
