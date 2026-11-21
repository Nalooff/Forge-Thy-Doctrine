class_name WaypointViz
extends Node3D
## 3D drawing of the movement orders: destination marker, route, orbit circle, follow ghost, facing arrow.
## In the tactical map it also draws range rings around the ship. Static helpers are shared with OrderTuner.

var arena: Node
var mi: MeshInstance3D
var im: ImmediateMesh
var ring_step := 0.0
var ring_count := 0
var plane_y := 0.0

const GOLD := Color(1.0, 0.72, 0.22, 0.95)
const DIM := Color(1.0, 0.7, 0.2, 0.4)


func _ready() -> void:
	im = ImmediateMesh.new()
	mi = make_instance(im)
	add_child(mi)


static func make_instance(mesh: ImmediateMesh) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.top_level = true
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = 16384.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inst.material_override = m
	return inst


static func fmt_dist(m: float) -> String:
	return "%d m" % int(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)


static func nice(x: float) -> float:
	var p := pow(10.0, floor(log(maxf(x, 0.001)) / log(10.0)))
	var f := x / p
	var n := 1.0 if f < 1.5 else (2.0 if f < 3.5 else (5.0 if f < 7.5 else 10.0))
	return n * p


static func s_line(m: ImmediateMesh, a: Vector3, b: Vector3, c: Color) -> void:
	m.surface_set_color(c)
	m.surface_add_vertex(a)
	m.surface_set_color(c)
	m.surface_add_vertex(b)


static func s_circle(m: ImmediateMesh, center: Vector3, r: float, c: Color) -> void:
	var prev := center + Vector3(r, 0, 0)
	for i in range(1, 65):
		var a := TAU * float(i) / 64.0
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		s_line(m, prev, p, c)
		prev = p


static func s_diamond(m: ImmediateMesh, w: Vector3, u: float, c: Color) -> void:
	var top := w + Vector3(0, u * 1.2, 0)
	var bot := w - Vector3(0, u * 1.2, 0)
	var ring: Array = [w + Vector3(u, 0, 0), w + Vector3(0, 0, u), w - Vector3(u, 0, 0), w - Vector3(0, 0, u)]
	for i in 4:
		s_line(m, top, ring[i], c)
		s_line(m, bot, ring[i], c)
		s_line(m, ring[i], ring[(i + 1) % 4], c)


static func s_arrow(m: ImmediateMesh, from: Vector3, dir: Vector3, length: float, c: Color) -> void:
	if dir.length() < 0.001:
		return
	var d := dir.normalized()
	var tip := from + d * length
	var side := d.cross(Vector3.UP)
	if side.length() < 0.01:
		side = d.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(d).normalized()
	var h := length * 0.18
	s_line(m, from, tip, c)
	for o in [side, -side, up, -up]:
		s_line(m, tip, tip - d * h * 2.0 + o * h, c)


static func s_box(m: ImmediateMesh, center: Vector3, basis: Basis, size: Vector3, c: Color) -> void:
	var h := size * 0.5
	var pts: Array = []
	for i in 8:
		var sx := -1.0 if (i & 1) == 0 else 1.0
		var sy := -1.0 if (i & 2) == 0 else 1.0
		var sz := -1.0 if (i & 4) == 0 else 1.0
		pts.append(center + basis * Vector3(h.x * sx, h.y * sy, h.z * sz))
	for i in 8:
		for bit in [1, 2, 4]:
			if (i & bit) == 0:
				s_line(m, pts[i], pts[i | bit], c)


static func s_chevrons(m: ImmediateMesh, center: Vector3, r: float, dirn: float, c: Color) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var tang := Vector3(-sin(a), 0, cos(a)) * dirn
		s_arrow(m, p - tang * r * 0.05, tang, r * 0.1, c)


func _process(_delta: float) -> void:
	im.clear_surfaces()
	ring_count = 0
	if arena == null or arena.player == null or not is_instance_valid(arena.player) or not arena.player.alive:
		return
	var map: bool = arena.rig.map_mode
	if not map and not arena.has_order_viz():
		return
	var cam: Camera3D = arena.rig.cam
	var sp: Vector3 = arena.player.global_position
	plane_y = sp.y
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	if map:
		ring_step = nice(float(arena.rig.map_dist) * 0.14)
		ring_count = 8
		var c0 := Vector3(sp.x, plane_y, sp.z)
		for i in range(1, ring_count + 1):
			s_circle(im, c0, ring_step * i, Color(0.75, 0.22, 0.1, 0.3 if i % 2 == 1 else 0.18))
		var ext := ring_step * ring_count
		s_line(im, c0 + Vector3(-ext, 0, 0), c0 + Vector3(ext, 0, 0), Color(0.75, 0.22, 0.1, 0.35))
		s_line(im, c0 + Vector3(0, 0, -ext), c0 + Vector3(0, 0, ext), Color(0.75, 0.22, 0.1, 0.35))
	var p: Dictionary = arena.order_p
	var length := float(arena.player.stats["longest"])
	match arena.order:
		"goto", "route":
			var pts: Array = []
			if arena.order == "route":
				pts = (p.get("points", []) as Array).slice(int(p.get("idx", 0)))
			elif arena.has_wp:
				pts = [arena.waypoint]
			var prev := sp
			for q in pts:
				var w: Vector3 = q
				var u := clampf(cam.global_position.distance_to(w) * 0.012, 1.5, 4000.0)
				s_line(im, prev, w, DIM)
				s_line(im, w, Vector3(w.x, plane_y, w.z), Color(1.0, 0.85, 0.4, 0.85))
				s_circle(im, Vector3(w.x, plane_y, w.z), u * 2.2, GOLD)
				s_diamond(im, w, u * 0.9, GOLD)
				prev = w
			var ed: Vector3 = p.get("end_dir", Vector3.ZERO)
			if ed.length() > 0.1 and not pts.is_empty():
				s_arrow(im, pts[pts.size() - 1], ed, clampf(cam.global_position.distance_to(pts[pts.size() - 1]) * 0.08, 8.0, 3000.0), GOLD)
		"hold":
			if p.has("pos"):
				var hp: Vector3 = p["pos"]
				var uh := clampf(cam.global_position.distance_to(hp) * 0.008, 1.0, 2000.0)
				s_diamond(im, hp, uh, GOLD)
				var fd: Vector3 = p.get("face", Vector3.ZERO)
				if fd.length() > 0.1:
					s_arrow(im, hp, fd, uh * 8.0, GOLD)
		"orbit":
			var c: Vector3 = arena.orbit_center(p)
			var r := float(p["radius"])
			s_circle(im, c, r, GOLD)
			s_chevrons(im, c, r, float(p["dir"]), GOLD)
			s_line(im, c, sp, DIM)
			s_line(im, c, Vector3(c.x, sp.y, c.z), DIM)
		"chase":
			var t = p.get("target")
			if t != null and is_instance_valid(t):
				s_line(im, sp, t.global_position, DIM)
				s_circle(im, t.global_position, float(p["dist"]), GOLD)
		"follow":
			var lt = p.get("target")
			if lt != null and is_instance_valid(lt):
				var gp: Vector3 = lt.to_global(p["offset"] as Vector3)
				var gb: Basis = lt.global_transform.basis
				var hl: Vector3 = p.get("head", Vector3.ZERO)
				if hl.length() > 0.1:
					gb = Basis.looking_at(gb * hl, Vector3.UP)
				s_line(im, sp, gp, DIM)
				s_box(im, gp, gb, Vector3(float(arena.player.stats["beam"]), float(arena.player.stats["height"]), float(arena.player.stats["length"])), GOLD)
				s_line(im, lt.global_position, gp, DIM)
		"lookat":
			var lp: Vector3 = arena.lookat_point(p)
			s_line(im, sp, lp, DIM)
			s_diamond(im, lp, clampf(cam.global_position.distance_to(lp) * 0.008, 1.0, 2000.0), GOLD)
	# facing-while-moving indicator
	var fm: Dictionary = arena.facing
	if fm["mode"] == "lock":
		s_arrow(im, sp, fm["dir"], length * 1.6, Color(1.0, 0.95, 0.75, 0.9))
	elif fm["mode"] == "point":
		var fp: Vector3 = arena.facing_point()
		s_line(im, sp, fp, Color(1.0, 0.95, 0.75, 0.5))
		s_diamond(im, fp, clampf(cam.global_position.distance_to(fp) * 0.006, 1.0, 1500.0), Color(1.0, 0.95, 0.75, 0.9))
	im.surface_end()
