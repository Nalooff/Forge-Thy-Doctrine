extends SceneTree
## The ship workshop from 5 m to 100 km: grid, camera planes, vertex handles with a level of detail, validation cost.
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _editor(bp: Dictionary) -> Node:
	var g: Node = get_root().get_node("Game")
	g.editing_bp = bp
	var ed: Node = load("res://scenes/ship_editor.tscn").instantiate()
	get_root().add_child(ed)
	return ed


func _initialize() -> void:
	# ---- validation: same answers as the exhaustive pair loop, much faster
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mods: Array = []
	for i in 300:
		var t: String = ["generator", "engine_room", "thruster", "barrel", "radar_room"][rng.randi() % 5]
		mods.append({"id": i + 1, "type": t, "pos": [rng.randf_range(-30, 30), rng.randf_range(-30, 30), rng.randf_range(-30, 30)], "size": [rng.randf_range(2, 8), rng.randf_range(2, 8), rng.randf_range(2, 8)], "dir": 0})
	var naive: Array = []
	for i in range(mods.size()):
		for j in range(i + 1, mods.size()):
			if ShipData._overlap_allowed(mods[i]["type"], mods[j]["type"]):
				continue
			if ShipData.module_box(mods[i]).grow(-0.01).intersects(ShipData.module_box(mods[j])):
				naive.append([i, j])
	var fast := ShipData.overlapping_pairs(mods)
	check(fast.size() == naive.size() and fast.size() > 20, "overlap search by spatial hash finds the same %d pairs as the O(n^2) loop" % naive.size())
	var same := true
	for k in range(mini(fast.size(), naive.size())):
		same = same and int(fast[k][0]) == int(naive[k][0]) and int(fast[k][1]) == int(naive[k][1])
	check(same, "...in the same order")
	var src: GDScript = load("res://tests/bench_ship.gd")
	var big: Dictionary = src.new().big_ship(120.0, 2000, 990)
	var t0 := Time.get_ticks_usec()
	var iss := ShipData.validate(big, {"max_tier": 8, "budget": 1.0e9})
	var vms := (Time.get_ticks_usec() - t0) / 1000.0
	check(vms < 2500.0, "validating a %d-module ship takes %.0f ms (it was 10,900 ms)" % [big["modules"].size(), vms])
	var small := Premades.lance()
	check(ShipData.get_module(small, 3)["id"] == 3 and ShipData.get_module(small, 999).is_empty(), "get_module finds by id (O(1) in the usual case)")
	var idx := ShipData.build_index(small)
	var ok_idx := true
	for m in small["modules"]:
		for t in ["engine_room", "turret_bay", "commander_post", ""]:
			ok_idx = ok_idx and ShipData.linked_ids_idx(idx, int(m["id"]), t) == ShipData.linked_ids(small, int(m["id"]), t)
	check(ok_idx, "the link index answers like linked_ids")

	# ---- a ship stays the same ship from 18 m to 90 km
	var base := Premades.lance()
	var msgs0: Array = []
	for i in ShipData.validate(base, {"max_tier": 8, "budget": 1.0e9}):
		msgs0.append(String(i["msg"]))
	for f in [1.0, 100.0, 1000.0, 5000.0]:
		var bp := Premades.lance()
		bp["interior"] = {"next_id": 1, "entrances": [], "nodes": [], "corridors": []}
		ShipData.scale_ship(bp, f, true)
		var st := ShipData.compute_stats(bp)
		var bad := 0
		for i in ShipData.validate(bp, {"max_tier": 8, "budget": 1.0e9}):
			var msg := String(i["msg"])
			if not (msg.contains("Class") or msg.contains("Polygon") or msg.contains("Costs")):
				bad += 1
		check(bad == msgs0.filter(func(x): return not (x.contains("Class") or x.contains("Polygon") or x.contains("Costs"))).size(), "x%d: %.0f m, class %s - same legality as the original (%d issues)" % [int(f), float(st["longest"]), st["class"], bad])

	# ---- the workshop at four sizes
	var results := {}
	for f in [1.0, 50.0, 1000.0, 5000.0]:
		var bp2 := Premades.lance()
		bp2["interior"] = {"next_id": 1, "entrances": [], "nodes": [], "corridors": []}
		ShipData.scale_ship(bp2, f, true)
		var ed := _editor(bp2)
		await process_frame
		await process_frame
		ed._set_step("Hull")
		await process_frame
		var hb := ShipData.hull_bounds(ed.bp["rings"])
		var longest := maxf(hb.size.x, maxf(hb.size.y, hb.size.z))
		var raw := longest / 80.0
		var nice_ok: bool = float(ed.snap) >= raw * 0.999 or float(ed.snap) == float(ed.NICE[ed.NICE.size() - 1])
		check(nice_ok and float(ed.snap) <= raw * 2.6 + 0.001 or float(ed.snap) == float(ed.NICE[ed.NICE.size() - 1]), "%.0f m: grid snap %s m (about 1/80 of the ship)" % [longest, str(ed.snap)])
		ed._frame_camera()
		check(ed.cam.far > longest * 3.0 and ed.cam.near < ed.cam_dist * 0.01 and ed.cam.near > 0.0, "%.0f m: camera planes near %.2f / far %.0f" % [longest, ed.cam.near, ed.cam.far])
		var vp_h := ed.get_viewport().get_visible_rect().size.y
		# a handle's apparent size in pixels
		var sizes: Array = []
		for hi in range(0, ed.handle_vis.size()):
			if ed.handle_vis[hi] == 1:
				var tr: Transform3D = ed.handle_mm.get_instance_transform(hi)
				var sc := tr.basis.get_scale().x
				var wpp: float = ed._world_per_pixel(tr.origin)
				sizes.append(sc * 2.0 / wpp)
		var all_same := not sizes.is_empty()
		for px in sizes:
			all_same = all_same and absf(float(px) - ed.HANDLE_PX) < 0.05
		check(all_same, "%.0f m: every handle is %.0f px wide (constant on screen)" % [longest, ed.HANDLE_PX])
		results[f] = ed.handles_shown
		ed.queue_free()
		await process_frame
	check(results[1.0] == results[5000.0], "18 m and 90 km ships show the same handles (%d)" % results[1.0])

	# ---- level of detail: many rings, far away
	var dense := Premades.lance()
	dense["interior"] = {"next_id": 1, "entrances": [], "nodes": [], "corridors": []}
	var rings: Array = dense["rings"]
	var first: Dictionary = rings[0]
	var last: Dictionary = rings[rings.size() - 1]
	var new_rings: Array = []
	for i in 61:
		var tt := float(i) / 60.0
		var r: Dictionary = (rings[1] as Dictionary).duplicate(true)
		r["z"] = lerpf(float(first["z"]), float(last["z"]), tt)
		new_rings.append(r)
	dense["rings"] = new_rings
	var ed2 := _editor(dense)
	await process_frame
	await process_frame
	ed2._set_step("Hull")
	ed2._frame_camera()
	await process_frame
	var total: int = ed2.bp["rings"].size() * ShipData.RING_PTS
	var far_shown: int = ed2.handles_shown
	check(far_shown < total * 0.6 and far_shown > 8, "61 rings seen whole: %d of %d handles drawn (the general shape)" % [far_shown, total])
	ed2.cam_dist = ed2.cam_dist * 0.04
	ed2._update_cam()
	var close_shown: int = ed2.handles_shown
	check(close_shown > far_shown, "zoomed in, more vertices appear (%d)" % close_shown)
	var ed_selected := true
	ed2.sel_ring = 30
	ed2.sel_vert = 3
	ed2._rebuild_handles()
	ed2.cam_dist = ed2.cam_dist * 25.0
	ed2._update_cam()
	ed_selected = ed2.handle_vis[30 * ShipData.RING_PTS + 3] == 1
	check(ed_selected, "the selected vertex always stays visible, even when thinned out")
	# many modules: one node, not one per module
	check(ed2.mod_root.get_child_count() == 0, "Hull step draws no module nodes")
	ed2.queue_free()
	await process_frame
	var bigbp: Dictionary = src.new().big_ship(55.0, 300, 200)
	var ed3 := _editor(bigbp)
	await process_frame
	await process_frame
	ed3._set_step("Modules")
	await process_frame
	check(ed3.mod_root.get_child_count() == 1 and (ed3.mod_root.get_child(0) as MultiMeshInstance3D).multimesh.instance_count == bigbp["modules"].size(), "%d modules are drawn as a single MultiMesh" % bigbp["modules"].size())
	ed3.queue_free()
	await process_frame
	var few := _editor(Premades.lance())
	await process_frame
	await process_frame
	few._set_step("Modules")
	await process_frame
	check(few.mod_root.get_child_count() == Premades.lance()["modules"].size(), "a small ship keeps one node per module")
	few.queue_free()
	await process_frame

	# ---- a 90 km ship flies: camera planes, no precision trouble
	var g: Node = get_root().get_node("Game")
	var huge := Premades.lance()
	huge["interior"] = {"next_id": 1, "entrances": [], "nodes": [], "corridors": []}
	ShipData.scale_ship(huge, 5000.0, true)
	g.session = {"mode": "sandbox", "ship": huge, "map": "range", "return_scene": "res://scenes/main_menu.tscn"}
	var ar: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(ar)
	for i in 12:
		await physics_frame
		await process_frame
	var pl: Ship = ar.player
	var cam: Camera3D = ar.rig.cam
	check(float(pl.stats["longest"]) > 80000.0, "the ship is %.0f m long" % float(pl.stats["longest"]))
	check(cam.far >= ar.rig.dist * 5.0 and cam.far > float(pl.stats["longest"]) * 2.0, "camera far plane %.0f m covers the ship from %.0f m away" % [cam.far, ar.rig.dist])
	check(cam.is_position_in_frustum(pl.global_position), "the ship is in the camera's view")
	check(cam.near > 5.0, "near plane grows with distance (%.1f m) so depth keeps its precision" % cam.near)
	ar.queue_free()
	await process_frame
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
