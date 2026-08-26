extends CanvasLayer

## NO `class_name`: a newly added global class only exists once Godot's class cache has been
## rebuilt by the editor, and a headless build (and the parse audit) must not depend on that
## having happened. Main preloads this file directly — the same call BuildCode.gd makes.

## Qud's TUTORIAL GUIDE box, mirrored. The mod publishes {"type":"tutorial", active, text, step}
## whenever TutorialManager's current message changes (mod/TutorialBridge.cs); this draws it.
##
## MEASURED off Qud's own tutorial, not styled by eye — screenshots/new game/TUTORIAL, at 1966px
## wide: panel 440x138 filled (12,34,33) with NO border, a hairline rule (53,85,92) across the
## panel at 37px from its top, broken for the title; "TUTORIAL GUIDE" in (255,224,0) centred on
## that rule; body ink (168,194,187), left-aligned, blank line between paragraphs. Four 5px yellow
## notches sit at the MIDPOINT OF EACH EDGE, half outside the panel — they are the whole reason
## the box reads as Qud's and not as a generic tooltip.
##
## PLACEMENT IS OURS, not Qud's: Qud parks the box beside whatever it is highlighting, and we do
## not mirror highlights (its targets are Unity RectTransforms and screen cells, which have no
## counterpart here). So it sits at the bottom of the play area, where it covers the least — a
## deliberate simplification, and the obvious thing to revisit if highlights ever get mirrored.

const FILL := Color8(12, 34, 33)
const RULE := Color8(53, 85, 92)
const TITLE_INK := Color8(255, 224, 0)
const BODY_INK := Color8(168, 194, 187)
const NOTCH := Color8(255, 224, 0)

## All of these are MEASURED off Qud's own tutorial (screenshots/new game/TUTORIAL, 1966x1126) and
## expressed against the SCREEN, because that is what they scale with in Qud: the panel width is
## CONSTANT at 445px across every step — only the height grows with the text — and the type does
## not resize with the message either.
const W_FRAC := 0.2263          # 445 / 1966
const RULE_Y_FRAC := 0.0346     # 39 / 1126, from the panel top
const BODY_TOP_FRAC := 0.0604   # 68 / 1126, first line of body ink
const BODY_BOT_FRAC := 0.0187   # 21 / 1126, below the last line
const LINE_PITCH_FRAC := 0.0178 # 20 / 1126 — baseline to baseline
const BODY_PX_FRAC := 0.0133    # 15 / 1126 — glyph height
const TITLE_PX_FRAC := 0.0107   # 7 / 1126 (cap height, so this reads small on purpose)
const PAD_X_FRAC := 0.093       # body inset, as a fraction of PANEL width (41 / 440)
const NOTCH_FRAC := 0.0044      # 5 / 1126
const EDGE_MARGIN_FRAC := 0.02  # keep the box off the very edge of the play area

var _panel: Control
var _bg: ColorRect
var _rule_l: ColorRect
var _rule_r: ColorRect
var _title: Label
var _body: RichTextLabel
var _accept: RichTextLabel
var _notches: Array = []
var _palette := {}
var _play_rect := Rect2()

func _init() -> void:
	layer = 40          # over the world, under the modal popup overlay
	visible = false

func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_relayout)

func _build() -> void:
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_bg = ColorRect.new()
	_bg.color = FILL
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(_bg)
	_rule_l = ColorRect.new(); _rule_l.color = RULE
	_rule_r = ColorRect.new(); _rule_r.color = RULE
	for r in [_rule_l, _rule_r]:
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(r)
	_title = Label.new()
	_title.text = "TUTORIAL GUIDE"
	_title.add_theme_color_override("font_color", TITLE_INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_body)
	# the accept prompt, centred at the foot of the box ("[Space] Continue")
	_accept = RichTextLabel.new()
	_accept.bbcode_enabled = true
	# fit_content sizes a label to its CONTENT, which BEATS [center] — the prompt sat at the body
	# inset instead of centred. A centred line needs it off and an explicit width.
	_accept.fit_content = false
	_accept.autowrap_mode = TextServer.AUTOWRAP_OFF
	_accept.scroll_active = false
	_accept.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_accept)
	for i in 4:
		var n := ColorRect.new()
		n.color = NOTCH
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(n)
		_notches.append(n)

## Called by Main whenever a tutorial frame arrives. `play` is the play area's rect, so the box
## can sit inside the world view rather than over the panels.
func show_step(data: Dictionary, palette: Dictionary, play: Rect2) -> void:
	_palette = palette
	_play_rect = play
	var raw := String(data.get("text", ""))
	if raw.strip_edges() == "":
		hide_step()
		return
	var lines := PackedStringArray()
	for line in raw.split("\n"):
		# Qud's own markup, through Raves' converter — the guide colours its keys and item names
		lines.append(QudText.to_bbcode(line, _palette))
	_body.text = "[color=#%s]%s[/color]" % [BODY_INK.to_html(false), "\n".join(lines)]
	# Qud's hint convention, the same one Raves uses everywhere else: the bracketed key is gold,
	# the rest is body ink. The prompt only exists while Qud is waiting on the key.
	var btn := String(data.get("button", "")).strip_edges()
	# Through QudText like everything else: the prompt arrives as Qud's own markup
	# ("[{{hotkey|Space}}] Continue"), and hand-colouring the brackets left the braces on screen.
	_accept.text = "" if btn == "" \
		else "[center]%s[/center]" % QudText.to_bbcode(btn, _palette)
	visible = true
	_relayout()
	# the body's height is not known until it has laid the text out, and the panel is sized from it
	_relayout.call_deferred()

func hide_step() -> void:
	visible = false

func set_play_rect(play: Rect2) -> void:
	if play == _play_rect:
		return
	_play_rect = play
	if visible:
		_relayout()

func _relayout() -> void:
	if _panel == null or not visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var area := _play_rect if _play_rect.size.x > 8.0 and _play_rect.size.y > 8.0 \
		else Rect2(Vector2.ZERO, vp)
	var w: float = round(vp.x * W_FRAC)
	var pad: float = round(w * PAD_X_FRAC)
	var rule_y: float = round(vp.y * RULE_Y_FRAC)
	# TYPE FIRST: the panel is sized from the text, so the text has to be sized before it. Qud's
	# guide is set SMALLER than Raves' body face, which is why the first pass produced a box half
	# again too tall for the same sentence — the width was already right.
	_title.add_theme_font_size_override("font_size", maxi(7, int(round(vp.y * TITLE_PX_FRAC))))
	var body_px: int = maxi(9, int(round(vp.y * BODY_PX_FRAC)))
	_body.add_theme_font_size_override("normal_font_size", body_px)
	_body.add_theme_font_size_override("bold_font_size", body_px)
	# Qud's pitch is 20px per line at 1126 — a hair tighter than this face sets on its own, so the
	# separation is DERIVED from the font rather than guessed, and follows a font change.
	var f := _body.get_theme_font("normal_font")
	var natural: float = f.get_height(body_px) if f != null else float(body_px)
	_body.add_theme_constant_override("line_separation",
		int(round(vp.y * LINE_PITCH_FRAC - natural)))
	_body.position = Vector2(pad, round(vp.y * BODY_TOP_FRAC))
	_body.size.x = w - pad * 2.0
	_body.custom_minimum_size.x = _body.size.x
	_accept.add_theme_font_size_override("normal_font_size", body_px)
	var body_h: float = maxf(_body.get_content_height(), vp.y * LINE_PITCH_FRAC)
	var accept_h: float = 0.0
	if _accept.text != "":
		var line: float = round(vp.y * LINE_PITCH_FRAC)
		_accept.size = Vector2(w - pad * 2.0, line * 1.3)
		_accept.custom_minimum_size = _accept.size
		_accept.position = Vector2(pad, _body.position.y + body_h + round(line * 0.5))
		accept_h = _accept.size.y + round(line * 0.5)
	_accept.visible = _accept.text != ""
	var h: float = _body.position.y + body_h + accept_h + round(vp.y * BODY_BOT_FRAC)
	# Placement is ours (see the header): bottom of the play area, then CLAMPED inside it. A long
	# step is genuinely tall — Qud's own reaches a quarter of the screen — and a box that ran off
	# the bottom took its last instruction with it.
	var m: float = round(vp.y * EDGE_MARGIN_FRAC)
	h = minf(h, area.size.y - m * 2.0)
	var pos := Vector2(area.position.x + round((area.size.x - w) * 0.5),
		area.position.y + area.size.y - h - m)
	pos.y = maxf(pos.y, area.position.y + m)
	_panel.position = pos
	_panel.size = Vector2(w, h)
	# the rule runs the panel's full width, broken by the title
	var tw: float = _title.get_minimum_size().x + round(vp.y * 0.021)
	var th: float = _title.get_minimum_size().y
	_title.position = Vector2(round((w - tw) * 0.5), rule_y - th * 0.5)
	_title.size = Vector2(tw, th)
	var t: float = maxf(1.0, round(vp.y / 1126.0))
	_rule_l.position = Vector2(0.0, rule_y - t * 0.5)
	_rule_l.size = Vector2(maxf(0.0, round((w - tw) * 0.5)), t)
	_rule_r.position = Vector2(round((w + tw) * 0.5), rule_y - t * 0.5)
	_rule_r.size = _rule_l.size
	# four notches, each straddling the midpoint of its edge — the tell that this is Qud's box
	var n: float = maxf(3.0, round(vp.y * NOTCH_FRAC))
	var cx: float = pos.x + round(w * 0.5) - n * 0.5
	var cy: float = pos.y + round(h * 0.5) - n * 0.5
	var at := [Vector2(cx, pos.y - n * 0.5), Vector2(cx, pos.y + h - n * 0.5),
		Vector2(pos.x - n * 0.5, cy), Vector2(pos.x + w - n * 0.5, cy)]
	for i in 4:
		var k: ColorRect = _notches[i]
		k.position = at[i]
		k.size = Vector2(n, n)
		k.visible = true
