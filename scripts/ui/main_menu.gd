extends Node3D
## Main menu (GDD section 5): Multiplayer, SinglePlayer, Creation, Plus - each extends a line of options.

var ui: CanvasLayer
var opt_row: HBoxContainer
var detail: VBoxContainer
var spin: Node3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.33, 0.45)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 35, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 6, 34)
	add_child(cam)
	spin = Node3D.new()
	add_child(spin)
	var bp := Premades.dart()
	var mi := MeshInstance3D.new()
	mi.mesh = ShipData.build_hull_mesh(bp["rings"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ShipData.col(bp["color"])
	mat.metallic = 0.6
	mat.roughness = 0.4
	mi.material_override = mat
	spin.add_child(mi)
	spin.position = Vector3(11, 0, 0)
	ui = CanvasLayer.new()
	add_child(ui)
	_build()


func _process(delta: float) -> void:
	spin.rotate_y(delta * 0.35)


func _btn(text: String, parent: Control, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(190, 34)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build() -> void:
	var root := VBoxContainer.new()
	root.position = Vector2(60, 60)
	root.add_theme_constant_override("separation", 10)
	ui.add_child(root)
	var title := Label.new()
	title.text = "FORGE THY DOCTRINE"
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)
	var sub := Label.new()
	sub.text = "Instrument of Ege  -  prototype"
	root.add_child(sub)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	root.add_child(main)
	for e in ["Multiplayer", "SinglePlayer", "Creation", "Plus"]:
		var ee: String = e
		_btn(ee, main, func(): _open(ee))
	opt_row = HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 12)
	root.add_child(opt_row)
	detail = VBoxContainer.new()
	detail.add_theme_constant_override("separation", 6)
	root.add_child(detail)
	_open("SinglePlayer")


func _clear(c: Control) -> void:
	for x in c.get_children():
		x.queue_free()


func _open(entry: String) -> void:
	_clear(opt_row)
	_clear(detail)
	match entry:
		"Multiplayer":
			_btn("Host", opt_row, func(): pass, true)
			_btn("Join", opt_row, func(): pass, true)
			_note("Peer-to-peer lobbies are roadmap step 4 and are not in this prototype.")
		"SinglePlayer":
			_btn("Campaign", opt_row, func(): pass, true)
			_btn("Freematch", opt_row, func(): _freematch_cfg())
			_btn("Tutorial", opt_row, func(): _sandbox_cfg(true))
			_btn("Sandbox", opt_row, func(): _sandbox_cfg(false))
			_note("Campaign: not available (as in the design doc).")
		"Creation":
			_btn("Ship creation", opt_row, func(): _open_editor())
			_btn("Module creation", opt_row, func(): pass, true)
			_btn("Download creation", opt_row, func(): pass, true)
			_note("Ships are JSON files in: %s" % ProjectSettings.globalize_path(Game.USER_SHIPS))
		"Plus":
			_btn("Options", opt_row, func(): _options())
			_btn("Credits", opt_row, func(): _credits())
			_btn("Quit", opt_row, func(): get_tree().quit())


func _note(t: String) -> void:
	var l := Label.new()
	l.text = t
	detail.add_child(l)


func _ship_picker() -> OptionButton:
	var pick := OptionButton.new()
	for s in Game.all_ships():
		pick.add_item("%s  (%s)" % [s["name"], s["source"]])
	detail.add_child(pick)
	return pick


func _sandbox_cfg(tut: bool) -> void:
	_clear(detail)
	_note("Choose your ship")
	var pick := _ship_picker()
	_btn("Start", detail, func():
		var ships := Game.all_ships()
		Game.session = {"mode": "sandbox", "ship": ships[pick.selected]["bp"], "return_scene": "res://scenes/main_menu.tscn", "tutorial": tut}
		Game.goto_scene("res://scenes/arena.tscn"))


func _freematch_cfg() -> void:
	_clear(detail)
	_note("Freematch: team deathmatch against bots")
	var pick := _ship_picker()
	var a := SpinBox.new()
	a.min_value = 0
	a.max_value = 4
	a.value = 1
	var e := SpinBox.new()
	e.min_value = 1
	e.max_value = 6
	e.value = 2
	var k := SpinBox.new()
	k.min_value = 3
	k.max_value = 50
	k.value = 10
	for pair in [["Allied bots", a], ["Enemy bots", e], ["Kills to win", k]]:
		var hb := HBoxContainer.new()
		var l := Label.new()
		l.text = pair[0]
		l.custom_minimum_size = Vector2(120, 0)
		hb.add_child(l)
		hb.add_child(pair[1])
		detail.add_child(hb)
	_btn("Start match", detail, func():
		var ships := Game.all_ships()
		Game.session = {"mode": "freematch", "ship": ships[pick.selected]["bp"], "return_scene": "res://scenes/main_menu.tscn", "bots_ally": int(a.value), "bots_enemy": int(e.value), "kill_limit": int(k.value)}
		Game.goto_scene("res://scenes/arena.tscn"))


func _open_editor() -> void:
	Game.editing_bp = {}
	Game.goto_scene("res://scenes/ship_editor.tscn")


func _options() -> void:
	_clear(detail)
	var ck := CheckButton.new()
	ck.text = "Assisted flight by default"
	ck.button_pressed = Game.settings["assist"]
	ck.toggled.connect(func(on: bool): Game.settings["assist"] = on)
	detail.add_child(ck)
	var cs := CheckButton.new()
	cs.text = "Camera shake on hits"
	cs.button_pressed = Game.settings["shake"]
	cs.toggled.connect(func(on: bool): Game.settings["shake"] = on)
	detail.add_child(cs)
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = "Mouse sensitivity (first person)"
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0005
	sl.max_value = 0.006
	sl.step = 0.0001
	sl.value = Game.settings["mouse_sens"]
	sl.custom_minimum_size = Vector2(200, 20)
	sl.value_changed.connect(func(v: float): Game.settings["mouse_sens"] = v)
	hb.add_child(sl)
	detail.add_child(hb)
	_note("Graphics/audio/key rebinding: roadmap.")


func _credits() -> void:
	_clear(detail)
	_note("Design: Forge Thy Doctrine GDD (docs/Forge_Thy_Doctrine.md)")
	_note("Prototype built with Godot 4.4 + AI assistance.")
