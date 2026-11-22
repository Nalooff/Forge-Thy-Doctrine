extends SceneTree
## Screenshots of Panel 1 in every tab (needs a display): xvfb-run godot --rendering-driver opengl3 --script res://tests/preview_shot.gd -- out_dir [ship]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var g: Node = get_root().get_node("Game")
	var bp: Dictionary = Premades.lance()
	if a.size() > 1 and a[1] == "anvil":
		bp = Premades.anvil()
	g.session = {"mode": "sandbox", "ship": bp, "return_scene": "res://scenes/main_menu.tscn"}
	var ar: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(ar)
	for i in 20:
		await process_frame
	var hud = ar.hud
	var pv = hud.preview
	var shots := [
		["basic", 0, false, {"kind": "mod", "type": "generator"}],
		["basic_hull", 0, false, {"kind": "hull"}],
		["exploded", 1, false, {}],
		["onion", 2, false, {"layer": 2}],
		["links", 3, false, {}],
		["power", 3, false, {"power": true}],
		["heat", 3, false, {"heat": true}],
		["basic_big", 0, true, {"kind": "mod", "type": "barrel"}],
		["exploded_big", 1, true, {}],
		["onion_big", 2, true, {"layer": 1}],
		["links_big", 3, true, {}],
		["heat_big", 3, true, {"heat": true}],
	]
	var cur_big := false
	for sh in shots:
		hud.p1.tab_active = sh[1]
		hud.p1.queue_redraw()
		if sh[2] != cur_big:
			pv._toggle_expand()
			cur_big = sh[2]
		pv.set_view(sh[1])
		pv.selected = {}
		var o: Dictionary = sh[3]
		if o.has("layer"):
			pv.set_layer(o["layer"])
		pv.sys_mode = 1 if o.has("power") else (2 if o.has("heat") else 0)
		pv._apply_view()
		pv.yaw = 0.7
		pv.pitch = -0.35
		for i in 45:
			await process_frame
		if o.get("kind", "") == "mod":
			for m in ar.player.mods:
				if m["type"] == o["type"]:
					pv.selected = {"kind": "module", "id": int(m["id"])}
					break
		elif o.get("kind", "") == "hull":
			for px in range(20, int(pv.size.x) - 20, 8):
				for py in range(10, int(pv.size.y) - 20, 8):
					var hh: Dictionary = pv.pick_at(Vector2(px, py))
					if hh.get("kind", "") == "hull" and pv.selected.is_empty():
						pv.selected = hh
		if o.has("heat"):
			var k := 0
			for m in ar.player.mods:
				m["heat"] = 25.0 + 70.0 * float((k * 37) % 10) / 10.0
				k += 1
			ar.player.hull_temp = 55.0
			ar.player._refresh_heat_summary()
		pv.refresh()
		for i in 3:
			await process_frame
		var img := get_root().get_viewport().get_texture().get_image()
		var r: Rect2 = hud.p1.get_global_rect().grow(6.0)
		var crop := img.get_region(Rect2i(Vector2i(maxf(r.position.x, 0), maxf(r.position.y, 0)), Vector2i(minf(r.size.x, img.get_width()), minf(r.size.y, img.get_height()))))
		crop.save_png("%s/%s.png" % [out, sh[0]])
		print("saved ", sh[0], " ", crop.get_size())
	quit()
