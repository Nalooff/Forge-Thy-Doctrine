class_name Premades
extends RefCounted
## Premade ships that ship with the game (GDD 1.1 "Starting points").


static func dart() -> Dictionary:
	var bp := ShipData.new_blueprint("Dart")
	bp["author"] = "Forge"
	var cp := ShipData.add_module(bp, "commander_post", Vector3(0, 0.3, -8.6), Vector3(2, 1.8, 2.4), 0)
	ShipData.add_module(bp, "turret_bay", Vector3(0, 0, -4.5), Vector3(2.5, 1.5, 2.5))
	ShipData.add_module(bp, "generator", Vector3(0, 0, -2.2), Vector3(2, 2, 2))
	ShipData.add_module(bp, "engine_room", Vector3(0, 0, 0.6), Vector3(2.5, 2, 3))
	ShipData.add_module(bp, "radar_room", Vector3(0, 0, 3.6), Vector3(2, 2, 2))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			ShipData.add_module(bp, "thruster", Vector3(sx * 1.3, sy * 0.8, 8.4), Vector3(1, 1, 2.4), 0)
	ShipData.add_module(bp, "barrel", Vector3(-1.9, 0, -6.4), Vector3(0.6, 0.6, 3.2), 0, "kinetic")
	ShipData.add_module(bp, "barrel", Vector3(1.9, 0, -6.4), Vector3(0.6, 0.6, 3.2), 0, "kinetic")
	ShipData.auto_link(bp)
	return bp


static func lance() -> Dictionary:
	var bp := dart()
	bp["name"] = "Lance"
	bp["accent"] = [0.95, 0.55, 0.2]
	var n := 0
	for m in bp["modules"]:
		if m["type"] == "barrel":
			m["weapon"] = "laser" if n == 0 else "missile"
			n += 1
	return bp


static func anvil() -> Dictionary:
	var bp := dart()
	bp["name"] = "Anvil"
	bp["thickness"] = 0.35
	bp["color"] = [0.45, 0.47, 0.5]
	bp["accent"] = [0.3, 0.85, 0.5]
	ShipData.scale_ship(bp, 2.6, true)
	# fewer, relatively smaller engines: a slow, heavily armoured corvette
	var keep: Array = []
	var removed: Array = []
	var seen := 0
	for m in bp["modules"]:
		if m["type"] == "thruster":
			seen += 1
			if seen > 2:
				removed.append(int(m["id"]))
				continue
		keep.append(m)
	for id in removed:
		ShipData.remove_module(bp, int(id))
	for m in bp["modules"]:
		if m["type"] == "barrel":
			m["weapon"] = "kinetic"
	return bp


static func all() -> Array:
	return [dart(), lance(), anvil()]
