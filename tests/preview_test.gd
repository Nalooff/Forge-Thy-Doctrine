extends SceneTree
## Headless check of Panel 1 (ShipPreview): hover info, exploded layout, onion decks, systems overlay.
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	var g: Node = get_root().get_node("Game")
	for bp in [Premades.lance(), Premades.anvil(), Premades.dart()]:
		g.session = {"mode": "sandbox", "ship": bp, "return_scene": "res://scenes/main_menu.tscn"}
		var ar: Node = load("res://scenes/arena.tscn").instantiate()
		get_root().add_child(ar)
		for i in 6:
			await physics_frame
			await process_frame
		await _run(ar, String(bp["name"]))
		ar.queue_free()
		await process_frame
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)


func _run(ar: Node, nm: String) -> void:
	var hud = ar.hud
	var pv = hud.preview
	pv.size = Vector2(300, 220)
	var s: Ship = ar.player
	check(pv.items.size() == s.mods.size() and pv.sections.size() == s.bp["rings"].size() - 1, "[%s] model built: %d modules, %d hull sections" % [nm, pv.items.size(), pv.sections.size()])

	# ---- basic: hover a module through the glass hull, hover bare hull
	pv.set_view(pv.BASIC)
	for i in 4:
		await process_frame
	var inner: Dictionary = {}
	for m in s.mods:
		if String(m["kind"]) == "internal":
			inner = m
			break
	if not inner.is_empty():
		var h: Dictionary = pv.pick_at(pv.module_screen_pos(int(inner["id"])))
		check(h.get("kind", "") == "module", "[%s] ray through the glass hull finds the internal module (%s)" % [nm, String(inner["label"])])
		var lines: Array = pv.info_lines({"kind": "module", "id": int(inner["id"])})
		check(lines.size() >= 5 and String(lines[0]["t"]).contains(String(inner["label"])), "[%s] module info card has %d lines" % [nm, lines.size()])
	var found_hull := false
	for px in range(20, 280, 10):
		for py in range(10, 210, 10):
			var hh: Dictionary = pv.pick_at(Vector2(px, py))
			if hh.get("kind", "") == "hull":
				found_hull = true
				var hl: Array = pv.info_lines(hh)
				check(hl.size() >= 5 and String(hl[0]["t"]).begins_with("HULL"), "[%s] hull info card: %s / %s" % [nm, hl[0]["t"], hl[1]["t"]])
				break
		if found_hull:
			break
	check(found_hull, "[%s] some screen point hits bare hull" % nm)
	pv.hull_mode = 3
	pv._apply_view()
	var none_hull := true
	for px in range(20, 280, 20):
		for py in range(10, 210, 20):
			if pv.pick_at(Vector2(px, py)).get("kind", "") == "hull":
				none_hull = false
	check(none_hull, "[%s] hull Off: nothing hull-pickable" % nm)
	pv.hull_mode = 0
	pv._apply_view()

	# ---- exploded
	pv.set_view(pv.EXPLODED)
	for i in 120:
		await process_frame
	check(absf(pv.spread_cur - 1.0) < 0.01, "[%s] explode animation reaches full spread" % nm)
	var overlaps := 0
	var moved := 0
	for i in range(pv.items.size()):
		var a: Dictionary = pv.items[i]
		var ma: Dictionary = a["m"]
		var ba := AABB((a["disp"] as Vector3) - (ma["size"] as Vector3) * 0.5, ma["size"])
		if (a["disp"] as Vector3).distance_to(a["home"]) > pv.longest * 0.03:
			moved += 1
		for j in range(i + 1, pv.items.size()):
			var b: Dictionary = pv.items[j]
			var mb: Dictionary = b["m"]
			var bb := AABB((b["disp"] as Vector3) - (mb["size"] as Vector3) * 0.5, mb["size"])
			if ba.intersects(bb):
				overlaps += 1
	check(overlaps == 0, "[%s] exploded: no two modules overlap (%d overlaps)" % [nm, overlaps])
	check(moved >= pv.items.size() - 1, "[%s] exploded: modules moved away from their place (%d of %d)" % [nm, moved, pv.items.size()])
	var gaps_ok := true
	for k in range(pv.sections.size() - 1):
		var z_a: float = (pv.sections[k]["node"] as Node3D).position.z + float(pv.sections[k]["z1"])
		var z_b: float = (pv.sections[k + 1]["node"] as Node3D).position.z + float(pv.sections[k + 1]["z0"])
		if z_b - z_a < pv.longest * 0.05:
			gaps_ok = false
	check(gaps_ok, "[%s] exploded: hull sections slide apart" % nm)
	pv.spread = 0.0
	for i in 160:
		await process_frame
	var home_ok := true
	for it in pv.items:
		if (it["disp"] as Vector3).distance_to(it["home"]) > 0.01:
			home_ok = false
	check(home_ok, "[%s] spread 0 puts every module back" % nm)
	pv.spread = 1.0

	# ---- onion
	pv.set_view(pv.ONION)
	check(pv.layers >= 4, "[%s] %d decks" % [nm, pv.layers])
	pv.set_layer(pv.layers)
	for i in 3:
		await process_frame
	var vis_all := 0
	for it in pv.items:
		if (it["fill"] as MeshInstance3D).visible:
			vis_all += 1
	check(vis_all == pv.items.size(), "[%s] ALL decks: every module shown" % nm)
	pv.set_layer(0)
	for i in 3:
		await process_frame
	var vis_low := 0
	for it in pv.items:
		if (it["fill"] as MeshInstance3D).visible:
			vis_low += 1
	var any_above := false
	for it in pv.items:
		if (it["home"] as Vector3).y - ((it["m"] as Dictionary)["size"] as Vector3).y * 0.5 >= pv.deck_range(0).y:
			any_above = true
	check(vis_low < pv.items.size() or not any_above, "[%s] deck 1: modules above are hidden (%d of %d shown)" % [nm, vis_low, pv.items.size()])
	check(pv.cut_lines.get_surface_count() >= 1 and pv.cut_fill.get_surface_count() >= 1, "[%s] cut face (outline + fill) is built" % nm)
	check(pv.deck_lines.get_surface_count() >= 1, "[%s] deck rings are drawn" % nm)
	var tops := 0
	for k in range(pv.layers):
		pv.set_layer(k)
		if pv._clip_y() <= pv.deck_range(k).y + 1e-4:
			tops += 1
	check(tops == pv.layers, "[%s] every deck clips at its own top" % nm)
	# a ray must not hit a part that was cut away
	pv.set_layer(0)
	for i in 3:
		await process_frame
	var hit_cut := false
	for it in pv.items:
		if pv._item_above_clip(it) and pv.pick_at(pv.module_screen_pos(int(it["id"]))).get("id", -1) == int(it["id"]):
			hit_cut = true
	check(not hit_cut, "[%s] hidden modules cannot be hovered" % nm)

	# ---- systems
	pv.set_view(pv.SYSTEMS)
	pv.sys_mode = 0
	pv.refresh()
	check(pv.ov_lines.get_surface_count() == 1, "[%s] links overlay drawn (%d links)" % [nm, s.bp["links"].size()])
	pv.sys_mode = 1
	pv.refresh()
	check(pv.ov_lines.get_surface_count() == 1, "[%s] power grid overlay drawn" % nm)
	check(pv._status_line().begins_with("Power"), "[%s] power header: %s" % [nm, pv._status_line()])

	# ---- damaged / destroyed module shows up in the card
	var victim: Dictionary = s.mods[0]
	victim["hp"] = 0.0
	victim["alive"] = false
	var vl: Array = pv.info_lines({"kind": "module", "id": int(victim["id"])})
	check(String(vl[1]["t"]) == "DESTROYED", "[%s] destroyed module reads DESTROYED" % nm)
	pv.set_view(pv.BASIC)
	pv.refresh()

	# ---- expand button resizes Panel 1 and back
	var before: float = hud.p1.anchor_top
	pv._toggle_expand()
	check(hud.p1.anchor_top < before, "[%s] Expand grows Panel 1" % nm)
	pv._toggle_expand()
	check(is_equal_approx(hud.p1.anchor_top, before), "[%s] Shrink restores Panel 1" % nm)
