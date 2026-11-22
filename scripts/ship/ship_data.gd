class_name ShipData
extends RefCounted
## Blueprint data model, geometry, stats, cost and legality rules (GDD sections 1.1-1.3, 2).
## A blueprint is a plain Dictionary so it can be saved as JSON.
## Ship space: nose points to -Z, +X is right, +Y is up. Units: metres, tonnes, kN, MW.

const RING_PTS := 8
const MIN_RING_GAP := 0.4
const ARMOR_DENSITY := 1.5        # t per m^3 of hull shell
const ARMOR_PROTECTION := 8.0     # armor rating (metres of steel-equivalent) per metre of thickness
const HULL_HP_PER_M3 := 40.0
const THRUST_KN_PER_M3 := 250.0
const THRUSTER_MW_PER_M3 := 5.0
const GENERATOR_MW_PER_M3 := 5.0
const RCS_FRACTION := 0.10        # GDD 2.3: RCS = 10% of best-vector thruster power
const GYRO_K := 150.0
# Heat (GDD hidden module "Heat"). Temperatures are in % of the critical temperature (100 = modules start to burn).
const HEAT_WASTE := 0.35          # share of the power a module consumes that ends up as heat
const GEN_WASTE := 0.12           # share of the power a generator delivers that ends up as heat (split between generators)
const HEAT_CAP_PER_M3 := 0.12     # MJ per % per m3 of module
const HEAT_COND := 0.02           # MW per m2 of module surface per % of difference between module and hull
const HEAT_RAD := 0.0008          # MW per m2 of hull per % of hull temperature (the hull is the radiator)
const HEAT_HULL_CAP := 0.10       # MJ per % per tonne of ship
const HEAT_WARN := 80.0           # above this a module loses output
const HEAT_CRIT := 100.0          # above this a module takes damage

const DIRS := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0)]
const DIR_NAMES := ["Forward (-Z)", "Back (+Z)", "Right (+X)", "Left (-X)", "Up (+Y)", "Down (-Y)"]
const DIR_AXIS := [2, 2, 0, 0, 1, 1]
const WEAPONS := ["kinetic", "laser", "missile"]

# face: which side of the module must touch open space (+1 = along dir, -1 = opposite, 0 = none)
const MODULES := {
	"commander_post": {"label": "Commander Post", "kind": "external", "min": Vector3(1.6, 1.6, 2.0), "density": 0.5, "cost": 7.0, "idle": 0.5, "hp": 0.8, "face": 1, "color": Color(0.35, 0.8, 1.0)},
	"generator": {"label": "Generator", "kind": "internal", "min": Vector3(2, 2, 2), "density": 1.0, "cost": 3.5, "idle": 0.0, "hp": 1.0, "face": 0, "color": Color(1.0, 0.85, 0.25)},
	"engine_room": {"label": "Engine Room", "kind": "internal", "min": Vector3(2.5, 2, 3), "density": 0.8, "cost": 2.5, "idle": 2.0, "hp": 1.2, "face": 0, "color": Color(1.0, 0.55, 0.2)},
	"turret_bay": {"label": "Turret Bay", "kind": "external", "min": Vector3(2.0, 1.2, 2.0), "density": 0.9, "cost": 4.0, "idle": 1.5, "hp": 1.0, "face": 1, "color": Color(0.9, 0.3, 0.3)},
	"turret_control": {"label": "Turret Control", "kind": "internal", "min": Vector3(2.0, 1.5, 2.0), "density": 0.7, "cost": 3.0, "idle": 1.2, "hp": 1.0, "face": 0, "color": Color(0.9, 0.5, 0.6)},
	"radar_room": {"label": "Radar Room", "kind": "internal", "min": Vector3(2, 2, 2), "density": 0.5, "cost": 3.0, "idle": 3.0, "hp": 0.7, "face": 0, "color": Color(0.5, 1.0, 0.5)},
	"thruster": {"label": "Thruster", "kind": "external", "min": Vector3(1, 1, 2), "density": 0.6, "cost": 4.5, "idle": 0.0, "hp": 0.8, "face": -1, "color": Color(1.0, 0.7, 0.2)},
	"barrel": {"label": "Barrel", "kind": "external", "min": Vector3(0.5, 0.5, 2.5), "density": 1.2, "cost": 5.0, "idle": 0.0, "hp": 0.9, "face": 1, "color": Color(0.8, 0.8, 0.85)},
}
## Turret Bay (external): rotates the barrels that physically touch it. Turret Control (internal): links to any
## barrel, but those barrels stay fixed.
const LINK_RULES := {"commander_post": ["engine_room", "turret_control", "turret_bay", "radar_room"], "engine_room": ["thruster"], "turret_bay": ["barrel"], "turret_control": ["barrel"]}
const OVERLAP_OK := [["turret_bay", "barrel"], ["engine_room", "thruster"], ["engine_room", "generator"]]

const CLASSES := [
	{"name": "Drone / Pod", "max": 15.0}, {"name": "Fighter", "max": 40.0}, {"name": "Corvette", "max": 120.0},
	{"name": "Frigate", "max": 400.0}, {"name": "Destroyer", "max": 1200.0}, {"name": "Cruiser", "max": 4000.0},
	{"name": "Battleship", "max": 20000.0}, {"name": "Titan", "max": 100000.0},
]
const TRI_BUDGET := [600, 1200, 3000, 6000, 12000, 24000, 48000, 96000]


# ------------------------------------------------------------------ basics
static func v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func a3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func col(a) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))


static func make_ring(z: float, w: float, h: float) -> Dictionary:
	var pts := [[0.0, h], [w * 0.7, h * 0.7], [w, 0.0], [w * 0.7, -h * 0.7], [0.0, -h], [-w * 0.7, -h * 0.7], [-w, 0.0], [-w * 0.7, h * 0.7]]
	return {"z": z, "pts": pts}


static func mirror_idx(i: int) -> int:
	return (RING_PTS - i) % RING_PTS


static func new_blueprint(ship_name: String) -> Dictionary:
	return {
		"version": 1, "name": ship_name, "author": "", "thickness": 0.12,
		"color": [0.55, 0.58, 0.65], "accent": [0.25, 0.6, 0.95],
		"rings": [make_ring(-9, 1.6, 1.2), make_ring(-5, 2.6, 1.9), make_ring(4, 3.0, 2.0), make_ring(9, 2.2, 1.6)],
		"modules": [], "links": [], "next_id": 1,
	}


## JSON loads every number as float: restore the integer fields.
static func normalize(bp: Dictionary) -> Dictionary:
	bp["next_id"] = int(bp.get("next_id", 1))
	for m in bp.get("modules", []):
		m["id"] = int(m["id"])
		m["dir"] = int(m.get("dir", 0))
		m["weapon"] = String(m.get("weapon", "kinetic"))
		bp["next_id"] = maxi(int(bp["next_id"]), int(m["id"]) + 1)
	var links: Array = []
	for l in bp.get("links", []):
		links.append([int(l[0]), int(l[1])])
	bp["links"] = links
	return bp


static func get_module(bp: Dictionary, id: int) -> Dictionary:
	for m in bp["modules"]:
		if int(m["id"]) == id:
			return m
	return {}


static func add_module(bp: Dictionary, type: String, pos: Vector3, size := Vector3.ZERO, dir := 0, weapon := "kinetic") -> int:
	var mn: Vector3 = MODULES[type]["min"]
	if size == Vector3.ZERO:
		size = mn * 1.25
	size = Vector3(maxf(size.x, mn.x), maxf(size.y, mn.y), maxf(size.z, mn.z))
	var id := int(bp["next_id"])
	bp["next_id"] = id + 1
	bp["modules"].append({"id": id, "type": type, "pos": a3(pos), "size": a3(size), "dir": dir, "weapon": weapon})
	return id


static func remove_module(bp: Dictionary, id: int) -> void:
	for i in range(bp["modules"].size()):
		if int(bp["modules"][i]["id"]) == id:
			bp["modules"].remove_at(i)
			break
	var keep: Array = []
	for l in bp["links"]:
		if l[0] != id and l[1] != id:
			keep.append(l)
	bp["links"] = keep


static func link_allowed(ta: String, tb: String) -> bool:
	return (LINK_RULES.has(ta) and tb in LINK_RULES[ta]) or (LINK_RULES.has(tb) and ta in LINK_RULES[tb])


static func touching(a: Dictionary, b: Dictionary) -> bool:
	return module_box(a).grow(0.06).intersects(module_box(b))


static func has_link(bp: Dictionary, a: int, b: int) -> bool:
	for l in bp["links"]:
		if (l[0] == a and l[1] == b) or (l[0] == b and l[1] == a):
			return true
	return false


static func add_link(bp: Dictionary, a: int, b: int) -> bool:
	var ma := get_module(bp, a)
	var mb := get_module(bp, b)
	if ma.is_empty() or mb.is_empty() or a == b or has_link(bp, a, b):
		return false
	if not link_allowed(ma["type"], mb["type"]):
		return false
	var pair := [ma["type"], mb["type"]]
	if "turret_bay" in pair and "barrel" in pair and not touching(ma, mb):
		return false
	bp["links"].append([a, b])
	return true


static func remove_link(bp: Dictionary, a: int, b: int) -> void:
	var keep: Array = []
	for l in bp["links"]:
		if not ((l[0] == a and l[1] == b) or (l[0] == b and l[1] == a)):
			keep.append(l)
	bp["links"] = keep


static func linked_ids(bp: Dictionary, id: int, of_type := "") -> Array:
	var out: Array = []
	for l in bp["links"]:
		var other := -1
		if l[0] == id:
			other = l[1]
		elif l[1] == id:
			other = l[0]
		if other >= 0:
			if of_type == "" or get_module(bp, other).get("type", "") == of_type:
				out.append(other)
	return out


## Link every thruster to its nearest engine room, every barrel to the Turret Bay it touches (else the nearest
## Turret Control), and the commander posts to every control target.
static func auto_link(bp: Dictionary) -> void:
	bp["links"] = []
	for m in bp["modules"]:
		if m["type"] == "thruster":
			var best := -1
			var bd := INF
			for o in bp["modules"]:
				if o["type"] == "engine_room":
					var d := v3(o["pos"]).distance_to(v3(m["pos"]))
					if d < bd:
						bd = d
						best = int(o["id"])
			if best >= 0:
				add_link(bp, int(m["id"]), best)
		elif m["type"] == "barrel":
			var best_bay := -1
			var bd2 := INF
			for o in bp["modules"]:
				if o["type"] == "turret_bay" and touching(o, m):
					var d2 := v3(o["pos"]).distance_to(v3(m["pos"]))
					if d2 < bd2:
						bd2 = d2
						best_bay = int(o["id"])
			if best_bay < 0:
				for o in bp["modules"]:
					if o["type"] == "turret_control":
						var d3 := v3(o["pos"]).distance_to(v3(m["pos"]))
						if d3 < bd2:
							bd2 = d3
							best_bay = int(o["id"])
			if best_bay >= 0:
				add_link(bp, int(m["id"]), best_bay)
	for cp in bp["modules"]:
		if cp["type"] == "commander_post":
			for o in bp["modules"]:
				if o["type"] in ["engine_room", "turret_control", "turret_bay", "radar_room"]:
					add_link(bp, int(cp["id"]), int(o["id"]))


static func scale_ship(bp: Dictionary, s: float, scale_modules := false) -> void:
	for r in bp["rings"]:
		r["z"] = float(r["z"]) * s
		for p in r["pts"]:
			p[0] = float(p[0]) * s
			p[1] = float(p[1]) * s
	for m in bp["modules"]:
		m["pos"] = a3(v3(m["pos"]) * s)
		if scale_modules:
			m["size"] = a3(v3(m["size"]) * s)


static func mirrored_copy(bp: Dictionary, id: int) -> int:
	var m := get_module(bp, id)
	if m.is_empty():
		return -1
	var p := v3(m["pos"])
	var d: int = m["dir"]
	if d == 2:
		d = 3
	elif d == 3:
		d = 2
	return add_module(bp, m["type"], Vector3(-p.x, p.y, p.z), v3(m["size"]), d, m["weapon"])


# ------------------------------------------------------------------ hull geometry
static func ring_pts_at(rings: Array, z: float) -> PackedVector2Array:
	var n := rings.size()
	if n < 2:
		return PackedVector2Array()
	if z < float(rings[0]["z"]) - 1e-4 or z > float(rings[n - 1]["z"]) + 1e-4:
		return PackedVector2Array()
	for i in range(n - 1):
		var z0: float = rings[i]["z"]
		var z1: float = rings[i + 1]["z"]
		if z <= z1 + 1e-6:
			var t := 0.0 if z1 - z0 < 1e-6 else clampf((z - z0) / (z1 - z0), 0.0, 1.0)
			var out := PackedVector2Array()
			for p in RING_PTS:
				var a: Array = rings[i]["pts"][p]
				var b: Array = rings[i + 1]["pts"][p]
				out.append(Vector2(lerpf(float(a[0]), float(b[0]), t), lerpf(float(a[1]), float(b[1]), t)))
			return out
	return PackedVector2Array()


static func hull_contains(rings: Array, p: Vector3) -> bool:
	var poly := ring_pts_at(rings, p.z)
	if poly.is_empty():
		return false
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.y), poly)


static func ring_center(r: Dictionary) -> Vector3:
	var c := Vector2.ZERO
	for p in r["pts"]:
		c += Vector2(float(p[0]), float(p[1]))
	c /= float(RING_PTS)
	return Vector3(c.x, c.y, float(r["z"]))


static func ring_vertex(r: Dictionary, i: int) -> Vector3:
	return Vector3(float(r["pts"][i][0]), float(r["pts"][i][1]), float(r["z"]))


## Triangles of the closed hull skin (sides + two fan caps). Winding is fixed so the skin is
## front-facing for Godot (clockwise seen from outside).
static func hull_triangles(rings: Array) -> Array:
	var tris: Array = []
	var n := rings.size()
	if n < 2:
		return tris
	for i in range(n - 1):
		for p in RING_PTS:
			var q := (p + 1) % RING_PTS
			var a := ring_vertex(rings[i], p)
			var b := ring_vertex(rings[i], q)
			var c := ring_vertex(rings[i + 1], p)
			var d := ring_vertex(rings[i + 1], q)
			tris.append([a, b, c])
			tris.append([b, d, c])
	for end in [0, n - 1]:
		var c := ring_center(rings[end])
		for p in RING_PTS:
			tris.append([c, ring_vertex(rings[end], p), ring_vertex(rings[end], (p + 1) % RING_PTS)])
	var vol := 0.0
	for t in tris:
		vol += (t[0] as Vector3).dot((t[1] as Vector3).cross(t[2])) / 6.0
	if vol > 0.0:
		for t in tris:
			var tmp: Vector3 = t[1]
			t[1] = t[2]
			t[2] = tmp
	return tris


## Identical modules do not run equally hot: a fixed factor per module (0.75 .. 1.25) from its id and type.
static func thermal_factor(id: int, type: String) -> float:
	return 0.75 + 0.5 * fposmod(sin(float(id) * 12.9898 + float(type.hash() % 1000) * 0.137) * 43758.5453, 1.0)


static func module_surface(sz: Vector3) -> float:
	return 2.0 * (sz.x * sz.y + sz.y * sz.z + sz.x * sz.z)


## Output multiplier of a module at temperature t (full up to HEAT_WARN, 40% at 110).
static func heat_factor(t: float) -> float:
	return clampf(1.0 - (t - HEAT_WARN) / 30.0 * 0.6, 0.4, 1.0)


## Blue (cold) -> green -> yellow -> orange -> red (critical).
static func heat_color(t: float) -> Color:
	var k := clampf(t / HEAT_CRIT, 0.0, 1.2)
	var stops := [[0.0, Color(0.15, 0.35, 0.85)], [0.35, Color(0.2, 0.8, 0.5)], [0.65, Color(1.0, 0.82, 0.15)], [0.85, Color(1.0, 0.4, 0.08)], [1.0, Color(0.95, 0.08, 0.04)], [1.2, Color(1.0, 0.85, 0.8)]]
	for i in range(stops.size() - 1):
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if k <= float(b[0]):
			return (a[1] as Color).lerp(b[1], (k - float(a[0])) / (float(b[0]) - float(a[0])))
	return stops[stops.size() - 1][1]


static func tri_area(t: Array) -> float:
	return 0.5 * ((t[1] as Vector3) - (t[0] as Vector3)).cross((t[2] as Vector3) - (t[0] as Vector3)).length()


static func build_hull_mesh(rings: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var tris := hull_triangles(rings)
	if tris.is_empty():
		return mesh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for t in tris:
		var n: Vector3 = -((t[1] as Vector3) - (t[0] as Vector3)).cross((t[2] as Vector3) - (t[0] as Vector3))
		n = n.normalized() if n.length() > 1e-9 else Vector3.UP
		for k in 3:
			verts.append(t[k])
			norms.append(n)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## One convex point cloud per hull segment (compound convex collision, GDD section 7).
static func hull_convex_parts(rings: Array) -> Array:
	var parts: Array = []
	for i in range(rings.size() - 1):
		var pts := PackedVector3Array()
		for p in RING_PTS:
			pts.append(ring_vertex(rings[i], p))
			pts.append(ring_vertex(rings[i + 1], p))
		parts.append(pts)
	return parts


static func hull_area(rings: Array) -> float:
	var a := 0.0
	for t in hull_triangles(rings):
		a += tri_area(t)
	return a


static func hull_bounds(rings: Array) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for r in rings:
		for i in RING_PTS:
			var v := ring_vertex(r, i)
			mn = mn.min(v)
			mx = mx.max(v)
	if mn.x == INF:
		return AABB()
	return AABB(mn, mx - mn)


# ------------------------------------------------------------------ modules
static func module_box(m: Dictionary) -> AABB:
	var s := v3(m["size"])
	return AABB(v3(m["pos"]) - s * 0.5, s)


static func module_volume(m: Dictionary) -> float:
	var s := v3(m["size"])
	return s.x * s.y * s.z


## Barrel geometry: length along the mount direction, caliber = mean of the other two sides.
static func barrel_dims(m: Dictionary) -> Vector2:
	var s := v3(m["size"])
	var ax: int = DIR_AXIS[int(m["dir"])]
	var length := s[ax]
	var others := 0.0
	for i in 3:
		if i != ax:
			others += s[i]
	return Vector2(length, others * 0.5)


static func weapon_stats(m: Dictionary) -> Dictionary:
	var cal := barrel_dims(m).y
	match String(m.get("weapon", "kinetic")):
		"laser":
			return {"kind": "laser", "damage": 90.0 * cal * cal, "pen": 0.5, "speed": 0.0, "interval": 0.15, "range": 3000.0, "power": 40.0 * cal * cal, "radius": 0.0, "cost_mult": 1.8, "ammo": -1}
		"missile":
			return {"kind": "missile", "damage": 900.0 * cal * cal, "pen": 3.0 * cal, "speed": 160.0, "interval": 1.5 + cal, "range": 3500.0, "power": 4.0 * cal * cal, "radius": 6.0 * cal, "cost_mult": 1.4, "ammo": 6}
		_:
			return {"kind": "kinetic", "damage": 600.0 * cal * cal, "pen": 2.2 * cal, "speed": 700.0, "interval": 0.25 + 1.2 * cal, "range": 2500.0, "power": 20.0 * cal * cal, "radius": 0.0, "cost_mult": 1.0, "ammo": -1}


static func module_stats(m: Dictionary) -> Dictionary:
	var t: String = m["type"]
	var def: Dictionary = MODULES[t]
	var vol := module_volume(m)
	var st := {
		"volume": vol, "hp": 60.0 * pow(vol, 0.8) * float(def["hp"]), "mass": vol * float(def["density"]),
		"cost": float(def["cost"]) * pow(vol, 0.85), "idle": float(def["idle"]) * sqrt(vol / 8.0),
		"out": 0.0, "peak": 0.0, "thrust": 0.0, "capacity": 0.0,
	}
	match t:
		"generator":
			st["out"] = GENERATOR_MW_PER_M3 * vol
		"thruster":
			st["thrust"] = THRUST_KN_PER_M3 * vol
			st["peak"] = THRUSTER_MW_PER_M3 * vol
		"engine_room":
			st["capacity"] = 0.5 * vol
		"barrel":
			var w := weapon_stats(m)
			st["peak"] = w["power"]
			st["cost"] = float(st["cost"]) * float(w["cost_mult"])
	return st


## Engine room that feeds this thruster (-1 if none) and the efficiency it provides.
static func thruster_engine(bp: Dictionary, thruster_id: int) -> int:
	var l := linked_ids(bp, thruster_id, "engine_room")
	return int(l[0]) if not l.is_empty() else -1


static func engine_factor(bp: Dictionary, engine_id: int) -> float:
	var e := get_module(bp, engine_id)
	if e.is_empty():
		return 0.0
	var load := 0.0
	for tid in linked_ids(bp, engine_id, "thruster"):
		load += module_volume(get_module(bp, tid))
	if load <= 0.0:
		return 1.0
	return clampf(float(module_stats(e)["capacity"]) / load, 0.0, 1.0)


static func class_tier(longest: float) -> int:
	for i in range(CLASSES.size()):
		if longest <= float(CLASSES[i]["max"]):
			return i + 1
	return CLASSES.size()


static func compute_stats(bp: Dictionary) -> Dictionary:
	var rings: Array = bp["rings"]
	var bounds := hull_bounds(rings)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var thickness: float = bp.get("thickness", 0.12)
	var tris := hull_triangles(rings)
	var area := 0.0
	var hull_com := Vector3.ZERO
	for t in tris:
		var a := tri_area(t)
		area += a
		hull_com += a * ((t[0] as Vector3) + (t[1] as Vector3) + (t[2] as Vector3)) / 3.0
	if area > 0.0:
		hull_com /= area
	var hull_mass := area * thickness * ARMOR_DENSITY
	var mass := hull_mass
	var com_sum := hull_com * hull_mass
	var cost := area * (0.05 + thickness * 0.6)
	var p_out := 0.0
	var p_idle := 0.0
	var p_peak := 0.0
	var thrust := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for m in bp["modules"]:
		var ms := module_stats(m)
		mass += float(ms["mass"])
		com_sum += v3(m["pos"]) * float(ms["mass"])
		cost += float(ms["cost"])
		p_out += float(ms["out"])
		p_idle += float(ms["idle"])
		p_peak += float(ms["peak"])
		if m["type"] == "thruster":
			var eid := thruster_engine(bp, int(m["id"]))
			if eid >= 0:
				thrust[int(m["dir"])] += float(ms["thrust"]) * engine_factor(bp, eid)
	var tier := class_tier(longest)
	var best := 0.0
	for t in thrust:
		best = maxf(best, t)
	var served_hard := minf(p_out, p_idle + 0.5 * p_peak)
	var radiate := maxf(HEAT_RAD * area, 0.001)
	return {
		"heat_idle": minf(p_idle, p_out) * (HEAT_WASTE + GEN_WASTE) / radiate,
		"heat_hard": served_hard * (HEAT_WASTE + GEN_WASTE) / radiate,
		"length": bounds.size.z, "beam": bounds.size.x, "height": bounds.size.y, "longest": longest,
		"area": area, "thickness": thickness, "armor": thickness * ARMOR_PROTECTION,
		"hull_hp": area * thickness * HULL_HP_PER_M3, "hull_mass": hull_mass,
		"mass": mass, "com": com_sum / maxf(mass, 0.001), "cost": cost,
		"tier": tier, "class": CLASSES[tier - 1]["name"],
		"power_out": p_out, "power_idle": p_idle, "power_peak": p_peak,
		"thrust": thrust, "thrust_best": best, "rcs": best * RCS_FRACTION,
		"accel_fwd": float(thrust[0]) / maxf(mass, 0.001),
		"gyro": clampf(GYRO_K / maxf(mass, 0.001), 0.25, 3.0),
		"tris": tris.size() + bp["modules"].size() * 12, "tri_budget": TRI_BUDGET[tier - 1],
	}


# ------------------------------------------------------------------ legality
static func _corners(box: AABB) -> Array:
	var out: Array = []
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				out.append(box.position + box.size * Vector3(x, y, z))
	return out


static func placement_ok(bp: Dictionary, m: Dictionary) -> String:
	var rings: Array = bp["rings"]
	var def: Dictionary = MODULES[m["type"]]
	var inside := 0
	for c in _corners(module_box(m)):
		if hull_contains(rings, c):
			inside += 1
	if def["kind"] == "internal":
		return "" if inside == 8 else "must be fully inside the hull (Not Placeable Here)"
	if m["type"] == "barrel":
		for bid in linked_ids(bp, int(m["id"]), "turret_bay"):
			if touching(get_module(bp, int(bid)), m):
				var dv0: Vector3 = DIRS[int(m["dir"])]
				var half0 := v3(m["size"])[DIR_AXIS[int(m["dir"])]] * 0.5
				if hull_contains(rings, v3(m["pos"]) + dv0 * (half0 + 0.02)):
					return "its muzzle is still inside the hull"
				return ""
	if inside == 0:
		return "must be anchored to the hull (no part inside)"
	if inside == 8:
		return "needs exposure to space (fully buried)"
	var face := int(def["face"])
	if face != 0:
		var dv: Vector3 = DIRS[int(m["dir"])]
		var half := v3(m["size"])[DIR_AXIS[int(m["dir"])]] * 0.5
		var fp := v3(m["pos"]) + dv * float(face) * (half + 0.02)
		if hull_contains(rings, fp):
			return "its exposed face (nozzle / muzzle / viewport) is still inside the hull"
	return ""


static func _overlap_allowed(ta: String, tb: String) -> bool:
	for p in OVERLAP_OK:
		if (p[0] == ta and p[1] == tb) or (p[0] == tb and p[1] == ta):
			return true
	return false


## Returns Array of {"msg": String, "mod": int}. Empty array = legal (everything green).
static func validate(bp: Dictionary, ctx := {}) -> Array:
	var issues: Array = []
	var rings: Array = bp["rings"]
	if rings.size() < 2:
		issues.append({"msg": "Hull needs at least 2 rings", "mod": -1})
		return issues
	for i in range(rings.size() - 1):
		if float(rings[i + 1]["z"]) - float(rings[i]["z"]) < MIN_RING_GAP - 1e-4:
			issues.append({"msg": "Rings %d and %d are too close" % [i + 1, i + 2], "mod": -1})
	for i in range(rings.size()):
		var poly := PackedVector2Array()
		for p in rings[i]["pts"]:
			poly.append(Vector2(float(p[0]), float(p[1])))
		var area := 0.0
		for k in range(poly.size()):
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			area += a.x * b.y - b.x * a.y
		if absf(area) * 0.5 < 0.05:
			issues.append({"msg": "Ring %d has no cross-section" % (i + 1), "mod": -1})
	var th: float = bp.get("thickness", 0.12)
	if th < 0.02 or th > 2.0:
		issues.append({"msg": "Hull thickness out of range", "mod": -1})
	var counts := {}
	for m in bp["modules"]:
		counts[m["type"]] = int(counts.get(m["type"], 0)) + 1
		var def: Dictionary = MODULES[m["type"]]
		var mn: Vector3 = def["min"]
		var s := v3(m["size"])
		if s.x < mn.x - 1e-4 or s.y < mn.y - 1e-4 or s.z < mn.z - 1e-4:
			issues.append({"msg": "%s #%d is below its minimum size" % [def["label"], m["id"]], "mod": int(m["id"])})
		var why := placement_ok(bp, m)
		if why != "":
			issues.append({"msg": "%s #%d %s" % [def["label"], m["id"], why], "mod": int(m["id"])})
	var mods: Array = bp["modules"]
	for i in range(mods.size()):
		for j in range(i + 1, mods.size()):
			if _overlap_allowed(mods[i]["type"], mods[j]["type"]):
				continue
			if module_box(mods[i]).grow(-0.01).intersects(module_box(mods[j])):
				issues.append({"msg": "%s #%d overlaps %s #%d" % [MODULES[mods[i]["type"]]["label"], mods[i]["id"], MODULES[mods[j]["type"]]["label"], mods[j]["id"]], "mod": int(mods[i]["id"])})
	if int(counts.get("commander_post", 0)) == 0:
		issues.append({"msg": "Needs at least one Commander Post", "mod": -1})
	if int(counts.get("generator", 0)) == 0:
		issues.append({"msg": "Needs at least one Generator", "mod": -1})
	if int(counts.get("engine_room", 0)) == 0 or int(counts.get("thruster", 0)) == 0:
		issues.append({"msg": "Needs an Engine Room and at least one Thruster", "mod": -1})
	for m in mods:
		var id := int(m["id"])
		match m["type"]:
			"thruster":
				if thruster_engine(bp, id) < 0:
					issues.append({"msg": "Thruster #%d is not linked to an Engine Room" % id, "mod": id})
			"barrel":
				var bays := linked_ids(bp, id, "turret_bay")
				var ctrls := linked_ids(bp, id, "turret_control")
				if bays.is_empty() and ctrls.is_empty():
					issues.append({"msg": "Barrel #%d is not linked to a Turret Bay or Turret Control" % id, "mod": id})
				for bid in bays:
					if not touching(get_module(bp, int(bid)), m):
						issues.append({"msg": "Barrel #%d must touch its Turret Bay #%d" % [id, bid], "mod": id})
			"engine_room", "turret_bay", "turret_control":
				if linked_ids(bp, id, "commander_post").is_empty():
					issues.append({"msg": "%s #%d has no Commander Post link" % [MODULES[m["type"]]["label"], id], "mod": id})
	var st := compute_stats(bp)
	if float(st["power_idle"]) > float(st["power_out"]):
		issues.append({"msg": "Idle power draw (%.0f MW) exceeds generation (%.0f MW)" % [st["power_idle"], st["power_out"]], "mod": -1})
	if int(st["tris"]) > int(st["tri_budget"]):
		issues.append({"msg": "Polygon budget exceeded (%d / %d)" % [st["tris"], st["tri_budget"]], "mod": -1})
	if ctx.has("max_tier") and int(st["tier"]) > int(ctx["max_tier"]):
		issues.append({"msg": "Class %s is not allowed on the selected map" % st["class"], "mod": -1})
	if ctx.has("budget") and float(st["cost"]) > float(ctx["budget"]):
		issues.append({"msg": "Costs %.0f pts, team budget is %.0f" % [st["cost"], ctx["budget"]], "mod": -1})
	return issues
