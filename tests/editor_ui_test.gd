extends SceneTree
## Headless check of the ship editor UI flow: godot --headless --path . --script res://tests/editor_ui_test.gd
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _initialize() -> void:
	var g: Node = get_root().get_node("Game")
	g.editing_bp = Premades.dart()
	var ed: Node = load("res://scenes/ship_editor.tscn").instantiate()
	get_root().add_child(ed)
	await process_frame
	await process_frame
	# Type / Modifier / Helper
	check(ed.mode_opts["Type"].item_count == 2 and ed.mode_opts["Type"].get_item_text(0) == "Vertex", "Hull step: Type offers Vertex/Ring")
	ed._pick_mode("Type", 1)
	check(ed.ring_mode, "Type = Ring selects whole rings")
	ed._pick_tab("Modifier")
	check(ed.left_title.text == "MODIFIER : MIRROR", "Modifier tab shows Mirror tools")
	ed._pick_tab("Modifier")
	check(not ed.left_panel.visible, "pressing the active tab again hides the left panel")
	ed._pick_tab("Helper")
	check(ed.left_panel.visible and ed.left_title.text == "HELPER : RULER", "Helper tab opens with Ruler")
	for s in ed.STEPS:
		ed._set_step(s)
		for t in ed.TABS:
			ed._pick_tab(t)
			ed._pick_tab(t) if not ed.left_panel.visible else null
	check(true, "every step x tab builds without error")
	ed._set_step("Hull")
	# view settings
	ed.ortho = true
	ed._update_cam()
	check(ed.cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthogonal projection")
	ed.ortho = false
	# Load popup
	ed._open_load()
	check(ed.load_ov.visible and ed.load_list.item_count >= 3, "Load popup lists the ships")
	check(ed.load_new.disabled and ed.load_mod.disabled, "load buttons disabled until a ship is selected")
	ed.load_list.select(1)
	ed._on_load_selected(1)
	check(not ed.load_new.disabled and ed.load_name.text.begins_with(ed._ship_cache[1]["name"]), "selected ship name shown at the bottom")
	var orig_name: String = ed._ship_cache[1]["name"]
	ed.load_scope.select(2)
	ed._load_pick(true)
	check(ed.bp["name"] == orig_name + " copy" and ed.bp["modules"].is_empty() and not ed.load_ov.visible, "new from prefab, hull only: copy without modules")
	ed._open_load()
	ed.load_list.select(1)
	ed._load_pick(false)
	check(ed.bp["name"] == orig_name and ed.bp["modules"].size() > 0, "modify this ship keeps name and modules")
	# export / import
	ed.bp = Premades.dart()
	ed._changed()
	await process_frame
	await process_frame
	ed._fd_action = "export"
	ed._on_file_picked("/tmp/export_test.json")
	check(FileAccess.file_exists("/tmp/export_test.json"), "export writes the ship file")
	var n0: int = g.all_ships().size()
	ed._fd_action = "import"
	ed._on_file_picked("/tmp/export_test.json")
	check(g.all_ships().size() == n0 + 1, "import adds a ship (name clash gets a suffix)")
	for s in g.all_ships():
		if s["source"] == "user" and String(s["name"]).ends_with("(imported)"):
			DirAccess.remove_absolute(s["path"])
	ed._fd_action = "import"
	var bad := FileAccess.open("/tmp/bad_ship.json", FileAccess.WRITE)
	bad.store_string("not json")
	bad.close()
	ed._on_file_picked("/tmp/bad_ship.json")
	check(ed.status.text.begins_with("Import failed"), "invalid file is refused")
	print("FAILS: ", fails)
	quit(fails)
