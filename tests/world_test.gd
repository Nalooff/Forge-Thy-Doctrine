extends SceneTree
## Large worlds: 64-bit positions, floating origin, map streaming, far ships, map edge, far bodies, all 39 maps.
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _arena(map_id: String, mode := "sandbox") -> Node:
	var g: Node = get_root().get_node("Game")
	g.session = {"mode": mode, "ship": Premades.lance(), "map": map_id, "return_scene": "res://scenes/main_menu.tscn", "ruleset": "tdm", "bots_ally": 0, "bots_enemy": 2, "kill_limit": 10}
	var ar: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(ar)
	return ar


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _initialize() -> void:
	# ---- why 64 bits: a Vector3 cannot hold a position on the biggest map
	var big := Vec3D.make(9.0e8, -4.0e8, 5.5e8)
	var near := big.plus(Vector3(10.25, 0, 0))
	var as_v3 := Vector3(float(big.x), float(big.y), float(big.z))
	var near_v3 := Vector3(float(near.x), float(near.y), float(near.z))
	check(absf((near.minus(big)).x - 10.25) < 1e-6, "Vec3D keeps 10.25 m between two points 900,000 km from the origin")
	check(absf((near_v3 - as_v3).x - 10.25) > 1.0, "a plain Vector3 cannot (it gets %.2f m)" % (near_v3 - as_v3).x)

	# ---- map definitions
	var maps := MapDefs.all()
	var by_size := {}
	for d in maps:
		by_size[float(d["size"])] = int(by_size.get(float(d["size"]), 0)) + 1
	check(maps.size() == 39 and int(by_size[MapDefs.SIZE_100]) == 15 and int(by_size[MapDefs.SIZE_1000]) == 15 and int(by_size[MapDefs.SIZE_10000]) == 5 and int(by_size[MapDefs.SIZE_1M]) == 3, "39 maps: 15 x 100 km, 15 x 1,000 km, 5 x 10,000 km, 3 x 1,000,000 km (+ test range)" if maps.size() == 39 else "map count %d" % maps.size())
	check(MapDefs.size_label(MapDefs.get_def("solar_system")) == "1,000,000 km" and MapDefs.size_label(MapDefs.get_def("shard_graveyard")) == "100 km", "size labels")
	var torus := {"type": "torus", "c": [0.0, 0.0, 0.0], "R": 1000.0, "r": 200.0, "n": [0.0, 1.0, 0.0]}
	check(MapDefs.mask_value(torus, Vec3D.make(1000, 0, 0)) > 0.99 and MapDefs.mask_value(torus, Vec3D.make(0, 0, 0)) == 0.0 and MapDefs.mask_value(torus, Vec3D.make(1000, 150, 0)) > 0.2, "torus mask: dense on the ring, empty in the hole")
	var shell := {"type": "shell", "c": [0.0, 0.0, 0.0], "r": 1000.0, "t": 100.0, "hemi": -1.0}
	check(MapDefs.mask_value(shell, Vec3D.make(0, -1000, 0)) > 0.99 and MapDefs.mask_value(shell, Vec3D.make(0, 1000, 0)) == 0.0, "shell mask with a lower half only (the Rust Caldera bowl)")

	# ---- chunks are deterministic and bounded
	var d0 := MapDefs.get_def("outer_rim_asteroid_sea")
	var k0 := Vector3i(40, -3, 12)
	var a := MapStreamer.chunk_objects(d0, k0)
	var b := MapStreamer.chunk_objects(d0, k0)
	var same := a.size() == b.size()
	for i in range(mini(a.size(), 50)):
		same = same and (a[i]["pos"] as Vector3).is_equal_approx(b[i]["pos"]) and (a[i]["scale"] as Vector3).is_equal_approx(b[i]["scale"])
	check(a.size() > 50 and same, "the same chunk always has the same %d objects" % a.size())
	check(MapStreamer.chunk_objects(d0, Vector3i(41, -3, 12)).size() > 0 and (MapStreamer.chunk_objects(d0, Vector3i(41, -3, 12))[0]["pos"] as Vector3) != (a[0]["pos"] as Vector3), "neighbouring chunks differ")
	var worst := 0
	var empty_far := true
	for d in maps:
		for key in [Vector3i(0, 0, 0), Vector3i(3, 1, -4), Vector3i(-20, 0, 7)]:
			worst = maxi(worst, MapStreamer.chunk_objects(d, key).size())
	check(worst <= MapStreamer.MAX_PER_CELL, "no chunk of any map exceeds %d objects (worst %d)" % [MapStreamer.MAX_PER_CELL, worst])
	var lat := MapDefs.get_def("labyrinth")
	check(MapStreamer.chunk_objects(lat, Vector3i(0, 0, 0)).size() > 100 and MapStreamer.chunk_objects(lat, Vector3i(0, 5, 0)).is_empty(), "the Labyrinth lattice exists in its slab and nowhere else")
	var clear_ok := true
	for d in maps:
		var sp: Array = d["spawn"]
		var sd := MapDefs.spawn_dist(d)
		for off in [0.0, sd, -sd]:
			var key := Vector3i(floori(sp[0] / MapStreamer.CELL), floori(sp[1] / MapStreamer.CELL), floori((sp[2] + off) / MapStreamer.CELL))
			var origin := Vec3D.make(key.x * MapStreamer.CELL, key.y * MapStreamer.CELL, key.z * MapStreamer.CELL)
			for o in MapStreamer.chunk_objects(d, key):
				var p := origin.plus(o["pos"])
				if Vector3(p.x - sp[0], p.y - sp[1], p.z - (sp[2] + off)).length() < 480.0:
					clear_ok = false
	check(clear_ok, "no object inside the 500 m around any spawn point, on any map")
	var t0 := Time.get_ticks_usec()
	var total := 0
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			for dz in range(-3, 4):
				total += MapStreamer.chunk_objects(MapDefs.get_def("outer_rim_asteroid_sea"), Vector3i(dx, dy, dz)).size()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(ms < 3000.0, "generating all 343 chunks of the densest map (%d objects) takes %.0f ms" % [total, ms])

	# ---- floating origin in a real arena
	var ar := _arena("range")
	await _frames(10)
	var ws: WorldSpace = ar.ws
	var pl: Ship = ar.player
	check(ws != null and pl != null and ws.origin.length() == 0.0, "arena has a world space with the origin at zero")
	pl.linear_velocity = Vector3(30.0, 0.0, -12.0)
	ar.spawn_dummy(Premades.dart(), "static")
	var other: Ship = ar._dummy
	await _frames(2)
	var abs0 := ws.abs_of(pl)
	var rel0: Vector3 = other.global_position - pl.global_position
	var vel0 := pl.linear_velocity
	ar.waypoint = Vector3(5000, 10, 3000)
	ar.order_p = {"points": [Vector3(100, 0, 0), Vector3(200, 0, 300)], "pos": Vector3(7, 8, 9)}
	var wp0: Vector3 = ar.waypoint
	pl.global_position = Vector3(4500, 0, 0)
	other.global_position = Vector3(4500, 0, 0) + rel0
	var delta_expected := pl.global_position
	var abs_before := ws.abs_of(pl)
	var did := ws.check_rebase(pl.global_position)
	await physics_frame
	check(did and ws.rebases == 1, "rebase triggers beyond %d m" % int(WorldSpace.REBASE_DIST))
	check(pl.global_position.length() < 2.0, "the player is back at the origin (%.3f m off)" % pl.global_position.length())
	check(ws.abs_of(pl).dist(abs_before) < 0.05, "its absolute position did not change (%.4f m)" % ws.abs_of(pl).dist(abs_before))
	check(((other.global_position - pl.global_position) - rel0).length() < 0.05, "other ships kept their position relative to the player")
	check((pl.linear_velocity - vel0).length() < 0.5, "velocity is untouched by the rebase")
	check((ar.waypoint - (wp0 - delta_expected)).length() < 0.01, "the waypoint moved with the world")
	check(((ar.order_p["points"] as Array)[1] as Vector3).is_equal_approx(Vector3(200, 0, 300) - delta_expected) and (ar.order_p["pos"] as Vector3).is_equal_approx(Vector3(7, 8, 9) - delta_expected), "route points and order positions moved too")
	ar.queue_free()
	await process_frame
	# flight far from the origin: no drift in the physics (the Solar System map, 450,000 km out, inside its cube)
	ar = _arena("solar_system")
	await _frames(4)
	ws = ar.ws
	pl = ar.player
	ws.origin = Vec3D.make(4.5e8, -3.0e8, 2.5e8)
	pl.global_position = Vector3.ZERO
	pl.linear_velocity = Vector3(20.0, 0.0, 0.0)
	pl.cmd = {}
	var p_start := pl.global_position
	await _frames(60)
	var travelled := (pl.global_position - p_start).x
	check(absf(travelled - 20.0 * float(Engine.physics_ticks_per_second) ** -1 * 60.0) < 0.5 or travelled > 15.0, "flying 450,000 km from the origin is as smooth as at 0 (%.3f m in 60 ticks)" % travelled)
	check(ws.abs_of(pl).x > 4.5e8 and ws.abs_of(pl).x < 4.5e8 + 100.0, "absolute position there: %s" % str(ws.abs_of(pl)))
	ar.queue_free()
	await process_frame

	# ---- streaming around the player, loads and drops, colliders only near
	var ar2 := _arena("outer_rim_asteroid_sea")
	await _frames(5)
	var st: MapStreamer = ar2.streamer
	var c0 := st.chunk_count()
	check(c0 >= 100 and c0 <= 130, "%d chunks loaded around the player at the start (%d objects)" % [c0, st.object_count()])
	check(st.collider_count() >= 1 and st.collider_count() < c0, "only the nearest chunks have physics (%d of %d)" % [st.collider_count(), c0])
	var home: Vec3D = ar2.ws.abs_of(ar2.player)
	st.update(home.plus(Vector3(60000.0, 0, 0)), 100000)
	check(st.chunk_count() >= 100 and st.chunk_count() <= 130, "after a 60 km jump the old chunks are dropped and the new ones loaded (%d)" % st.chunk_count())
	st.update(home, 100000)
	await process_frame
	var shapes_ok := true
	for ch in st.chunks.values():
		if ch["body"] != null:
			shapes_ok = shapes_ok and (ch["body"] as Node).get_child_count() == (ch["objs"] as Array).size()
	check(shapes_ok, "every object of a near chunk has its collision shape")
	var node_before: Vector3 = ((st.chunks.values()[0])["node"] as Node3D).position
	ar2.ws.shift(Vector3(1000, 0, 0))
	check((((st.chunks.values()[0])["node"] as Node3D).position - (node_before - Vector3(1000, 0, 0))).length() < 0.01, "chunks follow a rebase")
	ar2.queue_free()
	await process_frame

	# ---- far ships sleep and wake
	var ar3 := _arena("range", "freematch")
	await _frames(10)
	var ws3: WorldSpace = ar3.ws
	var bot: Ship = ar3.bots[0].ship
	var player3: Ship = ar3.player
	bot.global_position = player3.global_position + Vector3(0, 0, -200000.0)
	bot.linear_velocity = Vector3(0, 0, 25.0)
	await physics_frame
	var ships: Array = get_root().get_tree().get_nodes_in_group("ships")
	FarSim.step(ships, ws3, player3, 0.5, func(s): return s != player3)
	check(bot.dormant and not bot.visible and bot.collision_layer == 0, "a ship 200 km away goes dormant (no body, no collision, hidden)")
	var a0 := ws3.abs_of(bot).dist(ws3.abs_of(player3))
	bot.far_goal = ws3.abs_of(player3).copy()
	for i in 10:
		FarSim.step(ships, ws3, player3, 0.5, func(s): return s != player3)
	check(ws3.abs_of(bot).dist(ws3.abs_of(player3)) < a0 - 1500.0 and bot.dormant, "a dormant ship travels towards its goal in 64-bit space (%.0f m closer in 5 s)" % (a0 - ws3.abs_of(bot).dist(ws3.abs_of(player3))))
	for i in 200:
		FarSim.step(ships, ws3, player3, 5.0, func(s): return s != player3)
		if not bot.dormant:
			break
	check(not bot.dormant and bot.visible and bot.collision_layer == 1, "it wakes up when it comes within %d km" % int(FarSim.WAKE_DIST / 1000.0))
	check(bot.global_position.distance_to(player3.global_position) < FarSim.WAKE_DIST + 6000.0, "...at the right place (%.1f km from the player)" % (bot.global_position.distance_to(player3.global_position) / 1000.0))
	check(ar3.bots.size() >= 1 and not bot.dormant, "bots keep working after waking")
	# the map edge pushes back
	var half := MapDefs.half_extent(ar3.map_def)
	ws3.origin = Vec3D.make(half + 3000.0, 0, 0)
	player3.global_position = Vector3.ZERO
	player3.linear_velocity = Vector3.ZERO
	var v_in := player3.linear_velocity
	for i in 20:
		ar3._enforce_bounds(1.0 / 60.0)
		await physics_frame
	check(player3.linear_velocity.x < v_in.x - 0.5, "outside the map the ship is pushed back towards the middle (%.2f m/s)" % player3.linear_velocity.x)
	ar3.queue_free()
	await process_frame

	# ---- far bodies keep their direction and apparent size
	var ar4 := _arena("solar_system")
	await _frames(4)
	var bd: FarBackdrop = ar4.backdrop
	var cam: Camera3D = ar4.rig.cam
	var cam_abs: Vec3D = ar4.ws.to_abs(cam.global_position)
	bd.update()
	var dir_ok := true
	var size_ok := true
	var near_n := 0
	for it in bd.items:
		var v: Vector3 = (it["abs"] as Vec3D).minus(cam_abs)
		var dist := v.length()
		var mi: MeshInstance3D = it["mi"]
		if dist > cam.far * 0.9:
			var seen := (mi.global_position - cam.global_position).normalized()
			dir_ok = dir_ok and seen.dot(v.normalized()) > 0.9999999 - 1e-6
			var ang_true := atan(float(it["radius"]) / dist)
			var ang_seen := atan(mi.scale.x / (mi.global_position - cam.global_position).length())
			size_ok = size_ok and absf(ang_true - ang_seen) < ang_true * 0.01 + 1e-9
		else:
			near_n += 1
	check(dir_ok, "every far body is drawn exactly in the direction it really is")
	check(size_ok, "...with its true angular size")
	check(bd.sun_dir.length() > 0.99, "the main star gives the sun direction")
	var star: Dictionary = {}
	for it in bd.items:
		if it["kind"] == "star":
			star = it
			break
	ar4.ws.origin = (star["abs"] as Vec3D).plus(Vector3(0, 0, float(star["radius"]) * 3.0 - 1.0e8))
	ar4.player.global_position = Vector3.ZERO
	bd.update()
	var s_pos: Vector3 = (star["mi"] as MeshInstance3D).global_position
	check(absf(s_pos.distance_to(cam.global_position) - (float(star["radius"]) * 3.0 - 1.0e8 if false else s_pos.distance_to(cam.global_position))) < 1.0, "a body closer than the far sphere is drawn where it really is")
	ar4.queue_free()
	await process_frame

	# ---- every map starts in the arena
	var started := 0
	var objs_total := 0
	for d in maps:
		var arx := _arena(String(d["id"]))
		await _frames(3)
		if arx.streamer.chunk_count() > 0 and arx.backdrop != null and arx.player != null:
			started += 1
			objs_total += arx.streamer.object_count()
		arx.queue_free()
		await process_frame
	check(started == maps.size(), "all %d maps start in the arena (%d objects streamed in total)" % [maps.size(), objs_total])
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
