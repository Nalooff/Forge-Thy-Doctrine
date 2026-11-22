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


## Width of a normal corridor: scales with the ship (0.8 m on a corvette up to 3 m on a capital ship).
static func base_width(bp: Dictionary) -> float:
	return clampf(longest(bp) * 0.05, 0.8, 3.0)


## Space kept between a corridor and the hull skin (the armour takes room too).
static func margin(bp: Dictionary) -> float:
	return 0.04 + 0.5 * float(bp.get("thickness", 0.1))


## Half width and half height of the tube for a width factor (a ladder shaft is narrow and square).
static func tube_half(bp: Dictionary, wf: float, kind: int) -> Vector2:
	var w0 := base_width(bp)
	if kind == 3:
		return Vector2(0.38 * w0, 0.38 * w0)
	return Vector2(0.5 * w0 * wf, 0.5 * w0 * (1.35 + 0.2 * (wf - 1.0)))


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
	var nrm: Vector3 = ShipData.DIRS[face]
	var fr := _frame(nrm, Vector3.UP)
	var ab0 := tube_half(bp, 1.0, 0)
	if not ShipData.hull_contains(bp["rings"], stub) or _tube_problem(bp, stub, fr[0], fr[1], ab0.x, ab0.y, [module_id]) == "leaves the hull":
		return {"ok": false, "msg": "That face is too close to the hull: no room for a corridor."}
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


# ================================================================== tube geometry
## Right-handed frame (side, up) for a direction of travel; `up_hint` keeps floors level when it can.
static func _frame(t: Vector3, up_hint: Vector3) -> Array:
	var up := up_hint - t * up_hint.dot(t)
	if up.length() < 0.2:
		up = Vector3.BACK - t * Vector3.BACK.dot(t)
		if up.length() < 0.2:
			up = Vector3.RIGHT - t * Vector3.RIGHT.dot(t)
	up = up.normalized()
	var side := t.cross(up).normalized()
	return [side, up]


## "" when a tube cross-section at `pos` is entirely inside the hull and clear of the modules, otherwise why not.
static func _tube_problem(bp: Dictionary, pos: Vector3, side: Vector3, up: Vector3, a: float, b: float, exempt: Array) -> String:
	var rings: Array = bp["rings"]
	var m := margin(bp)
	var aa := a + m
	var bb := b + m
	for o in [Vector3.ZERO, side * aa, -side * aa, up * bb, -up * bb, side * aa * 0.8 + up * bb * 0.8, side * aa * 0.8 - up * bb * 0.8, -side * aa * 0.8 + up * bb * 0.8, -side * aa * 0.8 - up * bb * 0.8]:
		if not ShipData.hull_contains(rings, pos + (o as Vector3)):
			return "leaves the hull"
	var ext := Vector3(absf(side.x) * a + absf(up.x) * b, absf(side.y) * a + absf(up.y) * b, absf(side.z) * a + absf(up.z) * b) + Vector3(0.03, 0.03, 0.03)
	var box := AABB(pos - ext, ext * 2.0)
	for mod in bp["modules"]:
		if exempt.has(int(mod["id"])):
			continue
		if ShipData.module_box(mod).intersects(box):
			return "cuts through %s #%d" % [ShipData.MODULES[String(mod["type"])]["label"], int(mod["id"])]
	return ""


## Modules a path may touch near its two ends (the modules it starts from and arrives at).
static func _exempt_near(bp: Dictionary, c: Dictionary, pos: Vector3, ex: float) -> Array:
	var out: Array = []
	for key in ["a", "b"]:
		var e := entrance(bp, int(c[key]))
		if not e.is_empty() and entrance_pos(bp, e).distance_to(pos) < ex:
			out.append(int(e["module"]))
	return out


## Round the corners of the path (quadratic arcs) and keep as much rounding as still fits in the hull. Each point
## remembers the original segment it belongs to.
static func smooth_path(bp: Dictionary, c: Dictionary) -> Array:
	var raw := polyline(bp, c)
	var P: Array = []
	for p in raw:
		if P.is_empty() or (P[P.size() - 1] as Vector3).distance_to(p) > 1e-3:
			P.append(p)
	var n := P.size()
	var out: Array = []
	if n < 2:
		return out
	var w0 := base_width(bp)
	var wl: Array = c["w"]
	out.append({"p": P[0], "seg": 0})
	for i in range(1, n - 1):
		var vin := (P[i] as Vector3) - (P[i - 1] as Vector3)
		var vout := (P[i + 1] as Vector3) - (P[i] as Vector3)
		var lin := vin.length()
		var lout := vout.length()
		var u := vin / lin
		var v := vout / lout
		var th := acos(clampf(u.dot(v), -1.0, 1.0))
		if th < deg_to_rad(4.0):
			out.append({"p": P[i], "seg": i - 1})
			continue
		var dmax := 0.5 * minf(lin, lout)
		var d0 := minf(dmax, 1.6 * w0 * tan(th * 0.5))
		var wf := maxf(float(wl[i - 1]) if i - 1 < wl.size() else 1.0, float(wl[i]) if i < wl.size() else 1.0)
		var kind := maxi(seg_kind(P[i - 1], P[i]), seg_kind(P[i], P[i + 1]))
		var ab := tube_half(bp, wf, kind)
		var steps := clampi(int(th / deg_to_rad(11.0)), 3, 10)
		var best: Array = []
		for f in [1.0, 0.75, 0.55, 0.38, 0.25]:
			var d := maxf(d0 * f, minf(0.12 * w0, dmax))
			var pa: Vector3 = (P[i] as Vector3) - u * d
			var pb: Vector3 = (P[i] as Vector3) + v * d
			var pts: Array = []
			var ok := true
			for k in range(steps + 1):
				var s := float(k) / float(steps)
				var q: Vector3 = pa * (1.0 - s) * (1.0 - s) + (P[i] as Vector3) * 2.0 * s * (1.0 - s) + pb * s * s
				var tg: Vector3 = ((P[i] as Vector3) - pa) * 2.0 * (1.0 - s) + (pb - (P[i] as Vector3)) * 2.0 * s
				pts.append({"p": q, "seg": i - 1 if s < 0.5 else i})
				if ok:
					var fr := _frame(tg.normalized(), Vector3.UP)
					if _tube_problem(bp, q, fr[0], fr[1], ab.x, ab.y, _exempt_near(bp, c, q, w0 * 1.4)) != "":
						ok = false
			best = pts
			if ok:
				break
		out.append_array(best)
	out.append({"p": P[n - 1], "seg": n - 2})
	# long straight spans get extra points so widths can blend and ribs can run along them
	var dense: Array = [out[0]]
	for i in range(1, out.size()):
		var p0: Vector3 = out[i - 1]["p"]
		var p1: Vector3 = out[i]["p"]
		var k := int(ceil(p0.distance_to(p1) / (2.2 * w0)))
		for j in range(1, k):
			dense.append({"p": p0.lerp(p1, float(j) / float(k)), "seg": out[i]["seg"] if int(out[i]["seg"]) == int(out[i - 1]["seg"]) else out[i - 1]["seg"]})
		dense.append(out[i])
	return dense


## The corridor as a sequence of cross-sections: {p, t, side, up, a, b, kind, seg, wf}.
static func tube_samples(bp: Dictionary, c: Dictionary) -> Array:
	var path := smooth_path(bp, c)
	var n := path.size()
	var raw := polyline(bp, c)
	var w0 := base_width(bp)
	var wl: Array = c["w"]
	var S: Array = []
	for i in range(n):
		var seg := clampi(int(path[i]["seg"]), 0, maxi(raw.size() - 2, 0))
		S.append({"p": path[i]["p"], "seg": seg, "wf": float(wl[seg]) if seg < wl.size() else 1.0, "kind": seg_kind(raw[seg], raw[seg + 1])})
	# blend width changes over about two corridor widths
	var along: Array = [0.0]
	for i in range(1, n):
		along.append(float(along[i - 1]) + (S[i]["p"] as Vector3).distance_to(S[i - 1]["p"]))
	for i in range(n):
		var sum := 0.0
		var cnt := 0.0
		for j in range(n):
			if absf(float(along[j]) - float(along[i])) <= 1.6 * w0:
				sum += float(S[j]["wf"])
				cnt += 1.0
		S[i]["wfs"] = maxf(float(S[i]["wf"]) if int(S[i]["kind"]) == 3 else sum / maxf(cnt, 1.0), 1.0)
	var up_prev := Vector3.UP
	for i in range(n):
		var t: Vector3 = ((S[mini(i + 1, n - 1)]["p"] as Vector3) - (S[maxi(i - 1, 0)]["p"] as Vector3)).normalized()
		var hint := up_prev
		if absf(t.y) < 0.7:
			hint = Vector3.UP                       # keep floors level while the corridor is mostly horizontal
		var fr := _frame(t, hint)
		up_prev = fr[1]
		var ab := tube_half(bp, float(S[i]["wfs"]), int(S[i]["kind"]))
		S[i]["t"] = t
		S[i]["side"] = fr[0]
		S[i]["up"] = fr[1]
		S[i]["a"] = ab.x
		S[i]["b"] = ab.y
	return S


## Samples of the tube closer together than `step` (for checking, not for drawing).
static func _dense(S: Array, step: float) -> Array:
	var out: Array = []
	for i in range(S.size() - 1):
		var s0: Dictionary = S[i]
		var s1: Dictionary = S[i + 1]
		var k := maxi(int(ceil((s0["p"] as Vector3).distance_to(s1["p"]) / step)), 1)
		for j in range(k):
			var f := float(j) / float(k)
			out.append({"p": (s0["p"] as Vector3).lerp(s1["p"], f), "side": (s0["side"] as Vector3).lerp(s1["side"], f).normalized(), "up": (s0["up"] as Vector3).lerp(s1["up"], f).normalized(), "a": lerpf(float(s0["a"]), float(s1["a"]), f), "b": lerpf(float(s0["b"]), float(s1["b"]), f)})
	if not S.is_empty():
		out.append(S[S.size() - 1])
	return out


## "" if the whole tube (rounded corners and widened parts included) is inside the hull and clear of modules.
static func polyline_problem(bp: Dictionary, c: Dictionary) -> String:
	if polyline(bp, c).size() < 2:
		return "has a missing entrance"
	var w0 := base_width(bp)
	for s in _dense(tube_samples(bp, c), maxf(w0 * 0.4, 0.15)):
		var why := _tube_problem(bp, s["p"], s["side"], s["up"], float(s["a"]), float(s["b"]), _exempt_near(bp, c, s["p"], w0 * 1.4))
		if why != "":
			return why
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


static func _line_ok(bp: Dictionary, pa: Vector3, pb: Vector3, ea: Dictionary, eb: Dictionary) -> bool:
	var w0 := base_width(bp)
	var ab := tube_half(bp, 1.0, 0)
	var d := pb - pa
	var n := maxi(int(ceil(d.length() / maxf(w0 * 0.4, 0.15))), 1)
	var t := d.normalized() if d.length() > 1e-6 else Vector3.RIGHT
	var fr := _frame(t, Vector3.UP)
	var ca := entrance_pos(bp, ea)
	var cb := entrance_pos(bp, eb)
	for k in range(n + 1):
		var p := pa.lerp(pb, float(k) / float(n))
		var ex: Array = []
		if p.distance_to(ca) < w0 * 1.6:
			ex.append(int(ea["module"]))
		if p.distance_to(cb) < w0 * 1.6:
			ex.append(int(eb["module"]))
		if _tube_problem(bp, p, fr[0], fr[1], ab.x, ab.y, ex) != "":
			return false
	return true


## Find a path between two entrances. {ok, pts (bend points), msg}
static func route(bp: Dictionary, ea: Dictionary, eb: Dictionary) -> Dictionary:
	var rings: Array = bp["rings"]
	var w0 := base_width(bp)
	var ab := tube_half(bp, 1.0, 0)
	var r := ab.x + margin(bp)               # clearance sideways
	var rv := ab.y + margin(bp)              # clearance up and down (a corridor is taller than wide)
	var pa := entrance_stub(bp, ea)
	var pb := entrance_stub(bp, eb)
	var boxes: Array = []
	var grow := Vector3(r, rv, r)
	for mod in bp["modules"]:
		var bx := ShipData.module_box(mod)
		boxes.append(AABB(bx.position - grow, bx.size + grow * 2.0))
	var ex := w0 * 1.6
	if _line_ok(bp, pa, pb, ea, eb):
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
						if Geometry2D.is_point_in_polygon(Vector2(x, y + rv), poly) and Geometry2D.is_point_in_polygon(Vector2(x, y - rv), poly):
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
		var done := false
		var spread := clampf(-0.55 + 0.35 * float(k), -0.8, 0.8)
		k += 1
		# try the faces that look at each other first, then the others, until a corridor really fits
		for tf in _faces_toward(-d):
			if done:
				break
			var r1 := add_entrance(bp, int(t["id"]), tf, 0.0, 0.0)
			if not bool(r1["ok"]):
				continue
			for hf in _faces_toward(d):
				var r2 := add_entrance(bp, int(hub_in["id"]), hf, spread, 0.0)
				if not bool(r2["ok"]):
					r2 = add_entrance(bp, int(hub_in["id"]), hf, 0.0, spread)
				if not bool(r2["ok"]):
					continue
				if bool(add_corridor(bp, int(r1["id"]), int(r2["id"]))["ok"]):
					made += 1
					done = true
					break
				remove_entrance(bp, int(r2["id"]))
			if not done:
				remove_entrance(bp, int(r1["id"]))
	return made


## Faces of a module ordered from "pointing toward d" to "pointing away".
static func _faces_toward(d: Vector3) -> Array:
	var faces: Array = [0, 1, 2, 3, 4, 5]
	faces.sort_custom(func(a, b): return (ShipData.DIRS[a] as Vector3).dot(d) > (ShipData.DIRS[b] as Vector3).dot(d))
	return faces


# ================================================================== mesh
## Polygon budget cost of the interior: a nominal 12 per segment and door (corridors are drawn in the inspector only).
static func tri_count(bp: Dictionary) -> int:
	var n := 0
	for c in corridors(bp):
		n += seg_count(bp, c) * 12 + (c["doors"] as Array).size() * 12
	return n


const PROFILE_STEPS := 3
const DOOR_COLOR := Color(0.93, 0.96, 1.0)


## Rounded-rectangle outline (position and normal in side / up space), 4 corners x (PROFILE_STEPS + 1) points.
static func _profile(a: float, b: float) -> Array:
	var rc := 0.34 * minf(a, b)
	var centers := [Vector2(a - rc, b - rc), Vector2(-(a - rc), b - rc), Vector2(-(a - rc), -(b - rc)), Vector2(a - rc, -(b - rc))]
	var out: Array = []
	for k in 4:
		for j in range(PROFILE_STEPS + 1):
			var ang := deg_to_rad(90.0 * float(k) + 90.0 * float(j) / float(PROFILE_STEPS))
			var nrm := Vector2(cos(ang), sin(ang))
			out.append([(centers[k] as Vector2) + nrm * rc, nrm])
	return out


## One cross-section: [{v, n, ny}] around the corridor.
static func _ring(p: Vector3, side: Vector3, up: Vector3, a: float, b: float) -> Array:
	var out: Array = []
	for q in _profile(a, b):
		var pos: Vector2 = q[0]
		var nrm: Vector2 = q[1]
		out.append({"v": p + side * pos.x + up * pos.y, "n": (side * nrm.x + up * nrm.y).normalized(), "ny": nrm.y})
	return out


static func _shade(base: Color, ny: float) -> Color:
	# lighter ceiling strip, darker floor
	if ny > 0.0:
		return base.lerp(Color(1, 1, 1), 0.30 * ny * ny)
	return base.darkened(0.34 * ny * ny)


static func _emit(arr: Dictionary, v0: Vector3, v1: Vector3, v2: Vector3, n0: Vector3, n1: Vector3, n2: Vector3, c0: Color, c1: Color, c2: Color) -> void:
	var cr := (v1 - v0).cross(v2 - v0)
	if cr.length_squared() < 1e-12:
		return
	if cr.dot(n0 + n1 + n2) > 0.0:   # front faces are clockwise in Godot: put the visible side outwards
		var tv := v1
		v1 = v2
		v2 = tv
		var tn := n1
		n1 = n2
		n2 = tn
		var tc := c1
		c1 = c2
		c2 = tc
	(arr["v"] as Array).append_array([v0, v1, v2])
	(arr["n"] as Array).append_array([n0, n1, n2])
	(arr["c"] as Array).append_array([c0, c1, c2])


## Skin between two cross-sections.
static func _strip(arr: Dictionary, r0: Array, r1: Array, col0: Color, col1: Color, shade := true) -> void:
	var k_n := r0.size()
	for k in range(k_n):
		var k2 := (k + 1) % k_n
		var c00 := _shade(col0, float(r0[k]["ny"])) if shade else col0
		var c01 := _shade(col0, float(r0[k2]["ny"])) if shade else col0
		var c10 := _shade(col1, float(r1[k]["ny"])) if shade else col1
		var c11 := _shade(col1, float(r1[k2]["ny"])) if shade else col1
		_emit(arr, r0[k]["v"], r1[k]["v"], r1[k2]["v"], r0[k]["n"], r1[k]["n"], r1[k2]["n"], c00, c10, c11)
		_emit(arr, r0[k]["v"], r1[k2]["v"], r0[k2]["v"], r0[k]["n"], r1[k2]["n"], r0[k2]["n"], c00, c11, c01)


## Flat ring between an inner and an outer outline (the face of a door frame), facing `nrm`.
static func _annulus(arr: Dictionary, inner: Array, outer: Array, nrm: Vector3, col: Color) -> void:
	var k_n := inner.size()
	for k in range(k_n):
		var k2 := (k + 1) % k_n
		_emit(arr, inner[k]["v"], outer[k]["v"], outer[k2]["v"], nrm, nrm, nrm, col, col, col)
		_emit(arr, inner[k]["v"], outer[k2]["v"], inner[k2]["v"], nrm, nrm, nrm, col, col, col)


## A frame (door, or the collar at an entrance) around the tube at a cross-section.
static func _collar(arr: Dictionary, s: Dictionary, half: float, grow: float, col: Color) -> void:
	var t: Vector3 = s["t"]
	var p: Vector3 = s["p"]
	var a := float(s["a"])
	var b := float(s["b"])
	var in0 := _ring(p - t * half, s["side"], s["up"], a, b)
	var in1 := _ring(p + t * half, s["side"], s["up"], a, b)
	var out0 := _ring(p - t * half, s["side"], s["up"], a + grow, b + grow)
	var out1 := _ring(p + t * half, s["side"], s["up"], a + grow, b + grow)
	_strip(arr, out0, out1, col, col, false)
	_annulus(arr, in0, out0, -t, col)
	_annulus(arr, in1, out1, t, col)


## The cross-sections to draw: one per sample, plus ribs along stairs and rungs along ladders.
static func _draw_rings(S: Array, w0: float) -> Array:
	var out: Array = []
	for i in range(S.size()):
		var s0: Dictionary = S[i]
		if i == S.size() - 1:
			out.append({"s": s0, "k": 1.0})
			break
		var s1: Dictionary = S[i + 1]
		var kind := int(s0["kind"])
		if (kind == 2 or kind == 3) and int(s0["seg"]) == int(s1["seg"]):
			var period := (0.55 if kind == 2 else 0.30) * w0
			var cnt := maxi(int(round((s0["p"] as Vector3).distance_to(s1["p"]) / (period * 0.5))), 2)
			if cnt % 2 == 1:
				cnt += 1
			for j in range(cnt):
				var f := float(j) / float(cnt)
				var mid := {"p": (s0["p"] as Vector3).lerp(s1["p"], f), "side": (s0["side"] as Vector3).lerp(s1["side"], f).normalized(), "up": (s0["up"] as Vector3).lerp(s1["up"], f).normalized(), "t": (s0["t"] as Vector3).lerp(s1["t"], f).normalized(), "a": lerpf(float(s0["a"]), float(s1["a"]), f), "b": lerpf(float(s0["b"]), float(s1["b"]), f), "kind": kind, "seg": s0["seg"]}
				out.append({"s": mid, "k": 1.0 + ((0.06 if kind == 2 else 0.13) if j % 2 == 1 else 0.0)})
		else:
			out.append({"s": s0, "k": 1.0})
	return out


## Triangle mesh of every corridor: a smooth tube with rounded corners, door frames, ribs on stairs, rungs on ladders.
## The selected corridor (and segment) is brightened.
static func build_mesh(bp: Dictionary, sel_cor := -1, sel_seg := -1) -> ArrayMesh:
	var arr := {"v": [], "n": [], "c": []}
	var w0 := base_width(bp)
	for c in corridors(bp):
		var S := tube_samples(bp, c)
		if S.size() < 2:
			continue
		var sel := int(c["id"]) == sel_cor
		var rings := _draw_rings(S, w0)
		var prev: Array = []
		var prev_col := Color.WHITE
		for r in rings:
			var s: Dictionary = r["s"]
			var kk := float(r["k"])
			var ring := _ring(s["p"], s["side"], s["up"], float(s["a"]) * kk, float(s["b"]) * kk)
			var col: Color = KIND_COLORS[int(s["kind"])]
			if sel:
				col = col.lerp(Color.WHITE, 0.5 if (sel_seg < 0 or sel_seg == int(s["seg"])) else 0.16)
			if not prev.is_empty():
				_strip(arr, prev, ring, prev_col, col)
			prev = ring
			prev_col = col
		# frames: one at each entrance and one for every door
		_collar(arr, S[0], w0 * 0.09, w0 * 0.09, Color(0.78, 0.82, 0.9))
		var last: Dictionary = (S[S.size() - 1] as Dictionary).duplicate()
		last["t"] = -(last["t"] as Vector3)
		last["side"] = -(last["side"] as Vector3)
		_collar(arr, last, w0 * 0.09, w0 * 0.09, Color(0.78, 0.82, 0.9))
		var raw := polyline(bp, c)
		for d in c["doors"]:
			var si := int(d[0])
			if si < 0 or si >= raw.size() - 1:
				continue
			var want := (raw[si] as Vector3).lerp(raw[si + 1], float(d[1]))
			var best := 0
			var bd := INF
			for j in range(S.size()):
				var dd := (S[j]["p"] as Vector3).distance_to(want)
				if dd < bd:
					bd = dd
					best = j
			_collar(arr, S[best], w0 * 0.07, w0 * 0.07, DOOR_COLOR)
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
