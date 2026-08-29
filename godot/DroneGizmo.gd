extends Node3D

## THE DRONE AND ITS TARGET, drawn. Without these the rig view shows a landscape and nothing to
## grab: the drone is a camera position, which renders as nothing at all, and "drag the drone" has
## no subject.
##
## AMBER, NOT CYAN. The look cursor is #40a4b9 and it is on screen at the same time as this — the
## look tool is what flies the drone. Two cyan markers a tile apart is one marker as far as the eye
## is concerned, so the rig is warm and the cursor stays cool.

## Its own layer so the drone's OWN camera can drop the drone. A camera standing inside its own
## marker sees the inside of a box, which reads as a broken pane.
##
## MOVED onto this layer, never OR'd in — the lesson ZoneRenderer._tag_layer records in full: a
## node left on layer 1 as well is still drawn by a camera that culls this bit, so the cull does
## nothing and the mechanism only LOOKS right for as long as the marker happens to be out of frame.
const BODY_LAYER := 1 << 10

const AMBER := Color8(0xF0, 0xC0, 0x60)
const AMBER_DIM := Color8(0xB8, 0x8E, 0x3C)
const BODY_R := 0.35          # the drone's little body, in cells
const TARGET_R := 0.5         # the ground ring: exactly one cell across, so it reads as a cell

var _body: MeshInstance3D
var _target: MeshInstance3D
var _aim: MeshInstance3D


func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.mesh = _diamond_mesh(BODY_R)
	_body.material_override = _mat(AMBER)
	# THE ONE NODE THAT MOVES LAYER. Everything else stays on the default so every other pane —
	# and the gameplay view — draws the whole rig.
	_body.layers = BODY_LAYER
	add_child(_body)

	_target = MeshInstance3D.new()
	_target.mesh = _target_mesh(TARGET_R)
	_target.material_override = _mat(AMBER)
	add_child(_target)

	_aim = MeshInstance3D.new()
	_aim.mesh = ArrayMesh.new()
	_aim.material_override = _mat(AMBER_DIM)
	add_child(_aim)
	visible = false


## Put the rig where it is. Called every frame the gizmo is up — the drone glides between shots,
## so this is not a per-turn placement.
func place(drone: Vector3, target: Vector3) -> void:
	if _body == null:
		return
	_body.position = drone
	_target.position = target
	_rebuild_aim(drone, target)


## Shown while the camera selector is open or a drone camera is live, and hidden otherwise: it is
## a rig tool, and a gold diamond hanging over the world during ordinary play is scenery.
func set_shown(on: bool) -> void:
	visible = on


## The line from the drone to what it is pointed at — the part that makes the pair read as one rig
## rather than as two unrelated markers.
func _rebuild_aim(a: Vector3, b: Vector3) -> void:
	var m := ArrayMesh.new()
	if a.distance_to(b) > 0.001:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, b - a])
		m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	_aim.mesh = m
	_aim.position = a


## An octahedron: eight faces, no flat side to disappear at a glance, and readable as a body from
## any angle — including the elevation, which looks at it edge-on by construction.
static func _diamond_mesh(r: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var top := Vector3(0, r, 0)
	var bot := Vector3(0, -r, 0)
	var ring := [Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
	for i in 4:
		var p: Vector3 = ring[i]
		var q: Vector3 = ring[(i + 1) % 4]
		v.append_array([top, p, q])
		v.append_array([bot, q, p])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## How far the target's pin stands up out of the floor.
const TARGET_PIN_H := 1.2

## A ground ring with a cross through it, one cell across, AND A PIN STANDING OUT OF IT.
##
## THE PIN IS WHY THIS IS NOT JUST A RING. The elevation view is level with the ground by
## construction, so a flat ring is seen exactly edge-on and draws as a two-pixel dash — in the one
## view whose entire job is showing you where the target is. CellInspector reached the same answer
## for the same reason ("a finder line so the selection stays findable ... at a shallow pitch").
##
## Lines rather than a filled quad: the target sits ON the floor, and a filled marker hides the
## tile you are aiming at.
static func _target_mesh(r: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var y := 0.02      # just off the floor, so it does not z-fight with the ground quad
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		var b := TAU * float(i + 1) / float(n)
		v.append(Vector3(r * cos(a), y, r * sin(a)))
		v.append(Vector3(r * cos(b), y, r * sin(b)))
	v.append_array([Vector3(-r, y, 0), Vector3(r, y, 0), Vector3(0, y, -r), Vector3(0, y, r)])
	v.append_array([Vector3(0, y, 0), Vector3(0, y + TARGET_PIN_H, 0)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


## Unshaded so the rig reads the same at night — it is a tool, not scenery, and a gizmo that dims
## with the sun is one you cannot place after dusk.
##
## DEPTH-TESTED, deliberately. Daniel on the look cursor: "It's showing above the Dromad, which
## means it's not on the floor it's over everything?" The same complaint applies here, so the drone
## goes behind what is in front of it — the cost is a drone hidden behind a hill in the elevation,
## which is honest about where it is.
static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = false
	return m
