extends CanvasLayer

## Qud's end-of-run TOMBSTONE (GameSummaryScreen), mirrored — see mod/TombstoneBridge.cs.
##
## NO `class_name`, for the same reason TutorialGuide.gd has none: a newly added global class only
## exists once the editor has rebuilt its cache, and a headless build must not depend on that.
##
## Styled off Qud's own: a light panel centred on the dark field, the character's name in gold
## between brackets at the top, the summary body below it in Qud's markup, and a hint line at the
## foot. The gravestone art is Qud's; we draw the panel and let the text carry the screen.

## MEASURED off Qud's own tombstone (1920x1108): the slab is a MID-TEAL panel, not a light one,
## and the text on it is light — the first pass drew a pale slab and Qud's own markup colours
## (which are all tuned for a dark field) washed out on it to the point of being unreadable.
## Qud does NOT dim the game behind it either; the panel simply sits over the world.
const PANEL := Color8(69, 113, 123)
const NAME_INK := Color8(103, 140, 154)   # the name, in [ ] — quieter than you would guess
const BODY_INK := Color8(168, 194, 187)
const HINT_INK := Color8(164, 191, 185)

const W_FRAC := 0.4089        # 785 / 1920
const H_FRAC := 0.7004        # 776 / 1108
const CY_FRAC := 0.5817       # the panel is centred LOW, leaving room for the gravestone art
const NAME_Y_FRAC := 0.2662   # of the screen, not the panel — where Qud puts the name line
const BODY_Y_FRAC := 0.4242   # ...and the first line of the summary

signal dismissed
signal save_requested   # [F1] — Qud writes the tombstone file, not us

var _root: Control
var _slab: ColorRect
var _name: RichTextLabel
var _body: RichTextLabel
var _hint: RichTextLabel
var _palette := {}
var _built := false

func _init() -> void:
	layer = 60          # above the tutorial guide and the world; this is the end of the run
	visible = false

func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_relayout)

func _build() -> void:
	if _built:
		return
	_built = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not ignore: the tombstone is modal in Qud, and a click that fell through to the world
	# underneath would be acting on a game that has already ended.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_slab = ColorRect.new()
	_slab.color = PANEL
	_slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_slab)
	_name = _label(NAME_INK, HORIZONTAL_ALIGNMENT_CENTER)
	_body = _label(BODY_INK, HORIZONTAL_ALIGNMENT_LEFT)
	_body.scroll_active = true
	_hint = _label(HINT_INK, HORIZONTAL_ALIGNMENT_CENTER)

func _label(ink: Color, _align: int) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("default_color", ink)
	_root.add_child(l)
	return l

func show_tombstone(data: Dictionary, palette: Dictionary) -> void:
	_build()
	_palette = palette
	var who := QudText.strip(String(data.get("name", "")))
	var cause := String(data.get("cause", ""))
	var details := String(data.get("details", ""))
	_name.text = "[center][color=#%s][ %s ][/color][/center]" % [NAME_INK.to_html(false), who]
	var lines := PackedStringArray()
	if cause.strip_edges() != "":
		lines.append(QudText.to_bbcode(cause, _palette))
		lines.append("")
	for line in details.split("\n"):
		lines.append(QudText.to_bbcode(line, _palette))
	_body.text = "[color=#%s]%s[/color]" % [BODY_INK.to_html(false), "\n".join(lines)]
	# Both of Qud's, because both work: F1 is forwarded to the screen's own SaveTombstone().
	_hint.text = "[center][color=#%s][lb]F1[rb] Save Tombstone File   [lb]Esc[rb] Exit[/color][/center]" \
		% HINT_INK.to_html(false)
	visible = true
	_relayout()
	_relayout.call_deferred()

func hide_tombstone() -> void:
	visible = false

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventKey and e.pressed and not e.echo \
		and (e.keycode == KEY_ESCAPE or e.keycode == KEY_SPACE or e.keycode == KEY_ENTER):
		dismissed.emit()
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F1:
		save_requested.emit()
		get_viewport().set_input_as_handled()

func _relayout() -> void:
	if not visible or _root == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w: float = round(vp.x * W_FRAC)
	var h: float = round(vp.y * H_FRAC)
	var x: float = round((vp.x - w) * 0.5)
	var y: float = round(vp.y * CY_FRAC - h * 0.5)
	_slab.position = Vector2(x, y)
	_slab.size = Vector2(w, h)
	var pad: float = round(w * 0.045)
	var name_h: float = round(vp.y * 0.05)
	_name.position = Vector2(x, round(vp.y * NAME_Y_FRAC))
	_name.size = Vector2(w, name_h)
	_name.add_theme_font_size_override("normal_font_size",
		int(round(UiFont.px(get_viewport(), "big"))))
	var hint_h: float = round(vp.y * 0.035)
	var body_y: float = round(vp.y * BODY_Y_FRAC)
	_body.position = Vector2(x + pad, body_y)
	_body.size = Vector2(w - pad * 2.0, maxf(hint_h, y + h - body_y - hint_h - pad))
	_body.add_theme_font_size_override("normal_font_size",
		int(round(UiFont.px(get_viewport(), "body"))))
	_hint.position = Vector2(x, y + h - hint_h)
	_hint.size = Vector2(w, hint_h)
	_hint.add_theme_font_size_override("normal_font_size",
		int(round(UiFont.px(get_viewport(), "caption"))))
