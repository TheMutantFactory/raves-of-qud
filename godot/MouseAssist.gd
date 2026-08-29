extends Node

## MOUSE ASSIST — the cursor says what a click will do before you make it.
##
## Daniel: "Let's create a mouse-assist mode where the target tile is shown with shoes/boots icon to
## show that you can walk there. If you're on a person, open the chat window. If it's over an object,
## show an interaction icon. Does that make sense? If you're over stairs, it will switch to a down
## arrow."
##
## Qud is a keyboard game with a mouse bolted on, and Raves inherited the awkward half of that: a
## left click walked, a right click interacted, and the only way to find out which one a tile wanted
## was to try. The verb is knowable BEFORE the click — everything it depends on is already in the
## snapshot — so the cursor carries it.
##
## THE ICONS ARE QUD'S WHERE QUD HAS THEM. Boots are its own leather boots; the stairs arrows are the
## nav strip's own Up/Down buttons, which are the arrows the game already taught you. Only the two it
## has no art for — a speech bubble and a hand — are drawn here, and they are drawn rather than
## borrowed because a magnifier or a star would be a different word.
##
## WHAT THE VERB IS DERIVED FROM. Stairs and walls come off the tile the way the renderer reads them;
## "person" is the mod's `talks`, which asks Qud whether the thing has a ConversationScript, because
## a cave spider and a watervine farmer are both IsCreature and only one of them will answer.

signal verb_changed(verb: String)

## IN THE TILE, AT TILE SCALE. Daniel: "The sprite is too big. Let's draw a box outline of the
## selected tile and put the sprite as a billboard in that tile."
##
## Two presentations came before this and each said the wrong thing. A 2D marker floating above the
## tile read as DISTANCE in a perspective view — "it looks like you're walking to the cell behind".
## A hardware cursor at 32x48 was simply a large cursor, and it lived in screen space where the
## thing it describes lives in the world.
##
## A box on the ground says WHICH TILE with no ambiguity at all, because it is drawn on that tile;
## the sprite stands inside it at the size everything else in that cell is drawn at, so it reads as
## a thing in the world rather than an annotation over it.
const BOX_COLOR := Color(0.72, 0.84, 0.81, 0.85)
const BOX_LIFT := 0.012        # clear of the floor quads, under everything that stands on them
const SPRITE_PX := 0.9         # a hair under a cell: unmistakably inside the box it sits in
const SPRITE_Y := 0.55         # standing in the tile, not lying on it

var _box: MeshInstance3D       # the footprint outline, parented under the renderer
var _mark: Sprite3D            # the verb, standing in the tile
var _renderer: Node3D
var _tiles: RefCounted
var _cells := {}               # "x,y" -> Array of objects, from the live snapshot
var _verb := ""
var _cell := Vector2i(-9999, -9999)
var _icons := {}               # verb -> Texture2D
var tiles_dir := ""

func _ready() -> void:
	_tiles = load("res://QudTiles.gd").new()

## PARENTED UNDER THE RENDERER, the way the inspector's own marker is: that is what makes the box
## inherit the z-stretch in top-down and stay square with the cells it is drawn over.
func setup(renderer: Node3D) -> void:
	_renderer = renderer
	var host: Node = renderer if renderer != null else self
	_box = MeshInstance3D.new()
	_box.mesh = _box_mesh()
	_box.material_override = _line_material()
	_box.visible = false
	host.add_child(_box)
	_mark = Sprite3D.new()
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mark.shaded = false
	_mark.no_depth_test = true      # a hint about a tile you can see is not itself hidden by it
	_mark.render_priority = 3
	_mark.visible = false
	host.add_child(_mark)

## ON in user mode, never in parity mode: Qud's cursor says nothing, and 1:1 says what Qud says.
func enabled() -> bool:
	return not Settings.qud_shape("mouseassist")

## The live zone's cells, indexed for lookup. Called each snapshot.
func set_snapshot(data: Dictionary) -> void:
	_tiles.tiles_dir = String(data.get("tilesDir", _tiles.tiles_dir))
	tiles_dir = _tiles.tiles_dir
	var idx := {}
	for c in data.get("cells", []):
		idx["%d,%d" % [int(c.get("x", 0)), int(c.get("y", 0))]] = c.get("objs", [])
	_cells = idx

## The pointer moved (or the cell under it changed). `cell` is null when the pointer is not over the
## playfield at all — chrome, a modal, off the hole — and the icon goes away with it.
## `at` is where the TILE lands on screen, not where the pointer is.
func hover(at: Vector2, cell: Variant) -> void:
	if not enabled() or cell == null:
		_clear()
		return
	var c := Vector2i(cell.x, cell.y)
	var v := verb_at(c)
	if v != _verb or c != _cell:
		_cell = c
		_verb = v
		verb_changed.emit(v)
	if _box == null:
		return
	var show: bool = v != ""
	_box.position = Vector3(float(c.x), 0.0, float(c.y))
	_box.visible = show
	_mark.position = Vector3(float(c.x), SPRITE_Y, float(c.y))
	_mark.visible = show
	if show:
		var tex := _icon_for(v)
		_mark.texture = tex
		# Scaled to the CELL, not to the art: the boots tile is 16x24 and the hand 16x18, and a
		# shared pixel_size would draw them at two different heights in the same box.
		if tex != null and tex.get_height() > 0:
			_mark.pixel_size = SPRITE_PX / float(tex.get_height())

func _clear() -> void:
	if _box != null:
		_box.visible = false
	if _mark != null:
		_mark.visible = false
	if _verb != "":
		_verb = ""
		verb_changed.emit("")

func verb() -> String:
	return _verb

## What a click on this cell would do.
##
## THE WHOLE CELL IS READ BEFORE ANYTHING IS DECIDED. The first version returned on the first object
## that matched, which quietly made the answer depend on the order the mod happened to list them in
## — a farmer standing on a staircase came back "talk" or "down" according to nothing. The verb test
## found it on the case that has both.
##
## The order below is a claim about what a click is FOR, not about what is topmost:
##   talk   a person is the most specific thing a cell can hold, and one standing on the stairs is
##          still someone to speak to — you were not going to walk through them anyway.
##   stairs the reason you came, when nobody is standing in the way.
##   use    anything else that is not scenery.
##   wall   no verb at all: not a destination, not a thing to poke.
##   walk   what is left when nothing else claims the cell.
func verb_at(c: Vector2i) -> String:
	var objs: Array = _cells.get("%d,%d" % [c.x, c.y], [])
	if objs.is_empty():
		return ""                  # never seen: no floor, no verb
	var talks := false
	var stairs := ""
	var thing := false
	var solid := false
	for o in objs:
		var tile := String(o.get("tile", "")).to_lower()
		if tile.contains("stairsdown"):
			stairs = "down"
		elif tile.contains("stairsup"):
			stairs = "up"
		if bool(o.get("talks", false)):
			talks = true
		elif bool(o.get("wall", false)) or bool(o.get("occluding", false)):
			solid = true
		elif not bool(o.get("ground", false)):
			thing = true
	if talks:
		return "talk"
	if stairs != "":
		return stairs
	if thing:
		return "use"
	return "" if solid else "walk"

func _icon_for(v: String) -> Texture2D:
	if _icons.has(v):
		return _icons[v]
	var tex: Texture2D = null
	match v:
		"walk":
			# Qud's own leather boots, recoloured to the cursor's pale — the game's word for "feet".
			tex = _tiles.texture("Items/sw_leather_boots.bmp", Color8(0xb1, 0xc9, 0xc3), Color8(0x77, 0xbf, 0xcf))
		"down":
			tex = _title_png("nav/DownButton__Image.png")
		"up":
			tex = _title_png("nav/UpButton__Image.png")
		"talk":
			tex = _speech_tex()
		"use":
			tex = _look_tex()
	if tex != null:
		_icons[v] = tex
	return tex

## The footprint outline: a square line loop just clear of the floor, in cell-local space so the
## instance can simply be moved to the cell.
func _box_mesh() -> ArrayMesh:
	var y := ZoneRenderer.FLOOR_Y + BOX_LIFT
	var h := 0.5
	var c := [Vector3(-h, y, -h), Vector3(h, y, -h), Vector3(h, y, h), Vector3(-h, y, h)]
	var pts := PackedVector3Array()
	for i in 4:
		pts.append(c[i])
		pts.append(c[(i + 1) % 4])
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return mesh

func _line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = false
	m.albedo_color = BOX_COLOR
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# DEPTH-TESTED, because it is a mark ON THE FLOOR. Daniel: "It's showing above the Dromad, which
	# means it's not on the floor it's over everything?" — exactly right. no_depth_test drew the
	# outline over the merchant standing on the tile and over every wall between, so it read as a
	# decal floating in front of the scene rather than a square painted on the ground.
	m.no_depth_test = false
	m.render_priority = 3
	return m

func _title_png(fname: String) -> Texture2D:
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

## A speech bubble: rounded box, three dots, a tail down-left. Drawn because Qud ships no such icon,
## and because the two candidates it does ship — a magnifier, a star — already mean other things.
func _speech_tex() -> Texture2D:
	var w := 18
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color8(0x77, 0xbf, 0xcf)
	for y in h:
		for x in w:
			var in_box: bool = x >= 1 and x <= 16 and y >= 1 and y <= 10
			var corner: bool = (x <= 2 or x >= 15) and (y <= 2 or y >= 9)
			var edge: bool = in_box and not corner and (x <= 2 or x >= 15 or y <= 2 or y >= 9)
			var tail: bool = y >= 10 and y <= 14 and x >= 4 and x <= (8 - (y - 10))
			if edge or tail:
				img.set_pixel(x, y, ink)
	for d in 3:                                    # the three dots that make it a conversation
		for dx in 2:
			for dy in 2:
				img.set_pixel(4 + d * 4 + dx, 5 + dy, ink)
	return ImageTexture.create_from_image(img)

## A hand: palm, four fingers, a thumb. The conventional "you can use this", at a size where a
## realistic one would be mud.
## THE INTERACTION ICON: a Noun Project eye, tinted. Daniel supplied the SVG and the colour.
##
## It replaces a hand drawn here pixel by pixel (below, kept as the fallback). Two notes:
##
## FIRST ART IN THE REPO. Every other icon Raves shows is either built in code or pulled from Qud's
## own exported tiles at runtime; this is the first bitmap the project ships. It is imported at
## svg/scale 0.053 rather than 1.0 — the source is 1200pt, which Godot renders at 1600px, and a
## cursor does not need a 2.5-megapixel texture.
##
## TINTED INTO THE TEXTURE, not by modulating the sprite. `_mark` carries every verb's icon in turn,
## so a modulate would recolour the boots and the stairs arrows too.
const USE_TINT := Color8(0x40, 0xa4, 0xb9)

func _look_tex() -> Texture2D:
	var src: Texture2D = load("res://art/look.svg")
	if src == null:
		return _hand_tex()
	var img: Image = src.get_image()
	if img == null:
		return _hand_tex()
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	# The glyph is solid white, so the tint is a straight replace against its own alpha — no
	# multiply needed, and the antialiased edge keeps its coverage.
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				img.set_pixel(x, y, Color(USE_TINT.r, USE_TINT.g, USE_TINT.b, a))
	return ImageTexture.create_from_image(img)

## The hand this replaced, kept as the fallback for a build whose art did not import.
func _hand_tex() -> Texture2D:
	var w := 16
	var h := 18
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color8(0xcf, 0xc0, 0x41)
	var tops := [6, 3, 4, 6]                       # index finger stands proudest
	for fi in 4:
		var fx := 4 + fi * 3
		for y in range(tops[fi], 11):
			img.set_pixel(fx, y, ink)
			img.set_pixel(fx + 1, y, ink)
	for y in range(8, 12):                         # thumb, out to the left
		img.set_pixel(1 + (y - 8) / 2, y, ink)
		img.set_pixel(2 + (y - 8) / 2, y, ink)
	for y in range(11, 17):                        # palm
		for x in range(3, 13):
			img.set_pixel(x, y, ink)
	return ImageTexture.create_from_image(img)
