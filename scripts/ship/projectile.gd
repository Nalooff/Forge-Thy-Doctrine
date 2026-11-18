class_name Projectile
extends Node3D
## Pooled-style projectiles: kinetic rounds and missiles are stepped manually with ray queries
## (fast rounds would tunnel through bodies); lasers are instant hitscan (GDD section 7).

var vel := Vector3.ZERO
var shooter: Ship
var kind := "kinetic"
var damage := 0.0
var pen := 0.0
var radius := 0.0
var life := 4.0
var age := 0.0
var target: Ship
var cruise := 0.0


static func spawn(parent: Node, from_ship: Ship, ws: Dictionary, pos: Vector3, dir: Vector3, inherit: Vector3, tgt: Ship) -> Projectile:
	var p := Projectile.new()
	p.shooter = from_ship
	p.kind = ws["kind"]
	p.damage = ws["damage"]
	p.pen = ws["pen"]
	p.radius = ws["radius"]
	p.target = tgt
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if p.kind == "missile":
		p.vel = inherit + dir * 20.0
		p.cruise = ws["speed"]
		p.life = float(ws["range"]) / maxf(p.cruise, 1.0) + 3.0
		bm.size = Vector3(0.35, 0.35, 1.6)
		mat.albedo_color = Color(1.0, 0.45, 0.2)
	else:
		p.vel = inherit + dir * float(ws["speed"])
		p.life = float(ws["range"]) / maxf(float(ws["speed"]), 1.0)
		bm.size = Vector3(0.12, 0.12, 2.2)
		mat.albedo_color = Color(1.0, 0.9, 0.4)
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	parent.add_child(p)
	p.global_position = pos
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	p.look_at(pos + dir, up)
	return p


## Nearest hit of a segment against ship hulls (physics ray) and exposed external modules.
static func trace(tree: SceneTree, world: World3D, p0: Vector3, p1: Vector3, skip: Ship) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p0, p1, 1)
	if skip != null:
		q.exclude = [skip.get_rid()]
	var res := world.direct_space_state.intersect_ray(q)
	var best := {}
	var best_d := INF
	if not res.is_empty():
		best = {"ship": res["collider"], "pos": res["position"], "bare": false}
		best_d = p0.distance_to(res["position"])
	for s in tree.get_nodes_in_group("ships"):
		if s == skip:
			continue
		var h = (s as Ship).ext_module_ray(p0, p1)
		if h != null and p0.distance_to(h) < best_d:
			best = {"ship": s, "pos": h, "bare": true}
			best_d = p0.distance_to(h)
	return best


static func fire_laser(parent: Node, from_ship: Ship, ws: Dictionary, from: Vector3, dir: Vector3) -> void:
	var end := from + dir * float(ws["range"])
	var hit := trace(parent.get_tree(), (parent as Node3D).get_world_3d(), from, end, from_ship)
	var stop := end
	if not hit.is_empty():
		stop = hit["pos"]
		if hit["ship"] is Ship:
			(hit["ship"] as Ship).apply_hit(from_ship, stop, dir, ws["damage"], ws["pen"], "laser", 0.0, hit["bare"])
		Fx.burst(parent, stop, 1.2, Color(1.0, 0.3, 0.3), 0.25)
	Fx.beam(parent, from, stop, Color(1.0, 0.25, 0.25, 0.9))


func _physics_process(delta: float) -> void:
	age += delta
	if age > life:
		queue_free()
		return
	if kind == "missile":
		if target != null and is_instance_valid(target) and target.alive:
			var want := (target.global_position - global_position).normalized()
			var cur := vel.normalized()
			var ang := cur.angle_to(want)
			var step := minf(ang, 2.2 * delta)
			if ang > 0.0001:
				var axis := cur.cross(want)
				if axis.length() > 0.0001:
					cur = cur.rotated(axis.normalized(), step)
			vel = cur * minf(vel.length() + 140.0 * delta, cruise)
		else:
			vel = vel.normalized() * minf(vel.length() + 140.0 * delta, cruise)
	var p0 := global_position
	var p1 := p0 + vel * delta
	var skip: Ship = shooter if (shooter != null and is_instance_valid(shooter) and age < 0.5) else null
	var hit := trace(get_tree(), get_world_3d(), p0, p1, skip)
	if not hit.is_empty():
		var pos: Vector3 = hit["pos"]
		if hit["ship"] is Ship:
			(hit["ship"] as Ship).apply_hit(shooter, pos, vel.normalized(), damage, pen, kind, radius, hit["bare"])
		Fx.burst(get_parent(), pos, maxf(radius * 1.6, 1.0), Color(1.0, 0.6, 0.2), 0.4)
		queue_free()
		return
	global_position = p1
	if vel.length() > 0.1:
		var up := Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT
		look_at(p1 + vel, up)
