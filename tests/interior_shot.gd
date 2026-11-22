extends SceneTree
## Screenshot of the Interior step of the editor: xvfb-run godot --rendering-driver opengl3 --script res://tests/interior_shot.gd -- out.png [ship]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var g: Node = get_root().get_node("Game")
	g.editing_bp = Premades.anvil() if a.size() > 1 and a[1] == "anvil" else Premades.lance()
	var ed: Node = load("res://scenes/ship_editor.tscn").instantiate()
	get_root().add_child(ed)
	for i in 5:
		await process_frame
	ed._set_step("Interior")
	ed.cam_yaw = 0.9
	ed.cam_pitch = -0.55
	ed.cam_dist *= 0.75
	var cs: Array = Interior.corridors(ed.bp)
	ed.sel_cor = int(cs[cs.size() - 1]["id"])
	ed.sel_seg = 2
	ed._changed(false)
	ed._build_tools()
	for i in 12:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(a[0])
	print("saved")
	quit()
