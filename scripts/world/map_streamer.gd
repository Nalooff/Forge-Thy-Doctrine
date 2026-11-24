class_name MapStreamer
extends Node3D
## Fills the space around the player with the objects of the map, chunk by chunk.
##
## The map is never stored. A chunk (a cube of CELL metres) is generated from the map definition and its integer
## coordinates alone, so it is identical every time and for every player, costs nothing when nobody is near, and a
## map of 1,000,000 km is no bigger than one of 100 km. Visuals are one MultiMesh per kind per chunk (a few draw
## calls for thousands of rocks); a chunk only gets physics shapes when the player is within COLLIDE_R cells.
## Chunk nodes hold small coordinates relative to the floating origin and are moved back when the origin shifts.

const CELL := 5000.0
const LOAD_R := 3.0               # chunks loaded within this many cells
const COLLIDE_R := 1.5            # chunks that get collision shapes
const MAX_PER_CELL := 500

var ws: WorldSpace
var def: Dictionary
var chunks := {}                  # Vector3i -> {node, objs, body}
var _meshes := {}
var _mats := {}
var generated := 0


func setup(p_ws: WorldSpace, p_def: Dictionary) -> void:
	ws = p_ws
	def = p_def
	add_to_group("no_shift")
	ws.shifted.connect(_on_shifted)
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 10
	sph.rings = 5
	_meshes["rock"] = sph
	_meshes["ice"] = sph
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for k in ["shard", "monolith", "wreck", "lattice"]:
		_meshes[k] = box
	for k in _meshes.keys():
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		if k == "shard":
			m.emission_enabled = true
			m.emission = Color(0.12, 0.2, 0.3)
		if k == "ice":
			m.roughness = 0.35
		_mats[k] = m


func _on_shifted(delta: Vector3) -> void:
	for ch in chunks.values():
		(ch["node"] as Node3D).position -= delta


static func chunk_seed(d: Dictionary, key: Vector3i) -> int:
	return (int(d["seed"]) ^ (key.x * 73856093) ^ (key.y * 19349663) ^ (key.z * 83492791)) & 0x7fffffff


static func _lattice_hash(seed_v: int, i: int, j: int, k: int, axis: int) -> float:
	var h := (seed_v ^ (i * 374761393) ^ (j * 668265263) ^ (k * 2147483647) ^ (axis * 1274126177)) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float(h % 10000) / 10000.0


## Everything of one chunk, relative to the chunk's minimum corner: [{kind, pos, scale, basis, color}]
static func chunk_objects(d: Dictionary, key: Vector3i) -> Array:
	var origin := Vec3D.make(key.x * CELL, key.y * CELL, key.z * CELL)
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_seed(d, key)
	var out: Array = []
	var keep_out := MapDefs.keep_out(d)
	var cell_km := CELL / 1000.0
	for f in d["fields"]:
		var kind: String = f["kind"]
		var mask: Dictionary = f["mask"]
		if kind == "lattice":
			var sp: float = f["spacing"]
			var i0 := int(ceil(origin.x / sp))
			var j0 := int(ceil(origin.y / sp))
			var k0 := int(ceil(origin.z / sp))
			var i := i0
			while float(i) * sp < origin.x + CELL:
				var j := j0
				while float(j) * sp < origin.y + CELL:
					var k := k0
					while float(k) * sp < origin.z + CELL:
						var node := Vec3D.make(float(i) * sp, float(j) * sp, float(k) * sp)
						if MapDefs.mask_value(mask, node) > 0.0:
							for axis in 3:
								if _lattice_hash(int(d["seed"]), i, j, k, axis) < 0.38 and out.size() < MAX_PER_CELL:
									var th := lerpf(float(f["rmin"]), float(f["rmax"]), _lattice_hash(int(d["seed"]) + 7, i, j, k, axis))
									var sc := Vector3(th, th, th)
									sc[axis] = sp
									var cen := node.minus(origin)
									cen[axis] += sp * 0.5
									out.append({"kind": kind, "pos": cen, "scale": sc, "basis": Basis.IDENTITY, "color": f["color"]})
						k += 1
					j += 1
				i += 1
			continue
		var expected := float(f["density"]) * cell_km * cell_km * cell_km
		var n := int(floor(expected)) + (1 if rng.randf() < expected - floor(expected) else 0)
		for _i in range(n):
			var off := Vector3(rng.randf() * CELL, rng.randf() * CELL, rng.randf() * CELL)
			var m := MapDefs.mask_value(mask, origin.plus(off))
			var roll := rng.randf()
			var r := lerpf(float(f["rmin"]), float(f["rmax"]), pow(rng.randf(), 2.2))
			var rot := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			var sa := rng.randf_range(0.7, 1.4)
			var sb := rng.randf_range(0.6, 1.1)
			var sc2 := rng.randf_range(0.7, 1.4)
			var tint := rng.randf_range(0.8, 1.15)
			if roll > m:
				continue
			var pa := origin.plus(off)
			var blocked := false
			for ko in keep_out:
				if Vector3(pa.x - ko[0], pa.y - ko[1], pa.z - ko[2]).length() < float(ko[3]) + r:
					blocked = true
			if blocked:
				continue
			var scale := Vector3(r * sa, r * sb, r * sc2)
			var basis := rot
			match kind:
				"shard":
					scale = Vector3(r * 0.35, r * 1.6, r * 0.35)
				"monolith":
					scale = Vector3(r * 0.35 * sa, r * 5.0, r * 0.35 * sc2)
					basis = Basis(Vector3.UP, rng.randf() * TAU)
				"wreck":
					scale = Vector3(r * sa * 1.6, r * sb * 0.7, r * sc2 * 3.0)
			var c: Color = f["color"]
			out.append({"kind": kind, "pos": off, "scale": scale, "basis": basis, "color": Color(c.r * tint, c.g * tint, c.b * tint)})
			if out.size() >= MAX_PER_CELL:
				return out
	return out


func chunk_count() -> int:
	return chunks.size()


func object_count() -> int:
	var n := 0
	for ch in chunks.values():
		n += (ch["objs"] as Array).size()
	return n


func collider_count() -> int:
	var n := 0
	for ch in chunks.values():
		if ch["body"] != null:
			n += 1
	return n


func _load_chunk(key: Vector3i) -> void:
	var objs := chunk_objects(def, key)
	generated += 1
	var node := Node3D.new()
	node.position = ws.to_local(Vec3D.make(key.x * CELL, key.y * CELL, key.z * CELL))
	add_child(node)
	var by_kind := {}
	for o in objs:
		if not by_kind.has(o["kind"]):
			by_kind[o["kind"]] = []
		(by_kind[o["kind"]] as Array).append(o)
	for kind in by_kind.keys():
		var list: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _meshes[kind]
		mm.instance_count = list.size()
		for i in range(list.size()):
			var o: Dictionary = list[i]
			mm.set_instance_transform(i, Transform3D((o["basis"] as Basis).scaled(o["scale"]), o["pos"]))
			mm.set_instance_color(i, o["color"])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mats[kind]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	chunks[key] = {"node": node, "objs": objs, "body": null}


func _make_body(ch: Dictionary) -> void:
	var body := StaticBody3D.new()
	for o in ch["objs"]:
		var cs := CollisionShape3D.new()
		var sc: Vector3 = o["scale"]
		if o["kind"] == "rock" or o["kind"] == "ice":
			var ss := SphereShape3D.new()
			ss.radius = maxf(sc.x, maxf(sc.y, sc.z)) * 0.85
			cs.shape = ss
			cs.position = o["pos"]
		else:
			var bs := BoxShape3D.new()
			bs.size = sc
			cs.shape = bs
			cs.transform = Transform3D(o["basis"], o["pos"])
		body.add_child(cs)
	(ch["node"] as Node3D).add_child(body)
	ch["body"] = body


func _drop_chunk(key: Vector3i) -> void:
	var ch: Dictionary = chunks[key]
	(ch["node"] as Node3D).queue_free()
	chunks.erase(key)


## Load what is near the focus, drop what is far. `budget` chunks are generated per call (use a big one at start).
func update(focus_abs: Vec3D, budget := 2) -> void:
	var c := Vector3i(floori(focus_abs.x / CELL), floori(focus_abs.y / CELL), floori(focus_abs.z / CELL))
	for k in chunks.keys():
		var d := Vector3(k - c).length()
		if d > LOAD_R + 1.0:
			_drop_chunk(k)
	var want: Array = []
	var r := int(ceil(LOAD_R))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var d2 := Vector3(dx, dy, dz).length()
				if d2 <= LOAD_R:
					var key := c + Vector3i(dx, dy, dz)
					if not chunks.has(key):
						want.append([d2, key])
	want.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in range(mini(budget, want.size())):
		_load_chunk(want[i][1])
	for k in chunks.keys():
		var ch: Dictionary = chunks[k]
		var dd := Vector3(k - c).length()
		if dd <= COLLIDE_R and ch["body"] == null and not (ch["objs"] as Array).is_empty():
			_make_body(ch)
		elif dd > COLLIDE_R + 0.6 and ch["body"] != null:
			(ch["body"] as Node).queue_free()
			ch["body"] = null
