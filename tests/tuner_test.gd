extends SceneTree
## Headless check of the movement tuning modes: godot --headless --path . --script res://tests/tuner_test.gd
var fails := 0
var ar: Node
var vp := Vector2.ZERO

func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func motion(pos: Vector2, alt := false, rel := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	e.alt_pressed = alt
	ar.tuner.handle(e)

func click(pos: Vector2, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = pos
	e.pressed = pressed
	e.shift_pressed = shift
	ar.tuner.handle(e)

func run_for(frames: int) -> void:
	Engine.time_scale = 8.0
	var f0 := Engine.get_physics_frames()
	while Engine.get_physics_frames() - f0 < frames:
		await physics_frame
	Engine.time_scale = 1.0

func screen_of(p: Vector3) -> Vector2:
	return ar.rig.cam.unproject_position(p)

func _initialize() -> void:
	var g: Node = get_root().get_node("Game")
	g.session = {"mode": "sandbox", "ship": Premades.dart(), "return_scene": "res://scenes/main_menu.tscn"}
	ar = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(ar)
	for i in 8:
		await physics_frame
		await process_frame
	vp = get_root().get_visible_rect().size
	var dummy: Ship = ar._dummy
	var c := vp * 0.5 + Vector2(0, 120)

	# --- drive to point: plane, look preview, Alt height, click to go
	ar.hud.set_mode("Movement")
	ar.tuner.begin("point")
	check(ar.tuner.active and not ar.hud.sub_open, "Drive to point: tuning starts and hides the sub panel")
	motion(c)
	check(ar.tuner.look_point() != null, "ship looks at the cursor point on the plane")
	var y0: float = ar.tuner.plane_y
	motion(c, true, Vector2(0, -60))
	check(ar.tuner.plane_y > y0 + 1.0, "Alt + mouse up raises the plane")
	motion(c)
	click(c, true)
	click(c, false)
	check(not ar.tuner.active and ar.order == "goto" and ar.has_wp, "click confirms and the ship drives to the point")
	check(absf(ar.waypoint.y - ar.tuner.plane_y) < 0.5, "destination altitude = chosen plane altitude")
	check(ar.hud.sub_open, "sub panel comes back after confirming")
	# --- optional final heading by click-drag
	ar.tuner.begin("point")
	motion(c)
	click(c, true)
	motion(c + Vector2(160, 0))
	click(c + Vector2(160, 0), false)
	var ed: Vector3 = ar.order_p.get("end_dir", Vector3.ZERO)
	check(ar.order == "goto" and ed.length() > 0.9, "click-drag also sets a final heading")
	# --- cancel restores the previous order
	var prev: String = ar.order
	ar.tuner.begin("orbit")
	ar.tuner.cancel()
	check(not ar.tuner.active and ar.order == prev, "Esc cancels and restores the previous order")
	# --- orbit a ship
	ar.set_order("hold")
	ar.tuner.begin("orbit")
	await process_frame
	motion(screen_of(dummy.global_position))
	click(screen_of(dummy.global_position), true)
	check(ar.tuner.step == "ring", "Orbit: clicking a ship shows the radius circle")
	var dp: Vector3 = dummy.global_position
	ar.tuner.hover = dp
	motion(screen_of(dp + Vector3(0, 0, 0)) + Vector2(0, 0))
	# put the cursor so that the plane hit is ~250 m from the ship
	var want := dp + Vector3(250, 0, 0)
	motion(screen_of(want))
	var r: float = ar.tuner.radius
	check(r > 120.0 and r < 600.0, "mouse distance sets the radius (%.0f m)" % r)
	click(screen_of(want), true)
	check(ar.order == "orbit" and absf(float(ar.order_p["radius"]) - r) < 1.0, "click confirms the orbit")
	await run_for(60 * 25)
	var d2 := Vector2(ar.player.global_position.x - dummy.global_position.x, ar.player.global_position.z - dummy.global_position.z).length()
	print("orbit radius %.0f -> measured %.0f m" % [r, d2])
	check(d2 > r * 0.6 and d2 < r * 1.5, "ship circles the target at about the chosen radius")
	# the camera may not look at the target any more: use the tactical map view for the picks below
	ar.set_map_mode(true)
	for i in 6:
		await process_frame
	# --- orbit on a tilted plane: Alt tilts instead of changing the altitude
	ar.tuner.begin("orbit")
	motion(screen_of(dummy.global_position))
	click(screen_of(dummy.global_position), true)
	var dp2: Vector3 = dummy.global_position
	var yring: float = ar.tuner.plane_y
	motion(screen_of(dp2 + Vector3(250, 0, 0)))
	motion(screen_of(dp2 + Vector3(250, 0, 0)), true, Vector2(0, -80))
	check(ar.tuner.tilt > 0.3 and absf(ar.tuner.plane_y - yring) < 0.01, "Orbit: Alt+mouse tilts the plane and leaves the altitude alone (tilt %.0f deg)" % rad_to_deg(ar.tuner.tilt))
	click(screen_of(dp2 + Vector3(250, 0, 0)), true)
	var nrm: Vector3 = ar.order_p.get("normal", Vector3.UP)
	check(ar.order == "orbit" and nrm.dot(Vector3.UP) < 0.95, "tilted orbit order created")
	var rr := float(ar.order_p["radius"])
	await run_for(60 * 40)
	var rel: Vector3 = ar.player.global_position - dummy.global_position
	print("tilted orbit: radius %.0f, measured %.0f, out of plane %.1f" % [rr, rel.length(), rel.dot(nrm)])
	check(absf(rel.dot(nrm)) < rel.length() * 0.3 and rel.length() > rr * 0.6 and rel.length() < rr * 1.5, "ship circles in the tilted plane")
	# --- drive to ship, keep a distance
	ar.tuner.begin("chase")
	motion(screen_of(dummy.global_position))
	click(screen_of(dummy.global_position), true)
	var want2 := dummy.global_position + Vector3(180, 0, 0)
	motion(screen_of(want2))
	click(screen_of(want2), true)
	check(ar.order == "chase", "Drive to ship: order created")
	await run_for(60 * 40)
	var d3: float = ar.player.global_position.distance_to(dummy.global_position)
	print("chase distance %.0f m (wanted %.0f)" % [d3, float(ar.order_p["dist"])])
	check(absf(d3 - float(ar.order_p["dist"])) < 60.0, "ship settles at the chosen distance from the target")
	# --- follow offset with heading
	ar.tuner.begin("follow")
	motion(screen_of(dummy.global_position))
	click(screen_of(dummy.global_position), true)
	check(ar.tuner.step == "offset", "Follow offset: leader picked, ghost placement")
	var want3 := dummy.global_position + Vector3(0, 0, 120)
	motion(screen_of(want3))
	click(screen_of(want3), true)
	click(screen_of(want3), false)
	check(ar.order == "follow", "follow order created")
	await run_for(60 * 40)
	var dst: Vector3 = dummy.to_global(ar.order_p["offset"])
	print("follow error %.1f m" % ar.player.global_position.distance_to(dst))
	check(ar.player.global_position.distance_to(dst) < 40.0, "ship holds the formation offset")
	# --- facing while moving
	ar.set_order("hold")
	ar.set_facing_lock(Vector3(1, 0, 0))
	var start: Vector3 = ar.player.global_position
	ar.order_goto(start + Vector3(0, 0, -500), Vector3.ZERO)
	await run_for(60 * 12)
	var fwd: Vector3 = ar.player.forward()
	print("heading while moving: dot(+X) = %.2f" % fwd.dot(Vector3.RIGHT))
	check(fwd.dot(Vector3.RIGHT) > 0.8, "locked direction: ship keeps pointing +X while flying elsewhere")
	ar.set_facing_auto()
	check(ar.facing["mode"] == "auto", "facing back to auto")
	# --- route
	ar.set_order("hold")
	ar.tuner.begin("route")
	motion(c)
	click(c, true, true)
	click(c, false, true)
	check(ar.tuner.active and ar.tuner.points.size() == 1, "Route: Shift+click adds a point and stays in tuning")
	var c2 := c + Vector2(120, 0)
	motion(c2)
	click(c2, true)
	click(c2, false)
	check(ar.order == "route" and (ar.order_p["points"] as Array).size() == 2, "plain click ends the route with 2 points")
	# --- lock direction tuning + face
	ar.tuner.begin("lockdir")
	motion(c)
	click(c, true)
	check(ar.facing["mode"] == "lock", "Lock direction tuning sets the locked heading")
	ar.tuner.begin("lookat")
	motion(screen_of(dummy.global_position))
	click(screen_of(dummy.global_position), true)
	check(ar.order == "lookat", "Face: order created")
	print("FAILS: ", fails)
	quit(fails)
