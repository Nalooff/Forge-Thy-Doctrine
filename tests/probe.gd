extends SceneTree
func _init() -> void:
	for bp in Premades.all():
		var st := ShipData.compute_stats(bp)
		var iss := ShipData.validate(bp, {"max_tier": 4, "budget": 1500})
		print("== ", bp["name"], " class=", st["class"], " len=", snappedf(st["length"], 0.1), " mass=", snappedf(st["mass"], 0.1), "t cost=", snappedf(st["cost"], 0.1),
			" accel=", snappedf(st["accel_fwd"], 0.1), " pwr ", snappedf(st["power_out"], 0.1), "/", snappedf(st["power_idle"], 0.1), "/", snappedf(st["power_peak"], 0.1), " gyro=", snappedf(st["gyro"], 0.01), " tris=", st["tris"], " hullhp=", snappedf(st["hull_hp"], 1.0))
		for i in iss:
			print("   ISSUE: ", i["msg"])
	quit()
