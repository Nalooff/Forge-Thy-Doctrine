class_name Bot
extends RefCounted
## Simple commander AI used for Freematch opponents and test-range dummies.

var ship: Ship
var behavior := "hunter"   # hunter | sentry (stays put, shoots) | static (inert target) | drift | spin | dummy
var pref_range := 450.0
var _drift := Vector3.ZERO


func _init(s: Ship, b := "hunter") -> void:
	ship = s
	behavior = b
	_drift = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized() * 12.0
	var best := 0.0
	for m in ship.mods_of("barrel"):
		best = maxf(best, float(m["ws"]["range"]))
	if best > 0.0:
		pref_range = clampf(best * 0.18, 250.0, 700.0)


func nearest_enemy() -> Ship:
	var best: Ship = null
	var bd := INF
	for s in ship.get_tree().get_nodes_in_group("ships"):
		var o := s as Ship
		if o == ship or not o.alive or o.team == ship.team:
			continue
		var d := ship.global_position.distance_to(o.global_position)
		if d < bd:
			bd = d
			best = o
	return best


func update(_delta: float) -> void:
	if not ship.alive:
		return
	match behavior:
		"dummy":
			ship.cmd = {}
			return
		"static":
			ship.cmd = Autopilot.hold(ship)
			return
		"drift":
			ship.cmd = {"auto": true, "v_target": _drift}
			return
		"spin":
			ship.cmd = {"rot": Vector3(0.0, 0.0, 0.35), "move": Vector3.ZERO}
			return
	var t := nearest_enemy()
	ship.target = t
	if t == null:
		ship.cmd = Autopilot.hold(ship)
		return
	var d := ship.global_position.distance_to(t.global_position)
	var c: Dictionary
	if behavior == "sentry":
		c = Autopilot.face(ship, t.global_position)
		c["v_target"] = Vector3.ZERO
	elif not ship.can_move():
		c = Autopilot.face(ship, t.global_position)
	elif d > pref_range * 1.4:
		c = Autopilot.drive_toward(ship, t.global_position, 160.0, pref_range)
	else:
		c = Autopilot.orbit(ship, t.global_position, pref_range, 70.0)
	var rng := 1500.0
	for m in ship.mods_of("barrel"):
		rng = minf(rng, float(m["ws"]["range"]) * 0.7) if rng < 1500.0 else float(m["ws"]["range"]) * 0.7
	c["aim_target"] = t
	c["fire"] = d < rng
	ship.cmd = c
