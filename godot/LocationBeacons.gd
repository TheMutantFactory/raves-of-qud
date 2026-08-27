extends Node3D

## LOCATION BEACONS — a slab of light standing ON a place you asked to be shown, the way a
## navigation app plants a pin you can see before you can see the destination.
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
## STOOD AT THE REAL PLACE, AT REAL SCALE. Daniel: "The beacons need to be smaller when they're
## farther away. Can we set the beacons to their actual locations? Maybe create a rectangle the size
## of the zone at the zone and just let the camera work?"
##
## They used to be pinned at a fixed 34 cells, which made every beacon the same size whatever it was
## marking — a place seven parasangs off looked exactly as close as one you could walk to before
## dark. Now the marker is a ZONE-SIZED SLAB (80x25 cells, Qud's own zone footprint) standing at the
## target's true offset, and the perspective camera does the rest: near ones fill the view, far ones
## shrink to a smudge on the horizon. That is the depth cue, and it is free.
##
## ...which means the slab is a claim about ACCURACY, too. A map note names a parasang, not a cell,
## so the honest thing to draw is an area rather than a point — the slab says "somewhere in here",
## which is exactly what the journal knows.
##
## FOG IS OFF FOR THE SLAB, and has to be. SkyGrade's depth fog is total by 240 cells; a beacon five
## parasangs out is 375, so every distant one — the ones that most need marking — would have been
## erased by the atmosphere the moment they were placed at their real distance.

const PULSE_HZ := 0.45        # slow — a lighthouse, not a warning light
const PULSE_DEPTH := 0.30
## The name-plate's size at the regime's reference distance, and the range it may shrink and grow
## The plate is a label, not part of the scenery: it takes the depth cue (so a far beacon's name
## recedes with it) but stops well short of the vanishing point, because a name nobody can read
## marks nothing.
const PLATE_FONT := 20
const PLATE_MIN := 11
const PLATE_MAX := 28

## THE WORLD IS TWO PLACES AND A PARASANG IS A DIFFERENT SIZE IN EACH. Daniel: "Let's add the
## beacons to the overworld. Need to fix the distances. They're different from the surface
## distances."
##
## Measured off the wire rather than assumed. On the surface a zone is 80x25 cells of ground and a
## parasang is 3x3 of those — 240 cells east, 75 north — and the zone block carries wx/wy/zx/zy to
## say which one you are standing in. STEP ONTO THE WORLD MAP and every one of those comes back -1
## and the zone id loses its numbers ("JoppaWorld", not "JoppaWorld.8.22.2.1.10"), because the world
## map is ONE zone whose 80x25 cells ARE the parasangs: the player's cell is their world position,
## and the note's (mx,my) is its own cell.
##
## So everything downstream splits: how far a place is, which way it lies, how big to draw the
## marker, and how far away "far" is. What does NOT split is the unit the panel prints — a parasang
## is a parasang in both, which is the whole point of fixing this. The overworld numbers were coming
## out at 20-28 for places the surface called 0.4 and 7.4, because the surface formula was being fed
## the -1s.
const PARA := {
	# world units per parasang, marker footprint, marker height, "far" distance, plate reference
	"surface":   {"scale": Vector2(240.0, 75.0), "foot": Vector2(80.0, 25.0),
		"tall": 45.0, "near_ref": 300.0, "ref_dist": 140.0},
	# On the world map a parasang IS one cell, so the marker is one cell square — anything wider
	# would cover the places either side of the one it is marking.
	"overworld": {"scale": Vector2(1.0, 1.0), "foot": Vector2(1.0, 1.0),
		"tall": 6.0, "near_ref": 5.0, "ref_dist": 7.0},
}

var _targets: Array = []      # [{id, name, mx, my, color}]
var _marks := {}              # id -> Node3D (the slab)
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
## ...and the player's position IN PARASANGS, fractional — the one measurement both regimes share,
## and what every distance and bearing is derived from.
var _para := Vector2.ZERO
var _regime := "surface"
var _t := 0.0
var _shader_cache: Shader

func _ready() -> void:
	set_process(true)
	_hud = CanvasLayer.new()
	_hud.name = "BeaconPlates"
	_hud.layer = 1               # over the 3D, under the frame chrome (which owns layer 0 + the CRT at 100)
	add_child(_hud)

## The window rect the 3D actually shows through (MainFrame's play hole). An empty rect means "the
## whole window", which is how standalone Main runs.
func set_play_hole(r: Rect2) -> void:
	_hole = r

## The live zone + the player's cell in it. Both halves matter: the parasang position sets how far
## each place is and which way, the LOCAL cell is where in the rendered world the marker is planted.
func set_player(zone: Dictionary, px: int, py: int) -> void:
	_px = float(px)
	_pz = float(py)
	var was := _regime
	_regime = "overworld" if _is_world_map(zone) else "surface"
	if _regime == "overworld":
		# The world map's cells ARE parasangs, so the player's cell is the answer. +0.5 puts them in
		# the middle of their own, which is where the target offsets are measured from too — the two
		# halves cancel, and a note on your own cell reads as distance zero rather than half a step.
		_para = Vector2(_px + 0.5, _pz + 0.5)
	else:
		var w := float(zone.get("width", 80))
		var h := float(zone.get("height", 25))
		_para = Vector2(
			((float(zone.get("wx", 0)) * 3.0 + float(zone.get("zx", 0))) * w + _px) / PARA.surface.scale.x,
			((float(zone.get("wy", 0)) * 3.0 + float(zone.get("zy", 0))) * h + _pz) / PARA.surface.scale.y)
	if was != _regime:
		_apply_regime()      # footprint, height and fade distance all change with the map you are on
	_place()

## Is this Qud's WORLD MAP rather than a patch of ground? Two independent tells, and it takes either:
## the zone id drops its coordinates ("JoppaWorld", not "JoppaWorld.8.22.2.1.10") and every one of
## wx/wy/zx/zy/z comes back -1. Reading the -1s as real coordinates is exactly what put Bethesda
## Susa — the parasang the player was standing in — at "SE 25.5".
func _is_world_map(zone: Dictionary) -> bool:
	return int(zone.get("wx", 0)) < 0 or not String(zone.get("id", "")).contains(".")

## Resize every marker for the map we are now on. Cheap, and it only runs on a crossing.
func _apply_regime() -> void:
	var r: Dictionary = PARA[_regime]
	for m in _marks.values():
		var slab: MeshInstance3D = m.get_node_or_null("Slab")
		if slab == null:
			continue
		var box: BoxMesh = slab.mesh
		box.size = Vector3(r.foot.x, r.tall, r.foot.y)
		slab.position = Vector3(0, r.tall * 0.5, 0)
		slab.extra_cull_margin = r.tall
		var mat: ShaderMaterial = slab.get_surface_override_material(0)
		if mat != null:
			mat.set_shader_parameter("slab_h", r.tall)
			mat.set_shader_parameter("near_ref", r.near_ref)

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
	return _delta_para(mx, my).length()

## Compass bearing to a target, as a cardinal name. Measured in WORLD units for the same reason the
## placement is (see the header), so the letter and the column always agree.
func bearing_to(mx: int, my: int) -> String:
	var d := _delta(mx, my)
	# "Here" is a fraction of a PARASANG, not of a cell — half a cell is the whole world map.
	if _delta_para(mx, my).length() < 0.15:
		return "here"
	const NAMES := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var a := fposmod(atan2(d.y, d.x), TAU)
	return NAMES[int(round(a / (TAU / 8.0))) % 8]

## Target minus player, IN PARASANGS. The one measurement that means the same thing on both maps —
## the panel's number comes straight off it.
func _delta_para(mx: int, my: int) -> Vector2:
	return Vector2(float(mx) + 0.5, float(my) + 0.5) - _para

## ...and the same offset in the WORLD UNITS of whichever map is under us: 240x75 cells per parasang
## on the surface, one cell per parasang on the world map. Both the bearing and the placement read
## this, so the letter in the list and the marker on the ground can never disagree.
func _delta(mx: int, my: int) -> Vector2:
	return _delta_para(mx, my) * PARA[_regime].scale

## Stand each slab AT ITS PLACE — the player's own cell plus the true offset, in cells. No clamp:
## the whole point of the change is that a beacon seven parasangs off is 525 cells off, and looks it.
func _place() -> void:
	for t in _targets:
		var m: Node3D = _marks.get(String(t.get("id", "")), null)
		if m == null:
			continue
		var d := _delta(int(t.get("mx", 0)), int(t.get("my", 0)))
		m.position = Vector3(_px + d.x, 0.0, _pz + d.y)

func _process(dt: float) -> void:
	if _marks.is_empty():
		return
	_t += dt
	# ONE PHASE FOR ALL OF THEM. Beacons that breathe out of step read as separate effects; in step
	# they read as one system, which is what they are.
	var k: float = 1.0 - PULSE_DEPTH * 0.5 * (1.0 - cos(_t * TAU * PULSE_HZ))
	for m in _marks.values():
		var slab: MeshInstance3D = m.get_node_or_null("Slab")
		if slab != null:
			var mat: ShaderMaterial = slab.get_surface_override_material(0)
			if mat != null:
				var c: Color = m.get_meta("tint", Color.WHITE)
				mat.set_shader_parameter("tint", Color(c.r, c.g, c.b, c.a * k))
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
		var head: Vector3 = m.global_position + Vector3(0, float(PARA[_regime].tall), 0)
		# BEHIND THE CAMERA STILL UNPROJECTS — to a point mirrored back into the frame. Without this
		# test a beacon at your back draws its name in front of you, pointing the wrong way.
		if cam.is_position_behind(head):
			lab.visible = false
			continue
		var p := cam.unproject_position(head)
		# HORIZONTALLY out of the play area means the beacon is not on screen at all — hide it, or
		# the name slides under the opaque side panels. VERTICALLY is different and is clamped
		# below: a marker two parasangs off is 45 cells tall in a frame that only shows the horizon,
		# so its head leaves the top long before the beacon does, and the name went with it.
		if _hole.size.x > 1.0 and (p.x < _hole.position.x or p.x > _hole.end.x):
			lab.visible = false
			continue
		# THE NAME TAKES THE DEPTH CUE TOO. The slab shrinks with distance on its own now; a plate
		# that stayed one size would make a beacon five parasangs out shout as loudly as the one in
		# the next zone. It shrinks by the square root of the distance ratio (gentler than true
		# perspective) and stops at PLATE_MIN, because a name nobody can read marks nothing.
		var dist: float = cam.global_position.distance_to(head)
		var px: int = clampi(int(round(float(PLATE_FONT)
			* sqrt(float(PARA[_regime].ref_dist) / maxf(dist, 0.001)))), PLATE_MIN, PLATE_MAX)
		if int(lab.get_theme_font_size("font_size")) != px:
			lab.add_theme_font_size_override("font_size", px)
			lab.add_theme_constant_override("outline_size", maxi(3, px / 3))
			lab.reset_size()
		var sz := lab.get_minimum_size()
		var at := p - Vector2(sz.x * 0.5, sz.y)        # centred on the slab, sitting above its head
		if _hole.size.x > 1.0:
			at.y = clampf(at.y, _hole.position.y + 2.0, _hole.end.y - sz.y - 2.0)
		lab.visible = true
		lab.position = at

func _make_mark(t: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Beacon_" + String(t.get("id", "?"))

	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	var box := BoxMesh.new()
	var r: Dictionary = PARA[_regime]
	box.size = Vector3(r.foot.x, r.tall, r.foot.y)   # one zone of ground, or one world-map cell
	slab.mesh = box
	slab.position = Vector3(0, float(r.tall) * 0.5, 0)
	# NEVER CULLED BY DISTANCE OR ANGLE: a beacon can be 500 cells out and half of it below the
	# horizon, and Godot's default AABB culling is fine with that — but the extra margin costs
	# nothing and a beacon that blinks out as you turn is the one bug nobody would report clearly.
	slab.extra_cull_margin = float(r.tall)
	slab.set_surface_override_material(0, _slab_mat())
	root.add_child(slab)

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
	var slab: MeshInstance3D = root.get_node_or_null("Slab")
	if slab != null:
		var mat: ShaderMaterial = slab.get_surface_override_material(0)
		if mat != null:
			mat.set_shader_parameter("tint", Color(c.r, c.g, c.b, 0.55))

## The slab's material. A SHADER rather than a StandardMaterial3D with a ramp texture, because a
## BoxMesh's six faces do not share one vertical UV — the fade has to come from the vertex height,
## which is the one thing every face agrees on.
func _slab_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader()
	m.set_shader_parameter("tint", Color(1, 1, 1, 0.55))
	m.set_shader_parameter("slab_h", PARA[_regime].tall)
	m.set_shader_parameter("near_ref", PARA[_regime].near_ref)
	m.render_priority = 2
	return m

## Solid at the foot, gone at the head: a flat-topped block reads as something BUILT, one that
## dissolves upward reads as light.
##
## depth_draw_never keeps the two visible faces from cutting each other; the depth TEST stays on, so
## the world still occludes it — Daniel: "The beacon is shining through the floor", and it is the
## ground in front of you that has to win. fog_disabled is not a preference: SkyGrade's depth fog is
## total by 240 cells and these now stand at their real distance, which is routinely further.
func _shader() -> Shader:
	if _shader_cache != null:
		return _shader_cache
	_shader_cache = Shader.new()
	_shader_cache.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float slab_h = 45.0;
uniform float near_ref = 300.0;
varying float up;
varying float depth;
void vertex() {
	up = clamp((VERTEX.y + slab_h * 0.5) / max(slab_h, 0.001), 0.0, 1.0);
	depth = -(VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	ALBEDO = tint.rgb;
	// Fades toward the head (light, not masonry) AND toward the viewer (see near_ref).
	ALPHA = tint.a * pow(1.0 - up, 1.6) * clamp(depth / near_ref, 0.16, 1.0);
}
"""
	return _shader_cache
