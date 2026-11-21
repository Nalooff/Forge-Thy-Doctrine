extends SceneTree
## Headless check of per-turret targeting and the turret selection helpers.
var fails := 0
var ar: Node

func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _initialize() -> void:
	var g: Node = get_root().get_node("Game")
	g.session = {"mode": "sandbox", "ship": Premades.lance(), "return_scene": "res://scenes/main_menu.tscn"}
	ar = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(ar)
	for i in 8:
		await physics_frame
		await process_frame
	var a: Ship = ar._dummy
	var b: Ship = ar._spawn_ship(Premades.anvil(), 1, a.global_position + Vector3(150, 0, 0), Vector3(0, 0, 1))
	ar.player.target = a
	for i in 4:
		await physics_frame
	var units: Array = ar.weapon_units()
	print("units: ", units.map(func(u): return ar.weapon_unit_text(u)))
	check(units.size() >= 1, "the ship exposes weapon units (turret bays / fixed barrels)")
	ar.select_weapons("all")
	check(ar.sel_weapons.size() == units.size(), "Select all")
	ar.select_weapons("none")
	check(ar.sel_weapons.is_empty(), "Select none")
	ar.select_weapons("invert")
	check(ar.sel_weapons.size() == units.size(), "Invert from nothing selects everything")
	ar.select_weapons("kinetic")
	var nk := 0
	for u in units:
		if (u["kinds"] as Array).has("kinetic"):
			nk += 1
	check(ar.sel_weapons.size() == nk, "Select kinetic (%d)" % nk)
	ar.select_weapons("best")
	check(not ar.sel_weapons.is_empty(), "Select best finds turrets that can hit the lock")
	ar.select_weapons("idle")
	check(ar.sel_weapons.size() == units.size(), "all turrets start idle (follow the lock)")
	# assignment
	ar.select_weapons("all")
	ar.assign_weapons(b, "ship")
	var u0: Dictionary = ar.weapon_units()[0]
	var barrel: Dictionary = ar.player.by_id[int((u0["barrels"] as Array)[0])]
	check(u0["tmode"] == "ship" and ar.player.barrel_aim_target(barrel) == b, "assigned turret engages its own target, not the lock")
	ar.select_weapons("idle")
	check(ar.sel_weapons.is_empty(), "assigned turrets are no longer idle")
	for i in 30:
		await physics_frame
	var o: Vector3 = ar.player.to_global(barrel["cur_pos"])
	var aim_w: Vector3 = ar.player._barrel_aim_world(barrel)
	var to_b: float = (aim_w - o).angle_to(b.global_position - o)
	var to_a: float = (aim_w - o).angle_to(a.global_position - o)
	check(to_b < to_a, "the barrel points at its assigned target (%.1f deg off B vs %.1f deg off A)" % [rad_to_deg(to_b), rad_to_deg(to_a)])
	b.alive = false
	check(ar.player.barrel_aim_target(barrel) == a, "if the assigned target dies the turret falls back to the lock")
	b.alive = true
	ar.select_weapons("all")
	ar.assign_weapons(null, "cursor")
	check(ar.player.barrel_aim_target(barrel) == null, "cursor mode aims at the cursor, not at a ship")
	ar.assign_weapons(null, "main")
	check(ar.player.barrel_aim_target(barrel) == a, "back to the locked target")
	# HUD list
	ar.hud.set_mode("Combat")
	await process_frame
	check(ar.hud.weapon_list != null and ar.hud.weapon_list.item_count == units.size(), "Combat panel lists the turrets")
	ar.select_weapons("all")
	check(ar.hud.weapon_list.is_selected(0), "the list shows the selection")
	# pick a ship in the 3D view
	ar.set_map_mode(true)
	for i in 6:
		await process_frame
	ar.hud.sub_open = true
	ar.tuner.begin("wpick")
	var sp: Vector2 = ar.rig.cam.unproject_position(b.global_position)
	var m := InputEventMouseMotion.new()
	m.position = sp
	ar.tuner.handle(m)
	var c := InputEventMouseButton.new()
	c.button_index = MOUSE_BUTTON_LEFT
	c.position = sp
	c.pressed = true
	ar.tuner.handle(c)
	check(not ar.tuner.active and ar.weapon_units()[0]["tmode"] == "ship" and ar.weapon_units()[0]["tgt"] == b, "Pick a ship: clicking assigns the selected turrets")
	check(not ("Tactical Map" in ar.hud.MODES), "Tactical Map mode removed from the console")
	print("FAILS: ", fails)
	quit(fails)
