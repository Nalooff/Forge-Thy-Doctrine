extends Node3D
## Arena: Test Range (sandbox) and Freematch (team deathmatch vs bots). GDD 3.3, 4.1, 4.2.
## Session data (Game.session): mode, ship (blueprint), return_scene, bots_ally, bots_enemy, kill_limit.

var mode := "sandbox"
var player: Ship
var rig: CamRig
var hud: Hud
var bots: Array = []
var paused := false
var free_cursor := false
var player_bp: Dictionary = {}
var order := "none"
var scores := {}
var ruleset := "tdm"      # tdm = Team Deathmatch, elim = Team Elimination, dm = Deathmatch
var kill_limit := 10
var respawn_t := 0.0
var respawn_delay := 5.0
var test_shot_on := false
var test_shot_weapon := "kinetic"
var match_over := false
var _mouse := Vector2.ZERO
var _last_shake := -1000.0
var _t := 0.0
var _dummy: Ship
var _tutorial := false
var waypoint := Vector3.ZERO
var has_wp := false
var viz: WaypointViz
var tuner: OrderTuner
var sel_weapons: Array = []   # ids of the selected weapon units (Turret Bays / fixed barrels)
var order_p := {}          # parameters of the active order
var facing := {"mode": "auto"}   # facing while moving: auto (travel), lock (fixed direction), point
var _wp_drag := 0          # 0 none, 1 dragging on the XZ plane, 2 dragging altitude


func _ready() -> void:
	var s: Dictionary = Game.session
	mode = String(s.get("mode", "sandbox"))
	player_bp = s.get("ship", Premades.dart())
	ruleset = String(s.get("ruleset", "tdm"))
	kill_limit = int(s.get("kill_limit", 30 if ruleset == "dm" else 10))
	_tutorial = bool(s.get("tutorial", false))
	_build_world()
	rig = CamRig.new()
	add_child(rig)
	viz = WaypointViz.new()
	viz.arena = self
	add_child(viz)
	tuner = OrderTuner.new()
	tuner.arena = self
	add_child(tuner)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	if mode == "freematch":
		_start_freematch()
	else:
		_spawn_player(Vector3.ZERO, Vector3(0, 0, -1))
		spawn_dummy(Premades.anvil(), "static")
		hud.log_msg("[b]Test range[/b]: spawn dummies, test-shoot your own hull, try the flight model.")
		if _tutorial:
			hud.log_msg("[color=yellow]Tutorial[/color]: 1) thrust with W/A/S/D, 2) press X to toggle assist, 3) press T to lock the dummy, 4) hold LMB to fire, 5) read module HP at left.")
	hud.say("Mode: %s" % ("Test Range" if mode == "sandbox" else "Freematch - " + _ruleset_name()), Color(1.0, 0.75, 0.3))


# ------------------------------------------------------------------ world
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type sky;
float hash(vec3 p){ p = fract(p*0.3183099+.1); p*=17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
void sky(){
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.004,0.005,0.011);
	vec3 g = floor(d*520.0);
	float h = hash(g);
	col += vec3(step(0.9988, h) * (0.4 + 0.6*hash(g+7.1)));
	COLOR = col;
}
"""
	sm.shader = sh
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.38)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.32, 0.29, 0.27)
	rock_mat.roughness = 1.0
	for i in 45:
		var body := StaticBody3D.new()
		var r := rng.randf_range(15.0, 90.0)
		var pos := Vector3(rng.randf_range(-3000, 3000), rng.randf_range(-600, 600), rng.randf_range(-3000, 3000))
		if pos.length() < 250.0:
			pos += pos.normalized() * 400.0
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = r
		sp.height = r * 2.0
		sp.radial_segments = 14
		sp.rings = 8
		mi.mesh = sp
		mi.material_override = rock_mat
		mi.scale = Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.6, 1.1), rng.randf_range(0.7, 1.4))
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = r * 0.85
		cs.shape = ss
		body.add_child(cs)
		body.position = pos
		add_child(body)


func _spawn_ship(bp: Dictionary, team: int, pos: Vector3, dir: Vector3) -> Ship:
	var s := Ship.new()
	add_child(s)
	s.setup(bp, team)
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	s.global_transform = Transform3D(Basis.looking_at(dir, up), pos)
	s.module_destroyed.connect(_on_module_destroyed)
	s.died.connect(_on_died)
	return s


func _spawn_player(pos: Vector3, dir: Vector3) -> void:
	player = _spawn_ship(player_bp, 0, pos, dir)
	player.is_player = true
	player.assist = bool(Game.settings["assist"])
	player.hit_report.connect(_on_player_hit)
	rig.follow(player)
	rig.first_person = false
	hud.bind_ship(player)
	order = "none"
	has_wp = false
	_wp_drag = 0
	order_p = {}
	sel_weapons = []
	facing = {"mode": "auto"}
	if tuner != null:
		tuner.abort()
	rig.set_map_mode(false)
	_apply_mouse_mode()


func spawn_dummy(bp: Dictionary, behavior: String) -> void:
	if _dummy != null and is_instance_valid(_dummy):
		bots = bots.filter(func(b): return b.ship != _dummy)
		_dummy.queue_free()
	var tf := player.global_transform
	var pos := tf.origin + (-tf.basis.z) * 220.0
	_dummy = _spawn_ship(bp, 1, pos, tf.basis.z)
	bots.append(Bot.new(_dummy, behavior))
	hud.log_msg("Dummy: %s (%s)" % [bp["name"], behavior])


func _ruleset_name() -> String:
	return {"tdm": "Team Deathmatch", "elim": "Team Elimination", "dm": "Deathmatch"}.get(ruleset, "Team Deathmatch")


func _start_freematch() -> void:
	var ally := int(Game.session.get("bots_ally", 1))
	var enemy := int(Game.session.get("bots_enemy", 2))
	_spawn_player(Vector3(0, 0, 1300), Vector3(0, 0, -1))
	var lib: Array = Premades.all()
	if ruleset == "dm":
		for i in enemy:
			_spawn_bot(i + 1, lib)
		hud.log_msg("[b]Deathmatch[/b]: everyone for themselves, first to %d kills." % kill_limit)
		return
	for i in ally:
		_spawn_bot(0, lib)
	for i in enemy:
		_spawn_bot(1, lib)
	if ruleset == "elim":
		hud.log_msg("[b]Team Elimination[/b]: one life each, last team standing wins.")
	else:
		hud.log_msg("[b]Team Deathmatch[/b]: first team to %d kills wins." % kill_limit)


func _spawn_bot(team: int, lib: Array) -> void:
	var bp: Dictionary = lib[randi() % lib.size()]
	var z := 1300.0 if team == 0 else -1300.0
	var pos := Vector3(randf_range(-250, 250), randf_range(-60, 60), z + randf_range(-150, 150))
	if ruleset == "dm":
		var ang := float(team) * TAU / maxf(float(int(Game.session.get("bots_enemy", 2))), 1.0)
		pos = Vector3(cos(ang), randf_range(-0.1, 0.1), sin(ang)) * 1300.0
	var dir := (Vector3.ZERO - pos).normalized() if ruleset == "dm" else Vector3(0, 0, -1.0 if team == 0 else 1.0)
	var s := _spawn_ship(bp, team, pos, dir)
	bots.append(Bot.new(s, "hunter"))


# ------------------------------------------------------------------ events
func _on_module_destroyed(s: Ship, m: Dictionary) -> void:
	if s == player:
		hud.say("%s destroyed!" % m["label"], Color(1, 0.5, 0.3))
		hud.log_msg("[color=red]%s #%d destroyed[/color]" % [m["label"], m["id"]])


func _on_player_hit(_s: Ship, r: Dictionary) -> void:
	var parts: Array = []
	for mm in r["modules"]:
		parts.append("%s -%d%s" % [mm["label"], int(mm["dmg"]), " (DESTROYED)" if mm["destroyed"] else ""])
	hud.log_msg("[color=orange]%s[/color] pen %.2f vs armor %.2f -> %s | hull -%d | %s" % [r["kind"], r["pen"], r["armor"], "PENETRATED" if r["penetrated"] or r["kind"] == "missile" else "stopped", int(r["hull"]), ", ".join(parts) if not parts.is_empty() else "no module damage"])
	hud.flash()
	if Game.settings["shake"] and _t - _last_shake > 30.0:
		_last_shake = _t
		rig.shake(0.25)


func _alive_teams() -> Array:
	var t: Array = []
	for n in get_tree().get_nodes_in_group("ships"):
		var o := n as Ship
		if o.alive and not (o.team in t):
			t.append(o.team)
	return t


func _end_match(win: bool, text := "") -> void:
	match_over = true
	hud.say(("VICTORY" if win else "DEFEAT") if text == "" else text, Color(1.0, 0.8, 0.3) if win else Color(1, 0.3, 0.2))
	hud.log_msg("Match over. Press ESC to leave.")


func _on_died(s: Ship, k: Ship) -> void:
	var who := "%s" % s.name
	if k != null:
		who += " destroyed by %s" % k.name
	hud.log_msg("[color=yellow]%s[/color]" % who)
	var respawns := ruleset != "elim"
	if s == player:
		hud.say("YOUR SHIP WAS DESTROYED", Color(1, 0.3, 0.3))
		rig.first_person = false
		_apply_mouse_mode()
		if mode == "freematch" and not match_over and respawns:
			respawn_t = 3.0 + float(s.stats["longest"]) / 10.0
			hud.show_respawn(true, Game.all_ships())
	if mode == "freematch" and not match_over:
		var killer_team := -1
		if k != null and k.team != s.team:
			killer_team = k.team
		elif k == null or k == s:
			killer_team = -2   # suicide / gave up
		if ruleset != "elim" and killer_team >= 0:
			scores[killer_team] = int(scores.get(killer_team, 0)) + 1
		if ruleset == "elim":
			var alive_teams := _alive_teams()
			if alive_teams.size() <= 1:
				var player_wins: bool = alive_teams.size() == 1 and alive_teams[0] == player.team
				_end_match(player_wins, "VICTORY - last team standing" if player_wins else "DEFEAT - eliminated")
				return
		else:
			for tm in scores.keys():
				if int(scores[tm]) >= kill_limit:
					_end_match(int(tm) == player.team)
					return
		if s != player and respawns:
			var tm2 := s.team
			get_tree().create_timer(4.0 + float(s.stats["longest"]) / 12.0).timeout.connect(func():
				if not match_over:
					_spawn_bot(tm2, Premades.all()))
	if s != player:
		bots = bots.filter(func(b): return b.ship != s)
		get_tree().create_timer(25.0).timeout.connect(func():
			if is_instance_valid(s) and s != player:
				s.queue_free())


func respawn_now() -> void:
	if player != null and player.alive:
		return
	var idx := hud.respawn_pick.selected
	var all: Array = Game.all_ships()
	if idx >= 0 and idx < all.size():
		player_bp = all[idx]["bp"]
	if player != null and is_instance_valid(player):
		player.queue_free()
	_spawn_player(Vector3(randf_range(-200, 200), 0, 1300), Vector3(0, 0, -1))
	hud.show_respawn(false)


func give_up() -> void:
	if player != null and player.alive:
		player._die(null)


func repair_player() -> void:
	if player.wreck:
		hud.show_respawn(false)
	player.revive()
	hud.say("Ship repaired", Color(0.5, 1, 0.6))


func score_text() -> String:
	if mode != "freematch":
		return "Test range - no objectives."
	match ruleset:
		"elim":
			var mine := 0
			var theirs := 0
			for n in get_tree().get_nodes_in_group("ships"):
				if (n as Ship).team == player.team:
					mine += 1
				else:
					theirs += 1
			return "Alive  your team: %d   enemies: %d" % [mine, theirs]
		"dm":
			var best := 0
			for tm in scores.keys():
				if int(tm) != player.team:
					best = maxi(best, int(scores[tm]))
			return "Kills  you: %d   best rival: %d   (first to %d)" % [int(scores.get(player.team, 0)), best, kill_limit]
		_:
			var theirs2 := 0
			for tm in scores.keys():
				if int(tm) != player.team:
					theirs2 += int(scores[tm])
			return "Kills  your team: %d   enemies: %d   (limit %d)" % [int(scores.get(player.team, 0)), theirs2, kill_limit]


# ------------------------------------------------------------------ controls
func set_assist(on: bool) -> void:
	if player:
		player.assist = on


func set_waypoint(p: Vector3, go := true) -> void:
	waypoint = p
	has_wp = true
	if go:
		order = "goto"
		order_p = {"end_dir": Vector3.ZERO}


func clear_waypoint() -> void:
	has_wp = false
	_wp_drag = 0
	if order == "goto":
		order = "hold"
	hud.say("Waypoint cleared", Color(0.7, 0.9, 1))


func set_map_mode(on: bool) -> void:
	if player == null or not player.alive:
		return
	rig.set_map_mode(on)
	_wp_drag = 0
	_apply_mouse_mode()
	hud.say("Tactical map" if on else "Standard view", Color(1.0, 0.75, 0.3))


func wp_dist() -> float:
	return player.global_position.distance_to(waypoint) if has_wp and player != null else 0.0


func _plane_hit(mp: Vector2, y: float) -> Variant:
	var o := rig.cam.project_ray_origin(mp)
	var d := rig.cam.project_ray_normal(mp)
	if absf(d.y) < 0.02:
		return null
	var t := (y - o.y) / d.y
	if t < 0.0 or t > 80000.0:
		return null
	return o + d * t


func _plane_hit_n(mp: Vector2, point: Vector3, normal: Vector3) -> Variant:
	var o := rig.cam.project_ray_origin(mp)
	var d := rig.cam.project_ray_normal(mp)
	var den := normal.dot(d)
	if absf(den) < 0.02:
		return null
	var t := normal.dot(point - o) / den
	if t < 0.0 or t > 80000.0:
		return null
	return o + d * t


func _go_to_cursor() -> void:
	if player == null or not player.alive:
		return
	var ar := _aim_ray()
	var o: Vector3 = ar["o"]
	var d: Vector3 = ar["d"]
	var p: Vector3
	if rig.map_mode:
		var h = _plane_hit(get_viewport().get_mouse_position(), waypoint.y if has_wp else player.global_position.y)
		if h == null:
			return
		p = h
	else:
		var hit := Projectile.trace(get_tree(), get_world_3d(), o, o + d * 20000.0, player)
		p = (hit["pos"] as Vector3) if not hit.is_empty() else o + d * 1500.0
	set_waypoint(p)
	hud.say("Going to the cursor point", Color(1.0, 0.8, 0.3))


func _drag_altitude(event: InputEventMouseMotion) -> void:
	var cam := rig.cam
	var o := cam.project_ray_origin(event.position)
	var d := cam.project_ray_normal(event.position)
	var n := cam.global_position - waypoint
	n.y = 0.0
	if n.length() < 0.001:
		n = -cam.global_transform.basis.z
		n.y = 0.0
	n = n.normalized()
	var den := n.dot(d)
	if absf(den) > 0.08:
		var t := n.dot(waypoint - o) / den
		if t > 0.0:
			waypoint.y = clampf((o + d * t).y, -20000.0, 20000.0)
			return
	waypoint.y = clampf(waypoint.y - event.relative.y * float(rig.map_dist) * 0.002, -20000.0, 20000.0)


func _map_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if hud.is_mouse_over_ui():
				return false
			var mp: Vector2 = event.position
			if has_wp and not rig.cam.is_position_behind(waypoint) and rig.cam.unproject_position(waypoint).distance_to(mp) < 26.0:
				_wp_drag = 2
				return true
			var h = _plane_hit(mp, waypoint.y if has_wp else player.global_position.y)
			if h != null:
				set_waypoint(h)
				_wp_drag = 1
			return true
		elif _wp_drag != 0:
			_wp_drag = 0
			return true
	elif event is InputEventMouseMotion and _wp_drag != 0:
		if _wp_drag == 2:
			_drag_altitude(event)
		else:
			var h2 = _plane_hit(event.position, waypoint.y)
			if h2 != null:
				waypoint = h2
		return true
	return false


func set_order(kind: String) -> void:
	match kind:
		"hold":
			order_hold()
		"brake", "none":
			order = kind
			order_p = {}
			hud.say("Order: %s" % ("brake" if kind == "brake" else "manual control"), Color(0.7, 0.9, 1))
		"goto":
			if not has_wp:
				hud.say("No point yet - use Drive to point (or press G over the cursor)", Color(1, 0.8, 0.3))
				return
			order = "goto"
			order_p = {"end_dir": Vector3.ZERO}
		"face":
			tuner.begin("lookat")
		"drive":
			tuner.begin("chase")
		"orbit":
			tuner.begin("orbit")


func order_hold() -> void:
	order = "hold"
	order_p = {"pos": player.global_position}
	hud.say("Holding position", Color(0.7, 0.9, 1))


func order_goto(pos: Vector3, end_dir := Vector3.ZERO) -> void:
	waypoint = pos
	has_wp = true
	order = "goto"
	order_p = {"end_dir": end_dir}
	hud.say("Driving to the point", Color(1.0, 0.8, 0.3))


func order_route(pts: Array, end_dir := Vector3.ZERO) -> void:
	order = "route"
	order_p = {"points": pts.duplicate(), "idx": 0, "end_dir": end_dir}
	waypoint = pts[0]
	has_wp = true
	hud.say("Route: %d points" % pts.size(), Color(1.0, 0.8, 0.3))


func order_orbit(t: Ship, c: Vector3, r: float, normal: Vector3, dirn: float) -> void:
	order = "orbit"
	order_p = {"target": t, "center": c, "radius": r, "alt": 0.0, "normal": normal.normalized(), "dir": dirn}
	hud.say("Orbiting at %s" % WaypointViz.fmt_dist(r), Color(1.0, 0.8, 0.3))


func order_chase(t: Ship, dist: float) -> void:
	order = "chase"
	order_p = {"target": t, "dist": dist}
	hud.say("Driving to the ship, keeping %s" % WaypointViz.fmt_dist(dist), Color(1.0, 0.8, 0.3))


func order_follow(t: Ship, off: Vector3, head: Vector3) -> void:
	order = "follow"
	order_p = {"target": t, "offset": off, "head": head}
	hud.say("Following with offset", Color(1.0, 0.8, 0.3))


func order_lookat(t: Ship, pt: Vector3) -> void:
	order = "lookat"
	order_p = {"target": t, "point": pt}
	hud.say("Facing the point", Color(1.0, 0.8, 0.3))


func set_facing_lock(d: Vector3) -> void:
	if d.length() < 0.001:
		return
	facing = {"mode": "lock", "dir": d.normalized()}
	hud.say("Facing locked while moving", Color(1.0, 0.95, 0.75))


func lock_heading_now() -> void:
	set_facing_lock(player.forward())


func set_facing_point(t: Ship, pt: Vector3) -> void:
	facing = {"mode": "point", "ship": t, "point": pt}
	hud.say("Facing the point while moving", Color(1.0, 0.95, 0.75))


func set_facing_auto() -> void:
	facing = {"mode": "auto"}
	hud.say("Facing: along the travel direction", Color(1.0, 0.95, 0.75))


func facing_point() -> Vector3:
	var t = facing.get("ship")
	if t != null and is_instance_valid(t):
		return t.global_position
	return facing.get("point", Vector3.ZERO)


func lookat_point(p: Dictionary) -> Vector3:
	var t = p.get("target")
	if t != null and is_instance_valid(t):
		return t.global_position
	return p.get("point", Vector3.ZERO)


func orbit_center(p: Dictionary) -> Vector3:
	var t = p.get("target")
	var c: Vector3 = p["center"]
	if t != null and is_instance_valid(t):
		c = t.global_position
	return c + Vector3(0, float(p["alt"]), 0)


func has_order_viz() -> bool:
	return order in ["goto", "route", "orbit", "chase", "follow", "lookat", "hold"] or facing["mode"] != "auto"


func order_text() -> String:
	match order:
		"none":
			return "manual control"
		"brake":
			return "brake"
		"hold":
			return "hold position"
		"goto":
			return "drive to point  (%s)" % WaypointViz.fmt_dist(wp_dist())
		"route":
			return "route  (point %d of %d)" % [int(order_p.get("idx", 0)) + 1, (order_p.get("points", []) as Array).size()]
		"chase":
			return "drive to ship, keep %s" % WaypointViz.fmt_dist(float(order_p.get("dist", 0.0)))
		"orbit":
			var tilt := int(rad_to_deg(acos(clampf((order_p.get("normal", Vector3.UP) as Vector3).dot(Vector3.UP), -1.0, 1.0))))
			return "orbit, radius %s, tilt %d deg" % [WaypointViz.fmt_dist(float(order_p.get("radius", 0.0))), tilt]
		"follow":
			return "follow with offset"
		"lookat":
			return "face a point"
	return order


func facing_text() -> String:
	match facing["mode"]:
		"lock":
			var d: Vector3 = facing["dir"]
			return "locked  HDG %03d  PIT %+d" % [int(fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)), int(rad_to_deg(asin(clampf(d.y, -1, 1))))]
		"point":
			return "looking at a point"
	return "auto (travel direction)"


## The ship nearest to the cursor ray (used by the tuning modes to pick a target).
func pick_ship(mp: Vector2) -> Ship:
	var cam := rig.cam
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var best: Ship = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("ships"):
		var s := n as Ship
		if s == player or not s.alive:
			continue
		var rel := s.global_position - o
		var t := rel.dot(d)
		if t < 0.0:
			continue
		var perp := (rel - d * t).length()
		var tol := maxf(float(s.stats["longest"]) * 0.7, 6.0 + t * 0.012)
		if perp < tol and perp < bd:
			bd = perp
			best = s
	return best


func weapon_units() -> Array:
	return player.weapon_units() if player != null and is_instance_valid(player) else []


func _weapon_ref_target() -> Ship:
	var t = player.target
	if t != null and is_instance_valid(t) and t.alive:
		return t
	var best: Ship = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("ships"):
		var o := n as Ship
		if o == player or not o.alive or o.team == player.team:
			continue
		var d := player.global_position.distance_to(o.global_position)
		if d < bd:
			bd = d
			best = o
	return best


## Quick selections for the turret list: all, none, invert, kinetic/laser/missile, best, arc, idle, online.
func select_weapons(kind: String) -> void:
	var units := weapon_units()
	var out: Array = []
	var ref := _weapon_ref_target()
	var best_score := 0.0
	var scores := {}
	if kind == "best":
		for u in units:
			var sc := 0.0
			if u["online"] and (int(u["ammo"]) != 0 or int(u["barrel_count"]) > 0):
				sc = float(u["dps"])
				if ref != null and not player.unit_can_hit(u, ref):
					sc = 0.0
			scores[u["id"]] = sc
			best_score = maxf(best_score, sc)
	for u in units:
		var pick := false
		match kind:
			"all":
				pick = true
			"invert":
				pick = not sel_weapons.has(u["id"])
			"kinetic", "laser", "missile":
				pick = (u["kinds"] as Array).has(kind)
			"online":
				pick = bool(u["online"])
			"idle":
				pick = String(u["tmode"]) == "main"
			"arc":
				pick = ref != null and bool(u["online"]) and player.unit_can_hit(u, ref)
			"best":
				pick = best_score > 0.0 and float(scores[u["id"]]) >= best_score * 0.7
		if pick:
			out.append(u["id"])
	sel_weapons = out
	hud.refresh_weapons()
	if kind == "best" and out.is_empty():
		hud.say("No turret can hit a target right now", Color(1, 0.8, 0.3))


## Point the selected turrets at a ship ("ship"), back to the locked target ("main") or at the cursor ("cursor").
func assign_weapons(t: Ship, mode: String) -> void:
	var n := 0
	for u in weapon_units():
		if not sel_weapons.has(u["id"]):
			continue
		for bid in u["barrels"]:
			var m: Dictionary = player.by_id[int(bid)]
			m["tmode"] = mode
			m["tgt"] = t if mode == "ship" else null
		n += 1
	if n == 0:
		hud.say("Select some turrets first", Color(1, 0.8, 0.3))
		return
	match mode:
		"ship":
			hud.say("%d turret(s) -> %s" % [n, t.name], Color(1.0, 0.8, 0.3))
		"cursor":
			hud.say("%d turret(s) follow the cursor" % n, Color(1.0, 0.8, 0.3))
		_:
			hud.say("%d turret(s) follow the locked target" % n, Color(1.0, 0.8, 0.3))
	hud.refresh_weapons()


func assign_nearest() -> void:
	var t := _weapon_ref_target()
	if t == null:
		hud.say("No enemy to target", Color(1, 0.8, 0.3))
		return
	assign_weapons(t, "ship")


func weapon_unit_text(u: Dictionary) -> String:
	var kinds := ""
	for k in u["kinds"]:
		kinds += String(k).substr(0, 3).to_upper() + " "
	var tgt := "lock"
	match String(u["tmode"]):
		"cursor":
			tgt = "cursor"
		"ship":
			var t = u["tgt"]
			if t != null and is_instance_valid(t) and t.alive:
				tgt = "%s %dm" % [t.name, int(player.global_position.distance_to(t.global_position))]
			else:
				tgt = "lock (target lost)"
	var ammo := "" if int(u["ammo"]) <= 0 and not (u["kinds"] as Array).has("missile") else "  ammo %d" % int(u["ammo"])
	return "%s  %dx %s dps %d%s  ->  %s%s" % [u["label"], int(u["barrel_count"]), kinds, int(u["dps"]), ammo, tgt, "" if u["online"] else "  OFFLINE"]


func has_weapon_viz() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not sel_weapons.is_empty():
		return true
	for u in weapon_units():
		if String(u["tmode"]) != "main":
			return true
	return false


func lock_target() -> void:
	var best: Ship = null
	var bd := deg_to_rad(10.0)
	var ro := rig.cam.global_position
	var rd := -rig.cam.global_transform.basis.z
	if not rig.first_person and not free_cursor_on():
		pass
	for s in get_tree().get_nodes_in_group("ships"):
		var o := s as Ship
		if o == player or not o.alive or o.team == player.team:
			continue
		var a := rd.angle_to(o.global_position - ro)
		if a < bd:
			bd = a
			best = o
	if best == null:
		var dmin := INF
		for s in get_tree().get_nodes_in_group("ships"):
			var o := s as Ship
			if o != player and o.alive and o.team != player.team:
				var d := player.global_position.distance_to(o.global_position)
				if d < dmin:
					dmin = d
					best = o
	player.target = best
	if best:
		hud.say("Target locked: %s" % best.name, Color(1, 0.9, 0.4))


func clear_lock() -> void:
	player.target = null


func free_cursor_on() -> bool:
	return free_cursor or not rig.first_person


func _apply_mouse_mode() -> void:
	var capture := rig.first_person and not free_cursor and not paused and player != null and player.alive
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


func set_paused(on: bool) -> void:
	paused = on
	get_tree().paused = on
	hud.show_pause(on)
	_apply_mouse_mode()


func leave() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.goto_scene(String(Game.session.get("return_scene", "res://scenes/main_menu.tscn")))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if tuner.active:
			tuner.cancel()
			return
		set_paused(not paused)
		return
	if paused or player == null:
		return
	rig.unhandled(event)
	if tuner.handle(event):
		return
	if rig.map_mode and _map_input(event):
		return
	if event is InputEventMouseMotion and rig.first_person and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += event.relative
	if event.is_action_pressed("toggle_view"):
		if player.alive and not rig.cp_view_empty_check():
			rig.first_person = not rig.first_person
			_apply_mouse_mode()
	elif event.is_action_pressed("free_cursor"):
		free_cursor = not free_cursor
		_apply_mouse_mode()
	elif event.is_action_pressed("toggle_assist"):
		player.assist = not player.assist
		hud.say("Flight: %s" % ("ASSISTED" if player.assist else "MANUAL"), Color(0.7, 0.9, 1))
	elif event.is_action_pressed("lock_target"):
		lock_target()
	elif event.is_action_pressed("tactical_map"):
		set_map_mode(not rig.map_mode)
	elif event.is_action_pressed("go_cursor"):
		_go_to_cursor()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and test_shot_on and not rig.map_mode and not hud.is_mouse_over_ui():
		_test_shot()


func _aim_ray() -> Dictionary:
	var cam := rig.cam
	var ro := cam.global_position
	var rd := -cam.global_transform.basis.z
	if not rig.first_person:
		var mp := get_viewport().get_mouse_position()
		ro = cam.project_ray_origin(mp)
		rd = cam.project_ray_normal(mp)
	return {"o": ro, "d": rd}


func _test_shot() -> void:
	var r := _aim_ray()
	var o: Vector3 = r["o"]
	var d: Vector3 = r["d"]
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 3000.0, 1)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty() or res["collider"] != player:
		hud.say("Click on your own hull", Color(1, 0.8, 0.3))
		return
	var hit: Vector3 = res["position"]
	var fake := {"size": [0.6, 0.6, 3.0], "dir": 0, "weapon": test_shot_weapon}
	var ws := ShipData.weapon_stats(fake)
	if test_shot_weapon == "laser":
		Projectile.fire_laser(self, null, ws, hit - d * 30.0, d)
	else:
		Projectile.spawn(self, null, ws, hit - d * 30.0, d, Vector3.ZERO, null)
	hud.log_msg("[color=gray]Test %s round fired at your hull[/color]" % test_shot_weapon)


func _arrived_at(dest: Vector3) -> bool:
	return player.global_position.distance_to(dest) < maxf(12.0, float(player.stats["longest"]) * 0.5) and player.linear_velocity.length() < 10.0


func _finish_at(dest: Vector3, end_dir: Vector3, msg: String) -> void:
	order = "hold"
	order_p = {"pos": dest}
	if end_dir.length() > 0.1:
		order_p["face"] = end_dir
	hud.say(msg, Color(0.5, 1.0, 0.6))


## Turns the active movement order into a flight command for this frame.
func _order_cmd() -> Dictionary:
	var sl := hud.speed_limit
	var cmd := Autopilot.hold(player)
	match order:
		"hold":
			var hp: Vector3 = order_p.get("pos", player.global_position)
			cmd = Autopilot.follow(player, hp, Vector3.ZERO, minf(sl, 80.0))
			var hf: Vector3 = order_p.get("face", Vector3.ZERO)
			if hf.length() > 0.1:
				cmd["face"] = hf
		"brake":
			cmd = {"brake": true}
		"goto":
			if has_wp:
				if _arrived_at(waypoint):
					_finish_at(waypoint, order_p.get("end_dir", Vector3.ZERO), "Point reached")
				else:
					cmd = Autopilot.go_to(player, waypoint, sl)
		"route":
			var pts: Array = order_p["points"]
			var idx := int(order_p["idx"])
			var dest: Vector3 = pts[idx]
			waypoint = dest
			has_wp = true
			if idx >= pts.size() - 1:
				if _arrived_at(dest):
					_finish_at(dest, order_p.get("end_dir", Vector3.ZERO), "Route finished")
				else:
					cmd = Autopilot.go_to(player, dest, sl)
			else:
				if player.global_position.distance_to(dest) < maxf(40.0, float(player.stats["longest"])):
					order_p["idx"] = idx + 1
				cmd = Autopilot.pass_through(player, dest, sl)
		"chase":
			var t = order_p.get("target")
			if t != null and is_instance_valid(t) and t.alive:
				var tp: Vector3 = t.global_position
				var away: Vector3 = player.global_position - tp
				if away.length() < 0.1:
					away = Vector3.BACK
				cmd = Autopilot.follow(player, tp + away.normalized() * float(order_p["dist"]), t.linear_velocity, sl)
				cmd["face"] = (tp - player.global_position).normalized()
			else:
				order_hold()
				hud.say("Target lost - holding", Color(1, 0.8, 0.3))
		"follow":
			var lt = order_p.get("target")
			if lt != null and is_instance_valid(lt) and lt.alive:
				var dst: Vector3 = lt.to_global(order_p["offset"])
				cmd = Autopilot.follow(player, dst, lt.linear_velocity, sl)
				var hl: Vector3 = order_p.get("head", Vector3.ZERO)
				cmd["face"] = ((lt.global_transform.basis * hl).normalized() if hl.length() > 0.1 else lt.forward())
			else:
				order_hold()
				hud.say("Leader lost - holding", Color(1, 0.8, 0.3))
		"orbit":
			var ot = order_p.get("target")
			var tv := Vector3.ZERO
			if ot != null and is_instance_valid(ot) and ot.alive:
				order_p["center"] = ot.global_position
				tv = ot.linear_velocity
			cmd = Autopilot.orbit(player, orbit_center(order_p), float(order_p["radius"]), minf(sl, 80.0), float(order_p["dir"]), tv, order_p.get("normal", Vector3.UP))
		"lookat":
			cmd = Autopilot.face(player, lookat_point(order_p))
	return cmd


## Facing-while-moving: overrides the travel-direction facing of an automatic order.
func _apply_facing(cmd: Dictionary) -> void:
	if not cmd.get("auto", false) or order == "lookat" or (order == "hold" and order_p.has("face")):
		return
	match facing["mode"]:
		"lock":
			cmd["face"] = facing["dir"]
		"point":
			var d := facing_point() - player.global_position
			if d.length() > 0.1:
				cmd["face"] = d.normalized()


func _physics_process(delta: float) -> void:
	_t += delta
	for b in bots:
		b.update(delta)
	if mode == "freematch" and respawn_t > 0.0 and player != null and not player.alive:
		respawn_t -= delta
		hud.respawn_lbl.text = "Ship destroyed. Respawn in %d s" % ceili(maxf(respawn_t, 0.0)) if respawn_t > 0.0 else "Ready - pick a ship and respawn"
		if respawn_t <= 0.0:
			respawn_t = 0.0001
	if player == null or not player.alive or paused:
		_mouse = Vector2.ZERO
		return
	var mv := Vector3(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("thrust_down", "thrust_up"), Input.get_axis("thrust_back", "thrust_fwd"))
	var rot := Vector3(Input.get_axis("pitch_down", "pitch_up"), Input.get_axis("yaw_right", "yaw_left"), Input.get_axis("roll_right", "roll_left"))
	var k := float(Game.settings["mouse_sens"]) * 20.0
	rot += Vector3(-_mouse.y * k, -_mouse.x * k, 0.0)
	rot = Vector3(clampf(rot.x, -1, 1), clampf(rot.y, -1, 1), clampf(rot.z, -1, 1))
	_mouse = Vector2.ZERO
	var manual := mv != Vector3.ZERO or rot != Vector3.ZERO
	var cmd := {}
	var tgt := player.target
	var has_tgt := tgt != null and is_instance_valid(tgt) and tgt.alive
	var lp = tuner.look_point()
	if manual or (order == "none" and lp == null):
		cmd = {"move": mv, "rot": rot, "speed_limit": hud.speed_limit}
		if manual:
			order = "none"
			order_p = {}
	elif lp != null:
		cmd = Autopilot.face(player, lp)
	else:
		cmd = _order_cmd()
		_apply_facing(cmd)
	if Input.is_action_pressed("brake"):
		cmd["brake"] = true
	cmd["fire"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not rig.map_mode and not test_shot_on and not hud.is_mouse_over_ui() and (rig.first_person or free_cursor_on())
	var ar := _aim_ray()
	var o: Vector3 = ar["o"]
	var d: Vector3 = ar["d"]
	var hit := Projectile.trace(get_tree(), get_world_3d(), o, o + d * 4000.0, player)
	cmd["aim_point"] = (hit["pos"] as Vector3) if not hit.is_empty() else o + d * 2000.0
	if has_tgt:
		cmd["aim_target"] = tgt
	player.cmd = cmd
