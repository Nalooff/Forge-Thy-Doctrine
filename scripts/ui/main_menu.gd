extends Node3D
## Main menu: four buttons in a vertical list; pressing one draws a connector line to the entries it gives
## access to (Multi Player -> Join / Host, ...). The big spinning ship on the right is the last loaded ship.

const MAIN := ["Multi Player", "Single Player", "Creation", "Other"]
const TREE := {
	"Multi Player": ["Join", "Host"],
	"Single Player": ["Campaign", "Freematch", "Tutorial", "Sandbox"],
	"Creation": ["Ship creation", "Module creation", "Download creation"],
	"Other": ["Options", "Credits", "Quit"],
}
const BTN_X := 70.0
const BTN_W := 270.0
const BTN_H := 68.0
const OPT_X := 480.0
const OPT_W := 250.0
const OPT_H := 58.0
const RED := Color(0.62, 0.06, 0.1)

var ui: CanvasLayer
var root: Control
var lines: LineTree
var opt_nodes: Array = []
var main_btns: Array = []
var active := ""
var detail: Hud.ConsolePanel
var font_i: Font


class LineTree extends Control:
	var segs: Array = []     # [Vector2 a, Vector2 b]
	var t := 0.0

	func _draw() -> void:
		for sgm in segs:
			var a: Vector2 = sgm[0]
			var b: Vector2 = sgm[1]
			var e := a.lerp(b, t)
			draw_line(a, e, Color(0, 0, 0, 0.9), 9.0)
		for sgm in segs:
			var a2: Vector2 = sgm[0]
			var b2: Vector2 = sgm[1]
			draw_line(a2, a2.lerp(b2, t), RED, 5.0)


class HullPreview extends Control:
	var vp: SubViewport
	var holder: Node3D
	var cam: Camera3D
	var spin_speed := 0.5
	var longest := 10.0

	func setup(bp: Dictionary) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		svc.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(svc)
		vp = SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		svc.add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.55, 0.5)
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-35, 35, 0)
		vp.add_child(sun)
		holder = Node3D.new()
		vp.add_child(holder)
		cam = Camera3D.new()
		cam.fov = 34.0
		vp.add_child(cam)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ShipData.col(bp["color"])
		mat.metallic = 0.5
		mat.roughness = 0.5
		var mi := MeshInstance3D.new()
		mi.mesh = ShipData.build_hull_mesh(bp["rings"])
		mi.material_override = mat
		holder.add_child(mi)
		for m in bp["modules"]:
			if ShipData.MODULES[m["type"]]["kind"] != "external":
				continue
			var bm := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = ShipData.v3(m["size"])
			bm.mesh = box
			var mm := StandardMaterial3D.new()
			mm.albedo_color = ShipData.MODULES[m["type"]]["color"].darkened(0.3)
			bm.material_override = mm
			bm.position = ShipData.v3(m["pos"])
			holder.add_child(bm)
		var b := ShipData.hull_bounds(bp["rings"])
		longest = maxf(b.size.x, maxf(b.size.y, maxf(b.size.z, 1.0)))
		holder.position = -b.get_center()
		cam.look_at_from_position(Vector3(0, longest * 0.45, longest * 1.9), Vector3.ZERO, Vector3.UP)

	func _process(delta: float) -> void:
		if holder:
			holder.rotate_y(delta * spin_speed)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	font_i = UiStyle.display_font(800)
	_build_world()
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Hud.make_theme()
	ui.add_child(root)
	_build_ui()


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
	vec3 col = vec3(0.012,0.006,0.006) + vec3(0.05,0.012,0.006) * pow(max(0.0, d.x*0.6+d.y*0.3), 3.0);
	vec3 g = floor(d*520.0);
	col += vec3(step(0.9988, hash(g)) * (0.4 + 0.6*hash(g+7.1)));
	COLOR = col;
}
"""
	sm.shader = sh
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.3, 0.28)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 35, 0)
	sun.light_color = Color(1.0, 0.8, 0.65)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5, 36)
	add_child(cam)


func _outlined_label(text: String, size: int, pos: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", font_i)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 8)
	root.add_child(l)
	return l


func _box_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.8)
	sb.shadow_size = 3
	return sb


func _menu_button(text: String, pos: Vector2, size: Vector2, border: Color, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.add_theme_font_override("font", font_i)
	b.add_theme_font_size_override("font_size", 22 if size.x > 260.0 else 18)
	b.add_theme_color_override("font_color", Hud.EMBER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.02, 0.01))
	b.add_theme_stylebox_override("normal", _box_style(Color(0.07, 0.05, 0.05, 0.92), border, 4))
	b.add_theme_stylebox_override("hover", _box_style(Color(0.2, 0.09, 0.05, 0.95), Hud.EMBER, 4))
	b.add_theme_stylebox_override("pressed", _box_style(Hud.ORANGE, Color(0, 0, 0), 4))
	b.add_theme_stylebox_override("hover_pressed", _box_style(Hud.ORANGE, Color(0, 0, 0), 4))
	root.add_child(b)
	return b


func _build_ui() -> void:
	_outlined_label("Forge Thy Doctrine", 62, Vector2(60, 30), Color(0.96, 0.9, 0.82))
	_outlined_label("Instrument of Ege", 28, Vector2(330, 112), Hud.ORANGE)
	lines = LineTree.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(lines)
	var grp := ButtonGroup.new()
	for i in range(MAIN.size()):
		var name: String = MAIN[i]
		var b := _menu_button(name, Vector2(BTN_X, 215.0 + i * 135.0), Vector2(BTN_W, BTN_H), Color(0.02, 0.02, 0.02), true)
		b.button_group = grp
		b.pressed.connect(func(): _open(name))
		main_btns.append(b)
	var big := HullPreview.new()
	big.position = Vector2(760, 60)
	big.size = Vector2(780, 560)
	big.spin_speed = 0.25
	root.add_child(big)
	big.setup(Game.last_ship_bp())
	detail = Hud.ConsolePanel.new()
	detail.position = Vector2(780, 150)
	detail.size = Vector2(470, 440)
	detail.visible = false
	root.add_child(detail)
	(main_btns[1] as Button).button_pressed = true
	_open("Single Player")


func _clear_options() -> void:
	for n in opt_nodes:
		(n as Node).queue_free()
	opt_nodes.clear()


func _open(entry: String) -> void:
	active = entry
	_clear_options()
	detail.visible = false
	var opts: Array = TREE[entry]
	var idx := MAIN.find(entry)
	var by := 215.0 + idx * 135.0 + BTN_H * 0.5
	var n := opts.size()
	var spacing := 112.0
	var start := clampf(by - float(n - 1) * spacing * 0.5, 160.0, 780.0 - float(n - 1) * spacing)
	var spine_x := BTN_X + BTN_W + 55.0
	var segs: Array = [[Vector2(BTN_X + BTN_W, by), Vector2(spine_x, by)]]
	var ymin := by
	var ymax := by
	for i in range(n):
		var oy := start + float(i) * spacing
		ymin = minf(ymin, oy)
		ymax = maxf(ymax, oy)
		segs.append([Vector2(spine_x, oy), Vector2(OPT_X, oy)])
		var name: String = opts[i]
		var b := _menu_button(name, Vector2(OPT_X, oy - OPT_H * 0.5), Vector2(OPT_W, OPT_H), RED)
		b.modulate.a = 0.0
		b.pressed.connect(func(): _on_option(entry, name))
		opt_nodes.append(b)
		var tw := b.create_tween()
		tw.tween_interval(0.25 + 0.05 * i)
		tw.tween_property(b, "modulate:a", 1.0, 0.2)
	segs.append([Vector2(spine_x, ymin), Vector2(spine_x, ymax)])
	lines.segs = segs
	lines.t = 0.0
	var tl := lines.create_tween()
	tl.tween_method(func(v: float): lines.t = v; lines.queue_redraw(), 0.0, 1.0, 0.3)


# ------------------------------------------------------------------ option actions
func _info(title: String, text: String) -> VBoxContainer:
	detail.title = title.to_upper()
	detail.queue_redraw()
	for c in detail.body.get_children():
		c.queue_free()
	detail.visible = true
	if text != "":
		var l := Label.new()
		l.text = text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(400, 0)
		detail.body.add_child(l)
	return detail.body


func _on_option(main: String, opt: String) -> void:
	match opt:
		"Join", "Host":
			_info(opt, "Peer-to-peer lobbies (host / join, GameLobby, voice-to-text chat) are roadmap step 4 and are not in this prototype.")
		"Campaign":
			_info(opt, "The campaign is not available.")
		"Freematch":
			_freematch_cfg()
		"Tutorial":
			_sandbox_cfg(true)
		"Sandbox":
			_sandbox_cfg(false)
		"Ship creation":
			Game.editing_bp = {}
			Game.goto_scene("res://scenes/ship_editor.tscn")
		"Module creation", "Download creation":
			_info(opt, "Not in this prototype (community modules / downloads come later).\nShips are JSON files in:\n%s" % ProjectSettings.globalize_path(Game.USER_SHIPS))
		"Options":
			_options()
		"Credits":
			_info(opt, "Design: Forge Thy Doctrine GDD (docs/).\nPrototype built with Godot 4.4 and AI assistance.")
		"Quit":
			get_tree().quit()


func _ship_picker(parent: Control) -> OptionButton:
	var pick := OptionButton.new()
	var ships := Game.all_ships()
	for s in ships:
		pick.add_item("%s  (%s)" % [s["name"], s["source"]])
	for i in range(ships.size()):
		if ships[i]["name"] == Game.last_ship.get("name", ""):
			pick.select(i)
	parent.add_child(pick)
	return pick


func _sandbox_cfg(tut: bool) -> void:
	var b := _info("Tutorial" if tut else "Sandbox - test range", "Choose your ship.")
	var pick := _ship_picker(b)
	var go := Button.new()
	go.text = "Start"
	go.pressed.connect(func():
		var ships := Game.all_ships()
		var e: Dictionary = ships[pick.selected]
		Game.set_last_ship(e["name"], e["source"], e["path"])
		Game.session = {"mode": "sandbox", "ship": e["bp"], "return_scene": "res://scenes/main_menu.tscn", "tutorial": tut}
		Game.goto_scene("res://scenes/arena.tscn"))
	b.add_child(go)


func _freematch_cfg() -> void:
	var b := _info("Freematch", "Choose your ship and the rules.")
	var pick := _ship_picker(b)
	var rule := OptionButton.new()
	for r in ["Team Deathmatch (respawns)", "Team Elimination (one life)", "Deathmatch (free for all)"]:
		rule.add_item(r)
	b.add_child(rule)
	var spins := {}
	for pair in [["ally", "Allied bots", 1, 0, 4], ["enemy", "Enemy bots / DM rivals", 2, 1, 7], ["kills", "Kills to win", 10, 3, 100]]:
		var hb := HBoxContainer.new()
		var l := Label.new()
		l.text = pair[1]
		l.custom_minimum_size = Vector2(190, 0)
		hb.add_child(l)
		var sp := SpinBox.new()
		sp.min_value = pair[3]
		sp.max_value = pair[4]
		sp.value = pair[2]
		hb.add_child(sp)
		spins[pair[0]] = sp
		b.add_child(hb)
	var note := Label.new()
	note.text = "Design doc targets: TDM 100 kills, DM 30 kills."
	note.add_theme_font_size_override("font_size", 10)
	b.add_child(note)
	var go := Button.new()
	go.text = "Start match"
	go.pressed.connect(func():
		var ships := Game.all_ships()
		var e: Dictionary = ships[pick.selected]
		Game.set_last_ship(e["name"], e["source"], e["path"])
		var rs: String = ["tdm", "elim", "dm"][rule.selected]
		Game.session = {"mode": "freematch", "ship": e["bp"], "return_scene": "res://scenes/main_menu.tscn", "ruleset": rs,
			"bots_ally": int(spins["ally"].value), "bots_enemy": int(spins["enemy"].value), "kill_limit": int(spins["kills"].value)}
		Game.goto_scene("res://scenes/arena.tscn"))
	b.add_child(go)


func _options() -> void:
	var b := _info("Options", "")
	var ck := CheckButton.new()
	ck.text = "Assisted flight by default"
	ck.button_pressed = Game.settings["assist"]
	ck.toggled.connect(func(on: bool): Game.settings["assist"] = on)
	b.add_child(ck)
	var cs := CheckButton.new()
	cs.text = "Camera shake on hits"
	cs.button_pressed = Game.settings["shake"]
	cs.toggled.connect(func(on: bool): Game.settings["shake"] = on)
	b.add_child(cs)
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = "Mouse sensitivity (FP)"
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0005
	sl.max_value = 0.006
	sl.step = 0.0001
	sl.value = Game.settings["mouse_sens"]
	sl.custom_minimum_size = Vector2(180, 20)
	sl.value_changed.connect(func(v: float): Game.settings["mouse_sens"] = v)
	hb.add_child(sl)
	b.add_child(hb)
