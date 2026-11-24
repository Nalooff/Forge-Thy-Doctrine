class_name FarSim
extends RefCounted
## Ships far from the player are not worth a physics body: past SLEEP_DIST they become "dormant", a point with a
## 64-bit position and a velocity that keeps drifting (or heading for a goal), invisible and without collision.
## Inside WAKE_DIST they come back as a normal body at the right place. This is what lets a map be 1,000,000 km wide
## with 80 ships on it.

const SLEEP_DIST := 120000.0
const WAKE_DIST := 90000.0
const CRUISE := 400.0               # m/s a dormant ship travels at when it has a goal


static func sleep(s: Ship, ws: WorldSpace) -> void:
	if s.dormant:
		return
	s.far_abs = ws.to_abs(s.global_position)
	s.far_vel = s.linear_velocity
	s.dormant = true
	s.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	s.freeze = true
	s.visible = false
	s.collision_layer = 0
	s.collision_mask = 0


static func wake(s: Ship, ws: WorldSpace) -> void:
	if not s.dormant:
		return
	var p := ws.to_local(s.far_abs)
	s.dormant = false
	s.freeze = false
	s.visible = true
	s.collision_layer = 1
	s.collision_mask = 1
	s.global_transform = Transform3D(s.global_transform.basis, p)
	s.linear_velocity = s.far_vel


## Advance dormant ships by dt (they drift, or go to far_goal at CRUISE), wake the ones that came close and put the
## ones that are far to sleep. `can_sleep` lets the caller keep a ship awake (the player, a ship in a fight).
static func step(ships: Array, ws: WorldSpace, focus: Ship, dt: float, can_sleep: Callable) -> void:
	var fa := ws.abs_of(focus)
	for s in ships:
		var sh := s as Ship
		if sh == focus or not sh.alive:
			continue
		if sh.dormant:
			if sh.far_goal != null:
				var to_goal: Vector3 = (sh.far_goal as Vec3D).minus(sh.far_abs)
				if to_goal.length() > 50.0:
					sh.far_vel = to_goal.normalized() * CRUISE
				else:
					sh.far_vel = Vector3.ZERO
			sh.far_abs.add_in_place(sh.far_vel * dt)
			if sh.far_abs.dist(fa) < WAKE_DIST:
				wake(sh, ws)
		else:
			var d := ws.abs_of(sh).dist(fa)
			if d > SLEEP_DIST and (not can_sleep.is_valid() or can_sleep.call(sh)):
				sleep(sh, ws)
