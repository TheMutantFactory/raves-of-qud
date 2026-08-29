extends RefCounted

## THE DRONE RIG — where the flying camera is, what it is pointed at, and the list of shots you
## can scrub between. Daniel: "a new camera mode called drone-cam ... The drone can be dragged to
## integer tiles (like a UI grid or something). There is also a camera-target, which can be moved
## in tiles as well ... the user can scroll through the various 'animation' points from the list."
##
## STATE HERE, GEOMETRY IN CameraRig, WIDGETS IN DronePanel. Everything in this file is a pure
## function over plain values, so the whole scrub/glide model can be tested with no viewport, no
## camera and no zone — which is the only reason the awkward cases below (an empty list, a
## one-point list, a scrub that lands exactly on a point) get tested at all.
##
## TILES ARE INTEGERS, THE GLIDE IS NOT. A point stores Vector3i because the user places it on a
## grid and a half-tile placement is not a thing they asked for. The glide between two points is
## continuous — the camera passes through the space between tiles — so it returns Vector3. Storing
## the glide's output back into a point is the one thing that would quietly round the rig.

## x and z are Qud cell coordinates; y is altitude in tiles above the ground plane.
## Qud's own y (north/south) is this vector's z, the same swap the renderer makes.
const GROUND := 0

## How far one scroll notch travels along the path, as a fraction of the gap between two points.
## Four notches per leg: enough that a leg reads as a move rather than a jump, few enough that
## crossing a ten-point list is not a wrist exercise.
const NOTCH := 0.25


## Snap a world position to the tile grid the drone lives on. The drag handler works in world
## units because that is what a viewport ray gives it; this is the only place that becomes a cell.
static func snap(world: Vector3) -> Vector3i:
	return Vector3i(int(roundf(world.x)), int(roundf(world.y)), int(roundf(world.z)))


## One scroll notch. `notches` is signed (wheel up is positive), `invert` is the panel's checkbox.
##
## CLAMPED, NOT WRAPPED. A list of shots is a path with two ends, not a carousel: scrolling past
## the last point and landing back at the first would read as the camera cutting, which is the one
## thing a glide exists to avoid.
static func scrub(t: float, notches: float, count: int, invert := false) -> float:
	if count <= 1:
		return 0.0
	var dir := -1.0 if invert else 1.0
	return clampf(t + notches * dir * NOTCH, 0.0, float(count - 1))


## Where the rig is at scrub position `t`. Returns {} for an empty list — the caller keeps whatever
## the drone was doing, because a camera that snaps to the origin the moment you delete your last
## point is worse than one that simply stops taking direction from the list.
static func at(points: Array, t: float) -> Dictionary:
	if points.is_empty():
		return {}
	var last := points.size() - 1
	var u := clampf(t, 0.0, float(last))
	var i := int(floorf(u))
	var a: Dictionary = points[i]
	if i >= last:
		return _pose(a, a, 0.0)
	# `f` is the position WITHIN this leg, not within the list — so a ten-point path and a
	# two-point path both travel one leg per unit of t, and adding a point does not restretch
	# every leg before it.
	return _pose(a, points[i + 1], u - float(i))


static func _pose(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	return {
		"drone": Vector3(a["drone"]).lerp(Vector3(b["drone"]), f),
		"target": Vector3(a["target"]).lerp(Vector3(b["target"]), f),
		"zoom": lerpf(float(a.get("zoom", 1.0)), float(b.get("zoom", 1.0)), f),
	}


## A new shot, taken from wherever the rig is standing. The name is what the list shows; it is
## generated rather than left blank because an unnamed row in a list of eight is not a shot, it is
## a number the user has to decode from the picture.
static func make_point(drone: Vector3i, target: Vector3i, zoom: float, n: int) -> Dictionary:
	return {"name": "shot %d" % (n + 1), "drone": drone, "target": target, "zoom": zoom}


## Drag-reorder. Returns a NEW array — the panel rebuilds its rows from the result, and mutating
## in place while a row is mid-drag reorders the thing the mouse is holding.
static func reorder(points: Array, from_i: int, to_i: int) -> Array:
	var out := points.duplicate()
	if from_i < 0 or from_i >= out.size() or to_i < 0 or to_i >= out.size() or from_i == to_i:
		return out
	var it: Variant = out[from_i]
	out.remove_at(from_i)
	out.insert(to_i, it)
	return out


## Delete, and say where the scrub should land afterwards.
##
## THE SCRUB HAS TO MOVE, and this is the whole reason removal is not a one-liner at the call site:
## t indexes the list, so deleting a point ahead of the playhead leaves t pointing at a different
## shot than the one the user was looking at, and deleting the last point can leave t past the end.
static func remove(points: Array, i: int, t: float) -> Dictionary:
	var out := points.duplicate()
	if i < 0 or i >= out.size():
		return {"points": out, "t": t}
	out.remove_at(i)
	var nt := t
	if out.is_empty():
		nt = 0.0
	elif float(i) < t:
		nt = t - 1.0        # the playhead kept its shot; its index moved down one
	return {"points": out, "t": clampf(nt, 0.0, float(maxi(out.size() - 1, 0)))}
