extends "res://ChargenCardScreen.gd"
const BuildCode := preload("res://BuildCode.gd")

## CHARACTER CREATION — LIBRARY (docs/new-game-plan.md slice 8): the saved-build lane. A list
## of everything "Save Build To Library" has kept, plus a PASTE row that reads a build code off
## the clipboard — the other half of the summary's "Export Code to Clipboard", and the way a
## build travels between players. Picking a row decodes it and hands the flow a complete build,
## which lands on the summary like any other lane.

signal chose_build(build: Dictionary, label: String)

var mode_name := ""

var _entries: Array = []
var _row := 0
var _list_lbl: RichTextLabel = null
var _note_lbl: RichTextLabel = null
var _note := ""
var _note_t := 0.0

func _screen_node_name() -> String: return "LibraryScreen"
func _subtitle() -> String: return ":choose a saved build:"
func _load_items() -> Array: return []

func _breadcrumb_crumbs() -> Array:
	var out: Array = []
	if mode_name != "":
		out.append({"label": mode_name, "current": false,
			"tile": _chargen_tile("gameModes", mode_name)})
	out.append({"label": "Library", "current": true})
	return out

func _build_body(vp: Vector2) -> void:
	_entries = BuildCode.library()
	_list_lbl = _rich("", "body")
	_list_lbl.position = Vector2(vp.x * 0.32, vp.y * 0.50)
	_list_lbl.size = Vector2(vp.x * 0.36, vp.y * 0.30)
	_list_lbl.custom_minimum_size = _list_lbl.size
	add_child(_list_lbl)
	_note_lbl = _rich("", "body")
	_note_lbl.anchor_left = 0.0; _note_lbl.anchor_right = 1.0
	_note_lbl.position.y = vp.y * 0.83
	add_child(_note_lbl)
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

func _rows() -> int:
	return _entries.size() + 1     # + the paste row

func _refresh() -> void:
	var out := ""
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var col := NAME_SEL if i == _row else MUTED
		var cursor := "[color=#%s]› [/color]" % SEL_GOLD.to_html(false) if i == _row else "  "
		out += "%s[color=#%s]%s[/color][color=#%s]   %s[/color]\n" % [
			cursor, col.to_html(false), str(e.get("name", "(unnamed build)")),
			MUTED.to_html(false), str(e.get("saved", ""))]
	if _entries.is_empty():
		out += "[color=#%s]  Your library is empty — build a character and press [lb]S[rb] on the\n  build summary to keep it here.[/color]\n" % MUTED.to_html(false)
	out += "\n"
	var pcol := NAME_SEL if _row >= _entries.size() else MUTED
	var pcur := "[color=#%s]› [/color]" % SEL_GOLD.to_html(false) if _row >= _entries.size() else "  "
	out += "%s[color=#%s]Paste a build code from the clipboard[/color]" % [pcur, pcol.to_html(false)]
	_list_lbl.text = out
	_note_lbl.text = "[center][color=#%s]%s[/color][/center]" % [CC_GOLD.to_html(false), _note] if _note != "" else ""

func _take(build: Dictionary, label: String) -> void:
	if str(build.get("genotype", "")) == "" or str(build.get("subtype", "")) == "":
		_note = "That build code is missing a genotype or subtype."
		_note_t = 3.0
		_refresh()
		return
	chose_build.emit(build, label)

func _pick() -> void:
	if _row < _entries.size():
		var e: Dictionary = _entries[_row]
		_take(BuildCode.decode(str(e.get("code", ""))), str(e.get("name", "Library")))
		return
	var clip := DisplayServer.clipboard_get().strip_edges()
	if clip == "":
		_note = "The clipboard is empty."
		_note_t = 3.0
		_refresh()
		return
	var b: Dictionary = BuildCode.decode(clip)
	if b.is_empty():
		_note = "That does not look like a Qud build code."
		_note_t = 3.0
		_refresh()
		return
	_take(b, "Pasted")

func _process(dt: float) -> void:
	super._process(dt)
	if _note_t > 0.0:
		_note_t -= dt
		if _note_t <= 0.0:
			_note = ""
			_refresh()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_down"):
		_row = mini(_row + 1, _rows() - 1); _refresh(); accept_event(); return
	if e.is_action_pressed("ui_up"):
		_row = maxi(_row - 1, 0); _refresh(); accept_event(); return
	if e.is_action_pressed("ui_accept"):
		_pick(); accept_event(); return
	if e.is_action_pressed("ui_cancel"):
		closed.emit(); accept_event(); return
