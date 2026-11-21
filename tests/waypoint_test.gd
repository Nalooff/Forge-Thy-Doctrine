extends SceneTree
## Headless check of the waypoint movement system: godot --headless --path . --script res://tests/waypoint_test.gd
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _initialize() -> void:
	var g: Node = get_root().get_node("Game")
	g.session = {"mode": "sandbox", "ship": Premades.dart(), "return_scene": "res://scenes/main_menu.tscn"}
	var ar: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(ar)
	await physics_frame
	await physics_frame
	check(not ar.has_wp, "no waypoint at start")
	ar.set_order("goto")
	check(ar.order == "none", "goto without a waypoint is refused")
	# tactical map + plane picking
	ar.set_map_mode(true)
	await process_frame
	await process_frame
	check(ar.rig.map_mode and not ar.rig.first_person, "tactical map view on")
	var vp := get_root().get_visible_rect().size
	var h = ar._plane_hit(vp * 0.5, ar.player.global_position.y)
	check(h != null and absf((h as Vector3).y - ar.player.global_position.y) < 0.01, "click ray hits the XZ plane at ship altitude")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = vp * 0.5
	var used: bool = ar._map_input(ev)
	check(used and ar.has_wp and ar.order == "goto", "LMB on the map sets the waypoint and starts flying to it")
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	ar._map_input(rel)
	# altitude change
	ar.waypoint.y += 120.0
	ar.set_map_mode(false)
	check(not ar.rig.map_mode, "back to the standard view")
	# fly there
	var start: Vector3 = ar.player.global_position
	ar.set_waypoint(start + Vector3(0, 100, -600))
	Engine.time_scale = 8.0
	var f0 := Engine.get_physics_frames()
	var ticks := 0
	while Engine.get_physics_frames() - f0 < 60 * 120 and ar.order == "goto":
		await physics_frame
	ticks = Engine.get_physics_frames() - f0
	Engine.time_scale = 1.0
	var d: float = ar.wp_dist()
	print("arrived after %d physics ticks, distance left %.1f m, speed %.2f m/s" % [ticks, d, ar.player.linear_velocity.length()])
	check(ar.order == "hold" and d < 25.0 and ar.player.linear_velocity.length() < 12.0, "ship reaches the waypoint (including 100 m of altitude) and holds")
	ar.clear_waypoint()
	check(not ar.has_wp, "waypoint cleared")
	print("FAILS: ", fails)
	quit(fails)
