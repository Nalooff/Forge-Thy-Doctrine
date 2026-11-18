extends SceneTree
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var s := Ship.new()
	root.add_child(s)
	s.setup(Premades.dart(), 0)
	s.cmd = {"move": Vector3(0, 0, 1), "rot": Vector3.ZERO}
	for i in 120:
		await physics_frame
	print("speed after 2s full forward: ", s.linear_velocity.length(), " pos ", s.global_position, " power ", s.power_supply, "/", s.power_demand)
	quit()
