class_name CamRig
extends Node3D
## Commander camera (free orbit, GDD 4.1) and first-person view from the Commander Post.

var cam: Camera3D
var ship: Ship
var first_person := false
var yaw := 0.6
var pitch := -0.35
var dist := 40.0
var shake_t := 0.0
var shake_amp := 0.0
# tactical map view (GDD 4.3 view 2): high camera over the XZ plane, free pan / orbit / zoom
var map_mode := false
var map_follow := true
var map_focus := Vector3.ZERO
var map_dist := 2500.0
var map_yaw := 0.0
var map_pitch := -1.1


func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 40000.0
	cam.fov = 70.0
	add_child(cam)
	cam.current = true


func follow(s: Ship) -> void:
	ship = s
	dist = clampf(float(s.stats["longest"]) * 2.4, 12.0, 400000.0)


func set_map_mode(on: bool) -> void:
	map_mode = on
	if on:
		first_person = false
		map_follow = true
		if ship != null and is_instance_valid(ship):
			map_focus = ship.global_position
			map_dist = maxf(map_dist, float(ship.stats["longest"]) * 8.0)


func shake(amount: float) -> void:
	shake_amp = amount
	shake_t = 0.45


func unhandled(event: InputEvent) -> void:
	if first_person:
		return
	if map_mode:
		if event is InputEventMouseMotion:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				map_yaw -= event.relative.x * 0.005
				map_pitch = clampf(map_pitch - event.relative.y * 0.005, -1.55, -0.12)
			elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
				map_follow = false
				var b := cam.global_transform.basis
				var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
				var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
				map_focus += (-right * event.relative.x + fwd * event.relative.y) * map_dist * 0.0016
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				map_dist = maxf(map_dist * 0.88, 60.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				map_dist = minf(map_dist * 1.14, maxf(30000.0, _ship_len() * 40.0))
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(dist * 0.9, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(dist * 1.1, maxf(60000.0, _ship_len() * 12.0))


func cp_view() -> Dictionary:
	if ship == null:
		return {}
	for m in ship.mods_of("commander_post"):
		if m["alive"]:
			var d: Vector3 = ShipData.DIRS[int(m["dir"])]
			var half: float = (m["size"] as Vector3)[ShipData.DIR_AXIS[int(m["dir"])]] * 0.5
			return {"pos": (m["pos"] as Vector3) + d * half * 0.55, "dir": d}
	return {}


func _ship_len() -> float:
	return float(ship.stats["longest"]) if ship != null and is_instance_valid(ship) else 20.0


## Near and far planes follow the view distance, so a 100 km ship and a 5 m fighter both draw without z-fighting
## and without being clipped (far plane at least 40 km, near plane a thousandth of the distance to the ship).
func _fit_planes() -> void:
	var d := map_dist if (map_mode and not first_person) else dist
	var want_far := clampf(maxf(40000.0, d * 6.0 + _ship_len() * 3.0), 40000.0, 5.0e7)
	var want_near := clampf(d * 0.0015, 0.1, 3000.0)
	if first_person:
		want_near = 0.1
	cam.far = lerpf(cam.far, want_far, 0.25) if absf(cam.far - want_far) > want_far * 0.02 else want_far
	cam.near = lerpf(cam.near, want_near, 0.25) if absf(cam.near - want_near) > want_near * 0.02 else want_near


func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	_fit_planes()
	var t_basis := ship.global_transform.basis
	if first_person:
		var v := cp_view()
		if v.is_empty():
			first_person = false
		else:
			var d: Vector3 = v["dir"]
			var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
			global_transform = Transform3D(t_basis * Basis.looking_at(d, up), ship.to_global(v["pos"]))
			cam.position = Vector3.ZERO
	if map_mode and not first_person:
		var c := ship.global_position if map_follow else map_focus
		var moff := Vector3(0, 0, map_dist).rotated(Vector3.RIGHT, map_pitch).rotated(Vector3.UP, map_yaw)
		global_transform = Transform3D(Basis.looking_at(-moff, Vector3.UP), c + moff)
		cam.position = Vector3.ZERO
	elif not first_person:
		var center := ship.to_global(ship.stats["com"] as Vector3)
		var off := Vector3(0, 0, dist).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
		global_transform = Transform3D(Basis.looking_at(-off, Vector3.UP), center + off)
		cam.position = Vector3.ZERO
	if shake_t > 0.0:
		shake_t -= delta
		cam.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake_amp * (shake_t / 0.45)


func cp_view_empty_check() -> bool:
	return cp_view().is_empty()
