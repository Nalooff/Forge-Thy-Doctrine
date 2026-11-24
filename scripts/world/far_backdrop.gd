class_name FarBackdrop
extends Node3D
## Stars, planets, nebulae and black holes of a map. They are millions of kilometres away, far beyond the camera's
## far plane, so each one is drawn as an impostor: placed on a sphere around the camera at the same direction and the
## same angular size as the real body (computed from 64-bit positions, so parallax and approach are right). A body
## nearer than that sphere is drawn where it really is, so you can fly into it.

const FAR_FRACTION := 0.9

var ws: WorldSpace
var def: Dictionary
var cam: Camera3D
var items: Array = []
var sun_dir := Vector3(0.4, -0.6, -0.5)


func setup(p_ws: WorldSpace, p_def: Dictionary, p_cam: Camera3D) -> void:
	ws = p_ws
	def = p_def
	cam = p_cam
	add_to_group("no_shift")
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 40
	sphere.rings = 20
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var disk := CylinderMesh.new()
	disk.top_radius = 2.3
	disk.bottom_radius = 2.3
	disk.height = 0.02
	disk.radial_segments = 48
	var neb := Shader.new()
	neb.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled;\nuniform vec4 col : source_color = vec4(1.0);\nuniform float strength = 0.45;\nvoid fragment() {\n\tvec2 p = UV * 2.0 - 1.0;\n\tfloat a = clamp(1.0 - length(p), 0.0, 1.0);\n\ta = a * a;\n\tALBEDO = col.rgb * strength;\n\tALPHA = a;\n}\n"
	for b in def["bodies"]:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var col: Color = b["color"]
		var kind: String = b["kind"]
		match kind:
			"star":
				mi.mesh = sphere
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.albedo_color = col * float(b.get("power", 1.0)) if float(b.get("power", 1.0)) > 0.0 else col
				mi.material_override = m
			"blackhole":
				mi.mesh = sphere
				var m2 := StandardMaterial3D.new()
				m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m2.albedo_color = Color.BLACK
				mi.material_override = m2
			"nebula":
				mi.mesh = quad
				var sm := ShaderMaterial.new()
				sm.shader = neb
				sm.set_shader_parameter("col", col)
				mi.material_override = sm
			_:
				mi.mesh = sphere
				var m3 := StandardMaterial3D.new()
				m3.albedo_color = col
				m3.roughness = 0.9
				mi.material_override = m3
		add_child(mi)
		var ring: MeshInstance3D = null
		if bool(b.get("ring", false)) or kind == "blackhole":
			ring = MeshInstance3D.new()
			ring.mesh = disk
			var rm := StandardMaterial3D.new()
			rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rm.albedo_color = Color(1.0, 0.6, 0.25, 0.7) if kind == "blackhole" else Color(col.r, col.g, col.b, 0.45)
			rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rm.cull_mode = BaseMaterial3D.CULL_DISABLED
			ring.material_override = rm
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ring)
		var p: Array = b["pos"]
		items.append({"mi": mi, "ring": ring, "abs": Vec3D.make(p[0], p[1], p[2]), "radius": float(b["radius"]), "kind": kind})


## Place every body for the current camera position. Returns the direction from the camera to the main star (or zero).
func update() -> void:
	if cam == null:
		return
	var cam_abs := ws.to_abs(cam.global_position)
	var far_r := cam.far * FAR_FRACTION
	for it in items:
		var v: Vector3 = (it["abs"] as Vec3D).minus(cam_abs)
		var dist := v.length()
		var mi: MeshInstance3D = it["mi"]
		var radius: float = it["radius"]
		if dist < 1.0:
			mi.visible = false
			continue
		var dir := v / dist
		var pos: Vector3
		var sc: float
		if dist <= far_r:
			pos = cam.global_position + v
			sc = radius
		else:
			pos = cam.global_position + dir * far_r
			sc = radius * far_r / dist
		var visible_ok: bool = sc / far_r > 0.0004 or String(it["kind"]) == "star"
		mi.visible = visible_ok
		if it["kind"] == "nebula":
			mi.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP).scaled(Vector3(sc, sc, sc)), pos + dir * 0.0)
		else:
			mi.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(sc, sc, sc)), pos)
		var ring: MeshInstance3D = it["ring"]
		if ring != null:
			ring.visible = visible_ok
			ring.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(18.0)).scaled(Vector3(sc, sc, sc)), pos)
	# the main star (the biggest in the sky) lights the scene
	var best := -1.0
	for it in items:
		if it["kind"] != "star":
			continue
		var v2: Vector3 = (it["abs"] as Vec3D).minus(cam_abs)
		var ang: float = float(it["radius"]) / maxf(v2.length(), 1.0)
		if ang > best:
			best = ang
			sun_dir = v2.normalized()
