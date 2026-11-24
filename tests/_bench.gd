extends SceneTree
func big_ship(scale_f: float, n_int: int, n_ext: int) -> Dictionary:
	var bp := Premades.lance()
	bp["interior"] = {"next_id": 1, "entrances": [], "nodes": [], "corridors": []}
	ShipData.scale_ship(bp, scale_f, true)
	var hb := ShipData.hull_bounds(bp["rings"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var added := 0
	var tries := 0
	while added < n_int and tries < n_int * 20:
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
	for cfg in [["Lance x1", 1.0, 0, 0], ["x20 (360 m) 200 mods", 20.0, 120, 80], ["x55 (1 km) 500 mods", 55.0, 300, 200]]:
		var bp: Dictionary = big_ship(cfg[1], cfg[2], cfg[3])
		var t0 := Time.get_ticks_usec()
		var st := ShipData.compute_stats(bp)
		var t1 := Time.get_ticks_usec()
		var sh := Ship.new()
		sh.setup(bp, 0)
		var t2 := Time.get_ticks_usec()
		var nodes := 0
		var stack: Array = [sh]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			nodes += 1
			stack.append_array(n.get_children())
		# cost of the per-frame ship simulation pieces, called directly
		var t3 := Time.get_ticks_usec()
		for i in 60:
			sh._thermal_step(1.0 / 60.0)
		var t4 := Time.get_ticks_usec()
		for i in 60:
			sh._refresh_heat_summary()
		var t5 := Time.get_ticks_usec()
		print("%-22s modules=%d size=%.0f m  stats %.1f ms | setup %.1f ms | %d nodes | thermal step %.2f ms/frame | heat summary %.3f ms | tris %d | hull convex parts %d" % [cfg[0], bp["modules"].size(), float(st["longest"]), (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, nodes, (t4 - t3) / 60000.0, (t5 - t4) / 60000.0, int(st["tris"]), ShipData.hull_convex_parts(bp["rings"]).size()])
		sh.free()
	quit()
