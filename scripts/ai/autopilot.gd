class_name Autopilot
extends RefCounted
## Assisted movement orders (GDD 4.3 Movement: drive toward, go to, orbit around). They produce a
## control command that the ship's assisted flight controller executes.


static func drive_toward(ship: Ship, dest: Vector3, speed: float, stop_dist := 0.0) -> Dictionary:
	var to := dest - ship.global_position
	var dist := to.length()
	if dist < 0.01:
		return hold(ship)
	var a := maxf(ship.max_accel() * 0.6, 0.5)
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
