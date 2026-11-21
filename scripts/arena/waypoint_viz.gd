class_name WaypointViz
extends Node3D
## 3D drawing of the movement waypoint: line ship -> point, stem down to the ship's plane, ring on that
## plane and a diamond marker. In the tactical map it also draws range rings around the ship.

var arena: Node
var mi: MeshInstance3D
var im: ImmediateMesh
var ring_step := 0.0
var ring_count := 0
var plane_y := 0.0


func _ready() -> void:
	im = ImmediateMesh.new()
	mi = MeshInstance3D.new()
	mi.mesh = im
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	add_child(mi)


static func nice(x: float) -> float:
	var p := pow(10.0, floor(log(maxf(x, 0.001)) / log(10.0)))
	var f := x / p
	var n := 1.0 if f < 1.5 else (2.0 if f < 3.5 else (5.0 if f < 7.5 else 10.0))
	return n * p


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	im.surface_set_color(c)
	im.surface_add_vertex(a)
	im.surface_set_color(c)
	im.surface_add_vertex(b)


func _circle(center: Vector3, r: float, c: Color) -> void:
	var prev := center + Vector3(r, 0, 0)
	for i in range(1, 49):
		var a := TAU * float(i) / 48.0
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		_line(prev, p, c)
		prev = p


func _process(_delta: float) -> void:
	im.clear_surfaces()
	ring_count = 0
	if arena == null or arena.player == null or not is_instance_valid(arena.player) or not arena.player.alive:
		return
	var map: bool = arena.rig.map_mode
	if not map and not arena.has_wp:
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
			_circle(c0, ring_step * i, Color(0.75, 0.22, 0.1, 0.3 if i % 2 == 1 else 0.18))
		var ext := ring_step * ring_count
		_line(c0 + Vector3(-ext, 0, 0), c0 + Vector3(ext, 0, 0), Color(0.75, 0.22, 0.1, 0.35))
		_line(c0 + Vector3(0, 0, -ext), c0 + Vector3(0, 0, ext), Color(0.75, 0.22, 0.1, 0.35))
	if arena.has_wp:
		var w: Vector3 = arena.waypoint
		var u := clampf(cam.global_position.distance_to(w) * 0.012, 1.5, 4000.0)
		var base := Vector3(w.x, plane_y, w.z)
		var gold := Color(1.0, 0.72, 0.22, 0.95)
		_line(sp, w, Color(1.0, 0.7, 0.2, 0.4))
		_line(w, base, Color(1.0, 0.85, 0.4, 0.85))
		_circle(base, u * 2.2, gold)
		_circle(base, u * 0.5, gold)
		# diamond (octahedron) marker
		var top := w + Vector3(0, u * 1.2, 0)
		var bot := w - Vector3(0, u * 1.2, 0)
		var ring: Array = [w + Vector3(u, 0, 0), w + Vector3(0, 0, u), w - Vector3(u, 0, 0), w - Vector3(0, 0, u)]
		for i in 4:
			_line(top, ring[i], gold)
			_line(bot, ring[i], gold)
			_line(ring[i], ring[(i + 1) % 4], gold)
	im.surface_end()
