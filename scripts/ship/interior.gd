class_name Interior
extends RefCounted
## Step 4 of the Ship Forge (GDD "Module Link / Interior"): entrances on the internal modules and the
## corridors that join them.
##
## Data lives in bp["interior"]:
##   entrances: [{id, module, face (0..5, ShipData.DIRS), u, v (-1..1 across the face)}]
##   corridors: [{id, a, b (entrance ids), pts (bend points, world/ship space), w (width factor per segment),
##                doors [[segment, t], ...]}]
## The full path of a corridor is  entrance A, its stub, the bend points, the stub of B, entrance B  (see polyline()).
## A path must stay inside the hull and may not cut through modules. A steep segment becomes a slope, then
## stairs, then a ladder (seg_kind()).

const KIND_NAMES := ["Corridor", "Slope", "Stairs", "Ladder"]
const KIND_COLORS := [Color(0.35, 0.8, 0.85), Color(0.95, 0.85, 0.3), Color(1.0, 0.55, 0.15), Color(0.95, 0.25, 0.2)]
const WIDTHS := [1.0, 1.5, 2.0, 3.0]          # width factors a segment can be widened to (3 = a room)
const SLOPE_DEG := 12.0
const STAIRS_DEG := 32.0
const LADDER_DEG := 58.0
const MAX_CELLS := 30000


# ================================================================== data
static func ensure(bp: Dictionary) -> Dictionary:
	if not bp.has("interior"):
		bp["interior"] = {"next_id": 1, "entrances": [], "corridors": []}
	return bp["interior"]


## JSON loads every number as float: restore the integer fields.
static func normalize(bp: Dictionary) -> void:
	var it := ensure(bp)
	it["next_id"] = int(it.get("next_id", 1))
	for e in it["entrances"]:
		e["id"] = int(e["id"])
		e["module"] = int(e["module"])
		e["face"] = int(e["face"])
		e["u"] = float(e.get("u", 0.0))
		e["v"] = float(e.get("v", 0.0))
		it["next_id"] = maxi(int(it["next_id"]), int(e["id"]) + 1)
	for c in it["corridors"]:
		c["id"] = int(c["id"])
		c["a"] = int(c["a"])
		c["b"] = int(c["b"])
		var pts: Array = []
		for p in c.get("pts", []):
			pts.append([float(p[0]), float(p[1]), float(p[2])])
		c["pts"] = pts
		var w: Array = []
		for f in c.get("w", []):
			w.append(float(f))
		c["w"] = w
		var doors: Array = []
		for d in c.get("doors", []):
			doors.append([int(d[0]), float(d[1])])
		c["doors"] = doors
		it["next_id"] = maxi(int(it["next_id"]), int(c["id"]) + 1)


## Drop entrances whose module is gone (or is not internal any more) and corridors that lost an entrance.
static func prune(bp: Dictionary) -> int:
	var it := ensure(bp)
	var removed := 0
	for e in it["entrances"].duplicate():
		var m := ShipData.get_module(bp, int(e["module"]))
		if m.is_empty() or String(ShipData.MODULES[String(m["type"])]["kind"]) != "internal":
			remove_entrance(bp, int(e["id"]))
			removed += 1
	for c in it["corridors"].duplicate():
		if entrance(bp, int(c["a"])).is_empty() or entrance(bp, int(c["b"])).is_empty():
			remove_corridor(bp, int(c["id"]))
			removed += 1
	return removed


static func entrances(bp: Dictionary) -> Array:
	return ensure(bp)["entrances"]


static func corridors(bp: Dictionary) -> Array:
	return ensure(bp)["corridors"]


static func entrance(bp: Dictionary, id: int) -> Dictionary:
	for e in entrances(bp):
		if int(e["id"]) == id:
			return e
	return {}


static func corridor(bp: Dictionary, id: int) -> Dictionary:
	for c in corridors(bp):
		if int(c["id"]) == id:
			return c
	return {}


static func longest(bp: Dictionary) -> float:
	var b := ShipData.hull_bounds(bp["rings"])
	return maxf(b.size.x, maxf(b.size.y, b.size.z))


## Width of a normal corridor: scales with the ship (0.9 m on a corvette up to 3 m on a capital ship).
static func base_width(bp: Dictionary) -> float:
	return clampf(longest(bp) * 0.06, 0.9, 3.0)


static func _tangents(axis: int) -> Array:
	return [(axis + 1) % 3, (axis + 2) % 3]


static func entrance_pos(bp: Dictionary, e: Dictionary) -> Vector3:
	var m := ShipData.get_module(bp, int(e["module"]))
	if m.is_empty():
		return Vector3.ZERO
	var half := ShipData.v3(m["size"]) * 0.5
	var f := int(e["face"])
	var ax: int = ShipData.DIR_AXIS[f]
	var t := _tangents(ax)
	var p := ShipData.v3(m["pos"]) + (ShipData.DIRS[f] as Vector3) * half[ax]
	p[t[0]] += float(e["u"]) * half[t[0]]
	p[t[1]] += float(e["v"]) * half[t[1]]
	return p


static func entrance_stub(bp: Dictionary, e: Dictionary) -> Vector3:
	return entrance_pos(bp, e) + (ShipData.DIRS[int(e["face"])] as Vector3) * base_width(bp) * 0.8


## Which face of a module a point on its surface belongs to, with the u / v offsets across that face.
static func face_at(m: Dictionary, p: Vector3) -> Dictionary:
	var half := ShipData.v3(m["size"]) * 0.5
	var d := p - ShipData.v3(m["pos"])
	var best_ax := 0
	var best := -1.0
	for ax in 3:
		var k := absf(d[ax]) / maxf(half[ax], 1e-6)
		if k > best:
			best = k
			best_ax = ax
	var face := 0
	match best_ax:
		0:
			face = 2 if d.x > 0.0 else 3
		1:
			face = 4 if d.y > 0.0 else 5
		2:
			face = 1 if d.z > 0.0 else 0
	var t := _tangents(best_ax)
	var u := clampf(d[t[0]] / maxf(half[t[0]], 1e-6), -0.85, 0.85)
	var v := clampf(d[t[1]] / maxf(half[t[1]], 1e-6), -0.85, 0.85)
	return {"face": face, "u": snappedf(u, 0.05), "v": snappedf(v, 0.05)}


static func _inside_other_module(bp: Dictionary, p: Vector3, grow: float) -> bool:
	for m in bp["modules"]:
		if ShipData.module_box(m).grow(grow).has_point(p):
			return true
	return false


static func add_entrance(bp: Dictionary, module_id: int, face: int, u: float, v: float) -> Dictionary:
	var m := ShipData.get_module(bp, module_id)
	if m.is_empty():
		return {"ok": false, "msg": "No such module."}
	if String(ShipData.MODULES[String(m["type"])]["kind"]) != "internal":
		return {"ok": false, "msg": "Entrances go on internal modules only."}
	var it := ensure(bp)
	var e := {"id": int(it["next_id"]), "module": module_id, "face": face, "u": clampf(u, -0.85, 0.85), "v": clampf(v, -0.85, 0.85)}
	var stub := entrance_stub(bp, e)
	if not ShipData.hull_contains(bp["rings"], stub):
		return {"ok": false, "msg": "That face is against the hull: no room for a corridor."}
	var r := base_width(bp) * 0.5
	for m2 in bp["modules"]:
		if int(m2["id"]) != module_id and ShipData.module_box(m2).grow(r * 0.5).has_point(stub):
			return {"ok": false, "msg": "Another module blocks that face."}
	var p := entrance_pos(bp, e)
	for o in it["entrances"]:
		if entrance_pos(bp, o).distance_to(p) < base_width(bp) * 1.1:
			return {"ok": false, "msg": "Too close to another entrance."}
	it["next_id"] = int(it["next_id"]) + 1
	it["entrances"].append(e)
	return {"ok": true, "id": int(e["id"])}


static func remove_entrance(bp: Dictionary, id: int) -> void:
	var it := ensure(bp)
	var keep: Array = []
	for c in it["corridors"]:
		if int(c["a"]) != id and int(c["b"]) != id:
			keep.append(c)
	it["corridors"] = keep
	var ke: Array = []
	for e in it["entrances"]:
		if int(e["id"]) != id:
			ke.append(e)
	it["entrances"] = ke


static func remove_corridor(bp: Dictionary, id: int) -> void:
	var it := ensure(bp)
	var keep: Array = []
	for c in it["corridors"]:
		if int(c["id"]) != id:
			keep.append(c)
	it["corridors"] = keep


static func on_module_removed(bp: Dictionary, module_id: int) -> void:
	var it := ensure(bp)
	for e in it["entrances"].duplicate():
		if int(e["module"]) == module_id:
			remove_entrance(bp, int(e["id"]))


static func scale(bp: Dictionary, s: float) -> void:
	for c in ensure(bp)["corridors"]:
		for p in c["pts"]:
			p[0] = float(p[0]) * s
			p[1] = float(p[1]) * s
			p[2] = float(p[2]) * s


static func entrance_used(bp: Dictionary, entrance_id: int) -> bool:
	for c in corridors(bp):
		if int(c["a"]) == entrance_id or int(c["b"]) == entrance_id:
			return true
	return false


# ================================================================== paths
## Full path: entrance A, stub A, bend points, stub B, entrance B.
static func polyline(bp: Dictionary, c: Dictionary) -> PackedVector3Array:
	var ea := entrance(bp, int(c["a"]))
	var eb := entrance(bp, int(c["b"]))
	var out := PackedVector3Array()
	if ea.is_empty() or eb.is_empty():
		return out
	out.append(entrance_pos(bp, ea))
	out.append(entrance_stub(bp, ea))
	for p in c["pts"]:
		out.append(ShipData.v3(p))
	out.append(entrance_stub(bp, eb))
	out.append(entrance_pos(bp, eb))
	return out


## 0 corridor, 1 slope, 2 stairs, 3 ladder, from the steepness of one segment.
static func seg_kind(a: Vector3, b: Vector3) -> int:
	var d := b - a
	var run := Vector2(d.x, d.z).length()
	var ang := rad_to_deg(atan2(absf(d.y), maxf(run, 1e-6)))
	if ang >= LADDER_DEG:
		return 3
	if ang >= STAIRS_DEG:
		return 2
	if ang >= SLOPE_DEG:
		return 1
	return 0


static func seg_angle(a: Vector3, b: Vector3) -> float:
	var d := b - a
	return rad_to_deg(atan2(absf(d.y), maxf(Vector2(d.x, d.z).length(), 1e-6)))


static func seg_count(bp: Dictionary, c: Dictionary) -> int:
	return maxi(polyline(bp, c).size() - 1, 0)


static func seg_width(bp: Dictionary, c: Dictionary, seg: int) -> float:
	var w: Array = c.get("w", [])
	return base_width(bp) * (float(w[seg]) if seg < w.size() else 1.0)


static func length(bp: Dictionary, c: Dictionary) -> float:
	var p := polyline(bp, c)
	var l := 0.0
	for i in range(p.size() - 1):
		l += p[i].distance_to(p[i + 1])
	return l


static func info(bp: Dictionary, c: Dictionary) -> Dictionary:
	var p := polyline(bp, c)
	var kinds := [0, 0, 0, 0]
	for i in range(p.size() - 1):
		kinds[seg_kind(p[i], p[i + 1])] += 1
	var widest := 1.0
	for f in c.get("w", []):
		widest = maxf(widest, float(f))
	return {"length": length(bp, c), "segments": maxi(p.size() - 1, 0), "bends": (c["pts"] as Array).size(), "kinds": kinds, "doors": (c["doors"] as Array).size(), "widest": widest}


static func stats(bp: Dictionary) -> Dictionary:
	var n := 0
	var l := 0.0
	var st := 0
	var ld := 0
	var dr := 0
	for c in corridors(bp):
		var i := info(bp, c)
		n += 1
		l += float(i["length"])
		st += int(i["kinds"][2])
		ld += int(i["kinds"][3])
		dr += int(i["doors"])
	return {"count": n, "length": l, "stairs": st, "ladders": ld, "doors": dr, "entrances": entrances(bp).size()}


## Insert a bend point into a segment (so the corridor can be bent by hand).
static func insert_bend(bp: Dictionary, c: Dictionary, seg: int, p: Vector3) -> int:
	var poly := polyline(bp, c)
	if seg < 1 or seg > poly.size() - 3:
		seg = clampi(seg, 1, maxi(poly.size() - 3, 1))
	var a := poly[seg]
	var b := poly[seg + 1]
	var ab := b - a
	var tsplit := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.05, 0.95)
	var pts: Array = c["pts"]
	pts.insert(seg - 1, ShipData.a3(p))
	var w: Array = c["w"]
	var fw := float(w[seg]) if seg < w.size() else 1.0
	w.insert(seg, fw)
	var doors: Array = []
	for d in c["doors"]:
		var ds := int(d[0])
		var dt := float(d[1])
		if ds < seg:
			doors.append([ds, dt])
		elif ds > seg:
			doors.append([ds + 1, dt])
		elif dt < tsplit:
			doors.append([seg, dt / tsplit])
		else:
			doors.append([seg + 1, (dt - tsplit) / (1.0 - tsplit)])
	c["doors"] = doors
	return seg - 1


static func remove_bend(bp: Dictionary, c: Dictionary, k: int) -> void:
	var pts: Array = c["pts"]
	if k < 0 or k >= pts.size():
		return
	pts.remove_at(k)
	var seg := k + 1                       # segments seg and seg + 1 merge
	var w: Array = c["w"]
	if seg + 1 < w.size():
		w[seg] = maxf(float(w[seg]), float(w[seg + 1]))
		w.remove_at(seg + 1)
	var doors: Array = []
	for d in c["doors"]:
		var ds := int(d[0])
		var dt := float(d[1])
		if ds < seg:
			doors.append([ds, dt])
		elif ds == seg:
			doors.append([seg, dt * 0.5])
		elif ds == seg + 1:
			doors.append([seg, 0.5 + dt * 0.5])
		else:
			doors.append([ds - 1, dt])
	c["doors"] = doors


static func toggle_door(c: Dictionary, seg: int, t: float) -> bool:
	var doors: Array = c["doors"]
	for i in range(doors.size()):
		if int(doors[i][0]) == seg and absf(float(doors[i][1]) - t) < 0.12:
			doors.remove_at(i)
			return false
	doors.append([seg, clampf(t, 0.1, 0.9)])
	return true


## Next width factor for a segment (1 -> 1.5 -> 2 -> 3 -> 1).
static func cycle_width(c: Dictionary, seg: int) -> float:
	var w: Array = c["w"]
	if seg < 0 or seg >= w.size():
		return 1.0
	var i := 0
	for k in range(WIDTHS.size()):
		if absf(float(WIDTHS[k]) - float(w[seg])) < 0.01:
			i = k
	w[seg] = WIDTHS[(i + 1) % WIDTHS.size()]
	return float(w[seg])


# ================================================================== checks
static func _clearance_r(bp: Dictionary) -> float:
	return base_width(bp) * 0.6


static func _point_ok(bp: Dictionary, p: Vector3, r: float) -> bool:
	var rings: Array = bp["rings"]
	if not ShipData.hull_contains(rings, p):
		return false
	for o in [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0)]:
		if not ShipData.hull_contains(rings, p + o):
			return false
	return true


## "" if the path is fine, otherwise why it is not.
static func polyline_problem(bp: Dictionary, c: Dictionary) -> String:
	var poly := polyline(bp, c)
	if poly.size() < 2:
		return "has a missing entrance"
	var r := _clearance_r(bp)
	var ex := base_width(bp) * 1.6
	var mods: Array = bp["modules"]
	var step := maxf(r * 0.8, 0.2)
	for i in range(poly.size() - 1):
		var a := poly[i]
		var b := poly[i + 1]
		var n := maxi(int(ceil(a.distance_to(b) / step)), 1)
		for k in range(n + 1):
			var p := a.lerp(b, float(k) / float(n))
			var near_end := p.distance_to(poly[0]) < ex or p.distance_to(poly[poly.size() - 1]) < ex
			if not near_end and not _point_ok(bp, p, r * 0.7):
				return "leaves the hull"
			if not near_end:
				for m in mods:
					if ShipData.module_box(m).grow(r * 0.25).has_point(p):
						return "cuts through %s #%d" % [ShipData.MODULES[String(m["type"])]["label"], int(m["id"])]
	return ""


static func issues(bp: Dictionary) -> Array:
	var out: Array = []
	for c in corridors(bp):
		var why := polyline_problem(bp, c)
		if why != "":
			out.append({"msg": "Corridor #%d %s" % [int(c["id"]), why], "mod": -1})
	return out


# ================================================================== routing
class RouteStar extends AStar3D:
	func _compute_cost(from_id: int, to_id: int) -> float:
		var a := get_point_position(from_id)
		var b := get_point_position(to_id)
		var d := a.distance_to(b)
		return d * (1.0 + absf(b.y - a.y) / maxf(d, 0.001) * 1.5)   # flat corridors are cheaper than climbs

	func _estimate_cost(from_id: int, to_id: int) -> float:
		return get_point_position(from_id).distance_to(get_point_position(to_id))


static func _line_geo(bp: Dictionary, a: Vector3, b: Vector3, r: float, ex: float, boxes: Array) -> bool:
	var step := maxf(r * 0.8, 0.2)
	var n := maxi(int(ceil(a.distance_to(b) / step)), 1)
	for k in range(n + 1):
		var p := a.lerp(b, float(k) / float(n))
		if p.distance_to(a) < ex * 0.5 or p.distance_to(b) < ex * 0.5:
			continue
		if not _point_ok(bp, p, r * 0.7):
			return false
		for bx in boxes:
			if (bx as AABB).has_point(p):
				return false
	return true


## Find a path between two entrances. {ok, pts (bend points), msg}
static func route(bp: Dictionary, ea: Dictionary, eb: Dictionary) -> Dictionary:
	var rings: Array = bp["rings"]
	var w0 := base_width(bp)
	var r := w0 * 0.6
	var pa := entrance_stub(bp, ea)
	var pb := entrance_stub(bp, eb)
	var boxes: Array = []
	for m in bp["modules"]:
		boxes.append(ShipData.module_box(m).grow(r * 0.55))
	var ex := w0 * 1.6
	if _line_geo(bp, pa, pb, r, ex, boxes):
		return {"ok": true, "pts": []}
	# ---- voxel grid over the hull
	var hb := ShipData.hull_bounds(rings)
	var c := maxf(w0 * 0.5, maxf(hb.size.x, maxf(hb.size.y, hb.size.z)) / 80.0)
	var dims := Vector3i.ZERO
	while true:
		dims = Vector3i(maxi(1, int(ceil(hb.size.x / c))), maxi(1, int(ceil(hb.size.y / c))), maxi(1, int(ceil(hb.size.z / c))))
		if dims.x * dims.y * dims.z <= MAX_CELLS:
			break
		c *= 1.12
	var n := dims.x * dims.y * dims.z
	var inh := PackedByteArray()
	inh.resize(n)
	var zmin := float(rings[0]["z"])
	var zmax := float(rings[rings.size() - 1]["z"])
	for iz in range(dims.z):
		var z := hb.position.z + (float(iz) + 0.5) * c
		if z < zmin + r * 0.5 or z > zmax - r * 0.5:
			continue
		var poly := ShipData.ring_pts_at(rings, z)
		if poly.is_empty():
			continue
		var inset := Geometry2D.offset_polygon(poly, -r)
		if inset.is_empty():
			continue
		for iy in range(dims.y):
			var y := hb.position.y + (float(iy) + 0.5) * c
			for ix in range(dims.x):
				var x := hb.position.x + (float(ix) + 0.5) * c
				var p2 := Vector2(x, y)
				for ip in inset:
					if Geometry2D.is_point_in_polygon(p2, ip):
						inh[(iz * dims.y + iy) * dims.x + ix] = 1
						break
	var free := inh.duplicate()
	for bx in boxes:
		var b: AABB = bx
		var lo := Vector3i(clampi(int(floor((b.position.x - hb.position.x) / c)), 0, dims.x - 1), clampi(int(floor((b.position.y - hb.position.y) / c)), 0, dims.y - 1), clampi(int(floor((b.position.z - hb.position.z) / c)), 0, dims.z - 1))
		var hi := Vector3i(clampi(int(floor((b.end.x - hb.position.x) / c)), 0, dims.x - 1), clampi(int(floor((b.end.y - hb.position.y) / c)), 0, dims.y - 1), clampi(int(floor((b.end.z - hb.position.z) / c)), 0, dims.z - 1))
		for iz in range(lo.z, hi.z + 1):
			for iy in range(lo.y, hi.y + 1):
				for ix in range(lo.x, hi.x + 1):
					var cp := hb.position + Vector3((float(ix) + 0.5) * c, (float(iy) + 0.5) * c, (float(iz) + 0.5) * c)
					if b.has_point(cp):
						free[(iz * dims.y + iy) * dims.x + ix] = 0
	# the cells around the two stubs stay open (they touch the modules the corridor starts from)
	for end in [pa, pb]:
		var q: Vector3 = end
		var lo2 := Vector3i(clampi(int(floor((q.x - ex - hb.position.x) / c)), 0, dims.x - 1), clampi(int(floor((q.y - ex - hb.position.y) / c)), 0, dims.y - 1), clampi(int(floor((q.z - ex - hb.position.z) / c)), 0, dims.z - 1))
		var hi2 := Vector3i(clampi(int(floor((q.x + ex - hb.position.x) / c)), 0, dims.x - 1), clampi(int(floor((q.y + ex - hb.position.y) / c)), 0, dims.y - 1), clampi(int(floor((q.z + ex - hb.position.z) / c)), 0, dims.z - 1))
		for iz in range(lo2.z, hi2.z + 1):
			for iy in range(lo2.y, hi2.y + 1):
				for ix in range(lo2.x, hi2.x + 1):
					var i3 := (iz * dims.y + iy) * dims.x + ix
					var cp2 := hb.position + Vector3((float(ix) + 0.5) * c, (float(iy) + 0.5) * c, (float(iz) + 0.5) * c)
					if inh[i3] == 1 and cp2.distance_to(q) < ex:
						free[i3] = 1
	var cell_of := func(p: Vector3) -> int:
		var ix := clampi(int(floor((p.x - hb.position.x) / c)), 0, dims.x - 1)
		var iy := clampi(int(floor((p.y - hb.position.y) / c)), 0, dims.y - 1)
		var iz := clampi(int(floor((p.z - hb.position.z) / c)), 0, dims.z - 1)
		return (iz * dims.y + iy) * dims.x + ix
	var center_of := func(idx: int) -> Vector3:
		var ix := idx % dims.x
		var iy := (idx / dims.x) % dims.y
		var iz := idx / (dims.x * dims.y)
		return hb.position + Vector3((float(ix) + 0.5) * c, (float(iy) + 0.5) * c, (float(iz) + 0.5) * c)
	var astar := RouteStar.new()
	astar.reserve_space(n / 4)
	for idx in range(n):
		if free[idx] == 1:
			astar.add_point(idx, center_of.call(idx))
	var sx := dims.x
	var sxy := dims.x * dims.y
	for idx in range(n):
		if free[idx] != 1:
			continue
		var ix := idx % dims.x
		var iy := (idx / dims.x) % dims.y
		if ix + 1 < dims.x and free[idx + 1] == 1:
			astar.connect_points(idx, idx + 1)
		if iy + 1 < dims.y and free[idx + sx] == 1:
			astar.connect_points(idx, idx + sx)
		if idx + sxy < n and free[idx + sxy] == 1:
			astar.connect_points(idx, idx + sxy)
	var start := _nearest_free(astar, cell_of.call(pa), free, dims, 4)
	var goal := _nearest_free(astar, cell_of.call(pb), free, dims, 4)
	if start < 0 or goal < 0:
		return {"ok": false, "pts": [], "msg": "No room for a corridor next to those entrances."}
	var path := astar.get_point_path(start, goal)
	if path.is_empty():
		return {"ok": false, "pts": [], "msg": "No route: the hull or the modules block every way between them."}
	# straighten: keep only the points needed to stay in free cells
	var full: Array = [pa]
	for p in path:
		full.append(p)
	full.append(pb)
	var line_free := func(a: Vector3, b: Vector3) -> bool:
		var step := c * 0.45
		var k := maxi(int(ceil(a.distance_to(b) / step)), 1)
		for i in range(k + 1):
			var p: Vector3 = a.lerp(b, float(i) / float(k))
			if p.distance_to(pa) < ex or p.distance_to(pb) < ex:
				continue
			if free[cell_of.call(p)] != 1:
				return false
		return true
	var out: Array = [full[0]]
	var i := 0
	while i < full.size() - 1:
		var j := full.size() - 1
		while j > i + 1 and not line_free.call(full[i], full[j]):
			j -= 1
		out.append(full[j])
		i = j
	var bends: Array = []
	for k in range(1, out.size() - 1):
		bends.append(out[k])
	return {"ok": true, "pts": bends}


static func _nearest_free(astar: AStar3D, idx: int, free: PackedByteArray, dims: Vector3i, rad: int) -> int:
	if free[idx] == 1:
		return idx
	var ix := idx % dims.x
	var iy := (idx / dims.x) % dims.y
	var iz := idx / (dims.x * dims.y)
	var best := -1
	var bd := INF
	for dz in range(-rad, rad + 1):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var x := ix + dx
				var y := iy + dy
				var z := iz + dz
				if x < 0 or y < 0 or z < 0 or x >= dims.x or y >= dims.y or z >= dims.z:
					continue
				var k := (z * dims.y + y) * dims.x + x
				if free[k] == 1:
					var d := float(dx * dx + dy * dy + dz * dz)
					if d < bd:
						bd = d
						best = k
	return best


## Join two entrances with a corridor (auto-routed inside the hull, with a door at each end).
static func add_corridor(bp: Dictionary, ea_id: int, eb_id: int) -> Dictionary:
	var ea := entrance(bp, ea_id)
	var eb := entrance(bp, eb_id)
	if ea.is_empty() or eb.is_empty():
		return {"ok": false, "msg": "Pick two entrances."}
	if int(ea["module"]) == int(eb["module"]):
		return {"ok": false, "msg": "Both entrances are on the same module."}
	for c in corridors(bp):
		if (int(c["a"]) == ea_id and int(c["b"]) == eb_id) or (int(c["a"]) == eb_id and int(c["b"]) == ea_id):
			return {"ok": false, "msg": "Those entrances are already joined."}
	var r := route(bp, ea, eb)
	if not bool(r["ok"]):
		return r
	var it := ensure(bp)
	var pts: Array = []
	for p in r["pts"]:
		pts.append(ShipData.a3(p))
	var segs := pts.size() + 3
	var w: Array = []
	for i in segs:
		w.append(1.0)
	var c := {"id": int(it["next_id"]), "a": ea_id, "b": eb_id, "pts": pts, "w": w, "doors": [[0, 0.5], [segs - 1, 0.5]]}
	it["next_id"] = int(it["next_id"]) + 1
	it["corridors"].append(c)
	var why := polyline_problem(bp, c)
	if why != "":
		remove_corridor(bp, int(c["id"]))
		return {"ok": false, "msg": "The only route %s." % why}
	return {"ok": true, "id": int(c["id"])}


## Throw away the hand-made bends of a corridor and route it again.
static func reroute(bp: Dictionary, c: Dictionary) -> Dictionary:
	var r := route(bp, entrance(bp, int(c["a"])), entrance(bp, int(c["b"])))
	if not bool(r["ok"]):
		return r
	var pts: Array = []
	for p in r["pts"]:
		pts.append(ShipData.a3(p))
	c["pts"] = pts
	var w: Array = []
	for i in range(pts.size() + 3):
		w.append(1.0)
	c["w"] = w
	c["doors"] = [[0, 0.5], [pts.size() + 2, 0.5]]
	return {"ok": true}


## Quick network for a ship: every internal module gets an entrance facing the Commander Post and a corridor to it.
## Returns the number of corridors made.
static func auto_connect(bp: Dictionary) -> int:
	var hub := {}
	for m in bp["modules"]:
		if String(m["type"]) == "commander_post":
			hub = m
			break
	if hub.is_empty():
		return 0
	var made := 0
	var k := 0
	var targets: Array = []
	for m in bp["modules"]:
		if int(m["id"]) != int(hub["id"]) and String(ShipData.MODULES[String(m["type"])]["kind"]) == "internal":
			targets.append(m)
	# the hub is an external module on some ships; entrances only exist on internal ones, so use the nearest internal module
	var hub_in := hub
	if String(ShipData.MODULES[String(hub["type"])]["kind"]) != "internal":
		var bd := INF
		hub_in = {}
		for m in targets:
			var d := ShipData.v3(m["pos"]).distance_to(ShipData.v3(hub["pos"]))
			if d < bd:
				bd = d
				hub_in = m
		targets = targets.filter(func(t): return int(t["id"]) != int(hub_in["id"]))
	if hub_in.is_empty():
		return 0
	for t in targets:
		var d := ShipData.v3(t["pos"]) - ShipData.v3(hub_in["pos"])
		var order := _faces_toward(-d)   # the target's faces, nearest to the hub first
		var ea := -1
		for f in order:
			var res := add_entrance(bp, int(t["id"]), f, 0.0, 0.0)
			if bool(res["ok"]):
				ea = int(res["id"])
				break
		var eb := -1
		var spread := (-0.55 + 0.35 * float(k))
		for f in _faces_toward(d):       # the hub's faces, nearest to the target first
			var res2 := add_entrance(bp, int(hub_in["id"]), f, clampf(spread, -0.8, 0.8), 0.0)
			if not bool(res2["ok"]):
				res2 = add_entrance(bp, int(hub_in["id"]), f, 0.0, clampf(spread, -0.8, 0.8))
			if bool(res2["ok"]):
				eb = int(res2["id"])
				break
		k += 1
		if ea < 0 or eb < 0:
			continue
		if bool(add_corridor(bp, ea, eb)["ok"]):
			made += 1
	return made


## Faces of a module ordered from "pointing toward d" to "pointing away".
static func _faces_toward(d: Vector3) -> Array:
	var faces: Array = [0, 1, 2, 3, 4, 5]
	faces.sort_custom(func(a, b): return (ShipData.DIRS[a] as Vector3).dot(d) > (ShipData.DIRS[b] as Vector3).dot(d))
	return faces


# ================================================================== mesh
static func tri_count(bp: Dictionary) -> int:
	var n := 0
	for c in corridors(bp):
		n += seg_count(bp, c) * 12 + (c["doors"] as Array).size() * 12
	return n


static func _box(arr: Dictionary, p0: Vector3, p1: Vector3, wdt: float, hgt: float, col: Color, ext: float) -> void:
	var f := p1 - p0
	if f.length() < 1e-4:
		return
	var fn := f.normalized()
	var ref := Vector3.UP if absf(fn.y) < 0.95 else Vector3.RIGHT
	var side := fn.cross(ref).normalized()
	var up := side.cross(fn).normalized()
	var a := p0 - fn * ext
	var b := p1 + fn * ext
	var hs := side * wdt * 0.5
	var hu := up * hgt * 0.5
	var v := [a - hs - hu, a + hs - hu, a + hs + hu, a - hs + hu, b - hs - hu, b + hs - hu, b + hs + hu, b - hs + hu]
	var faces := [[0, 3, 2, 1, -fn], [4, 5, 6, 7, fn], [0, 1, 5, 4, -up], [3, 7, 6, 2, up], [0, 4, 7, 3, -side], [1, 2, 6, 5, side]]
	for fc in faces:
		var n: Vector3 = fc[4]
		for idx in [0, 1, 2, 0, 2, 3]:
			(arr["v"] as Array).append(v[fc[idx]])
			(arr["n"] as Array).append(n)
			(arr["c"] as Array).append(col)


## Triangle mesh of every corridor (vertex colours by segment kind, doors in white). The selected corridor is brightened.
static func build_mesh(bp: Dictionary, sel_cor := -1, sel_seg := -1) -> ArrayMesh:
	var arr := {"v": [], "n": [], "c": []}
	var w0 := base_width(bp)
	for c in corridors(bp):
		var poly := polyline(bp, c)
		var sel := int(c["id"]) == sel_cor
		for i in range(poly.size() - 1):
			var k := seg_kind(poly[i], poly[i + 1])
			var f: float = float((c["w"] as Array)[i]) if i < (c["w"] as Array).size() else 1.0
			var wdt := w0 * f
			var hgt := w0 * (1.5 if f <= 1.5 else 1.9)
			if k == 3:
				wdt = w0 * 0.7
				hgt = w0 * 0.7
			var col: Color = KIND_COLORS[k]
			if sel:
				col = col.lerp(Color.WHITE, 0.45 if (sel_seg < 0 or sel_seg == i) else 0.15)
			_box(arr, poly[i], poly[i + 1], wdt, hgt, col, wdt * 0.25 if i > 0 and i < poly.size() - 2 else 0.0)
		for d in c["doors"]:
			var si := int(d[0])
			if si < 0 or si >= poly.size() - 1:
				continue
			var pos := poly[si].lerp(poly[si + 1], float(d[1]))
			var dir := (poly[si + 1] - poly[si]).normalized()
			var wd := w0 * float((c["w"] as Array)[si] if si < (c["w"] as Array).size() else 1.0)
			_box(arr, pos - dir * w0 * 0.07, pos + dir * w0 * 0.07, wd * 1.08, w0 * (1.6 if wd <= w0 * 1.5 else 2.0), Color(0.92, 0.95, 1.0), 0.0)
	var mesh := ArrayMesh.new()
	if (arr["v"] as Array).is_empty():
		return mesh
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array(arr["v"])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array(arr["n"])
	a[Mesh.ARRAY_COLOR] = PackedColorArray(arr["c"])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return mesh


## Closest point of the path to a ray: {cor, seg, t, pos, dist}. Used to pick corridors in the editor and in Panel 1.
static func pick_ray(bp: Dictionary, origin: Vector3, dir: Vector3, max_dist_factor := 0.6) -> Dictionary:
	var best := {}
	var bd := INF
	var w0 := base_width(bp)
	for c in corridors(bp):
		var poly := polyline(bp, c)
		for i in range(poly.size() - 1):
			var f := float((c["w"] as Array)[i]) if i < (c["w"] as Array).size() else 1.0
			var a := poly[i]
			var b := poly[i + 1]
			var cp := Geometry3D.get_closest_points_between_segments(origin, origin + dir * 1.0e6, a, b)
			var d := cp[0].distance_to(cp[1])
			if d <= w0 * f * max_dist_factor:
				var t := origin.distance_to(cp[0])
				if t < bd:
					bd = t
					var ab := b - a
					best = {"cor": int(c["id"]), "seg": i, "t": clampf((cp[1] - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0), "pos": cp[1], "dist": t}
	return best
