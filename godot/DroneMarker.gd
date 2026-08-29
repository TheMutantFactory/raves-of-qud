extends Node3D

## THE DRONE, drawn. "The Drone control is a side view of the player and the drone" — and a drone
## is a camera position, which renders as nothing at all, so without this the control pane shows a
## landscape and no drone to move.
##
## AMBER, not the look cursor's cyan (#40a4b9): both can be on screen at once, and two cool markers
## a tile apart read as one marker.

## Its own layer so the DRONECAM can drop it — a camera sits inside this thing, and the inside of
## an octahedron fills the pane.
##
## MOVED onto the layer, never OR'd in. ZoneRenderer._tag_layer records why: a node left on layer 1
## as well is still drawn by a camera culling this bit, so the cull does nothing and only LOOKS
## right while the marker is off screen. Here it never is.
const BODY_LAYER := 1 << 10
const AMBER := Color8(0xF0, 0xC0, 0x60)
const R := 0.35

var _body: MeshInstance3D


func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.mesh = _diamond(R)
	var m := StandardMaterial3D.new()
	# Unshaded: a marker that dims with the sun is one you cannot place after dusk. Depth-tested
	# though — Daniel on the look cursor: "It's showing above the Dromad ... it's over everything?"
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = AMBER
	m.no_depth_test = false
	_body.material_override = m
	_body.layers = BODY_LAYER
	add_child(_body)
	visible = false


func place(p: Vector3) -> void:
	if _body != null:
		_body.position = p


## An octahedron: no flat side to vanish at a glance, and the control pane looks at it edge-on by
## construction.
static func _diamond(r: float) -> ArrayMesh:
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


func set_shown(on: bool) -> void:
	visible = on
