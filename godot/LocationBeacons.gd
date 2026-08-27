extends Node3D

## LOCATION BEACONS — a light column standing over the horizon in the direction of a place you
## asked to be shown, the way a navigation app plants a pin you can see before you can see the
## destination.
##
## Daniel: "If you enable the location (checkbox), it will show up on the game like a 'google maps'
## navigation beacon on the horizon."
##
## WHAT A BEACON IS AIMED AT. Qud's journal map notes carry a PARASANG (JournalMapNote.ParasangX/Y)
## — a world-map cell, not a zone cell, so the target is a 240x75 patch of ground and the beacon
## points at its middle. That is the right resolution for this: the beacon says WHICH WAY, and the
## last three zones of the walk are Qud's business, not ours.
##
## THE WORLD IS NOT SQUARE, and the bearing has to respect that. A parasang is 3x3 zones and a zone
## is 80x25 cells, so one parasang east is 240 cells of walking and one parasang north is 75 — a
## displacement that reads as 45 degrees on Qud's world map is a shallow 17 degrees on the ground.
## The beacon lives on the ground, so it is placed in RAVES' world units (x = cells east, z = cells
## south, the same metric the store offsets neighbouring zones by). Point it the map's way and it
## would point somewhere you cannot walk.
##
## THE NAME IS DRAWN IN 2D, the column in 3D. A Label3D standing beside the beam is 34 cells out,
## and CameraRig starts its far depth-of-field at 18 — so the one part of a beacon that has to be
## READ was the one part the lens was blurring. Daniel: "The location text in the game field is
## behind the tilt-shift. Probably need to add it to an overlay." So the label is a HUD control
## whose position is the beam's head unprojected through the live camera: it tracks the world
## exactly, and no post-process touches it.
##
## RANGE IS CLAMPED, NOT SCALED. The marker sits at the true distance while that is near enough to
## mean something and parks at FAR_R beyond it, so a place four parasangs off still has a visible
## column instead of one lost in the fog — and arriving walks the beacon down onto the spot rather
## than leaving it pinned at arm's length forever.

## How far out a distant beacon stands, in cells. Beyond the zone (80x25) on purpose: the column is
## meant to read as being OUT THERE, past the ground you can walk this turn.
const FAR_R := 34.0
## ...and how close it may come. Under this the column would be standing on the player.
const NEAR_R := 5.0
const BEAM_H := 26.0          # tall enough to clear any wall and still be in frame at a low angle
const BEAM_R_BOT := 0.95
const BEAM_R_TOP := 0.30
## The label rides at the BEAM'S FOOT, not its head. At the head it was simply off the top of the
## frame — a 26-cell column seen from a low compass camera leaves the screen long before it ends —
## and the foot is where the eye already is: the horizon, which is what the beacon is standing on.
const LABEL_Y := 4.2
const PULSE_HZ := 0.45        # slow — a lighthouse, not a warning light
const PULSE_DEPTH := 0.30

## Cells per parasang, from Qud's own geometry: 3 zones of 80x25.
const PARA_W := 240.0
const PARA_H := 75.0

var _targets: Array = []      # [{id, name, mx, my, color}]
var _marks := {}              # id -> Node3D (the column)
var _plates := {}             # id -> Label   (the name, on the HUD overlay)
var _hud: CanvasLayer         # the overlay the plates live on
## The play area, in window pixels — MainFrame's hole, pushed down from Main. A plate outside it is
## hidden rather than clipped: the side panels are opaque, and a name-plate sliding under the message
## log reads as a bug in the log.
var _hole := Rect2()
## "Something is in front of the playfield" — Main's own _modal_owns_input, handed over rather than
## re-derived. The plates are HUD controls on their own layer, so a status screen does NOT cover
## them: a beacon's name drew across Qud's Equipment tab until this asked.
var blocked_cb: Callable = Callable()
var _px := 0.0                # player's LOCAL cell in the live zone (where the beacons stand from)
var _pz := 0.0
var _gx := 0.0                # ...and their GLOBAL cell, which is what the bearing is measured in
var _gz := 0.0
var _t := 0.0
var _ramp: Texture2D

func _ready() -> void:
	set_process(true)
	_ramp = _beam_ramp()
	_hud = CanvasLayer.new()
	_hud.name = "BeaconPlates"
	_hud.layer = 1               # over the 3D, under the frame chrome (which owns layer 0 + the CRT at 100)
	add_child(_hud)

## The window rect the 3D actually shows through (MainFrame's play hole). An empty rect means "the
## whole window", which is how standalone Main runs.
func set_play_hole(r: Rect2) -> void:
	_hole = r

## The live zone + the player's cell in it. Both halves matter: the GLOBAL position sets which way
## each beacon lies, the LOCAL one is where in the rendered world the column gets planted.
func set_player(zone: Dictionary, px: int, py: int) -> void:
	_px = float(px)
	_pz = float(py)
	var w := float(zone.get("width", 80))
	var h := float(zone.get("height", 25))
	_gx = (float(zone.get("wx", 0)) * 3.0 + float(zone.get("zx", 0))) * w + _px
	_gz = (float(zone.get("wy", 0)) * 3.0 + float(zone.get("zy", 0))) * h + _pz
	_place()

## The enabled locations, from the Locations panel. Rebuilds only what changed.
func set_targets(list: Array) -> void:
	_targets = list
	var want := {}
	for t in list:
		want[String(t.get("id", ""))] = t
	for id in _marks.keys():
		if not want.has(id):
			_marks[id].queue_free()
			_marks.erase(id)
			if _plates.has(id):
				_plates[id].queue_free()
				_plates.erase(id)
	for id in want.keys():
		if not _marks.has(id):
			var m := _make_mark(want[id])
			add_child(m)
			_marks[id] = m
			var plate := _make_plate(want[id])
			_hud.add_child(plate)
			_plates[id] = plate
		_retint(_marks[id], want[id])
	_place()

## Distance to a target IN PARASANGS — the unit Qud itself measures the world in, and the one the
## panel prints beside each row.
func parasangs_to(mx: int, my: int) -> float:
	var d := _delta(mx, my)
	return Vector2(d.x / PARA_W, d.y / PARA_H).length()

## Compass bearing to a target, as a cardinal name. Measured in WORLD units for the same reason the
## placement is (see the header), so the letter and the column always agree.
func bearing_to(mx: int, my: int) -> String:
	var d := _delta(mx, my)
	if d.length() < 0.5:
		return "here"
	const NAMES := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var a := fposmod(atan2(d.y, d.x), TAU)
	return NAMES[int(round(a / (TAU / 8.0))) % 8]

## Target centre minus player, in global cells.
func _delta(mx: int, my: int) -> Vector2:
	var tx := (float(mx) * 3.0 + 1.0) * 80.0 + 40.0
	var tz := (float(my) * 3.0 + 1.0) * 25.0 + 12.0
	return Vector2(tx - _gx, tz - _gz)

func _place() -> void:
	for t in _targets:
		var m: Node3D = _marks.get(String(t.get("id", "")), null)
		if m == null:
			continue
		var d := _delta(int(t.get("mx", 0)), int(t.get("my", 0)))
		var dir := d.normalized() if d.length() > 0.001 else Vector2(0, -1)
		var r: float = clampf(d.length(), NEAR_R, FAR_R)
		m.position = Vector3(_px + dir.x * r, 0.0, _pz + dir.y * r)

func _process(dt: float) -> void:
	if _marks.is_empty():
		return
	_t += dt
	# ONE PHASE FOR ALL OF THEM. Beacons that breathe out of step read as separate effects; in step
	# they read as one system, which is what they are.
	var k: float = 1.0 - PULSE_DEPTH * 0.5 * (1.0 - cos(_t * TAU * PULSE_HZ))
	for m in _marks.values():
		var beam: MeshInstance3D = m.get_node_or_null("Beam")
		if beam != null:
			var mat: StandardMaterial3D = beam.get_surface_override_material(0)
			if mat != null:
				var c: Color = m.get_meta("tint", Color.WHITE)
				mat.albedo_color = Color(c.r, c.g, c.b, c.a * k)
	_track_plates()

## Put each name-plate where its column's head lands on screen. THE LIVE CAMERA, asked of the
## viewport rather than held: Raves switches between eight camera modes and a seven-pane multiview,
## and a cached camera would leave every plate pinned to wherever the last one was looking.
func _track_plates() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if blocked_cb.is_valid() and bool(blocked_cb.call()):
		for lab in _plates.values():
			lab.visible = false
		return
	for id in _plates.keys():
		var lab: Label = _plates[id]
		var m: Node3D = _marks.get(id, null)
		if m == null:
			continue
		var head: Vector3 = m.global_position + Vector3(0, LABEL_Y, 0)
		# BEHIND THE CAMERA STILL UNPROJECTS — to a point mirrored back into the frame. Without this
		# test a beacon at your back draws its name in front of you, pointing the wrong way.
		if cam.is_position_behind(head):
			lab.visible = false
			continue
		var p := cam.unproject_position(head)
		var sz := lab.get_minimum_size()
		var at := p - Vector2(sz.x * 0.5, sz.y)      # centred on the column, sitting above the head
		if _hole.size.x > 1.0 and not _hole.has_point(p):
			lab.visible = false
			continue
		lab.visible = true
		lab.position = at

func _make_mark(t: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Beacon_" + String(t.get("id", "?"))

	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = BEAM_R_TOP
	cyl.bottom_radius = BEAM_R_BOT
	cyl.height = BEAM_H
	cyl.radial_segments = 12
	cyl.rings = 1
	beam.mesh = cyl
	beam.position = Vector3(0, BEAM_H * 0.5, 0)
	beam.set_surface_override_material(0, _beam_mat())
	root.add_child(beam)

	_retint(root, t)
	return root

## One beacon's HUD name-plate. A plain Label on the overlay layer, positioned every frame from the
## beam's head — see the header for why this is not a Label3D.
func _make_plate(t: Dictionary) -> Label:
	var lab := Label.new()
	lab.name = "Plate_" + String(t.get("id", "?"))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_font_size_override("font_size", 20)
	# A hard outline, because the plate floats over sky, ground and buildings by turns and has no
	# box of its own to sit in.
	lab.add_theme_constant_override("outline_size", 6)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	return lab

## Name + colour, applied to an existing marker (a rename or a recolour must not rebuild the mesh).
func _retint(root: Node3D, t: Dictionary) -> void:
	var c: Color = t.get("color", Color8(0x45, 0xd5, 0xc9))
	root.set_meta("tint", Color(c.r, c.g, c.b, 0.55))
	var lab: Label = _plates.get(String(t.get("id", "")), null)
	if lab != null:
		lab.text = String(t.get("name", ""))
		lab.add_theme_color_override("font_color", c)
	var beam: MeshInstance3D = root.get_node_or_null("Beam")
	if beam != null:
		var mat: StandardMaterial3D = beam.get_surface_override_material(0)
		if mat != null:
			mat.albedo_color = Color(c.r, c.g, c.b, 0.55)

func _beam_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# DEPTH-TESTED, so the world occludes it. Daniel: "The beacon is shining through the floor" — a
	# column planted 34 cells out has most of its length below the horizon, and drawing that over
	# the ground in front of you made a distant landmark look like a pillar of light standing in the
	# middle of Joppa. The NAME still ignores every wall; that one is a HUD control, and it is the
	# half that has to be readable from anywhere.
	m.disable_receive_shadows = true
	m.albedo_texture = _ramp          # the vertical fade — see _beam_ramp
	m.render_priority = 2
	return m

## The column's fade: solid at the foot, gone at the head. A flat-topped beam reads as a PILLAR
## (something built); one that dissolves upward reads as light.
func _beam_ramp() -> Texture2D:
	var img := Image.create(1, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		# MEASURED IN PIXELS, because the screenshot lies about this: the image viewer lifts a dark
		# scene and the column looked head-bright either way. Sampling the beam's excess over the
		# background beside it settled it — CylinderMesh maps v=0 to the TOP, so the ramp is written
		# head-first, and the "fix" that flipped it made the column solid in the sky.
		var f := float(y) / 63.0
		img.set_pixel(0, y, Color(1, 1, 1, pow(f, 1.6)))
	return ImageTexture.create_from_image(img)
