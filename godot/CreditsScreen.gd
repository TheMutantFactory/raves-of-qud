extends Control

## THE CREDITS SCREEN — who made what, as a tree with two branches.
##
## Daniel: "Let's create a 'Credits' view. It's a tree that contains a node with Freehold Games
## images and credit and another node that displays open images and credits."
##
## THE SPLIT IS THE POINT, and it is the one that matters legally: assets that belong to someone
## else and are only RENDERED from the copy you own, against assets that ship in this repository
## under an open licence. Everything Raves draws falls in one branch or the other, and the reader
## can see at a glance which is which. The copy itself lives in Brand.credit_branches — Brand is
## where this project keeps facts about other people, so a rename or a new screen cannot drift from
## them.
##
## THE FREEHOLD BRANCH SHOWS QUD'S OWN TILES, resolved at runtime out of the player's export. That
## is not incidental: a credits screen for art you do not ship should not ship that art to
## illustrate itself. If the export is not there the rows simply carry no icon.
##
## Styled as the toolkit screen is — the same dimmed backdrop, teal box, gold title and "[Esc] Back"
## footer — because it opens from the same title-screen link column and should read as a sibling.
## It is NOT a 1:1 mimic: Qud has its own credits screen and this is not it. This is Raves saying
## what Raves is made of.

signal closed

## highvisor scene name (MainMenu._open_overlay reads it)
var ui_scene := "credits"

const SCRIM := Color(0.01, 0.02, 0.02, 0.90)
const BACKDROP_DIM := Color(0.01, 0.02, 0.02, 0.765)
const PANEL := Color8(0x0E, 0x3F, 0x3A)
const BORDER := Color8(0x5B, 0x8A, 0x84)
const TITLE_GOLD := Color8(0xE8, 0xD4, 0x4D)
const ITEM := Color8(0x7F, 0xC0, 0xBA)
const NOTE := Color8(0x8F, 0xA6, 0x9E)
const HINT_DIM := Color8(0x8F, 0xA6, 0x9E)
const FONT_REG := "res://fonts/SourceCodePro-Regular.ttf"
const FONT_BOLD := "res://fonts/SourceCodePro-Bold.ttf"
const ITEM_PX := 17

## Wider and taller than the toolkit box: this one carries paragraphs, not nine short rows.
const BOX_W_FRAC := 0.62
const BOX_H_FRAC := 0.66
const BOX_CY := 0.5

var _box: Control
var _tree: Tree
var _tiles: RefCounted


func _ready() -> void:
	name = "CreditsScreen"
	_fit_to_viewport()
	theme = UiFont.make_theme(get_viewport())
	var empty := StyleBoxEmpty.new()
	for tt in ["Label", "Caption", "Title", "Big"]:
		theme.set_stylebox("normal", tt, empty)
	get_viewport().size_changed.connect(_relayout)

	var scrim := ColorRect.new()
	scrim.color = SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP   # modal: swallow clicks to the menu behind
	add_child(scrim)

	_box = Control.new()
	add_child(_box)
	_build_box()
	_relayout()

func _fit_to_viewport() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _relayout() -> void:
	_fit_to_viewport()
	if _box == null:
		return
	UiFont.refresh_theme(theme, get_viewport())
	var vp := get_viewport().get_visible_rect().size
	var bw := vp.x * BOX_W_FRAC
	var bh := vp.y * BOX_H_FRAC
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = BOX_CY
	_box.anchor_bottom = BOX_CY
	_box.offset_left = -bw * 0.5
	_box.offset_right = bw * 0.5
	_box.offset_top = -bh * 0.5
	_box.offset_bottom = bh * 0.5

func _build_box() -> void:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_border_width_all(2)
	sb.border_color = BORDER
	sb.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", sb)
	_box.add_child(panel)

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.add_theme_font_override("normal_font", load(FONT_BOLD))
	title.add_theme_font_size_override("normal_font_size", ITEM_PX + 3)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "[center][color=#%s]┤ [/color][color=#%s]Credits[/color][color=#%s] ├[/color][/center]" % [
		HINT_DIM.to_html(false), TITLE_GOLD.to_html(false), HINT_DIM.to_html(false)]
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = -0.03
	title.anchor_bottom = 0.06
	for k in ["left", "top", "right", "bottom"]:
		title.set("offset_" + k, 0.0)
	_box.add_child(title)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.allow_reselect = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.add_theme_font_override("font", load(FONT_REG))
	_tree.add_theme_font_size_override("font_size", ITEM_PX)
	_tree.add_theme_color_override("font_color", ITEM)
	_tree.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_tree.anchor_left = 0.03
	_tree.anchor_right = 0.97
	_tree.anchor_top = 0.08
	_tree.anchor_bottom = 0.93
	for k in ["left", "top", "right", "bottom"]:
		_tree.set("offset_" + k, 0.0)
	_box.add_child(_tree)
	_fill_tree()

	var foot := RichTextLabel.new()
	foot.bbcode_enabled = true
	foot.fit_content = true
	foot.scroll_active = false
	foot.add_theme_font_override("normal_font", load(FONT_REG))
	foot.add_theme_font_size_override("normal_font_size", ITEM_PX - 2)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gold := "#%s" % TITLE_GOLD.to_html(false)
	var dim := "#%s" % HINT_DIM.to_html(false)
	foot.text = "[center][color=%s]┤ [/color][url=esc][color=%s][lb]Esc[rb][/color][color=%s] Back[/color][/url][color=%s] ├[/color][/center]" % [dim, gold, dim, dim]
	foot.anchor_left = 0.0
	foot.anchor_right = 1.0
	foot.anchor_top = 0.955
	foot.anchor_bottom = 1.045
	for k in ["left", "top", "right", "bottom"]:
		foot.set("offset_" + k, 0.0)
	_box.add_child(foot)
	preload("res://UiHint.gd").clickable(foot, {"esc": func(): closed.emit()})

## Two branches, each opened, each with its own note and its own rows.
func _fill_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	for branch in Brand.credit_branches():
		var head := _tree.create_item(root)
		head.set_text(0, String(branch.get("head", "")))
		head.set_custom_color(0, TITLE_GOLD)
		head.set_selectable(0, false)
		head.set_collapsed(false)
		var note := _tree.create_item(head)
		note.set_text(0, String(branch.get("note", "")))
		note.set_custom_color(0, NOTE)
		note.set_selectable(0, false)
		note.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
		for e in branch.get("entries", []):
			var entry: Dictionary = e
			var row := _tree.create_item(head)
			row.set_text(0, "%s — %s" % [String(entry.get("name", "")),
				String(entry.get("note", ""))])
			row.set_selectable(0, false)
			row.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
			var tex := _row_icon(entry)
			if tex != null:
				row.set_icon(0, tex)
				row.set_icon_max_width(0, 24)

## The row's picture: a Qud tile out of the player's own export, or a res:// asset this repo does
## ship. Nothing is drawn when neither is available — a credits screen should not invent art.
func _row_icon(entry: Dictionary) -> Texture2D:
	var art := String(entry.get("art", ""))
	if art != "":
		return load(art) as Texture2D
	var tile := String(entry.get("tile", ""))
	if tile == "":
		return null
	if _tiles == null:
		_tiles = load("res://QudTiles.gd").new()
		_tiles.tiles_dir = InputModel.support_dir().path_join("tiles")
		_tiles.palette = QudPalette.markup()
	return _tiles.texture(tile, Color.WHITE, Color.WHITE)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()
