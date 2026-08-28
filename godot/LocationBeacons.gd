extends Node3D

## LOCATION BEACONS — the place's OWN PICTURE standing on the ground where it is, the way a
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
## FOG IS OFF FOR THE CARD, and has to be. SkyGrade's depth fog is total by 240 cells; a beacon five
## parasangs out is 375, so every distant one — the ones that most need marking — would have been
## erased by the atmosphere the moment they were placed at their real distance.

## The name-plate's size at the regime's reference distance, and the range it may shrink and grow
## The plate is a label, not part of the scenery: it takes the depth cue (so a far beacon's name
## recedes with it) but stops well short of the vanishing point, because a name nobody can read
## marks nothing.
const PLATE_FONT := 20
const PLATE_MIN := 11
const PLATE_MAX := 28
## Air between the name and the top of the art, as a fraction of the plate's own font size.
const PLATE_GAP := 0.55

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
var _flat := false              # cards laid flat for a straight-down camera (see _face_camera)
var _tiles: RefCounted          # QudTiles — recolours a place's own sprite
var tiles_dir := ""             # pushed from Main with the snapshot
var palette := {}

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
		# The card is sized from the regime and its own art; _retint knows both, so a crossing just
		# asks it again rather than restating the arithmetic here.
		for t in _targets:
			if String(t.get("id", "")) == _mark_id(m):
				_retint(m, t)
				break

## Which target a marker node belongs to — its node name carries the id it was built with.
func _mark_id(m: Node3D) -> String:
	return String(m.name).trim_prefix("Beacon_")

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

func _process(_dt: float) -> void:
	if _marks.is_empty():
		return
	_face_camera()
	_track_plates()

## UPRIGHT, OR LAID FLAT FOR A CAMERA THAT IS OVERHEAD — the same choice ZoneRenderer makes for
## every other tile sprite (set_top_down), decided here from the live camera instead of plumbed in,
## because the beacons are a sibling of the renderer and the multiview panes each look their own way.
func _face_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Straight down is forward.y == -1; -0.94 is about 70 degrees below the horizon.
	var flat: bool = -cam.global_transform.basis.z.y > 0.94
	if flat == _flat:
		return
	_flat = flat
	var mode := BaseMaterial3D.BILLBOARD_ENABLED if flat else BaseMaterial3D.BILLBOARD_FIXED_Y
	for m in _marks.values():
		var card: MeshInstance3D = m.get_node_or_null("Card")
		if card != null and card.material_override != null:
			card.material_override.billboard_mode = mode

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
		var head: Vector3 = m.global_position + Vector3(0, float(m.get_meta("top", PARA[_regime].tall)), 0)
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
		# CLEAR OF THE ART, not resting on it. p is the card's top edge, so a plate placed by its own
		# height alone sits with its descenders in the sprite's outline. The gap is a fraction of the
		# font rather than a pixel count, because the font itself shrinks with distance.
		var at := p - Vector2(sz.x * 0.5, sz.y + float(px) * PLATE_GAP)
		if _hole.size.x > 1.0:
			at.y = clampf(at.y, _hole.position.y + 2.0, _hole.end.y - sz.y - 2.0)
		lab.visible = true
		lab.position = at

func _make_mark(t: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Beacon_" + String(t.get("id", "?"))
	var r: Dictionary = PARA[_regime]

	# THE PLACE, AT THE SIZE OF A ZONE. Daniel: "Let's use the location sprite and make it the size
	# of the zone and the color of the sprite."
	#
	# The slab this replaces said "something is over there" in a colour picked from a cycle. Qud
	# already has a picture of every one of these — the world-map terrain object standing on that
	# parasang, the same art its own map draws — so the beacon IS that picture: Joppa's huts, Red
	# Rock's red rock, in the colours Qud gives them. Nothing has to be invented and nothing has to
	# be looked up twice.
	# A QUAD WITH OUR OWN MATERIAL, not a Sprite3D. Sprite3D builds its material internally and
	# gives no way to switch fog off — and SkyGrade's depth fog is total by 240 cells, while these
	# stand at their real distance, routinely further. The slab this replaces disabled fog in its
	# shader; losing that is why the first version of this card was invisible from four parasangs
	# and looked for all the world like it had never been created.
	var card := MeshInstance3D.new()
	card.name = "Card"
	card.mesh = QuadMesh.new()
	card.material_override = _card_mat()
	card.position = Vector3(0, float(r.tall) * 0.5, 0)
	card.extra_cull_margin = float(r.tall)
	root.add_child(card)
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

## Name, art and size, applied to an existing marker — a rename or a recolour must not rebuild it.
##
## SIZED TO THE ZONE, from the art's own aspect: the width is the regime's footprint (a zone across
## on the ground, one cell on the world map) and the height follows the tile, so a 16x24 sprite
## stands half again as tall as it is wide instead of being squashed into a square.
func _retint(root: Node3D, t: Dictionary) -> void:
	var c: Color = t.get("color", Color8(0x45, 0xd5, 0xc9))
	var lab: Label = _plates.get(String(t.get("id", "")), null)
	if lab != null:
		lab.text = String(t.get("name", ""))
	var card: MeshInstance3D = root.get_node_or_null("Card")
	if card == null:
		return
	var mat: StandardMaterial3D = card.material_override
	var art: Dictionary = t.get("art", {})
	var tex: Texture2D = null
	if not art.is_empty() and String(art.get("tile", "")) != "":
		if _tiles == null:
			_tiles = load("res://QudTiles.gd").new()
		_tiles.tiles_dir = tiles_dir
		_tiles.palette = palette
		tex = _tiles.texture_for(art, true)
	if tex == null:
		# NO ART, STILL A BEACON: a location the mod found no terrain object for falls back to a
		# plain coloured card rather than vanishing, which is the failure nobody would report.
		tex = _blank_tex()
		mat.albedo_color = Color(c.r, c.g, c.b, 1.0)
	else:
		# ...and when there IS art, THE SPRITE IS THE BEACON: full white, full alpha, no tint and no
		# pulse. Daniel: "I can't tell if you're using the sprite artwork directly and applying an
		# effect... Can you use just the native sprite?" So nothing is applied over Qud's own pixels
		# — the only thing this material still insists on is being out of the fog, without which a
		# beacon at its real distance is erased by the atmosphere.
		mat.albedo_color = Color.WHITE
	# STANDING ON ITS OWN FEET, NOT ON ITS BOUNDING BOX. A Qud tile is 16x24 with the art sitting
	# wherever it likes inside that box: Red Rock's massif ends five rows early, which on a card 120
	# tall is TWENTY-FIVE CELLS of nothing underneath it. The quad was planted correctly the whole
	# time — its bottom edge measured within 3px of the horizon — but what the eye reads as the
	# beacon is the INK, and the ink was hanging a quarter of a card up. Daniel: "The height of the
	# sprite is okay, but it needs to be lowered to the ground." So the card is cropped to the art's
	# opaque bounds and that is what gets planted.
	var full := Vector2i(tex.get_width(), tex.get_height())
	var ink := _ink_rect(tex)
	tex = _crop(tex, ink)
	mat.albedo_texture = tex
	# THE NAME IS PAINTED OUT OF THE PICTURE IT NAMES. Daniel: "Let's also try and make it one of the
	# sprite colors." The palette colour it used before was a cycle position — the list's way of
	# telling two rows apart — and had nothing to do with what was standing on the horizon, so a red
	# massif was captioned in green. Now the plate takes a colour the sprite actually contains.
	if lab != null:
		lab.add_theme_color_override("font_color", _plate_color(tex, c))
	# SIZED TO THE ZONE: a WHOLE tile spans the regime's footprint — a zone across on the ground, one
	# cell on the world map — so the cropped card keeps that same per-pixel scale rather than being
	# stretched back out to the full width. A tile whose art is inset stays inset.
	var r2: Dictionary = PARA[_regime]
	var cell: float = float(r2.foot.x) / float(maxi(full.x, 1))
	var w: float = cell * float(ink.size.x)
	var h: float = cell * float(ink.size.y)
	var q: QuadMesh = card.mesh
	q.size = Vector2(w, h)
	card.position = Vector3(0, h * 0.5, 0)
	card.extra_cull_margin = h
	# THE PLATE RIDES THE CARD'S TOP, not the regime's slab height. The card is as tall as the art
	# makes it — a 16x24 tile a zone wide stands 120 up — so a plate pinned to the old 45 sat in the
	# middle of the picture it was supposed to be labelling.
	root.set_meta("top", h)

## The card's material: camera-facing, unlit, translucent, and OUT OF THE FOG — see _make_mark.
func _card_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# FIXED_Y, NOT A FULL BILLBOARD — this is what plants it. A full billboard tips the whole quad
	# back to face a camera that is looking down, pivoting about its CENTRE: a card 120 tall on a
	# 30-degree view swings its base thirty cells into the air, and the landmark reads as hanging in
	# the sky rather than standing on the ground. Daniel: "The height of the sprite is okay, but it
	# needs to be lowered to the ground." Turning only about Y keeps the bottom edge on y=0, which is
	# also how ZoneRenderer stands every other tile sprite. _face_camera lays it flat for overhead.
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true          # without this the quad's own size is thrown away
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true                   # SkyGrade's depth fog is total by 240 cells
	m.no_depth_test = true                 # a landmark is not hidden by the hill in front of it
	m.render_priority = 2
	return m

## The fallback card: one opaque pixel, tinted by the beacon's own colour and stretched to the same
## size as a real sprite would be.
var _blank: Texture2D
func _blank_tex() -> Texture2D:
	if _blank == null:
		var img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0.85))
		_blank = ImageTexture.create_from_image(img)
	return _blank

## The opaque bounds of a tile — the part of the 16x24 box the art actually uses. Everything outside
## it is padding, and padding under a beacon is what makes a planted card look airborne.
func _ink_rect(tex: Texture2D) -> Rect2i:
	var img := tex.get_image()
	if img == null:
		return Rect2i(0, 0, tex.get_width(), tex.get_height())
	var r := img.get_used_rect()
	# A fully transparent tile has no used rect; draw the whole box rather than nothing.
	return r if r.size.x > 0 and r.size.y > 0 else Rect2i(0, 0, img.get_width(), img.get_height())

func _crop(tex: Texture2D, r: Rect2i) -> Texture2D:
	if r.position == Vector2i.ZERO and r.size == Vector2i(tex.get_width(), tex.get_height()):
		return tex
	var img := tex.get_image()
	if img == null:
		return tex
	var out := Image.create(r.size.x, r.size.y, false, img.get_format())
	out.blit_rect(img, r, Vector2i.ZERO)
	return ImageTexture.create_from_image(out)

## A colour the sprite actually contains, for its name-plate.
##
## NOT the average and not the most common: averaging two palette colours lands on a third that is
## in neither, and the commonest pixel in a landmark tile is usually its darkest shading. So this
## takes the few colours the art is mostly made of and picks the BRIGHTEST of those — a colour that
## is genuinely in the picture, and the one most likely to read against sky as well as ground.
func _plate_color(tex: Texture2D, fallback: Color) -> Color:
	var img := tex.get_image()
	if img == null:
		return fallback
	var counts := {}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var px_c := img.get_pixel(x, y)
			if px_c.a < 0.5:
				continue
			var k := px_c.to_rgba32()
			counts[k] = int(counts.get(k, 0)) + 1
	if counts.is_empty():
		return fallback
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var best := fallback
	var best_l := -1.0
	for i in range(mini(4, keys.size())):
		var col := Color(Color.hex(int(keys[i])), 1.0)
		var l := col.get_luminance()
		if l > best_l:
			best_l = l
			best = col
	return best
