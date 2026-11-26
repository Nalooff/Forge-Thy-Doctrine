extends SceneTree
## Ships that are km long: the optimised paths against exhaustive ones, batched visuals, and cost.
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _big(scale_f: float, n_int: int, n_ext: int) -> Dictionary:
	var src: GDScript = load("res://tests/bench_ship.gd")
	return src.new().big_ship(scale_f, n_int, n_ext)


func _sum_groups(sh: Ship, key: String) -> float:
	var t := 0.0
	for g in sh._groups:
		t += float(g[key])
	return t


func _sum_arr(sh: Ship, key: String, d: int) -> float:
	var t := 0.0
	for g in sh._groups:
		t += float((g[key] as Array)[d])
	return t


func _initialize() -> void:
	# ---- small ships stay exact and unbatched
	var small := Ship.new()
	small.setup(Premades.lance(), 0)
	check(small._exact and not small._batch and small._groups.size() == small.mods.size() or small._groups.size() <= small.mods.size(), "a Lance keeps the exact per-module path (%d groups for %d modules)" % [small._groups.size(), small.mods.size()])
	var nodes_small := small.get_child_count()
	check(nodes_small > 10, "...and one node per external module (%d nodes)" % nodes_small)
	small.free()

	# ---- a 600-module ship: grouped allocation equals the exhaustive sum
	var bp := _big(40.0, 320, 280)
	var sh := Ship.new()
	var t0 := Time.get_ticks_usec()
	sh.setup(bp, 0)
	var setup_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(not sh._exact and sh._batch and sh._groups.size() <= Ship.GROUPS, "%d modules: grouped (%d priority groups), batched visuals" % [sh.mods.size(), sh._groups.size()])
	check(sh.get_child_count() <= 8, "...with %d scene nodes instead of one per module" % sh.get_child_count())
	check(sh._mm_body != null and sh._mm_body.instance_count == sh._bt_body.size() and sh._mm_barrel.instance_count == sh._bt_barrel.size() and sh._mm_flame.instance_count == sh._bt_flame.size(), "body / barrel / flame MultiMeshes hold %d / %d / %d instances" % [sh._bt_body.size(), sh._bt_barrel.size(), sh._bt_flame.size()])
	sh._used = [0.0, 0.0, 0.6, 0.0, 0.0, 0.0]
	sh._firing = false
	sh._allocate_power()
	var demand_sum := 0.0
	var served_sum := 0.0
	for m in sh.mods:
		sh._write_module_power(m)
		demand_sum += float(m["demand"])
		served_sum += float(m["demand"]) * float(m["frac"])
	check(absf(demand_sum - sh.power_demand) < 0.001 * maxf(demand_sum, 1.0), "total demand: groups %.1f MW = modules %.1f MW" % [sh.power_demand, demand_sum])
	check(absf(served_sum - sh._served) < 0.001 * maxf(served_sum, 1.0), "power served: groups %.1f MW = modules %.1f MW" % [sh._served, served_sum])
	# shortage: the groups closest to a generator are served first
	var gens: Array = sh.mods_of("generator")
	for i in range(1, gens.size()):
		sh._hurt_module(gens[i], 1e12, {"modules": []}, null)
	gens[0]["hfrac"] = 0.0005                      # the last generator is overheated: only a fraction of its output
	sh._rebuild_groups()
	sh._used = [0.0, 0.0, 1.0, 0.0, 0.0, 0.0]
	sh._allocate_power()
	var seen_partial := false
	var order_ok := true
	for g in sh._groups:
		var f := float(g["frac"])
		if float(g["demand"]) <= 0.0:
			continue
		if seen_partial and f > 0.0:
			order_ok = false
		if f < 1.0:
			seen_partial = true
	check(seen_partial and order_ok and sh._served <= sh._supply + 1e-3, "short of power: groups are served in priority order, then nothing (served %.1f of %.1f MW)" % [sh._served, sh._supply])
	sh.free()

	# ---- incremental death == full rebuild
	var sh2 := Ship.new()
	sh2.setup(_big(40.0, 320, 280), 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var killed := 0
	for i in 140:
		var m: Dictionary = sh2.mods[rng.randi() % sh2.mods.size()]
		if m["alive"]:
			sh2._hurt_module(m, 1e12, {"modules": []}, null)
			killed += 1
	for et in ["engine_room", "generator", "radar_room"]:
		for m in sh2.mods_of(et).slice(0, 6):
			if m["alive"]:
				sh2._hurt_module(m, 1e12, {"modules": []}, null)
	var snap := {"base": _sum_groups(sh2, "base"), "bar": _sum_groups(sh2, "bar"), "supply": sh2._supply, "gens": sh2._n_gens, "rcs": sh2.rcs_cap}
	var thr_snap: Array = []
	var force_snap: Array = []
	for d in 6:
		thr_snap.append(_sum_arr(sh2, "thr", d))
		force_snap.append(_sum_arr(sh2, "thr_force", d))
	var caps_snap: Array = sh2.caps.duplicate()
	sh2._rebuild_groups()
	var same: bool = absf(snap["base"] - _sum_groups(sh2, "base")) < 0.01 and absf(snap["bar"] - _sum_groups(sh2, "bar")) < 0.01 and absf(snap["supply"] - sh2._supply) < 0.01 and snap["gens"] == sh2._n_gens and absf(snap["rcs"] - sh2.rcs_cap) < 0.01
	for d in 6:
		same = same and absf(float(thr_snap[d]) - _sum_arr(sh2, "thr", d)) < 0.01 and absf(float(force_snap[d]) - _sum_arr(sh2, "thr_force", d)) < 0.01 and absf(float(caps_snap[d]) - float(sh2.caps[d])) < 0.01
	check(same, "after %d+ deaths the incremental update equals a full rebuild (power, thrust, caps, generators)" % killed)
	sh2.free()

	# ---- sliced heat == full pass
	var a := Ship.new()
	a.setup(_big(40.0, 320, 280), 0)
	var b := Ship.new()
	b.setup(_big(40.0, 320, 280), 0)
	b._th_n = 1
	b._th_acc = [0.0]
	for s in [a, b]:
		s._used = [0.0, 0.0, 0.5, 0.0, 0.0, 0.0]
	for i in 60 * 40:
		for s in [a, b]:
			s._allocate_power()
		for m in b.mods:
			b._write_module_power(m)
		a._thermal_step(1.0 / 60.0)
		b._thermal_step(1.0 / 60.0)
	check(a._th_n > 1 and absf(a.hull_temp - b.hull_temp) <= 0.12 * maxf(b.hull_temp, 1.0) + 0.3, "heat in time slices (%d slices) matches the full pass: hull %.2f%% vs %.2f%%" % [a._th_n, a.hull_temp, b.hull_temp])
	check(absf(a.heat_peak - b.heat_peak) <= 0.12 * maxf(b.heat_peak, 1.0) + 1.0, "hottest module %.1f%% vs %.1f%%" % [a.heat_peak, b.heat_peak])
	a.free()
	b.free()

	# ---- the spatial grid returns every module a segment or a sphere can touch
	var sh3 := Ship.new()
	sh3.setup(_big(120.0, 2000, 990), 0)
	var hb := ShipData.hull_bounds(sh3.bp["rings"])
	var miss := 0
	var cand_total := 0
	var trials := 150
	for i in trials:
		var p0 := hb.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * hb.size
		var p1 := p0 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(5.0, 400.0)
		var got: Array = sh3.modules_along(p0, p1)
		cand_total += got.size()
		var ids := {}
		for m in got:
			ids[int(m["id"])] = true
		for m in sh3.mods:
			if (m["box"] as AABB).intersects_segment(p0, p1) != null and not ids.has(int(m["id"])):
				miss += 1
	check(miss == 0, "grid: no module missed along %d random segments of a %d-module ship" % [trials, sh3.mods.size()])
	check(float(cand_total) / trials < 0.1 * sh3.mods.size(), "...and it looks at %.0f modules per segment instead of %d" % [float(cand_total) / trials, sh3.mods.size()])
	var miss2 := 0
	for i in 60:
		var p := hb.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * hb.size
		var r := rng.randf_range(2.0, 60.0)
		var got2: Array = sh3.modules_near(p, r)
		var ids2 := {}
		for m in got2:
			ids2[int(m["id"])] = true
		for m in sh3.mods:
			if (m["box"] as AABB).grow(0.0).intersects(AABB(p - Vector3(r, r, r), Vector3(r, r, r) * 2.0)) and not ids2.has(int(m["id"])):
				miss2 += 1
	check(miss2 == 0, "grid: no module missed around 60 random points")
	# hits still work through the grid
	var ext: Dictionary = {}
	for m in sh3.mods:
		if m["kind"] == "external" and m["alive"]:
			ext = m
			break
	var cp: Vector3 = ext["pos"]
	var hit = sh3.ext_module_ray(sh3.to_global(cp + Vector3(0, 6, 0)), sh3.to_global(cp - Vector3(0, 6, 0)))
	check(hit != null, "a ray through an external module still finds it")

	# ---- batched visuals follow damage, slewing and death
	var sh4 := Ship.new()
	sh4.setup(_big(40.0, 40, 120), 0)
	get_root().add_child(sh4)
	await physics_frame
	var th: Dictionary = sh4.mods_of("thruster")[0]
	var gun: Dictionary = sh4.mods_of("barrel")[0]
	if DisplayServer.get_name() == "headless":
		print("SKIP  batched visual read-back (the headless renderer keeps no MultiMesh data; run under xvfb to check)")
	else:
		var col0: Color = sh4._mm_body.get_instance_color(int(th["mmb"]))
		sh4._hurt_module(th, 1e12, {"modules": []}, null)
		check(sh4._mm_body.get_instance_color(int(th["mmb"])).r < 0.1 and col0.r > 0.1, "a destroyed module goes dark in the batch")
		sh4.revive()
		check(sh4._mm_body.get_instance_color(int(th["mmb"])).is_equal_approx(col0), "revive restores it")
		var x0: Transform3D = sh4._mm_barrel.get_instance_transform(int(gun["mmc"]))
		check(x0.origin.is_equal_approx(gun["cur_pos"]), "a barrel instance sits at its module position")
		sh4._die(null)
		check(sh4._mm_flame.get_instance_transform(int(th["mmf"])).basis.get_scale().y < 0.001, "a dead ship has no flames")
	sh4.queue_free()

	# ---- cost: frame time does not grow with the module count
	var med := {}
	for cfg in [[20.0, 120, 80], [120.0, 2000, 990]]:
		var s5 := Ship.new()
		var ts := Time.get_ticks_usec()
		s5.setup(_big(cfg[0], cfg[1], cfg[2]), 0)
		var sms := (Time.get_ticks_usec() - ts) / 1000.0
		get_root().add_child(s5)
		s5.gravity_scale = 0.0
		s5.cmd = {"move": Vector3(0, 0, 1), "fire": false, "auto": false}
		for i in 20:
			await physics_frame
		var vals: Array = []
		for i in 90:
			await physics_frame
			vals.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		vals.sort()
		med[s5.mods.size()] = float(vals[45])
		print("      %d modules: setup %.0f ms, physics frame median %.2f ms" % [s5.mods.size(), sms, vals[45]])
		check(sms < 4000.0, "%d modules: setup %.0f ms" % [s5.mods.size(), sms])
		s5.queue_free()
		await process_frame
	var keys := med.keys()
	keys.sort()
	check(float(med[keys[1]]) < 8.0 and float(med[keys[1]]) < 4.0 * float(med[keys[0]]) + 1.0, "frame cost: %.2f ms for %d modules vs %.2f ms for %d (%dx the modules)" % [med[keys[1]], keys[1], med[keys[0]], keys[0], keys[1] / keys[0]])

	# ---- killing hundreds of modules in one frame does not stall
	var big := Ship.new()
	big.setup(_big(120.0, 2000, 990), 0)
	var tk := Time.get_ticks_usec()
	var n_kill := 0
	for m in big.mods:
		if n_kill >= 600:
			break
		if m["alive"]:
			big._hurt_module(m, 1e12, {"modules": []}, null)
			n_kill += 1
	var kms := (Time.get_ticks_usec() - tk) / 1000.0
	check(kms < 400.0, "destroying %d modules of a %d-module ship takes %.0f ms in total (no rebuild per death)" % [n_kill, big.mods.size(), kms])
	big.free()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
