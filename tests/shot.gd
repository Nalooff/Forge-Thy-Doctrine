extends SceneTree
## Renders a scene and saves a screenshot (needs a display, e.g. xvfb-run): -- scene_path out.png [step]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var g: Node = get_root().get_node("Game")
	var scene_path: String = a[0]
	var out: String = a[1]
	if a.size() > 2 and scene_path.contains("editor"):
		g.editing_bp = Premades.dart()
	g.session = {"mode": "sandbox", "ship": Premades.lance(), "return_scene": "res://scenes/main_menu.tscn"}
	var scn: Node = load(scene_path).instantiate()
	get_root().add_child(scn)
	await process_frame
	await process_frame
	if a.size() > 2 and scn.has_method("_set_step"):
		scn._set_step(a[2])
	elif a.size() > 2 and scn.get("hud") != null:
		scn.hud.set_mode(a[2])
	for i in 90:
		await process_frame
	if scn.has_method("lock_target"):
		scn.player.cmd = {}
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()
