extends Control

## Reusable CHARACTER-CREATION "card row" screen — the shared template behind Qud's guided chargen
## steps (Choose Game Mode, Choose Genotype, …). One horizontal row of dashed-frame cards on Qud's
## dark ground, with the sheaf emblem + "character creation" + a ":choose …:" subtitle above, the
## selected item's flavour text below, "[R] Randomize Selection", the nav hint, a top-left breadcrumb,
## and left/right page arrows. All the extracted-sprite chrome (frame, emblem, arrows, ornament) and
## the icon-recolour/selection machinery live here; a subclass supplies the DATA + a few strings by
## overriding the hooks in the "SUBCLASS HOOKS" section.

signal closed
signal chose(name: String)          # the confirmed item name (mode / genotype / …)
signal advance_page                 # the "Next" affordance (right arrow / [9]) — subclass decides

# ── palette (measured off Qud captures) ───────────────────────────────────────────
const BG := Color8(0x04, 0x21, 0x20)
const CC_GOLD := Color8(0xAC, 0xA3, 0x36)     # "character creation"
const SUB_TEAL := Color8(0x29, 0x73, 0x82)    # ":choose …:"
const MUTED := Color8(0x61, 0x7C, 0x78)       # breadcrumb / description / hint
## The category band's dashed RULE. Qud draws every band's rule in this one colour and gives only
## the LABEL the arcology's colour — measured on all three at once: the rule reads (73,117,126)
## under the green Ekuemekiyye label, the cyan Ibul label AND the orange Yawningmoon label alike.
## Raves used to tint the rule to match its label, which is why the header row read as three
## coloured strips rather than three labels on one rule.
const BAND_RULE := Color8(0x49, 0x75, 0x7E)   # Qud (73,117,126)
## Breadcrumb icons. Qud draws them all in ONE flat colour — the mode sprite, the plus, the True Kin
## face and the current crumb's plain glyph every peak at (66,100,112) — so the tile is used as a
## MASK and tinted, NOT rendered in the item's own `detail` colour the way the cards are.
const CRUMB_ICON := Color8(0x42, 0x64, 0x70)  # Qud (66,100,112)
## Selected card border + hotkey + caret. Qud's own W (#cfc041) — measured off the caste screen's
## selection frame at (207,192,65), which is that palette entry exactly. Was a hand-picked
## (200,184,57).
const SEL_GOLD := QudPalette.COLORS["W"]
const BRIGHT_GOLD := Color8(0xE8, 0xD0, 0x1C) # onboarding highlight + guide corner squares (bright yellow)
const DIM_BORDER := Color8(0x2C, 0x47, 0x47)  # unselected card border
## Blocked-card warnings. Qud's own caution amber (its 'W'), not red: this is "not here",
## not "something broke".
const WARN_AMBER := Color8(0xCF, 0xC0, 0x41)
const NAME_SEL := Color8(0xC5, 0xCE, 0xC6)    # selected name
# Unselected name and hotkey, SAMPLED off Qud rather than eyeballed, and sampled on all three card
# screens because these are shared: the 90th-percentile ink of an unselected label measured
# (13,62,61)/(13,63,62)/(14,64,63) for the name on caste/genotype/mode, and (5,50,48)/(12,57,56)/
# (12,57,56) for the hotkey. Raves was drawing (77,99,95) and (106,101,58) — the name far too bright,
# and the hotkey a wrong HUE: Qud's resting hotkey is the same dim teal as the name, not olive-gold.
# Only the SELECTED card's hotkey goes gold (SEL_GOLD), which is what the olive was half-remembering.
const NAME_DIM := Color8(0x0D, 0x3F, 0x3E)    # unselected name    — Qud (13,63,62)
const HOTKEY_DIM := Color8(0x0C, 0x39, 0x38)  # unselected hotkey  — Qud (12,57,56)
const ICON_MAIN := Color8(0xA8, 0xC2, 0xBB)   # neutral (unselected) icon body
const ICON_DETAIL := Color8(0x15, 0x49, 0x48) # neutral icon detail
const ICON_SEL := Color(1, 1, 1, 1)
const ICON_DIM := Color(0.35, 0.47, 0.54, 1.0)
## Side-nav ("[Esc] Back" / "[Num 9] Next"), measured off Qud's caste screen. Three distinct
## colours, where Raves previously used MUTED for everything and a guessed DIM:
##   arrow, enabled  (66,100,112) — the same steel as the breadcrumb icons
##   text,  enabled  (177,201,195) — QudPalette y
##   either, disabled (15,59,58)  — QudPalette k, all but invisible
## Qud's Next reads disabled on arrival because nothing is confirmed yet; its Back is always live,
## so the Back reading is the one that is not confounded by state — and Raves was drawing it at
## (97,124,120) against Qud's (177,201,195).
const NAV_ARROW := Color8(0x42, 0x64, 0x70)   # Qud (66,100,112) — same value as CRUMB_ICON
## The three-dot deco under the description. Its own steel, bluer than both MUTED (97,124,120) and
## the nav/crumb steel (66,100,112) — not a palette entry, so it is recorded as measured.
const DECO_KNOB := Color8(0x5B, 0x7A, 0x8A)   # Qud (91,122,138)
## How far a card NAME may spill past its column on each side before wrapping. Qud's names overflow
## their cards freely — "Horticulturist" is 118px over a 97px card — and 10 each side is what makes
## "Priest of All Suns" break in two like Qud's rather than three. Costs no layout width; see the
## wrapper in _build_card.
const NAME_OVERFLOW := 10
const HINT_TEXT := QudPalette.COLORS["y"]     # Qud (177,201,195)
const DIM := QudPalette.COLORS["k"]           # Qud (15,59,58) — "[Num 9] Next" when disabled

## Qud's colour codes -> RGB. QudPalette.COLORS is the canonical table and always was; this file
## carried its own hand-approximated copy that had drifted badly, and since the same table colours
## every screen, every parity comparison was carrying the drift.
##
## Measured on THIS screen's arcology band rules at 1920x1080: Qud draws the Ibul band (96,162,174)
## where the local copy drew (97,245,245), and Yawningmoon (168,64,14) where it drew (244,75,75) —
## generic bright ANSI colours against Qud's muted set. Three entries were the wrong hue family
## outright: R is ORANGE, not pink-red; k/K are dark TEAL, not grey; y is green-tinted bone.
##
## Confirmed first-party rather than assumed: `hv bridge dumpcolors` calls Qud's own
## ColorUtility.colorFromChar for every code (mod: ColorsExporter) and the export agrees with
## QudPalette exactly, so the wiki transcription it was built from is correct.
const QUD_COLORS := QudPalette.COLORS

## Qud draws its chargen text SMALLER than the app's own scale. Measured by column-profiling the same
## strings in both apps at 1920x1080: "character creation" spans 284px in Qud against 330 in Raves,
## ":choose caste:" 127 against 142 — the same ratio on the genotype screen as on Choose Caste, so it
## is one scale for the whole chargen flow rather than a per-screen nudge. 0.87 lands the title at
## 287 and the subtitle at 124.
##
## Applied as a THEME rather than per-label font sizes, which UiFont's contract forbids: the sizes
## still come from UiFont.px() and still track window height, this subtree just reads them at 0.87.
## It is also what stops long card names wrapping — "Horticulturist" only overflowed its frame
## because it was being drawn 15% too wide.
const TEXT_SCALE := 0.87

var selected := ""

## Steer the player at ONE card by drawing a bright highlight box around it (opt-in; set before
## adding to the tree). Left at -1, no card is steered.
##
## Nothing sets this since Raves' tutorial lane was removed (2026-08-26). It is kept because it is
## three lines and it is the mechanism any future guided flow would want — the notice popup below
## survived the same cut for the same reason, and is in use.
var onboard_index := -1
## Set before adding to the tree: open on THIS card rather than on the screen's default. Used by
## every Back link — a Back that forgets what the player picked is a Back that silently rerolls
## part of their build.
var preselect_name := ""
var _onboard_active := true   # onboard card shows the bright highlight until the player engages a card
## The notice popup, in Qud's frame style. Still in use: the chartype screen shows the lanes Raves
## has no slice for through it ("NOT YET IN RAVES").
var guide_title := "TUTORIAL GUIDE"
var guide_body := ""

var _items: Array = []
var _sel := 0
var _cards: Array = []
var _desc: RichTextLabel
var _warn: RichTextLabel   # blocked-card explanation (see _card_blocked)
var _deco_knobs: Array = []   # the three-dot deco, hidden while a refusal is on screen
var _col_title: Label         # "character creation" — the top of the cascading column
                              # (named _col_* so a subclass may keep its own _title_lbl)
var _col_sub: Label           # ":choose …:"
var _col_row: Control        # the HBox of cards
var _resize_t: Timer          # debounces the rebuild while a window is being dragged
var _foot_actions := {}       # url id -> Callable, for the clickable footer keys
var _body_bot := 0.0          # panel screens: the bottom of their own content (see _body_bottom)
var _body_nodes: Array = []   # panel screens: everything their body drew, so the cascade can push it
var _body_top_home := 0.0     # ...and the y its first row was built at
var _title_bottom := 0.0      # filled by the cascade; the selection frame may not rise above it
var _sub_top := 0.0           # ...and prefers to sit above this, in the title-to-subtitle gap
var _refusal: Control      # the red X flashed over a refused card
## Qud's own red — its palette 'R' (#d74200), not a hand-picked one, so the X belongs to the
## same 18 colours as everything else on screen.
const REFUSE_RED := QudPalette.COLORS["R"]
var _palette := {}
var _border_tex: ImageTexture
var _peer := StreamPeerTCP.new()
var _sent := false
var _resolve_until := 0
var _poll_t := 0.0
var _emblem_rect: TextureRect
var _emblem_extracted := false
var _frame_tex: Texture2D
var _frame_extracted := false
var _guide_body_label: RichTextLabel   # the popup body, so the live tip can be swapped in
var _sel_frame: NinePatchRect          # Qud's big solid-yellow selection frame (corner brackets), moves to the selection

# ══ SUBCLASS HOOKS — override these ════════════════════════════════════════════════

## WHAT BACK AND NEXT DO — one path, so the key and the click cannot diverge. A screen that
## must hand its build to the flow before advancing (attributes, mutations, cybernetics all
## emit their picks first) overrides _nav_next rather than only handling the key, which is
## exactly how a click would otherwise drop the player's choices on the floor.
func _nav_back() -> void:
	closed.emit()

func _nav_next() -> void:
	advance_page.emit()

## Node name (debug/inspection only).
func _screen_node_name() -> String: return "ChargenCardScreen"

## Breadcrumb crumbs shown top-left, left→right, e.g.
## [{"label": "Classic", "tile": "UI/sw_classic_mode.bmp"}, {"label": "Caste", "current": true}].
## `tile` is optional and only drawn on COMPLETED crumbs; the current one keeps the plain glyph.
func _breadcrumb_crumbs() -> Array: return [{"label": "Choose", "current": true}]

## The ":choose …:" subtitle line under "character creation".
func _subtitle() -> String: return ":choose:"

## The item list: [{name, display, hotkey, tile, desc}], in card order.
func _load_items() -> Array: return []

## WHY A CARD CANNOT BE CHOSEN IN RAVES — "" when it can. A non-empty string is shown under
## the description whenever the card is selected (hovering a card selects it, so this is the
## hover warning too) and REFUSES the confirm, keys and clicks alike. Better than a mode that
## looks available and then behaves differently from Qud's.
func _card_blocked(_item_name: String) -> String: return ""

## Which card is selected on open.
func _default_index() -> int: return 0

## Is the "Next" (page-forward) affordance enabled? Disabled ⇒ drawn very dim, no advance.
func _next_enabled() -> bool: return false

## Build a card's [colored (selected), neutral (unselected)] icon textures from its tile. Default =
## the mode two-tone recolour; the genotype screen keeps native creature colours for `colored`.
func _card_icon(tile: String, item_name: String) -> Dictionary:
	var colored := _recolor_tile(tile, ICON_MAIN, ICON_DETAIL)
	return {"colored": colored, "neutral": colored}

## CATEGORY BANDS — a coloured, dash-ruled header row above the cards, each band spanning its own
## contiguous group of them: [{display, start, count}], where `display` is Qud's own markup and
## carries the band's colour. Empty (the default) means no header row at all, which is every chargen
## screen but Choose Caste — Qud groups the twelve castes under their three arcologies and rules a
## dashed line across each group.
func _category_bands() -> Array: return []

## Vertical layout, as fractions of viewport height. These are HOOKS rather than constants because
## the banded screen is not the unbanded one shifted by a fixed amount: inserting the header row moves
## the title and subtitle up by ~0.035 but the card row by only ~0.013, so a single "lift" would put
## one of them wrong. Measured off Qud captures at 1920x1080; see CasteScreen for the banded set.
func _y_title() -> float: return 0.4304   # was 0.435; row-profiling put Raves' title 5px below Qud's
func _y_subtitle() -> float: return 0.455
func _y_bands() -> float: return 0.449
func _y_cards() -> float: return 0.483
func _y_desc() -> float: return 0.665

## Card width and inter-card gap, as fractions of viewport WIDTH. A hook because the row does not
## simply stretch with the item count: Qud fits twelve castes into much the same span it gives five
## game modes by drawing them narrower and tighter, so a screen with a long row supplies its own
## measured pair rather than inheriting the five-card one.
func _card_w_frac() -> float: return 0.049
## Card HEIGHT as a fraction of viewport height. A hook for the same reason the width is one:
## Qud's starting-location cards carry a 5x3 map thumbnail and are far taller than the figure
## cards, and a screen with taller cards is not the figure row stretched.
func _card_h_frac() -> float: return 0.086
func _card_gap_frac() -> float: return 0.014

## How far ABOVE the selected card the big selection frame reaches, as a fraction of viewport height.
## On an unbanded screen Qud runs it up to the subtitle line; on Choose Caste there is an arcology
## row in that space and Qud's frame stops short of it, so the banded screen tightens this rather
## than drawing its highlight straight through a header.
func _sel_pad_top_frac() -> float: return 0.024

## The three-dot deco's measured HOME, as a fraction of viewport height. Qud puts it lower on the
## card screens than on the panel ones, which is why this is a hook and not a constant.
func _y_deco() -> float: return 0.8333
## The top of the footer block. The deco is never pushed into it.
func _y_footer_top() -> float: return 0.905
## THE BOTTOM OF WHAT THE BODY DREW, in pixels, for screens whose body is a PANEL rather than the
## card row — the cascade cannot walk rows it does not know about. A panel screen sets `_body_bot`
## at the end of its _build_body and the deco follows it. 0 means "nothing to clear".
func _body_bottom() -> float: return _body_bot

# ══ lifecycle ══════════════════════════════════════════════════════════════════════

func _ready() -> void:
	name = _screen_node_name()
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	get_viewport().size_changed.connect(_on_viewport_resized)
	theme = UiFont.scaled_theme(get_viewport(), TEXT_SCALE)
	for code in QUD_COLORS:
		_palette[code] = "#" + Color(QUD_COLORS[code]).to_html(false)
	_items = _load_items()
	_sel = clampi(_default_index(), 0, maxi(0, _items.size() - 1))
	if preselect_name != "":
		for i in _items.size():
			if str(_items[i].get("name", "")) == preselect_name:
				_sel = i
				break

	_build_screen()
	_peer.connect_to_host(BridgeClient.host(), BridgeClient.port())

## Everything visual, in one place, so a resize can re-run EXACTLY what a first build ran.
func _build_screen() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_build_topleft()
	_build_side_nav()
	_build_center()
	_ensure_sel_frame()
	_apply_selection()
	_resolve_icons()
	if guide_body != "":
		_build_guide()
	_init_sel_frame_deferred()   # awaits layout, then boxes the selected card
	# EVERY screen, not just the card ones: _build_center draws the title and subtitle for all of
	# them, and a panel screen'"'"'s deco has the same job to do as a card screen'"'"'s.
	_layout_column.call_deferred()

## RESPONSIVE, by rebuilding. Every row on this screen is sized and placed from the viewport at
## BUILD time — card widths, the band pitch, the chevrons, the breadcrumb, the emblem — and a
## Control that was given anchors keeps the OFFSETS it was built with, so a resized window left
## the column centred on the old width with the cards and the flavour line adrift. Re-running the
## build is the honest fix: there is exactly one code path that knows how this screen is laid out,
## and it is the one that just ran.
##
## Debounced, because size_changed fires every frame while a window is being dragged, and the
## selection is carried across so a resize does not reset what the player picked.
func _on_viewport_resized() -> void:
	if _resize_t != null and is_instance_valid(_resize_t):
		_resize_t.start()
		return
	_resize_t = Timer.new()
	_resize_t.one_shot = true
	_resize_t.wait_time = 0.15
	_resize_t.timeout.connect(_rebuild_screen)
	add_child(_resize_t)
	_resize_t.start()

func _rebuild_screen() -> void:
	var keep := _sel
	for c in get_children():
		if c == _resize_t:
			continue
		remove_child(c)   # NOW, not queue_free: a lingering child poisons the next build's
		c.queue_free()    # get_children() the same way it poisoned _build_buttons
	_cards.clear()
	_bands.clear()
	_deco_knobs.clear()
	_sel_frame = null
	_col_title = null
	_col_sub = null
	_col_row = null
	_desc = null
	_warn = null
	_emblem_rect = null
	_guide_body_label = null
	theme = UiFont.scaled_theme(get_viewport(), TEXT_SCALE)
	_sel = clampi(keep, 0, maxi(0, _items.size() - 1))
	_build_screen()

func _process(dt: float) -> void:
	_peer.poll()
	if not _sent and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_sent = true
		_send_bridge({"type": "command", "name": "export"})
		_resolve_until = Time.get_ticks_msec() + 6000
	if _resolve_until > 0:
		_poll_t += dt
		if _poll_t >= 0.4:
			_poll_t = 0.0
			_resolve_icons()
		if Time.get_ticks_msec() >= _resolve_until:
			_resolve_until = 0
			_resolve_icons()

func _exit_tree() -> void:
	if _peer != null:
		_peer.disconnect_from_host()

func _send_bridge(msg: Dictionary) -> void:
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var payload := JSON.stringify(msg).to_utf8_buffer()
	var n := payload.size()
	var frame := PackedByteArray()
	frame.append((n >> 24) & 0xFF); frame.append((n >> 16) & 0xFF)
	frame.append((n >> 8) & 0xFF); frame.append(n & 0xFF)
	frame.append_array(payload)
	_peer.put_data(frame)

func _fit_to_viewport() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

# ══ icon resolution (async tile export) ════════════════════════════════════════════

func _resolve_icons() -> void:
	var latest := _load_items()
	var all_done := true
	for i in range(mini(_cards.size(), latest.size())):
		if _cards[i].has("colored"):
			continue
		var t := str(latest[i].get("tile", ""))
		if t == "":
			all_done = false
			continue
		var icons := _card_icon(t, str(latest[i].get("name", "")))
		if icons.is_empty() or icons.get("colored") == null:
			all_done = false
			continue
		_cards[i]["colored"] = icons["colored"]
		_cards[i]["neutral"] = icons.get("neutral", icons["colored"])
	_apply_selection()
	if not _frame_extracted:
		var fr := _load_card_frame()
		if fr != null:
			_frame_tex = fr
			_frame_extracted = true
			for c in _cards:
				_apply_card_frame(c["border"])
	if not _emblem_extracted:
		var e := _load_emblem()
		if e != null:
			_set_emblem(e)
			_emblem_extracted = true
	if all_done and _emblem_extracted:
		_resolve_until = 0

# ══ layout: top-left breadcrumb ════════════════════════════════════════════════════

func _build_topleft() -> void:
	var frame := _load_card_frame()
	var x := 30.0
	for crumb in _breadcrumb_crumbs():
		var box := Control.new()
		box.position = Vector2(x, 28)
		box.size = Vector2(44, 46)
		_crumb_frame(box, frame)
		# A COMPLETED crumb shows the tile of the thing that was chosen — Qud puts the Classic mode
		# sprite behind "Classic" and the True Kin sprite behind "True Kin". The CURRENT crumb keeps
		# the plain filled rounded-rect, which is what every crumb used to draw.
		var tile := str(crumb.get("tile", ""))
		var tex: Texture2D = null
		if tile != "" and not bool(crumb.get("current", false)):
			tex = _recolor_tile(tile, CRUMB_ICON, CRUMB_ICON)
		if tex != null:
			var ic := TextureRect.new()
			ic.texture = tex
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 22x23, not the box's full 28x30: Qud's crumb sprite lights ~85 px against 139 at that
			# size, i.e. Raves was drawing it ~1.28x too large. (Counting is the only clean way to
			# compare here — Qud's dashed crumb FRAME is tinted the same colour as the icon, so an
			# ink bounding box measures the frame, and every crumb then reads an identical 34x43.)
			ic.position = Vector2(11, 12); ic.size = Vector2(22, 23)
			box.add_child(ic)
		else:
			var glyph := Panel.new()   # the filled rounded-rect breadcrumb icon
			var gsb := StyleBoxFlat.new()
			gsb.bg_color = CRUMB_ICON
			gsb.set_corner_radius_all(3)
			glyph.add_theme_stylebox_override("panel", gsb)
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyph.position = Vector2(14, 11); glyph.size = Vector2(16, 24)
			box.add_child(glyph)
		add_child(box)
		x += 52
		var cur: bool = bool(crumb.get("current", false))
		var t := _text(str(crumb.get("label", "")), NAME_SEL if cur else MUTED, "body")
		t.position = Vector2(x + 6, 40)
		add_child(t)
		x += t.get_theme_font("font").get_string_size(t.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, t.get_theme_font_size("font_size")).x + 22

## The tile of a previously-chosen chargen item, for its breadcrumb crumb — e.g. _chargen_tile(
## "gameModes", "Classic") -> "UI/sw_classic_mode.bmp". Empty when chargen.json is missing or the
## name is not in that section, which just leaves the crumb on its plain glyph.
func _chargen_tile(section: String, item_name: String) -> String:
	if item_name == "":
		return ""
	var path := InputModel.support_dir().path_join("chargen.json")
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary and data.get(section, null) is Array):
		return ""
	for it in data[section]:
		if it is Dictionary and str(it.get("name", "")) == item_name:
			return str(it.get("tile", ""))
	return ""

func _crumb_frame(box: Control, frame: Texture2D) -> void:
	if frame != null:
		var np := NinePatchRect.new()
		np.texture = frame
		var m := int(round(frame.get_height() * 17.0 / 80.0))
		np.patch_margin_left = m; np.patch_margin_right = m
		np.patch_margin_top = m; np.patch_margin_bottom = m
		np.draw_center = false
		np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		np.modulate = MUTED
		np.set_anchors_preset(Control.PRESET_FULL_RECT)
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(np)
	else:
		var b := TextureRect.new()
		b.texture = _dashed_border_tex(44, 46)
		b.modulate = MUTED
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(b)

# ══ layout: left/right page nav ════════════════════════════════════════════════════

## ONE CLICK TARGET PER SIDE, spanning the chevron AND its caption — Daniel: "the arrow, the
## keyboard shortcut and the word Back. Just draw one whole clicktarget box around it." The
## box is added BEFORE the art it covers, which still draws on top; the chevron and the
## caption both ignore the mouse, so the click lands here. Clicking Back is Esc and clicking
## Next is [9], emitted through the same signals the keys use, so every screen that already
## handles those keys is clickable for free.
func _nav_hit(rect: Rect2, on_click: Callable, enabled := true) -> Control:
	var c := Control.new()
	c.position = rect.position
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if enabled:
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		c.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed \
					and e.button_index == MOUSE_BUTTON_LEFT:
				on_click.call()
				c.accept_event())
	add_child(c)
	return c

func _build_side_nav() -> void:
	var vp := get_viewport_rect().size
	var ah: int = int(round(vp.y * 0.0306))   # 33px at 1080 — Qud's chevron height
	# the two hit boxes go down FIRST so the chevrons and captions draw over them
	_nav_hit(Rect2(vp.x * 0.012, vp.y * 0.470, vp.x * 0.098, vp.y * 0.086),
		func(): _nav_back())
	_nav_hit(Rect2(vp.x * 0.888, vp.y * 0.470, vp.x * 0.100, vp.y * 0.086),
		func(): _nav_next(), _next_enabled())
	var la := _make_arrow(true, NAV_ARROW, ah)
	la.position = Vector2(vp.x * 0.033, vp.y * 0.485)
	add_child(la)
	# The bracketed KEY is gold and the word beside it is not — the same split Qud uses for
	# "[R] Randomize Selection" and "[Space] select", and which this caption was missing. Measured:
	# Qud's "[Esc]" carries yellow pixels peaking at (174,169,62) while "Back" peaks at (177,201,195).
	var lb := _rich("[color=#%s][lb]Esc[rb][/color][color=#%s] Back[/color]"
		% [SEL_GOLD.to_html(false), HINT_TEXT.to_html(false)], "caption")
	lb.position = Vector2(vp.x * 0.02, vp.y * 0.525)
	add_child(lb)
	var nxt: bool = _next_enabled()
	var ra := _make_arrow(false, NAV_ARROW if nxt else DIM, ah)
	ra.position = Vector2(vp.x * 0.955, vp.y * 0.485)
	add_child(ra)
	# "Num 9", not "9" — Qud names the KEYPAD key, and the caption is 110px wide against Raves' 82.
	# DISABLED loses the gold too: Qud's Next caption has no yellow pixel anywhere while it is dim.
	var rb := _rich("[right][color=#%s][lb]Num 9[rb][/color][color=#%s] Next[/color][/right]"
		% [(SEL_GOLD if nxt else DIM).to_html(false), (HINT_TEXT if nxt else DIM).to_html(false)],
		"caption")
	rb.position = Vector2(vp.x * 0.90, vp.y * 0.525)
	rb.size = Vector2(vp.x * 0.085, 0)
	add_child(rb)

## Qud's side chevron is a THIN two-segment stroke, not a filled glyph. Measured on the caste
## screen: 18 wide x 33 tall with a 3px stroke, tip toward the screen edge.
##
## DRAWN, not blitted. nav_arrow.png is a 15x15 sprite and this used to stretch it into a 43px box —
## a 2.9x upscale that turned the stroke into a ~15px blob, five times Qud's. No sprite scaling can
## fix that either: Qud's chevron is 18x33, an aspect a square source cannot reach.
func _make_arrow(left: bool, color: Color, h: int) -> Control:
	var w := int(round(h * 0.545))          # Qud 18 wide against 33 tall
	# 2.1px at h=33, which MEASURES as Qud's 3. The stroke runs at ~45 degrees and a diagonal line's
	# horizontal cross-section is width/sin(angle), so a line drawn 3px wide profiles as ~4.2 —
	# asking for 3 directly came out 5 against Qud's 3.
	var t := maxf(1.0, h * 0.064)
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var back := float(w) - t * 0.5      # the two open ends, at the edge away from the tip
		var tip := t * 0.5
		var x0 := back if left else tip
		var x1 := tip if left else back
		c.draw_line(Vector2(x0, tip), Vector2(x1, h * 0.5), color, t)
		c.draw_line(Vector2(x1, h * 0.5), Vector2(x0, float(h) - tip), color, t))
	return c

# ══ layout: centre column (emblem, titles, cards, flavour, hint) ═══════════════════

func _build_center() -> void:
	var vp := get_viewport_rect().size
	var em := TextureRect.new()
	em.stretch_mode = TextureRect.STRETCH_SCALE
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(em)
	_emblem_rect = em
	var etex := _load_emblem()
	_emblem_extracted = etex != null
	# NOTHING when it has not been extracted yet -- the poll above fills it in as soon as the
	# sprite lands. The old fallback drew a hand-coded approximation of Qud's sheaf, which meant
	# the screen showed a crown that exists nowhere in Qud and looked, correctly, wrong.
	_set_emblem(etex)
	var cc := _text("character creation", CC_GOLD, "big")
	cc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cc.anchor_left = 0.0; cc.anchor_right = 1.0
	cc.position.y = vp.y * _y_title()
	add_child(cc)
	_col_title = cc
	var sub := _text(_subtitle(), SUB_TEAL, "caption")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.anchor_left = 0.0; sub.anchor_right = 1.0
	sub.position.y = vp.y * _y_subtitle()   # initial; the cascade re-places it (see _layout_column)
	add_child(sub)
	_col_sub = sub

	_build_body(vp)

## THE BODY HOOK. The default body is the card row + description + deco + randomize line + nav
## hint — every ":choose …:" screen. A summary-style screen (no cards, panel layout) overrides
## this and keeps all the chrome above (emblem, title, subtitle, breadcrumb, side nav) for free.
func _build_body(vp: Vector2) -> void:
	var card_w := int(vp.x * _card_w_frac())
	var card_h := int(vp.y * _card_h_frac())
	_border_tex = _dashed_border_tex(card_w, card_h)
	_frame_tex = _load_card_frame()
	_frame_extracted = _frame_tex != null
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(vp.x * _card_gap_frac()))
	row.anchor_left = 0.0; row.anchor_right = 1.0
	row.position.y = vp.y * _y_cards()   # tuck the cards just under the subtitle, as in Qud (was 0.5 — too low)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_col_row = row
	# Qud widens the pitch across an ARCOLOGY BOUNDARY: its caste cards measure
	# [120,120,120,140,120,120,120,140,120,120,120] at 1920x1080 — four cards per band, +20px where
	# one band ends and the next begins. Without it Raves' row was uniform and finished ~56px narrower
	# than Qud's, and the bands sat too close to read as separate groups. A zero-width spacer with a
	# minimum size is enough; the row's own separation lands on both sides of it, so ask for the
	# DIFFERENCE rather than the whole gap.
	var band_break := {}
	for b in _category_bands():
		var last := int(b.get("start", 0)) + int(b.get("count", 0)) - 1
		if last >= 0 and last < _items.size() - 1:
			band_break[last] = true
	for i in range(_items.size()):
		var cell := _build_card(_items[i], i, card_w, card_h)
		row.add_child(cell)
		# The break goes INSIDE the last card's cell, not between cells in the row. As a row child a
		# spacer collects the row's separation on BOTH sides, so a boundary cost 2*gap + spacer and
		# could not be tuned down to Qud's 140 once the gap reached 23 — it measured 143 with the
		# spacer already clamped to zero. Inside the cell (whose own separation is 0) it adds exactly
		# its own width: col + break + gap = 95 + 20 + 25 = 140.
		if band_break.has(i):
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(_band_break_px(), 0)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(spacer)
	_build_bands()
	# ALWAYS, and NOT from inside _build_bands. This schedules `_size_names`, which every card
	# screen needs, and band positioning, which only some do -- and it used to be the last line of
	# _build_bands, below its `if bands.is_empty(): return`. So the screens WITHOUT category bands
	# (game mode, character type, genotype) never sized their name wrappers, the wrappers stayed
	# 0px tall, and the hotkey rode up over the name exactly as _size_names' own comment warns.
	# Choose Caste has bands and was fine, which is why this read as "some screens are wrong".
	_layout_deferred()

	_desc = _rich("", "body")
	_desc.position = Vector2(vp.x * 0.393, vp.y * _y_desc())   # left-justified, as in Qud (not centred)
	_desc.custom_minimum_size.x = vp.x * 0.32
	add_child(_desc)
	# the blocked-card warning, under the description and centred — see _card_blocked
	_warn = _rich("", "body")
	# fit_content (from _rich) sizes a label to its CONTENT, which beats autowrap and ran the
	# warning off the right edge — a wrapped column needs it off and an explicit width.
	_warn.fit_content = false
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# WIDE ENOUGH TO CLEAR THE DECO. At 0.44 the last line wrapped and landed on the three-dot
	# knob at 0.8333; the column is sized so a four-line warning finishes above it.
	_warn.position = Vector2(vp.x * 0.225, vp.y * (_y_desc() + 0.075))
	_warn.size = Vector2(vp.x * 0.55, vp.y * 0.14)
	_warn.custom_minimum_size = _warn.size
	add_child(_warn)

	# The three-dot deco under the description. Measured off Qud's caste screen: three 5px dots
	# centred at (959,900) at 1920x1080, offsets (0,-4), (-9,+4), (+9,+4). The spread is NOT
	# symmetric — twice as wide as it is tall — so one `d` for both axes cannot describe it. Raves
	# drew 9px dots at +-11 on both axes at y837: bigger, rounder and ~60px too high.
	#
	# Drawn rather than blitted from deco_knob.png, which was the previous approach and could not
	# reach the right colour. That sprite carries Qud's art colour (58,80,92) baked in, and a
	# TextureRect's modulate MULTIPLIES, so asking for (91,122,138) rendered (21,38,50) — exactly
	# the product. Getting there from the sprite would need a modulate above 1.0 to brighten it.
	# At 5px Qud's dots are solid blocks anyway, so a ColorRect is both exact and one less
	# dependency on an extracted asset being present.
	_make_deco()

	var rnd := _rich("[center][url=r][color=#%s][lb]R[rb][/color][color=#%s] Randomize Selection[/color][/url][/center]" % [
		SEL_GOLD.to_html(false), MUTED.to_html(false)], "body")
	rnd.anchor_left = 0.0; rnd.anchor_right = 1.0
	rnd.position.y = vp.y * Y_RANDOMIZE
	add_child(rnd)
	_clickable_foot(rnd, {"r": _randomize})

	var hint := _rich("", "caption")
	hint.anchor_left = 0.0; hint.anchor_right = 1.0
	hint.position.y = vp.y * Y_HINT
	var ih := int(round(UiFont.px(get_viewport(), "caption") * 1.15))
	hint.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	var icon := QudChrome.nav_icon(ih, SEL_GOLD)
	hint.add_image(icon, icon.get_width(), icon.get_height())
	hint.append_text("[color=#%s] navigate      [/color][color=#%s][lb]Space[rb][/color][color=#%s] select[/color]" % [
		MUTED.to_html(false), SEL_GOLD.to_html(false), MUTED.to_html(false)])
	hint.pop()
	add_child(hint)

func _build_card(m: Dictionary, idx: int, cw: int, ch: int) -> Control:
	var cell := HBoxContainer.new()
	# ZERO, not 4. The cell held a caret next to the column and needed a gap; the caret is an overlay
	# now, so the only thing this separation can still reach is the band-break spacer — where it
	# would silently add 4px to every boundary.
	cell.add_theme_constant_override("separation", 0)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_entered.connect(func(): _engage(); _select(idx))
	cell.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_engage(); _select(idx); _confirm())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let clicks fall through to the cell's gui_input
	cell.add_child(col)
	var boxc := Control.new()
	boxc.custom_minimum_size = Vector2(cw, ch)
	boxc.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (default STOP would swallow the click → no select)
	var border := NinePatchRect.new()
	border.modulate = DIM_BORDER
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_card_frame(border)
	boxc.add_child(border)
	# The caret is an OVERLAY on the card box, not a column of its own. As an HBox child it reserved
	# 12px + 4px separation in EVERY card, selected or not, inflating the pitch by 16px twelve times
	# over: Raves measured a 134px card pitch against Qud's 120, and because the band rules are
	# positioned FROM the cards they inherited it (Raves' header row spanned 1587px against Qud's
	# 1495). Qud draws its caret in the GAP beside the selected card and reserves nothing for the
	# rest, so this hangs outside the box's left edge and costs no layout width.
	var caret := _text("›", SEL_GOLD, "big")
	caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boxc.add_child(caret)
	caret.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	caret.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	caret.position.x = -13
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The vertical inset SETS THE SPRITE SIZE: these tiles are taller than they are wide, so the icon
	# area's height is what STRETCH_KEEP_ASPECT_CENTERED scales against and the horizontal inset never
	# binds. At 10 the sprite came out ~20% too big on every card screen -- measured ink 33x60 against
	# Qud's 28x50 on Choose Caste, and 42x51 against 35x43 on Choose Genotype, i.e. 1.18-1.20 in both
	# places. 16 puts the area at 60px tall and the sprite on Qud's size.
	#
	# NOTE these four are literal px while the card box around them is a fraction of the viewport, so
	# they do not track window height the way everything else here does. Correct at 1920x1080, which
	# is what 1:1 runs at; a different window size would drift.
	icon.offset_left = 12; icon.offset_right = -12; icon.offset_top = 16; icon.offset_bottom = -16
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boxc.add_child(icon)
	col.add_child(boxc)
	var nm := _text(str(m.get("display", m.get("name", "?"))), NAME_DIM, "caption")
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# THE NAME IS NOT A COLUMN CHILD, it sits in a wrapper — because a container sizes its children
	# to its own width, so as a direct child the label could never be wider than the column, and its
	# minimum width DROVE that column. Widening it to fit "Priest of All Suns" the way Qud does
	# (two lines, not three) dragged the card pitch from 119 to 139 against Qud's 120.
	#
	# Qud has no such coupling: "Horticulturist" is 118px over a 97px card and its neighbours do not
	# move. The wrapper reserves exactly the column width; the label inside is anchored full-rect
	# with negative side offsets, so it stays NAME_OVERFLOW px wider and spills symmetrically over
	# the cards either side without contributing a pixel to layout.
	# WORD, not WORD_SMART. Qud wraps a card name only at spaces and lets a single long word overflow
	# its card -- "Horticulturist", "Syzygyrior" and "Praetorian" all sit on one line, wider than the
	# frame under them. (Qud breaks "Priest of All Suns" across TWO lines, not three; Raves takes
	# three because its font's advance is ~1px per character wider at the same cap height -- 9.4px
	# against Qud's 8.43, measured on "Horticulturist" at 132px against 118 with an identical 11px
	# glyph height. That is a font-face metric difference, so it cannot be fixed by changing the font
	# SIZE without losing the matching height.) WORD_SMART instead breaks
	# INSIDE words when they do not fit, which on Choose Caste produced "Horticul/turist" and
	# "Praetori/an". It never showed up on the mode and genotype screens because nothing there is
	# longer than its card.
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	var nmwrap := Control.new()
	nmwrap.custom_minimum_size = Vector2(cw, 0)   # height set in _size_names once laid out
	nmwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nmwrap)
	nmwrap.add_child(nm)
	nm.set_anchors_preset(Control.PRESET_FULL_RECT)
	nm.offset_left = -NAME_OVERFLOW
	nm.offset_right = NAME_OVERFLOW
	var hk := _text("[%s]" % str(m.get("hotkey", "")), HOTKEY_DIM, "caption")
	hk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hk.custom_minimum_size = Vector2(cw, 0)
	col.add_child(hk)
	_cards.append({"cell": cell, "col": col, "boxc": boxc, "border": border, "icon": icon,
		"name": nm, "namewrap": nmwrap, "hotkey": hk, "caret": caret})
	return cell

# ══ category bands (Choose Caste's arcology headers) ═══════════════════════════════

## One dash-ruled header per band, each spanning exactly its own run of cards.
##
## Built as an HBox — [rule][label][rule] — rather than a padded string of "─" characters, because
## the fill has to reach the group's real edges and a character count only reaches them by accident:
## the three arcology names differ in length by more than a card's width, so Qud's own rules are
## visibly different lengths. Letting two expanding rules take up the slack gets that for free at any
## font size or window width.
##
## Positioned AFTER layout (deferred), for the same reason _position_sel_frame is: an HBoxContainer
## has no meaningful child rects until the container has run, so measuring the card columns on the
## build frame would place every band at x=0 with zero width.
var _bands: Array = []

func _build_bands() -> void:
	var bands := _category_bands()
	if bands.is_empty():
		return
	for b in bands:
		var holder := HBoxContainer.new()
		holder.add_theme_constant_override("separation", 6)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The band name arrives as Qud markup ("{{G|The Toxic Arboreta…}}") straight out of
		# chargen.json, so the colour is IN the string — take it from the first run rather than
		# making the subclass restate it, which would be a second place for it to go stale.
		var plain := ""
		var col := MUTED
		var first := true
		for run in QudText.runs(str(b.get("display", "")), _palette, MUTED):
			plain += str(run[0])
			if first:
				col = run[1]
				first = false
		var lrule := _dash_rule(BAND_RULE, -1)
		var label := _text(plain, col, "caption")
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rrule := _dash_rule(BAND_RULE, 1)
		holder.add_child(lrule)
		holder.add_child(label)
		holder.add_child(rrule)
		add_child(holder)
		_bands.append({"holder": holder, "start": int(b.get("start", 0)), "count": int(b.get("count", 0))})

## Extra width given to the LAST card of a category, so the next band starts further along. Qud runs
## a 140px pitch across a band boundary against 120 within one, i.e. exactly 20px more.
func _band_break_px() -> float:
	return round(get_viewport_rect().size.x * 0.0104)   # 20px at 1920

## A horizontal dashed rule that eats whatever width the label leaves, END-CAPPED with a vertical
## tick on its outer side (`cap` = -1 for the left rule, +1 for the right).
##
## The cap is not decoration. Without it the three arcology rules run off both edges into each other
## and the header row reads as ONE continuous strip of text rather than three labels each owning its
## own four cards -- which is exactly how it was misread. Qud draws "─┤ The Ice-Sheathed Arcology of
## Ibul ├─": the rule visibly starts and stops around its group.
func _dash_rule(col: Color, cap := 0) -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(8, 2)
	c.draw.connect(func():
		var w := c.size.x
		var y := c.size.y * 0.5
		var x := 0.0
		while x < w:
			c.draw_rect(Rect2(x, y, minf(4.0, w - x), 1.0), col)
			x += 7.0
		if cap != 0:
			var cx := 0.0 if cap < 0 else w - 1.0
			c.draw_rect(Rect2(cx, y - 3.0, 1.0, 7.0), col))
	return c

## Give each name wrapper the height its (already wider) label actually needs. A Control does not
## size itself to its children, so without this the wrapper stays 0px tall and the hotkey rides up
## over the name. Deferred because the label's wrapped height is only knowable once it has been laid
## out at its real width.
func _size_names() -> void:
	for c in _cards:
		var w: Control = c.get("namewrap")
		var l: Label = c.get("name")
		if w == null or l == null:
			continue
		var h := l.get_minimum_size().y
		if h > 0.0 and absf(w.custom_minimum_size.y - h) > 0.5:
			w.custom_minimum_size.y = h

## The post-build layout pass EVERY card screen runs. Named for what it does rather than for the
## bands, which are the optional half: `_size_names` is the part with no opt-out, and burying this
## behind a bands check is what put the hotkey on top of the name on three screens.
func _layout_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_size_names()
	await get_tree().process_frame   # let the row re-flow at the new name heights
	_layout_column()

func _position_bands() -> void:
	if _bands.is_empty():
		return
	var vp := get_viewport_rect().size
	for b in _bands:
		var lo: int = b["start"]
		var hi: int = lo + b["count"] - 1
		if lo < 0 or hi >= _cards.size() or b["count"] <= 0:
			continue
		var a: Control = _cards[lo].get("col")
		var z: Control = _cards[hi].get("col")
		if a == null or z == null:
			continue
		var x0 := a.get_global_rect().position.x
		var x1 := z.get_global_rect().end.x
		if x1 - x0 <= 1.0:
			continue
		# Qud's rules run PAST the cards they head, not flush with them: its band row spans x212-1707
		# against card frames at x231-1688, i.e. ~19px proud at each end. Flush looked deliberate and
		# measured wrong.
		# Back to ~19px each side (0.0099), which is what Qud measures: its band row spans x212-1707
		# against card frames at x231-1688. It was halved to 0.005 because adjacent bands were meeting
		# with no room for their end caps — but the real cause of that was the card row having NO
		# inter-band break, so the bands were butted together before the outset ever mattered. With
		# the break restored (see _band_break_px) the full outset fits and Qud's visible gap between
		# one arcology's rule and the next comes back.
		var out := vp.x * 0.0099
		var h: Control = b["holder"]
		h.position = Vector2(x0 - out, vp.y * _y_bands())
		h.size = Vector2((x1 - x0) + out * 2.0, h.size.y)

# ══ guided-tutorial extras ═════════════════════════════════════════════════════════

## The onboard highlight is the target card's OWN dotted frame drawn in bright yellow (no second box),
## so it reads as one frame like Qud's. It drops to the normal (darker) colour the moment the player
## engages a card — see `_engage()` + `_apply_selection()`.

## The guided "TUTORIAL GUIDE" popup, in Qud's frame style: a dark panel with the dotted frame border
## (same tiny-frame-h as the cards, dim), a BRIGHT-YELLOW square at each of the 4 corners, and a title
## rule — "TUTORIAL GUIDE" (gold) centred in a muted horizontal line — then the body text.
func _build_guide() -> void:
	var vp := get_viewport_rect().size
	var pw := vp.x * 0.245
	var ph := vp.y * 0.30
	var panel := Control.new()
	panel.position = Vector2(vp.x * 0.182, vp.y * 0.185)
	panel.size = Vector2(pw, ph)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# Border = Qud's panel-border texture (borderTop/Bot/Side): a teal/near-black checkerboard, tiled
	# to fill the panel; an inset background then leaves it showing only as a band around the edge.
	var hatch := TextureRect.new()
	hatch.texture = _hatch_tex(int(pw), int(ph), Color8(46, 99, 105), Color8(0, 21, 20))
	hatch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hatch.stretch_mode = TextureRect.STRETCH_SCALE
	hatch.set_anchors_preset(Control.PRESET_FULL_RECT)
	hatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hatch)

	var bw := 6.0   # border-band thickness
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.09, 0.09, 1.0)
	bg.position = Vector2(bw, bw)
	bg.size = Vector2(pw - bw * 2.0, ph - bw * 2.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	# 4 bright-yellow squares centred on the N / S / E / W band midpoints — the only breaks in the band
	var sq := 9.0
	for mid in [
		Vector2((pw - sq) * 0.5, (bw - sq) * 0.5),        # N
		Vector2((pw - sq) * 0.5, ph - (bw + sq) * 0.5),   # S
		Vector2((bw - sq) * 0.5, (ph - sq) * 0.5),        # W
		Vector2(pw - (bw + sq) * 0.5, (ph - sq) * 0.5),   # E
	]:
		var s := ColorRect.new()
		s.color = BRIGHT_GOLD
		s.position = mid
		s.size = Vector2(sq, sq)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(s)

	# title rule: [line] TUTORIAL GUIDE [line], near the top
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 10)
	trow.position = Vector2(18, 20)
	trow.size = Vector2(pw - 36, 18)
	trow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trow.add_child(_rule_seg())
	var hdr := _text(guide_title, SEL_GOLD, "caption")
	trow.add_child(hdr)
	trow.add_child(_rule_seg())
	panel.add_child(trow)

	var body := _rich("", "caption")
	body.add_theme_font_size_override("normal_font_size", int(vp.y * 0.0155))   # smaller — fits the box, as in Qud
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.position = Vector2(20, 52)
	body.size = Vector2(pw - 40, ph - 66)
	panel.add_child(body)
	_guide_body_label = body
	_update_guide_body(guide_body)

## Set the popup body text (muted), used for both the initial text and the live tip once captured.
func _update_guide_body(txt: String) -> void:
	if _guide_body_label == null:
		return
	_guide_body_label.text = "[color=#%s]%s[/color]" % [
		Color8(0x9C, 0xB0, 0xAC).to_html(false), txt.replace("[", "[lb]")]

## A horizontal rule segment for the title bar (expands to fill its side).
func _rule_seg() -> ColorRect:
	var r := ColorRect.new()
	r.color = MUTED
	r.custom_minimum_size = Vector2(0, 1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ══ selection ══════════════════════════════════════════════════════════════════════

func _select(idx: int) -> void:
	if idx < 0 or idx >= _cards.size() or idx == _sel:
		return
	_sel = idx
	_apply_selection()

## The player has engaged a card (hovered, arrowed, or clicked) — retire the onboarding highlight so
## the steered card follows the normal selected/unselected colours from here on.
func _engage() -> void:
	if not _onboard_active:
		return
	_onboard_active = false
	_apply_selection()

# ══ the big selection frame (Qud's solid-yellow corner-bracket highlight) ═════════════

## A single frame that boxes the SELECTED card, generously larger than the card (overlapping toward
## its neighbour, exactly as Qud draws it). Bright yellow while it's still the onboarding steer, the
## normal darker gold once the player has engaged. The card's own dotted frame stays dim underneath.
func _ensure_sel_frame() -> void:
	if _items.is_empty():
		return
	if _sel_frame != null:
		return
	var np := NinePatchRect.new()
	# Qud's real selection frame — the "polat-locator-big" sprite (139×186, 9-slice border 16/15).
	# Extracted at runtime to sel_frame.png; procedural corner-brackets are only the fallback.
	var tex := _load_title_sprite("sel_frame.png")
	var ml := 16; var mr := 16; var mt := 15; var mb := 15
	if tex == null:
		tex = _sel_frame_tex()
		ml = 20; mr = 20; mt = 20; mb = 20
	np.texture = tex
	np.patch_margin_left = ml; np.patch_margin_right = mr
	np.patch_margin_top = mt; np.patch_margin_bottom = mb
	np.draw_center = false
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.visible = false
	add_child(np)
	_sel_frame = np

func _init_sel_frame_deferred() -> void:
	if _items.is_empty():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_position_sel_frame()

## True when the selected card is marked by recolouring its OWN dotted frame rather than by the big
## locator sprite. Qud does this wherever the cards are packed tightly — measured on Choose Caste,
## where the highlight is exactly the card box (x231..328, y507..615 for card [A], i.e. 97x108) drawn
## in #cfc041, dotted, with the same dash pattern as the unselected frames. It is emphatically NOT
## the locator: that whole box lights only 159 pixels, where a solid frame of the same size lights
## over a thousand.
##
## The locator is still right on the roomy screens (genotype's two big cards), so this is a hook
## rather than a change of behaviour for everyone.
func _sel_uses_card_frame() -> bool:
	return false

func _position_sel_frame() -> void:
	if _sel_frame != null and _sel_uses_card_frame():
		_sel_frame.visible = false
		return
	if _sel_frame == null or _sel < 0 or _sel >= _cards.size():
		return
	var col: Control = _cards[_sel].get("col")
	if col == null:
		return
	var r := col.get_global_rect()   # self is at (0,0) full-rect, so global == local
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return
	var vp := get_viewport_rect().size
	var pl := vp.x * 0.024
	var pr := vp.x * 0.024
	var pt := vp.y * _sel_pad_top_frac()   # top edge lands on the subtitle line, as in Qud
	var pb := vp.y * 0.0185  # bottom edge clears the hotkey and stops above the flavour line
	# NEVER ABOVE THE TITLE. The frame is drawn from the card COLUMN, which grows with its own
	# wrapped name, so on a screen with tall cards its top edge climbed into "character creation"
	# and struck through the words. The cascade reserves the overhang; this is the guarantee.
	# The rail wants the GAP between the title and the subtitle: below the title'"'"'s ink, above the
	# subtitle'"'"'s. Clamped to the title first, because clearing the title is the guarantee and
	# missing the subtitle is only the preference — when the gap is too small for both, the
	# subtitle is the one Qud draws inside the frame anyway.
	var top: float = maxf(r.position.y - pt, _title_bottom + 2.0)
	if _sub_top > _title_bottom + 4.0:
		top = minf(top, _sub_top - 2.0)
	top = maxf(top, _title_bottom + 2.0)
	_sel_frame.position = Vector2(r.position.x - pl, top)
	_sel_frame.size = Vector2(r.size.x + pl + pr, r.position.y + r.size.y + pb - top)
	_sel_frame.modulate = BRIGHT_GOLD if (_onboard_active and _sel == onboard_index) else SEL_GOLD
	_sel_frame.visible = true

## Procedural frame art: a thin continuous border with a bold L bracket at each corner. Rendered as a
## NinePatch (corner = bracket, drawn 1:1; edges = the thin line, stretched), white → modulated gold.
func _sel_frame_tex() -> ImageTexture:
	var s := 56
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(1, 1, 1, 1)
	var t := 2     # thin connecting line
	var bl := 20   # corner-bracket arm length (== patch_margin)
	var bt := 3    # corner-bracket thickness
	for i in range(s):
		for k in range(t):
			img.set_pixel(i, k, c)
			img.set_pixel(i, s - 1 - k, c)
			img.set_pixel(k, i, c)
			img.set_pixel(s - 1 - k, i, c)
	for cn in [[0, 0, 1, 1], [s - 1, 0, -1, 1], [0, s - 1, 1, -1], [s - 1, s - 1, -1, -1]]:
		var cx: int = cn[0]; var cy: int = cn[1]; var dx: int = cn[2]; var dy: int = cn[3]
		for a in range(bl):
			for k in range(bt):
				img.set_pixel(cx + dx * a, cy + dy * k, c)
				img.set_pixel(cx + dx * k, cy + dy * a, c)
	return ImageTexture.create_from_image(img)

func _apply_selection() -> void:
	if _items.is_empty():
		return
	for i in range(_cards.size()):
		var on: bool = (i == _sel)
		var c: Dictionary = _cards[i]
		# Normally each card's own dotted frame stays dim and the big _sel_frame is the highlight —
		# but on a dense row Qud highlights by RECOLOURING the card's own frame instead (see
		# _sel_uses_card_frame), which is why this is not unconditionally DIM_BORDER.
		c["border"].modulate = SEL_GOLD if (on and _sel_uses_card_frame()) else DIM_BORDER
		if c.has("colored"):
			c["icon"].texture = c["colored"] if on else c["neutral"]
			c["icon"].modulate = ICON_SEL if on else ICON_DIM
		c["name"].add_theme_color_override("font_color", NAME_SEL if on else NAME_DIM)
		c["hotkey"].add_theme_color_override("font_color", SEL_GOLD if on else HOTKEY_DIM)
		c["caret"].add_theme_color_override("font_color", SEL_GOLD if on else Color(0, 0, 0, 0))
	if _desc != null and _sel >= 0 and _sel < _items.size():
		var lines := PackedStringArray()
		for line in str(_items[_sel].get("desc", "")).split("\n", false):
			lines.append(QudText.to_bbcode(line, _palette))
		_desc.text = "[color=#%s]%s[/color]" % [MUTED.to_html(false), "\n".join(lines)]
	if _refusal != null and is_instance_valid(_refusal):
		_refusal.queue_free()   # moving off the card answers the refusal; the X goes with it
		_refusal = null
	if _warn != null:
		var why := ""
		if _sel >= 0 and _sel < _items.size():
			why = _card_blocked(str(_items[_sel].get("name", "")))
		_warn.text = "[center][color=#%s]%s[/color][/center]" % [WARN_AMBER.to_html(false), why] \
			if why != "" else ""
		# A four-line refusal pushed past the description can reach the three-dot deco, and a
		# knob printed through the sentence explaining the refusal is worse than no knob. The
		# deco is decoration; the warning is the reason the player cannot have the card.
		for k in _deco_knobs:
			if is_instance_valid(k):
				k.visible = why == ""
		# deferred: the description and warning have not laid out the text we just gave them, and
		# their heights are the whole input to where everything under them goes
		_layout_column.call_deferred()
	_position_sel_frame()

func _randomize() -> void:
	if _items.size() > 1:
		var n := _sel
		while n == _sel:
			n = randi() % _items.size()
		_select(n)

func _confirm() -> void:
	if _sel >= 0 and _sel < _items.size():
		var nm := str(_items[_sel].get("name", ""))
		if _card_blocked(nm) != "":
			# the warning is already on screen; ANSWER the click as well as refusing it —
			# a press that changes nothing at all reads as a broken button
			_flash_refusal()
			return
		selected = nm
		chose.emit(selected)

## A Qud-red X struck across the blocked card, for ~2s. Drawn over the card's own column so it
## lands inside the frame whatever the card's size, and freed on its own timer — a refusal the
## player can SEE, which a silent no-op is not.
func _flash_refusal() -> void:
	if _sel < 0 or _sel >= _cards.size():
		return
	var col: Control = _cards[_sel].get("col")
	if col == null:
		return
	var r := col.get_global_rect()
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return
	if _refusal != null and is_instance_valid(_refusal):
		_refusal.queue_free()
	var x := Control.new()
	x.position = r.position
	x.size = r.size
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: float = maxf(2.0, r.size.y * 0.055)
	var pad: float = r.size.x * 0.12
	x.draw.connect(func():
		var w := x.size.x
		var h := x.size.y
		x.draw_line(Vector2(pad, pad), Vector2(w - pad, h - pad), REFUSE_RED, t)
		x.draw_line(Vector2(w - pad, pad), Vector2(pad, h - pad), REFUSE_RED, t))
	add_child(x)
	_refusal = x
	var tm := get_tree().create_timer(2.0)
	tm.timeout.connect(func():
		if is_instance_valid(x):
			x.queue_free())

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_nav_back(); accept_event()
	elif e.is_action_pressed("ui_right"):
		_engage(); _select(mini(_sel + 1, _cards.size() - 1)); accept_event()
	elif e.is_action_pressed("ui_left"):
		_engage(); _select(maxi(_sel - 1, 0)); accept_event()
	elif e.is_action_pressed("ui_accept"):
		_confirm(); accept_event()
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_R:
		_randomize(); accept_event()
	elif e is InputEventKey and e.pressed and not e.echo \
			and (e.keycode == KEY_9 or e.keycode == KEY_KP_9) and _next_enabled():
		# THE NEXT AFFORDANCE, wired at last: the side nav has drawn "[9] Next" since the first
		# card screen, and the signal existed, but nothing ever emitted it — found the moment a
		# screen (the summary) actually needed it. Subclasses opt in via _next_enabled().
		_nav_next(); accept_event()

# ══ extracted-sprite chrome ════════════════════════════════════════════════════════

func _apply_card_frame(np: NinePatchRect) -> void:
	if _frame_tex != null:
		np.texture = _frame_tex
		var m := int(round(_frame_tex.get_height() * 17.0 / 80.0))
		np.patch_margin_left = m; np.patch_margin_right = m
		np.patch_margin_top = m; np.patch_margin_bottom = m
	else:
		np.texture = _border_tex
		for s in ["left", "top", "right", "bottom"]:
			np.set("patch_margin_" + s, 0)
	np.draw_center = false
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _load_card_frame() -> Texture2D:
	return _load_title_sprite("card_frame.png")

## THE ONE CROWN — see QudChrome.emblem(). This used to load the sprite itself and fall back to a
## hand-drawn approximation; both are gone, because two copies of one picture is how they drift.
func _load_emblem() -> Texture2D:
	return QudChrome.emblem()

func _set_emblem(tex: Texture2D) -> void:
	if _emblem_rect == null or tex == null:
		return
	var vp := get_viewport_rect().size
	_emblem_rect.texture = tex
	var eh: int = int(vp.y * 0.042)
	var ew: int = int(eh * float(tex.get_width()) / float(tex.get_height()))
	# Sits just above the title, and must TRACK it: this was the literal 0.432 (i.e. _y_title() less
	# a 0.003 nudge), which put the sheaf straight through the middle of "character creation" the
	# moment Choose Caste raised the title block to make room for its arcology row.
	#
	# The +0.0045 is MEASURED, not nudged, and it corrects a gap that was wrong on every chargen
	# screen: row-profiling Qud against Raves put the emblem-to-title gap at 6px in Qud and 14px in
	# Raves, on the genotype screen as much as on Choose Caste. The same delta lands both, which is
	# what says it is one constant being wrong rather than two screens disagreeing.
	_emblem_rect.position = Vector2((vp.x - ew) * 0.5, vp.y * (_y_title() + 0.0045) - eh)
	_emblem_rect.size = Vector2(ew, eh)

func _load_title_sprite(fname: String) -> Texture2D:
	var path := InputModel.support_dir().path_join("title").path_join(fname)
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)

## Load an exported tile untouched (its native colours).
func _native_tile(tile: String) -> Texture2D:
	if tile == "":
		return null
	var fname := tile.replace("/", "_").replace("\\", "_")
	var path := InputModel.support_dir().path_join("tiles").path_join(fname)
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		if img.load(path) != OK:
			return null
	return ImageTexture.create_from_image(img)

## Load a tile and remap each opaque pixel two-tone by darkness (dark→main body, light→detail).
func _recolor_tile(tile: String, main: Color, detail: Color) -> Texture2D:
	if tile == "":
		return null
	var fname := tile.replace("/", "_").replace("\\", "_")
	var path := InputModel.support_dir().path_join("tiles").path_join(fname)
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		if img.load(path) != OK:
			return null
	img.convert(Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p := img.get_pixel(x, y)
			if p.a > 0.04:
				var cov: float = 1.0 - (p.r + p.g + p.b) / 3.0
				var col := detail.lerp(main, cov)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, p.a))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

# ══ procedural fallbacks (used until the extracted sprites land) ════════════════════

## A checkerboard fill — Qud's borderTop/Bot/Side panel-border texture (originally khaki + near-black
## `(0,21,20)`), here recoloured. It's a 2px-cell checkerboard: a pixel is `light` when (x/cell + y/cell)
## is even. Reads as a diagonal lattice; tiles seamlessly. Rendered NEAREST.
func _hatch_tex(w: int, h: int, light: Color, dark: Color, cell := 2) -> ImageTexture:
	var img := Image.create(maxi(2, w), maxi(2, h), false, Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			img.set_pixel(x, y, light if ((x / cell + y / cell) % 2 == 0) else dark)
	return ImageTexture.create_from_image(img)

func _dashed_border_tex(w: int, h: int, dash := 5, gap := 4, th := 2) -> ImageTexture:
	var img := Image.create(maxi(2, w), maxi(2, h), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(1, 1, 1, 1)
	var x := 0
	while x < w:
		for dx in range(mini(dash, w - x)):
			for t in range(th):
				img.set_pixel(x + dx, t, c)
				img.set_pixel(x + dx, h - 1 - t, c)
		x += dash + gap
	var y := 0
	while y < h:
		for dy in range(mini(dash, h - y)):
			for t in range(th):
				img.set_pixel(t, y + dy, c)
				img.set_pixel(w - 1 - t, y + dy, c)
		y += dash + gap
	return ImageTexture.create_from_image(img)

# ══ text helpers ═══════════════════════════════════════════════════════════════════

func _text(txt: String, col: Color, role := "body") -> Label:
	var l := Label.new()
	l.text = txt
	if role != "body":
		l.theme_type_variation = role.capitalize()
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _rich(bb: String, role := "body") -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if role != "body":
		l.theme_type_variation = role.capitalize()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = bb
	return l

# ══ the centre column, as ONE cascading pass ═══════════════════════════════════════
#
# WHY THIS EXISTS. Every row of a chargen screen used to be placed at its own measured
# fraction of the viewport, independently of the rows above it — title at _y_title(),
# cards at _y_cards(), flavour at _y_desc(), the deco at a literal 0.8333. That is fine
# while every row is the height it was measured at, and wrong the moment one is not:
# a location name that wraps to two lines, a genotype with five perk bullets, a blocked
# card's four-line refusal. Each collision then got its own patch — push the flavour
# below the cards, push the warning below the flavour, hide the deco when the warning
# reaches it — and the next longer string found the next gap. Daniel: "we need to fix
# this issue we've been kludging over and over."
#
# So the column is laid out ONCE, top to bottom, each row placed after the one above it:
# the ORDER is structural and cannot be violated by content. The measured constants stay
# — they are still where Qud puts these rows — but they now describe the GAP each row
# wants, not an absolute address it insists on. Nominal content lands exactly where it
# always did; longer content pushes what follows down instead of printing through it.
#
# The footer (randomize + hint) is pinned to the BOTTOM and the column grows into the
# slack between. When the slack runs out the footer is what gives, which is the right
# failure: a hint line low on the screen is readable, a hint line through the deco is not.

## Each row's measured HOME — where Qud puts it — is still the per-screen _y_* hook. The cascade
## treats those as MINIMUMS, not addresses: a row sits at its measured home unless the content
## above has already pushed past it, in which case it follows. Nominal content is therefore
## pixel-identical to the layout these constants were measured for, and longer content pushes
## instead of printing through.
const MIN_GAP := 0.006          # the smallest gap between two rows, as a fraction of height
const SUB_EXTRA := 0.008        # Daniel: "the row-to-row spacing between the title and the
                                # :choose xyz: is too small" — this is the whole widening
const Y_RANDOMIZE := 0.905      # Qud's, measured; the footer is pinned from the bottom up
const Y_HINT := 0.965

## Lay the column out. Safe to call at any time and as often as needed — it reads the live
## heights, so it is also the resize handler and the "the description just changed" handler.
func _layout_column() -> void:
	if _col_title == null or not is_instance_valid(_col_title):
		return
	var vp := get_viewport_rect().size
	var gap: float = vp.y * MIN_GAP
	var y: float = _stack(_col_title, vp.y * _y_title(), gap)
	_title_bottom = y - gap
	_sub_top = maxf(y, vp.y * (_y_subtitle() + SUB_EXTRA))
	y = _stack(_col_sub, _sub_top, gap)
	# A PANEL BODY MOVES AS A BLOCK. Its rows are built at measured offsets relative to each other,
	# so the cascade must not re-place them individually — but it does have to push the whole block
	# clear of a header that has grown. Without this the widened title gap slid the subtitle down
	# onto Customize's first row, which is the same collision from the other direction.
	if _body_top_home > 0.0 and not _body_nodes.is_empty():
		var shift: float = maxf(0.0, y - _body_top_home)
		if shift > 0.5:
			for n in _body_nodes:
				if n != null and is_instance_valid(n) and n is Control:
					(n as Control).position.y += shift
			_body_bot += shift
			_body_top_home += shift
	# THE SELECTION FRAME reaches ABOVE the card row, and that overhang is what was landing on the
	# title. Reserve it here so the frame has somewhere to be. Qud lets the frame enclose the
	# SUBTITLE, so only the title has to be cleared.
	var over: float = vp.y * _sel_pad_top_frac()
	if _col_row != null and is_instance_valid(_col_row):
		_col_row.position.y = maxf(maxf(y, vp.y * _y_cards()), _title_bottom + over)
		y = _col_row.position.y + _row_height() + gap
	y = _stack(_desc, maxf(y, vp.y * _y_desc()), gap)
	if _warn != null and is_instance_valid(_warn) and _warn.text != "":
		y = _stack(_warn, y, gap)
	_place_deco(maxf(y, _body_bottom()), vp)
	_position_bands()
	_position_sel_frame()

## Put `c` at `y`, and return the y the NEXT row starts at.
func _stack(c: Control, y: float, gap: float) -> float:
	if c == null or not is_instance_valid(c):
		return y + gap
	c.position.y = round(y)
	var h: float = c.size.y
	if c is RichTextLabel:
		h = maxf(h, (c as RichTextLabel).get_content_height())
	if h <= 1.0:
		h = c.get_minimum_size().y
	return y + h + gap

## The card row's height, which is the TALLEST card — the row itself can report 0 before its
## children have re-flowed at their measured name heights (see _size_names).
func _row_height() -> float:
	var h := 0.0
	for c in _cards:
		var col: Control = c.get("col")
		if col != null and is_instance_valid(col):
			h = maxf(h, col.size.y)
	if h <= 1.0 and _col_row != null and is_instance_valid(_col_row):
		h = _col_row.size.y
	return h

## The three-dot deco, at the top of whatever space is left under the column. It is the row
## the old layout kept colliding with, because it was the only one addressed absolutely.
func _place_deco(y: float, vp: Vector2) -> void:
	if _deco_knobs.is_empty():
		return
	var ks: int = maxi(3, int(round(vp.y * 0.0046)))
	var dx: int = maxi(2, int(round(vp.x * 0.0047)))
	var dy: int = maxi(1, int(round(vp.y * 0.0037)))
	# Qud's own resting place, unless the column has grown past it — then it follows the column.
	var oy: float = maxf(vp.y * _y_deco(), y + ks)
	# ...but never into the footer.
	oy = minf(oy, vp.y * _y_footer_top() - ks * 3.0)
	var cx: float = vp.x * 0.5
	var offs := [Vector2(0, -dy), Vector2(-dx, dy), Vector2(dx, dy)]
	for i in mini(_deco_knobs.size(), offs.size()):
		var k: ColorRect = _deco_knobs[i]
		if k == null or not is_instance_valid(k):
			continue
		k.position = Vector2(cx + offs[i].x - ks * 0.5, oy + offs[i].y - ks * 0.5)
		k.size = Vector2(ks, ks)

## The three teal knobs, created but NOT placed — _place_deco owns where they go. Shared, because
## three screens each carried their own copy of this loop with its own hard-coded y, which is the
## duplication that let each of them drift into its own content.
func _make_deco() -> void:
	if not _deco_knobs.is_empty():
		return
	var ks: int = maxi(3, int(round(get_viewport_rect().size.y * 0.0046)))
	for _i in 3:
		var k := ColorRect.new()
		k.color = DECO_KNOB
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.size = Vector2(ks, ks)
		add_child(k)
		_deco_knobs.append(k)

## Register what a PANEL body just drew, so the cascade can push it as a block. Used as:
##     var m := _body_mark()
##     ...build the panel...
##     _body_claim(m, top_y)
## Card screens need none of this — the cascade already knows their row.
func _body_mark() -> int:
	return get_child_count()

func _body_claim(mark: int, top_y: float) -> void:
	_body_nodes.clear()
	for i in range(mark, get_child_count()):
		_body_nodes.append(get_child(i))
	_body_top_home = top_y

## Make a footer line's bracketed keys CLICKABLE. `actions` maps a url id to the Callable that
## key already runs, so the click and the keypress go through one implementation and cannot drift.
##
## Every chargen footer names its keys — "[R] Randomize Selection", "[Delete] Reset Selection",
## "[E] Export Code to Clipboard" — and a named key on screen is something a player clicks.
## Wrap the segment in [url=id] and pass the same Callable the key handler calls.
func _clickable_foot(rich: RichTextLabel, actions: Dictionary) -> void:
	if rich == null:
		return
	rich.mouse_filter = Control.MOUSE_FILTER_STOP
	# MERGED, not replaced: a screen can have more than one footer line (the summary has its
	# export/save row and, in the Random lane, a reroll row) and the second call must not throw
	# away the first one's actions. Ids are unique per screen, which is what makes that safe.
	for k in actions:
		_foot_actions[k] = actions[k]
	if not rich.meta_clicked.is_connected(_on_foot_meta):
		rich.meta_clicked.connect(_on_foot_meta)

func _on_foot_meta(meta: Variant) -> void:
	var cb: Variant = _foot_actions.get(String(meta), null)
	if cb is Callable:
		(cb as Callable).call()
