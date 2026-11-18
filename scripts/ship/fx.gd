class_name Fx
extends RefCounted
## Tiny visual effects (expanding glow spheres, beams).


static func burst(parent: Node, pos: Vector3, size: float, color: Color, life := 0.5) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.2
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)


static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, width := 0.15, life := 0.12) -> void:
	if parent == null or not parent.is_inside_tree() or from.distance_to(to) < 0.01:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, from.distance_to(to))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var d := (to - from).normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
	mi.look_at_from_position((from + to) * 0.5, to, up)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(mi.queue_free)
