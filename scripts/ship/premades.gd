class_name Premades
extends RefCounted
## Premade ships that ship with the game (GDD 1.1 "Starting points").


static func _base(ship_name: String) -> Dictionary:
	var bp := ShipData.new_blueprint(ship_name)
	bp["author"] = "Forge"
	ShipData.add_module(bp, "commander_post", Vector3(0, 0.3, -8.6), Vector3(2, 1.8, 2.4), 0)
	ShipData.add_module(bp, "generator", Vector3(0, 0, -2.2), Vector3(2, 2, 2))
	ShipData.add_module(bp, "engine_room", Vector3(0, 0, 0.6), Vector3(2.5, 2, 3))
	ShipData.add_module(bp, "radar_room", Vector3(0, 0, 3.6), Vector3(2, 2, 2))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			ShipData.add_module(bp, "thruster", Vector3(sx * 1.3, sy * 0.8, 8.4), Vector3(1, 1, 2.4), 0)
	return bp


## Dart: fixed forward guns on a Turret Control (aim by pointing the ship).
static func dart() -> Dictionary:
	var bp := _base("Dart")
	ShipData.add_module(bp, "turret_control", Vector3(0, 0, -4.5), Vector3(2.5, 1.5, 2.5))
	ShipData.add_module(bp, "barrel", Vector3(-1.9, 0, -6.4), Vector3(0.6, 0.6, 3.2), 0, "kinetic")
	ShipData.add_module(bp, "barrel", Vector3(1.9, 0, -6.4), Vector3(0.6, 0.6, 3.2), 0, "kinetic")
	ShipData.auto_link(bp)
	Interior.auto_connect(bp)
	return bp


## Lance: a rotating Turret Bay on the spine carrying a laser and a missile pod.
static func lance() -> Dictionary:
	var bp := _base("Lance")
	bp["accent"] = [0.95, 0.55, 0.2]
	ShipData.add_module(bp, "turret_bay", Vector3(0, 1.85, -2.0), Vector3(2.5, 1.5, 2.5), 4)
	ShipData.add_module(bp, "barrel", Vector3(-0.7, 2.35, -2.0), Vector3(0.6, 0.6, 3.2), 0, "laser")
	ShipData.add_module(bp, "barrel", Vector3(0.7, 2.35, -2.0), Vector3(0.6, 0.6, 3.2), 0, "missile")
	ShipData.auto_link(bp)
	Interior.auto_connect(bp)
	return bp


## Anvil: slow, heavily armoured corvette with a big kinetic turret.
static func anvil() -> Dictionary:
	var bp := lance()
	bp["name"] = "Anvil"
	bp["thickness"] = 0.35
	bp["color"] = [0.45, 0.47, 0.5]
	bp["accent"] = [0.3, 0.85, 0.5]
	ShipData.scale_ship(bp, 2.6, true)
	var removed: Array = []
	var seen := 0
	for m in bp["modules"]:
		if m["type"] == "thruster":
			seen += 1
			if seen > 2:
				removed.append(int(m["id"]))
	for id in removed:
		ShipData.remove_module(bp, int(id))
	for m in bp["modules"]:
		if m["type"] == "barrel":
			m["weapon"] = "kinetic"
	bp["interior"] = {"next_id": 1, "entrances": [], "corridors": []}   # the Anvil rebuilds its own network
	Interior.auto_connect(bp)
	return bp


static func all() -> Array:
	return [dart(), lance(), anvil()]
