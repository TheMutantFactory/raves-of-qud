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

const ICON_PX := 22.0
const ICON_DY := 14.0          # below-right of the pointer, clear of the hotspot

var _hud: CanvasLayer
var _icon: TextureRect
var _tiles: RefCounted
var _cells := {}               # "x,y" -> Array of objects, from the live snapshot
var _verb := ""
var _cell := Vector2i(-9999, -9999)
var _icons := {}               # verb -> Texture2D
var tiles_dir := ""

func _ready() -> void:
	_tiles = load("res://QudTiles.gd").new()
	_hud = CanvasLayer.new()
	_hud.name = "MouseAssist"
	_hud.layer = 2               # over the 3D and the beacon plates, under the frame chrome
	add_child(_hud)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.visible = false
	_hud.add_child(_icon)

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
func hover(screen_pos: Vector2, cell: Variant) -> void:
	if not enabled() or cell == null:
		_clear()
		return
	var c := Vector2i(cell.x, cell.y)
	var v := verb_at(c)
	if v != _verb or c != _cell:
		_cell = c
		_verb = v
		if v != "":
			_icon.texture = _icon_for(v)
		verb_changed.emit(v)
	_icon.visible = v != ""
	if _icon.visible:
		_icon.size = Vector2(ICON_PX, ICON_PX)
		_icon.position = screen_pos + Vector2(ICON_DY, ICON_DY)

func _clear() -> void:
	if _icon != null:
		_icon.visible = false
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
			tex = _hand_tex()
	if tex != null:
		_icons[v] = tex
	return tex

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
