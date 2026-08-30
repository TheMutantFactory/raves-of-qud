extends Node3D

## Emitted every snapshot with the raw Qud data, so a host (MainFrame) can drive its status bar /
## panels off the same stream the Holodeck renders — no second bridge connection needed.
signal snapshot(data: Dictionary)
## Re-broadcast of PopupOverlay.closed so the frame's screens can refresh (see
## StatusScreens._refresh_after_popup).
signal popup_closed
signal popup_option(text: String)   # a mirrored menu popup's picked option (plain text)

## Wires the bridge client to the renderer, drives the camera, and maps input to
## Qud movement commands. Built in code so the scene file stays a single node.
##
## CAMERA MODES — pick with the ` debug menu or SHIFT+number (the plain digit row is
## Qud's ability bar, CmdAbility1..10); the current mode
## and its controls show on screen.
##   1 COMPASS  (default)  cardinal-LOCKED low-angle view. Follows the player's
##                         position but NEVER rotates on movement, so the world
##                         doesn't spin under you. Q/E rotate the heading (45° default,
##                         90° toggle in the ` menu), R/F zoom. The stable, default view.
##   2 FOLLOW              rides behind your heading, looking ahead (trails movement).
##   3 FIRST_PERSON        at the player, eye-level, looking along the locked heading.
##   4 CINEMATIC           frames you + the selected tile, slowly orbiting (v1;
##                         combat-aware framing via an event buffer is future work).
##   5 MOUSE               orbit/pan with the mouse around the SELECTED tile.
##   6 KEYBOARD            free flight. WASD moves the camera, arrows AIM it.
##   7 TOP_FOLLOW          Qud-classic overhead: orthographic, straight down, NORTH up,
##                         tracking the player; R/F or the wheel zoom in and out.
##
##   Esc returns to COMPASS (and dismisses the report). Shift+C/K/F still jump to
##   mouse/keyboard/follow. Wheel zooms. Ctrl/Cmd+click or I inspects a tile.
##   F12                   -> save the viewport to <tilesDir>/../shot.png
##   Ctrl/Cmd + right-click -> photograph the CLEAN scene, then inspect (+ Qud shot)
##
## Terminology: "tile" here means a map square (Qud's Cell). Note the collision —
## the `tile` field on the wire is the sprite-art path. Code touching Qud's API
## keeps the name Cell.

var client: BridgeClient
var _wish_layer: CanvasLayer    # Ctrl+Shift+W wish prompt overlay (built lazily), sends "wish" to Qud
var _wish_edit: LineEdit
var _popup: PopupOverlay        # mirrors Qud modal popups forwarded by the mod (own file)
var _tutorial: CanvasLayer      # mirrors Qud's TUTORIAL GUIDE box (TutorialGuide.gd)
var _tomb: CanvasLayer          # mirrors Qud's end-of-run summary (TombstoneScreen.gd)
var _item_picker: PickerOverlay # mirrors Qud's PickGameObjectScreen (empty-slot equip picker)
var _cyber: Control            # mirrors Qud's cybernetics TERMINAL (the becoming nook)
var overlay_check: Callable = Callable()   # MainFrame: "is a frame overlay (status/controlmap) open?"
# Click-to-travel: where the left button went down, and how far it may travel and still count as a
# click rather than a camera-orbit drag. 6 px is a hand tremor at the trackpad; an orbit is tens.
var _travel_press = null        # Vector2 while the button is down, else null
const TRAVEL_SLOP := 6.0
var _binds := QudBinds.new()    # the player's Qud keybindings — custom-remap fallback routing
var _palette := QudPalette.markup()   # Qud colour map (code -> hex) for popup markup.
								# Seeded from the canonical table, then replaced by the
								# live one on the first snapshot -- see QudPalette.markup().
var _char_creator: CharacterCreator
var renderer: ZoneRenderer
var store := WorldStore.new()   # Phase-0 world store; renderer reads the live zone from it
var _prof_turns := 0            # for the periodic profile auto-dump
var inspector: CellInspector
var reporter: TileReport
var onboarding: OnboardingControl
var _font_preview: FontPreview

# Day/night atmosphere (sky bodies + MULTIPLY grade + time->tint) lives in SkyGrade.gd, fed each snapshot.
var _sky_grade                     # SkyGrade (Node3D); created in _ready
## Navigation beacons — the light columns the Locations panel arms (LocationBeacons.gd). A Node3D
## in the world, not an overlay: a beacon is a thing standing on the ground four parasangs away, and
## the camera has to be able to look away from it.
var _beacons                       # LocationBeacons (Node3D); created in _ready
## THE WALK BETWEEN CELLS. `_walk_to` is Qud's answer — a whole cell — and `_walk_at` is where the
## player is actually drawn, chasing it at a walking pace. See SmoothMove and _walk_step.
var _walk_to := Vector2.ZERO
var _walk_at := Vector2.ZERO
var _walk_seeded := false
const _SMOOTH := preload("res://SmoothMove.gd")
var _target                        # TargetCursor: Qud's target picker, mirrored
var _trade: TradeOverlay           # Qud's trade screen, mirrored
var _assist                        # MouseAssist (Node); created in _ready
var _assist_pos := Vector2(-1, -1) # last pointer position, re-read once a frame (see _process)

const SURFACE_Z := 10
var _depth := SURFACE_Z            # current stratum (zone.z); >SURFACE_Z is underground

# Vertical level stacking: how many strata BELOW the live zone still render (deeper
# ones cull off). Shallower levels never render (they'd occlude from above). The gap
# between levels is renderer.level_height (a ` menu slider).
const LEVEL_KEEP_DOWN := 2

# The camera rig (nodes + modes + placement math) lives in CameraRig.gd, created in _ready. Main keeps
# this enum as a MIRROR so its mode checks (input, snapshot, multiview) read `CamMode.X`; the values match
# CameraRig.CamMode exactly. `_cam_rig._mode` is the live mode. (Stage 1 of the Main.gd decomposition.)
enum CamMode { COMPASS, FOLLOW, FIRST_PERSON, CINEMATIC, MOUSE, KEYBOARD, TOP_FOLLOW, ADVENTURE,
	DRONECAM }
var _cam_rig                    # CameraRig (Node3D, loaded); created in _ready. Untyped so the headless
								# --check-only stays deterministic (a class_name's cache is flaky there);
								# locals off _cam_rig.* therefore need explicit types, not `:=`.
var _multiview                  # Multiview (Node, loaded); the all-views grid. Created in _ready.
var _drone_marker               # DroneMarker (Node3D); the amber diamond the control pane flies
var _remote                     # RemoteControl (RefCounted); the godot_cmd file channel. Created in _ready.

# Remembered view/render settings, saved on exit and restored on launch (so Raves doesn't
# reset to "looking south" every run). In user:// — available at startup, before the mod
# sends the support-dir path.
const SETTINGS_PATH := "user://raves_settings.json"

var _zone_center := Vector3(40, 0, 12)
var _zone_dims := Vector2(80, 25)   # live zone width x height in cells
var _prev_tile := Vector2i(-9999, -9999)
var _prev_zone_id := ""          # to detect zone crossings (shift the camera to stay continuous)
var _mode_label: Label
var _dbg_menu                   # DebugMenu (Node, loaded); the ` panel. Created in _ready.
var _reset_btn: Button
var _wm_cards_btn: Button   # persistent top-right world-map card toggle (mirrors O / the ` menu)
## Set true by MainFrame before this scene enters its SubViewport: the Holodeck is hosted inside the
## main UI frame, so hide its OWN chrome (mode label + Reset/2D buttons). The frame supplies its menu.
var embedded := false

## When false, skip ALL 3D build/render work in _on_snapshot — bridge + data (the snapshot signal)
## keep flowing with zero GPU/Metal work. The frame connects data-first with this off, then calls
## set_render_3d(true) to bring the viewport up separately. Default true = standalone renders normally.
var render_3d := true
var _ui_theme: Theme   # project-wide default theme (UiFont) on the root viewport — see _ready
var _ui_right_inset := 0.0   # 1:1: fraction of the window the side panels cover; recentres the cam (MainFrame pushes it)

# Responsive HUD text: a fraction of viewport height, but never below a floor —
# "min(px, %vh)" web sensibility, re-applied on window resize.
# Font sizes come from UiFont (the single source of truth). These stay as thin aliases so the rest
# of the file / the ruler read the same numbers.
func _ui_font_size() -> int:
	return UiFont.px(get_viewport(), "body")

## Size EVERY label/button in the top UI from the source of truth: the mode label, the whole debug
## menu (title, mode buttons, toggle buttons, slider labels), and the corner Reset button. Re-run on
## window resize so it tracks the viewport.
func _apply_ui_fonts() -> void:
	# Re-assert the 1:1 (parity) camera span on any window resize — a resize otherwise reverts the
	# top-down ortho span toward user-mode framing, which breaks the 1:1 match at a fixed size.
	if _cam_locked() and render_3d and _cam_rig != null:
		_cam_rig.set_one_to_one(true)
		_cam_rig.set_right_inset(_ui_right_inset)   # the inset is a fraction of the window — track resizes
	UiFont.refresh_theme(_ui_theme, get_viewport())   # keep the project-wide default in sync with the window
	_stamp_theme_roots(get_tree().root)               # make the default theme cross CanvasLayer boundaries
	var fs := _ui_font_size()
	if _mode_label != null:
		_mode_label.add_theme_font_size_override("font_size", fs)
	var dbg_panel: Control = _dbg_menu.panel() if _dbg_menu != null else null
	if dbg_panel != null:
		_apply_font_recursive(dbg_panel, fs)
	if _reset_btn != null:
		_reset_btn.add_theme_font_size_override("font_size", fs)
	if _wm_cards_btn != null:
		_wm_cards_btn.add_theme_font_size_override("font_size", fs)
	# keep the debug menu just BELOW the help label so they never overlap, even as
	# the responsive font grows the label's height
	if dbg_panel != null and _mode_label != null:
		var lh: float = maxf(_mode_label.get_minimum_size().y, float(fs))
		dbg_panel.position = Vector2(14, _mode_label.position.y + lh + 8.0)

## Make the project-wide default theme (UiFont) reach EVERY Control, even ones nested under a
## CanvasLayer or plain Node. In Godot 4 a Control whose direct parent is neither a Control nor a
## Window becomes its own "theme root" and does NOT inherit the root viewport's theme — so a single
## CanvasLayer in the chain (CharacterCreator, and any future pop-up UI) severs propagation and the
## controls fall back to the tiny built-in default. Assigning `_ui_theme` to each such theme-root
## Control reconnects the whole tree to the one source of truth. Idempotent; safe to re-run on resize
## or after new UI is built. Controls that set their OWN theme on purpose (OnboardingControl) are left
## alone so their explicit choice still wins.
func _stamp_theme_roots(node: Node) -> void:
	if node is Control:
		var p := node.get_parent()
		if not (p is Control) and (node as Control).theme == null:
			(node as Control).theme = _ui_theme
	for c in node.get_children():
		_stamp_theme_roots(c)

## Apply a font size to every Label/Button under `node` (recursively) — how the debug menu and any
## nested popups get sized uniformly from one call.
func _apply_font_recursive(node: Node, size: int) -> void:
	if node is Label or node is Button:
		node.add_theme_font_size_override("font_size", size)
	for c in node.get_children():
		_apply_font_recursive(c, size)

## Show/hide the font-size ruler (Lorem Ipsum at each px) with the current UI-font math in the header,
## so you can pick the MINIMUM and NORMAL sizes. Toggle: L, or the ` menu button.
func _toggle_font_preview() -> void:
	if _font_preview == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var hdr := "Font-size ruler — window %dx%d · current UI font %dpx  (UiFont.MIN=%d, FRAC=%.4f)" % [
		int(vp.x), int(vp.y), _ui_font_size(), UiFont.MIN, UiFont.FRAC]
	_font_preview.toggle(hdr)

func _ready() -> void:
	# Source-of-truth fonts, made AUTOMATIC: a project-wide default theme on the root viewport, so
	# every Control that doesn't override — CharacterCreator, and any future UI — inherits the UiFont
	# body size + the Atkinson font for free. Refreshed on resize in _apply_ui_fonts.
	_ui_theme = UiFont.make_theme(get_viewport())
	get_tree().root.theme = _ui_theme

	renderer = ZoneRenderer.new()
	add_child(renderer)
	renderer.lighting_changed.connect(_relight_now)

	client = BridgeClient.new()
	add_child(client)
	client.snapshot.connect(_on_snapshot)
	client.popup.connect(_on_popup)
	client.tutorial.connect(_on_tutorial)
	client.tombstone.connect(_on_tombstone)
	# ASK for the live step. The mod publishes the guide on change only, so attaching to a run
	# already in progress (Continue, or a viewer restarted mid-tutorial) would show no box until
	# the tutorial next spoke — and a beat can sit there for many turns waiting to be obeyed.
	client.send_command("tutorial_resend", {})
	client.send_command("tombstone_resend", {})
	client.qud_view.connect(func(v: String) -> void: qud_view_changed.emit(v))
	client.picker.connect(_on_picker)
	client.cyber.connect(_on_cyber)
	client.connected.connect(_on_bridge_connected)

	_sky_grade = load("res://SkyGrade.gd").new()   # day/night atmosphere: WorldEnvironment + grade + sun/moon
	add_child(_sky_grade)
	_sky_grade.setup(embedded, renderer)

	_beacons = load("res://LocationBeacons.gd").new()   # the Locations panel's horizon markers
	add_child(_beacons)
	# The cursor's verb (boots / speech bubble / hand / stairs arrow) — see MouseAssist.
	# Qud's target picker, mirrored — its own overlay, because it owns the playfield's mouse while
	# it is up and nothing else may act on a click (see _travel_click).
	_target = load("res://TargetCursor.gd").new()
	add_child(_target)
	_target.setup(renderer)
	_target.answered.connect(func(x: int, y: int, cancel: bool) -> void:
		# ARM THE FLAMES BEFORE THE SHOT, PLAY THEM ON QUD'S WORD. The path only exists here — it is
		# the one the reticle was drawing — but whether the shot HAPPENED is Qud's to say, and it
		# says so in the message log a moment later. Playing on the click instead would light up a
		# refused shot, a wall, and every bow shot besides.
		if not cancel and renderer != null:
			renderer.arm_ray(_target.path())
		client.send_command("picktarget", {"x": x, "y": y, "cancel": cancel}))
	client.picktarget.connect(func(d: Dictionary) -> void: _target.set_state(d))
	# Qud's trade board, mirrored. Its own overlay for the same reason the item picker has one: it is
	# a Qud SCREEN, not a PopupMessage, so the popup mirror never sees it.
	_trade = TradeOverlay.new()
	add_child(_trade)
	_trade.act.connect(func(payload: Dictionary) -> void:
		client.send_command("trade", payload))
	client.trade.connect(func(d: Dictionary) -> void:
		# The frame's own tilesDir wins: during a trade there are no snapshots, so the renderer's
		# copy can still be empty when the board arrives.
		var td := String(d.get("tilesDir", ""))
		if td == "" and renderer != null:
			td = renderer.tiles_dir()
		_trade.set_state(d, _palette, td))
	_assist = load("res://MouseAssist.gd").new()
	add_child(_assist)
	_assist.setup(renderer)   # the box + billboard live under the renderer, for its z-stretch
	# The name-plates sit on their own HUD layer, which no modal covers — so they have to stand
	# down themselves. Same predicate the rest of the app asks (see _modal_owns_input), plus the
	# tombstone, which is the one full-screen thing that is not a modal.
	_beacons.blocked_cb = func() -> bool:
		return _modal_owns_input() or (_tomb != null and _tomb.visible)

	_cam_rig = load("res://CameraRig.gd").new()   # pivot + camera + modes + placement math
	add_child(_cam_rig)
	_cam_rig.setup(self, renderer, null)          # inspector wired in once it's built (below)

	# Multi-view grid (its own file). Built BEFORE the debug menu, whose button connects to its toggle.
	# Pane clicks call back into Main._multiview_inspect (Main owns the inspector + report form).
	# The drone's marker. In the scene, not in the renderer's per-turn subtree — that subtree is
	# cleared and rebuilt every step.
	_drone_marker = load("res://DroneMarker.gd").new()
	add_child(_drone_marker)
	_multiview = load("res://Multiview.gd").new()
	add_child(_multiview)
	# The last argument is how a pane's compass ring moves the player: it hands back a COMPASS
	# NAME ("N", "SE", …) already resolved for that pane's heading, so this end stays the one
	# place that talks to the bridge about movement.
	_multiview.setup(_cam_rig, _MODE_NAMES, _multiview_inspect, _set_mode,
		func(d: String): client.send_command("move", {"dir": d}))

	# Remote-command channel (the godot_cmd file poller for control.py). Driven from _process; the dispatch
	# (_exec_godot_cmd) stays here since each command drives a Main subsystem.
	_remote = load("res://RemoteControl.gd").new()
	_remote.setup(_support_dir, _exec_godot_cmd)

	# Direction picker (ability-prompt cursor, its own file). Driven from _process/_input.
	_picker = load("res://DirectionPicker.gd").new()
	add_child(_picker)
	_picker.setup(_cam_rig, client)

	_binds.setup(_support_dir())   # custom-keybind fallback map (reloads on export change)

	# Popup overlay (its own file): mirrors Qud modals (message / yes-no / option list / text prompt)
	# forwarded by the mod, and ships the viewer's answer back so Qud's blocked turn thread unblocks.
	_popup = PopupOverlay.new()
	add_child(_popup)
	# The TUTORIAL GUIDE, mirrored from Qud (mod/TutorialBridge.cs). A child of the Holodeck scene
	# on purpose: this node lives inside MainFrame's SubViewport, so its viewport IS the play area
	# and the box lands over the world instead of over the side panels, with no rect to thread.
	_tutorial = preload("res://TutorialGuide.gd").new()
	add_child(_tutorial)
	# The end-of-run tombstone, mirrored from Qud (mod/TombstoneBridge.cs).
	_tomb = preload("res://TombstoneScreen.gd").new()
	add_child(_tomb)
	_tomb.dismissed.connect(func():
		# Close QUD's first and let its own frame turn the screen off here — dismissing locally
		# would put Raves back at the title with Qud still parked on the summary, which is the
		# desync this whole path exists to remove.
		client.send_command("tombstone_exit", {}))
	_tomb.save_requested.connect(func():
		client.send_command("tombstone_save", {}))
	_popup.closed.connect(func(): popup_closed.emit())
	_popup.answered.connect(func(payload: Dictionary):
		client.send_command("popup", payload)
		if str(payload.get("action", "")) == "option":
			popup_option.emit(str(payload.get("text", ""))))

	# Item picker (its own file): Qud's PickGameObjectScreen — what an EMPTY paper-doll slot
	# raises. It is a screen, not a PopupMessage, so it arrives on its own channel.
	_cyber = load("res://CyberOverlay.gd").new()
	add_child(_cyber)
	_cyber.answered.connect(func(payload: Dictionary):
		client.send_command("cyber", payload))
	_item_picker = PickerOverlay.new()
	add_child(_item_picker)
	_item_picker.closed.connect(func(): popup_closed.emit())
	_item_picker.answered.connect(func(payload: Dictionary):
		client.send_command("picker", payload))

	_load_settings()   # restore camera heading/mode/zoom/depth/window before the UI reads them
	_build_mode_label()
	# The ` debug menu (its own file). It reaches Main actions through these callbacks; _toggle_flat_2d
	# stays here (the O key + persistent button share it), and it mirrors the flat state back via refresh_flat_2d.
	_dbg_menu = load("res://DebugMenu.gd").new()
	add_child(_dbg_menu)
	_dbg_menu.build(_cam_rig, renderer, _sky_grade, _multiview, _MODE_NAMES, {
		"set_mode": _set_mode,
		"toggle_flat_2d": _toggle_flat_2d,
		"font_ruler": _toggle_font_preview,
		"water_changed": _on_water_depth_changed,
		"level_changed": _on_level_height_changed,
	})
	_build_reset_button()
	_apply_ui_fonts()
	get_viewport().size_changed.connect(_apply_ui_fonts)
	_cam_rig.apply_zstretch()   # a restored top-down mode needs the stretch applied at startup
	_cam_rig.snap()             # place the camera from the restored state (was _update_camera(0.0))

	inspector = CellInspector.new()
	add_child(inspector)
	inspector.setup(renderer, _cam_rig._cam)
	inspector.look_resolve = cell_at_look   # the cursor may leave the live zone; Main owns the store
	_cam_rig.set_inspector(inspector)

	reporter = TileReport.new()
	add_child(reporter)
	reporter.setup(renderer)
	reporter.dismissed.connect(_dismiss_selection)

	onboarding = OnboardingControl.new()
	add_child(onboarding)
	onboarding.setup()

	_font_preview = FontPreview.new()
	add_child(_font_preview)

	_char_creator = CharacterCreator.new()
	_char_creator.client = client
	add_child(_char_creator)

	# Every UI subtree above is now in the tree; re-run so the theme stamp reaches the ones built
	# after the first _apply_ui_fonts() call (inspector, reporter, onboarding, font ruler, character
	# creator). Deferred so each node's own _ready()/_build has finished.
	_apply_ui_fonts.call_deferred()

	if embedded:
		_hide_holodeck_chrome()

## Hide the Holodeck's own on-screen chrome (mode label, ⟳ Reset, tiles-2D button) when it's hosted
## inside the main UI frame — the frame will provide these controls itself. The world, the debug menu
## (`), and the inspector still work; only the always-on HUD buttons go away.
## Turn the 3D build/render on or off at runtime. Turning it ON renders the current zone immediately
## (from the store the data-only path kept current) instead of waiting for the next turn.
func set_render_3d(on: bool) -> void:
	render_3d = on
	if on:
		if _cam_locked():
			_cam_rig.set_one_to_one(true)         # robust: 1:1 span even if already TOP_FOLLOW
			_cam_rig.set_right_inset(_ui_right_inset)   # recentre the view in the play hole
			_set_mode(CamMode.TOP_FOLLOW, true)   # enter the 1:1 camera as the viewport comes up
		var live: Dictionary = store.live_snapshot()
		if not live.is_empty():
			renderer.render_snapshot(live, _neighbor_zones())

func _hide_holodeck_chrome() -> void:
	if _mode_label != null:
		_mode_label.visible = false
	if _reset_btn != null:
		_reset_btn.visible = false
	if _wm_cards_btn != null:
		_wm_cards_btn.visible = false

## On (re)connect, wait one turn so Qud publishes a snapshot immediately and Raves has a
## zone to render — instead of a blank view until the player first moves. Passes a turn for
## now; a no-turn refresh will replace this later.
func _on_bridge_connected() -> void:
	client.send_command("wait", {})

## Qud's per-cell sprite flip (PartyFlip) is render-context state, so the mod can't read it stably for
## the player's CELL object — but the separate `player` block reads it reliably. Copy that flip onto the
## player's own cell creature so the renderer (flip_h = obj.hflip) faces the playfield player like Qud.
func _inject_player_facing(data: Dictionary) -> void:
	var pl: Dictionary = data.get("player", {})
	if not pl.has("hflip"):
		return
	var px := int(pl.get("x", -9999))
	var py := int(pl.get("y", -9999))
	for cell in data.get("cells", []):
		if int(cell.get("x", -2)) == px and int(cell.get("y", -2)) == py:
			for obj in cell.get("objs", []):
				if bool(obj.get("creature", false)):
					obj["hflip"] = pl.get("hflip")
			return

## A Qud modal (message / yes-no / option list / text prompt) mirrored by the mod. During a popup the turn
## thread is blocked, so NO snapshots arrive — this is the only channel that tells us it opened. The overlay
## is modal (eats input) until the viewer answers, which ships a "popup" command back to unblock Qud.
## Qud's tutorial moved to a new beat (or stopped talking). The box persists across turns, unlike
## a popup, so it is driven ONLY by these frames — nothing else may clear it.
func _on_tutorial(data: Dictionary) -> void:
	if _tutorial == null:
		return
	if bool(data.get("active", false)):
		_tutorial.show_step(data, _palette, Rect2())
	else:
		_tutorial.hide_step()

## The run ended (or its summary was dismissed). Qud is the authority on both edges.
func _on_tombstone(data: Dictionary) -> void:
	if _tomb == null:
		return
	var up := bool(data.get("active", false))
	if up:
		_tomb.show_tombstone(data, _palette)
	else:
		_tomb.hide_tombstone()
	tombstone_changed.emit(up)

func _on_popup(data: Dictionary) -> void:
	if _popup == null:
		return
	if bool(data.get("active", false)):
		_popup.show_popup(data, _palette)
	else:
		_popup.hide_popup()

## Qud's item picker, mirrored. Same blocking story as a popup — the turn thread is parked inside
## PickGameObjectScreen.show(), so this channel is the only word we get that it opened. The viewer's
## row choice goes back as a "picker" command and Qud's own HandleSelectItem applies it.
func _on_picker(data: Dictionary) -> void:
	if _item_picker == null:
		return
	if bool(data.get("active", false)):
		_item_picker.show_picker(data, _palette)
	else:
		_item_picker.hide_picker()

## The game the saved compass heading belongs to, so a different one can reset it (see below).
## Empty until a snapshot names one; a pre-gameId mod leaves it empty and nothing resets, which is
## the right way to fail here — keeping a heading is harmless, losing someone's is not.
var _cam_game_id := ""

## FACE NORTH IN A GAME THAT IS NOT THE ONE THE HEADING WAS SAVED FROM.
##
## The view file is global, so the compass survived into every new character: start a new game and
## the camera pointed wherever the last session left it. Zoom or mode carrying over is a
## preference; a HEADING is an orientation in a particular world, and in a new one it refers to
## nothing. The wire has carried `gameId` all along (WorldStore keys its zone cache by it, for the
## same reason: a new game must not render a previous game's zones) — this is the camera's half of
## that rule.
##
## THE MODE RESETS TOO, as of 2026-08-26 — Daniel: "when Qud starts, the camera should be
## compass-mode, pointing north." This reverses what the line below used to say (that the mode is
## a preference like zoom and should carry over). A new character arriving in first-person, or in
## the top-down parity view, is not where anyone wants to start reading a new world; compass north
## is the orientation every other map in Qud is drawn in.
##
## Distance and zoom still carry over: those really are how the player likes to look at the game.
func _check_camera_game(data: Dictionary) -> void:
	var gid := String(data.get("gameId", ""))
	if gid == "" or gid == _cam_game_id:
		return
	# INCLUDING from "" — the empty stored id means the saved camera belongs to no game we can
	# name, which is exactly the case where it should not be inherited. Skipping it was why a
	# fresh session's first game still came up in whatever mode the file happened to hold.
	if _cam_rig != null:
		_cam_rig._compass_yaw = _cam_rig.COMPASS_YAW_DEFAULT
		# ...and through _set_mode, not by assigning _mode: that is what lays the billboards down,
		# fixes the z-stretch and tells the frame which camera it is now on. NOT while the 1:1
		# camera lock is on — in parity mode the camera is not the viewer's to reset.
		if not _cam_locked():
			_set_mode(CamMode.COMPASS)
	_cam_game_id = gid

## Qud's cybernetics terminal, mirrored. Same parked-turn-thread story as the popup and the
## picker — the screen awaits its own completionSource, so this channel is the only word we get.
func _on_cyber(data: Dictionary) -> void:
	if _cyber == null:
		return
	if bool(data.get("active", false)):
		_cyber.show_terminal(data, _palette)
	else:
		_cyber.hide_terminal()

## Re-render what is already on screen, for a setting whose effect is decided during the relight.
## The 2D/3D toggle and the deep-water depth both do this for the same reason: a control whose
## result does not appear until you take a step reads as a control that does not work.
func _relight_now() -> void:
	var live: Dictionary = store.live_snapshot()
	if not live.is_empty():
		ZoneRenderer.mark_fire_lit(live)
		renderer.render_snapshot(live, _neighbor_zones())


func _on_snapshot(data: Dictionary) -> void:
	# Data-freshness beacon for the test rig: the UI heartbeat proves the
	# VIEWER is alive, not that the WIRE is — a dropped bridge connection
	# left stale zones (and stale dynamic creatures) on screen through a
	# certification band while raves_state.json read perfectly healthy.
	UiState.note_snapshot()
	# WHICH CELLS A FIRE LIT, worked out ONCE and here, at the top of the one function every
	# snapshot passes through. The renderer and the panels are handed the same cell dictionaries,
	# so marking them at the door is what keeps the map and the room agreeing about what you can
	# see — the alternative is each consumer forming its own opinion, which is the bug this
	# codebase has now paid for twice.
	ZoneRenderer.mark_fire_lit(data)
	# WORLD MAP is a distinct SCREEN, not a zone: Qud sends it as a negative
	# stratum (zone.z < 0 — the parasang overview ZoneRenderer already keys
	# _world_map off). Report it so the rig can tell "player is reading the
	# map" from "player is in a zone": they render in the same frame, so a
	# checker that only asks for in_game would happily pixel-score a world
	# map against a zone capture — the failure mode that poisoned a
	# certification band from the menus. MainFrame still owns the in_game
	# announcement; this only splits it while a snapshot says otherwise.
	# Same rule as ZoneRenderer._world_map — Qud's IsWorldMap(): a dotless ZoneID.
	var _zid := String((data.get("zone", {}) as Dictionary).get("id", ""))
	UiState.note_world_map(_zid != "" and not _zid.contains("."))
	# Cache the colour map so popup markup renders with the same palette. Do NOT
	# hide the popup here: ASYNC popups (ShowYesNoAsync / PickOptionAsync) never
	# block the turn thread, so snapshots keep flowing while they're up — the old
	# "snapshot == no popup" rule made the mirror FLICKER (show → snapshot-hide →
	# re-announce, forever). The watcher's active:false is the dismissal channel
	# (it force-rescans before declaring one), and a stranded overlay is always
	# escapable — Esc answers Cancel and hides locally.
	var pal: Dictionary = data.get("palette", {})
	if not pal.is_empty():
		_palette = pal
	# The popup's menu rows carry TILE PATHS; the directory they live in rides the snapshot, not the
	# popup payload, so the overlay is told here rather than made to wait for one.
	if _popup != null:
		_popup.tiles_dir = String(data.get("tilesDir", _popup.tiles_dir))
	if _assist != null:
		_assist.set_snapshot(data)
	# The beacons draw each place's own world-map sprite, so they need the tile directory and the
	# palette the same way every other panel does.
	if _beacons != null:
		_beacons.tiles_dir = String(data.get("tilesDir", _beacons.tiles_dir))
		_beacons.palette = data.get("palette", _beacons.palette)
	# Route the render through the store: draw the live zone plus any remembered
	# neighbours (same stratum) the player has visited, placed by global offset.
	Profiler.add_us("server", int(data.get("serverUs", 0)))
	_inject_player_facing(data)   # the player's cell obj carries no reliable hflip; use the player block's
	# the Creating World overlay (an embark in progress) learns the game is live from the
	# FIRST snapshot — the exact moment the world beneath it starts rendering
	get_tree().call_group("creating_world", "game_live")
	Profiler.begin("ingest")
	_check_camera_game(data)   # a different game than the stored heading belongs to -> face north
	store.ingest(data)   # keep the store current even when not rendering, so 3D can start instantly
	Profiler.done("ingest")
	# The 3D build/render (meshes, SubViewport) is the heavy GPU work. When render_3d is off (the frame
	# hosts us data-first, viewport later) we skip ALL of it and just feed data — no Metal work at all.
	if render_3d:
		Profiler.begin("neighbors")
		var nbs := _neighbor_zones()
		Profiler.done("neighbors")
		# first-person: hide the player creature (the camera sits on its cell)
		var pc: Dictionary = data.get("player", {})
		# FIRST PERSON HIDES THE PLAYER WITH A CULL MASK, not by skipping his cell. Skipping is a
		# property of the WORLD and first person is a property of one CAMERA -- the difference did
		# not matter until multiview put seven cameras on the same world, and then it showed up as
		# the player standing in front of the first-person view. ZoneRenderer tags his cell onto
		# PLAYER_LAYER; dropping that bit is all "first person" means here.
		if _cam_rig._mode == CamMode.FIRST_PERSON:
			_cam_rig._cam.cull_mask &= ~ZoneRenderer.PLAYER_LAYER
		else:
			_cam_rig._cam.cull_mask |= ZoneRenderer.PLAYER_LAYER
		Profiler.begin("render")
		renderer.render_snapshot(store.live_snapshot(), nbs)
		Profiler.done("render")
	inspector.on_snapshot(data)
	# THE BEACONS ARE FED BEFORE THE PANELS ARE, because the Locations panel asks THEM how far away
	# each place is (beacon_metrics) the moment it gets the snapshot. Feeding them after the emit
	# measured the first frame's distances from the world ORIGIN instead of from the player, and the
	# list came up ordered by how far each place is from the top-left corner of Qud.
	if _beacons != null:
		var bz: Dictionary = data.get("zone", {})
		var bp: Dictionary = data.get("player", {})
		var bx := int(bp.get("x", -1))
		var by := int(bp.get("y", -1))
		if bx >= 0 and by >= 0 and not bz.is_empty():
			_beacons.set_player(bz, bx, by)
	snapshot.emit(data)   # let a host frame update its status bar / panels off the same data (always)

	# Auto-dump the profile every N turns (cumulative, no reset) so it's always fresh
	# without needing a keypress — the manual P key can be flaky (window focus / UI).
	_prof_turns += 1
	if _prof_turns % 40 == 0:
		_dump_profile(false)

	_depth = int(data.get("zone", {}).get("z", SURFACE_Z))
	_sky_grade.update(data.get("time", {}), _depth, _zone_center)   # day/night; uses last frame's zone centre
	_update_mode_label()   # refresh the ⏱ time label with the new time

	var z: Dictionary = data.get("zone", {})
	if z.has("width") and z.has("height"):
		_zone_center = Vector3(float(z["width"]) / 2.0, 0.0, float(z["height"]) / 2.0)
		_zone_dims = Vector2(float(z["width"]), float(z["height"]))
		_cam_rig.set_zone_cells(_zone_dims)   # 1:1 zone-fit tracks the live zone size

	# Read the player cell FIRST. An absent/invalid cell (a mid-teardown frame, or the
	# player briefly having no cell) reports (-1,-1) — hold the last good camera state and
	# ignore this frame entirely rather than re-anchoring the world off garbage coords.
	var p: Dictionary = data.get("player", {})
	var px := int(p.get("x", -1))
	var py := int(p.get("y", -1))
	if px < 0 or py < 0:
		return
	var tile := Vector2i(px, py)
	var moved := _prev_tile.x > -9999 and tile != _prev_tile

	# Crossing a zone edge re-anchors the live zone to local coords, so the player's
	# (px,py) jumps discontinuously (e.g. 0 -> 79) and everything on screen shifts.
	# Shift the camera by the SAME amount (the two zones' global-origin difference) so
	# it stays locked on the same world content — a seamless continuous crossing, no
	# cut or sweep. Also don't read the coord jump as a step (it flipped `_facing`).
	#
	# GUARD — the shift only makes sense for a player who actually STEPPED over the edge:
	# a real crossing always jumps the local tile. If the zone id changes while the player
	# sits still (e.g. "become" swaps the body onto a stationary corpse and the reported
	# zone id flaps), applying the shift would yank the eye off a motionless player every
	# frame while the lerp scrolls it back — the reset-away / scroll-toward loop. So gate
	# the whole crossing on `moved`.
	var zid := String(z.get("id", ""))
	var old_zid := _prev_zone_id
	var crossed := moved and old_zid != "" and zid != old_zid
	_prev_zone_id = zid
	if crossed and store.has_zone(old_zid) and store.has_zone(zid):
		var oo: Vector3i = store.record(old_zid).get("origin", Vector3i.ZERO)
		var no: Vector3i = store.record(zid).get("origin", Vector3i.ZERO)
		# Shift the camera by the two zones' global-origin difference so it stays locked on the
		# same world content across the re-anchor — a seamless continuous crossing.
		_cam_rig.apply_cross_shift(Vector3(oo.x - no.x, 0.0, oo.y - no.y))
	elif crossed:
		print("[cross] SKIPPED shift: old=%s has=%s  new=%s has=%s" % [
			old_zid, store.has_zone(old_zid), zid, store.has_zone(zid)])

	# facing = the direction of the last actual step (a crossing's coord jump doesn't count), so the
	# camera trails behind. The rig applies it, tracks the player, and self-seeds on the first frame.
	var stepped := moved and not crossed
	var step_dir := Vector2(tile.x - _prev_tile.x, tile.y - _prev_tile.y) if stepped else Vector2.ZERO
	_prev_tile = tile
	# WHERE THE PLAYER IS is not where they are DRAWN — see _walk_step. The camera follows the
	# walking position so it does not arrive a cell before its subject; the cell itself is recorded
	# here as the target the walk is heading for.
	_walk_to = Vector2(px, py)
	if crossed or not _walk_seeded:
		# A CROSSING IS NOT A WALK. The coordinates re-anchor to the new zone's origin, so easing
		# between them slides the player the width of a zone through whatever is in the way.
		_walk_at = _walk_to
		_walk_seeded = true
	# ...AND PULL THE SPRITE BACK IN THIS SAME FRAME. Daniel, reading a video frame by frame: "the
	# player is moved to the new tile. Then the player is moved back to the original tile. Then the
	# camera and the player move to the new tile."
	#
	# All three phases are one missing line. render_snapshot ran ABOVE this and re-seated the
	# player's sprite on the new cell; _walk_to only becomes the new cell HERE; and the offset that
	# carries the sprite back to where it is being drawn was not applied until the next _process.
	# So the frame ended with the player standing on the destination (phase one), the next frame
	# applied an offset of a whole cell backwards (phase two), and only then did the ease run
	# (phase three). The walk was correct throughout — it was drawn a frame ahead of itself.
	if renderer != null:
		renderer.set_walk_offset(_walk_at - _walk_to)
	_cam_rig.set_player(Vector3(_walk_at.x, 0, _walk_at.y), step_dir, stepped)

## Remembered zones to draw around the live one: every OTHER stored zone on the
## same stratum, offset by the difference of its global origin from the live zone's
## (in cells = world units). Cross-stratum stacking is Phase 2; a distance/eviction
## radius is Phase 1's freeze-unfreeze step — for now the store holds few zones.
func _neighbor_zones() -> Array:
	var out: Array = []
	# 2D mode floors EVERY object in EVERY cell, so a full surface zone plus its remembered
	# neighbours is far more geometry than the 3D path (walls are greedy-meshed there, most cells
	# hold nothing to floor). Rebuilding all of them flat in one re-render blew past the GPU timeout
	# and hung on the surface (the overworld is a single zone, so it never hit this). Render just the
	# live zone flat; neighbour context returns in 3D. (Incremental flat neighbours are a follow-up.)
	if _flat_2d:
		return out
	var live_id := store.live_id()
	if live_id == "":
		return out
	var live_rec := store.live_record()
	var live_origin: Vector3i = live_rec.get("origin", Vector3i.ZERO)
	var live_z: int = int(live_rec.get("stratum", 0))
	for id in store.ids():
		if id == live_id:
			continue
		var rec: Dictionary = store.record(id)
		# Vertical stacking: keep same-stratum neighbours (dz==0, the horizontal
		# remembered zones) plus DEEPER levels (dz>0) up to LEVEL_KEEP_DOWN, which
		# _sync_neighbors offsets downward. Shallower levels (dz<0) are turned off —
		# they'd hang above as a terrain ceiling and occlude the current level.
		var dz: int = int(rec.get("stratum", -9999)) - live_z
		if dz < 0 or dz > LEVEL_KEEP_DOWN:
			continue
		var o: Vector3i = rec.get("origin", Vector3i.ZERO)
		# the player's position when this zone was last live (its final snapshot), so the
		# renderer can erase the sight-disc they carried out of it (see _build_darkness).
		var pl: Dictionary = rec.get("snapshot", {}).get("player", {})
		out.append({
			"id": id,
			"cells": rec.get("snapshot", {}).get("cells", []),
			"offset": Vector2i(o.x - live_origin.x, o.y - live_origin.y),
			"dz": dz,
			"px": int(pl.get("x", -9999)),
			"py": int(pl.get("y", -9999)),
		})
	return out

# --- remote control (for automated dev loops) -------------------------------
# Claude can't send keys to Godot, only commands to Qud's bridge. So Godot polls a
# small command file: control.py writes lines, we execute + delete. Lets an external
# driver trigger Godot-side actions (screenshot, switch camera) to close the loop.
## The RavesOfQud data dir. Prefer the renderer's tiles dir (proven correct once a
## turn has been taken), but fall back to the OS support dir so the command channel +
## screenshots work BEFORE Qud connects — e.g. to photograph the onboarding UI cold.
func _support_dir() -> String:
	if renderer != null:
		var b := renderer.tiles_dir().get_base_dir()
		if b != "":
			return b
	return InputModel.support_dir()

func _exec_godot_cmd(cmd: String) -> void:
	if cmd == "":
		return
	var parts := cmd.split(" ", false)
	match parts[0]:
		"shot":
			# `shot` — the window as it stands. `shot clean` — the same frame with the SELECTION
			# OVERLAY dropped: the inspector's report panel is a full-height wall of text pinned
			# over the playfield, so the one gesture that tells you what a cell IS also hides the
			# thing you inspected. _screenshot has taken a `clean` flag all along and no command
			# ever passed it, which is why every appearance check after an inspect had to move the
			# camera away from its own subject first.
			_screenshot(parts.size() > 1 and parts[1] == "clean", true)   # forced: unfocused, no auto-draw
		"census":
			# Rung 6a: dump the renderer's per-cell placement verdicts so the rig
			# can diff them against the wire's cells — "did we draw everything
			# the zone sent?" with no pixels, no calibration, no focus.
			var cs := FileAccess.open(_support_dir().path_join("census.json"), FileAccess.WRITE)
			if cs != null:
				var payload := {}
				if renderer != null:
					payload = {
						"zone": _prev_zone_id,
						"cells": renderer.placement_census(),
					}
				cs.store_string(JSON.stringify(payload))
				cs.close()
		"uidump":
			# dump the frame's bottom-row widget rects — who is taller than the 90px budget?
			var fr := get_parent()
			if fr != null and fr.get("_effects") != null:
				var ud := FileAccess.open(_support_dir().path_join("uidump.json"), FileAccess.WRITE)
				if ud != null:
					var d := {}
					for k in ["_effects", "_target", "_context", "_command", "_row_split", "_side", "_msglog"]:
						var n: Control = fr.get(k)
						if n != null:
							var r := n.get_global_rect()
							d[k] = [r.position.x, r.position.y, r.size.x, r.size.y]
					ud.store_string(JSON.stringify(d))
					ud.close()
		"minimapdump":
			# What the tile map's last pass saw: how many cells carried objects, how many of those
			# resolved to art, and where it was looking for it.
			var mdf := FileAccess.open(_support_dir().path_join("minimapdump.json"), FileAccess.WRITE)
			if mdf != null:
				var mv = get_parent().get("_minimap") if get_parent() != null else null
				mdf.store_string(JSON.stringify(mv.probe if mv != null else {"error": "no minimap"}))
				mdf.close()
		"firedump":
			# WHERE THE FIRELIGHT SWITCH STOPS. The chain is four links long — the setting, the
			# static gate, the per-cell mark, and what the relight makes of it — and a picture
			# that barely changes cannot say which one broke. This asks all four at once.
			var fd := FileAccess.open(_support_dir().path_join("firedump.json"), FileAccess.WRITE)
			if fd != null:
				var live: Dictionary = store.live_snapshot()
				var cs: Array = live.get("cells", [])
				var n_lit := 0
				var n_mark := 0
				var n_seen := 0
				for c in cs:
					if int(c.get("light", 200)) >= ZoneRenderer.LIGHT_LIT:
						n_lit += 1
					if bool(c.get("firelit", false)):
						n_mark += 1
					if ZoneRenderer.cell_is_seen(c):
						n_seen += 1
				fd.store_string(JSON.stringify({
					"setting_firecells": Settings.qol_on("firecells"),
					"fire_dark": ZoneRenderer.fire_dark,
					"cells": cs.size(), "lit_raw": n_lit, "marked": n_mark, "seen": n_seen,
					"player": live.get("player", {}).get("x", -1),
				}))
				fd.close()
		"walkdump":
			# The last WALK_LOG_N frames of player/torch placement, for a stutter too fast to
			# screenshot.
			var wd := FileAccess.open(_support_dir().path_join("walkdump.json"), FileAccess.WRITE)
			if wd != null:
				wd.store_string(JSON.stringify(_walk_log))
				wd.close()
		"dustdump":
			# Is the wind blowing, and does that match the stratum? Written as a file because the
			# answer is needed while the turn thread is parked.
			var dd := FileAccess.open(_support_dir().path_join("dustdump.json"), FileAccess.WRITE)
			if dd != null:
				var dr := {}
				if renderer != null:
					dr = renderer.dust_report()
					dr["zone"] = _prev_zone_id
					dr["depth"] = _depth
				dd.store_string(JSON.stringify(dr))
				dd.close()
		"camdump":
			# dump the camera/hole state to camdump.json — the deterministic probe for
			# "why is the 1:1 stage the wrong size" class of bugs.
			var cd := FileAccess.open(_support_dir().path_join("camdump.json"), FileAccess.WRITE)
			if cd != null and _cam_rig != null:
				var vpr := get_viewport().get_visible_rect().size
				cd.store_string(JSON.stringify({
					"mode": _cam_rig._mode, "main_1to1": _one_to_one, "rig_1to1": _cam_rig._one_to_one,
					"hole": [_cam_rig._play_hole.position.x, _cam_rig._play_hole.position.y,
						_cam_rig._play_hole.size.x, _cam_rig._play_hole.size.y],
					"zoom_q": _cam_rig._zoom_q, "top_zoom": _cam_rig._top_zoom,
					"ortho": (_cam_rig._cam.size if _cam_rig._cam != null else -1.0),
					"vp": [vpr.x, vpr.y], "render_3d": render_3d,
				}))
				cd.close()
		"zoom1to1":
			# `zoom1to1 <factor>` — set the 1:1 zoom factor directly (quarters, >= 1.0). The
			# deterministic test input: key/wheel injection proved unreliable for sweeps.
			if parts.size() >= 2 and _cam_rig != null:
				_cam_rig.set_zoom_1to1(float(parts[1]))
		"look":
			# `look` toggles the look cursor, `look N` steps it. Driving it from outside is the only
			# way to test a mode whose whole point is that it does not open a window: there is no
			# panel to assert on, just a marker in the world and a line in the log.
			if parts.size() >= 2 and inspector != null and inspector.look_on():
				_report_look_cell(inspector.look_move(_cam_rig.compass_delta(parts[1].to_upper())))
			else:
				look_toggle()
		"lookreport":
			look_report()
		"camrot":
			# `camrot <deg>` — turn the full-screen camera. Raves has had no control-channel way to
			# do this: Q/E are the in-app keys, and a synthetic Q sent from outside reaches QUD and
			# opens its journal. That left a whole class of appearance question unanswerable from
			# outside — "does the thing behind me look right" needs the camera pointed at it.
			if parts.size() >= 2 and _cam_rig != null:
				_cam_rig._compass_yaw = fposmod(_cam_rig._compass_yaw
					+ deg_to_rad(float(parts[1])), TAU)
		"held":
			# `held` — toggle the hand-torch diagnostic. Only useful from source (the exported app
			# writes no stdout), which is exactly where this gets debugged.
			if renderer != null:
				renderer._held_dbg = not renderer._held_dbg
				print("[held] debug %s" % ("ON" if renderer._held_dbg else "off"))
		"zonereport":
			# `zonereport` — write zones.txt: which zones the store holds, where each lands in the
			# 3x3 slot grid, and what the SURROUND BAND actually built this turn.
			#
			# This exists because reading it off a screenshot does not work. A band cell and a
			# loaded neighbour's memory-toned ground are near enough in colour to be mistaken for
			# each other, and I spent a round measuring a boundary I had assumed was unvisited when
			# the store had it all along -- the same class of error as the frozen ramp that the bib
			# turned out to be. `print` is no use here either: the EXPORTED app writes no log, and
			# the exported app is the one highvisor launches. So: a file, first-party, on demand.
			_write_zone_report()
		"screenpos":
			# `screenpos CX CY` — print where a zone CELL lands on screen, in window pixels.
			# The missing half of `inspect`: that says what a cell IS, this says where to LOOK,
			# so an outside tool can sample the rendered pixel for a named cell instead of
			# guessing coordinates off a crop. Every appearance question in this project has
			# eventually needed it.
			if parts.size() >= 3 and _cam_rig != null and _cam_rig._cam != null:
				var wq := Vector3(float(parts[1]), 0.0, float(parts[2]) * _cam_rig.zstretch())
				var sq: Vector2 = _cam_rig._cam.unproject_position(wq)
				print("[screenpos] cell (%s,%s) -> (%d,%d)" % [parts[1], parts[2], int(sq.x), int(sq.y)])
		"inspect":
			# `inspect CX CY` — run the cell inspector at a ZONE CELL from outside (writes
			# selection.txt like a Ctrl+click). Closes the loop for tooling: no window focus
			# or mouse warp needed to ask "what did this cell render as?".
			if parts.size() >= 3 and _cam_rig != null and _cam_rig._cam != null:
				var wp := Vector3(float(parts[1]), 0.0, float(parts[2]) * _cam_rig.zstretch())
				var sp: Vector2 = _cam_rig._cam.unproject_position(wp)
				inspector.inspect_at(_cam_rig._cam, sp, _cam_rig.zstretch())
		"cam":
			if parts.size() > 1:
				_set_mode(clampi(int(parts[1]) - 1, 0, 7))   # 1-8 -> COMPASS..TOP_FOLLOW
		"mv":
			_multiview.toggle()   # all-views grid (same as the 0 key / the ` menu button)
		"pane":
			# `pane <i> rot <deg>` / `pane <i> zoom <mult>` — drive ONE pane's own camera state.
			# The camera menu's widgets will call the same Multiview methods; having them on the
			# command channel too is what lets the per-pane behaviour be TESTED without a mouse,
			# which is the only way to show that turning one pane leaves the other six alone.
			if parts.size() > 3:
				var pi := int(parts[1])
				match parts[2]:
					"rot": _multiview.pane_rotate(pi, float(parts[3]))
					"zoom": _multiview.pane_zoom(pi, float(parts[3]))
		"dbg":
			_dbg_menu.toggle()    # the ` debug menu (for headless UI checks)
		"profile":
			# `profile` — dump the Pareto to profile.txt and reset; `profile keep` dumps
			# without resetting. The F9/P keys' headless twin, for driving from outside.
			_dump_profile(parts.size() < 2 or String(parts[1]) != "keep")
		"cwtest":
			# summon the Creating World overlay over a LIVE game — the next snapshot flips it
			# to the embark modal, which is the whole flow minus an actual (save-destroying)
			# embark. The only honest way to test slice 4 against a running session.
			get_tree().root.add_child(load("res://CreatingWorldOverlay.gd").new())
		"spritedump":
			# `spritedump CX CY` — print every visual node whose footprint covers the cell:
			# type, position, modulate/albedo, texture id, visibility. The inspector reports
			# what was MEANT to render; this reports what the scene graph actually holds —
			# the difference is where the all-black-sprite class of bug lives.
			if parts.size() >= 3:
				var dcx := int(parts[1])
				var dcy := int(parts[2])
				var found := 0
				for nd in _walk_all(renderer):
					if not (nd is Node3D) or not (nd as Node3D).is_visible_in_tree():
						continue
					var cell2 := renderer._node_cell(nd)
					if cell2.x != dcx or cell2.y != dcy:
						continue
					found += 1
					var extra := ""
					if nd is SpriteBase3D:
						var sb := nd as SpriteBase3D
						var tx: Texture2D = sb.texture
						extra = "modulate=%s tex=%s(%s)" % [sb.modulate,
							(tx.get_size() if tx != null else Vector2.ZERO),
							(str(tx.get_instance_id()).right(6) if tx != null else "nil")]
					elif nd is MeshInstance3D:
						var mo2 := (nd as MeshInstance3D).material_override
						if mo2 is StandardMaterial3D:
							extra = "albedo=%s" % (mo2 as StandardMaterial3D).albedo_color
					print("[spritedump] %s %s pos=%s %s  path=%s" % [nd.get_class(), nd.name,
						(nd as Node3D).global_position, extra,
						str(nd.get_path()).replace(str(renderer.get_path()), "~")])
				print("[spritedump] %d node(s) over (%d,%d)" % [found, dcx, dcy])
		"fph":
			if parts.size() > 1:
				_cam_rig._fp_height = clampf(float(parts[1]), 0.15, 3.0)
		"onboard":
			# `onboard` opens the chooser; `onboard <screen>` jumps to a screen
			# (devices/ktype/layout/numpad/mouse); `onboard close` dismisses it.
			if parts.size() > 1 and parts[1] == "close":
				onboarding.close()
			elif parts.size() > 1:
				onboarding.show_screen(parts[1])
			else:
				onboarding.open()

var _bg_draw_accum := 0.0
const BG_DRAW_INTERVAL := 0.05   # ~20fps forced draws while unfocused

## One frame of the walk, then everything that follows the player is told where he is DRAWN rather
## than which cell he occupies: the camera, the sprite, and the torch he carries.
##
## THE PACE IS auto_walk_rate, the same setting a held direction key repeats at, so a held key
## produces continuous motion instead of a sprite that lurches and waits. A different number here
## would be a second, silent speed setting that disagrees with the one in Options.
## A RING OF THE LAST FEW FRAMES. Two bugs in a row here have been one-frame artefacts — the
## player drawn a frame ahead of itself, and now a torch that leads him — and every instrument I
## have samples slower than that: screenshots land 200ms apart and step straight over a 16ms pop.
## A history costs nothing per frame and turns "watch for the glitch" into "read what happened".
const WALK_LOG_N := 120
var _walk_log: Array = []

func _walk_log_frame() -> void:
	if renderer == null:
		return
	Profiler.begin("walklog")
	var e: Dictionary = renderer.walk_probe()
	# THE FIVE MODAL FLAGS. _playfield_cell refuses a click while any of them is up, so a single
	# one stuck true silently kills every click on the world while keys and the wheel carry on
	# working — which is exactly how this presented.
	e["modal"] = {
		"trade": _trade != null and _trade.active(),
		"popup": _popup != null and _popup.visible,
		"item_picker": _item_picker != null and _item_picker.visible,
		"cyber": _cyber != null and _cyber.visible,
		"overlay": overlay_check.is_valid() and bool(overlay_check.call()),
		"owns": _modal_owns_input(),
	}
	# ...AND THE THREE GATES BEFORE THEM. _playfield_cell returns null for four different reasons
	# and says which to nobody; a click that does nothing looks identical whichever it was.
	e["pick"] = {
		"inspector": inspector != null,
		"cam": _cam_rig != null and _cam_rig._cam != null,
		# THE GUARD THE MINIMAP DOES NOT GO THROUGH. _travel_click hands the click to the target
		# cursor before it considers travelling, so an active cursor eats every click on the world
		# while the minimap, which calls travel_to_cell directly, keeps working. That asymmetry is
		# the whole shape of "I cannot click to move but the arrow keys work", and it is the first
		# thing to read when that is reported again.
		"target_active": _target != null and _target.active,
	}
	# NOT the pick itself. Asking _playfield_cell here would raycast and walk the control tree
	# EVERY FRAME to answer a question that only matters when someone is reading the dump.
	e["at"] = [_walk_at.x, _walk_at.y]
	e["to"] = [_walk_to.x, _walk_to.y]
	_walk_log.append(e)
	if _walk_log.size() > WALK_LOG_N:
		_walk_log.remove_at(0)
	Profiler.done("walklog")


func _walk_step(dt: float) -> void:
	if not _walk_seeded or _cam_rig == null:
		return
	var was := _walk_at
	_walk_at = _SMOOTH.step(_walk_at, _walk_to, dt,
		maxf(1.0, float(Settings.get_value("auto_walk_rate", 6.0))))
	if _walk_at == was:
		return
	_cam_rig.set_player(Vector3(_walk_at.x, 0, _walk_at.y), Vector2.ZERO, false)
	if renderer != null:
		renderer.set_walk_offset(_walk_at - _walk_to)

func _process(dt: float) -> void:
	_walk_step(dt)
	_remote.poll(dt)
	_hold_step(dt)   # Final-Fantasy hold-to-walk: a held direction keeps stepping
	_assist_step()   # the cursor's verb, re-read at most once a frame
	if _picker.is_picking():
		_picker.update_cursor()
	# Keep the viewer rendering while its window is UNFOCUSED, so it stays live beside
	# Qud for side-by-side human testing (a human drives one window; both must move).
	# macOS pauses an unfocused window's draw, but _process still runs — so force a draw
	# at ~20fps (the same primitive the remote screenshot uses). Only when unfocused, to
	# avoid double-drawing over the normal focused render loop.
	if not get_window().has_focus():
		_bg_draw_accum += dt
		if _bg_draw_accum >= BG_DRAW_INTERVAL:
			_bg_draw_accum = 0.0
			RenderingServer.force_draw()

	# Camera modes, held-key zoom/fly, placement, and wall cutaway all live in the rig now.
	# THE SAME GUARD THE EVENT PATH USES, on the POLLED path — which is where it was missing.
	# _unhandled_input has consulted TypingGuard for a while; Input.is_key_pressed never did, and
	# does not consult focus at all, so the camera keys went on firing under a form's caret.
	_cam_rig.process(dt, _multiview.is_on(), TypingGuard.typing(get_viewport()))
	_walk_log_frame()   # LAST in the frame, so it records what will actually be drawn
	if _drone_marker != null:
		# ONLY WHILE THE SELECTOR IS OPEN. Daniel: "hide the drone after you select the camera. I
		# keep seeing it while I'm moving." The marker is a PLACEMENT AID — it exists so you can
		# see where the drone is while you are putting it somewhere, and once you are flying it
		# you are looking THROUGH it, so there is nothing left for it to tell you.
		#
		# It used to stay up whenever DRONECAM was the live mode, which is precisely when the main
		# camera sits inside it.
		_drone_marker.set_shown(_multiview.is_on())
		_drone_marker.place(_cam_rig.drone_pos())
	# ...AND THE CAMERA DROPS IT REGARDLESS. Hiding the node is the fix for what Daniel saw; this
	# is the invariant behind it — the drone never sees its own body, however the marker's
	# visibility is decided. The grid's own DRONECAM pane already did this; the MAIN camera never
	# did, which is why selecting the mode put an amber blob in the middle of the screen.
	_cam_rig.cull_drone_body(_cam_rig._mode == CamMode.DRONECAM)
	if _multiview.is_on():
		_multiview.update()

# ── hold to walk, and walk-in-a-direction ─────────────────────────────────────
#
# TWO DIFFERENT WALKS, and they answer different questions.
#
# HOLD-TO-WALK is Final Fantasy's: keep the direction down and you keep stepping, one tile at a
# time, at a rate the player sets. Daniel: "holding down the direction key will cause the player to
# walk in that direction, 1 tile at a time. User setting for auto-walk rate." It is a Raves input
# nicety — Qud sees ordinary single steps, so nothing about turns, interrupts or bookkeeping
# changes; only the number of key presses your hand has to make does.
#
# THE KEYCODE IS WHAT IS HELD, not the direction. Re-running the same key each repeat means turning
# the camera mid-walk turns the walk with it, because "forward" is a camera-relative question that
# has to be re-asked, not a compass letter cached at the first press.
#
# WALK-IN-A-DIRECTION is Qud's own CmdWalk (bound to W): pick a direction and go until something
# stops you. That one is the GAME's, interrupts and all, so it is a command sent once — see the
# mod's `walk`.
const HOLD_START := 0.28      # a tap must not become two steps; repeats begin after this
var _hold_key := 0            # the movement key currently held down, 0 for none
var _hold_intent := Vector2.ZERO   # its camera-relative intent (arrows), else ZERO
var _hold_abs := ""           # ...or its absolute compass direction (numpad)
var _hold_t := 0.0
var _hold_started := false
## True while W has been pressed and Raves is waiting for the direction to walk in.
var _walk_pending := false

## Remember what just moved the player, so holding the key keeps it moving. Called from the arrow
## and numpad handlers with whichever of the two forms they used.
func _hold_begin(key: int, intent: Vector2, abs_dir := "") -> void:
	_hold_key = key
	_hold_intent = intent
	_hold_abs = abs_dir
	_hold_t = 0.0
	_hold_started = false

## One tick of hold-to-walk. Polled rather than driven by the OS key-repeat, which has its own rate
## the player cannot set and which `_unhandled_input` deliberately drops (`not event.echo`).
func _hold_step(dt: float) -> void:
	if _hold_key == 0:
		return
	# THE SAME GUARDS THE EVENT PATH USES. A polled walk that ignored them would keep stepping under
	# an open status screen, which is the bug the modal check already exists to prevent.
	if not Input.is_key_pressed(_hold_key) or _modal_owns_input() \
			or TypingGuard.typing(get_viewport()):
		_hold_key = 0
		return
	_hold_t += dt
	var rate: float = maxf(1.0, float(Settings.get_value("auto_walk_rate", 6.0)))
	if _hold_t < (1.0 / rate if _hold_started else HOLD_START):
		return
	_hold_t = 0.0
	_hold_started = true
	if _hold_abs != "":
		client.send_command("move", {"dir": _hold_abs})
	else:
		_move_relative(_hold_intent)

## W pressed: Qud's CmdWalk, in two halves. Raves collects the DIRECTION first and sends both at
## once, because Qud's own flow opens a blocking direction prompt and a client that answered it late
## would leave the game parked on a prompt nobody can see.
func _walk_arm() -> void:
	_walk_pending = true
	walk_prompt.emit(true, "")

## The direction for an armed walk. Returns true if it consumed the key.
func _walk_answer(d: String) -> bool:
	if not _walk_pending:
		return false
	_walk_pending = false
	walk_prompt.emit(false, d)
	if d != "":
		client.send_command("walk", {"dir": d})
	return true

## Ask the mouse assist what is under the pointer. ONCE A FRAME, not once per motion event: the
## answer needs a raycast, and a mouse crossing the window emits far more events than there are
## frames to draw them in. The position is read from the viewport rather than remembered from an
## event, so it stays right when the world moves under a still pointer.
func _assist_step() -> void:
	# AIMING OUTRANKS THE VERB CURSOR. While Qud is asking for a target the only thing a click can
	# mean is "there" — so the reticle takes the pointer, and the boots/hand/speech icon that would
	# otherwise be promising a walk or a conversation gets out of the way.
	if _target != null and _target.active:
		if _assist != null:
			_assist.hover(Vector2.ZERO, null)
		_target.hover(_playfield_cell(get_viewport().get_mouse_position()))
		return
	if _assist == null:
		return
	if not _assist.enabled():
		_assist.hover(Vector2.ZERO, null)   # feature off mid-session: put the system arrow back
		return
	var pos: Vector2 = get_viewport().get_mouse_position()
	var cell = _playfield_cell(pos)
	# THE ICON MARKS THE TILE, so it is placed from the TILE — unprojected the same way `screenpos`
	# does it — rather than from the pointer. Anchoring it to the cursor meant it moved within the
	# tile as the pointer did, and sat under the arrow while it was there.
	_assist.hover(pos, cell)

## Move the player relative to the camera. `intent` is (strafe, forward) in screen
## space: (0,1)=forward, (0,-1)=back, (1,0)=right, (-1,0)=left.
func _move_relative(intent: Vector2) -> void:
	var d: String = _cam_rig.relative_compass(intent)
	if d == "":
		return
	# LOOK MODE STEERS THE CURSOR, NOT THE PLAYER. Same keys, same camera-relative mapping — the
	# only difference is what moves. Daniel: "the keyboard can be used on the playfield to move the
	# cursor. The control should be relative to the camera direction."
	if inspector != null and inspector.look_on():
		var c: Vector2i = inspector.look_move(_cam_rig.compass_delta(d))
		_report_look_cell(c)
		return
	client.send_command("move", {"dir": d})

## The cell at a LOOK-SPACE coordinate, which may lie outside the live zone.
##
## Look space is the live zone's cell grid EXTENDED: (-1,-1) is the last cell of the zone up and
## left, (80,0) the first of the zone east. That is the same space the darkness offsets and the
## surround band already work in, so a cursor can walk out of the zone the way the renderer already
## draws out of it. Daniel: "I need the look tool to be able to move into other zones so I can
## comment on transzone this-and-that."
##
## Returns {"zone": id, "cell": Dictionary, "local": Vector2i} — `cell` empty when nothing is
## there, which is a real answer (an empty tile) and not a failure.
func cell_at_look(c: Vector2i) -> Dictionary:
	var live := store.live_record()
	if live.is_empty():
		return {}
	var w := int(renderer._live_w)
	var h := int(renderer._live_h)
	if w <= 0 or h <= 0:
		return {}
	# Which zone owns it, by the same slot arithmetic the renderer uses for neighbour offsets.
	var sx := int(floor(float(c.x) / float(w)))
	var sy := int(floor(float(c.y) / float(h)))
	var local := Vector2i(c.x - sx * w, c.y - sy * h)
	var lo: Vector3i = live.get("origin", Vector3i.ZERO)
	var want := Vector3i(lo.x + sx * w, lo.y + sy * h, lo.z)
	var zid := store.live_id()
	if sx != 0 or sy != 0:
		zid = ""
		for id in store.ids():
			var rec: Dictionary = store.record(id)
			var o: Vector3i = rec.get("origin", Vector3i.ZERO)
			if o == want:
				zid = id
				break
		if zid == "":
			return {"zone": "", "cell": {}, "local": local}   # never visited: nothing to say
	var snap: Dictionary = store.record(zid).get("snapshot", {})
	for cd in snap.get("cells", []):
		if int(cd.get("x", -1)) == local.x and int(cd.get("y", -1)) == local.y:
			return {"zone": zid, "cell": cd, "local": local}
	return {"zone": zid, "cell": {}, "local": local}

## Announce the look cursor's cell so the message log can show it.
func _report_look_cell(c: Vector2i) -> void:
	if inspector != null:
		look_changed.emit(true, c, inspector.look_line(c.x, c.y))

## Open the look cursor ON THE PLAYER, or close it. Daniel: "it starts by highlighting the user."
## Starting anywhere else means hunting for the cursor before you can steer it, and the player is
## the one cell you can always find.
func look_toggle() -> void:
	if inspector == null:
		return
	if inspector.look_on():
		inspector.look_end()
		look_changed.emit(false, Vector2i.ZERO, "")
		return
	var pc: Dictionary = store.live_record().get("snapshot", {}).get("player", {})
	var c := Vector2i(int(pc.get("x", 0)), int(pc.get("y", 0)))
	inspector.look_begin(c)
	_report_look_cell(c)

## Write the full tile report for wherever the look cursor is — the deliberate, asked-for version
## of what a Ctrl+click does. Nothing pops up until this is pressed, which is the point of the mode.
func look_report() -> void:
	if inspector == null or not inspector.look_on():
		return
	inspector.report_look()
	# ...AND AIM THE REPORT FORM AT IT. "Report tile" is the name of the FORM — the thing that
	# picks the object on the tile and files a verdict against it — not of the read-only capture
	# the inspector panel shows. Opening only the panel gives you the text and none of the actions.
	# Daniel: "I clicked report tile. That opened up the inspector ... I cannot report the tile or
	# select the object on the tile. Or select one of the default modifications."
	#
	# Same pairing as _inspect(): the two panels are one gesture everywhere else, and the button
	# had reproduced half of it.
	var sel = inspector.selected_tile()
	if sel != null and reporter != null:
		reporter.set_target(sel.x, sel.y, inspector.zone_id(),
			inspector.last_objects(), inspector.last_report())

## Send a named Qud command (CmdFire, CmdReload, …) over the bridge — from a Raves hotkey or a UI
## button. The mod injects it into Qud's input like a keypress, so any targeting UI opens in the Qud
## window. No-op until the bridge is up.
func request_command(cmd: String) -> void:
	if client != null:
		client.send_command("command", {"command": cmd})

## Re-export Qud's journal — the cheap journal-only exporter, not the whole `export` run. The
## Locations panel polls this while it is open so a place discovered this turn shows up in the list.
func request_journal() -> void:
	if client != null:
		client.send_command("journal", {})

## Re-export QUD'S TRAVEL LOG — the parasangs it records the player as having visited, with the
## world map's own name for each. The other half of the Locations list; see the panel.
func request_places() -> void:
	if client != null:
		client.send_command("places", {})

## The Locations panel's ticked rows -> the horizon markers.
func set_beacons(targets: Array) -> void:
	if _beacons != null:
		_beacons.set_targets(targets)

## The Locations panel's signpost: label the beacons, or leave them unnamed.
func set_beacon_plates(on: bool) -> void:
	if _beacons != null:
		_beacons.plates_on = on

## Distance (parasangs) and bearing to a world-map cell, ASKED OF THE BEACON NODE so the number the
## panel prints and the column the player sees are the same measurement.
func beacon_metrics(mx: int, my: int) -> Dictionary:
	if _beacons == null:
		return {"para": 0.0, "dir": "?"}
	return {"para": _beacons.parasangs_to(mx, my), "dir": _beacons.bearing_to(mx, my)}

## Write a Qud option (Options.SetOption + re-export, mod-side on the uiQueue) — the nav
## overlay toggles use this to flip the same option ids Qud's own buttons persist.
func request_setoption(id: String, value: String) -> void:
	if client != null:
		client.send_command("setoption", {"id": id, "value": value})

## Back Qud out of its current MODERN screen (options/keybinds/records…). Those screens ignore every
## OS-synthesized key, so this first-party command is the only way out — the in-game Options and
## Control Mapping overlays use it to keep Qud in step when they close.
func request_uiback() -> void:
	if client != null:
		client.send_command("uiback")

## Invoke an inventory action (e.g. ReplaceSocketCell — "change the battery") on a specific equipped
## weapon, identified by its Qud GameObject id. Runs on Qud's main thread mod-side.
func request_item_action(item_id: String, action: String) -> void:
	if client != null:
		client.send_command("itemaction", {"item": item_id, "command": action})

## A Nearby Objects row was clicked: Qud's item menu for THAT object. The id is the mod's own
## finder-list id (see mod/Navigator.TwiddleNearby), so the object acted on is the one drawn.
func request_nearby(object_id: String) -> void:
	if client != null:
		client.send_command("nearby", {"id": object_id})

## Press one of Qud's OWN top-bar buttons by name. For the window lock there is no Option to set —
## its state lives on the button — so the only honest way to flip it is Qud's own onClick.
func request_nav_click(button: String) -> void:
	if client != null:
		client.send_command("navclick", {"button": button})

## A raw key into Qud's own queue, by NAME ("escape") or as a single character. Legacy screens —
## the Looker — read keys directly and ignore commands, so this is the only way to answer them.
func request_key(key: String) -> void:
	if client != null:
		client.send_command("key", {"key": key})

# --- direction picker (for abilities like Make Camp that prompt for a direction) ----------------
# Qud's PickDirection blocks the turn thread waiting for a LeftClick at a CELL (it derives the
# direction). We show the ability's icon as a cursor over the Holodeck; clicking an adjacent tile
# sends that cell (mod injects the click), a non-adjacent click / right-click / Esc cancels (mod
# injects a RightClick so Qud UNBLOCKS). Only started for abilities that actually prompt, else Qud
# would freeze waiting. The picker itself lives in DirectionPicker.gd; Main drives it from _process/_input.
var _picker                     # DirectionPicker (Node, loaded); created in _ready

## Public entry point — MainFrame calls this on the Holodeck when an ability prompts for a direction.
func start_direction_picker(icon: Texture2D) -> void:
	_picker.start(icon)

func _walk_all(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func _set_mode(m: int, force := false) -> void:
	# 1:1 (parity) mode locks the camera to the Qud-faithful top-down view — user camera
	# switches (number keys, Shift+C/K/F, multi-view) are ignored until 1:1 is turned off.
	# `force` is the internal path (set_one_to_one) that is allowed to change it.
	if _cam_locked() and not force:
		return
	if _multiview.is_on():
		_multiview.toggle()   # picking a mode leaves the multi-view grid
	# The rig does the camera part (state reset, billboard lay-down, zstretch) and reports if it changed.
	if _cam_rig.set_mode(m):
		_update_mode_label()
		_refresh_wm_cards_btn()   # keep the 2D/3D button label in sync
		# Announce ONLY on a real change (set_mode reports it), so re-picking the current camera
		# does not re-print its controls.
		camera_changed.emit(m, String(_MODE_NAMES.get(m, "")))

# --- 1:1 (parity) mode ------------------------------------------------------
# The master switch that flips Raves between the QoL "user" experience and a Qud-faithful
# "1:1" reproduction. Here it owns the CAMERA half (force + lock the top-down view) and
# announces changes; MainFrame owns the panel half + persistence via one_to_one_changed.
var _one_to_one := false
var _saved_cam_mode := -1      # user-mode camera, restored when leaving 1:1
var _saved_flat_2d := false    # user-mode tile mode (3D vs flat), restored when leaving 1:1
## `chosen` = the viewer asked for this (Ctrl+M / the highvisor button), as opposed to Raves
## APPLYING a mode at startup. Only a choice is persisted — see MainFrame._on_one_to_one_changed.
signal one_to_one_changed(on: bool, chosen: bool)
## Qud moved to a different CurrentGameView — its legacy screens (the Looker) arrive here, on the
## popup mirror's channel rather than the snapshot, because those screens stop snapshots.
signal qud_view_changed(name: String)

## The end-of-run tombstone is up (or gone). MainFrame listens: while it is up, the heartbeat that
## returns Raves to the title has to WAIT, or the two windows disagree about where the player is.
signal tombstone_changed(up: bool)

## A camera mode actually CHANGED (the rig confirmed it). Carries the mode and its controls line
## from _MODE_NAMES, so MainFrame can print the controls without keeping its own copy of them.
signal camera_changed(mode: int, controls: String)
## The look cursor moved (or opened/closed). `on` false means it left look mode. MainFrame prints
## the line to the message log and keeps its "report tile" button pointed at the same cell — the
## frame owns the log, and Main owns the cursor, so this is the seam between them.
signal look_changed(on: bool, cell: Vector2i, line: String)

## W has armed a walk and is waiting for a direction (or has stopped waiting). The frame prints the
## prompt: this mode has no window of its own, and a key that silently changes what the NEXT key
## means is the look cursor's trap all over again.
signal walk_prompt(armed: bool, dir: String)

func is_one_to_one() -> bool:
	return _one_to_one

## Is the CAMERA locked to Qud's top-down? Its own question, because `_one_to_one` answers three at
## once -- camera, lighting model and flat-tile rendering -- and the first QoL feature loaded back
## (Daniel, 2026-08-12: "let's restore the user-mode cameras") wants exactly one of them. 1:1 mode
## still locks it: `qud_shape` short-circuits on the mode before it ever looks at the feature.
func _cam_locked() -> bool:
	return Settings.qud_shape("cameras")

## Is the TILE MODEL locked to Qud's flat rendering? The third face of the old `_one_to_one`
## (after camera and lighting), split out for the `tiles3d` QoL feature. Locked = flat, as loaded,
## live zone only; unlocked = the viewer's own 3D/flat choice (the O key), neighbours in 3D.
func _tiles_locked() -> bool:
	return Settings.qud_shape("tiles3d")

func set_one_to_one(on: bool, chosen := false) -> void:
	if on == _one_to_one:
		return
	_one_to_one = on
	# Camera half — asks _cam_locked(), NOT `on`: with the `cameras` QoL feature loaded back, user
	# mode keeps Qud's lighting and flat tiles while the viewer drives their own camera again.
	var cam := _cam_locked()
	_cam_rig.set_one_to_one(cam)   # 1:1 vs user ortho span (safe in data-only; guards a null camera)
	# Only meaningful with the 3D viewport up (data-only mode has no camera to flip);
	# set_render_3d re-applies TOP_FOLLOW when the viewport comes on.
	if cam:
		_saved_cam_mode = _cam_rig._mode
		if render_3d:
			_set_mode(CamMode.TOP_FOLLOW, true)   # the Qud-faithful 1:1 top-down (ONE_TO_ONE_SPAN)
	elif render_3d and _saved_cam_mode >= 0:
		_set_mode(_saved_cam_mode, true)          # back to the user's camera
	# Lighting half: 1:1 uses Qud's rectangular model (see ZoneRenderer) — no glow pools, flames,
	# smoke or motes are LOADED, unexplored cells draw nothing, explored-dark cells get the flat
	# memory dim. Set BEFORE the flat rebuild below so the rebuild uses the 1:1 light rules.
	# The renderer asks the TILES question, not the mode. Its 1:1 is not merely a light table --
	# it is the flat render architecture itself: statics (the voxel walls) are never BUILT in 1:1,
	# every cell draws in the per-turn winner-only pass, and the ghost/memory recolour lives inside
	# that pass. "Voxel walls under 1:1 rendering" is not a mode that exists, so loading tiles3d
	# back necessarily brings the renderer's user world model (glow pools, per-sprite dim) with it.
	if renderer != null:
		renderer.set_one_to_one(_tiles_locked())
	# Tile half: Qud renders every tile FLAT, as loaded — the voxel walls / stretched-UV 3D look is a
	# user-mode feature. 1:1 forces the flat path (which also renders ONLY the live zone — see
	# _neighbor_zones); leaving 1:1 restores whatever the user had. Ordered after the camera flip so
	# the rebuild happens under the final top-down stretch. (Set _one_to_one first — _toggle_flat_2d
	# is locked while on, so go through _apply_flat_2d directly.)
	# Asks _tiles_locked(), not `on`: with `tiles3d` loaded back, user mode keeps Qud's lighting
	# while the voxel walls return. The rebuild still happens either way — the LIGHT rules changed
	# above, and the geometry must be rebuilt under them.
	if _tiles_locked():
		_saved_flat_2d = _flat_2d
		_apply_flat_2d(true)               # rebuild even if already flat — the light rules changed
	else:
		_apply_flat_2d(_saved_flat_2d)     # the viewer's own tile mode (3D by default)
	one_to_one_changed.emit(on, chosen)

## The Options overlay's "Default camera" row, applied LIVE (MainFrame wires this through
## OptionsScreen.apply_camera_cb). Same path as the number keys, same lock: while the cameras
## feature is off, _set_mode ignores it and the setting simply waits for the next build.
func set_camera_mode(m: int) -> void:
	_set_mode(clampi(m, 0, CamMode.TOP_FOLLOW))

## Open/close the camera grid — what `0` does, exposed for MainFrame's toolbar button. Honours the
## 1:1 camera lock for the same reason the key does: in parity mode the camera is not the viewer's.
func toggle_camera_menu() -> void:
	if _cam_locked():
		return
	_multiview.toggle()

func toggle_one_to_one() -> void:
	set_one_to_one(not _one_to_one, true)   # a viewer choice: this one sticks

## MainFrame tells us how much of the window the 1:1 side panels cover (0..~0.4). The camera shifts its
## lens so the zone-fit centres in the visible play hole (left of the sidebar), not the full window.
func set_ui_right_inset(frac: float) -> void:
	_ui_right_inset = clampf(frac, 0.0, 0.6)
	if _cam_rig != null:
		_cam_rig.set_right_inset(_ui_right_inset)

## MainFrame pushes the play hole's actual px rect (row 3's transparent area). The 1:1 camera fits
## Qud's 80x25 stage into THIS rect (both axes) at Qud's letterbox scale — the pixel-1:1 model.
func set_play_hole_rect(r: Rect2) -> void:
	if _cam_rig != null:
		_cam_rig.set_play_hole(r)
	# The beacon name-plates are HUD controls over the same hole; outside it the side panels are
	# opaque and a plate would slide under the message log.
	if _beacons != null:
		_beacons.set_play_hole(r)
	if _target != null:
		_target.set_play_hole(r)

## One gesture -> everything a collaborator needs about a tile. Photograph the BARE
## scene FIRST (no selection overlay), then inspect — so shot.png is a clean plate
## of the tile, paired with the report (selection.txt) and Qud's view (qud_shot.png).
func _inspect_and_capture() -> void:
	await _screenshot(true)
	_inspect()

## Clear everything a selection put on screen: report form, inspector panel, marker.
## Bound to Esc and to the form's Cancel button.
func _dismiss_selection() -> void:
	inspector.hide_panel()
	reporter.hide_panel()

## Inspect, and aim the report form at the same tile.
func _inspect() -> void:
	inspector.inspect_at(_cam_rig._cam, get_viewport().get_mouse_position(), _cam_rig.zstretch())
	var sel = inspector.selected_tile()
	if sel != null:
		reporter.set_target(sel.x, sel.y, inspector.zone_id(),
			inspector.last_objects(), inspector.last_report())

## RIGHT-CLICK: Qud's context interaction on the clicked tile — the object's menu, which comes
## back over the popup mirror. Qud's own handler picks the object and decides what right-clicking
## it means (see mod/Navigator.Interact); all we carry is the cell.
func _interact_click(pos: Vector2) -> void:
	var cell = _playfield_cell(pos)
	if cell == null:
		return
	interact_at_cell(Vector2i(cell.x, cell.y))


## The same interaction, addressed by CELL. The minimap has a cell and no screen ray, so both
## surfaces meet here rather than each having its own idea of what a right-click does.
func interact_at_cell(c: Vector2i) -> void:
	client.send_command("interact", {"x": c.x, "y": c.y})


## CLICK-TO-TRAVEL. Send the clicked cell to Qud, which walks the player there with its own
## MoveTo goal (see mod/Navigator.cs) -- pathing, doors and hostile-interrupts are Qud's, not ours.
##
## The cell comes from the INSPECTOR's picking, not a second mapping of our own: travel then lands
## on exactly the cell Ctrl+click reports, wall-snapping included.
## A left click on the playfield. THE CURSOR ALREADY SAID WHAT THIS WOULD DO, so this does that:
## the icon and the action come from one answer (MouseAssist.verb_at), which is the only way the
## promise can be kept. Without assist it stays what it always was — a walk order.
##
## REACH DECIDES TALK-VERSUS-WALK. Qud's own interact handler acts on an ADJACENT cell; asked about
## a person across the room it does nothing at all, and a cursor that promised a conversation would
## have lied. So out of reach every verb walks you there, which is the first half of what you wanted
## anyway, and the icon is then telling you what you will find when you arrive.
func _travel_click(pos: Vector2) -> void:
	var cell = _playfield_cell(pos)
	# THE PICKER GETS THE CLICK, and gets it even off the playfield: a click that lands on chrome
	# while Qud is waiting for a target must not fall through and order a walk the moment the shot
	# resolves. This is the bug as reported — the click went to the verb table and chatted at a
	# Dawnglider — so the guard is FIRST, before the cell is even required.
	if _target != null and _target.active:
		_target.click(cell)
		return
	if cell == null:
		return
	travel_to_cell(Vector2i(cell.x, cell.y))


## Travel addressed by CELL — everything below this line was the back half of _travel_click, and it
## never needed the screen position, only the cell the position resolved to. Split out so the
## minimap can order exactly the same walk: the off-zone edge case, the reach test, the verb the
## cursor promised. A second copy of this on the map would drift from this one within a week.
func travel_to_cell(c: Vector2i) -> void:
	# CLICKED INTO A NEIGHBOUR ZONE. Daniel: "You need to be able to walk off-zone using the mouse."
	# Raves draws the zones either side, so clicking into one is the obvious way to ask to go there
	# -- and it did nothing, because a click becomes `moveto` and Qud's travel only addresses cells
	# in the CURRENT zone. The mod logged "outside the zone" and stopped.
	if _edge_dir(c) != "":
		client.send_command("moveedge", {"dir": _edge_dir(c)})
		return
	var verb: String = _assist.verb_at(c) if (_assist != null and _assist.enabled()) else "walk"
	var pc: Dictionary = store.live_record().get("snapshot", {}).get("player", {})
	var here := Vector2i(int(pc.get("x", -999)), int(pc.get("y", -999)))
	var adjacent: bool = maxi(absi(c.x - here.x), absi(c.y - here.y)) <= 1
	match verb:
		"down", "up":
			# Standing on them, use them; otherwise walk over and the arrow will still be there.
			if c == here:
				client.send_command("command", {"command": "CmdMoveD" if verb == "down" else "CmdMoveU"})
				return
		"talk", "use":
			if adjacent:
				client.send_command("interact", {"x": c.x, "y": c.y})
				return
	client.send_command("moveto", {"x": c.x, "y": c.y})


## The zone cell a playfield click lands on, or null if this click is not the playfield's to have.
## Shared by both buttons so travel and interact can never disagree about either half of that.
func _playfield_cell(pos: Vector2) -> Variant:
	if inspector == null or _cam_rig == null or _cam_rig._cam == null:
		return null
	# claims() is the same "is this UI chrome?" test the Cmd+right-click branch above uses -- the
	# play hole carries feedback_skip, every panel and screen does not.
	if FeedbackTool.claims(pos):
		return null
	# A modal owns the whole screen even where it does not paint: clicking the visible playfield
	# behind a popup must not quietly order a walk, or open a second menu behind the first.
	if _modal_owns_input():
		return null
	return inspector.cell_at(_cam_rig._cam, pos, _cam_rig.zstretch())

## Is a modal (mirrored Qud popup, item picker, or a MainFrame overlay — status screens /
## control mapping / options) currently in charge of input? One definition, because this
## question is asked from four places and the copies drifted: the mouse branch of
## `_unhandled_input` never asked it at all, which is how a wheel over the skills list
## zoomed the playfield behind the modal (2026-08-10).
func _modal_owns_input() -> bool:
	return (_trade != null and _trade.active()) \
		or (_popup != null and _popup.visible) \
		or (_item_picker != null and _item_picker.visible) \
		or (_cyber != null and _cyber.visible) \
		or (overlay_check.is_valid() and bool(overlay_check.call()))

## Inspect from a multi-view pane: raycast with that pane's camera + the pane-local mouse
## position. The 3D marker is shared, so the pick shows across every pane.
func _multiview_inspect(cam: Camera3D, pos: Vector2) -> void:
	inspector.inspect_at(cam, pos)
	var sel = inspector.selected_tile()
	if sel != null:
		reporter.set_target(sel.x, sel.y, inspector.zone_id(),
			inspector.last_objects(), inspector.last_report())

## Write the Pareto timing report to profile.txt (Claude reads it). Auto-called every
## 40 turns (reset=false, cumulative), and by the P key (reset=true, fresh window).
func _dump_profile(reset := true) -> void:
	# THE SUPPORT DIR, like every other dump. This derived its path from the RENDERER's tiles_dir
	# and returned silently when that was empty — so asking for a profile did nothing at all, with
	# a stale report still sitting on disk to be mistaken for the answer. It was, twice.
	var dir := _support_dir()
	if dir == "":
		return
	var f := FileAccess.open(dir.path_join("profile.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string(Profiler.report())
		f.close()
	if reset:
		Profiler.reset()

## Save the viewport to a known path so a collaborator can just read it.
##
## The OS-level `screencapture` is blocked without Screen Recording permission,
## and this is better anyway: it captures the rendered viewport exactly, with no
## window chrome and nothing overlapping it.
func _screenshot(clean := false, forced := false) -> void:
	var dir := _support_dir()
	if dir == "":
		return
	# `clean` drops the WHOLE selection overlay — report panel and 3D marker — out of
	# frame, so the shot is a bare plate of the scene; restored right after.
	var restore := false
	if clean and inspector.overlay_visible():
		inspector.set_overlay_visible(false)
		restore = true
	if forced:
		# a remote (control.py) shot: the window is unfocused so no frame is being
		# drawn and `await frame_post_draw` would hang forever. Force one now.
		RenderingServer.force_draw()
	else:
		await RenderingServer.frame_post_draw      # let the frame finish first
	var img := get_viewport().get_texture().get_image()
	if restore:
		inspector.set_overlay_visible(true)
	if img == null:
		return
	var path := dir.path_join("shot.png")
	if img.save_png(path) == OK:
		# ask Qud to capture itself too, so the pair can be compared side by side
		client.send_command("shot", {})
		_mode_label.text = "saved shot.png + asked Qud for qud_shot.png"

func _build_mode_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_mode_label = Label.new()
	_mode_label.position = Vector2(14, 8)
	_mode_label.add_theme_font_size_override("font_size", UiFont.px(get_viewport()))  # _apply_ui_fonts keeps it live
	_mode_label.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	layer.add_child(_mode_label)
	_update_mode_label()

const _MODE_NAMES := {
	CamMode.COMPASS: "COMPASS — cardinal-locked · arrows move (↑=fwd) · Q/E rotate · R/F zoom · S/D height · W/X dolly",
	CamMode.FOLLOW: "3RD-PERSON — ↑↓ move (↓ backs up) · ←→ turn · Ctrl+Shift+←→ strafe · R/F zoom · S/D height · W/X dolly",
	CamMode.ADVENTURE: "ADVENTURE — compass-locked · height/distance/angle sliders in Options · Q/E rotate",
	CamMode.FIRST_PERSON: "FIRST-PERSON — ↑↓ move · ←→ turn · Ctrl+Shift+←→ strafe · Shift+arrows diagonal",
	CamMode.CINEMATIC: "CINEMATIC — frames you + selected tile",
	# Named as the ENUM and the Options "Default camera" list name them. These heads are the
	# multiview pane captions and the HUD mode hint, and they read ORBIT / FLY for years after
	# the modes were renamed -- two names for one camera, in the two places a viewer compares.
	CamMode.MOUSE: "MOUSE — drag orbits the selected tile",
	CamMode.KEYBOARD: "KEYBOARD — WASD move, arrows aim",
	CamMode.TOP_FOLLOW: "TOP-DOWN FOLLOW — classic overhead · north up · tracks you · R/F zoom",
	CamMode.DRONECAM: "DRONECAM — first person from the drone · ring flies it · ▲▼ height · rotate to turn",
}

func _update_mode_label() -> void:
	_mode_label.text = "camera: %s     ·  ` menu · 1-7 · 0 all-views · F1 controls" % _MODE_NAMES.get(_cam_rig._mode, "?")
	if _sky_grade != null and _sky_grade.time_label != "":
		_mode_label.text += "     ⏱ " + _sky_grade.time_label
	if _dbg_menu != null:
		_dbg_menu.set_active_mode(_cam_rig._mode)   # highlight the active mode button

# --- debug menu -------------------------------------------------------------

# --- world 2D/3D toggle (shared: the ` menu's face button, the O key, and the persistent top-right btn) ---
var _flat_2d := false   # false = 3D upright billboards, true = everything flat on the floor (2D map)

## Flip the WHOLE world — every stratum — between 3D (upright billboards + wall blocks) and 2D
## (everything laid flat on the floor, a classic top-down map). The renderer drops its frozen
## geometry, so re-render the current snapshot to rebuild the live zone (and neighbours) in the new
## mode — instant feedback instead of waiting for the next turn.
## 1:1 FORCES flat (Qud renders tiles flat, as loaded — the 3D wall stretch/UV mapping is a user-mode
## feature), so the toggle is locked out while 1:1 is on, like the camera modes.
func _toggle_flat_2d() -> void:
	if _tiles_locked():
		return                       # Qud's shape owns the tile mode (flat) until tiles3d is loaded back
	_apply_flat_2d(not _flat_2d)

## The shared apply path (O toggle + the 1:1 master switch): set the renderer mode, rebuild the
## current snapshot in it, and sync the two UI mirrors of the state.
func _apply_flat_2d(on: bool) -> void:
	_flat_2d = on
	renderer.set_flat_2d(on)
	var live: Dictionary = store.live_snapshot()
	if not live.is_empty():
		renderer.render_snapshot(live, _neighbor_zones())
	if _dbg_menu != null:
		_dbg_menu.refresh_flat_2d(_flat_2d)   # the ` menu's mirror of this state
	_refresh_wm_cards_btn()

## Label for the persistent top-right button — the current tile mode (3D up vs 2D flat).
func _refresh_wm_cards_btn() -> void:
	if _wm_cards_btn == null:
		return
	_wm_cards_btn.text = "tiles (O): %s" % ("2D flat" if _flat_2d else "3D up")

## Live-apply the deep-water depth: creatures are re-cropped in the dynamic pass, so
## re-render the current snapshot (same zone -> only the cheap dynamics rebuild) for
## instant feedback instead of waiting for the next turn.
func _on_water_depth_changed(v: float) -> void:
	renderer.deep_water_depth = v
	var live: Dictionary = store.live_snapshot()
	if not live.is_empty():
		renderer.render_snapshot(live, _neighbor_zones())

## Live-apply the level gap: only neighbour subtree positions change, so a re-render
## just repositions the already-built stacks (no rebuild) — instant feedback.
func _on_level_height_changed(v: float) -> void:
	renderer.level_height = v
	var live: Dictionary = store.live_snapshot()
	if not live.is_empty():
		renderer.render_snapshot(live, _neighbor_zones())

## Top-right corner buttons, stacked in a VBox so they never overlap at any font size:
##   ⟳ Reset            — restarts the whole program (picks up code changes) at the current size
##   WM cards (O)       — the world-map card orientation toggle, with its live state on the label
func _build_reset_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	# A VBox pinned to the top-right corner (grow LEFT to fit the widest label, DOWN to stack).
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_END
	box.offset_left = -10.0
	box.offset_right = -10.0
	box.offset_top = 10.0
	box.add_theme_constant_override("separation", 6)
	layer.add_child(box)

	_reset_btn = Button.new()
	_reset_btn.text = "⟳ Reset"
	_reset_btn.focus_mode = Control.FOCUS_NONE   # click-only; keep arrows for the player
	_reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_END   # hug the right edge under the anchor
	_reset_btn.pressed.connect(_reset_program)
	box.add_child(_reset_btn)

	# The 2D/3D toggle, surfaced as a persistent button (not just the ` debug menu and the O key) so
	# its effect is discoverable — the label shows the current tile mode (3D up vs 2D flat).
	_wm_cards_btn = Button.new()
	_wm_cards_btn.focus_mode = Control.FOCUS_NONE
	_wm_cards_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_wm_cards_btn.pressed.connect(_toggle_flat_2d)
	box.add_child(_wm_cards_btn)
	_refresh_wm_cards_btn()

	_reset_btn.add_theme_font_size_override("font_size", UiFont.px(get_viewport()))
	_wm_cards_btn.add_theme_font_size_override("font_size", UiFont.px(get_viewport()))

## Relaunch the process, preserving the current window size via --resolution (a plain
## reload_current_scene would keep the old cached scripts; a restart re-reads them).
func _reset_program() -> void:
	_save_settings()   # persist before the restart (quit() doesn't fire WM_CLOSE_REQUEST)
	var sz := DisplayServer.window_get_size()
	var restart := PackedStringArray(["--resolution", "%dx%d" % [sz.x, sz.y]])
	# If highvisor launched us in --launch-qud mode, re-pass those user args so the
	# restarted instance stays borderless and re-adopts the still-running Qud (the
	# quit() below doesn't fire WM_CLOSE_REQUEST, so QudLauncher leaves Qud alive).
	var qargs := QudLauncher.relaunch_args()
	if not qargs.is_empty():
		restart.append("--")
		restart.append_array(qargs)
	OS.set_restart_on_exit(true, restart)
	get_tree().quit()

## Save on window close (the X); the Reset button saves explicitly in _reset_program.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_settings()

## Persist the view/render settings a run should remember.
func _dc_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _save_settings() -> void:
	# The view file belongs to USER mode. A 1:1 run forces the stage's camera (TOP_FOLLOW),
	# window and zoom, and writing ANY of that back hands the next user-mode launch state it
	# never chose. The `win` key learned this first (a parity run's stage size overwrote the
	# user's); `mode` had the same leak and its bite was subtler — the restore put the
	# renderer top-down before the first static build, so depth halos placed hidden and
	# statics never rebuild on a camera change. One guard now covers the whole file.
	if Settings.one_to_one():
		return
	var sz := DisplayServer.window_get_size()
	var keep_win: Variant = null
	if FileAccess.file_exists(SETTINGS_PATH):
		var pf := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if pf != null:
			var prev: Variant = JSON.parse_string(pf.get_as_text())
			pf.close()
			if prev is Dictionary:
				keep_win = prev.get("win", null)
	var d := {
		"mode": _cam_rig._mode,
		"cam_ver": 3,                      # 2: COMPASS_YAW_DEFAULT flipped to north. 3: per-game heading
		# NORMALISED. Q/E accumulate without wrapping, so a well-used session stores things
		# like 4*PI — mathematically south, but not a value any comparison would recognise
		# as the default (that is exactly what defeated the cam_ver 2 migration first try).
		"compass_yaw": fposmod(_cam_rig._compass_yaw, TAU),
		# WHOSE heading this is. The compass is an orientation IN A WORLD, not a preference like
		# zoom, so carrying it into a different game is carrying something that no longer refers
		# to anything. Daniel, on a new character: "the camera is on compass facing west. The
		# camera should default to north on a new game ... maybe it's remembering the camera from
		# the last loaded game." It was — the view file is global, so every new character
		# inherited whatever heading the previous session ended on.
		"compass_game": _cam_game_id,
		"compass_45": _cam_rig._compass_45,
		"look_head": _cam_rig._look_head,
		"dist": _cam_rig._dist,
		"top_zoom": _cam_rig._top_zoom,
		"fp_height": _cam_rig._fp_height,
		"water_depth": (renderer.deep_water_depth if renderer != null else 0.6),
		"level_height": (renderer.level_height if renderer != null else 4.0),
		"depthcue": (_dc_to_array(_sky_grade.depthcue_params()) + [_sky_grade.depthcue_curve()] if _sky_grade != null else [0.25, 5.0, 0.58, 3]),
		"win": (keep_win if keep_win != null else [sz.x, sz.y]),
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()

## Restore what _save_settings wrote. Sets values only (no _set_mode — the label isn't
## built yet); the mode's camera/renderer setup follows from the rig's _mode in its _update_camera and
## the set_top_down call here. Missing/invalid keys keep the code defaults.
func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	# A view file written before cam_ver 2 stored the OLD default heading (0.0 = facing
	# south) whether or not its owner ever chose it, so restoring it verbatim would keep
	# every existing user pointing south forever. Treat exactly-the-old-default as unset
	# and take the new one; any yaw they actually turned to survives untouched.
	var yaw := fposmod(float(d.get("compass_yaw", _cam_rig._compass_yaw)), TAU)
	var ver := int(d.get("cam_ver", 1))
	if ver < 2 and minf(yaw, TAU - yaw) < 0.01:
		yaw = _cam_rig.COMPASS_YAW_DEFAULT
	if ver < 3:
		# A heading written before cam_ver 3 has no game recorded against it, so there is no way to
		# tell whose it is — and the odds are it belongs to whatever was played last, not to the
		# game about to load. Take the default once; from here every heading is stamped with its
		# game (see _check_camera_game) and only ever resets when the game actually changes.
		yaw = _cam_rig.COMPASS_YAW_DEFAULT
	_cam_rig._compass_yaw = yaw
	_cam_game_id = String(d.get("compass_game", ""))
	_cam_rig._compass_45 = bool(d.get("compass_45", _cam_rig._compass_45))
	_cam_rig._look_head = bool(d.get("look_head", _cam_rig._look_head))
	_cam_rig._dist = clampf(float(d.get("dist", _cam_rig._dist)), _cam_rig.DIST_MIN, _cam_rig.DIST_MAX)
	_cam_rig._top_zoom = clampf(float(d.get("top_zoom", _cam_rig._top_zoom)), _cam_rig.TOP_ZOOM_MIN, _cam_rig.TOP_ZOOM_MAX)
	_cam_rig._fp_height = clampf(float(d.get("fp_height", _cam_rig._fp_height)), 0.15, 3.0)
	if renderer != null:
		renderer.deep_water_depth = clampf(float(d.get("water_depth", renderer.deep_water_depth)), 0.0, 1.0)
		renderer.level_height = clampf(float(d.get("level_height", renderer.level_height)), 0.0, 16.0)
	var dc = d.get("depthcue", null)
	if dc is Array and dc.size() >= 3 and _sky_grade != null:
		_sky_grade.set_depthcue_params(float(dc[0]), float(dc[1]), float(dc[2]))
		if dc.size() >= 4:
			_sky_grade.set_depthcue_curve(int(dc[3]))
	var win = d.get("win", null)
	# Skip in launch-qud mode: QudLauncher owns the window geometry there (borderless
	# quadrant), and a saved size would fight it when entering gameplay.
	#
	# Skip in 1:1 mode for the same reason, one layer out: the STAGE owns geometry there
	# (hv layout / the cockpit buttons), and Raves must match Qud's window exactly or every
	# parity leaf rect means a different thing in each app. This restore fired late enough
	# to look like something else entirely -- `hv restart raves` placed the window
	# correctly, then loading the Holodeck for a status tab resized it back to a saved
	# 4267x2400, so captures came back 2400 tall against a 1080-tall spec and the blame
	# went to the restart racing the window. It was this, on a completely different clock.
	if win is Array and win.size() == 2 and int(win[0]) > 200 and int(win[1]) > 200 \
			and not QudLauncher.active and not Settings.clone_of_qud():
		DisplayServer.window_set_size(Vector2i(int(win[0]), int(win[1])))
	var m := int(d.get("mode", _cam_rig._mode))
	if m >= 0 and m <= CamMode.TOP_FOLLOW:
		_cam_rig._mode = m
		if renderer != null:
			renderer.set_top_down(m == CamMode.TOP_FOLLOW)

# --- input ------------------------------------------------------------------

## Direction-picker input is handled in _input (BEFORE the GUI), because the frame's container Controls
## consume mouse clicks over the Holodeck before they'd reach _unhandled_input. Only consumes while
## picking; otherwise events flow to the GUI / _unhandled_input as normal.
func _input(event: InputEvent) -> void:
	if _picker.is_picking() and _picker.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	# Inspect clicks must be caught HERE (before the GUI): when the Holodeck is embedded in MainFrame, the
	# frame's container Controls eat mouse clicks over it before _unhandled_input — the same reason the
	# picker lives here. Ctrl/Cmd+click inspects; Ctrl/Cmd+right-click inspects AND photographs both apps.
	# (Non-inspect mouse — MOUSE-mode orbit/pan, wheel zoom — stays in _unhandled_input.)
	if event is InputEventMouseButton and event.pressed and (event.ctrl_pressed or event.meta_pressed):
		if event.button_index == MOUSE_BUTTON_LEFT:
			_inspect()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Cmd+Right-click over UI CHROME belongs to the element-feedback form, and the scene
			# sees _input before autoloads — consuming unconditionally here starved FeedbackTool
			# of every such click in-game. Over the playfield claims() is false and we inspect.
			if FeedbackTool.claims(event.position):
				return
			_inspect_and_capture()
			get_viewport().set_input_as_handled()
		return
	# CLICK-TO-TRAVEL. A plain left click on the playfield walks the player there, as in Qud.
	# Decided on RELEASE, and only when the mouse barely moved: in MOUSE mode this same button
	# drags the camera orbit, and a drag must not also be a travel order.
	# Deliberately NOT consumed -- the release still has to reach _unhandled_input to END that
	# orbit; swallowing it leaves the camera spinning with the button already up.
	# …and a plain RIGHT click is Qud's context interaction on that tile. Same click-not-drag
	# discipline (right-drag pans in MOUSE mode), same reason for not consuming it.
	if event is InputEventMouseButton \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed or event.shift_pressed):
		if event.pressed:
			# ARMED ON THE PRESS, and only if the press itself was the playfield's to have.
			#
			# The release-time guard in _playfield_cell was already right and already too late:
			# clicking a popup option answers it on PRESS, so the popup is gone by the time the
			# RELEASE arrives, _modal_owns_input() answers false, and the click that dismissed the
			# menu also ordered a walk to whatever was behind it. Daniel: "Clicking on the popup
			# also clicks on the playfield and orders the character to move to that click location."
			#
			# Asking at press time asks while the thing that owns the click still exists. It also
			# settles the quieter half of the same bug — a press on the message log or any other
			# panel armed the gesture too, because _input runs before the GUI and never saw the
			# chrome that swallowed it.
			_travel_press = event.position if _playfield_cell(event.position) != null else null
		else:
			var press = _travel_press
			_travel_press = null
			if press != null and event.position.distance_to(press) <= TRAVEL_SLOP:
				if event.button_index == MOUSE_BUTTON_LEFT:
					_travel_click(event.position)
				elif _target != null and _target.active:
					_target.click(_playfield_cell(event.position), true)   # right-click calls it off
				else:
					_interact_click(event.position)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# TYPING GUARD, and it is NOT redundant here. `_unhandled_input` only sees keys the GUI did
		# not consume -- which is not "no keys while a field has focus": a field consumes what it
		# has a use for and ignores the rest, and modifier combos are exactly the rest. Measured
		# with the feedback note focused: letters landed in the box, and Ctrl+Shift+X ran Qud's xp
		# wish (0 -> 150 Exp). Everything below dispatches to QUD -- moves, waits, wishes, and
		# `_binds.match_event`, which runs whatever the player has bound -- so it is all off-limits
		# while someone is typing.
		if TypingGuard.typing(get_viewport()):
			return
		# THE TERMINAL EATS KEYS FIRST while it is up: it is a modal, and arrows/Space/Esc mean
		# navigate/accept/quit INSIDE it, not move/wait/system-menu in the game underneath.
		if _cyber != null and _cyber.visible and _cyber.handle_key(event):
			get_viewport().set_input_as_handled()
			return
		# Shift+Space: wait a turn in Qud (a Godot->Qud passthrough). Takes a turn for now.
		if event.shift_pressed and event.keycode == KEY_SPACE:
			client.send_command("wait", {}); return
		# F1 opens the controls chooser. (While it's open it swallows input via its
		# own _input, so this handler won't see keys until it closes.)
		if event.keycode == KEY_F1:
			onboarding.open(); return
		# Ctrl+M: toggle 1:1 (parity) mode — camera + panels flip to Qud-faithful, and back.
		# Ctrl (not Cmd, which is macOS "minimize"); the highvisor 1:1 button injects this same key.
		if event.keycode == KEY_M and event.ctrl_pressed \
				and not (event.meta_pressed or event.shift_pressed or event.alt_pressed):
			toggle_one_to_one(); return
		# Ctrl+Shift+W: Qud's wish shortcut. Opens a text prompt in Raves; on Enter we ship the wish
		# to Qud over the bridge (it runs Qud's own wish handler). Lets us grant xp, spawn items, etc.
		if event.keycode == KEY_W and event.ctrl_pressed and event.shift_pressed \
				and not event.meta_pressed:
			_open_wish(); return
		# Dedicated stress-test wishes (single combo, no text prompt) — bump the EXP / HP bars straight
		# from Qud's own wish handler. X = +150 xp, H = -3 hp (hurt), J = full heal.
		if event.ctrl_pressed and event.shift_pressed and not event.meta_pressed:
			if event.keycode == KEY_X:
				client.send_command("wish", {"wish": "xp:150"}); return
			if event.keycode == KEY_H:
				client.send_command("wish", {"wish": "statpenalty:Hitpoints:3"}); return
			if event.keycode == KEY_J:
				client.send_command("wish", {"wish": "statpenalty:Hitpoints:-9999"}); return
		# mode switches first — they reassign what the arrows mean
		if event.shift_pressed and event.keycode == KEY_C:
			_set_mode(CamMode.MOUSE); return
		if event.shift_pressed and event.keycode == KEY_K:
			_set_mode(CamMode.KEYBOARD); return
		if event.shift_pressed and event.keycode == KEY_F:
			_set_mode(CamMode.FOLLOW); return
		# Plain F = FIRE (forwarded to Qud), NOT a camera key. Qud runs its own fire/targeting flow.
		# (Temporary Raves keybinds are being retired; Qud's own controls arrive next.)
		if event.keycode == KEY_F and not event.shift_pressed \
				and not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed):
			request_command("CmdFire"); return
		# THE DIGIT ROW IS QUD'S ABILITY BAR, and the camera modes moved off it to give it back.
		# Daniel: "The camera change keys are overriding the abilities. I'm trying to use flaming
		# ray, but the Raves just tries to Chat with the Dawngliders." Qud binds 1-9 and 0 to
		# CmdAbility1..CmdAbility10, so every activated ability in the game was unreachable — the
		# key changed the camera and the player was left clicking at things instead.
		#
		# The same trade W, S and D already made with the camera's dolly and height controls: Qud's
		# key wins and the camera function takes a modifier. SHIFT+digit, because Qud itself has
		# ALT+1..9 (CmdMoveFar*, move to edge/corner) and Shift+digit is free in its whole table —
		# checked against the player's own exported bindings, not assumed.
		#
		# Nothing below has to forward the plain digit: _unhandled_input already ends in the
		# QudBinds fallback, which runs whatever the player has BOUND. That routes 1 to whatever
		# their ability bar is remapped to as readily as to the default, which a hardcoded
		# CmdAbility1 here would not.
		var cam_num: bool = event.shift_pressed \
			and not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed)
		if cam_num:
			# camera modes by number (mirrored in the ` debug menu)
			if event.keycode == KEY_1: _set_mode(CamMode.COMPASS); return
			if event.keycode == KEY_2: _set_mode(CamMode.FOLLOW); return
			if event.keycode == KEY_3: _set_mode(CamMode.FIRST_PERSON); return
			if event.keycode == KEY_4: _set_mode(CamMode.CINEMATIC); return
			if event.keycode == KEY_5: _set_mode(CamMode.MOUSE); return
			if event.keycode == KEY_6: _set_mode(CamMode.KEYBOARD); return
			if event.keycode == KEY_7: _set_mode(CamMode.TOP_FOLLOW); return
			if event.keycode == KEY_8: _set_mode(CamMode.ADVENTURE); return
			if event.keycode == KEY_9: _set_mode(CamMode.DRONECAM); return
			if event.keycode == KEY_0 and not _cam_locked(): _multiview.toggle(); return   # all-views grid (a camera feature)
		if event.keycode == KEY_QUOTELEFT:      # ` toggles the debug menu
			_dbg_menu.toggle(); return
		# B: "become anything" character-creator menu (pick a blueprint to embody)
		if event.keycode == KEY_B and not event.shift_pressed \
				and not (event.ctrl_pressed or event.meta_pressed):
			_char_creator.toggle(renderer.tiles_dir().get_base_dir()); return
		# O: flip the whole world 3D (billboards) <-> 2D (flat on the floor). (Was B; moved off B
		# when the character-creator merge took B for "become".)
		if event.keycode == KEY_O:
			_toggle_flat_2d(); return
		# Q/E rotate the locked compass heading (COMPASS mode only), 45° or 90° per _compass_45
		if (_cam_rig._mode == CamMode.COMPASS or _cam_rig._mode == CamMode.ADVENTURE) \
				and event.keycode == KEY_Q:
			_cam_rig._compass_yaw += _cam_rig.compass_step(); return
		if (_cam_rig._mode == CamMode.COMPASS or _cam_rig._mode == CamMode.ADVENTURE) \
				and event.keycode == KEY_E:
			_cam_rig._compass_yaw -= _cam_rig.compass_step(); return
		# W / X dolly the camera one tile forward / back along its heading — move the
		# camera like the player. Discrete per press; pairs with S/D vertical pan. Not
		# in FLY (WASD drives the free camera there), and not in 1:1 — Qud's camera is
		# the letterbox model only (zoom + clamped player follow), never a free dolly.
		# LOOK MODE: W = WALK TO the look tile (Daniel: "use the walk key to walk to the look
		# tile — it was w a while ago"). The mod's own moveto command does the travelling —
		# Qud's pathing and hostile-interrupts, exactly as a click-to-travel would — and the
		# cursor closes, its job done. Takes W from the camera dolly only while looking.
		# INTERACT WITH WHAT YOU ARE LOOKING AT. Daniel: "the look feature needs to be able to look
		# at adjacent objects and interact with them." Looking already named them — look_line lists
		# every object on the cell — but there was no way to act on one without leaving the mode,
		# walking over and using the mouse.
		#
		# Enter (and Space) send Qud's own `interact` for the cursor's cell, which is the same verb
		# a right-click sends: AdventureMouseInteract decides what the cell means — twiddle a
		# thing, take a default action, or nudge at empty ground — so Raves never has to guess
		# which of those an object wants, and an adjacent creature, item or door each behave the
		# way Qud already makes them behave.
		#
		# The cursor closes behind it, like the walk key: the menu that opens IS the next thing to
		# look at, and leaving a look marker under a popup was the old Looker trap in miniature.
		if inspector != null and inspector.look_on() \
				and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			var ic: Vector2i = inspector.look_cell()
			if ic.x >= 0 and ic.y >= 0:
				client.send_command("interact", {"x": ic.x, "y": ic.y})
				look_toggle()
				print("[look] interact at (%d,%d)" % [ic.x, ic.y])
			return
		if event.keycode == KEY_W and inspector != null and inspector.look_on():
			var wc: Vector2i = inspector.look_cell()
			if wc.x >= 0 and wc.y >= 0 and wc.x < int(renderer._live_w) and wc.y < int(renderer._live_h):
				client.send_command("moveto", {"x": wc.x, "y": wc.y})
				look_toggle()   # travel begins; the cursor's job is done
				print("[look] walking to (%d,%d)" % [wc.x, wc.y])
			return
		# W IS QUD'S WALK KEY (CmdWalk, "Walk in a direction"), and in play modes that is what it
		# does here — the same trade S and D already made, where the stairs commands took the keys
		# from the camera's height controls. The forward dolly keeps working on SHIFT+W, beside X.
		if _cam_rig._mode != CamMode.KEYBOARD and not _cam_locked() and event.keycode == KEY_W:
			if event.shift_pressed:
				_cam_rig._cam_pan += _cam_rig.cam_forward() * _cam_rig.CAM_STEP
			else:
				_walk_arm()
			return
		if _cam_rig._mode != CamMode.KEYBOARD and not _cam_locked() and event.keycode == KEY_X:
			_cam_rig._cam_pan -= _cam_rig.cam_forward() * _cam_rig.CAM_STEP; return
		# S / D = go UP / DOWN stairs (Qud's climb commands CmdMoveU / CmdMoveD; Down also
		# pulls down from the world map). Direct command injection — NOT a raw keymap
		# forward, so it works whatever s/d are bound to in Qud. Mirrors the top-bar
		# ▲ Up / ▼ Down buttons. Skipped in FLY (KEYBOARD) mode, where WASD flies the camera.
		if _cam_rig._mode != CamMode.KEYBOARD and event.keycode == KEY_S:
			client.send_command("command", {"command": "CmdMoveU"}); return
		if _cam_rig._mode != CamMode.KEYBOARD and event.keycode == KEY_D:
			client.send_command("command", {"command": "CmdMoveD"}); return
		if event.keycode == KEY_ESCAPE:
			# AIMING LEAVES FIRST OF ALL. Qud's picker takes Escape itself when it has the keyboard,
			# but Raves has it here — and it must be possible to call a shot off without reaching for
			# the other window. Measured the hard way: with nothing wired, Escape from Raves left the
			# game parked in PickTarget and it took the mod's own `uiback` to get out.
			if _target != null and _target.active:
				_target.click(null, true)
				return
			# LOOK MODE LEAVES SECOND, and by itself — the whole complaint about the old Look button
			# was that it put the game somewhere it could not be talked out of, so this one exits
			# on the key everyone tries first, before Esc means anything else.
			if inspector != null and inspector.look_on():
				look_toggle()
				return
			# close the camera/debug menu and any selection, but KEEP the current camera.
			# With nothing to dismiss, 1:1 Esc = Qud's own binding (CmdSystemMenu,
			# Commands.xml): the system-menu POPUP opens in Qud and mirrors back into
			# Raves through the popup bridge — picking Save and Quit / Options there
			# round-trips like any popup.
			# NB .visible on the debug menu is useless — the NODE stays visible, only
			# its internal panel toggles (is_open() reads that). Same trap generally.
			var had_ui: bool = (inspector != null and inspector.selected_tile() != null) \
				or (_dbg_menu != null and _dbg_menu.is_open()) \
				or (_char_creator != null and _char_creator.visible)
			_dismiss_selection()
			if _dbg_menu != null:
				_dbg_menu.close()
			if _char_creator != null:
				_char_creator.visible = false
			# a MainFrame overlay (status screens / control mapping) owns Esc for its
			# own close — Main runs FIRST in _unhandled_input (later sibling), so
			# without this check Esc would ALSO pop Qud's system menu underneath
			var overlay_open: bool = overlay_check.is_valid() and bool(overlay_check.call())
			if not had_ui and _one_to_one and not overlay_open:
				client.send_command("command", {"command": "CmdSystemMenu"})
			return
		if event.keycode == KEY_I:
			_inspect(); return
		if event.keycode == KEY_L:
			_toggle_font_preview(); return   # L: font-size ruler (Lorem Ipsum at each px)
		if event.keycode == KEY_F12:
			_screenshot(); return
		if event.keycode == KEY_P:
			_dump_profile(); return   # P: macOS grabs F9 (Mission Control)
		if event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			if _cam_locked() and _cam_rig._mode == CamMode.TOP_FOLLOW:
				_cam_rig.zoom_1to1_step(-1); return   # Qud's CmdZoomOut (quarter step, floor = fit)
			inspector.nudge_font(-2)
			reporter.nudge_font(-2); return
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			if _cam_locked() and _cam_rig._mode == CamMode.TOP_FOLLOW:
				_cam_rig.zoom_1to1_step(1); return    # Qud's CmdZoomIn (quarter step)
			inspector.nudge_font(2)
			reporter.nudge_font(2); return
		# A MODAL OWNS THE ARROWS — the KEYBOARD half of the rule the mouse branch below
		# already states, and the half that was missing. While a status screen, the control
		# mapping, a popup or the terminal is up, Up/Down mean MOVE THE SELECTION, not walk
		# north/south: pressing Down on the equipment list sent the player walking behind the
		# overlay (reported 2026-08-10). The status panes consume mouse events but no keys at
		# all, so nothing upstream was ever going to stop this; like the wheel fix, the modal
		# check has to be here as well, because a pane that forgets to consume must not be able
		# to move the player. Placed above the movement block only — Escape keeps its own
		# overlay handling further up, and the debug keys (F12/P/I) stay usable over a modal.
		if _modal_owns_input():
			return
		# in KEYBOARD mode the arrows drive the camera, not the player
		if _cam_rig._mode == CamMode.KEYBOARD:
			return
		# Arrows move the PLAYER relative to the camera heading — "up" is always forward on
		# screen (the Godot->Qud translation). SHIFT+arrow = that direction rotated 45° to the
		# DIAGONAL (Up=NE, Right=SE, Down=SW, Left=NW). FIRST-PERSON turns in place on plain
		# L/R; Ctrl/Cmd+Shift+L/R strafes there. Numpad is the ABSOLUTE 8-way fallback.
		var mod: bool = event.ctrl_pressed or event.meta_pressed
		var diag: bool = event.shift_pressed and not mod    # Shift alone -> diagonal move
		var strafe_mod: bool = event.shift_pressed and mod  # Ctrl/Cmd+Shift -> strafe (first-person)
		# A WALK IS ARMED — this key is its direction, not a step. Same keys, same camera-relative
		# reading; only what happens with the answer differs.
		if _walk_pending:
			var wd := ""
			match event.keycode:
				KEY_UP:    wd = _cam_rig.relative_compass(Vector2(1, 1) if diag else Vector2(0, 1))
				KEY_DOWN:  wd = _cam_rig.relative_compass(Vector2(-1, -1) if diag else Vector2(0, -1))
				KEY_LEFT:  wd = _cam_rig.relative_compass(Vector2(-1, 1) if diag else Vector2(-1, 0))
				KEY_RIGHT: wd = _cam_rig.relative_compass(Vector2(1, -1) if diag else Vector2(1, 0))
				KEY_KP_8: wd = "N"
				KEY_KP_2: wd = "S"
				KEY_KP_4: wd = "W"
				KEY_KP_6: wd = "E"
				KEY_KP_7: wd = "NW"
				KEY_KP_9: wd = "NE"
				KEY_KP_1: wd = "SW"
				KEY_KP_3: wd = "SE"
				_:
					# ANY OTHER KEY CANCELS, rather than being swallowed. An armed mode that eats
					# unrelated keys is worse than one that gives up on the first sign of a change
					# of mind — and Esc has its own handling further up, which this must not block.
					_walk_answer("")
					return
			_walk_answer(wd)
			return
		match event.keycode:
			KEY_UP:
				_move_relative(Vector2(1, 1) if diag else Vector2(0, 1))      # NE / forward
				_hold_begin(KEY_UP, Vector2(1, 1) if diag else Vector2(0, 1))
			KEY_DOWN:
				_move_relative(Vector2(-1, -1) if diag else Vector2(0, -1))   # SW / back
				_hold_begin(KEY_DOWN, Vector2(-1, -1) if diag else Vector2(0, -1))
			KEY_LEFT:
				if diag:
					_move_relative(Vector2(-1, 1))       # NW diagonal
					_hold_begin(KEY_LEFT, Vector2(-1, 1))
				elif _cam_rig._mode == CamMode.FIRST_PERSON and not strafe_mod:
					_cam_rig._compass_yaw += PI * 0.25            # turn left 45°
				elif _cam_rig._mode == CamMode.FOLLOW and not strafe_mod:
					_cam_rig.turn_follow(PI * 0.25)               # FOLLOW turns like first-person
				else:
					_move_relative(Vector2(-1, 0))       # strafe left (or FP/FOLLOW Ctrl+Shift)
					_hold_begin(KEY_LEFT, Vector2(-1, 0))
			KEY_RIGHT:
				if diag:
					_move_relative(Vector2(1, -1))       # SE diagonal
					_hold_begin(KEY_RIGHT, Vector2(1, -1))
				elif _cam_rig._mode == CamMode.FIRST_PERSON and not strafe_mod:
					_cam_rig._compass_yaw -= PI * 0.25            # turn right 45°
				elif _cam_rig._mode == CamMode.FOLLOW and not strafe_mod:
					_cam_rig.turn_follow(-PI * 0.25)
				else:
					_move_relative(Vector2(1, 0))        # strafe right
					_hold_begin(KEY_RIGHT, Vector2(1, 0))
			KEY_KP_8:
				client.send_command("move", {"dir": "N"})
				_hold_begin(KEY_KP_8, Vector2.ZERO, "N")
			KEY_KP_2:
				client.send_command("move", {"dir": "S"})
				_hold_begin(KEY_KP_2, Vector2.ZERO, "S")
			KEY_KP_4:
				client.send_command("move", {"dir": "W"})
				_hold_begin(KEY_KP_4, Vector2.ZERO, "W")
			KEY_KP_6:
				client.send_command("move", {"dir": "E"})
				_hold_begin(KEY_KP_6, Vector2.ZERO, "E")
			KEY_KP_7:
				client.send_command("move", {"dir": "NW"})
				_hold_begin(KEY_KP_7, Vector2.ZERO, "NW")
			KEY_KP_9:
				client.send_command("move", {"dir": "NE"})
				_hold_begin(KEY_KP_9, Vector2.ZERO, "NE")
			KEY_KP_1:
				client.send_command("move", {"dir": "SW"})
				_hold_begin(KEY_KP_1, Vector2.ZERO, "SW")
			KEY_KP_3:
				client.send_command("move", {"dir": "SE"})
				_hold_begin(KEY_KP_3, Vector2.ZERO, "SE")
		# LAST fallback: the player's own Qud keybindings (Control Mapping remaps).
		# Qud stores a remap fine but Raves' hardcoded keys never consulted it, so a
		# custom bind ("{" = Move east) died at our seam. Raves handlers above keep
		# precedence (movement keys just moved — bail before double-sending); any
		# unclaimed combo that matches a binding runs Qud's own command.
		if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_KP_8, KEY_KP_2,
				KEY_KP_4, KEY_KP_6, KEY_KP_7, KEY_KP_9, KEY_KP_1, KEY_KP_3]:
			return
		if not _modal_owns_input():
			var qcmd: String = _binds.match_event(event)
			if qcmd != "":
				client.send_command("command", {"command": qcmd})
	elif event is InputEventMouseButton:
		# A MODAL OWNS THE MOUSE TOO — the same rule `cell_at` states above ("a modal owns
		# the whole screen even where it does not paint"), which this branch never applied.
		# Without it, scrolling a status-screen list zoomed the playfield behind it, and an
		# orbit/pan drag over a modal moved the camera underneath. accept_event() in
		# StatusScreens stops the wheel reaching here at all; this is the backstop for every
		# overlay, including any that forgets to consume.
		if _modal_owns_input():
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# Ctrl/Cmd+click inspect is handled in _input (containers eat it here when embedded);
				# a plain click orbits (MOUSE mode).
				_cam_rig._orbiting = event.pressed and _cam_rig._mode == CamMode.MOUSE
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				# Ctrl/Cmd+right-click inspect+capture is handled in _input; a plain right/middle pans.
				_cam_rig._panning = event.pressed and _cam_rig._mode == CamMode.MOUSE
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					if _cam_locked() and _cam_rig._mode == CamMode.TOP_FOLLOW:
						_cam_rig.zoom_1to1_step(1)     # Qud's quarter-step zoom in (min factor 1.0 = fit)
					elif _cam_rig._mode == CamMode.TOP_FOLLOW:
						_cam_rig._top_zoom = clampf(_cam_rig._top_zoom * 0.9, _cam_rig.TOP_ZOOM_MIN, _cam_rig.TOP_ZOOM_MAX)
					else:
						_cam_rig._dist = clampf(_cam_rig._dist * 0.9, _cam_rig.DIST_MIN, _cam_rig.DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					if _cam_locked() and _cam_rig._mode == CamMode.TOP_FOLLOW:
						_cam_rig.zoom_1to1_step(-1)    # Qud's quarter-step zoom out (stops at the zone fit)
					elif _cam_rig._mode == CamMode.TOP_FOLLOW:
						_cam_rig._top_zoom = clampf(_cam_rig._top_zoom * 1.1, _cam_rig.TOP_ZOOM_MIN, _cam_rig.TOP_ZOOM_MAX)
					else:
						_cam_rig._dist = clampf(_cam_rig._dist * 1.1, _cam_rig.DIST_MIN, _cam_rig.DIST_MAX)
	elif event is InputEventMouseMotion:
		if _cam_rig._orbiting:
			_cam_rig._yaw += event.relative.x * _cam_rig.ORBIT_SENS
			_cam_rig._pitch = clampf(_cam_rig._pitch + event.relative.y * _cam_rig.ORBIT_SENS, _cam_rig.PITCH_MIN, _cam_rig.PITCH_MAX)
		elif _cam_rig._panning:
			# pan along the ground plane, scaled by zoom so it feels constant
			var right: Vector3 = _cam_rig._cam.global_transform.basis.x
			var fwd: Vector3 = -_cam_rig._cam.global_transform.basis.z
			right.y = 0.0; fwd.y = 0.0
			right = right.normalized(); fwd = fwd.normalized()
			var speed: float = _cam_rig._dist * 0.0016
			# grab-the-world: drag right moves the world right (camera goes left)
			_cam_rig._pan += (-right * event.relative.x - fwd * event.relative.y) * speed

# ── Wish prompt (Ctrl+Shift+W) ───────────────────────────────────────────────
# A minimal text prompt that ships whatever you type to Qud's own wish handler over the bridge (grant
# xp, spawn items, …), no Qud-side prompt needed. A user-mode button will front this later; for now the
# shortcut is the entry point. send_command no-ops if the bridge isn't connected.
func _open_wish() -> void:
	if _wish_layer == null:
		_wish_layer = CanvasLayer.new()
		_wish_layer.layer = 128
		add_child(_wish_layer)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.theme = UiFont.make_theme(get_viewport())   # avoid the CanvasLayer tiny-font trap
		_wish_layer.add_child(center)
		var panel := PanelContainer.new()
		var pstyle := StyleBoxFlat.new()
		pstyle.bg_color = Color(0.05, 0.06, 0.07, 0.96)
		pstyle.set_content_margin_all(14)
		pstyle.border_color = Color(0.30, 0.40, 0.45)
		pstyle.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", pstyle)
		center.add_child(panel)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		panel.add_child(vb)
		var lbl := Label.new()
		lbl.text = "Wish  (Enter to send · Esc to cancel)"
		vb.add_child(lbl)
		_wish_edit = LineEdit.new()
		_wish_edit.custom_minimum_size = Vector2(460, 0)
		_wish_edit.placeholder_text = "e.g. xp:5000"
		_wish_edit.text_submitted.connect(_on_wish_submitted)
		_wish_edit.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
				_close_wish())
		vb.add_child(_wish_edit)
	_wish_layer.visible = true
	_wish_edit.text = ""
	_wish_edit.grab_focus()

func _on_wish_submitted(text: String) -> void:
	var w := text.strip_edges()
	if w != "" and client != null:
		client.send_command("wish", {"wish": w})
		# The wish drains on Qud's game thread (Tick), which does NOT run while Qud sits
		# unfocused with no turn passing — the wish silently pends and "wishing doesn't
		# work". Chase it with a wait: PushCommand wakes the parked input loop even
		# unfocused, the turn ticks, the wish applies, and the snapshot refreshes Raves.
		client.send_command("wait", {})
	_close_wish()

func _close_wish() -> void:
	if _wish_layer != null:
		_wish_layer.visible = false
	if _wish_edit != null:
		_wish_edit.release_focus()

## Write zones.txt beside selection.txt — the store's zones, their 3x3 slots, and the band's stats.
## See the `zonereport` command for why this is a file rather than a print or a screenshot.
func _write_zone_report() -> void:
	if renderer == null:
		return
	var dir: String = renderer.tiles_dir().get_base_dir()
	if dir == "":
		return
	var live_id := store.live_id()
	var live_rec := store.live_record()
	var lo: Vector3i = live_rec.get("origin", Vector3i.ZERO)
	var lz: int = int(live_rec.get("stratum", 0))
	var lines: Array = []
	lines.append("=== %s — zone report ===" % Brand.GAME_NAME)
	lines.append("live %s  origin %s  stratum %d" % [live_id, str(lo), lz])
	var zw: int = int(renderer._live_w)
	var zh: int = int(renderer._live_h)
	lines.append("zone %dx%d" % [zw, zh])
	lines.append("")
	lines.append("STORE (every zone the player has visited; slot is the 3x3 cell around the live one)")
	for id in store.ids():
		var rec: Dictionary = store.record(id)
		var o: Vector3i = rec.get("origin", Vector3i.ZERO)
		var dz: int = int(rec.get("stratum", -9999)) - lz
		var dx: int = o.x - lo.x
		var dy: int = o.y - lo.y
		var slot := "far"
		if zw > 0 and zh > 0:
			var sx: int = int(floor(float(dx) / float(zw)))
			var sy: int = int(floor(float(dy) / float(zh)))
			if absi(sx) <= 1 and absi(sy) <= 1 and dz == 0:
				slot = "(%d,%d)" % [sx, sy]
		# What the zone's darkness mesh was actually BAKED with, not what the cap says now. The
		# two differing is the whole failure mode of a guarded bake, and it is invisible on glass.
		var baked := ""
		if renderer._static_zones.has(id):
			var zn: Node3D = renderer._static_zones[id]
			var nd := 0
			for ch in zn.get_children():
				if ch.has_meta("is_darkness"):
					nd += 1
			baked = "  baked[cap=%s off=%s darkmesh=%d]" % [
				str(zn.get_meta("dark_cap")) if zn.has_meta("dark_cap") else "-",
				str(zn.get_meta("dark_off")) if zn.has_meta("dark_off") else "-", nd]
		lines.append("  %-34s d=(%+5d,%+5d) dz=%+d  slot %s%s%s"
			% [id, dx, dy, dz, slot, baked, "   <-- LIVE" if id == live_id else ""])
	lines.append("")
	lines.append("BOUNDARY PROBES — screen pixel for each cell crossing the zone edge, so an outside")
	lines.append("tool samples the CELL it means instead of a coordinate guessed off a crop. Each row")
	lines.append("runs from 2 cells inside the zone out through the band; d is depth outside the rect.")
	var pc: Dictionary = store.live_record().get("snapshot", {}).get("player", {})
	var pxc: int = int(pc.get("x", zw / 2))
	var pyc: int = int(pc.get("y", zh / 2))
	var band: int = renderer.penumbra_radius + 1
	for edge in ["N", "S", "W", "E"]:
		var row: Array = []
		for d in range(-2, band + 1):
			# d < 0 is inside the zone, d >= 1 is the band. d = 0 is the edge row itself, which is
			# the one the band's first row has to match.
			var c: Vector2i
			match edge:
				"N": c = Vector2i(pxc, -d)
				"S": c = Vector2i(pxc, (zh - 1) + d)
				"W": c = Vector2i(-d, pyc)
				_:   c = Vector2i((zw - 1) + d, pyc)
			var sp: Vector2 = _cell_screen_pos(c)
			if sp.x < -9000:
				continue
			row.append("d%+d (%d,%d)@%d,%d" % [d, c.x, c.y, int(sp.x), int(sp.y)])
		lines.append("  %s: %s" % [edge, "  ".join(PackedStringArray(row))])
	lines.append("")
	var n_ghosted := 0
	var n_hidden := 0
	var n_livespr := 0
	for se in renderer._lit_sprites:
		var sn = se["s"]
		if not is_instance_valid(sn):
			continue
		if sn.modulate.a <= 0.001:
			n_hidden += 1        # unexplored (or hideDark out of sight): alpha-zeroed, texture untouched
		elif se.get("ghost") != null and sn.texture == se["ghost"]:
			n_ghosted += 1
		else:
			n_livespr += 1
	lines.append("SPRITES  lit=%d ghosted=%d hidden=%d (of %d registered)" % [n_livespr,
		n_ghosted, n_hidden, renderer._lit_sprites.size()])
	lines.append("LIGHTS  daylight=%.3f  glow_mul=%.3f  fire_glow_mul=%.3f  n=%d" % [
		renderer._daylight, renderer._glow_mul(), renderer._fire_glow_mul(), renderer._lights.size()])
	for li in range(mini(4, renderer._lights.size())):
		var L: Dictionary = renderer._lights[li]
		var gt: float = (L["glow"] as MeshInstance3D).transparency if L.get("glow") != null else -1.0
		lines.append("  light[%d] cell=%s on_fire=%s glow_transparency=%.3f" % [
			li, str(L.get("cell")), str(L.get("on_fire")), gt])
	lines.append("")
	lines.append("DEPARTED ZONES (their darkness hands over from the live zone's edge)")
	lines.append("  ambient_tone (median)      %.4f" % renderer._ambient_tone)
	lines.append("  rebake step                %d/%d" % [renderer._ambient_step(), int(renderer.CAP_QUANT)])
	lines.append("  memory tone (art only)     %.4f" % (1.0 - renderer.MEMORY_GROUND))
	var ho: Array = []
	for d in range(1, renderer.penumbra_radius + 2):
		ho.append("%.3f" % renderer._band_alpha(d, 0.0))
	lines.append("  hand-over d=1..%d at t0=0   %s" % [renderer.penumbra_radius + 1,
		" ".join(PackedStringArray(ho))])
	# READ THE BAKE BACK. The report used to print only the formulas; the memory-film change
	# needs the actual vertex alphas each neighbour's darkness mesh carries, because a formula
	# can be right while the mesh hanging in the scene is from an older bake (or another code
	# path entirely). One line per zone: alpha -> quad-corner count, coarsened to 2dp.
	for zid in renderer._static_zones:
		var zn3: Node3D = renderer._static_zones[zid]
		var hist := {}
		var nmesh := 0
		for chd in zn3.get_children():
			if not chd.has_meta("is_darkness") or not (chd is MeshInstance3D):
				continue
			nmesh += 1
			var am: ArrayMesh = (chd as MeshInstance3D).mesh
			if am == null:
				continue
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var cols = arr[Mesh.ARRAY_COLOR]
				if cols == null:
					continue
				for cc in cols:
					var key := "%.2f" % cc.a
					hist[key] = int(hist.get(key, 0)) + 1
		if nmesh > 0:
			var ks: Array = hist.keys()
			ks.sort()
			var hh: Array = []
			for hk in ks:
				hh.append("%s:%d" % [hk, int(hist[hk])])
			lines.append("  darkmesh %s  %s" % [str(zid), " ".join(PackedStringArray(hh))])
	lines.append("")
	# Whether the hand-authored model was found and understood. "no file" is normal; a file that
	# loads with the wrong node names is the failure that otherwise just looks like nothing changed.
	# Per DOOR DESIGN now, so a design silently falling back to the shared model is visible here
	# rather than only as "that one still looks like the basic door".
	var seen_tiles := {}
	for dk2 in renderer._door_static.keys():
		var dt := String(renderer._door_tile_at.get(dk2, ""))
		if dt == "" or seen_tiles.has(dt):
			continue
		seen_tiles[dt] = true
		var dvp := renderer._door_vox_path(dt)
		var dvv: Dictionary = renderer._door_vox(dt)
		lines.append("  vox %-26s -> %-34s %s" % [dt.get_file(), dvp.get_file(),
			("%d models %s" % [(dvv["models"] as Array).size(),
				str((dvv["nodes"] as Dictionary).keys())]) if not dvv.is_empty() else "NOT LOADED"])
	# What the animation mirror actually BUILT this turn. A schedule frame that was skipped and one
	# that was drawn look identical in a still, and a flashing overlay is only on screen a sixth of
	# the time — so counting the nodes is the only way to ask "is that icon still being made?".
	var akind := {}
	var aframes := 0
	var anodes := 0
	for it in renderer._anim_items:
		var kd := String(it.get("kind", "?"))
		akind[kd] = int(akind.get(kd, 0)) + 1
		if kd == "frames":
			for fr in it.get("sched", []):
				aframes += 1
				if fr.get("node") != null:
					anodes += 1
	lines.append("ANIM overlays: %s   schedule frames %d, of which drawn %d"
		% [str(akind), aframes, anodes])
	# Whether anything is actually riding above its cell, and how far. A bob is a few pixels on a
	# two-second cycle -- a still cannot show it, and two stills a second apart show a difference
	# without saying it was the right one.
	var fl: Array = renderer._float_sprites
	var fy := ""
	for e in fl:
		if is_instance_valid(e["s"]):
			fy += " %.2f" % (e["s"] as Node3D).position.y
	# Per sprite, because the whole point of the change is that they should NOT agree: distance
	# sets each one's amplitude and period, so two lines reading the same numbers would mean the
	# distance term is not doing anything.
	var fl2: Array = []
	for e in fl:
		if is_instance_valid(e["s"]):
			fl2.append("T %.1f/step %.4f/foreign %.4f" % [float(e["period"]),
				float(e.get("max_step", 0.0)), float(e.get("max_foreign", 0.0))])
			e["max_step"] = 0.0
			e["max_foreign"] = 0.0
	lines.append("FLOATING: %d sprites  [%s]" % [fl.size(), "  ".join(PackedStringArray(fl2))])
	# PARTICLES IN DEPARTED ZONES. A memory should not run, and "is it still emitting?" cannot be
	# answered from a screenshot — an emitter that has been switched off still has particles aloft
	# for a second or two, so a still shows water either way.
	var pt_total := 0
	var pt_live := 0
	for zid in renderer._static_zones:
		if zid == store.live_id():
			continue
		var st: Array = [renderer._static_zones[zid]]
		while not st.is_empty():
			var n: Node = st.pop_back()
			for ch in n.get_children():
				st.append(ch)
			if n is GPUParticles3D:
				pt_total += 1
				if (n as GPUParticles3D).emitting:
					pt_live += 1
	lines.append("DEPARTED-ZONE PARTICLES: %d found, %d still emitting" % [pt_total, pt_live])
	# LIGHT POOLS — what shape each ground pool actually ended up, and how much of it Qud's light
	# map clipped away. A pool that stops at a wall is a claim about cells the CAMERA usually
	# cannot show: a viewport holds a handful of lights, and the ones standing against buildings
	# are rarely among them (two probe runs found 192 lit cells on screen and five unlit ones).
	# So the renderer reports its own masks and the check stops depending on where you are stood.
	# Sleepers are hard to verify by pixel: they sleep at night, often at range, in the camera's
	# depth-of-field blur — the first detector shipped wrong and the miss was only visible because
	# Daniel happened to look. The renderer says outright who it laid down.
	lines.append("ASLEEP: %d creature(s) lying down this turn %s"
		% [renderer._asleep_posed.size(), str(renderer._asleep_posed)])
	lines.append("VOXEL WALLS (.vox meshed at runtime; %d layers is the opt-in)"
		% renderer.WALL_VOX_LAYERS)
	if renderer._wall_vox_files.is_empty():
		lines.append("  no wall .vox looked up yet (no wall cell asked for one)")
	for f in renderer._wall_vox_files:
		lines.append("  %-34s %s" % [f, renderer._wall_vox_files[f]])
	lines.append("  cells meshed from a model this build: %d" % renderer._wall_vox_placed)
	lines.append("LIGHT POOLS (mask = cells Qud calls lit; clipped = the pool stopping at walls)")
	var pool_lit := 0
	var pool_all := 0
	for L in renderer._lights:
		if not L.has("pool_mask"):
			continue
		var pm := String(L["pool_mask"])
		var ones := pm.count("1")
		pool_lit += ones
		pool_all += pm.length()
		var pcell: Vector2i = L["cell"]
		lines.append("  (%2d,%2d) %2d cells  %3d lit / %3d  clipped %3d%s"
			% [pcell.x, pcell.y, int(L["pool_n"]), ones, pm.length(), pm.length() - ones,
			   "   <-- stops at a wall" if ones < pm.length() else ""])
	if pool_all > 0:
		lines.append("  TOTAL %d of %d pool cells lit; %d clipped (%.1f%%)"
			% [pool_lit, pool_all, pool_all - pool_lit, 100.0 * (pool_all - pool_lit) / pool_all])
	else:
		lines.append("  (no live pools — daylight, or a zone with no light sources)")
	lines.append("DOOR .vox per design:")
	lines.append("DOOR art probe: %s" % renderer._door_art_probe("Tiles/sw_door_basic.bmp", "&y", "y"))
	lines.append("DOORS (cell -> screen pixel, so a door can be photographed without hunting for it)")
	var dks: Array = renderer._door_static.keys()
	dks.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for dk in dks:
		# THE BAKED STATIC MUST BE HIDDEN. A door is redrawn every turn in its current state, and
		# the bake underneath is put away by that redraw — but anything else that writes `visible`
		# can bring it back, and then the old pose and the new one are both on screen at once.
		# That is what "I closed a door, the open door is also still present" looks like, and it is
		# invisible in a still unless you know to ask which of the two you are looking at.
		var parts: Array = renderer._door_static[dk]
		var shown := false
		for nd in parts:
			if is_instance_valid(nd) and (nd as Node3D).visible:
				shown = true
		var dsp: Vector2 = _cell_screen_pos(dk)
		# THE LEAF'S FOOTPRINT IN ITS OWN CELL, which is the camera-independent way to ask whether a
		# closed door is actually shut. A leaf built hinge-relative but mapped with the ABSOLUTE
		# column function picks up the -0.5 cell-centring twice and sits half a cell out of its
		# doorway; on screen that reads as a vaguely wrong door, in these numbers it is unmissable.
		# Shut and in-frame means both spans inside +/-0.5, and the thin one is the leaf's depth.
		var box := ""
		# FIND the pivot rather than index it. _door_static holds whatever pieces a door is made of
		# and that list has already grown once (the frame's inner cap joined it); positional access
		# silently reported nothing when it did, which looks exactly like a door with no leaf.
		var pv: Node3D = null
		for nd in parts:
			if is_instance_valid(nd) and nd is Node3D:
				for ch in (nd as Node3D).get_children():
					if ch is MeshInstance3D:
						pv = nd
		if pv != null:
			for ch in pv.get_children():
				if ch is MeshInstance3D:
					var ab: AABB = (ch as MeshInstance3D).get_aabb()
					ab = pv.transform * ab
					ab.position -= Vector3(dk.x, 0, dk.y)   # cell-relative: the cell spans +/-0.5
					box = "  leaf x[%+.2f %+.2f] z[%+.2f %+.2f] y[%.2f %.2f]" % [
						ab.position.x, ab.position.x + ab.size.x,
						ab.position.z, ab.position.z + ab.size.z,
						ab.position.y, ab.position.y + ab.size.y]
					# An OPEN leaf reaching into the next cell is not a fault — that is what a door
					# does, and the swing is deliberately allowed to when the neighbour is a room.
					# The fault is reaching into a WALL, which is the thing that looked broken
					# before. So test what is actually over there, not the arithmetic edge.
					for nb in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var blo := Vector2(ab.position.x, ab.position.z)
						var bhi := blo + Vector2(ab.size.x, ab.size.z)
						var into: bool = (nb.x > 0 and bhi.x > 0.5) or (nb.x < 0 and blo.x < -0.5) \
							or (nb.y > 0 and bhi.y > 0.5) or (nb.y < 0 and blo.y < -0.5)
						if into and renderer._zone_wall_cells.has(dk + nb):
							box += "  <-- INTO THE WALL AT (%d,%d)" % [dk.x + nb.x, dk.y + nb.y]
		lines.append("  (%2d,%2d) @%5d,%5d  bake:%-18s%s" % [dk.x, dk.y, int(dsp.x), int(dsp.y),
			"VISIBLE (stale!)" if shown else "hidden (ok)", box])
	lines.append("")
	lines.append("FOG-OF-WAR MESHES (static geometry hidden in never-explored cells)")
	var mt := 0
	var mh := 0
	for e in renderer._known_meshes:
		if not is_instance_valid(e["n"]):
			continue
		mt += 1
		if not (e["n"] as Node3D).visible:
			mh += 1
	lines.append("  tracked %d   hidden %d   showing %d" % [mt, mh, mt - mh])
	lines.append("")
	lines.append("SURROUND BAND (_build_unexplored, last turn)")
	var bs: Dictionary = renderer._band_stats
	if bs.is_empty():
		lines.append("  (nothing recorded — the band has not run this session)")
	else:
		for k in bs:
			lines.append("  %-26s %s" % [k, str(bs[k])])
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("zones.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)) + "\n")
		f.close()

## Where a zone cell lands on screen, in window pixels (or x = -9999 if there is no camera).
## Same projection `screenpos` prints; this is the form the zone report can write to a file,
## because the EXPORTED app -- the one highvisor launches -- flushes no stdout at all.
func _cell_screen_pos(c: Vector2i) -> Vector2:
	if _cam_rig == null or _cam_rig._cam == null:
		return Vector2(-9999, -9999)
	var wq := Vector3(float(c.x), 0.0, float(c.y) * _cam_rig.zstretch())
	return _cam_rig._cam.unproject_position(wq)


## Which way out of the zone a cell lies, or "" if it is inside it.
##
## MEASURED AS A FRACTION OF THE ZONE, not in cells. A zone is 80x25, so a click three cells past
## the south edge and three past the east edge is not an ambiguous diagonal -- three cells is an
## eighth of the way down a zone and a twenty-sixth of the way across one, and south is plainly the
## way that click was pointing. Comparing raw cell counts would have sent it east.
func _edge_dir(c: Vector2i) -> String:
	if renderer == null:
		return ""
	return edge_dir_for(c, int(renderer._live_w), int(renderer._live_h))

## ...as a pure function of the cell and the zone's size, so it can be asked directly. The rule is
## the whole of the feature's judgement and it is the part with no visible symptom when it is
## wrong: a mis-chosen axis just walks the player somewhere reasonable-looking that is not where
## they pointed.
static func edge_dir_for(c: Vector2i, w: int, h: int) -> String:
	if w <= 0 or h <= 0:
		return ""
	var over_x := 0
	var over_y := 0
	if c.x < 0:
		over_x = c.x
	elif c.x >= w:
		over_x = c.x - (w - 1)
	if c.y < 0:
		over_y = c.y
	elif c.y >= h:
		over_y = c.y - (h - 1)
	if over_x == 0 and over_y == 0:
		return ""
	if absf(float(over_y) / float(h)) >= absf(float(over_x) / float(w)):
		return "S" if over_y > 0 else "N"
	return "E" if over_x > 0 else "W"
