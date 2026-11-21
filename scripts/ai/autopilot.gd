class_name Autopilot
extends RefCounted
## Assisted movement orders (GDD 4.3 Movement: drive toward, go to, orbit around). They produce a
## control command that the ship's assisted flight controller executes.


## Acceleration (m/s2) the ship can really produce along a world direction: each thrust axis
## (fwd/back/right/left/up/down + RCS) limits it, so braking is judged with the weak reverse thrusters.
static func accel_along(ship: Ship, dir_world: Vector3) -> float:
	var d := ship.global_transform.basis.inverse() * dir_world.normalized()
	var best := INF
	var axes: Array = [[d.x, 2, 3], [d.y, 4, 5], [-d.z, 0, 1]]
	for ax in axes:
		var comp: float = ax[0]
		if absf(comp) < 0.02:
			continue
		var cap := float(ship.caps[ax[1] if comp > 0.0 else ax[2]]) + ship.rcs_cap
		best = minf(best, cap / absf(comp))
	return maxf(best / maxf(ship.mass, 0.001), 0.3) if best < INF else 0.3


static func drive_toward(ship: Ship, dest: Vector3, speed: float, stop_dist := 0.0) -> Dictionary:
	var to := dest - ship.global_position
	var dist := to.length()
	if dist < 0.01:
		return hold(ship)
	var a := accel_along(ship, -to) * 0.6
	var v := minf(speed, sqrt(2.0 * a * maxf(dist - stop_dist, 0.0)))
	return {"auto": true, "v_target": to.normalized() * v, "face": to.normalized(), "speed_limit": speed}


static func orbit(ship: Ship, center: Vector3, radius: float, speed: float) -> Dictionary:
	var rel := ship.global_position - center
	var r := maxf(rel.length(), 0.01)
	var radial := rel / r
	var tangent := radial.cross(Vector3.UP)
	if tangent.length() < 0.01:
		tangent = radial.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var a := maxf(ship.max_accel() * 0.5, 0.5)
	var sp := minf(speed, sqrt(a * radius))
	var v := tangent * sp + radial * clampf((radius - r) * 0.6, -sp, sp)
	return {"auto": true, "v_target": v, "face": (-radial).normalized()}


static func hold(ship: Ship) -> Dictionary:
	return {"auto": true, "v_target": Vector3.ZERO}


static func face(ship: Ship, point: Vector3) -> Dictionary:
	return {"auto": true, "v_target": ship.linear_velocity, "face": (point - ship.global_position).normalized()}


## Fly to a fixed point and stop on it (waypoint order). Slows down along sqrt(2*a*d) so it arrives at rest.
static func go_to(ship: Ship, dest: Vector3, speed: float) -> Dictionary:
	return drive_toward(ship, dest, speed, 0.0)
