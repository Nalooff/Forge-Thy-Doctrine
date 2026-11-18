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


func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 40000.0
	cam.fov = 70.0
	add_child(cam)
	cam.current = true


func follow(s: Ship) -> void:
	ship = s
	dist = clampf(float(s.stats["longest"]) * 2.4, 12.0, 20000.0)


func shake(amount: float) -> void:
	shake_amp = amount
	shake_t = 0.45


func unhandled(event: InputEvent) -> void:
	if first_person:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(dist * 0.9, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(dist * 1.1, 60000.0)


func cp_view() -> Dictionary:
	if ship == null:
		return {}
	for m in ship.mods_of("commander_post"):
		if m["alive"]:
			var d: Vector3 = ShipData.DIRS[int(m["dir"])]
			var half: float = (m["size"] as Vector3)[ShipData.DIR_AXIS[int(m["dir"])]] * 0.5
			return {"pos": (m["pos"] as Vector3) + d * half * 0.55, "dir": d}
	return {}


func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
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
	if not first_person:
		var center := ship.to_global(ship.stats["com"] as Vector3)
		var off := Vector3(0, 0, dist).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
		global_transform = Transform3D(Basis.looking_at(-off, Vector3.UP), center + off)
		cam.position = Vector3.ZERO
	if shake_t > 0.0:
		shake_t -= delta
		cam.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake_amp * (shake_t / 0.45)


func cp_view_empty_check() -> bool:
	return cp_view().is_empty()
