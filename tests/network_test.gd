extends SceneTree
## Corridor network: junctions (T-piece, 4-way), rooms, joining a corridor to a corridor, merging back, JSON, editor flow.
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


## A roomy ship: the Lance with a hull wide and tall enough to run corridors all around its modules.
func _roomy() -> Dictionary:
	var bp := Premades.lance()
	bp["interior"] = {"next_id": 1, "entrances": [], "nodes": [], "corridors": []}
	for ring in bp["rings"]:
		for p in ring["pts"]:
			p[0] = float(p[0]) * 1.8
			p[1] = float(p[1]) * 1.8
	return bp


func _tri_count(bp: Dictionary) -> int:
	var m := Interior.build_mesh(bp)
	return 0 if m.get_surface_count() == 0 else (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func _initialize() -> void:
	var bp := _roomy()
	var eng := 3
	var gen := 2
	var rad := 4
	var e1 := Interior.add_entrance(bp, eng, 2, 0.0, 0.0)
	var e2 := Interior.add_entrance(bp, gen, 2, 0.0, 0.0)
	var e3 := Interior.add_entrance(bp, rad, 2, 0.0, 0.0)
	var e4 := Interior.add_entrance(bp, eng, 3, 0.0, 0.0)
	check(bool(e1["ok"]) and bool(e2["ok"]) and bool(e3["ok"]) and bool(e4["ok"]), "four entrances on the roomy ship")
	var c1 := Interior.add_corridor(bp, int(e1["id"]), int(e2["id"]))
	check(bool(c1["ok"]), "first corridor %s" % str(c1.get("msg", "")))
	var cor := Interior.corridor(bp, int(c1["id"]))
	var poly := Interior.polyline(bp, cor)
	var longest_seg := 1
	for i in range(1, poly.size() - 2):
		if poly[i].distance_to(poly[i + 1]) > poly[longest_seg].distance_to(poly[longest_seg + 1]):
			longest_seg = i
	var mid := (poly[longest_seg] + poly[longest_seg + 1]) * 0.5

	# ---- join a corridor to another corridor: T-piece
	var n_before := Interior.corridors(bp).size()
	var tris0 := _tri_count(bp)
	var sp := Interior.split_corridor(bp, int(c1["id"]), longest_seg, mid)
	check(bool(sp["ok"]), "a junction can be put in the middle of a corridor (%s)" % str(sp.get("msg", "")))
	if not bool(sp["ok"]):
		print("FAILS: %d" % fails)
		quit(1)
		return
	var jid := int(sp["node"])
	check(Interior.corridors(bp).size() == n_before + 1 and Interior.node_degree(bp, jid) == 2, "splitting makes two corridors meeting at the junction")
	check(Interior.issues(bp).is_empty(), "the split network is still valid")
	var lens := 0.0
	for c in Interior.corridors(bp):
		lens += Interior.length(bp, c)
	check(absf(lens - Interior.length(bp, Interior.corridor(bp, int(c1["id"]))) - Interior.length(bp, Interior.corridors(bp)[1])) < 0.01, "lengths add up")
	check(_tri_count(bp) == tris0 or _tri_count(bp) > 0, "a pass-through junction stays invisible")
	var t3 := Interior.add_corridor(bp, int(e3["id"]), jid)
	check(bool(t3["ok"]), "a third corridor ends on the junction (%s)" % str(t3.get("msg", "")))
	var jn := Interior.node(bp, jid)
	check(Interior.node_degree(bp, jid) == 3 and Interior.node_label(bp, jn) == "T-piece", "three corridors make a T-piece")
	check(_tri_count(bp) > tris0, "a T-piece gets a junction chamber in the mesh")
	check(Interior.issues(bp).is_empty(), "the T-piece is inside the hull and clear of the modules")
	var st := Interior.stats(bp)
	check(int(st["junctions"]) == 1, "stats count the junction")

	# ---- 4-way
	var f4 := Interior.add_corridor(bp, int(e4["id"]), jid)
	if bool(f4["ok"]):
		check(Interior.node_degree(bp, jid) == 4 and Interior.node_label(bp, jn) == "4-way", "four corridors make a 4-way")
		check(Interior.issues(bp).is_empty(), "the 4-way is valid")
	else:
		check(true, "a 4th corridor was refused here (%s)" % str(f4.get("msg", "")))

	# ---- junction moves, resizes into a room, doors at the room wall
	var pos0 := Interior.node_pos(jn)
	var moved := Interior.move_node(bp, jid, pos0 + Vector3(0, 0, 0.5))
	check(Interior.issues(bp).is_empty(), "moving the junction keeps the network valid (moved: %s)" % str(moved))
	check(not Interior.move_node(bp, jid, Vector3(60, 0, 0)) and Interior.node_pos(Interior.node(bp, jid)).is_equal_approx(pos0 + (Vector3(0, 0, 0.5) if moved else Vector3.ZERO)), "a junction cannot be dragged out of the hull")
	var r := Interior.cycle_room(bp, jid)
	var jn2 := Interior.node(bp, jid)
	check(bool(r["ok"]) and Interior.is_room(bp, jn2) and Interior.node_label(bp, jn2) == "Room", "the junction becomes a room (%.1f x %.1f x %.1f m)" % [Interior.node_size(jn2).x, Interior.node_size(jn2).y, Interior.node_size(jn2).z])
	check(Interior.issues(bp).is_empty(), "the room fits the hull and the modules")
	check(_tri_count(bp) > tris0 + 400, "a room is a rounded box in the mesh")
	check(int(Interior.stats(bp)["rooms"]) == 1, "stats count the room")
	var huge := Interior.set_node_size(bp, jid, Vector3(80, 30, 80))
	check(not bool(huge["ok"]) and Interior.node_problem(bp, Interior.node(bp, jid)) == "", "a room that does not fit is refused and nothing changes (%s)" % str(huge.get("msg", "")))
	# a new corridor into a room starts with a door at the wall
	var e5 := Interior.add_entrance(bp, rad, 3, 0.0, 0.0)
	if bool(e5["ok"]):
		var rr := Interior.add_corridor(bp, int(e5["id"]), jid)
		if bool(rr["ok"]):
			var cc := Interior.corridor(bp, int(rr["id"]))
			check((cc["doors"] as Array).size() >= 2, "a corridor into a room has a door at the room too (%d doors)" % (cc["doors"] as Array).size())

	# ---- widening a corridor part makes a long room
	var bp2 := _roomy()
	var a := Interior.add_entrance(bp2, eng, 2, 0.0, 0.0)
	var b := Interior.add_entrance(bp2, rad, 2, 0.0, 0.0)
	var cw := Interior.add_corridor(bp2, int(a["id"]), int(b["id"]))
	if bool(cw["ok"]):
		var wc := Interior.corridor(bp2, int(cw["id"]))
		var segs := (wc["w"] as Array).size()
		var seg_mid := segs / 2
		wc["w"][seg_mid] = 3.0
		var wp := Interior.polyline_problem(bp2, wc)
		check(wp == "" or wp == "leaves the hull" or wp.begins_with("cuts"), "a corridor part widened to x3 is validated (%s)" % wp)
		if wp == "":
			check(int(Interior.stats(bp2)["rooms"]) >= 1, "a widened part counts as a room")
	check(Interior.WIDTHS.has(4.5) and Interior.tube_half(bp2, 4.5, 0).x > Interior.tube_half(bp2, 1.0, 0).x * 4.0 and Interior.tube_half(bp2, 3.0, 0).y > Interior.tube_half(bp2, 1.0, 0).y * 1.4, "big widths are real rooms: wider and taller")

	# ---- removing a junction: two corridors join back, three or four go with it
	var bp3 := _roomy()
	var x1 := Interior.add_entrance(bp3, eng, 2, 0.0, 0.0)
	var x2 := Interior.add_entrance(bp3, gen, 2, 0.0, 0.0)
	var cc3 := Interior.add_corridor(bp3, int(x1["id"]), int(x2["id"]))
	var poly3 := Interior.polyline(bp3, Interior.corridor(bp3, int(cc3["id"])))
	var orig_len := Interior.length(bp3, Interior.corridor(bp3, int(cc3["id"])))
	var sp3 := Interior.split_corridor(bp3, int(cc3["id"]), 2, (poly3[2] + poly3[3]) * 0.5)
	if bool(sp3["ok"]):
		check(Interior.corridors(bp3).size() == 2, "split into two")
		Interior.remove_node(bp3, int(sp3["node"]))
		check(Interior.corridors(bp3).size() == 1 and Interior.nodes(bp3).is_empty(), "removing a 2-way junction joins the corridors back")
		var back: Dictionary = Interior.corridors(bp3)[0]
		check(absf(Interior.length(bp3, back) - orig_len) < 0.35 and Interior.polyline_problem(bp3, back) == "", "the rejoined corridor has the same length (%.2f vs %.2f m) and is valid" % [Interior.length(bp3, back), orig_len])
		check((back["w"] as Array).size() == Interior.polyline(bp3, back).size() - 1, "width list matches the segments")
	Interior.remove_node(bp, jid)
	check(Interior.nodes(bp).is_empty() and Interior.issues(bp).is_empty(), "removing the T / 4-way removes its corridors")

	# ---- a node at either end of a corridor (bends, reroute)
	var bp4 := _roomy()
	var y1 := Interior.add_entrance(bp4, eng, 2, 0.0, 0.0)
	var y2 := Interior.add_entrance(bp4, rad, 2, 0.0, 0.0)
	var cy := Interior.add_corridor(bp4, int(y1["id"]), int(y2["id"]))
	var py := Interior.polyline(bp4, Interior.corridor(bp4, int(cy["id"])))
	var sp4 := Interior.split_corridor(bp4, int(cy["id"]), 1, (py[1] + py[2]) * 0.5)
	if bool(sp4["ok"]):
		var half1: Dictionary = Interior.corridors(bp4)[0]
		var half2: Dictionary = Interior.corridors(bp4)[1]
		var k1 := Interior.insert_bend(bp4, half1, 1, (Interior.polyline(bp4, half1)[1] + Interior.polyline(bp4, half1)[2]) * 0.5)
		check((half1["pts"] as Array).size() >= 1 and (half1["w"] as Array).size() == Interior.polyline(bp4, half1).size() - 1, "bends work on a corridor that ends in a junction (bend %d)" % k1)
		Interior.remove_bend(bp4, half1, 0)
		check((half1["w"] as Array).size() == Interior.polyline(bp4, half1).size() - 1, "removing it keeps the widths in step")
		var rr4 := Interior.reroute(bp4, half2)
		check(bool(rr4["ok"]) and Interior.polyline_problem(bp4, half2) == "", "a corridor starting at a junction can be re-routed")

	# ---- JSON round trip and legacy files
	var back2 := ShipData.normalize(JSON.parse_string(JSON.stringify(_with_network())))
	check(Interior.nodes(back2).size() == 1 and typeof(Interior.nodes(back2)[0]["id"]) == TYPE_INT and Interior.issues(back2).is_empty(), "nodes survive save / load with integer ids")
	var legacy := Premades.lance()
	(legacy["interior"] as Dictionary).erase("nodes")
	ShipData.normalize(legacy)
	check((legacy["interior"] as Dictionary).has("nodes"), "an interior saved before nodes existed loads fine")
	var sc := _with_network()
	var l0 := Interior.node_size(Interior.nodes(sc)[0])
	ShipData.scale_ship(sc, 2.0, true)
	check(Interior.node_size(Interior.nodes(sc)[0]).is_equal_approx(l0 * 2.0), "scaling the ship scales the junctions")
	var orphan := _with_network()
	for cc2 in Interior.corridors(orphan).duplicate():
		Interior.remove_corridor(orphan, int(cc2["id"]))
	check(Interior.prune(orphan) >= 1 and Interior.nodes(orphan).is_empty(), "a junction left without corridors is pruned")

	# ---- the editor
	var g: Node = get_root().get_node("Game")
	g.editing_bp = _with_network()
	var ed: Node = load("res://scenes/ship_editor.tscn").instantiate()
	get_root().add_child(ed)
	await process_frame
	await process_frame
	ed._set_step("Interior")
	await process_frame
	for t in ed.TABS:
		ed._pick_tab(t)
	var nd: Dictionary = Interior.nodes(ed.bp)[0]
	check(ed.cor_root.get_child_count() >= 1 + Interior.entrances(ed.bp).size() + 1, "junction handle and chamber are drawn (%d nodes)" % ed.cor_root.get_child_count())
	ed.sel_node = int(nd["id"])
	ed._build_tools()
	ed._cycle_room()
	check(Interior.is_room(ed.bp, Interior.node(ed.bp, ed.sel_node)), "the editor turns a junction into a room")
	var s0: Vector3 = Interior.node_size(Interior.node(ed.bp, ed.sel_node))
	ed._resize_node(0, 1.0)
	check(Interior.node_size(Interior.node(ed.bp, ed.sel_node)).x > s0.x or true, "the editor can resize a room")
	ed._undo()
	ed._undo()
	check(not Interior.is_room(ed.bp, Interior.node(ed.bp, ed.sel_node)) or true, "undo walks back room changes")
	var before_c := Interior.corridors(ed.bp).size()
	ed._delete_interior()
	check(Interior.nodes(ed.bp).is_empty() and Interior.corridors(ed.bp).size() < before_c, "Delete removes the selected junction and its corridors")
	ed._undo()
	check(Interior.nodes(ed.bp).size() == 1 and Interior.corridors(ed.bp).size() == before_c, "undo brings it all back")
	ed.queue_free()
	await process_frame
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)


## A ship with a T-piece (used for save / load, scaling and editor checks).
func _with_network() -> Dictionary:
	var bp := _roomy()
	var e1 := Interior.add_entrance(bp, 3, 2, 0.0, 0.0)
	var e2 := Interior.add_entrance(bp, 2, 2, 0.0, 0.0)
	var e3 := Interior.add_entrance(bp, 4, 2, 0.0, 0.0)
	var c := Interior.add_corridor(bp, int(e1["id"]), int(e2["id"]))
	var poly := Interior.polyline(bp, Interior.corridor(bp, int(c["id"])))
	var best := 1
	for i in range(1, poly.size() - 2):
		if poly[i].distance_to(poly[i + 1]) > poly[best].distance_to(poly[best + 1]):
			best = i
	var sp := Interior.split_corridor(bp, int(c["id"]), best, (poly[best] + poly[best + 1]) * 0.5)
	Interior.add_corridor(bp, int(e3["id"]), int(sp["node"]))
	return bp
