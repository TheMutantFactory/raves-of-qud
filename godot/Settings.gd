extends Node

## Persistent Raves settings — the store behind the Options screen. Autoload "Settings".
##
## Mirrors the overrides.json / title_layout.json pattern: a JSON file in the RavesOfQud
## support dir, defaults in code so a wiped config still boots. Loaded at startup; the
## GLOBAL settings (font scale, fullscreen) are applied immediately so the whole app honors
## them before any UI builds. OptionsScreen reads/writes via get_value/set_value + save();
## the per-view defaults (full_info, camera, bridge host/port) are read by their own
## components (MainFrame, CameraRig, BridgeClient) via get_value at init.

const DEFAULTS := {
	"font_scale": 1.0,          # global UI size multiplier (UiFont.scale)
	"fullscreen": false,        # window mode
	"full_info": false,         # perceived (false) vs full/debug (true) info by default
	# 1:1 test — visual effects. MINIMAL by default (all off): start bare and build up to find
	# where Raves diverges from Qud. Each applies on (re)launch; toggle in Options.
	"fx_scanlines": false,      # CRT scanline interlace
	"fx_vignette": false,       # CRT corner vignette (Qud's HUD has none)
	"camera": 0,                # default CameraRig.CamMode index (user mode)
	"mode": "user",             # "user" = QoL Holodeck · "1to1" = Qud-faithful parity mode
	                            # (1to1 hard-overrides camera + panels; see MainFrame._apply_one_to_one)
	"bridge_host": "127.0.0.1", # which Qud to render (BridgeClient)
	"bridge_port": 48710,
	# THE PENUMBRA — the gradient between the zone you are in and the dark beyond it.
	#   radius     how many tiles the fade spans before full darkness
	#   divisions  steps per tile. 1 = one flat step per tile (a tile-resolution fade).
	#              Higher subdivides the tile, so the fade steps WITHIN a tile; 16 puts a step on
	#              every pixel column of Qud's 16x24 tile, which is as fine as the art can show.
	"penumbra_radius": 3,
	# How many zones OUT fires stay lit (sconce pools + flames) in user mode. 0 = only the
	# zone you are standing in — a departed zone's flames are a memory, and a memory does not
	# burn (Daniel, from a zone south of Joppa: "there are flames on. They are out-zone").
	# Evaluated when a remembered zone builds, so raising it takes effect on the next crossing.
	"fire_zone_radius": 0,
	# HOW MUCH IS KEPT IN MEMORY, NOT HOW MUCH IS DRAWN. How many zones out a departed zone's
	# BUILT GEOMETRY stays banked — every one of them HIDDEN, warm for a fast return. Beyond it
	# the subtree is freed; the store keeps the data and walking back rebuilds it. 1 = just the
	# 3x3 ring; higher trades memory for fewer rebuilds and changes nothing you can see.
	#
	# WHAT YOU CAN SEE IS THE 3x3 RING, and no setting widens it. _zone_beyond_ramp hides any
	# zone whose nearest cell is penumbra_radius+1 or more away, and a second ring starts a whole
	# zone-width out (~80 cells), so the ramp slider cannot reach it either — past the ring,
	# _build_unexplored's far frame covers the ground edge to edge instead. Daniel set this to 5
	# and asked why he was not seeing five zones out; the answer is that it never meant that.
	"remember_radius": 2,
	# ADVENTURE camera (mode 8), Daniel's crane spec: horizontal ground distance back,
	# vertical height up, and a FREE pitch angle. Defaults equal COMPASS at its default
	# zoom (back ~12, up ~8, pitch 35deg aims square at the player) so it starts familiar.
	"adventure_height": 8.0,
	"adventure_distance": 12.0,
	"adventure_angle": 35.0,
	# The see-through BUBBLE around the player: walls within this many cells, on the camera
	# side, fade regardless of light — the narrow-cave answer. 0 turns it off.
	"cutaway_bubble": 2.5,
	# FINAL-FANTASY HOLD-TO-WALK: how many steps a second a held direction key takes. Daniel:
	# "holding down the direction key will cause the player to walk in that direction, 1 tile at a
	# time. User setting for auto-walk rate." Stated as steps PER SECOND rather than seconds per
	# step, because the number people want to turn up is the speed.
	"auto_walk_rate": 6.0,
	"cutaway_bubble_on": true,   # the master switch; the radius slider stays the size knob
	"penumbra_divisions": 1,
}

## True when Raves was launched with --one-to-one (or --1to1): 1:1 is LOCKED for this
## run. The Options screen hides the RAVES section entirely — parity with Qud's options,
## and deliberately no toggle back to user mode (run without the flag for that). Doubles
## as the pressure valve that flushes out user-mode UI elements missing a 1:1 gate.
var one_to_one_only := false

## THE LITERAL MODE. Use this only where the answer must be "which mode did the viewer pick" —
## reporting it (UiState, the feedback record and its badge) and offering the way BACK from it
## (OptionsScreen, which builds a different screen per mode and is the only route to the toggle).
## For "should this surface take Qud's shape", use `qud_shape` below.
func one_to_one() -> bool:
	if one_to_one_only:
		return true
	return str(get_value("mode", "user")) == "1to1"

## USER MODE STARTS AS A 1:1 CLONE — Daniel, 2026-08-12: "Let's copy all the 1:1 settings to
## usermode. We'll load back in features 1 at a time."
##
## User mode had accumulated its own shape screen by screen, and testing it meant meeting those
## divergences one surprise at a time: a save name under Continue that Qud does not show, an
## in-game field Qud does not have, a "turn on viewport" step left over from before the 1:1 flow
## existed. Each was defensible alone and the pile was not, because nothing said what the pile
## contained — 55 call sites across 16 files, and no list of them anywhere.
##
## So the DEFAULT flips. A surface asks `qud_shape()` and gets Qud's form in both modes; a QoL
## feature comes back only when it is named here and switched on, which makes the set of
## divergences a list you can read instead of a thing you discover.
##
## `feature` is that name. Unnamed sites can never opt out, which is deliberate for now: they are
## the ones nobody has argued for yet.
## name -> [label, default]. EVERY entry is a divergence from Qud someone chose on purpose, and
## being in this dictionary is what makes it choosable rather than merely present. Off by default:
## user mode starts as a 1:1 clone and features are loaded back one at a time.
const QOL_FEATURES := {
	"titlebar": ["Window titlebar", false],
	"cameras": ["User cameras (Compass / Follow / First person / …)", false],
	"tiles3d": ["3D tiles (voxel walls + upright sprites)", false],
	"lighting": ["Day/night lighting (grade + sun/moon + fog)", false],
	"particles": ["Smoke plumes (sconces & torches at night)", false],
	# THE THREE PIECES OF A FIRE, each switchable on its own. Qud lights a cell; Raves builds a
	# fixture out of three separate things over that cell, and until now only the smoke had a
	# lever. Daniel asked what could turn the floor lighting off and the answer was nothing —
	# _place_light was gated on 1:1 and the world map and on nothing else.
	#
	# ON by default, all three, because they are what a Raves fire already looks like; these
	# exist to take pieces AWAY. 1:1 is untouched either way — qud_shape short-circuits there,
	# and _place_light returns before any of it in parity mode regardless.
	#
	# WHAT `floorglow` IS NOT, and the label has to say so. Daniel, with it switched off:
	# "Campfires and arc sconces still have the floor/walls lit." They do, and the switch is
	# working — measured from one spot, toggling it moves the warm pixel COUNT barely at all
	# (14,474 -> 14,772) and only shifts their colour (199,124,60 -> 203,149,70). The orange
	# underneath is QUD'S LIGHT MAP: a lit cell is drawn at full colour while everything else is
	# multiplied down toward the memory ghost, and this zone's rock is Qud's `&y`, a tan. Qud's
	# own screen shows the same cells bright, its shale the same orange.
	#
	# It reads as a much bigger effect here than in Qud for a reason that is not lighting at all:
	# Raves draws a FLOOR TILE where Qud draws nothing, so Qud's lit patch is a few wall glyphs
	# over black and Raves' is a whole glowing floor. Asked whether "off" should dim or
	# extinguish those cells, Daniel chose neither — Qud's lighting stays as Qud sends it, and
	# the switch says plainly that it only removes the pool Raves adds on top.
	"floorglow": ["Extra glow pool under torches, sconces & fires (not Qud's cell lighting)", true],
	"flames": ["3D flames on torches, sconces & fires", true],
	# SEPARATE FROM `particles`, which covers the night plumes on sconces and standing torches and
	# is off by default. An on-fire object's smoke was deliberately exempt from that gate — "a real
	# fire smokes whether or not the viewer opted into ambience" — so folding it in would have
	# deleted campfire smoke for everyone who never turned `particles` on. It gets its own lever.
	"firesmoke": ["Smoke from things that are on fire", true],
	# ...AND THE CELLS THEMSELVES, which is what Daniel was actually after. The three above remove
	# what Raves adds on top of a fire; this one takes away the light Qud's fire casts on the room.
	# Switch it off and a campfire or arc sconce stops lighting the floor and walls around it —
	# they fall back to the remembered ghost — while the light you are CARRYING still works, so
	# you can see where you are going. See ZoneRenderer.mark_fire_lit for how a cell is attributed
	# to a fire when Qud sends only one light byte and no account of what lit it.
	"firecells": ["Campfires & sconces light the cells around them", true],
	# THE OTHER HALF OF THE ANSWER. Standing beside a campfire with a lit torch, every cell around
	# you is lit twice over, and switching the fires off changes nothing you can see there — which
	# read as a broken switch three times before the two were told apart. Off, the ground you are
	# carrying light over goes dark too; together they answer "is that the campfire or my torch?"
	# by experiment instead of by argument. Turning BOTH off in an unlit room leaves you seeing
	# nothing, which is what having no light means.
	"carriedlight": ["Your carried light (torch, lantern) lights the cells around you", true],
	"depthcue": ["Depth cue (farther is slightly darker)", false],
	"cutaway": ["Wall cutaway (fade rock between camera and you)", false],
	# ON by default, unlike its neighbours: Qud draws a tree in one cell because it has
	# only one cell to draw it in, and at 1x a 3D tree reads as a shrub. 1:1 mode is
	# unaffected — the renderer gates the scale out there, where pixels are measured.
	"bigtrees": ["Trees, blockers & statues at 2x scale", true],
	# THE TWO SIDE PANELS, also ON by default. Both had working user-mode halves that had become
	# unreachable: every panel was switched by the bare qud_shape(), which is TRUE in user mode, so
	# the log's grouping toggle and Nearby's larger icons could not be turned on from anywhere.
	# Daniel asked for both back, and neither costs parity — 1:1 short-circuits qud_shape() for
	# every feature, so the Qud-faithful shape is untouched there.
	"msglog": ["Message log: group repeats (xN) + inline pictographs", true],
	# ON by default (report 9e4163d1): user mode's title corner shows RAVES' client + mod
	# versions in place of Qud's release/build — you cannot pin a bug report to a build you
	# were never shown. 1:1 keeps Qud's corner untouched, as with every QoL feature.
	"versions": ["Title screen: Raves client + mod versions", true],
	# ON by default. The title wordmark is Qud's own extracted art; this sprays OUR letters
	# over two of its glyphs so it reads "RAVES OF MUD" — the modpack signing the poster it
	# is standing on. 1:1 short-circuits every QoL feature, so parity mode keeps Qud's title
	# untouched, which is the whole reason this is a feature and not an unconditional draw.
	"overpaint": ["Title screen: spray RAVES OF MUD over the wordmark", true],
	"nearby": ["Nearby objects: larger icons", true],
	# ON by default, and a QoL feature rather than an unconditional panel for the usual reason: the
	# Locations list and its horizon beacons are a RAVES navigation aid built on a 3D world Qud does
	# not have, so parity mode must not grow a fifth panel Qud never draws.
	"locations": ["Locations panel + horizon beacons", true],
	# ON by default. The minimap had NO feature, which means clone_of_qud() answered for it — a
	# constant true — so the panel was Qud's minimap in both modes and its own painted/structural
	# maps were unreachable from anywhere. Daniel: "I think we did this before, but I forget."
	# They were built; the parity policy had switched them off. This is the lever Settings.gd's own
	# note points at: "what you actually want is a QoL feature."
	"minimap": ["Minimap: Raves sources (painted / structural / top-down camera)", true],
	# ON by default. Qud's own menus carry a per-row IRenderable (QudMenuItem.icon) and simply do
	# not draw it — the points-of-interest list ships a real tile for every creature and object in
	# it. Showing them is a divergence, so it is a feature: 1:1 keeps Qud's text-only rows.
	"popupicons": ["Menu popups: show each row's sprite", true],
	# ON by default. The cursor carries the verb — boots, a speech bubble, a hand, a stairs arrow —
	# and a click follows it. Qud's own cursor says nothing, so 1:1 keeps that silence.
	"mouseassist": ["Mouse assist: the cursor shows what a click will do", true],
}

## WHERE USER MODE STOPS CLONING 1:1 — the two questions, and they are NOT the same question.
##
## User mode renders as a 1:1 CLONE of Qud and diverges only where a QoL feature says so. So a
## surface asking "do I take Qud's shape here?" is really asking one of two things, and the answer
## in user mode differs:
##
##   qud_shape("msglog")   Qud's shape UNLESS that feature has been loaded back — it HAS a
##                         user-mode form, and this is what selects between them.
##   clone_of_qud()        identical in both modes, by decision — there is no user-mode form.
##
## They used to be one call with an optional argument, and the bare form was the trap: with no
## feature it can never be false in user mode, so an `else` hanging off it was unreachable in BOTH
## modes. Three features were written, shipped and unreachable that way (the message log's grouping,
## Nearby's larger icons, row 4's user-mode heights) — each read as a deleted feature and was only
## a dead branch. The feature name is now REQUIRED, so the ambiguous form cannot be written at all,
## and the decision is legible in the call itself rather than in a comment beside it.
func qud_shape(feature: String) -> bool:
	if one_to_one():
		return true
	if feature != "" and qol_on(feature):
		return false      # this QoL feature has been loaded back in
	return true           # user mode: Qud's shape until told otherwise

## "This surface is Qud's shape in BOTH modes." An assertion, not a shortcut — say it only where
## there is genuinely no user-mode alternative. If you find yourself wanting an `else` here, what
## you actually want is a QoL feature: register it in QOL_FEATURES and call qud_shape(name), which
## is the one path that makes a user-mode form reachable (and puts it in Options and presets for
## free, since both enumerate the registry).
func clone_of_qud() -> bool:
	# CONSTANT TRUE, and deliberately so: both modes are Qud's shape here, which is the whole claim.
	# It stays a call rather than becoming an `if true` at 48 sites because it is the ONE lever if
	# that policy ever changes, and because the name is what makes the claim legible where it is
	# made. qud_shape(feature) is the only gate that can answer false in user mode.
	return true

## Is a named QoL feature switched back on? Unknown names are always off -- a typo must not
## silently re-enable a divergence.
func qol_on(feature: String) -> bool:
	if not QOL_FEATURES.has(feature):
		return false
	return bool(get_value("qol_" + feature, bool(QOL_FEATURES[feature][1])))

var _instance_lock: TCPServer = null   # held for the process lifetime — see _ready
var _data: Dictionary = {}
var _rect_mtime := -1.0

func _ready() -> void:
	# ── SINGLE INSTANCE, enforced by the app itself ──────────────────────────────────────
	# Two Raves viewers (a dev run beside the exported app, or a double hv launch) both render
	# the same bridge traffic and fight over Metal buffers — measured 2026-08-24 as paired
	# SIGBUS _platform_memmove crashes, one per instance window. The lock is a localhost port:
	# first instance binds it and lives; any later one sees the bind fail and quits before it
	# creates a renderer. The port is arbitrary and private; the server accepts nothing.
	# NOT a bind test: Godot's TCPServer uses SO_REUSEPORT on macOS, so a second listener
	# binds happily beside the first (measured — the bind "lock" never failed). Instead the
	# newcomer CONNECTS to the port: a live connection means a live holder, and the newcomer
	# quits before it creates a renderer. The holder never accepts; probes just disconnect.
	var probe := StreamPeerTCP.new()
	if probe.connect_to_host("127.0.0.1", 17893) == OK:
		for i in 30:
			probe.poll()
			if probe.get_status() != StreamPeerTCP.STATUS_CONNECTING:
				break
			OS.delay_msec(10)
		if probe.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			probe.disconnect_from_host()
			print("[instance-lock] another Raves viewer is already running — quitting this one")
			get_tree().quit()
			return
	_instance_lock = TCPServer.new()
	_instance_lock.listen(17893, "127.0.0.1")
	for a in Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args()):
		if a == "--one-to-one" or a == "--1to1":
			one_to_one_only = true
	_load()
	apply_global()
	# Window-placement channel: highvisor WRITES window_rect.json (the reverse of our
	# state reports) and we place ourselves via DisplayServer — macOS AX cannot
	# reliably move a borderless Godot window (readback showed sets landing at
	# y=-2196 / failing outright once 1:1 went chromeless).
	var t := Timer.new()
	t.wait_time = 0.5
	t.timeout.connect(_poll_window_rect)
	add_child(t)
	t.start()
	_poll_window_rect()

func _poll_window_rect() -> void:
	var path := InputModel.support_dir().path_join("window_rect.json")
	if not FileAccess.file_exists(path):
		return
	var m := FileAccess.get_modified_time(path)
	if float(m) == _rect_mtime:
		return
	_rect_mtime = float(m)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return   # never fight fullscreen
	var w := int(d.get("w", 0))
	var h := int(d.get("h", 0))
	# SANITY: refuse a placement that would land the window off every screen.
	# A rect computed on another machine's layout (the Mac's 4K stack docked us
	# at y=-1269 on the PC) silently broke the capture rig's calibrated
	# geometry mid-run. Validate the TRANSLATED rect against real screens;
	# skip the whole request when it doesn't intersect any of them.
	if d.has("x") and d.has("y") and w > 0 and h > 0:
		var off_chk := DisplayServer.screen_get_position(DisplayServer.get_primary_screen())
		var tx := int(d.get("x")) + off_chk.x
		var ty := int(d.get("y")) + off_chk.y
		var on_any := false
		for si in DisplayServer.get_screen_count():
			var sp := DisplayServer.screen_get_position(si)
			var ssz := DisplayServer.screen_get_size(si)
			if tx < sp.x + ssz.x and tx + w > sp.x and ty < sp.y + ssz.y and ty + h > sp.y:
				on_any = true
				break
		if not on_any:
			print("Settings: REJECTED off-screen window_rect ", d)
			return
	if w > 0 and h > 0:
		DisplayServer.window_set_size(Vector2i(w, h))
	if d.has("x") and d.has("y"):
		# The rect arrives in CG coordinates (origin = primary display's top-left);
		# Godot's virtual-desktop origin is the bounding box's top-left. The primary
		# screen's godot-space position IS the offset between the two spaces.
		var off := DisplayServer.screen_get_position(DisplayServer.get_primary_screen())
		DisplayServer.window_set_position(Vector2i(int(d.get("x")), int(d.get("y"))) + off)

func get_value(key: String, default_val = null) -> Variant:
	if _data.has(key):
		return _data[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return default_val

func set_value(key: String, value) -> void:
	_data[key] = value

## Persist to disk, then re-apply the global settings (so a change takes effect live).
func save() -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data, "  "))
	apply_global()

## Apply the settings that affect the whole app immediately (not per-view).
func apply_global() -> void:
	UiFont.scale = clampf(float(get_value("font_scale", 1.0)), 0.6, 2.0)
	var fs := bool(get_value("fullscreen", false))
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	# CHROMELESS, matching Qud's -popupwindow: the macOS title strip eats 32px of the frame and
	# shifts all content down, which ghosts every parity diff (2026-08-03 menu baseline) — measured
	# again 2026-08-12, when it was the ONLY thing left between the two modes' title screens. With
	# it aligned away they were pixel-identical, 0 of 1,950,720.
	#
	# It used to be 1:1 only ("user mode keeps the titlebar"). It is now the first named QoL
	# feature instead: off by default like the rest, switch `titlebar` on to get it back.
	# ONLY ON CHANGE: re-setting the borderless flag on macOS recreates the window even when
	# the value is identical — every Settings.save() flashed the whole app out and back, and a
	# slider drag (one save per tick) was a flash storm. Daniel: "the bottom 3 sliders make
	# the whole raves window disappear and then reappear."
	var want_borderless := qud_shape("titlebar")
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS) != want_borderless:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, want_borderless)

func _path() -> String:
	return InputModel.support_dir().path_join("settings.json")

func _load() -> void:
	_data = DEFAULTS.duplicate(true)
	var path := _path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			_data[k] = d[k]
