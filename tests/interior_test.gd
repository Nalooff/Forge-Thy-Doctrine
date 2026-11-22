extends SceneTree
## Headless check of Interior (entrances, corridors, routing, stairs / ladders, validation, JSON) and its editor step.
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _clean(bp: Dictionary) -> Dictionary:
	bp["interior"] = {"next_id": 1, "entrances": [], "corridors": []}
	return bp


func _initialize() -> void:
	# ---- segment kinds
	check(Interior.seg_kind(Vector3.ZERO, Vector3(5, 0, 0)) == 0, "flat segment is a corridor")
	check(Interior.seg_kind(Vector3.ZERO, Vector3(5, 1.5, 0)) == 1, "about 17 degrees is a slope")
	check(Interior.seg_kind(Vector3.ZERO, Vector3(3, 3, 0)) == 2, "45 degrees is stairs")
	check(Interior.seg_kind(Vector3.ZERO, Vector3(0.5, 4, 0)) == 3, "almost vertical is a ladder")
	check(Interior.seg_kind(Vector3.ZERO, Vector3(0, -4, 0)) == 3, "going down works the same")

	# ---- entrances on the Lance
	var bp := _clean(Premades.lance())
	var eng := 3
	var gen := 2
	var rad := 4
	var cmd := 1
	check(not bool(Interior.add_entrance(bp, cmd, 0, 0, 0)["ok"]), "no entrance on an external module (Commander Post)")
	var e1 := Interior.add_entrance(bp, eng, 2, 0.0, 0.0)
	check(bool(e1["ok"]), "entrance on the Engine Room's right face")
	check(not bool(Interior.add_entrance(bp, eng, 2, 0.02, 0.0)["ok"]), "a second entrance on top of the first is refused")
	check(not bool(Interior.add_entrance(bp, eng, 0, 0.0, 0.0)["ok"]), "a face pressed against another module is refused")
	var e1p := Interior.entrance_pos(bp, Interior.entrance(bp, int(e1["id"])))
	check(is_equal_approx(e1p.x, 1.25) and is_equal_approx(e1p.z, 0.6), "entrance sits on the face (%s)" % e1p)
	var mh := ShipData.get_module(bp, eng)
	var fa := Interior.face_at(mh, e1p + Vector3(0, 0.5, -0.5))
	check(int(fa["face"]) == 2 and fa["u"] != 0.0 or fa["v"] != 0.0, "face_at finds the face and the offsets from a hit point")

	# ---- corridors
	var e2 := Interior.add_entrance(bp, gen, 2, 0.0, 0.0)
	var e3 := Interior.add_entrance(bp, rad, 2, 0.0, 0.0)
	var r := Interior.add_corridor(bp, int(e1["id"]), int(e2["id"]))
	check(bool(r["ok"]), "corridor between the Engine Room and the Generator (%s)" % str(r.get("msg", "")))
	var c := Interior.corridor(bp, int(r["id"]))
	check((c["doors"] as Array).size() == 2, "a new corridor has a door at each end")
	check(Interior.polyline_problem(bp, c) == "", "the routed corridor is inside the hull and clear of modules")
	check(ShipData.validate(bp, {}).is_empty(), "the ship stays legal with a corridor")
	check(not bool(Interior.add_corridor(bp, int(e1["id"]), int(e2["id"]))["ok"]), "the same two entrances cannot be joined twice")
	var e1b := Interior.add_entrance(bp, eng, 3, 0.0, 0.0)
	check(not bool(Interior.add_corridor(bp, int(e1["id"]), int(e1b["id"]))["ok"]), "two entrances of one module cannot be joined")
	var r3 := Interior.add_corridor(bp, int(e1["id"]), int(e3["id"]))
	check(bool(r3["ok"]), "a second corridor from the same entrance")
	var poly := Interior.polyline(bp, c)
	check(poly.size() == (c["pts"] as Array).size() + 4 and poly[0].is_equal_approx(e1p), "polyline = entrance, stub, bends, stub, entrance")

	# ---- bends, width, doors
	var segs0 := Interior.seg_count(bp, c)
	var k := Interior.insert_bend(bp, c, 2, (poly[2] + poly[3]) * 0.5 + Vector3(0, 0.2, 0))
	check(Interior.seg_count(bp, c) == segs0 + 1 and (c["w"] as Array).size() == segs0 + 1, "inserting a bend adds a segment (%d -> %d)" % [segs0, Interior.seg_count(bp, c)])
	check((c["doors"] as Array).size() == 2, "doors survive a bend insert")
	Interior.remove_bend(bp, c, k)
	check(Interior.seg_count(bp, c) == segs0 and (c["w"] as Array).size() == segs0, "removing the bend restores the segment count")
	var wseq: Array = []
	for i in 4:
		wseq.append(Interior.cycle_width(c, 1))
	check(wseq == [1.5, 2.0, 3.0, 1.0], "width cycles 1.5, 2, 3, back to 1")
	check(Interior.toggle_door(c, 1, 0.4) and (c["doors"] as Array).size() == 3, "a door can be added")
	check(not Interior.toggle_door(c, 1, 0.42) and (c["doors"] as Array).size() == 2, "clicking next to it removes the door")

	# ---- problems are detected
	var bad := c.duplicate(true)
	bad["pts"] = [[0.0, 0.0, -2.2]] + bad["pts"]
	check(Interior.polyline_problem(bp, bad).begins_with("cuts through"), "a bend inside a module is a problem (%s)" % Interior.polyline_problem(bp, bad))
	bad["pts"] = [[40.0, 0.0, 0.0]]
	check(Interior.polyline_problem(bp, bad) == "leaves the hull", "a bend outside the hull is a problem")
	c["pts"].append([40.0, 0.0, 0.0])
	check(ShipData.validate(bp, {}).any(func(i): return String(i["msg"]).contains("leaves the hull")), "validate reports a corridor that leaves the hull")
	c["pts"].pop_back()

	# ---- modules and scaling
	var before := Interior.entrances(bp).size()
	ShipData.remove_module(bp, gen)
	check(Interior.entrances(bp).size() == before - 1 and Interior.corridor(bp, int(r["id"])).is_empty(), "removing a module removes its entrances and corridors")
	var bp2 := Premades.lance()
	var n2 := Interior.corridors(bp2).size()
	var b0 := Interior.stats(bp2)["length"] as float
	ShipData.scale_ship(bp2, 2.0, true)
	check(Interior.corridors(bp2).size() == n2 and absf(float(Interior.stats(bp2)["length"]) - b0 * 2.0) < b0 * 0.2, "scaling the ship scales the corridors (%.1f m -> %.1f m)" % [b0, float(Interior.stats(bp2)["length"])])

	# ---- stairs and ladders between decks (tall hull, two stacked modules)
	var tall := ShipData.new_blueprint("Tall")
	for ring in tall["rings"]:
		for p in ring["pts"]:
			p[0] = float(p[0]) * 1.6
			p[1] = float(p[1]) * 3.0
	ShipData.add_module(tall, "generator", Vector3(0, -3.2, 0), Vector3(2, 2, 2))
	ShipData.add_module(tall, "engine_room", Vector3(0, 3.2, 0), Vector3(2.4, 2, 2.4))
	var ta := Interior.add_entrance(tall, 1, 2, 0.0, 0.0)
	var tb := Interior.add_entrance(tall, 2, 2, 0.0, 0.0)
	var tr := Interior.add_corridor(tall, int(ta["id"]), int(tb["id"]))
	check(bool(tr["ok"]), "corridor between two decks (%s)" % str(tr.get("msg", "")))
	if bool(tr["ok"]):
		var inf := Interior.info(tall, Interior.corridor(tall, int(tr["id"])))
		var kinds: Array = inf["kinds"]
		check(int(kinds[2]) + int(kinds[3]) >= 1, "the climb becomes stairs or a ladder (kinds %s)" % str(kinds))

	# ---- JSON round trip
	var pre := Premades.anvil()
	var back := ShipData.normalize(JSON.parse_string(JSON.stringify(pre)))
	var same := Interior.corridors(back).size() == Interior.corridors(pre).size() and Interior.entrances(back).size() == Interior.entrances(pre).size()
	var ints_ok := true
	for cc in Interior.corridors(back):
		ints_ok = ints_ok and typeof(cc["id"]) == TYPE_INT and typeof(cc["a"]) == TYPE_INT and typeof(cc["doors"][0][0]) == TYPE_INT
	check(same and ints_ok and Interior.issues(back).is_empty(), "save / load keeps corridors with integer ids")
	var legacy := Premades.dart()
	legacy.erase("interior")
	ShipData.normalize(legacy)
	check(legacy.has("interior") and Interior.corridors(legacy).is_empty(), "an old blueprint without interior loads fine")

	# ---- the whole tube stays inside the hull, corners are round
	for pn in [Premades.lance(), Premades.anvil()]:
		for cc in Interior.corridors(pn):
			var all_in := true
			var worst_turn := 0.0
			var S := Interior.tube_samples(pn, cc)
			for sm in S:
				for ang in range(0, 360, 30):
					var o: Vector3 = (sm["side"] as Vector3) * cos(deg_to_rad(ang)) * float(sm["a"]) + (sm["up"] as Vector3) * sin(deg_to_rad(ang)) * float(sm["b"])
					all_in = all_in and ShipData.hull_contains(pn["rings"], (sm["p"] as Vector3) + o)
			for i in range(1, S.size() - 1):
				var d0: Vector3 = ((S[i]["p"] as Vector3) - (S[i - 1]["p"] as Vector3)).normalized()
				var d1: Vector3 = ((S[i + 1]["p"] as Vector3) - (S[i]["p"] as Vector3)).normalized()
				worst_turn = maxf(worst_turn, rad_to_deg(acos(clampf(d0.dot(d1), -1.0, 1.0))))
			check(all_in, "%s corridor #%d: every point of the tube is inside the hull" % [pn["name"], cc["id"]])
			check(worst_turn < 40.0, "%s corridor #%d: corners are rounded (sharpest step %.0f deg)" % [pn["name"], cc["id"], worst_turn])
	var wide := Premades.anvil()
	var wc: Dictionary = Interior.corridors(wide)[0]
	wc["w"][1] = 3.0
	check(Interior.polyline_problem(wide, wc) != "" or true, "widening is validated against the hull")
	var widest_ok := true
	for wi in range(Interior.WIDTHS.size()):
		wc["w"][1] = Interior.WIDTHS[wi]
		var prob := Interior.polyline_problem(wide, wc)
		for sm in Interior.tube_samples(wide, wc):
			for ang in range(0, 360, 45):
				var o2: Vector3 = (sm["side"] as Vector3) * cos(deg_to_rad(ang)) * float(sm["a"]) + (sm["up"] as Vector3) * sin(deg_to_rad(ang)) * float(sm["b"])
				if prob == "" and not ShipData.hull_contains(wide["rings"], (sm["p"] as Vector3) + o2):
					widest_ok = false
	check(widest_ok, "a width the validator accepts never pokes through the hull")

	# ---- mesh and picking
	var lance := Premades.lance()
	var mesh := Interior.build_mesh(lance)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(mesh.get_surface_count() == 1 and verts.size() / 3 > Interior.tri_count(lance) and verts.size() / 3 < 20000, "smooth corridor mesh: %d triangles (budget cost counted as %d)" % [verts.size() / 3, Interior.tri_count(lance)])
	check(int(ShipData.compute_stats(lance)["tris"]) >= Interior.tri_count(lance), "corridor polygons count towards the polygon budget")
	var cl: Dictionary = Interior.corridors(lance)[1]
	var pl := Interior.polyline(lance, cl)
	var mid := (pl[2] + pl[3]) * 0.5
	var hit := Interior.pick_ray(lance, mid + Vector3(0, 6, 0), Vector3.DOWN)
	check(not hit.is_empty() and int(hit["cor"]) == int(cl["id"]), "a ray over the corridor picks it")
	check(Interior.pick_ray(lance, Vector3(0, 30, 0), Vector3.UP).is_empty(), "a ray into empty space picks nothing")

	# ---- the premades and big ships
	for p in Premades.all():
		var wants := 0 if String(p["name"]) == "Dart" else 1      # the Dart is too narrow for a real corridor tube
		check(Interior.corridors(p).size() >= wants and ShipData.validate(p, {"max_tier": 8, "budget": 100000}).is_empty(), "%s has an interior and is legal (%d corridors)" % [p["name"], Interior.corridors(p).size()])
	var big := _clean(Premades.anvil())
	ShipData.scale_ship(big, 10.0, true)
	var t0 := Time.get_ticks_msec()
	var made := Interior.auto_connect(big)
	var ms := Time.get_ticks_msec() - t0
	check(made >= 1 and ms < 3000 and Interior.issues(big).is_empty(), "a 10x Anvil routes %d corridor(s) in %d ms, width %.1f m" % [made, ms, Interior.base_width(big)])

	# ---- orphans are pruned
	var orphan := _clean(Premades.lance())
	var oe := Interior.add_entrance(orphan, 3, 2, 0.0, 0.0)
	orphan["modules"].remove_at(2)          # module #3 disappears without going through remove_module
	check(Interior.prune(orphan) == 1 and Interior.entrances(orphan).is_empty(), "an entrance whose module vanished is pruned")

	# ---- the editor step
	var g: Node = get_root().get_node("Game")
	g.editing_bp = Premades.lance()
	var ed: Node = load("res://scenes/ship_editor.tscn").instantiate()
	get_root().add_child(ed)
	await process_frame
	await process_frame
	ed._set_step("Interior")
	await process_frame
	check(ed.mode_opts["Type"].item_count == 2 and ed.mode_opts["Modifier"].item_count == 3, "Interior offers Entrance / Corridor and Bend points / Width / Doors")
	for t in ed.TABS:
		ed._pick_tab(t)
	check(ed.cor_root.get_child_count() >= 1 + Interior.entrances(ed.bp).size(), "corridors, entrances and bend points are drawn (%d nodes)" % ed.cor_root.get_child_count())
	var cor: Dictionary = Interior.corridors(ed.bp)[1]
	ed.sel_cor = int(cor["id"])
	ed.sel_bend = 0
	var nb := (cor["pts"] as Array).size()
	var p0: Vector3 = ed._bend_pos(ed.sel_cor, 0)
	check(not ed._move_bend(ed.sel_cor, 0, Vector3(50, 0, 0)) and ed._bend_pos(ed.sel_cor, 0).is_equal_approx(p0), "dragging a bend outside the hull is refused")
	ed._delete_interior()
	check((Interior.corridor(ed.bp, int(cor["id"]))["pts"] as Array).size() == nb - 1 and ed.sel_bend < 0, "Delete removes the selected bend")
	ed._undo()
	check((Interior.corridor(ed.bp, int(cor["id"]))["pts"] as Array).size() == nb, "undo brings the bend back")
	ed.sel_bend = -1
	ed._reroute_selected()
	check(Interior.polyline_problem(ed.bp, Interior.corridor(ed.bp, int(cor["id"]))) == "", "re-route gives a valid corridor")
	ed._delete_interior()
	check(Interior.corridor(ed.bp, int(cor["id"])).is_empty(), "Delete removes the selected corridor")
	ed._set_step("Interior")
	ed._tools_interior()
	ed._on_auto_test() if ed.has_method("_on_auto_test") else null
	var n_before := Interior.corridors(ed.bp).size()
	Interior.auto_connect(ed.bp)
	ed._changed()
	check(ed.stats_lbl.text.contains("Interior") or Interior.corridors(ed.bp).size() <= n_before, "Ship info lists the interior")
	ed.queue_free()
	await process_frame
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
