extends SceneTree
## Screenshots of a corridor network (T-piece + room): xvfb-run godot --rendering-driver opengl3 --script res://tests/network_shot.gd -- out_dir
func _roomy() -> Dictionary:
	var bp := Premades.lance()
	bp["interior"] = {"next_id": 1, "entrances": [], "nodes": [], "corridors": []}
	for ring in bp["rings"]:
		for p in ring["pts"]:
			p[0] = float(p[0]) * 1.8
			p[1] = float(p[1]) * 1.8
	var e1 := Interior.add_entrance(bp, 3, 2, 0.0, 0.0)
	var e2 := Interior.add_entrance(bp, 2, 2, 0.0, 0.0)
	var e3 := Interior.add_entrance(bp, 4, 2, 0.0, 0.0)
	var e4 := Interior.add_entrance(bp, 3, 3, 0.0, 0.0)
	var c := Interior.add_corridor(bp, int(e1["id"]), int(e2["id"]))
	var poly := Interior.polyline(bp, Interior.corridor(bp, int(c["id"])))
	var best := 1
	for i in range(1, poly.size() - 2):
		if poly[i].distance_to(poly[i + 1]) > poly[best].distance_to(poly[best + 1]):
			best = i
	var sp := Interior.split_corridor(bp, int(c["id"]), best, (poly[best] + poly[best + 1]) * 0.5)
	Interior.add_corridor(bp, int(e3["id"]), int(sp["node"]))
	Interior.add_corridor(bp, int(e4["id"]), int(sp["node"]))
	return bp
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var g: Node = get_root().get_node("Game")
	var bp := _roomy()
	var made_room := false
	g.editing_bp = bp
	var ed: Node = load("res://scenes/ship_editor.tscn").instantiate()
	get_root().add_child(ed)
	for i in 5:
		await process_frame
	ed._set_step("Interior")
	ed.cam_yaw = 0.9
	ed.cam_pitch = -0.7
	ed.cam_dist *= 0.7
	var nd: Dictionary = Interior.nodes(ed.bp)[0]
	ed.sel_node = int(nd["id"])
	ed._build_tools()
	ed._changed(false)
	for i in 12:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(a[0] + "/net_editor_t.png")
	ed._cycle_room()
	ed.sel_node = int(nd["id"])
	ed._build_tools()
	ed._changed(false)
	for i in 12:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(a[0] + "/net_editor_room.png")
	print("room: ", Interior.is_room(ed.bp, Interior.node(ed.bp, int(nd["id"]))), " issues ", Interior.issues(ed.bp))
	var final_bp: Dictionary = ed.bp.duplicate(true)
	ed.queue_free()
	await process_frame
	g.session = {"mode": "sandbox", "ship": final_bp, "return_scene": "res://scenes/main_menu.tscn"}
	var ar: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(ar)
	for i in 20:
		await process_frame
	var hud = ar.hud
	var pv = hud.preview
	pv._toggle_expand()
	pv.set_view(2)
	pv.set_layer(99)
	pv.yaw = 0.6
	pv.pitch = -0.6
	var n2: Dictionary = Interior.nodes(ar.player.bp)[0]
	pv.selected = {"kind": "node", "id": int(n2["id"]), "y": 0.0}
	for i in 50:
		await process_frame
	pv.refresh()
	for i in 6:
		await process_frame
	var img := get_root().get_viewport().get_texture().get_image()
	var r: Rect2 = hud.p1.get_global_rect().grow(6.0)
	img.get_region(Rect2i(Vector2i(maxf(r.position.x, 0), maxf(r.position.y, 0)), Vector2i(minf(r.size.x, img.get_width()), minf(r.size.y, img.get_height())))).save_png(a[0] + "/net_panel1.png")
	print("saved")
	quit()
