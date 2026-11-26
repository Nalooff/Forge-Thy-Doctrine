extends SceneTree
## Cost of a physics frame of one ship that thrusts and fires, by number of modules: godot --headless --script res://tests/bench_ship.gd
func big_ship(scale_f: float, n_int: int, n_ext: int) -> Dictionary:
	var bp := Premades.lance()
	bp["interior"] = {"next_id": 1, "entrances": [], "nodes": [], "corridors": []}
	ShipData.scale_ship(bp, scale_f, true)
	var hb := ShipData.hull_bounds(bp["rings"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var added := 0
	var tries := 0
	while added < n_int and tries < n_int * 30:
		tries += 1
		var p := hb.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * hb.size
		if ShipData.hull_contains(bp["rings"], p) and ShipData.hull_contains(bp["rings"], p + Vector3(3, 3, 3)) and ShipData.hull_contains(bp["rings"], p - Vector3(3, 3, 3)):
			var t: String = ["generator", "engine_room", "radar_room"][added % 3]
			ShipData.add_module(bp, t, p, Vector3(4, 4, 4))
			added += 1
	for i in n_ext:
		var z := hb.position.z + hb.size.z * 0.1 + hb.size.z * 0.8 * rng.randf()
		ShipData.add_module(bp, "thruster" if i % 2 == 0 else "barrel", Vector3(rng.randf_range(-1, 1) * hb.size.x * 0.3, hb.end.y - 2.0, z), Vector3(2, 2, 3))
	return bp
func _initialize() -> void:
	for cfg in [["11 modules", 1.0, 0, 0], ["211 modules", 20.0, 120, 80], ["511 modules", 55.0, 300, 200], ["3,000 modules", 120.0, 2000, 990], ["8,000 modules", 250.0, 5500, 2490]]:
		var bp: Dictionary = big_ship(cfg[1], cfg[2], cfg[3])
		var t0 := Time.get_ticks_usec()
		var sh := Ship.new()
		sh.setup(bp, 0)
		var setup_ms := (Time.get_ticks_usec() - t0) / 1000.0
		get_root().add_child(sh)
		sh.gravity_scale = 0.0
		sh.cmd = {"move": Vector3(0, 0, 1), "fire": false, "auto": false}
		for i in 30:
			await physics_frame
		var vals: Array = []
		for i in 150:
			await physics_frame
			vals.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		vals.sort()
		var per_frame: float = vals[75]
		var worst: float = vals[149]
		var dead := 0
		for m in sh.mods:
			if not m["alive"]:
				dead += 1
		print("%-14s %5d modules, %6.0f m long | setup %7.1f ms | physics frame median %5.2f ms, worst %5.2f ms (budget 16.7) | %d scene nodes" % [cfg[0], sh.mods.size(), float(sh.stats["longest"]), setup_ms, per_frame, worst, sh.get_child_count()])
		sh.queue_free()
		await process_frame
	quit()
