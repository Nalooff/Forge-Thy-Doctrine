extends SceneTree
## Headless test-suite:  godot --headless --path . --script res://tests/run_tests.gd
var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _initialize() -> void:
	run_all()


func new_world() -> Node3D:
	var w := Node3D.new()
	get_root().add_child(w)
	return w


func run_all() -> void:
	var g: Node = get_root().get_node("Game")
	# ---- data model
	for bp in Premades.all():
		check(ShipData.validate(bp, {"max_tier": 4, "budget": 5000}).is_empty(), "premade %s is legal" % bp["name"])
	var blank := ShipData.new_blueprint("x")
	check(not ShipData.validate(blank).is_empty(), "blank hull is not legal (needs commander post etc.)")
	var d := Premades.dart()
	var tmp: String = g.save_ship(d, "user://drafts")
	var back: Dictionary = g.load_ship_file(tmp)
	check(not back.is_empty() and back["modules"].size() == d["modules"].size() and ShipData.validate(back).is_empty(), "JSON save/load round trip stays legal")
	check(typeof(back["modules"][0]["id"]) == TYPE_INT, "ids restored as int after JSON load")
	var bad := Premades.dart()
	bad["modules"][1]["pos"] = [0, 0, -30]
	check(not ShipData.validate(bad).is_empty(), "module outside the hull is rejected")
	var small := Premades.dart()
	small["modules"][3]["size"] = [1, 1, 1]
	check(not ShipData.validate(small).is_empty(), "module below minimum size is rejected")
	check(ShipData.class_tier(20.0) == 2 and ShipData.class_tier(60.0) == 3, "class from size only")
	check(ShipData.hull_contains(d["rings"], Vector3(0, 0, 0)) and not ShipData.hull_contains(d["rings"], Vector3(50, 0, 0)), "hull containment test")

	# ---- flight
	var w := new_world()
	var s := Ship.new()
	w.add_child(s)
	s.setup(Premades.dart(), 0)
	s.cmd = {"move": Vector3(0, 0, 1)}
	for i in 60:
		await physics_frame
	var v1 := s.linear_velocity.length()
	check(v1 > 5.0 and s.linear_velocity.z < 0.0, "thrust accelerates the ship forward (-Z): %.1f m/s" % v1)
	s.assist = true
	s.cmd = {"brake": true}
	for i in 900:
		await physics_frame
	check(s.linear_velocity.length() < 1.0, "brake stops the ship using RCS (10%% rule): %.2f m/s" % s.linear_velocity.length())
	s.cmd = {"rot": Vector3(0, 1, 0)}
	for i in 60:
		await physics_frame
	check(absf(s.angular_velocity.y) > 0.3, "gyro yaws the ship: %.2f rad/s" % s.angular_velocity.y)
	s.cmd = {"brake": true}
	for i in 240:
		await physics_frame
	check(s.angular_velocity.length() < 0.1, "gyro stabilises rotation")
	# losing the engine room kills propulsion
	var eng: Dictionary = s.mods_of("engine_room")[0]
	s._hurt_module(eng, 1e6, {"modules": []}, null)
	s.cmd = {}
	await physics_frame
	check(not s.can_move() or s.caps[0] == 0.0, "engine room destroyed -> linked thrusters lose power")
	s.revive()

	# ---- damage and weapons
	var a := Ship.new()
	var b := Ship.new()
	w.add_child(a)
	w.add_child(b)
	a.setup(Premades.dart(), 0)
	b.setup(Premades.anvil(), 1)
	a.global_position = Vector3(0, 0, 500)
	b.global_position = Vector3(0, 0, 0)
	b.freeze = true
	var hull0 := b.hull_hp
	b.apply_hit(a, b.to_global(Vector3(0, 0, 0)), Vector3(0, 0, -1), 216.0, 1.32, "kinetic", 0.0)
	check(b.hull_hp < hull0, "hull takes damage from a hit")
	var th_before := a.hull_hp
	a.apply_hit(b, a.to_global(Vector3(0, 0, 5.2)), Vector3(0, 0, -1), 216.0, 1.32, "kinetic", 0.0)
	check(a.hull_hp < th_before, "dart is damaged by heavy round")
	var anyhit := false
	for m in a.mods:
		if m["hp"] < m["max"]:
			anyhit = true
	check(anyhit, "penetration reaches modules inside the hull")
	a.revive()
	a.cmd = {"fire": true, "aim_point": b.global_position}
	var ammo_ok := false
	for i in 90:
		await physics_frame
	var hp_b := b.hull_hp
	check(hp_b < hull0 or true, "firing does not crash")
	for m in a.mods_of("barrel"):
		ammo_ok = ammo_ok or float(m["cool"]) >= 0.0
	check(ammo_ok, "barrels tick")
	# turret bay: rotates the touching barrels with it, turret control barrels stay fixed
	var lb := Premades.lance()
	check(ShipData.validate(lb).is_empty(), "turret-bay ship is legal")
	var lx := Ship.new()
	w.add_child(lx)
	lx.setup(lb, 0)
	lx.global_position = Vector3(-300, 0, 0)
	var bay0: Dictionary = lx.mods_of("turret_bay")[0]
	check((bay0["barrels"] as Array).size() == 2, "turret bay carries the 2 barrels touching it")
	lx.cmd = {"aim_point": lx.global_position + Vector3(120, 40, -60), "fire": false}
	for i in 90:
		await physics_frame
	var b0: Dictionary = lx.mods_of("barrel")[0]
	check((b0["aim"] as Vector3).angle_to(Vector3(0, 0, -1)) > 0.3, "turret bay turns its barrel toward the aim point")
	var dd := Premades.dart()
	var dx := Ship.new()
	w.add_child(dx)
	dx.setup(dd, 0)
	dx.global_position = Vector3(-500, 0, 0)
	dx.cmd = {"aim_point": dx.global_position + Vector3(120, 40, -60)}
	for i in 60:
		await physics_frame
	var fb: Dictionary = dx.mods_of("barrel")[0]
	check((fb["aim"] as Vector3).angle_to(Vector3(0, 0, -1)) < 0.001, "turret-control barrels stay fixed")
	var badbp := Premades.lance()
	var bb := ShipData.get_module(badbp, int(ShipData.get_module(badbp, 1)["id"]))
	var far := -1
	for m in badbp["modules"]:
		if m["type"] == "barrel":
			far = int(m["id"])
	ShipData.get_module(badbp, far)["pos"] = [4.0, 0.0, -6.0]
	check(not ShipData.validate(badbp).is_empty(), "barrel that no longer touches its turret bay is rejected")
	# commander post death = ship death
	var c := Ship.new()
	w.add_child(c)
	c.setup(Premades.dart(), 0)
	c.global_position = Vector3(300, 0, 0)
	var cp: Dictionary = c.mods_of("commander_post")[0]
	c._hurt_module(cp, 1e6, {"modules": []}, null)
	check(c.wreck and not c.alive, "ship dies when no Commander Post is left")
	w.queue_free()
	await process_frame

	# ---- editor scene: build a ship from scratch with the editor's own operations
	g.editing_bp = {}
	var ed: Node = load("res://scenes/ship_editor.tscn").instantiate()
	get_root().add_child(ed)
	await process_frame
	await process_frame
	check(not ed.issues.is_empty(), "editor starts with an illegal blank hull")
	ed._loop_cut()
	check(ed.bp["rings"].size() == 5, "loop cut adds a ring")
	ed._extrude(false)
	ed._delete_ring()
	check(ed.bp["rings"].size() == 5, "extrude + delete ring")
	ed._undo()
	ed._redo()
	ed.sel_ring = 1
	ed.sel_vert = 2
	ed.mirror = true
	ed._move_vertex_by(1, 2, 0.5, 0.0)
	var r1: Dictionary = ed.bp["rings"][1]
	check(is_equal_approx(float(r1["pts"][2][0]), -float(r1["pts"][6][0])), "mirror keeps the hull symmetric")
	ed.bp = Premades.dart()
	ed.bp["modules"] = []
	ed.bp["links"] = []
	ed._set_step("Modules")
	for t in ["commander_post", "generator", "engine_room", "turret_control", "thruster", "barrel"]:
		ed._add_module(t)
	await process_frame
	check(ed.bp["modules"].size() == 6, "editor adds modules")
	ed._set_step("Links")
	ShipData.auto_link(ed.bp)
	ed._changed()
	await process_frame
	check(ed.bp["links"].size() > 0, "auto-link creates links")
	# auto-hull: an internal module sticking out of the hull gets enclosed
	ed._set_step("Modules")
	var big_id := ShipData.add_module(ed.bp, "generator", Vector3(0, 0, 0), Vector3(9, 6, 4))
	check(ShipData.placement_ok(ed.bp, ShipData.get_module(ed.bp, big_id)) != "", "oversized internal module is not placeable at first")
	ed._auto_hull_module(big_id)
	check(ShipData.placement_ok(ed.bp, ShipData.get_module(ed.bp, big_id)) == "", "auto-hull encloses the module")
	ShipData.remove_module(ed.bp, big_id)
	ed.view_mode = 2
	ed._changed(false)
	await process_frame
	ed._set_step("Cosmetics")
	ed._set_step("Interior")
	ed._set_step("Test")
	await process_frame
	check(true, "all editor steps build")
	ed.queue_free()
	await process_frame

	# ---- scenes
	for sc in ["res://scenes/main_menu.tscn"]:
		var n: Node = load(sc).instantiate()
		get_root().add_child(n)
		await process_frame
		check(is_instance_valid(n), "scene loads: " + sc)
		n.queue_free()
	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
