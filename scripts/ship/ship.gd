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
# Simulation that scales (km-long ships with thousands of modules): modules are grouped by power priority, the
# per-frame work is O(groups); per-module values (demand, frac, heat) are refreshed in time slices. Ships with
# EXACT_MAX modules or fewer keep exact per-module values every frame.
const EXACT_MAX := 64
const GROUPS := 64
var _by_type := {}
var _barrels: Array = []
var _cooling: Array = []          # barrels with a cooldown running
var _bays: Array = []
var _flames: Array = []
var _groups: Array = []
var _exact := true
var _struct_dirty := true
var _prio_stale := false          # a generator died: the priority order is out of date (recomputed at most every PRIO_EVERY s)
var _prio_cd := 0.0
var _engine_thr := {}             # engine room id -> its thrusters
var _ctrl_barrels := {}           # turret control id -> its barrels
const PRIO_EVERY := 4.0
var rebuilds := 0                 # how many times the power groups were rebuilt (profiling)
var _sw_sig := -1
var _gen_sig := -1
var _supply := 0.0
var _served := 0.0
var _n_gens := 0
var _used := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _firing := false
# Batched visuals (ships with many external modules): one MultiMesh for the bodies, one for the barrels, one for
# the flames instead of one node per module, so a moving ship costs a few nodes, not thousands.
const BATCH_MIN := 24
var _batch := false
var _bt_body: Array = []
var _bt_barrel: Array = []
var _bt_flame: Array = []
var _mm_body: MultiMesh
var _mm_barrel: MultiMesh
var _mm_flame: MultiMesh
var _flames_dir := [[], [], [], [], [], []]
var _fl_q := [-1, -1, -1, -1, -1, -1]
var _th_n := 1
var _th_i := 0
var _th_acc: Array = []
var _acc_w := 0.0
var _acc_c := Vector3.ZERO
var _acc_peak := 0.0
var _acc_hot: Dictionary = {}
var _grid := {}
var _grid_cell := 8.0
var dormant := false              # far from the player: not simulated (see FarSim)
var far_abs: Vec3D                # 64-bit position while dormant
var far_vel := Vector3.ZERO
var far_goal: Vec3D               # where a dormant ship is heading (null = drift)
var hull_temp := 0.0             # % of critical (see ShipData.HEAT_*)
var heat_peak := 0.0             # hottest module, %
var heat_hottest: Dictionary = {}
var heat_centroid := Vector3.ZERO  # where the heat is building up (ship space), weighted by module heat content
var _hull_cap := 1.0
var _hull_rad := 1.0
var _heat_t := 0.0
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
	var ext_n := 0
	for bm in bp["modules"]:
		if ShipData.MODULES[String(bm["type"])]["kind"] == "external":
			ext_n += 1
	_batch = ext_n > BATCH_MIN
	hull_hp_max = maxf(float(stats["hull_hp"]), 1.0)
	hull_hp = hull_hp_max
	_hull_rad = maxf(ShipData.HEAT_RAD * float(stats["area"]), 0.001)
	_hull_cap = maxf(ShipData.HEAT_HULL_CAP * float(stats["mass"]), 0.5)
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
	for m in mods:
		if m["type"] == "barrel" and int(m["bay"]) >= 0 and by_id.has(int(m["bay"])):
			(by_id[int(m["bay"])]["barrels"] as Array).append(int(m["id"]))
	for i in range(mods.size()):
		var m: Dictionary = mods[i]
		if m["type"] == "turret_bay":
			m["slew"] = clampf(4.0 / sqrt(maxf(ShipData.module_volume(bp["modules"][i]), 1.0)), 0.4, 3.0)
		if not _by_type.has(m["type"]):
			_by_type[m["type"]] = []
		(_by_type[m["type"]] as Array).append(m)
		if m["type"] == "barrel":
			_barrels.append(m)
		elif m["type"] == "turret_bay":
			_bays.append(m)
		if m["flame"] != null:
			_flames.append(m)
	for t in _by_type.get("thruster", []):
		if int(t["engine"]) >= 0:
			if not _engine_thr.has(int(t["engine"])):
				_engine_thr[int(t["engine"])] = []
			(_engine_thr[int(t["engine"])] as Array).append(t)
	for b in _barrels:
		for cid in b["ctrls"]:
			if not _ctrl_barrels.has(int(cid)):
				_ctrl_barrels[int(cid)] = []
			(_ctrl_barrels[int(cid)] as Array).append(b)
	_exact = mods.size() <= EXACT_MAX
	_th_n = 1 if _exact else clampi(int(ceil(float(mods.size()) / 150.0)), 2, 60)   # about 150 modules per frame
	_th_acc = []
	for i in _th_n:
		_th_acc.append(0.0)
	_build_batches()
	_build_grid()
	_rebuild_groups()


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
		"bay": -1, "ctrls": [], "mount": ShipData.DIRS[int(m["dir"])], "cur_pos": ShipData.v3(m["pos"]), "q": Quaternion.IDENTITY,
		"barrels": [], "slew": 1.5, "limit": 75.0,
		"tmode": "main", "tgt": null,
		"heat": 0.0, "hfrac": 1.0, "hwaste": 0.0, "hfac": ShipData.thermal_factor(int(m["id"]), String(m["type"])),
		"hcap": maxf(ShipData.HEAT_CAP_PER_M3 * float(ms["volume"]), 0.2), "hsurf": ShipData.module_surface(ShipData.v3(m["size"])),
	}
	if m["type"] == "thruster":
		rm["engine"] = ShipData.thruster_engine(bp, int(m["id"]))
		rm["ef"] = ShipData.engine_factor(bp, int(rm["engine"])) if int(rm["engine"]) >= 0 else 0.0
	if m["type"] == "barrel":
		var ws := ShipData.weapon_stats(m)
		rm["ws"] = ws
		rm["ammo"] = int(ws["ammo"])
		rm["bd"] = ShipData.barrel_dims(m)
		rm["len"] = (rm["bd"] as Vector2).x
		var bays := ShipData.linked_ids(bp, int(m["id"]), "turret_bay")
		rm["bay"] = int(bays[0]) if not bays.is_empty() else -1
		rm["ctrls"] = ShipData.linked_ids(bp, int(m["id"]), "turret_control")
	by_id[int(m["id"])] = rm
	mods.append(rm)
	if def["kind"] != "external":
		return
	if _batch:
		match String(m["type"]):
			"commander_post", "turret_bay":
				_bt_body.append(rm)
			"thruster":
				_bt_body.append(rm)
				_bt_flame.append(rm)
			"barrel":
				_bt_barrel.append(rm)
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
		"turret_bay":
			mat.albedo_color = Color(0.3, 0.3, 0.34)
			rm["node"] = _box_node(rm["pos"], rm["size"], mat)
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


func _body_color(m: Dictionary) -> Color:
	match String(m["type"]):
		"commander_post":
			return (TEAM_COLORS[team % TEAM_COLORS.size()] as Color).lightened(0.15)
		"thruster":
			return Color(0.25, 0.25, 0.28)
		"turret_bay":
			return Color(0.3, 0.3, 0.34)
	return Color(0.7, 0.72, 0.78)


func _barrel_xf(m: Dictionary) -> Transform3D:
	var a: Vector3 = m["aim"]
	var up := Vector3.UP if absf(a.y) < 0.98 else Vector3.RIGHT
	var dims: Vector2 = m["bd"]
	return Transform3D(Basis.looking_at(a, up) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(dims.y, dims.x, dims.y)), m["cur_pos"])


func _flame_set(m: Dictionary, l: float) -> void:
	var fb: Basis = m["fl_basis"]
	var r: float = m["fl_r"]
	var origin: Vector3 = (m["fl_origin"] as Vector3) + fb.y * (0.5 * l)
	_mm_flame.set_instance_transform(int(m["mmf"]), Transform3D(fb * Basis.from_scale(Vector3(r, l, r)), origin))


func _make_mm(mesh: Mesh, n: int, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mm


func _build_batches() -> void:
	if not _batch:
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.4
	mat.roughness = 0.5
	if not _bt_body.is_empty():
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		_mm_body = _make_mm(bm, _bt_body.size(), mat)
		for i in range(_bt_body.size()):
			var m: Dictionary = _bt_body[i]
			m["mmb"] = i
			_mm_body.set_instance_transform(i, Transform3D(Basis.from_scale(m["size"]), m["pos"]))
			_mm_body.set_instance_color(i, _body_color(m))
	if not _bt_barrel.is_empty():
		var cm := CylinderMesh.new()
		cm.height = 1.0
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.radial_segments = 8
		cm.rings = 1
		_mm_barrel = _make_mm(cm, _bt_barrel.size(), mat)
		for i in range(_bt_barrel.size()):
			var b: Dictionary = _bt_barrel[i]
			b["mmc"] = i
			_mm_barrel.set_instance_transform(i, _barrel_xf(b))
			_mm_barrel.set_instance_color(i, Color(0.7, 0.72, 0.78))
	if not _bt_flame.is_empty():
		var fm := CylinderMesh.new()
		fm.height = 1.0
		fm.top_radius = 0.0
		fm.bottom_radius = 1.0
		fm.radial_segments = 8
		fm.rings = 1
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.vertex_color_use_as_albedo = true
		_mm_flame = _make_mm(fm, _bt_flame.size(), fmat)
		for i in range(_bt_flame.size()):
			var t: Dictionary = _bt_flame[i]
			t["mmf"] = i
			var dvv: Vector3 = ShipData.DIRS[int(t["dir"])]
			var half: float = (t["size"] as Vector3)[ShipData.DIR_AXIS[int(t["dir"])]] * 0.5
			t["fl_origin"] = (t["pos"] as Vector3) - dvv * half
			t["fl_basis"] = Basis(Quaternion(Vector3.UP, -dvv))
			t["fl_r"] = minf((t["size"] as Vector3).x, (t["size"] as Vector3).y) * 0.4
			_mm_flame.set_instance_color(i, Color(1.0, 0.65, 0.25))
			_flame_set(t, 0.0)
			(_flames_dir[int(t["dir"])] as Array).append(t)


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
	return _by_type.get(type, [])


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


# ------------------------------------------------------------------ spatial index (big ships)
func _build_grid() -> void:
	_grid.clear()
	if mods.size() <= EXACT_MAX:
		return
	var ext := PackedFloat32Array()
	for m in mods:
		var sz: Vector3 = m["size"]
		ext.append(maxf(sz.x, maxf(sz.y, sz.z)))
	ext.sort()
	_grid_cell = clampf(ext[ext.size() / 2] * 2.5, 4.0, 400.0)
	for m in mods:
		var b: AABB = m["box"]
		var lo := _cell(b.position)
		var hi := _cell(b.end)
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var key := Vector3i(x, y, z)
					if not _grid.has(key):
						_grid[key] = []
					(_grid[key] as Array).append(m)


func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / _grid_cell), floori(p.y / _grid_cell), floori(p.z / _grid_cell))


func _collect(c: Vector3i, out: Array, seen: Dictionary) -> void:
	var lst = _grid.get(c)
	if lst == null:
		return
	for m in lst:
		var id: int = m["id"]
		if not seen.has(id):
			seen[id] = true
			out.append(m)


## Modules whose cells the segment (ship space) passes through. All modules on a small ship.
func modules_along(a: Vector3, b: Vector3) -> Array:
	if _grid.is_empty():
		return mods
	var out: Array = []
	var seen := {}
	var d := b - a
	var c := _cell(a)
	var cend := _cell(b)
	var step := Vector3i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1, 1 if d.z > 0.0 else -1)
	var tmax := Vector3(INF, INF, INF)
	var tdelta := Vector3(INF, INF, INF)
	for ax in 3:
		if absf(d[ax]) > 1e-9:
			var nb := (float(c[ax]) + (1.0 if step[ax] > 0 else 0.0)) * _grid_cell
			tmax[ax] = (nb - a[ax]) / d[ax]
			tdelta[ax] = _grid_cell / absf(d[ax])
	var guard := 0
	while guard < 16384:
		guard += 1
		_collect(c, out, seen)
		if c == cend:
			break
		var axm := 0 if (tmax.x <= tmax.y and tmax.x <= tmax.z) else (1 if tmax.y <= tmax.z else 2)
		if tmax[axm] > 1.0:
			break
		c[axm] += step[axm]
		tmax[axm] += tdelta[axm]
	return out


## Modules within `r` of a point (ship space), by cell. All modules on a small ship.
func modules_near(p: Vector3, r: float) -> Array:
	if _grid.is_empty():
		return mods
	var out: Array = []
	var seen := {}
	var lo := _cell(p - Vector3(r, r, r))
	var hi := _cell(p + Vector3(r, r, r))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				_collect(Vector3i(x, y, z), out, seen)
	return out


func ext_module_ray(p0w: Vector3, p1w: Vector3):
	var a := to_local(p0w)
	var b := to_local(p1w)
	var best = null
	var best_d := INF
	for m in modules_along(a, b):
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
	for m in _by_type.get("thruster", []):
		if not module_online(m) or not switches["thrusters"]:
			continue
		var eng: Dictionary = by_id.get(int(m["engine"]), {})
		if eng.is_empty() or not eng["alive"]:
			continue
		caps[int(m["dir"])] += float(m["ms"]["thrust"]) * float(m["ef"])
	var best := 0.0
	for c in caps:
		best = maxf(best, c)
	rcs_cap = best * ShipData.RCS_FRACTION


## Something that changes who is online or what they draw happened (a module died, the ship died, ...).
func mark_structure_dirty() -> void:
	_struct_dirty = true


func _structure_sig() -> int:
	var sg := 0
	var bit := 1
	for k in switches.keys():
		if bool(switches[k]):
			sg |= bit
		bit <<= 1
	return sg | (1 << 24 if alive else 0)


## Distance from a point to the nearest of `gens`; a hash grid keeps this cheap with thousands of generators.
func _assign_groups(gen_pos: Array) -> void:
	var n := mods.size()
	var prios := PackedFloat32Array()
	prios.resize(n)
	if gen_pos.is_empty():
		pass
	elif n * gen_pos.size() <= 30000:
		for i in range(n):
			var p: Vector3 = (mods[i] as Dictionary)["pos"]
			var dmin := INF
			for g in gen_pos:
				dmin = minf(dmin, p.distance_squared_to(g))
			prios[i] = sqrt(dmin)
	else:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for g in gen_pos:
			lo = lo.min(g)
			hi = hi.max(g)
		var span := (hi - lo).max(Vector3(1, 1, 1))
		var cell := maxf(pow(span.x * span.y * span.z / float(gen_pos.size()), 1.0 / 3.0) * 1.5, 1.0)
		var cells := {}
		for g in gen_pos:
			var key := Vector3i(floori(g.x / cell), floori(g.y / cell), floori(g.z / cell))
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(g)
		var max_ring := int(ceil(maxf(span.x, maxf(span.y, span.z)) / cell)) + 2
		for i in range(n):
			var p2: Vector3 = (mods[i] as Dictionary)["pos"]
			var c0 := Vector3i(floori(p2.x / cell), floori(p2.y / cell), floori(p2.z / cell))
			var best := INF
			var found_ring := -1
			for r in range(0, max_ring):
				if found_ring >= 0 and r > found_ring + 1:
					break
				for dx in range(-r, r + 1):
					for dy in range(-r, r + 1):
						for dz in range(-r, r + 1):
							if maxi(absi(dx), maxi(absi(dy), absi(dz))) != r:
								continue
							var lst = cells.get(c0 + Vector3i(dx, dy, dz))
							if lst == null:
								continue
							for g in lst:
								best = minf(best, p2.distance_squared_to(g))
							if found_ring < 0:
								found_ring = r
			prios[i] = sqrt(best) if best < INF else 0.0
	var sorted := prios.duplicate()
	sorted.sort()
	var gc := n if _exact else mini(GROUPS, n)
	gc = maxi(gc, 1)
	var bounds := PackedFloat32Array()
	for gi in range(gc):
		bounds.append(sorted[mini(gi * n / gc, n - 1)] if n > 0 else 0.0)
	_groups = []
	for gi in range(gc):
		_groups.append({"mods": [], "base": 0.0, "bar": 0.0, "thr": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "thr_force": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "frac": 1.0, "demand": 0.0, "prio": bounds[gi]})
	for i in range(n):
		var m: Dictionary = mods[i]
		m["prio"] = prios[i]
		var gi2 := clampi(bounds.bsearch(prios[i], false) - 1, 0, gc - 1)
		m["grp"] = gi2
		(_groups[gi2]["mods"] as Array).append(m)


## What each priority group asks for: idle power, thrusters' peak per direction, barrels' extra when firing.
func _aggregate_groups() -> void:
	for g in _groups:
		g["base"] = 0.0
		g["bar"] = 0.0
		for d in 6:
			g["thr"][d] = 0.0
			g["thr_force"][d] = 0.0
	var thr_on: bool = switches["thrusters"]
	for m in mods:
		var g: Dictionary = _groups[int(m["grp"])]
		var t: String = m["type"]
		m["thr_ok"] = false
		m["bar_ok"] = false
		if t == "thruster" and thr_on and module_online(m):
			var eng: Dictionary = by_id.get(int(m["engine"]), {})
			if not eng.is_empty() and eng["alive"]:
				var d := int(m["dir"])
				m["thr_ok"] = true
				g["thr"][d] += float(m["ms"]["peak"]) * float(m["ef"])
				g["thr_force"][d] += float(m["ms"]["thrust"]) * float(m["ef"]) * float(m["hfrac"])
				continue
		g["base"] += float(m["idle_eff"])
		if t == "barrel" and module_online(m) and _barrel_controlled(m):
			m["bar_ok"] = true
			g["bar"] += float(m["ws"]["power"]) - float(m["idle_eff"])


## A module was destroyed: take its contribution out of the groups (and that of whatever depended on it) without
## rebuilding everything. Only the generator priority order is left to a later, rate-limited rebuild.
func _on_module_died(m: Dictionary) -> void:
	if _groups.is_empty() or _struct_dirty:
		_struct_dirty = true
		return
	var g: Dictionary = _groups[int(m["grp"])]
	var t: String = m["type"]
	var caps_changed := false
	if bool(m.get("thr_ok", false)):
		var d := int(m["dir"])
		g["thr"][d] = float(g["thr"][d]) - float(m["ms"]["peak"]) * float(m["ef"])
		g["thr_force"][d] = float(g["thr_force"][d]) - float(m["ms"]["thrust"]) * float(m["ef"]) * float(m["hfrac"])
		m["thr_ok"] = false
		caps[d] = float(caps[d]) - float(m["ms"]["thrust"]) * float(m["ef"])
		caps_changed = true
	else:
		g["base"] = float(g["base"]) - float(m["idle_eff"])
	if bool(m.get("bar_ok", false)):
		g["bar"] = float(g["bar"]) - (float(m["ws"]["power"]) - float(m["idle_eff"]))
		m["bar_ok"] = false
	m["idle_eff"] = 0.0
	match t:
		"generator":
			_supply -= float(m["ms"]["out"]) * float(m["hfrac"])
			_n_gens -= 1
			_prio_stale = true
		"engine_room":
			for th in _engine_thr.get(int(m["id"]), []):
				if bool(th["thr_ok"]):
					var gt: Dictionary = _groups[int(th["grp"])]
					var dd := int(th["dir"])
					gt["thr"][dd] = float(gt["thr"][dd]) - float(th["ms"]["peak"]) * float(th["ef"])
					gt["thr_force"][dd] = float(gt["thr_force"][dd]) - float(th["ms"]["thrust"]) * float(th["ef"]) * float(th["hfrac"])
					gt["base"] = float(gt["base"]) + float(th["idle_eff"])
					th["thr_ok"] = false
					caps[dd] = float(caps[dd]) - float(th["ms"]["thrust"]) * float(th["ef"])
			caps_changed = true
		"turret_bay":
			for bid in m["barrels"]:
				_drop_barrel_if_uncontrolled(by_id[int(bid)])
		"turret_control":
			for b in _ctrl_barrels.get(int(m["id"]), []):
				_drop_barrel_if_uncontrolled(b)
	if caps_changed:
		var best := 0.0
		for c in caps:
			best = maxf(best, c)
		rcs_cap = best * ShipData.RCS_FRACTION


func _drop_barrel_if_uncontrolled(b: Dictionary) -> void:
	if bool(b.get("bar_ok", false)) and not _barrel_controlled(b):
		var gb: Dictionary = _groups[int(b["grp"])]
		gb["bar"] = float(gb["bar"]) - (float(b["ws"]["power"]) - float(b["idle_eff"]))
		b["bar_ok"] = false


func _rebuild_groups() -> void:
	_struct_dirty = false
	_prio_stale = false
	_prio_cd = PRIO_EVERY
	rebuilds += 1
	_sw_sig = _structure_sig()
	var gsig := 0
	var gen_pos: Array = []
	_supply = 0.0
	_n_gens = 0
	for m in mods:
		var on := module_online(m)
		var idle := float(m["ms"]["idle"]) if on else 0.0
		if m["type"] == "radar_room" and not switches["radar"]:
			idle = 0.0
		m["idle_eff"] = idle
		if m["type"] == "generator" and on:
			_supply += float(m["ms"]["out"]) * float(m["hfrac"])
			_n_gens += 1
			gen_pos.append(m["pos"])
			gsig = (gsig * 31 + int(m["id"])) & 0x7fffffff
	_refresh_caps()
	if gsig != _gen_sig or _groups.is_empty():
		_gen_sig = gsig
		_assign_groups(gen_pos)
	_aggregate_groups()


## Power: virtual consumers (gyro, RCS) first, then the priority groups, closest-to-a-generator first.
func _allocate_power() -> void:
	if _exact:
		var sp := 0.0
		for m in _by_type.get("generator", []):
			if module_online(m):
				sp += float(m["ms"]["out"]) * float(m["hfrac"])
		_supply = sp
	var remaining := _supply
	var total := 0.0
	var served := 0.0
	for c in [_virt_gyro, _virt_rcs]:
		var dm: float = c["demand"]
		total += dm
		var take := minf(dm, remaining)
		c["frac"] = (take / dm) if dm > 0.0 else 1.0
		remaining -= take
		served += take
	for g in _groups:
		var thr: Array = g["thr"]
		var dm2 := float(g["base"]) + (float(g["bar"]) if _firing else 0.0)
		for d in 6:
			dm2 += float(_used[d]) * float(thr[d])
		g["demand"] = dm2
		total += dm2
		var take2 := minf(dm2, remaining)
		g["frac"] = (take2 / dm2) if dm2 > 0.0 else 1.0
		remaining -= take2
		served += take2
	power_supply = _supply
	power_demand = total
	power_frac = clampf(_supply / total, 0.0, 1.0) if total > 0.0 else 1.0
	_served = served


## The per-module numbers (demand, frac, throttle) the rest of the game reads, derived from the group they belong to.
func _write_module_power(m: Dictionary) -> void:
	var g: Dictionary = _groups[int(m["grp"])]
	var d := float(m["idle_eff"])
	var thr := 0.0
	if bool(m["thr_ok"]):
		var di := int(m["dir"])
		d = float(m["ms"]["peak"]) * float(_used[di]) * float(m["ef"])
		thr = float(_used[di])
	elif bool(m["bar_ok"]) and _firing:
		d = float(m["ws"]["power"])
	m["demand"] = d
	m["frac"] = float(g["frac"]) if d > 0.0 else (1.0 if module_online(m) else 0.0)
	m["throttle"] = thr * float(m["frac"]) if d > 0.0 else 0.0


func _thrust_force(d: int) -> float:
	var t := 0.0
	for g in _groups:
		t += float((g["thr_force"] as Array)[d]) * float(g["frac"])
	return t


# ------------------------------------------------------------------ physics
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if wreck or dormant:
		return
	var dt := state.step
	var basis := state.transform.basis
	var inv := basis.inverse()
	var v_loc := inv * state.linear_velocity
	var w_loc := inv * state.angular_velocity
	_ram_cd = maxf(0.0, _ram_cd - dt)
	_prio_cd -= dt
	if _struct_dirty or _sw_sig != _structure_sig() or (_prio_stale and _prio_cd <= 0.0):
		_rebuild_groups()
	_virt_rcs["demand"] = 0.0
	_virt_gyro["demand"] = 0.0
	var controlled := alive and not cmd.is_empty()
	_firing = controlled and bool(cmd.get("fire", false))
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
	_used = used
	var kn_to_mw := ShipData.THRUSTER_MW_PER_M3 / ShipData.THRUST_KN_PER_M3
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

	# ---- power allocation (closest to a generator = highest priority), O(groups)
	_allocate_power()
	if _exact:
		for m in mods:
			_write_module_power(m)
	_thermal_step(dt)

	# ---- apply forces
	var f_local := Vector3.ZERO
	for a in 3:
		var r: float = f_req[a]
		if absf(r) < 1e-6:
			continue
		var sgn := 1 if r > 0.0 else -1
		var d := dir_index(a, sgn)
		var total := float(used[d]) * _thrust_force(d)
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


## Heat: every module turns part of the power it uses into heat and conducts it to the hull, the hull radiates it
## into space (bigger hull = better cooling). Hot modules lose output (thrust, fire rate, generator power), above
## critical they burn. Switch things off or stop firing to cool down.
func _thermal_step(dt: float) -> void:
	if not alive:
		return
	if _th_n <= 1:
		var flow := _thermal_pass(0, mods.size(), dt)
		hull_temp = clampf(hull_temp + (flow - _hull_rad * hull_temp) / _hull_cap * dt, 0.0, 300.0)
		_heat_damage_hull(dt)
		_heat_t -= dt
		if _heat_t <= 0.0:
			_heat_t = 0.2
			_refresh_heat_summary()
		return
	# big ship: each frame refreshes one slice of the modules, with the time that slice has been waiting
	for i in range(_th_n):
		_th_acc[i] = float(_th_acc[i]) + dt
	var n := mods.size()
	var lo := _th_i * n / _th_n
	var hi := (_th_i + 1) * n / _th_n
	var sdt: float = _th_acc[_th_i]
	_th_acc[_th_i] = 0.0
	for i in range(lo, hi):
		_write_module_power(mods[i])
	var flow2 := _thermal_pass(lo, hi, sdt)
	hull_temp = clampf(hull_temp + flow2 * sdt / _hull_cap - _hull_rad * hull_temp / _hull_cap * dt, 0.0, 300.0)
	_heat_damage_hull(dt)
	_th_i = (_th_i + 1) % _th_n
	if _th_i == 0:
		heat_peak = _acc_peak
		heat_hottest = _acc_hot
		heat_centroid = _acc_c / _acc_w if _acc_w > 0.001 else Vector3(stats["com"])
		_acc_peak = 0.0
		_acc_hot = {}
		_acc_w = 0.0
		_acc_c = Vector3.ZERO


func _heat_damage_hull(dt: float) -> void:
	if hull_temp > ShipData.HEAT_CRIT:
		_damage_hull(hull_hp_max * 0.002 * clampf((hull_temp - ShipData.HEAT_CRIT) / 20.0, 0.2, 3.0) * dt, null)


## Heat of modules [lo, hi) for `dt` seconds; returns the heat (MW) they pushed into the hull.
func _thermal_pass(lo: int, hi: int, dt: float) -> float:
	var served := _served
	var n_gens := _n_gens
	if _th_n <= 1:
		n_gens = 0
		for m in _by_type.get("generator", []):
			if module_online(m):
				n_gens += 1
		served = 0.0
		for m in mods:
			if float(m["demand"]) > 0.0:
				served += float(m["demand"]) * float(m["frac"])
		served += float(_virt_gyro["demand"]) * float(_virt_gyro["frac"]) + float(_virt_rcs["demand"]) * float(_virt_rcs["frac"])
	var gen_waste := ShipData.GEN_WASTE * served / float(maxi(n_gens, 1))
	var flow_sum := 0.0
	var report := {"modules": []}
	for i in range(lo, hi):
		var m: Dictionary = mods[i]
		var alive_m := bool(m["alive"])
		var waste := 0.0
		if alive_m:
			if String(m["type"]) == "generator":
				waste = gen_waste if module_online(m) else 0.0
			else:
				waste = float(m["demand"]) * float(m["frac"]) * ShipData.HEAT_WASTE
			waste *= float(m["hfac"])
		m["hwaste"] = waste
		var flow := ShipData.HEAT_COND * float(m["hsurf"]) * (float(m["heat"]) - hull_temp)
		flow_sum += flow
		var t := clampf(float(m["heat"]) + (waste - flow) / float(m["hcap"]) * dt, 0.0, 300.0)
		m["heat"] = t
		var old_h := float(m["hfrac"])
		var new_h := ShipData.heat_factor(t) if alive_m else 1.0
		m["hfrac"] = new_h
		if absf(new_h - old_h) > 1e-6:
			# output that depends on the heat factor is kept in the aggregates
			if String(m["type"]) == "generator" and not _exact:
				_supply += float(m["ms"]["out"]) * (new_h - old_h)
			elif bool(m.get("thr_ok", false)):
				(_groups[int(m["grp"])]["thr_force"] as Array)[int(m["dir"])] += float(m["ms"]["thrust"]) * float(m["ef"]) * (new_h - old_h)
		if alive_m and t > ShipData.HEAT_CRIT:
			_hurt_module(m, float(m["max"]) * 0.006 * clampf((t - ShipData.HEAT_CRIT) / 20.0, 0.2, 3.0) * dt, report, null)
		if _th_n > 1:
			if alive_m and t > _acc_peak:
				_acc_peak = t
				_acc_hot = m
			var w := t * float(m["ms"]["volume"])
			_acc_w += w
			_acc_c += (m["pos"] as Vector3) * w
	return flow_sum


func _refresh_heat_summary() -> void:
	var wsum := 0.0
	var csum := Vector3.ZERO
	heat_peak = 0.0
	heat_hottest = {}
	for m in mods:
		var t := float(m["heat"])
		if bool(m["alive"]) and t > heat_peak:
			heat_peak = t
			heat_hottest = m
		var w := t * float(m["ms"]["volume"])
		wsum += w
		csum += (m["pos"] as Vector3) * w
	heat_centroid = csum / wsum if wsum > 0.001 else Vector3(stats["com"])


func _physics_process(delta: float) -> void:
	if dormant:
		return
	if wreck:
		return
	_update_barrels(delta)
	_update_visuals()


## A barrel can act when its own module is online and a Turret Bay or Turret Control it is linked to is online.
func _barrel_controlled(m: Dictionary) -> bool:
	if not switches["weapons"] or not module_online(m):
		return false
	var bay: Dictionary = by_id.get(int(m["bay"]), {})
	if not bay.is_empty() and module_online(bay):
		return true
	for c in m["ctrls"]:
		var cm: Dictionary = by_id.get(int(c), {})
		if not cm.is_empty() and module_online(cm):
			return true
	return false


func _mounted(m: Dictionary) -> bool:
	var bay: Dictionary = by_id.get(int(m["bay"]), {})
	return not bay.is_empty() and bool(bay["alive"])


## Ship a barrel is told to engage: its own assignment, the main lock, or nothing (cursor aim).
func barrel_aim_target(m: Dictionary) -> Variant:
	match String(m.get("tmode", "main")):
		"cursor":
			return null
		"ship":
			var t = m.get("tgt", null)
			if t != null and is_instance_valid(t) and (t as Ship).alive:
				return t
	return cmd.get("aim_target", null)


## Weapon units = what the commander selects: a Turret Bay with the barrels on it, or a fixed barrel.
func weapon_units() -> Array:
	var out: Array = []
	for m in mods:
		if m["type"] == "turret_bay" and not (m["barrels"] as Array).is_empty():
			out.append(_weapon_unit(int(m["id"]), "bay", m["barrels"]))
		elif m["type"] == "barrel" and int(m["bay"]) < 0:
			out.append(_weapon_unit(int(m["id"]), "fixed", [int(m["id"])]))
	return out


func _weapon_unit(id: int, kind: String, ids: Array) -> Dictionary:
	var kinds := {}
	var dps := 0.0
	var ammo := 0
	var rng := INF
	var online := false
	for bid in ids:
		var b: Dictionary = by_id[int(bid)]
		var ws: Dictionary = b["ws"]
		kinds[String(ws["kind"])] = true
		dps += float(ws["damage"]) / maxf(float(ws["interval"]), 0.01)
		rng = minf(rng, float(ws["range"]))
		if int(ws["ammo"]) >= 0:
			ammo += int(b["ammo"])
		online = online or (bool(b["alive"]) and _barrel_controlled(b))
	var ref: Dictionary = by_id[id]
	var first: Dictionary = by_id[int(ids[0])]
	return {"id": id, "kind": kind, "barrels": ids.duplicate(), "kinds": kinds.keys(), "dps": dps, "range": rng, "ammo": ammo,
		"online": online, "pos": ref["pos"], "tmode": String(first.get("tmode", "main")), "tgt": first.get("tgt", null),
		"label": "%s #%d" % [ref["label"], id], "barrel_count": ids.size()}


## Can this unit point at the ship right now (inside its slew arc / aligned when fixed, inside range)?
func unit_can_hit(u: Dictionary, t: Ship) -> bool:
	var ref: Dictionary = by_id[int(u["id"])]
	var first: Dictionary = by_id[int((u["barrels"] as Array)[0])]
	var mount: Vector3 = first["mount"]
	var lim := deg_to_rad(float(ref["limit"])) if u["kind"] == "bay" else deg_to_rad(4.0)
	var rel := t.global_position - to_global(ref["pos"])
	if rel.length() > float(u["range"]):
		return false
	var want := (global_transform.basis.inverse() * rel).normalized()
	return mount.angle_to(want) <= lim


## World point a barrel should be pointed at (lead aiming when a target is locked).
func _barrel_aim_world(m: Dictionary) -> Vector3:
	var basis := global_transform.basis
	var origin := to_global(m["cur_pos"])
	var ws: Dictionary = m["ws"]
	var tgt = barrel_aim_target(m)
	if tgt != null and is_instance_valid(tgt) and (tgt as Ship).alive:
		var sp := float(ws["speed"]) if ws["kind"] == "kinetic" else 0.0
		return lead_point(origin, sp, (tgt as Ship).global_position, (tgt as Ship).linear_velocity, linear_velocity)
	var apt = cmd.get("aim_point", null)
	if apt != null:
		return apt
	return origin + basis * (m["mount"] as Vector3) * 100.0


func _update_barrels(delta: float) -> void:
	var controlled := alive and not cmd.is_empty()
	var basis := global_transform.basis
	var inv := basis.inverse()
	# ---- Turret Bays slew as one body: the barrels touching them are carried along, so aiming stays consistent
	for bay in _bays:
		if not bay["alive"]:
			continue
		var q: Quaternion = bay["q"]
		var target_q := Quaternion.IDENTITY
		if controlled and module_online(bay) and switches["weapons"] and not (bay["barrels"] as Array).is_empty():
			var ref: Dictionary = by_id[int((bay["barrels"] as Array)[0])]
			var want := (inv * (_barrel_aim_world(ref) - to_global(bay["pos"]))).normalized()
			var mount: Vector3 = ref["mount"]
			var ang := mount.angle_to(want)
			var lim := deg_to_rad(float(bay["limit"]))
			if ang > lim:
				want = mount.slerp(want, lim / ang).normalized()
			if mount.cross(want).length() > 1e-5 or mount.dot(want) > 0.0:
				target_q = Quaternion(mount, want)
		var a := q.angle_to(target_q)
		if a > 1e-4:
			q = q.slerp(target_q, clampf(float(bay["slew"]) * delta / a, 0.0, 1.0))
		var moved := a > 1e-4
		bay["q"] = q
		if bay["node"] != null:
			(bay["node"] as Node3D).basis = Basis(q)
		elif _batch and moved:
			_mm_body.set_instance_transform(int(bay["mmb"]), Transform3D(Basis(q) * Basis.from_scale(bay["size"]), bay["pos"]))
		for bid in bay["barrels"]:
			var b: Dictionary = by_id[int(bid)]
			b["aim"] = q * (b["mount"] as Vector3)
			b["cur_pos"] = (bay["pos"] as Vector3) + q * ((b["pos"] as Vector3) - (bay["pos"] as Vector3))
			if b["pivot"] != null:
				(b["pivot"] as Node3D).position = b["cur_pos"]
				_aim_pivot(b)
			elif _batch and moved:
				_mm_barrel.set_instance_transform(int(b["mmc"]), _barrel_xf(b))
	# ---- firing
	var firing_cmd := controlled and bool(cmd.get("fire", false))
	var ci := 0
	while ci < _cooling.size():
		var cm: Dictionary = _cooling[ci]
		cm["cool"] = maxf(0.0, float(cm["cool"]) - delta * float((_groups[int(cm["grp"])] as Dictionary)["frac"]) * float(cm["hfrac"]))
		if float(cm["cool"]) <= 0.0:
			_cooling.remove_at(ci)
		else:
			ci += 1
	for m in _barrels if firing_cmd else []:
		if float(m["cool"]) > 0.0 or not m["alive"] or int(m["ammo"]) == 0:
			continue
		if not _barrel_controlled(m) or float((_groups[int(m["grp"])] as Dictionary)["frac"]) <= 0.3:
			continue
		var aim: Vector3 = m["aim"]
		var ok := true
		if _mounted(m):
			var desired := (inv * (_barrel_aim_world(m) - to_global(m["cur_pos"]))).normalized()
			ok = aim.angle_to(desired) < deg_to_rad(4.0)
		if not ok:
			continue
		var muzzle: Vector3 = (m["cur_pos"] as Vector3) + aim * (float(m["len"]) * 0.5 + 0.3)
		if ShipData.hull_contains(bp["rings"], muzzle + aim * 1.5):
			continue
		_fire(m, barrel_aim_target(m))


func _fire(m: Dictionary, tgt) -> void:
	var ws: Dictionary = m["ws"]
	var basis := global_transform.basis
	var aim: Vector3 = m["aim"]
	var dir := (basis * aim).normalized()
	var from := to_global((m["cur_pos"] as Vector3) + aim * (float(m["len"]) * 0.5 + 0.3))
	m["cool"] = float(ws["interval"])
	_cooling.append(m)
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
	for m in _flames:
		var th: float = m["throttle"]
		var l := 0.01 + th * minf((m["size"] as Vector3).z * 1.6, 6.0) if m["alive"] else 0.01
		(m["flame"] as Node3D).scale = Vector3(1.0, l, 1.0)
	if _batch and alive:
		for d in 6:
			var q := int(float(_used[d]) * power_frac * 20.0)
			if q != int(_fl_q[d]):
				_fl_q[d] = q
				for t in _flames_dir[d]:
					_flame_set(t, (0.01 + float(q) / 20.0 * minf((t["size"] as Vector3).z * 1.6, 6.0)) if t["alive"] else 0.0)


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
		for m in modules_near(lp, radius):
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
			for m in modules_along(start, lp + ld * depth):
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
		_on_module_died(m)
		if m["node"] != null:
			if m["mat"] != null:
				(m["mat"] as StandardMaterial3D).albedo_color = Color(0.05, 0.05, 0.05)
				(m["mat"] as StandardMaterial3D).emission_enabled = false
		if m["flame"] != null:
			(m["flame"] as Node3D).visible = false
		if _batch:
			if m.has("mmb"):
				_mm_body.set_instance_color(int(m["mmb"]), Color(0.05, 0.05, 0.05))
			if m.has("mmc"):
				_mm_barrel.set_instance_color(int(m["mmc"]), Color(0.05, 0.05, 0.05))
			if m.has("mmf"):
				_flame_set(m, 0.0)
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
	_struct_dirty = true
	remove_from_group("ships")
	add_to_group("wrecks")
	for m in mods:
		if m["flame"] != null:
			(m["flame"] as Node3D).visible = false
	for m in _bt_flame:
		_flame_set(m, 0.0)
	hull_mat.albedo_color = Color(0.1, 0.09, 0.09)
	Fx.burst(get_parent(), global_position, maxf(6.0, float(stats["longest"]) * 0.6), Color(1.0, 0.55, 0.2), 1.2)
	died.emit(self, attacker)


## Sandbox helper: restore every module and the hull.
func revive() -> void:
	_struct_dirty = true
	hull_hp = hull_hp_max
	hull_temp = 0.0
	heat_peak = 0.0
	for m in mods:
		m["heat"] = 0.0
		m["hfrac"] = 1.0
		m["hwaste"] = 0.0
		m["hp"] = m["max"]
		m["alive"] = true
		m["ammo"] = int((m["ws"] as Dictionary).get("ammo", -1)) if m["type"] == "barrel" else -1
		if m["flame"] != null:
			(m["flame"] as Node3D).visible = true
		if _batch:
			if m.has("mmb"):
				_mm_body.set_instance_color(int(m["mmb"]), _body_color(m))
			if m.has("mmc"):
				_mm_barrel.set_instance_color(int(m["mmc"]), Color(0.7, 0.72, 0.78))
		if m["mat"] != null and m["type"] != "commander_post":
			(m["mat"] as StandardMaterial3D).albedo_color = Color(0.25, 0.25, 0.28) if m["type"] == "thruster" else Color(0.7, 0.72, 0.78)
	if wreck:
		wreck = false
		alive = true
		remove_from_group("wrecks")
		add_to_group("ships")
