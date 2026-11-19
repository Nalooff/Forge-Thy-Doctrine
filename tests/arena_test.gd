extends SceneTree
## Headless smoke test: run an arena scene for N physics seconds and report.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "sandbox"
	var secs: float = float(args[1]) if args.size() > 1 else 5.0
	var g: Node = get_root().get_node("Game")
	g.session = {"mode": mode, "ship": Premades.dart(), "return_scene": "res://scenes/main_menu.tscn", "bots_ally": 1, "bots_enemy": 3, "kill_limit": 3, "ruleset": (args[2] if args.size() > 2 else "tdm")}
	var scn: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(scn)
	await process_frame
	var frames := int(secs * 60.0)
	for i in frames:
		await physics_frame
		if i == 60 and mode == "sandbox":
			scn.player.cmd = {"move": Vector3(0, 0, 1), "fire": true}
	var ships := get_nodes_in_group("ships")
	print("mode=", mode, " ships alive=", ships.size(), " wrecks=", get_nodes_in_group("wrecks").size(), " scores=", scn.scores)
	if scn.player:
		print("player alive=", scn.player.alive, " hull=", snappedf(scn.player.hull_hp, 1.0), " speed=", snappedf(scn.player.linear_velocity.length(), 0.1))
	quit()
