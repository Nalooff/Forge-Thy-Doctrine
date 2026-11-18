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
var scores := [0, 0]
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


func _ready() -> void:
	var s: Dictionary = Game.session
	mode = String(s.get("mode", "sandbox"))
	player_bp = s.get("ship", Premades.dart())
	kill_limit = int(s.get("kill_limit", 10))
	_tutorial = bool(s.get("tutorial", false))
	_build_world()
	rig = CamRig.new()
	add_child(rig)
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
	hud.say("Mode: %s" % ("Test Range" if mode == "sandbox" else "Freematch - Team Deathmatch"), Color(0.6, 1.0, 0.8))


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


func _start_freematch() -> void:
	var ally := int(Game.session.get("bots_ally", 1))
	var enemy := int(Game.session.get("bots_enemy", 2))
	_spawn_player(Vector3(0, 0, 1300), Vector3(0, 0, -1))
	var lib: Array = Premades.all()
	for i in ally:
		_spawn_bot(0, lib)
	for i in enemy:
		_spawn_bot(1, lib)
	hud.log_msg("[b]Team Deathmatch[/b]: first team to %d kills wins." % kill_limit)


func _spawn_bot(team: int, lib: Array) -> void:
	var bp: Dictionary = lib[randi() % lib.size()]
	var z := 1300.0 if team == 0 else -1300.0
	var pos := Vector3(randf_range(-250, 250), randf_range(-60, 60), z + randf_range(-150, 150))
	var s := _spawn_ship(bp, team, pos, Vector3(0, 0, -1.0 if team == 0 else 1.0))
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


func _on_died(s: Ship, k: Ship) -> void:
	var who := "%s" % s.name
	if k != null:
		who += " destroyed by %s" % k.name
	hud.log_msg("[color=yellow]%s[/color]" % who)
	if s == player:
		hud.say("YOUR SHIP WAS DESTROYED", Color(1, 0.3, 0.3))
		rig.first_person = false
		_apply_mouse_mode()
		if mode == "freematch" and not match_over:
			respawn_t = 3.0 + float(s.stats["longest"]) / 10.0
			hud.show_respawn(true, Game.all_ships())
	if mode == "freematch" and not match_over:
		var killer_team := -1
		if k != null and k.team != s.team:
			killer_team = k.team
		elif k == null or k == s:
			killer_team = 1 - s.team
		if killer_team >= 0 and killer_team < 2:
			scores[killer_team] += 1
		if scores[0] >= kill_limit or scores[1] >= kill_limit:
			match_over = true
			var win: bool = scores[0] >= kill_limit
			hud.say("VICTORY" if win else "DEFEAT", Color(0.5, 1, 0.5) if win else Color(1, 0.4, 0.4))
			hud.log_msg("Match over. Press ESC to leave.")
			return
		if s != player:
			var tm := s.team
			get_tree().create_timer(4.0 + float(s.stats["longest"]) / 12.0).timeout.connect(func():
				if not match_over:
					_spawn_bot(tm, Premades.all()))
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
	if mode == "freematch":
		return "Kills  You/Allies: %d   Enemies: %d   (limit %d)" % [scores[0], scores[1], kill_limit]
	return "Test range - no objectives."


# ------------------------------------------------------------------ controls
func set_assist(on: bool) -> void:
	if player:
		player.assist = on


func set_order(kind: String) -> void:
	order = kind
	if kind in ["face", "drive", "orbit"] and (player.target == null or not is_instance_valid(player.target) or not player.target.alive):
		lock_target()
		if player.target == null:
			hud.say("No target - nothing to %s" % kind, Color(1, 0.8, 0.3))
			order = "none"
	hud.say("Order: %s" % kind, Color(0.7, 0.9, 1))


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
		set_paused(not paused)
		return
	if paused or player == null:
		return
	rig.unhandled(event)
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
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and test_shot_on and not hud.is_mouse_over_ui():
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
	if manual or order == "none":
		cmd = {"move": mv, "rot": rot, "speed_limit": hud.speed_limit}
		if manual:
			order = "none"
	else:
		match order:
			"hold":
				cmd = Autopilot.hold(player)
			"brake":
				cmd = {"brake": true}
			"face":
				cmd = Autopilot.face(player, tgt.global_position) if has_tgt else Autopilot.hold(player)
			"drive":
				cmd = Autopilot.drive_toward(player, tgt.global_position, hud.speed_limit, 150.0) if has_tgt else Autopilot.hold(player)
			"orbit":
				cmd = Autopilot.orbit(player, tgt.global_position, 400.0, minf(hud.speed_limit, 80.0)) if has_tgt else Autopilot.hold(player)
	if Input.is_action_pressed("brake"):
		cmd["brake"] = true
	cmd["fire"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not test_shot_on and not hud.is_mouse_over_ui() and (rig.first_person or free_cursor_on())
	var ar := _aim_ray()
	var o: Vector3 = ar["o"]
	var d: Vector3 = ar["d"]
	var hit := Projectile.trace(get_tree(), get_world_3d(), o, o + d * 4000.0, player)
	cmd["aim_point"] = (hit["pos"] as Vector3) if not hit.is_empty() else o + d * 2000.0
	if has_tgt:
		cmd["aim_target"] = tgt
	player.cmd = cmd
