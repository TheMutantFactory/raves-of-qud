extends Node

## QUD'S TARGET PICKER, MIRRORED — the reticle you aim a ray, a burst or a thrown rock with.
##
## Daniel: "I'm trying to use flaming ray, but the Raves just tries to Chat with the Dawngliders."
## Firing the ability worked; what followed did not. Qud went into PickTarget and waited, and Raves
## showed nothing at all — no cursor, no prompt, and no snapshots either, because the picker SPINS ON
## THE TURN THREAD (RenderMapToBuffer / DrawBuffer / kbhit, round and round) and the turn thread is
## what publishes them. The viewer looked frozen at exactly the moment it was being asked a question,
## and a click went through the ordinary verb table and chatted at a hostile.
##
## WHAT THIS DRAWS. A reticle box on the cell under the pointer and a line of pips from the shooter
## to it, so the shot's path is visible before it is taken, plus Qud's own prompt line above the
## playfield ("Flaming Ray | Space-select | unlock (F1)").
##
## WHAT IT DOES NOT DO: track Qud's cursor. Qud keeps that in a local inside ShowPicker's loop, out
## of reach of any mod, and asking for it back would be a second source of truth to keep in step.
## Raves owns the cursor instead and TELLS Qud where it is at the moment of the shot — which is the
## same direction the information already flows for a click-to-travel.
##
## THE LINE IS BRESENHAM, and it is ours rather than Qud's. Qud draws its own with Zone.Line into a
## text buffer we do not read; this is a preview, and a preview that disagreed with the shot by a
## cell at long range would be worse than none. It is deliberately drawn as a dotted PATH rather than
## a beam: it promises "this is the way I am pointing", not "these are the cells that will burn".

## The stack of pips, and the box. Warm because every other marker in the playfield is cool: the
## mouse-assist box is pale green and the look cursor gold, and a third cool outline would read as
## one of those rather than as a weapon.
const BOX_COLOR := Color(1.0, 0.42, 0.28, 0.95)
const LINE_COLOR := Color(1.0, 0.55, 0.30, 0.75)
const BOX_LIFT := 0.014         # just above the mouse-assist box, so they do not z-fight when both show
const PIP := 0.16               # a pip's half-width, in cells
const PIP_Y := 0.30             # pips float at knee height, clear of floor art

var active := false
var mode := ""
var text := ""
var _from := Vector2i.ZERO      # the shooter's cell, from the mod
var _cell := Vector2i(-9999, -9999)
var _box: MeshInstance3D
var _line: MeshInstance3D
var _renderer: Node3D
var _label: Label
var _hud: CanvasLayer
var _hole := Rect2()

signal answered(x: int, y: int, cancel: bool)


func setup(renderer: Node3D) -> void:
	_renderer = renderer
	var host: Node = renderer if renderer != null else self
	_box = MeshInstance3D.new()
	_box.mesh = _box_mesh()
	_box.material_override = _line_mat(BOX_COLOR)
	_box.visible = false
	host.add_child(_box)
	_line = MeshInstance3D.new()
	_line.material_override = _line_mat(LINE_COLOR)
	_line.visible = false
	host.add_child(_line)
	_hud = CanvasLayer.new()
	_hud.name = "TargetPrompt"
	_hud.layer = 1
	add_child(_hud)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", load("res://fonts/SourceCodePro-Bold.ttf"))
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", BOX_COLOR)
	_label.visible = false
	_hud.add_child(_label)

func set_play_hole(r: Rect2) -> void:
	_hole = r
	_place_label()

## The mod's picktarget frame.
func set_state(d: Dictionary) -> void:
	var was := active
	active = bool(d.get("active", false))
	mode = String(d.get("mode", ""))
	text = _strip(String(d.get("text", "")))
	_from = Vector2i(int(d.get("px", 0)), int(d.get("py", 0)))
	if not active:
		_cell = Vector2i(-9999, -9999)
		_box.visible = false
		_line.visible = false
		_label.visible = false
		return
	if not was:
		# Opens on the shooter, so there is always a valid answer even if the pointer never moves.
		_cell = _from
	_label.text = text
	_label.visible = text != ""
	_place_label()
	_redraw()

## The pointer moved over the playfield. `cell` is null when it is not over it at all.
func hover(cell: Variant) -> void:
	if not active or cell == null:
		return
	var c := Vector2i(cell.x, cell.y)
	if c == _cell:
		return
	_cell = c
	_redraw()

## A click in the playfield while the picker is up. Always consumed — see Main.
func click(cell: Variant, cancel := false) -> bool:
	if not active:
		return false
	if cancel:
		answered.emit(_cell.x, _cell.y, true)
		return true
	if cell != null:
		_cell = Vector2i(cell.x, cell.y)
	answered.emit(_cell.x, _cell.y, false)
	return true

## The cells this shot would travel, shooter excluded — what the preview was promising. Handed to
## the renderer at confirm-time so the flames land on exactly the path the player was shown; a
## second derivation, however careful, is a second thing to keep in step with the pips on screen.
func path() -> Array:
	var out: Array = []
	for c in _bresenham(_from, _cell):
		if c != _from:
			out.append(c)
	return out

func _redraw() -> void:
	_box.position = Vector3(float(_cell.x), 0.0, float(_cell.y))
	_box.visible = true
	_line.mesh = _line_mesh()
	_line.visible = true

## Qud's prompt, centred over the top of the playfield the way Qud puts it over its own map.
func _place_label() -> void:
	if _label == null:
		return
	_label.reset_size()
	var sz := _label.get_minimum_size()
	var r := _hole if _hole.size.x > 1.0 else Rect2(Vector2.ZERO, Vector2(get_viewport().size))
	_label.position = Vector2(r.position.x + (r.size.x - sz.x) * 0.5, r.position.y + 8.0)

## Qud's markup ("&W" colour codes and "{{tag|body}}" spans) is for its own text console; the plate
## is a Godot Label. Strip rather than translate: the prompt is one short line and its MEANING is
## all in the words.
##
## THE TAGS NEST, which a first pass here did not allow for and the screen reported immediately.
## Off the wire, the missile weapon's prompt is
##     {{W|{{hotkey|Space}}}}-select | unlock ({{hotkey|F1}}) | Fire Missile Weapon
## -- a colour span wrapped around a hotkey span. Scanning for the first "}}" closes the INNER one,
## so the outer braces survive and "{{hotkey|Space}}-select" is what the player reads. A depth
## counter is the whole fix: push on "{{", pop on "}}", and drop characters only while they are
## still part of a tag's NAME, which is everything up to that depth's first "|".
func _strip(s: String) -> String:
	var out := ""
	var naming: Array = []      # one entry per open tag: still inside its name?
	var i := 0
	while i < s.length():
		# Colour codes are two characters and carry no text of their own.
		if s[i] == "&" and i + 1 < s.length():
			i += 2
			continue
		if s.substr(i, 2) == "{{":
			naming.push_back(true)
			i += 2
			continue
		if s.substr(i, 2) == "}}" and not naming.is_empty():
			naming.pop_back()
			i += 2
			continue
		if not naming.is_empty() and naming[naming.size() - 1]:
			# Inside a tag name: the "|" ends it, and everything before it is markup.
			if s[i] == "|":
				naming[naming.size() - 1] = false
			i += 1
			continue
		out += s[i]
		i += 1
	return out

func _box_mesh() -> ArrayMesh:
	var y := ZoneRenderer.FLOOR_Y + BOX_LIFT
	var h := 0.5
	var c := [Vector3(-h, y, -h), Vector3(h, y, -h), Vector3(h, y, h), Vector3(-h, y, h)]
	var pts := PackedVector3Array()
	for i in 4:
		pts.append(c[i])
		pts.append(c[(i + 1) % 4])
	return _mesh_from(pts)

## A pip on every cell the shot passes through, shooter and target excluded — the shooter is not
## in the way of itself, and the target already has the box around it.
func _line_mesh() -> ArrayMesh:
	var pts := PackedVector3Array()
	var y := ZoneRenderer.FLOOR_Y + PIP_Y
	for c in _bresenham(_from, _cell):
		if c == _from or c == _cell:
			continue
		var x := float(c.x)
		var z := float(c.y)
		pts.append(Vector3(x - PIP, y, z)); pts.append(Vector3(x + PIP, y, z))
		pts.append(Vector3(x, y, z - PIP)); pts.append(Vector3(x, y, z + PIP))
	return _mesh_from(pts)

func _mesh_from(pts: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if pts.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return mesh

## Integer line, the same shape Qud walks a shot along.
func _bresenham(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var x := a.x
	var y := a.y
	# A hard cap, because this runs off a cursor: a bad `from` (a stale zone, a picker that opened
	# before the player's cell arrived) must not spin the frame away.
	for _i in range(400):
		out.append(Vector2i(x, y))
		if x == b.x and y == b.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return out

func _line_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true     # you are aiming at it; the scenery does not get to hide the reticle
	m.render_priority = 4      # above the mouse-assist marker, which is priority 3
	return m
