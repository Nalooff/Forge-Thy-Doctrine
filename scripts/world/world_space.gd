class_name WorldSpace
extends Node
## Floating origin (large-world coordinates).
##
## Everything in the scene keeps small coordinates. `origin` is the absolute position (64-bit) of the scene's (0, 0, 0).
## When the focus (the player's ship) gets farther than REBASE_DIST from the scene origin, the whole world is moved
## back by the same vector in one go: ship bodies through the physics server, every other top-level 3D node by its
## position, and anything that remembers a point (waypoints, orders, the camera rig) through the `shifted` signal.
## Relative geometry, velocities and contacts are untouched, so nothing can tell it happened, but float32 never
## has to represent a big number. Ships far from the focus are not simulated at all (see FarSim).

signal shifted(delta: Vector3)

const REBASE_DIST := 4000.0

var origin := Vec3D.make(0.0, 0.0, 0.0)
var root: Node
var rebases := 0
var total_shift := 0.0


func to_abs(local: Vector3) -> Vec3D:
	return origin.plus(local)


func to_local(a: Vec3D) -> Vector3:
	return a.minus(origin)


## Absolute position of a ship, awake (scene position + origin) or dormant (kept in 64 bits).
func abs_of(s: Ship) -> Vec3D:
	if s.dormant:
		return s.far_abs
	return to_abs(s.global_position)


func abs_distance(a: Ship, b: Ship) -> float:
	return abs_of(a).dist(abs_of(b))


## Move the world so that the scene point `delta` becomes the new origin.
func shift(delta: Vector3) -> void:
	origin.add_in_place(delta)
	rebases += 1
	total_shift += delta.length()
	if root != null:
		for c in root.get_children():
			if c is Ship:
				var sh := c as Ship
				if sh.dormant:
					continue
				var t := sh.global_transform
				sh.global_transform = Transform3D(t.basis, t.origin - delta)   # takes effect at once for readers, and in the physics server
			elif c is Node3D and not c.is_in_group("no_shift"):
				(c as Node3D).global_position -= delta
	shifted.emit(delta)


## Call every physics frame with the focus position. True when the world was recentred.
func check_rebase(focus_pos: Vector3) -> bool:
	if focus_pos.length() > REBASE_DIST:
		shift(focus_pos)
		return true
	return false


## How far (m) a position is outside the cube of the map, 0 inside. The map is centred on the absolute origin.
static func outside_amount(a: Vec3D, half_extent: float) -> float:
	return maxf(0.0, maxf(absf(a.x), maxf(absf(a.y), absf(a.z))) - half_extent)
