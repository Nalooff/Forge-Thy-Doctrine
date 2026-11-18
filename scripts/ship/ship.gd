class_name Ship
extends RigidBody3D
## A live ship built from a blueprint: Newtonian flight (thrusters + RCS + gyro), power grid with
## priorities, barrels, module-HP damage with spatial penetration, and death rules (GDD 2, 4, 6).
##
## Control interface (set by the player controller or a bot every frame):
##   cmd.move   Vector3  x=strafe right, y=up, z=forward   (-1..1)
##   cmd.rot    Vector3  x=pitch up, y=yaw left, z=roll left (-1..1)
##   cmd.fire   bool;  cmd.aim_point Vector3 (world);  cmd.aim_target Ship (lead aiming)
##   cmd.brake  bool;  cmd.speed_limit float
##   cmd.auto   bool;  cmd.v_target Vector3 (world velocity);  cmd.face Vector3 (world direction)

signal module_destroyed(ship: Ship, mod: Dictionary)
signal died(ship: Ship, killer: Ship)
signal hit_report(ship: Ship, report: Dictionary)

const TEAM_COLORS := [Color(0.3, 0.6, 1.0), Color(1.0, 0.3, 0.3), Color(0.3, 1.0, 0.4), Color(1.0, 0.85, 0.2)]

var bp: Dictionary
var team := 0
var stats: Dictionary
var mods: Array = []
var by_id := {}
var hull_hp := 0.0
var hull_hp_max := 1.0
var alive := true
var wreck := false
var killer: Ship
var target: Ship
var cmd := {}
var assist := true
var switches := {"thrusters": true, "weapons": true, "radar": true, "gyro": true}
var power_supply := 0.0
var power_demand := 0.0
var power_frac := 1.0
var caps := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var rcs_cap := 0.0
var hull_mat: StandardMaterial3D
var hull_mi: MeshInstance3D
var is_player := false
var _ram_cd := 0.0
var _gyro_frac := 1.0
var _virt_gyro := {"demand": 0.0, "frac": 1.0, "prio": -1.0}
var _virt_rcs := {"demand": 0.0, "frac": 1.0, "prio": -1.0}

const DIR_SIGN := [-1, 1, 1, -1, 1, -1]


static func dir_index(axis: int, sgn: int) -> int:
	if axis == 2:
		return 0 if sgn < 0 else 1
	if axis == 0:
		return 2 if sgn > 0 else 3
	return 4 if sgn > 0 else 5


static func lead_point(origin: Vector3, speed: float, tpos: Vector3, tvel: Vector3, own_vel: Vector3) -> Vector3:
	if speed <= 0.0:
		return tpos
	var rel := tpos - origin
	var rv := tvel - own_vel
	var a := rv.dot(rv) - speed * speed
	var b := 2.0 * rel.dot(rv)
	var c := rel.dot(rel)
	var t := 0.0
	if absf(a) < 1e-4:
		t = -c / b if absf(b) > 1e-6 else 0.0
	else:
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			return tpos
		var s := sqrt(disc)
		var t1 := (-b - s) / (2.0 * a)
		var t2 := (-b + s) / (2.0 * a)
		t = minf(t1, t2) if (t1 > 0.0 and t2 > 0.0) else maxf(t1, t2)
	if t < 0.0 or t > 8.0:
		return tpos
	return tpos + rv * t


# ------------------------------------------------------------------ construction
func setup(blueprint: Dictionary, p_team: int) -> void:
	bp = blueprint.duplicate(true)
	team = p_team
	stats = ShipData.compute_stats(bp)
	name = String(bp["name"])
	collision_layer = 1
	collision_mask = 1
	mass = maxf(float(stats["mass"]), 0.1)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = stats["com"]
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	add_to_group("ships")
	hull_hp_max = maxf(float(stats["hull_hp"]), 1.0)
	hull_hp = hull_hp_max
	for pts in ShipData.hull_convex_parts(bp["rings"]):
		var cs := CollisionShape3D.new()
		var sh := ConvexPolygonShape3D.new()
		sh.points = pts
		cs.shape = sh
		add_child(cs)
	hull_mat = StandardMaterial3D.new()
	hull_mat.albedo_color = ShipData.col(bp["color"])
	hull_mat.metallic = 0.6
	hull_mat.roughness = 0.45
	hull_mi = MeshInstance3D.new()
	hull_mi.mesh = ShipData.build_hull_mesh(bp["rings"])
	hull_mi.material_override = hull_mat
	add_child(hull_mi)
	for m in bp["modules"]:
		_make_module(m)
	_refresh_caps()


func _make_module(m: Dictionary) -> void:
	var def: Dictionary = ShipData.MODULES[m["type"]]
	var ms := ShipData.module_stats(m)
	var rm := {
		"id": int(m["id"]), "type": String(m["type"]), "label": def["label"], "kind": def["kind"],
		"pos": ShipData.v3(m["pos"]), "size": ShipData.v3(m["size"]), "dir": int(m["dir"]),
		"hp": float(ms["hp"]), "max": float(ms["hp"]), "alive": true, "ms": ms,
		"demand": 0.0, "frac": 1.0, "prio": 0.0, "enabled": true, "throttle": 0.0,
		"box": ShipData.module_box(m), "node": null, "pivot": null, "flame": null, "mat": null,
		"cool": 0.0, "ammo": -1, "aim": ShipData.DIRS[int(m["dir"])], "ws": {}, "len": 0.0, "engine": -1, "ef": 1.0,
	}
	if m["type"] == "thruster":
		rm["engine"] = ShipData.thruster_engine(bp, int(m["id"]))
		rm["ef"] = ShipData.engine_factor(bp, int(rm["engine"])) if int(rm["engine"]) >= 0 else 0.0
	if m["type"] == "barrel":
		var ws := ShipData.weapon_stats(m)
		rm["ws"] = ws
		rm["ammo"] = int(ws["ammo"])
		rm["len"] = ShipData.barrel_dims(m).x
		var bays := ShipData.linked_ids(bp, int(m["id"]), "turret_bay")
		rm["bay"] = int(bays[0]) if not bays.is_empty() else -1
	by_id[int(m["id"])] = rm
	mods.append(rm)
	if def["kind"] != "external":
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ShipData.col(bp["accent"])
	mat.metallic = 0.4
	mat.roughness = 0.5
	rm["mat"] = mat
	var dv: Vector3 = ShipData.DIRS[int(m["dir"])]
	match m["type"]:
		"commander_post":
			mat.albedo_color = TEAM_COLORS[team % TEAM_COLORS.size()]
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 0.6
			rm["node"] = _box_node(rm["pos"], rm["size"], mat)
		"thruster":
			mat.albedo_color = Color(0.25, 0.25, 0.28)
			rm["node"] = _box_node(rm["pos"], rm["size"], mat)
			var half: float = (rm["size"] as Vector3)[ShipData.DIR_AXIS[int(m["dir"])]] * 0.5
			var fl := Node3D.new()
			var fm := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.height = 1.0
			cm.top_radius = 0.0
			cm.bottom_radius = minf((rm["size"] as Vector3).x, (rm["size"] as Vector3).y) * 0.4
			fm.mesh = cm
			fm.position = Vector3(0, 0.5, 0)
			var fmat := StandardMaterial3D.new()
			fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fmat.albedo_color = Color(1.0, 0.65, 0.25)
			fm.material_override = fmat
			fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fl.add_child(fm)
			fl.position = rm["pos"] - dv * half
			fl.basis = Basis(Quaternion(Vector3.UP, -dv))
			fl.scale = Vector3(1, 0.01, 1)
			add_child(fl)
			rm["flame"] = fl
		"barrel":
			var pivot := Node3D.new()
			pivot.position = rm["pos"]
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			var dims := ShipData.barrel_dims(m)
			cyl.height = dims.x
			cyl.top_radius = dims.y * 0.5
			cyl.bottom_radius = dims.y * 0.5
			mi.mesh = cyl
			mi.rotate_x(PI * 0.5)
			mat.albedo_color = Color(0.7, 0.72, 0.78)
			mi.material_override = mat
			pivot.add_child(mi)
			add_child(pivot)
			rm["pivot"] = pivot
			rm["node"] = pivot
			_aim_pivot(rm)


func _box_node(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _aim_pivot(rm: Dictionary) -> void:
	var a: Vector3 = rm["aim"]
	var up := Vector3.UP if absf(a.y) < 0.98 else Vector3.RIGHT
	(rm["pivot"] as Node3D).basis = Basis.looking_at(a, up)


# ------------------------------------------------------------------ queries
func mods_of(type: String) -> Array:
	var out: Array = []
	for m in mods:
		if m["type"] == type:
			out.append(m)
	return out


func module_online(m: Dictionary) -> bool:
	return alive and bool(m["alive"]) and bool(m["enabled"])


func forward() -> Vector3:
	return -global_transform.basis.z


func radar_range() -> float:
	if not switches["radar"]:
		return 400.0
	for m in mods_of("radar_room"):
		if m["alive"] and float(m["frac"]) > 0.2:
			return 6000.0
	return 400.0


func max_accel() -> float:
	return (float(caps[0]) + rcs_cap) / mass


func can_move() -> bool:
	return alive and (float(caps[0]) + float(caps[1]) + float(caps[2]) + float(caps[3]) + float(caps[4]) + float(caps[5])) > 0.0 and power_supply > 0.0


func ext_module_ray(p0w: Vector3, p1w: Vector3):
	var a := to_local(p0w)
	var b := to_local(p1w)
	var best = null
	var best_d := INF
	for m in mods:
		if not m["alive"] or m["kind"] != "external":
			continue
		var box: AABB = m["box"]
		var hit = box.intersects_segment(a, b)
		if hit != null:
			var d := a.distance_to(hit)
			if d < best_d:
				best_d = d
				best = hit
	return null if best == null else to_global(best)


func _refresh_caps() -> void:
	caps = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for m in mods:
		if m["type"] != "thruster" or not module_online(m) or not switches["thrusters"]:
			continue
		var eng: Dictionary = by_id.get(int(m["engine"]), {})
		if eng.is_empty() or not eng["alive"]:
			continue
		caps[int(m["dir"])] += float(m["ms"]["thrust"]) * float(m["ef"])
	var best := 0.0
	for c in caps:
		best = maxf(best, c)
	rcs_cap = best * ShipData.RCS_FRACTION


# ------------------------------------------------------------------ physics
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if wreck:
		return
	var dt := state.step
	var basis := state.transform.basis
	var inv := basis.inverse()
	var v_loc := inv * state.linear_velocity
	var w_loc := inv * state.angular_velocity
	_ram_cd = maxf(0.0, _ram_cd - dt)
	_refresh_caps()
	for m in mods:
		m["demand"] = float(m["ms"]["idle"]) if module_online(m) else 0.0
		if m["type"] == "radar_room" and not switches["radar"]:
			m["demand"] = 0.0
		m["throttle"] = 0.0
	_virt_rcs["demand"] = 0.0
	_virt_gyro["demand"] = 0.0
	var controlled := alive and not cmd.is_empty()
	var move: Vector3 = cmd.get("move", Vector3.ZERO) if controlled else Vector3.ZERO
	var rot: Vector3 = cmd.get("rot", Vector3.ZERO) if controlled else Vector3.ZERO
	var auto: bool = cmd.get("auto", false) and controlled
	var braking: bool = cmd.get("brake", false) and controlled
	var want := Vector3(move.x, move.y, -move.z)

	# ---- linear request (kN, local axes)
	var f_req := Vector3.ZERO
	var use_assist := assist or auto or braking
	if use_assist:
		var v_tgt := Vector3.ZERO
		if auto:
			v_tgt = inv * (cmd.get("v_target", Vector3.ZERO) as Vector3)
		elif not braking:
			v_tgt = want * float(cmd.get("speed_limit", 150.0))
		f_req = (v_tgt - v_loc) * 4.0 * mass
	else:
		f_req = want * 1e12
	var used := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var rcs_f := Vector3.ZERO
	for a in 3:
		var r: float = f_req[a]
		if absf(r) < 1e-6:
			continue
		var sgn := 1 if r > 0.0 else -1
		var d := dir_index(a, sgn)
		var wf := absf(r)
		var cap: float = caps[d]
		var thr := minf(wf, cap)
		var rc := minf(wf - thr, rcs_cap)
		if cap > 0.0:
			used[d] = thr / cap
		rcs_f[a] = rc * sgn
	var kn_to_mw := ShipData.THRUSTER_MW_PER_M3 / ShipData.THRUST_KN_PER_M3
	for m in mods:
		if m["type"] == "thruster" and module_online(m) and switches["thrusters"]:
			m["demand"] = float(m["ms"]["peak"]) * float(used[int(m["dir"])]) * float(m["ef"])
	_virt_rcs["demand"] = rcs_f.length() * kn_to_mw * 1.0

	# ---- angular request
	var alpha_max := float(stats["gyro"]) * (1.0 if switches["gyro"] else 0.0)
	var w_max := minf(1.6, sqrt(maxf(alpha_max, 0.01) * 2.0))
	var alpha_des := Vector3.ZERO
	if auto and cmd.has("face"):
		var f := forward()
		var face: Vector3 = cmd["face"]
		var ang := f.angle_to(face)
		var w_world := Vector3.ZERO
		if ang > 0.002:
			var axis := f.cross(face)
			if axis.length() < 1e-5:
				axis = basis.y
			w_world = axis.normalized() * minf(ang * 2.5, w_max)
		alpha_des = ((inv * w_world) - w_loc) * 6.0
	elif assist or auto or braking:
		alpha_des = ((rot * w_max) - w_loc) * 6.0
	else:
		alpha_des = rot * alpha_max
	if alpha_des.length() > alpha_max:
		alpha_des = alpha_des.normalized() * alpha_max
	var gyro_peak := 0.5 * sqrt(mass)
	_virt_gyro["demand"] = gyro_peak * (alpha_des.length() / maxf(alpha_max, 0.001)) if alpha_max > 0.0 else 0.0
	for m in mods:
		if m["type"] == "barrel" and module_online(m) and switches["weapons"] and controlled and cmd.get("fire", false):
			m["demand"] = float(m["ws"]["power"])

	# ---- power allocation (closest to a generator = highest priority)
	var supply := 0.0
	var gens: Array = []
	for m in mods_of("generator"):
		if module_online(m):
			supply += float(m["ms"]["out"])
			gens.append(m["pos"])
	for m in mods:
		var dmin := 0.0
		if not gens.is_empty():
			dmin = INF
			for g in gens:
				dmin = minf(dmin, (m["pos"] as Vector3).distance_to(g))
		m["prio"] = dmin
	var consumers: Array = []
	for m in mods:
		if float(m["demand"]) > 0.0:
			consumers.append(m)
	consumers.append(_virt_gyro)
	consumers.append(_virt_rcs)
	consumers.sort_custom(func(a, b): return float(a["prio"]) < float(b["prio"]))
	var remaining := supply
	var total_demand := 0.0
	for c in consumers:
		var dm: float = c["demand"]
		total_demand += dm
		var take := minf(dm, remaining)
		c["frac"] = (take / dm) if dm > 0.0 else 1.0
		remaining -= take
	power_supply = supply
	power_demand = total_demand
	power_frac = clampf(supply / total_demand, 0.0, 1.0) if total_demand > 0.0 else 1.0
	for m in mods:
		if float(m["demand"]) <= 0.0:
			m["frac"] = 1.0 if module_online(m) else 0.0

	# ---- apply forces
	var f_local := Vector3.ZERO
	for a in 3:
		var r: float = f_req[a]
		if absf(r) < 1e-6:
			continue
		var sgn := 1 if r > 0.0 else -1
		var d := dir_index(a, sgn)
		var total := 0.0
		for m in mods:
			if m["type"] == "thruster" and int(m["dir"]) == d and float(m["demand"]) > 0.0:
				total += float(m["ms"]["thrust"]) * float(m["ef"]) * float(used[d]) * float(m["frac"])
				m["throttle"] = float(used[d]) * float(m["frac"])
		total += absf(rcs_f[a]) * float(_virt_rcs["frac"])
		f_local[a] = total * sgn
	state.apply_central_force(basis * f_local)
	var inertia := state.inverse_inertia_tensor.inverse()
	_gyro_frac = float(_virt_gyro["frac"])
	state.apply_torque(inertia * (basis * alpha_des) * _gyro_frac)

	# ---- ramming: contact impulses damage the hull (GDD 6)
	if _ram_cd <= 0.0:
		for i in state.get_contact_count():
			var imp := state.get_contact_impulse(i).length()
			if imp > 40.0:
				_ram_cd = 0.25
				_damage_hull((imp - 40.0) * 0.6, null)
				Fx.burst(get_parent(), state.get_contact_local_position(i) + state.transform.origin * 0.0, 1.5, Color(1, 0.8, 0.4), 0.3)
				break


func _physics_process(delta: float) -> void:
	if wreck:
		return
	_update_barrels(delta)
	_update_visuals()


func _update_barrels(delta: float) -> void:
	var controlled := alive and not cmd.is_empty()
	var basis := global_transform.basis
	for m in mods:
		if m["type"] != "barrel":
			continue
		m["cool"] = maxf(0.0, float(m["cool"]) - delta * float(m["frac"]))
		if not m["alive"] or not controlled:
			continue
		var bay: Dictionary = by_id.get(int(m["bay"]), {})
		var ok: bool = (not bay.is_empty()) and module_online(bay) and switches["weapons"] and module_online(m)
		if not ok:
			continue
		var ws: Dictionary = m["ws"]
		var apt = cmd.get("aim_point", null)
		var tgt = cmd.get("aim_target", null)
		var pt: Vector3 = to_global(m["pos"]) + basis * (ShipData.DIRS[int(m["dir"])] as Vector3) * 100.0
		if tgt != null and is_instance_valid(tgt) and (tgt as Ship).alive:
			var sp := float(ws["speed"])
			pt = lead_point(to_global(m["pos"]), sp if ws["kind"] == "kinetic" else 0.0, (tgt as Ship).global_position, (tgt as Ship).linear_velocity, linear_velocity)
		elif apt != null:
			pt = apt
		var desired := (basis.inverse() * (pt - to_global(m["pos"]))).normalized()
		var mount: Vector3 = ShipData.DIRS[int(m["dir"])]
		if desired.angle_to(mount) > deg_to_rad(65.0):
			desired = mount.slerp(desired, deg_to_rad(65.0) / desired.angle_to(mount)).normalized()
		var cur: Vector3 = m["aim"]
		var ang := cur.angle_to(desired)
		if ang > 0.0001:
			cur = cur.slerp(desired, clampf(2.5 * delta / ang, 0.0, 1.0)).normalized()
		m["aim"] = cur
		if m["pivot"] != null:
			_aim_pivot(m)
		var aligned := cur.angle_to(desired) < deg_to_rad(4.0)
		if cmd.get("fire", false) and float(m["cool"]) <= 0.0 and float(m["frac"]) > 0.3 and aligned and int(m["ammo"]) != 0:
			_fire(m, tgt)


func _fire(m: Dictionary, tgt) -> void:
	var ws: Dictionary = m["ws"]
	var basis := global_transform.basis
	var aim: Vector3 = m["aim"]
	var dir := (basis * aim).normalized()
	var from := to_global((m["pos"] as Vector3) + aim * (float(m["len"]) * 0.5 + 0.3))
	m["cool"] = float(ws["interval"])
	var parent := get_parent()
	match ws["kind"]:
		"laser":
			Projectile.fire_laser(parent, self, ws, from, dir)
		"missile":
			m["ammo"] = int(m["ammo"]) - 1
			var t: Ship = tgt as Ship if tgt != null else target
			Projectile.spawn(parent, self, ws, from, dir, linear_velocity, t)
		_:
			Projectile.spawn(parent, self, ws, from, dir, linear_velocity, null)
	Fx.burst(parent, from, 0.9, Color(1.0, 0.9, 0.6), 0.12)


func _update_visuals() -> void:
	var frac := hull_hp / hull_hp_max
	var base := ShipData.col(bp["color"])
	hull_mat.albedo_color = base.lerp(Color(0.12, 0.1, 0.1), clampf(1.0 - frac, 0.0, 1.0) * 0.8)
	for m in mods:
		if m["flame"] != null:
			var th: float = m["throttle"]
			var l := 0.01 + th * minf((m["size"] as Vector3).z * 1.6, 6.0) if m["alive"] else 0.01
			(m["flame"] as Node3D).scale = Vector3(1.0, l, 1.0)


# ------------------------------------------------------------------ damage
## Hull armor vs penetration, then a spatial path through the modules (GDD 6: hull -> armor -> modules).
func apply_hit(attacker: Ship, wpos: Vector3, dir_w: Vector3, damage: float, pen: float, kind: String, radius: float, bare := false) -> void:
	if wreck:
		Fx.burst(get_parent(), wpos, 1.0, Color(1, 0.6, 0.2), 0.2)
		return
	var lp := to_local(wpos)
	var ld := (global_transform.basis.inverse() * dir_w).normalized()
	var armor := 0.0 if bare else float(stats["armor"])
	var report := {"kind": kind, "armor": armor, "pen": pen, "penetrated": false, "modules": [], "hull": 0.0, "damage": damage}
	var dealt_hull := 0.0
	if kind == "missile":
		dealt_hull = damage * 0.3
		var scale_in := 0.4 if (pen <= armor and not bare) else 1.0
		for m in mods:
			if not m["alive"]:
				continue
			var box: AABB = m["box"]
			var cp := Vector3(clampf(lp.x, box.position.x, box.end.x), clampf(lp.y, box.position.y, box.end.y), clampf(lp.z, box.position.z, box.end.z))
			var dist := lp.distance_to(cp)
			if dist < radius:
				var dm := damage * (1.0 - dist / maxf(radius, 0.01)) * scale_in
				_hurt_module(m, dm, report, attacker)
	else:
		var penetrated := bare or pen > armor
		report["penetrated"] = penetrated
		if not penetrated:
			dealt_hull = damage * (0.6 if kind == "kinetic" else 0.5)
		else:
			dealt_hull = damage * 0.25
			var left := damage * clampf(1.0 - (armor / maxf(pen, 0.001)) * 0.5, 0.3, 1.0)
			var depth := 1.5 if bare else (pen - armor) * 3.0 + 0.5
			var start := lp - ld * 0.15
			var hits: Array = []
			for m in mods:
				if not m["alive"]:
					continue
				var box: AABB = m["box"]
				if box.has_point(start):
					hits.append({"m": m, "d": 0.0})
				else:
					var h = box.intersects_segment(start, lp + ld * depth)
					if h != null:
						hits.append({"m": m, "d": start.distance_to(h)})
			hits.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
			for h in hits:
				if left <= 0.0:
					break
				var m: Dictionary = h["m"]
				var take := minf(left, float(m["hp"]))
				_hurt_module(m, take, report, attacker)
				left -= take
	report["hull"] = dealt_hull
	Fx.burst(get_parent(), wpos, 0.8 + radius * 0.6, Color(1.0, 0.7, 0.3), 0.3)
	hit_report.emit(self, report)
	_damage_hull(dealt_hull, attacker)


func _hurt_module(m: Dictionary, dmg: float, report: Dictionary, attacker: Ship) -> void:
	if dmg <= 0.0 or not m["alive"]:
		return
	m["hp"] = float(m["hp"]) - dmg
	(report["modules"] as Array).append({"label": m["label"], "id": m["id"], "dmg": dmg, "destroyed": float(m["hp"]) <= 0.0})
	if float(m["hp"]) <= 0.0:
		m["hp"] = 0.0
		m["alive"] = false
		if m["node"] != null:
			if m["mat"] != null:
				(m["mat"] as StandardMaterial3D).albedo_color = Color(0.05, 0.05, 0.05)
				(m["mat"] as StandardMaterial3D).emission_enabled = false
		if m["flame"] != null:
			(m["flame"] as Node3D).visible = false
		Fx.burst(get_parent(), to_global(m["pos"]), maxf(2.0, (m["size"] as Vector3).length()), Color(1.0, 0.5, 0.15), 0.6)
		module_destroyed.emit(self, m)
		if m["type"] == "commander_post":
			var any := false
			for c in mods_of("commander_post"):
				if c["alive"]:
					any = true
			if not any:
				_die(attacker)


func _damage_hull(amount: float, attacker: Ship) -> void:
	if wreck or amount <= 0.0:
		return
	hull_hp -= amount
	if hull_hp <= 0.0:
		hull_hp = 0.0
		_die(attacker)


func _die(attacker: Ship) -> void:
	if wreck:
		return
	alive = false
	wreck = true
	killer = attacker
	cmd = {}
	remove_from_group("ships")
	add_to_group("wrecks")
	for m in mods:
		if m["flame"] != null:
			(m["flame"] as Node3D).visible = false
	hull_mat.albedo_color = Color(0.1, 0.09, 0.09)
	Fx.burst(get_parent(), global_position, maxf(6.0, float(stats["longest"]) * 0.6), Color(1.0, 0.55, 0.2), 1.2)
	died.emit(self, attacker)


## Sandbox helper: restore every module and the hull.
func revive() -> void:
	hull_hp = hull_hp_max
	for m in mods:
		m["hp"] = m["max"]
		m["alive"] = true
		m["ammo"] = int((m["ws"] as Dictionary).get("ammo", -1)) if m["type"] == "barrel" else -1
		if m["flame"] != null:
			(m["flame"] as Node3D).visible = true
		if m["mat"] != null and m["type"] != "commander_post":
			(m["mat"] as StandardMaterial3D).albedo_color = Color(0.25, 0.25, 0.28) if m["type"] == "thruster" else Color(0.7, 0.72, 0.78)
	if wreck:
		wreck = false
		alive = true
		remove_from_group("wrecks")
		add_to_group("ships")
