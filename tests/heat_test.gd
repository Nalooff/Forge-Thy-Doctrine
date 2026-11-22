extends SceneTree
## Headless check of the Heat system (ship simulation, HUD gauge, Panel 1 heat map).
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


## Demands for the thermal step: "idle", "hard" (forward thrusters + every barrel at peak), "off".
func load_all(sh: Ship, mode: String) -> void:
	var supply := 0.0
	var demand := 0.0
	for m in sh.mods:
		var ms: Dictionary = m["ms"]
		var d := float(ms["idle"])
		if mode == "hard":
			if m["type"] == "thruster":
				d = float(ms["peak"]) * (1.0 if int(m["dir"]) == 0 else 0.0)
			elif m["type"] == "barrel":
				d = float(ms["peak"])
		elif mode == "off":
			d = 0.0
		m["demand"] = d
		demand += d
		if m["type"] == "generator":
			supply += float(ms["out"]) * float(m["hfrac"])
	var f := minf(1.0, supply / maxf(demand, 0.001))
	for m in sh.mods:
		m["frac"] = f if float(m["demand"]) > 0.0 else 1.0


func run(sh: Ship, mode: String, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		load_all(sh, mode)
		sh._thermal_step(0.05)
		t += 0.05


func _initialize() -> void:
	# ---- helpers
	check(is_equal_approx(ShipData.heat_factor(70.0), 1.0) and is_equal_approx(ShipData.heat_factor(80.0), 1.0), "no output loss up to the warning temperature")
	check(absf(ShipData.heat_factor(95.0) - 0.7) < 0.01 and is_equal_approx(ShipData.heat_factor(110.0), 0.4) and is_equal_approx(ShipData.heat_factor(250.0), 0.4), "output falls to 40% at 110% and no lower")
	check(ShipData.heat_color(0.0) != ShipData.heat_color(100.0) and ShipData.heat_color(30.0).b > ShipData.heat_color(90.0).b, "heat colour runs from blue to red")

	# ---- stats for the editor
	var lance := Premades.lance()
	var anvil := Premades.anvil()
	var sl := ShipData.compute_stats(lance)
	var sa := ShipData.compute_stats(anvil)
	check(float(sl["heat_idle"]) < float(sl["heat_hard"]) and float(sa["heat_idle"]) < float(sa["heat_hard"]), "editor stats: hard use heats more than idle (Lance %d%% / %d%%, Anvil %d%% / %d%%)" % [sl["heat_idle"], sl["heat_hard"], sa["heat_idle"], sa["heat_hard"]])

	# ---- per-module thermal factor
	var sh := Ship.new()
	sh.setup(lance, 0)
	var seen := {}
	var in_range := true
	for m in sh.mods:
		var f := float(m["hfac"])
		in_range = in_range and f >= 0.75 and f <= 1.25
		if m["type"] == "thruster":
			seen[snappedf(f, 0.001)] = true
	check(in_range, "thermal factors stay within 0.75 .. 1.25")
	check(seen.size() >= 2, "identical thrusters do not all run equally hot (%d different factors)" % seen.size())
	var sh2 := Ship.new()
	sh2.setup(lance, 0)
	var same := true
	for i in range(sh.mods.size()):
		same = same and is_equal_approx(float(sh.mods[i]["hfac"]), float(sh2.mods[i]["hfac"]))
	check(same, "the same blueprint always gets the same thermal factors")
	sh2.free()

	# ---- idle, hard use, cool-down
	run(sh, "idle", 120.0)
	var idle_peak := 0.0
	for m in sh.mods:
		idle_peak = maxf(idle_peak, float(m["heat"]))
	check(sh.hull_temp < 20.0 and idle_peak < 25.0, "idle for 2 min stays cold (hull %.1f%%, hottest %.1f%%)" % [sh.hull_temp, idle_peak])
	var prev := sh.hull_temp
	run(sh, "hard", 120.0)
	check(sh.hull_temp > prev + 30.0, "hard use for 2 min heats the hull (%.1f%% -> %.1f%%)" % [prev, sh.hull_temp])
	run(sh, "hard", 120.0)
	var any_warn := false
	var min_hfrac := 1.0
	var all_alive := true
	for m in sh.mods:
		any_warn = any_warn or float(m["heat"]) >= ShipData.HEAT_WARN
		min_hfrac = minf(min_hfrac, float(m["hfrac"]))
		all_alive = all_alive and bool(m["alive"])
	check(any_warn and min_hfrac < 1.0, "after 4 min some module overheats and loses output (min output x%.2f)" % min_hfrac)
	check(all_alive and sh.hull_hp > sh.hull_hp_max * 0.99, "the Lance does not burn itself out under sustained fire")
	sh._refresh_heat_summary()
	check(sh.heat_peak >= ShipData.HEAT_WARN and not sh.heat_hottest.is_empty(), "summary names the hottest module (%s %d%%)" % [sh.heat_hottest["label"], int(sh.heat_peak)])
	var hb := ShipData.hull_bounds(lance["rings"]).grow(1.0)
	check(hb.has_point(sh.heat_centroid), "centre of heat is inside the ship (%.1f, %.1f, %.1f)" % [sh.heat_centroid.x, sh.heat_centroid.y, sh.heat_centroid.z])
	run(sh, "off", 240.0)
	check(sh.hull_temp < 10.0, "switched off for 4 min the ship cools down (hull %.1f%%)" % sh.hull_temp)

	# ---- centre of heat follows the hot module
	var hot_mod: Dictionary = {}
	for m in sh.mods:
		m["heat"] = 0.0
		if m["type"] == "thruster" and (hot_mod.is_empty() or (m["pos"] as Vector3).z > (hot_mod["pos"] as Vector3).z):
			hot_mod = m
	hot_mod["heat"] = 90.0
	sh._refresh_heat_summary()
	check(sh.heat_centroid.distance_to(hot_mod["pos"]) < 0.01, "with one hot module the centre of heat sits on it")

	# ---- burning
	var victim: Dictionary = hot_mod
	victim["heat"] = 130.0
	var hp0 := float(victim["hp"])
	run(sh, "off", 5.0)
	check(float(victim["hp"]) < hp0 and bool(victim["alive"]), "above 100%% a module takes damage (%.0f -> %.0f hp)" % [hp0, float(victim["hp"])])
	var gen: Dictionary = sh.mods_of("generator")[0]
	gen["heat"] = 105.0
	sh._thermal_step(0.01)
	check(float(gen["hfrac"]) < 0.6, "an overheated generator delivers less power (x%.2f)" % float(gen["hfrac"]))
	var dead: Dictionary = sh.mods_of("radar_room")[0]
	dead["alive"] = false
	dead["demand"] = 5.0
	dead["frac"] = 1.0
	sh._thermal_step(0.05)
	check(float(dead["hwaste"]) == 0.0, "a destroyed module produces no heat")
	sh.free()

	# ---- HUD gauge, warning and Panel 1 heat map in a real arena
	var g: Node = get_root().get_node("Game")
	g.session = {"mode": "sandbox", "ship": Premades.lance(), "return_scene": "res://scenes/main_menu.tscn"}
	var ar: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(ar)
	for i in 8:
		await physics_frame
		await process_frame
	var s: Ship = ar.player
	var hud = ar.hud
	var pv = hud.preview
	var thr: Dictionary = s.mods_of("thruster")[0]
	thr["heat"] = 92.0
	s.hull_temp = 60.0
	for i in 40:
		await physics_frame
		await process_frame
	check(float(hud.bar_heat.value) > 0.6, "HEAT gauge follows the hottest module (%.2f)" % float(hud.bar_heat.value))
	check(hud._heat_warned.size() >= 1, "an overheating warning was raised once")
	pv.set_view(pv.SYSTEMS)
	pv.sys_mode = 2
	pv._apply_view()
	pv.refresh()
	await process_frame
	check(pv.heat_mi.visible, "heat marker shown in the Systems / Heat view")
	thr["heat"] = 92.0
	var col: Color = pv._module_color(thr)
	check(col.is_equal_approx(ShipData.heat_color(float(thr["heat"]))), "Panel 1 colours modules by temperature")
	thr["heat"] = 92.0
	var lines: Array = pv.info_lines({"kind": "module", "id": int(thr["id"])})
	var has_heat := false
	for l in lines:
		has_heat = has_heat or String(l["t"]).begins_with("Heat")
	check(has_heat and String(lines[1]["t"]).begins_with("OVERHEATING"), "module card shows the heat line and the OVERHEATING status (%s)" % String(lines[1]["t"]))
	check(pv._status_line().begins_with("hull") and pv._status_line().contains("hot"), "Panel 1 header: %s" % pv._status_line())
	hud.set_mode("Power & Systems")
	hud._refresh_sub()
	check(String(hud.sub_text.text).contains("HEAT"), "Power & Systems panel lists the heat")
	ar.queue_free()
	await process_frame
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
