extends Node3D
## Ship Forge (GDD section 1): timeline of steps Hull -> Modules -> Links -> Interior -> Cosmetics -> Test,
## permanent stat/legality panel, undo/redo, adaptive snapping and camera for any ship size.

const STEPS := ["Hull", "Modules", "Links", "Interior", "Cosmetics", "Test"]
const MAPS := [
	{"name": "Skirmish map (up to Frigate)", "tier": 4},
	{"name": "Fleet map (up to Cruiser)", "tier": 6},
	{"name": "Titan sea (all classes)", "tier": 8},
]
const TABS := ["Type", "Modifier", "Helper"]
const TL_H := 62.0
const HELPERS := ["Ruler", "Frame view"]
const MODES := {
	"Hull": {"Type": ["Vertex", "Ring"], "Modifier": ["Mirror", "Soft select", "Thickness"], "Helper": HELPERS},
	"Modules": {"Type": ["Module"], "Modifier": ["Auto-hull"], "Helper": HELPERS},
	"Links": {"Type": ["Link"], "Modifier": ["Auto-link"], "Helper": HELPERS},
	"Interior": {"Type": ["Corridor"], "Modifier": ["None"], "Helper": HELPERS},
	"Cosmetics": {"Type": ["Paint"], "Modifier": ["None"], "Helper": HELPERS},
	"Test": {"Type": ["Test range"], "Modifier": ["None"], "Helper": HELPERS},
}
const NICE := [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 250.0, 500.0, 1000.0]

var bp: Dictionary
var step := "Hull"
var sel_ring := 1
var sel_vert := -1          # -1 = whole ring
var sel_mod := -1
var link_from := -1
var mirror := true
var soft := false
var ring_mode := false
var view_mode := 0          # 0 shaded, 1 x-ray, 2 wireframe (GDD view modifier)
var auto_hull_on := false
var hull_clear := 0.3
var snap := 0.25
var budget := 600.0
var map_idx := 0
var undo_stack: Array = []
var redo_stack: Array = []
var cam: Camera3D
var cam_target := Vector3.ZERO
var cam_yaw := 0.8
var cam_pitch := -0.4
var cam_dist := 40.0
var hull_mi: MeshInstance3D
var hull_mat: StandardMaterial3D
var handle_root: Node3D
var mod_root: Node3D
var line_mi: MeshInstance3D
var line_mesh: ImmediateMesh
var ui: CanvasLayer
var tools: VBoxContainer
var stats_lbl: RichTextLabel
var hint: Label
var status: Label
var name_edit: LineEdit
var tab := "Type"
var tab_sel := {}           # "Step|Tab" -> chosen option index
var mode_btns := {}
var mode_opts := {}
var left_panel: PanelContainer
var left_title: Label
var legal_lbl: Label
var tl: Timeline
var ortho := false
var show_ruler := false
var load_ov: ColorRect
var load_list: ItemList
var load_name: Label
var load_scope: OptionButton
var load_new: Button
var load_mod: Button
var file_dlg: FileDialog
var _fd_action := ""
var mod_list: ItemList
var issues: Array = []
var stats: Dictionary = {}
var dirty := true
var dirty_since_save := false
var orbiting := false
var panning := false
var dragging := false
var drag_start := Vector3.ZERO
var drag_orig := Vector3.ZERO
var drag_last := Vector3.ZERO
var _last_undo_t := -10.0
var _t := 0.0
var _size_spins: Array = []
var _building_ui := false
var _ship_cache: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_ui()
	if Game.editing_bp.is_empty():
		bp = ShipData.new_blueprint("New Ship")
	else:
		bp = Game.editing_bp
	_after_load()


func _after_load() -> void:
	sel_ring = clampi(sel_ring, 0, bp["rings"].size() - 1)
	sel_vert = -1
	sel_mod = -1
	link_from = -1
	name_edit.text = bp["name"]
	_frame_camera()
	_set_step(step)
	_changed(false)


# ------------------------------------------------------------------ world
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.6)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	cam = Camera3D.new()
	add_child(cam)
	hull_mat = StandardMaterial3D.new()
	hull_mat.metallic = 0.4
	hull_mat.roughness = 0.5
	hull_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hull_mi = MeshInstance3D.new()
	hull_mi.material_override = hull_mat
	add_child(hull_mi)
	handle_root = Node3D.new()
	add_child(handle_root)
	mod_root = Node3D.new()
	add_child(mod_root)
	line_mesh = ImmediateMesh.new()
	line_mi = MeshInstance3D.new()
	line_mi.mesh = line_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.no_depth_test = false
	line_mi.material_override = lm
	add_child(line_mi)


func _frame_camera() -> void:
	var b := ShipData.hull_bounds(bp["rings"])
	cam_target = b.get_center()
	var longest := maxf(b.size.x, maxf(b.size.y, maxf(b.size.z, 1.0)))
	cam_dist = longest * 1.15
	_update_cam()


func _update_cam() -> void:
	var off := Vector3(0, 0, cam_dist).rotated(Vector3.RIGHT, cam_pitch).rotated(Vector3.UP, cam_yaw)
	cam.look_at_from_position(cam_target + off, cam_target, Vector3.UP)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
	if ortho:
		cam.size = cam_dist * 1.5
	cam.near = maxf(cam_dist * 0.002, 0.01)
	cam.far = cam_dist * 200.0


func _auto_snap() -> void:
	var b := ShipData.hull_bounds(bp["rings"])
	var raw := maxf(b.size.x, maxf(b.size.y, b.size.z)) / 80.0
	snap = NICE[NICE.size() - 1]
	for n in NICE:
		if n >= raw:
			snap = n
			break


# ------------------------------------------------------------------ UI
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.12, 0.9)
	sb.border_color = Color(0.3, 0.5, 0.7, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _btn(text: String, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _lbl(text: String, parent: Control, size := 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


class Timeline extends Control:
	signal picked(step_name: String)
	var steps: Array = []
	var active := ""
	var font: FontVariation

	func _init() -> void:
		font = FontVariation.new()
		font.base_font = ThemeDB.fallback_font
		font.variation_embolden = 0.5
		font.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.25, 1), Vector2.ZERO)

	func set_active(s: String) -> void:
		active = s
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and steps.size() > 0:
			var i := clampi(int(ev.position.x / (size.x / steps.size())), 0, steps.size() - 1)
			picked.emit(steps[i])
			accept_event()

	func _draw() -> void:
		var n := steps.size()
		if n == 0:
			return
		var w := size.x / n
		var h := size.y
		var a := minf(h * 0.4, w * 0.25)
		for i in n:
			var x := i * w
			var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + w - a, 0), Vector2(x + w, h * 0.5), Vector2(x + w - a, h), Vector2(x, h)])
			if i > 0:
				pts.append(Vector2(x + a, h * 0.5))
			var col := Color(0.93, 0.11, 0.14) if steps[i] == active else Color(1.0, 0.5, 0.15)
			draw_colored_polygon(pts, col)
			var outline := pts.duplicate()
			outline.append(pts[0])
			draw_polyline(outline, Color(0, 0, 0), 4.0)
			var tx := x + (a if i > 0 else 14.0) + 6.0
			draw_string(font, Vector2(tx, h * 0.5 + 9.0), steps[i], HORIZONTAL_ALIGNMENT_LEFT, w - a * 2.0, 26, Color(0.04, 0.02, 0.02))


func _bar_box(parent: Control, ratio: float) -> HBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style())
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_stretch_ratio = ratio
	parent.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	pc.add_child(hb)
	return hb


func _opt(items: Array, parent: Control, cb: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	for it in items:
		ob.add_item(it)
	ob.item_selected.connect(cb)
	parent.add_child(ob)
	return ob


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# ---- top bars (mock-up): row 1 = name/save/undo/redo/load | view settings | export/import
	var top := VBoxContainer.new()
	top.anchor_right = 1.0
	top.offset_left = 6
	top.offset_right = -6
	top.offset_top = 6
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	top.add_child(row1)
	var box_a := _bar_box(row1, 36.0)
	_btn("< Menu", box_a, func(): Game.editing_bp = {}; Game.goto_scene("res://scenes/main_menu.tscn"))
	_lbl("Name :", box_a)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(120, 0)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t: String): bp["name"] = t; dirty_since_save = true)
	box_a.add_child(name_edit)
	_btn("Save", box_a, _save)
	_btn("Undo", box_a, _undo)
	_btn("Redo", box_a, _redo)
	_btn("Load", box_a, _open_load)

	var box_b := _bar_box(row1, 27.0)
	_lbl("View settings", box_b, 12)
	_opt(["Full", "X-ray", "Wireframe"], box_b, func(i: int): view_mode = i; _changed(false))
	_opt(["Perspective", "Orthogonal"], box_b, func(i: int): ortho = (i == 1))
	var cm := MenuButton.new()
	cm.text = "Camera"
	cm.flat = false
	cm.focus_mode = Control.FOCUS_NONE
	var views := [["Top", 0.0, -1.5], ["Bottom", 0.0, 1.5], ["Side right", PI * 0.5, 0.0], ["Side left", -PI * 0.5, 0.0],
		["Front", PI, 0.0], ["Rear", 0.0, 0.0], ["Default 3/4", 0.8, -0.4]]
	for i in views.size():
		cm.get_popup().add_item(views[i][0], i)
	cm.get_popup().id_pressed.connect(func(id: int): cam_yaw = views[id][1]; cam_pitch = views[id][2])
	box_b.add_child(cm)

	var box_c := _bar_box(row1, 37.0)
	box_c.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn("Export", box_c, _export)
	_btn("Import", box_c, _import)

	# ---- row 2: Type / Modifier / Helper (button = show its tab on the left, dropdown = which one) | legal
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	top.add_child(row2)
	var box_d := _bar_box(row2, 63.0)
	for t in TABS:
		var tt: String = t
		var tb := Button.new()
		tb.text = tt + " :"
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(func(): _pick_tab(tt))
		box_d.add_child(tb)
		mode_btns[tt] = tb
		mode_opts[tt] = _opt([], box_d, func(i: int): _pick_mode(tt, i))
		if tt != "Helper":
			box_d.add_child(VSeparator.new())
	var box_e := _bar_box(row2, 37.0)
	box_e.alignment = BoxContainer.ALIGNMENT_CENTER
	legal_lbl = _lbl("", box_e, 15)

	# ---- left tools tab
	left_panel = PanelContainer.new()
	left_panel.add_theme_stylebox_override("panel", _panel_style())
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 6
	left_panel.offset_right = 300
	left_panel.offset_top = 96
	left_panel.offset_bottom = -(TL_H + 40)
	root.add_child(left_panel)
	var lv := VBoxContainer.new()
	left_panel.add_child(lv)
	left_title = _lbl("", lv, 15)
	left_title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sc)
	tools = VBoxContainer.new()
	tools.custom_minimum_size = Vector2(270, 0)
	tools.add_theme_constant_override("separation", 4)
	sc.add_child(tools)

	# ---- right ship info panel
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _panel_style())
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.anchor_bottom = 1.0
	rp.offset_left = -330
	rp.offset_right = -6
	rp.offset_top = 96
	rp.offset_bottom = -(TL_H + 40)
	root.add_child(rp)
	var rv := VBoxContainer.new()
	rp.add_child(rv)
	var maprow := HBoxContainer.new()
	rv.add_child(maprow)
	var mp := OptionButton.new()
	mp.focus_mode = Control.FOCUS_NONE
	for m in MAPS:
		mp.add_item(m["name"])
	mp.item_selected.connect(func(i: int): map_idx = i; _changed(false))
	maprow.add_child(mp)
	_lbl("pts", maprow)
	var bsp := SpinBox.new()
	bsp.min_value = 50
	bsp.max_value = 100000
	bsp.value = budget
	bsp.step = 50
	bsp.value_changed.connect(func(v: float): budget = v; _changed(false))
	maprow.add_child(bsp)
	stats_lbl = RichTextLabel.new()
	stats_lbl.bbcode_enabled = true
	stats_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_lbl.add_theme_font_size_override("normal_font_size", 13)
	rv.add_child(stats_lbl)

	# ---- bottom: status/hint line and the step timeline
	hint = Label.new()
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.anchor_right = 1.0
	hint.offset_top = -(TL_H + 34)
	hint.offset_left = 310
	hint.offset_right = -340
	hint.add_theme_font_size_override("font_size", 12)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
	status = Label.new()
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.offset_top = -(TL_H + 34)
	status.offset_left = 10
	status.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)
	tl = Timeline.new()
	tl.steps = STEPS
	tl.anchor_top = 1.0
	tl.anchor_bottom = 1.0
	tl.anchor_right = 1.0
	tl.offset_left = 6
	tl.offset_right = -6
	tl.offset_top = -(TL_H + 4)
	tl.offset_bottom = -4
	tl.mouse_filter = Control.MOUSE_FILTER_STOP
	tl.picked.connect(_set_step)
	root.add_child(tl)

	# ---- Load popup
	load_ov = ColorRect.new()
	load_ov.color = Color(0, 0, 0, 0.55)
	load_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	load_ov.mouse_filter = Control.MOUSE_FILTER_STOP
	load_ov.visible = false
	root.add_child(load_ov)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_ov.add_child(cc)
	var lpan := PanelContainer.new()
	lpan.add_theme_stylebox_override("panel", _panel_style())
	lpan.custom_minimum_size = Vector2(780, 500)
	cc.add_child(lpan)
	var lbox := VBoxContainer.new()
	lpan.add_child(lbox)
	_lbl("LOAD A SHIP", lbox, 16).add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	load_list = ItemList.new()
	load_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	load_list.item_selected.connect(_on_load_selected)
	lbox.add_child(load_list)
	var bb := HBoxContainer.new()
	lbox.add_child(bb)
	load_name = _lbl("(select a ship)", bb, 14)
	load_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_name.clip_text = true
	_lbl("Copy:", bb, 12)
	load_scope = _opt(["Everything", "Hull + modules", "Hull only"], bb, func(_i: int): pass)
	load_new = _btn("Load as new ship (prefab)", bb, func(): _load_pick(true))
	load_new.tooltip_text = "Starts a new ship from this prefab. Save adds a new ship; the prefab is not changed."
	load_mod = _btn("Modify this ship", bb, func(): _load_pick(false))
	load_mod.tooltip_text = "Edits this ship. Save overwrites it."
	load_new.disabled = true
	load_mod.disabled = true
	_btn("Close", bb, func(): load_ov.visible = false)

	file_dlg = FileDialog.new()
	file_dlg.access = FileDialog.ACCESS_FILESYSTEM
	file_dlg.use_native_dialog = true
	file_dlg.filters = PackedStringArray(["*.json ; Forge Thy Doctrine ship"])
	file_dlg.file_selected.connect(_on_file_picked)
	add_child(file_dlg)
	_refresh_ship_list()


func say(t: String) -> void:
	status.text = t


# ------------------------------------------------------------------ load / import / export
func _refresh_ship_list() -> void:
	_ship_cache = Game.all_ships()
	load_list.clear()
	for s in _ship_cache:
		load_list.add_item("%s   (%s)" % [s["name"], s["source"]])
	load_name.text = "(select a ship)"
	load_new.disabled = true
	load_mod.disabled = true


func _open_load() -> void:
	_refresh_ship_list()
	load_ov.visible = true


func _on_load_selected(_i: int) -> void:
	var sel := load_list.get_selected_items()
	if sel.is_empty():
		return
	var ent: Dictionary = _ship_cache[sel[0]]
	load_name.text = "%s  (%s)" % [ent["name"], ent["source"]]
	load_new.disabled = false
	load_mod.disabled = false


func _load_pick(as_prefab: bool) -> void:
	var sel := load_list.get_selected_items()
	if sel.is_empty():
		return
	_push_undo()
	var ent: Dictionary = _ship_cache[sel[0]]
	var src: Dictionary = (ent["bp"] as Dictionary).duplicate(true)
	if as_prefab:
		src["name"] = String(src["name"]) + " copy"
		src["author"] = ""
		var scope := load_scope.selected
		if scope == 2:
			src["modules"] = []
		if scope >= 1:
			src["links"] = []
	bp = ShipData.normalize(src)
	if not as_prefab:
		Game.set_last_ship(ent["name"], ent["source"], ent["path"])
	load_ov.visible = false
	_after_load()
	if as_prefab:
		say("New ship started from prefab %s - Save will add a new ship." % ent["name"])
	elif ent["source"] == "premade":
		say("Premade ships cannot be overwritten: Save will add your own ship with this name.")
	else:
		say("Modifying %s - Save will overwrite it." % bp["name"])


func _export() -> void:
	if not issues.is_empty():
		say("Cannot export: the ship must be fully legal (see the red items).")
		return
	_fd_action = "export"
	file_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dlg.title = "Export ship"
	file_dlg.current_file = String(bp["name"]).validate_filename() + ".json"
	file_dlg.popup_centered_ratio(0.7)


func _import() -> void:
	_fd_action = "import"
	file_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dlg.title = "Import ship"
	file_dlg.popup_centered_ratio(0.7)


func _on_file_picked(path: String) -> void:
	if _fd_action == "export":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			say("Export failed: cannot write %s" % path)
			return
		f.store_string(JSON.stringify(bp, "\t"))
		say("Exported to %s" % path)
		return
	var d := Game.load_ship_file(path)
	if d.is_empty():
		say("Import failed: this is not a valid ship file.")
		return
	if not ShipData.validate(d).is_empty():
		say("Import refused: this ship is not legal in this version of the game.")
		return
	var taken := {}
	for s in Game.all_ships():
		taken[s["name"]] = true
	var nm: String = d["name"]
	while taken.has(nm):
		nm += " (imported)"
	d["name"] = nm
	if Game.save_ship(d) == "":
		say("Import failed: could not save the ship.")
		return
	_refresh_ship_list()
	say("Imported %s - open it with Load." % nm)


func _save() -> void:
	if not issues.is_empty():
		say("Cannot save: the ship must be fully legal (see the red items).")
		return
	var path := Game.save_ship(bp)
	if path == "":
		say("Save failed")
		return
	dirty_since_save = false
	Game.set_last_ship(bp["name"], "user", path)
	_refresh_ship_list()
	say("Saved to %s" % ProjectSettings.globalize_path(path))


# ------------------------------------------------------------------ steps, Type / Modifier / Helper
func _mode_value(t: String) -> String:
	var opts: Array = MODES[step][t]
	var i := clampi(int(tab_sel.get(step + "|" + t, 0)), 0, opts.size() - 1)
	return opts[i]


func _sync_modes() -> void:
	for t in TABS:
		var ob: OptionButton = mode_opts[t]
		ob.clear()
		for o in MODES[step][t]:
			ob.add_item(o)
		ob.select(clampi(int(tab_sel.get(step + "|" + t, 0)), 0, ob.item_count - 1))
	_apply_type_mode()
	_sync_tab_buttons()


func _apply_type_mode() -> void:
	ring_mode = step == "Hull" and _mode_value("Type") == "Ring"
	sel_vert = -1


func _sync_tab_buttons() -> void:
	for t in TABS:
		(mode_btns[t] as Button).set_pressed_no_signal(left_panel.visible and tab == t)


func _pick_tab(t: String) -> void:
	if tab == t and left_panel.visible:
		left_panel.visible = false
	else:
		tab = t
		left_panel.visible = true
	_sync_tab_buttons()
	_build_tools()


func _pick_mode(t: String, i: int) -> void:
	tab_sel[step + "|" + t] = i
	if t == "Type":
		_apply_type_mode()
	tab = t
	left_panel.visible = true
	_sync_tab_buttons()
	_build_tools()
	_changed(false)


func _set_step(s: String) -> void:
	step = s
	link_from = -1
	tl.set_active(s)
	_sync_modes()
	var hints := {
		"Hull": "LMB on a vertex: select/drag (mirror keeps symmetry). Arrows = X/Y, PageUp/PageDown = ring Z. RMB orbit, MMB/Shift+RMB pan, wheel zoom. Ctrl+Z undo.",
		"Modules": "LMB a module to select and drag it (camera plane). Arrows/PageUp/PageDown nudge. Red outline = minimum size. White line = facing.",
		"Links": "LMB module A, then module B to link: Commander Post -> Engine/Turret Control/Turret Bay/Radar, Engine -> Thruster, Turret Bay -> touching Barrel (turns it), Turret Control -> any Barrel (fixed).",
		"Interior": "Corridors, doors, stairs and ladders belong to roadmap step 6 and are not in this prototype.",
		"Cosmetics": "Colors only in this prototype. Stowage props and decals: later roadmap.",
		"Test": "Launch the solo test range: place a dummy, shoot your own hull, test flight.",
	}
	hint.text = hints[s]
	_build_tools()
	_changed(false)


func _build_tools() -> void:
	_building_ui = true
	for c in tools.get_children():
		c.queue_free()
	_size_spins.clear()
	var v := _mode_value(tab)
	left_title.text = ("%s : %s" % [tab, v]).to_upper()
	match tab:
		"Type":
			match step:
				"Hull":
					if v == "Vertex":
						_tools_hull_vertex()
					else:
						_tools_hull_ring()
				"Modules":
					_tools_mod_type()
				"Links":
					_tools_links()
				"Interior":
					_lbl("Not in this prototype.\n\nPlanned: entrances on internal modules,\ncorridors with bend points, doors,\nauto slope -> stairs -> ladder.", tools)
				"Cosmetics":
					_tools_cosmetics()
				"Test":
					_tools_test()
		"Modifier":
			_tools_modifier(v)
		"Helper":
			_tools_helper(v)
	_building_ui = false


func _check(text: String, on: bool, cb: Callable) -> CheckButton:
	var ck := CheckButton.new()
	ck.text = text
	ck.button_pressed = on
	ck.focus_mode = Control.FOCUS_NONE
	ck.toggled.connect(cb)
	tools.add_child(ck)
	return ck


func _tools_modifier(v: String) -> void:
	match v:
		"Mirror":
			_check("Mirror symmetry (X)", mirror, func(on: bool): mirror = on; _changed(false))
			_lbl("Sculpt one side, the other follows.\nVertices cannot cross the centerline.", tools, 11)
		"Soft select":
			_check("Soft selection (proportional)", soft, func(on: bool): soft = on)
			_lbl("Moving a vertex drags its neighbours\nsmoothly along with it.", tools, 11)
		"Thickness":
			var tr := HBoxContainer.new()
			tools.add_child(tr)
			_lbl("Thickness (m)", tr, 12)
			var ts := HSlider.new()
			ts.min_value = 0.02
			ts.max_value = 1.5
			ts.step = 0.01
			ts.value = float(bp["thickness"])
			ts.custom_minimum_size = Vector2(130, 18)
			ts.value_changed.connect(func(x: float): if not _building_ui: _push_undo(); bp["thickness"] = x; _changed())
			tr.add_child(ts)
			_lbl("Thicker armor = tougher but heavier and\nmore expensive.", tools, 11)
		"Auto-hull":
			_tools_mod_autohull()
		"Auto-link":
			_btn("Auto-link everything", tools, func(): _push_undo(); ShipData.auto_link(bp); _changed(); _build_tools())
			_btn("Clear all links", tools, func(): _push_undo(); bp["links"] = []; _changed(); _build_tools())
		_:
			_lbl("No modifier for this step yet.", tools, 12)


func _tools_helper(v: String) -> void:
	match v:
		"Ruler":
			_check("Show bounding box", show_ruler, func(on: bool): show_ruler = on; _changed(false))
			var st := stats
			if not st.is_empty():
				_lbl("Length  %.2f m\nBeam    %.2f m\nHeight  %.2f m\nGrid snap %.2f m (adapts to ship size)" % [st["length"], st["beam"], st["height"], snap], tools, 12)
		"Frame view":
			_btn("Frame the whole ship", tools, _frame_camera)


func _ring_nav() -> void:
	var rr := HBoxContainer.new()
	tools.add_child(rr)
	_btn("< Ring", rr, func(): sel_ring = maxi(sel_ring - 1, 0); sel_vert = -1; _changed(false))
	_btn("Ring >", rr, func(): sel_ring = mini(sel_ring + 1, bp["rings"].size() - 1); sel_vert = -1; _changed(false))


func _tools_hull_vertex() -> void:
	_lbl("Click a vertex of the selected ring to move it\n(mirror keeps it symmetric).", tools, 11)
	_ring_nav()
	_btn("Loop cut (after ring)", tools, _loop_cut)
	var ex := HBoxContainer.new()
	tools.add_child(ex)
	_btn("Extrude nose", ex, func(): _extrude(true))
	_btn("Extrude tail", ex, func(): _extrude(false))
	_btn("Delete ring", tools, _delete_ring)


func _tools_hull_ring() -> void:
	_lbl("Clicking selects the whole ring.", tools, 11)
	_ring_nav()
	_lbl("Ring tools (selected ring)", tools, 12)
	var sr := HBoxContainer.new()
	tools.add_child(sr)
	_btn("Scale +10%", sr, func(): _scale_ring(1.1, 1.1))
	_btn("Scale -10%", sr, func(): _scale_ring(0.9, 0.9))
	var wr := HBoxContainer.new()
	tools.add_child(wr)
	_btn("Wider", wr, func(): _scale_ring(1.1, 1.0))
	_btn("Narrower", wr, func(): _scale_ring(0.9, 1.0))
	_btn("Taller", wr, func(): _scale_ring(1.0, 1.1))
	_btn("Flatter", wr, func(): _scale_ring(1.0, 0.9))
	_btn("Round (fillet) ring", tools, _round_ring)
	_lbl("Whole hull", tools, 12)
	var sh := HBoxContainer.new()
	tools.add_child(sh)
	_btn("Scale x1.1", sh, func(): _scale_hull(1.1))
	_btn("Scale x0.9", sh, func(): _scale_hull(0.9))


func _tools_mod_type() -> void:
	var tr := HBoxContainer.new()
	tools.add_child(tr)
	var tp := OptionButton.new()
	tp.focus_mode = Control.FOCUS_NONE
	var types: Array = ShipData.MODULES.keys()
	for t in types:
		tp.add_item(ShipData.MODULES[t]["label"])
	tr.add_child(tp)
	_btn("Add", tr, func(): _add_module(types[tp.selected]))
	mod_list = ItemList.new()
	mod_list.custom_minimum_size = Vector2(250, 190)
	mod_list.item_selected.connect(func(i: int): sel_mod = int(mod_list.get_item_metadata(i)); _build_tools(); _changed(false))
	tools.add_child(mod_list)
	_fill_mod_list()
	_tools_mod_detail()


func _tools_mod_autohull() -> void:
	_check("Auto-hull on invalid placement", auto_hull_on, func(on: bool): auto_hull_on = on)
	var hr := HBoxContainer.new()
	tools.add_child(hr)
	_lbl("Hull clearance X (m)", hr, 12)
	var hsl := HSlider.new()
	hsl.min_value = 0.0
	hsl.max_value = 3.0
	hsl.step = 0.05
	hsl.value = hull_clear
	hsl.custom_minimum_size = Vector2(110, 18)
	hsl.value_changed.connect(func(v: float): hull_clear = v)
	hr.add_child(hsl)
	var m := ShipData.get_module(bp, sel_mod) if sel_mod >= 0 else {}
	if not m.is_empty() and ShipData.MODULES[m["type"]]["kind"] == "internal":
		_btn("Auto-hull: enclose selected module", tools, func(): _push_undo(); _auto_hull_module(sel_mod))
	else:
		_lbl("Select an internal module (Type tab) to\nenclose it with the hull.", tools, 11)


func _tools_mod_detail() -> void:
	if sel_mod < 0 or ShipData.get_module(bp, sel_mod).is_empty():
		_lbl("Select a module (list or click in 3D).", tools, 12)
		return
	var m := ShipData.get_module(bp, sel_mod)
	var def: Dictionary = ShipData.MODULES[m["type"]]
	_lbl("%s #%d  (%s)" % [def["label"], m["id"], def["kind"]], tools, 13)
	var mn: Vector3 = def["min"]
	_lbl("Minimum size: %.2f x %.2f x %.2f m" % [mn.x, mn.y, mn.z], tools, 11)
	var sz := ShipData.v3(m["size"])
	for ax in 3:
		var hb := HBoxContainer.new()
		tools.add_child(hb)
		_lbl(["Size X", "Size Y", "Size Z"][ax], hb, 12)
		var spn := SpinBox.new()
		spn.min_value = mn[ax]
		spn.max_value = 100000.0
		spn.step = snap
		spn.set_value_no_signal(sz[ax])
		var axx := ax
		spn.value_changed.connect(func(v: float): _set_size(axx, v))
		hb.add_child(spn)
	var dr := HBoxContainer.new()
	tools.add_child(dr)
	_lbl("Facing", dr, 12)
	var dp := OptionButton.new()
	for n in ShipData.DIR_NAMES:
		dp.add_item(n)
	dp.select(int(m["dir"]))
	dp.item_selected.connect(func(i: int): _push_undo(); m["dir"] = i; _changed())
	dr.add_child(dp)
	if m["type"] == "barrel":
		var wr := HBoxContainer.new()
		tools.add_child(wr)
		_lbl("Weapon", wr, 12)
		var wp := OptionButton.new()
		for w in ShipData.WEAPONS:
			wp.add_item(w)
		wp.select(ShipData.WEAPONS.find(m["weapon"]))
		wp.item_selected.connect(func(i: int): _push_undo(); m["weapon"] = ShipData.WEAPONS[i]; _changed())
		wr.add_child(wp)
		var ws := ShipData.weapon_stats(m)
		_lbl("dmg %.0f  pen %.2f  rate %.1f/s  power %.1f MW" % [ws["damage"], ws["pen"], 1.0 / float(ws["interval"]), ws["power"]], tools, 11)
	var ms := ShipData.module_stats(m)
	_lbl("HP %.0f   mass %.1f t   cost %.1f pts" % [ms["hp"], ms["mass"], ms["cost"]], tools, 11)
	if def["kind"] == "internal":
		_btn("Auto-hull: enclose this module", tools, func(): _push_undo(); _auto_hull_module(sel_mod))
	var br := HBoxContainer.new()
	tools.add_child(br)
	_btn("Duplicate", br, func(): _duplicate_module(false))
	_btn("Mirror copy", br, func(): _duplicate_module(true))
	_btn("Delete", br, _delete_module)


func _fill_mod_list() -> void:
	mod_list.clear()
	for m in bp["modules"]:
		var i := mod_list.add_item("%s #%d" % [ShipData.MODULES[m["type"]]["label"], m["id"]])
		mod_list.set_item_metadata(i, int(m["id"]))
		if int(m["id"]) == sel_mod:
			mod_list.select(i)


func _tools_links() -> void:
	_btn("Auto-link everything", tools, func(): _push_undo(); ShipData.auto_link(bp); _changed(); _build_tools())
	_btn("Clear all links", tools, func(): _push_undo(); bp["links"] = []; _changed(); _build_tools())
	_lbl("Links (click to remove):", tools, 12)
	for l in bp["links"]:
		var a := ShipData.get_module(bp, int(l[0]))
		var b := ShipData.get_module(bp, int(l[1]))
		if a.is_empty() or b.is_empty():
			continue
		var la := int(l[0])
		var lb := int(l[1])
		_btn("%s #%d  ->  %s #%d" % [ShipData.MODULES[a["type"]]["label"], la, ShipData.MODULES[b["type"]]["label"], lb], tools, func(): _push_undo(); ShipData.remove_link(bp, la, lb); _changed(); _build_tools())


func _tools_cosmetics() -> void:
	for pair in [["Hull paint", "color"], ["Accent paint", "accent"]]:
		var hb := HBoxContainer.new()
		tools.add_child(hb)
		_lbl(pair[0], hb, 13)
		var cp := ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(80, 26)
		cp.color = ShipData.col(bp[pair[1]])
		var key: String = pair[1]
		cp.color_changed.connect(func(c: Color): bp[key] = [c.r, c.g, c.b]; _changed())
		hb.add_child(cp)
	_lbl("Camo, wear and decals: later.", tools, 11)


func _tools_test() -> void:
	_lbl("Solo test range (like War Thunder):\nplace a dummy ship, test flight, turrets,\nand fire a chosen round at your own hull.", tools, 12)
	var b := _btn("Launch test range", tools, _launch_test)
	b.disabled = not issues.is_empty()
	if not issues.is_empty():
		_lbl("Fix the red items first - the ship\nmust be playable.", tools, 12).add_theme_color_override("font_color", Color(1, 0.5, 0.4))


func _launch_test() -> void:
	if not issues.is_empty():
		return
	Game.editing_bp = bp
	Game.session = {"mode": "sandbox", "ship": bp.duplicate(true), "return_scene": "res://scenes/ship_editor.tscn"}
	Game.save_ship(bp, Game.DRAFTS)
	Game.goto_scene("res://scenes/arena.tscn")


# ------------------------------------------------------------------ undo / change tracking
func _push_undo() -> void:
	undo_stack.append(bp.duplicate(true))
	if undo_stack.size() > 80:
		undo_stack.pop_front()
	redo_stack.clear()
	_last_undo_t = _t


func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(bp.duplicate(true))
	bp = undo_stack.pop_back()
	Game.editing_bp = bp
	name_edit.text = bp["name"]
	sel_ring = clampi(sel_ring, 0, bp["rings"].size() - 1)
	_build_tools()
	_changed(false)


func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(bp.duplicate(true))
	bp = redo_stack.pop_back()
	Game.editing_bp = bp
	name_edit.text = bp["name"]
	sel_ring = clampi(sel_ring, 0, bp["rings"].size() - 1)
	_build_tools()
	_changed(false)


func _changed(mark := true) -> void:
	dirty = true
	if mark:
		dirty_since_save = true
	Game.editing_bp = bp


# ------------------------------------------------------------------ hull editing
func _ring(i: int) -> Dictionary:
	return bp["rings"][i]


func _set_vert(r: int, i: int, x: float, y: float) -> void:
	var ring := _ring(r)
	if mirror and (i == 0 or i == 4):
		x = 0.0
	ring["pts"][i] = [x, y]
	if mirror:
		var j := ShipData.mirror_idx(i)
		if j != i:
			ring["pts"][j] = [-x, y]


func _move_vertex_by(r: int, i: int, dx: float, dy: float) -> void:
	var p: Array = _ring(r)["pts"][i]
	_set_vert(r, i, float(p[0]) + dx, float(p[1]) + dy)
	if soft:
		for off in [1, 2]:
			var w := 0.5 if off == 1 else 0.2
			for rr in [r - off, r + off]:
				if rr >= 0 and rr < bp["rings"].size():
					var q: Array = _ring(rr)["pts"][i]
					_set_vert(rr, i, float(q[0]) + dx * w, float(q[1]) + dy * w)


func _move_ring_by(r: int, dx: float, dy: float) -> void:
	if mirror:
		dx = 0.0
	for p in _ring(r)["pts"]:
		p[0] = float(p[0]) + dx
		p[1] = float(p[1]) + dy


func _move_ring_z(r: int, dz: float) -> void:
	var rings: Array = bp["rings"]
	var z := float(_ring(r)["z"]) + dz
	if r > 0:
		z = maxf(z, float(rings[r - 1]["z"]) + ShipData.MIN_RING_GAP)
	if r < rings.size() - 1:
		z = minf(z, float(rings[r + 1]["z"]) - ShipData.MIN_RING_GAP)
	_ring(r)["z"] = z


func _loop_cut() -> void:
	var rings: Array = bp["rings"]
	if sel_ring >= rings.size() - 1:
		_extrude(false)
		return
	_push_undo()
	var a := _ring(sel_ring)
	var b := _ring(sel_ring + 1)
	var pts: Array = []
	for i in ShipData.RING_PTS:
		pts.append([(float(a["pts"][i][0]) + float(b["pts"][i][0])) * 0.5, (float(a["pts"][i][1]) + float(b["pts"][i][1])) * 0.5])
	rings.insert(sel_ring + 1, {"z": (float(a["z"]) + float(b["z"])) * 0.5, "pts": pts})
	sel_ring += 1
	_changed()


func _extrude(nose: bool) -> void:
	_push_undo()
	var rings: Array = bp["rings"]
	var b := ShipData.hull_bounds(rings)
	var d := maxf(snap * 8.0, b.size.z * 0.1)
	var src: Dictionary = rings[0] if nose else rings[rings.size() - 1]
	var nr: Dictionary = src.duplicate(true)
	nr["z"] = float(src["z"]) + (-d if nose else d)
	if nose:
		rings.insert(0, nr)
		sel_ring = 0
	else:
		rings.append(nr)
		sel_ring = rings.size() - 1
	_changed()


func _delete_ring() -> void:
	if bp["rings"].size() <= 2:
		say("A hull needs at least 2 rings.")
		return
	_push_undo()
	bp["rings"].remove_at(sel_ring)
	sel_ring = clampi(sel_ring, 0, bp["rings"].size() - 1)
	sel_vert = -1
	_changed()


func _scale_ring(sx: float, sy: float) -> void:
	_push_undo()
	var c := ShipData.ring_center(_ring(sel_ring))
	for p in _ring(sel_ring)["pts"]:
		p[0] = c.x + (float(p[0]) - c.x) * sx
		p[1] = c.y + (float(p[1]) - c.y) * sy
	_changed()


func _round_ring() -> void:
	_push_undo()
	var r := _ring(sel_ring)
	var w := 0.0
	var h := 0.0
	for p in r["pts"]:
		w = maxf(w, absf(float(p[0])))
		h = maxf(h, absf(float(p[1])))
	var t := ShipData.make_ring(float(r["z"]), w, h)
	for i in ShipData.RING_PTS:
		r["pts"][i] = t["pts"][i]
	_changed()


func _scale_hull(s: float) -> void:
	_push_undo()
	ShipData.scale_ship(bp, s, false)
	_changed()
	_frame_camera()


# ------------------------------------------------------------------ module editing
func _add_module(type: String) -> void:
	_push_undo()
	var b := ShipData.hull_bounds(bp["rings"])
	var c := b.get_center()
	var def: Dictionary = ShipData.MODULES[type]
	var size: Vector3 = (def["min"] as Vector3) * 1.25
	var pos := c
	match type:
		"thruster":
			pos = Vector3(0, 0, b.end.z - size.z * 0.35)
		"commander_post":
			pos = Vector3(0, 0, b.position.z - size.z * 0.1)
		"barrel":
			pos = Vector3(0, 0, b.position.z)
		"turret_bay":
			pos = Vector3(0, b.end.y - size.y * 0.25, c.z)
	sel_mod = ShipData.add_module(bp, type, pos, size, 4 if type == "turret_bay" else 0, "kinetic")
	_changed()
	_maybe_auto_hull(sel_mod)
	_build_tools()


## Auto-Hull (GDD 2.1): push the hull outward so an internal module is fully enclosed, keeping X metres of clearance.
func _auto_hull_module(id: int) -> void:
	var m := ShipData.get_module(bp, id)
	if m.is_empty() or ShipData.MODULES[m["type"]]["kind"] != "internal":
		return
	var box := ShipData.module_box(m).grow(hull_clear)
	var rings: Array = bp["rings"]
	var first := _ring(0)
	var last := _ring(rings.size() - 1)
	if box.position.z < float(first["z"]):
		first["z"] = box.position.z
	if box.end.z > float(last["z"]):
		last["z"] = box.end.z
	var i0 := 0
	var i1 := rings.size() - 1
	for i in range(rings.size()):
		if float(rings[i]["z"]) <= box.position.z:
			i0 = i
	for i in range(rings.size() - 1, -1, -1):
		if float(rings[i]["z"]) >= box.end.z:
			i1 = i
	var corners := [Vector2(box.position.x, box.position.y), Vector2(box.end.x, box.position.y), Vector2(box.end.x, box.end.y), Vector2(box.position.x, box.end.y)]
	for i in range(i0, i1 + 1):
		var ring := _ring(i)
		var c := ShipData.ring_center(ring)
		for it in 90:
			var poly := PackedVector2Array()
			for p in ring["pts"]:
				poly.append(Vector2(float(p[0]), float(p[1])))
			var ok := true
			for cn in corners:
				if not Geometry2D.is_point_in_polygon(cn, poly):
					ok = false
			if ok:
				break
			for p in ring["pts"]:
				p[0] = c.x + (float(p[0]) - c.x) * 1.04
				p[1] = c.y + (float(p[1]) - c.y) * 1.04
	_changed()


func _maybe_auto_hull(id: int) -> void:
	if not auto_hull_on:
		return
	var m := ShipData.get_module(bp, id)
	if m.is_empty() or ShipData.MODULES[m["type"]]["kind"] != "internal":
		return
	if ShipData.placement_ok(bp, m) != "":
		_auto_hull_module(id)


func _set_size(ax: int, v: float) -> void:
	if _building_ui or sel_mod < 0:
		return
	var m := ShipData.get_module(bp, sel_mod)
	if m.is_empty():
		return
	_push_undo()
	var s := ShipData.v3(m["size"])
	s[ax] = maxf(v, (ShipData.MODULES[m["type"]]["min"] as Vector3)[ax])
	m["size"] = ShipData.a3(s)
	_changed()
	_maybe_auto_hull(sel_mod)


func _duplicate_module(mirrored: bool) -> void:
	var m := ShipData.get_module(bp, sel_mod)
	if m.is_empty():
		return
	_push_undo()
	if mirrored:
		if absf(ShipData.v3(m["pos"]).x) < 0.01:
			say("Move the module off the centre line first.")
			return
		sel_mod = ShipData.mirrored_copy(bp, sel_mod)
	else:
		sel_mod = ShipData.add_module(bp, m["type"], ShipData.v3(m["pos"]) + Vector3(snap * 4.0, 0, 0), ShipData.v3(m["size"]), int(m["dir"]), m["weapon"])
	_changed()
	_build_tools()


func _delete_module() -> void:
	if sel_mod < 0:
		return
	_push_undo()
	ShipData.remove_module(bp, sel_mod)
	sel_mod = -1
	_changed()
	_build_tools()


# ------------------------------------------------------------------ rebuild visuals
func _process(delta: float) -> void:
	_t += delta
	_update_cam()
	if dirty:
		dirty = false
		_rebuild()
	if dirty_since_save and fmod(_t, 4.0) < delta:
		Game.save_ship(bp, Game.DRAFTS)


func _rebuild() -> void:
	_auto_snap()
	var rings: Array = bp["rings"]
	hull_mi.mesh = ShipData.build_hull_mesh(rings)
	var c := ShipData.col(bp["color"])
	hull_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c.a = 1.0 if step == "Cosmetics" else (0.7 if step == "Hull" else 0.28)
	if view_mode == 1:
		c.a = minf(c.a, 0.2)
	hull_mat.albedo_color = c
	hull_mi.visible = view_mode != 2
	stats = ShipData.compute_stats(bp)
	issues = ShipData.validate(bp, {"max_tier": MAPS[map_idx]["tier"], "budget": budget})
	_rebuild_handles()
	_rebuild_modules()
	_rebuild_lines()
	_update_stats()
	if mod_list != null and is_instance_valid(mod_list) and step == "Modules":
		_fill_mod_list()


func _rebuild_handles() -> void:
	for c in handle_root.get_children():
		c.queue_free()
	if step != "Hull":
		return
	var hs := maxf(float(stats["longest"]) * 0.009, 0.05)
	var sm := SphereMesh.new()
	sm.radius = hs
	sm.height = hs * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	var rings: Array = bp["rings"]
	for r in range(rings.size()):
		for i in ShipData.RING_PTS:
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			var col := Color(0.85, 0.85, 0.9)
			if r == sel_ring:
				col = Color(1.0, 0.6, 0.2)
				if sel_vert == i:
					col = Color(1.0, 1.0, 0.2)
				elif sel_vert >= 0 and mirror and ShipData.mirror_idx(sel_vert) == i:
					col = Color(0.3, 1.0, 1.0)
			mat.albedo_color = col
			mi.material_override = mat
			mi.position = ShipData.ring_vertex(rings[r], i)
			handle_root.add_child(mi)


func _type_color(t: String) -> Color:
	return ShipData.MODULES[t]["color"]


func _rebuild_modules() -> void:
	for c in mod_root.get_children():
		c.queue_free()
	if step == "Hull" or step == "Cosmetics" or step == "Interior":
		return
	var bad := {}
	for i in issues:
		if int(i["mod"]) >= 0:
			bad[int(i["mod"])] = true
	for m in bp["modules"]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = ShipData.v3(m["size"])
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var col := _type_color(m["type"])
		if bad.has(int(m["id"])):
			col = col.lerp(Color(1, 0.1, 0.1), 0.6)
		col.a = 0.75 if int(m["id"]) == sel_mod or int(m["id"]) == link_from else 0.5
		mat.albedo_color = col
		mi.material_override = mat
		mi.position = ShipData.v3(m["pos"])
		mod_root.add_child(mi)


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	line_mesh.surface_set_color(col)
	line_mesh.surface_add_vertex(a)
	line_mesh.surface_set_color(col)
	line_mesh.surface_add_vertex(b)


func _box_lines(center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c: Array = []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				c.append(center + Vector3(x * h.x, y * h.y, z * h.z))
	for i in 8:
		for j in range(i + 1, 8):
			var d := (c[i] as Vector3) - (c[j] as Vector3)
			if (absf(d.x) > 0.0001 and absf(d.y) < 0.0001 and absf(d.z) < 0.0001) or (absf(d.y) > 0.0001 and absf(d.x) < 0.0001 and absf(d.z) < 0.0001) or (absf(d.z) > 0.0001 and absf(d.x) < 0.0001 and absf(d.y) < 0.0001):
				_line(c[i], c[j], col)


func _rebuild_lines() -> void:
	line_mesh.clear_surfaces()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var rings: Array = bp["rings"]
	var L := float(stats["longest"])
	if step == "Hull" or view_mode == 2:
		for r in range(rings.size()):
			var col := Color(1.0, 0.6, 0.2) if (r == sel_ring and step == "Hull") else Color(0.5, 0.55, 0.65)
			for i in ShipData.RING_PTS:
				_line(ShipData.ring_vertex(rings[r], i), ShipData.ring_vertex(rings[r], (i + 1) % ShipData.RING_PTS), col)
			if r < rings.size() - 1:
				for i in ShipData.RING_PTS:
					_line(ShipData.ring_vertex(rings[r], i), ShipData.ring_vertex(rings[r + 1], i), Color(0.35, 0.4, 0.5))
	if step == "Hull":
		var b := ShipData.hull_bounds(rings)
		var hy := b.size.y * 0.8
		var z0 := b.position.z - L * 0.05
		var z1 := b.end.z + L * 0.05
		var mc := Color(0.4, 0.9, 1.0, 0.6) if mirror else Color(0.3, 0.3, 0.3)
		_line(Vector3(0, -hy, z0), Vector3(0, hy, z0), mc)
		_line(Vector3(0, hy, z0), Vector3(0, hy, z1), mc)
		_line(Vector3(0, hy, z1), Vector3(0, -hy, z1), mc)
		_line(Vector3(0, -hy, z1), Vector3(0, -hy, z0), mc)
	if show_ruler:
		var rb := ShipData.hull_bounds(rings)
		_box_lines(rb.get_center(), rb.size, Color(0.3, 1.0, 0.5))
	_line(Vector3.ZERO, Vector3(L * 0.15, 0, 0), Color.RED)
	_line(Vector3.ZERO, Vector3(0, L * 0.15, 0), Color.GREEN)
	_line(Vector3.ZERO, Vector3(0, 0, -L * 0.15), Color(0.4, 0.5, 1.0))
	if step in ["Modules", "Links"]:
		for m in bp["modules"]:
			var p := ShipData.v3(m["pos"])
			var dv: Vector3 = ShipData.DIRS[int(m["dir"])]
			var half := ShipData.v3(m["size"])[ShipData.DIR_AXIS[int(m["dir"])]] * 0.5
			_line(p, p + dv * (half + L * 0.03), Color.WHITE)
		for l in bp["links"]:
			var a := ShipData.get_module(bp, int(l[0]))
			var b2 := ShipData.get_module(bp, int(l[1]))
			if not a.is_empty() and not b2.is_empty():
				_line(ShipData.v3(a["pos"]), ShipData.v3(b2["pos"]), Color(1.0, 0.9, 0.3))
		if sel_mod >= 0:
			var m := ShipData.get_module(bp, sel_mod)
			if not m.is_empty():
				var p := ShipData.v3(m["pos"])
				_box_lines(p, ShipData.v3(m["size"]), Color(1, 1, 0.2))
				_box_lines(p, ShipData.MODULES[m["type"]]["min"], Color(1, 0.15, 0.15))
	line_mesh.surface_end()


func _update_stats() -> void:
	var st := stats
	var ok := issues.is_empty()
	var t := "[b]Ship info[/b]\n[b]%s[/b]  -  [color=#8cf]%s[/color] (tier %d)\n" % [bp["name"], st["class"], st["tier"]]
	t += "Size  %.1f x %.1f x %.1f m  (snap %.2f m)\n" % [st["length"], st["beam"], st["height"], snap]
	t += "Mass  %.1f t   Hull armor %.2f\n" % [st["mass"], st["armor"]]
	var cost_ok := float(st["cost"]) <= budget
	t += "Cost  [color=%s]%.0f[/color] / %.0f pts\n" % ["#6f6" if cost_ok else "#f66", st["cost"], budget]
	var pwr_ok := float(st["power_idle"]) <= float(st["power_out"])
	t += "Power [color=%s]%.0f MW out, %.0f idle, %.0f peak[/color]\n" % ["#6f6" if pwr_ok else "#f66", st["power_out"], st["power_idle"], st["power_peak"]]
	t += "Accel fwd %.1f m/s2   RCS %.0f kN   gyro %.2f rad/s2\n" % [st["accel_fwd"], st["rcs"], st["gyro"]]
	var tri_ok := int(st["tris"]) <= int(st["tri_budget"])
	t += "Polys [color=%s]%d / %d[/color]\n" % ["#6f6" if tri_ok else "#f66", st["tris"], st["tri_budget"]]
	if not ok:
		for i in issues:
			t += "[color=#f88]- %s[/color]\n" % i["msg"]
	legal_lbl.text = "LEGAL - playable, can be saved" if ok else "NOT LEGAL (%d issue%s)" % [issues.size(), "" if issues.size() == 1 else "s"]
	legal_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.45) if ok else Color(1.0, 0.4, 0.35))
	stats_lbl.text = t


# ------------------------------------------------------------------ input
func _ray() -> Array:
	var mp := get_viewport().get_mouse_position()
	return [cam.project_ray_origin(mp), cam.project_ray_normal(mp)]


func _pick_handle() -> Vector2i:
	var mp := get_viewport().get_mouse_position()
	var best := Vector2i(-1, -1)
	var bd := 14.0
	var rings: Array = bp["rings"]
	for r in range(rings.size()):
		for i in ShipData.RING_PTS:
			var wp := ShipData.ring_vertex(rings[r], i)
			if cam.is_position_behind(wp):
				continue
			var d := cam.unproject_position(wp).distance_to(mp)
			if d < bd:
				bd = d
				best = Vector2i(r, i)
	return best


func _pick_module() -> int:
	var rr := _ray()
	var best := -1
	var bd := INF
	for m in bp["modules"]:
		var h = ShipData.module_box(m).intersects_ray(rr[0], rr[1])
		if h != null:
			var d: float = (rr[0] as Vector3).distance_to(h)
			if d < bd:
				bd = d
				best = int(m["id"])
	return best


func _drag_hit() -> Variant:
	var rr := _ray()
	var o: Vector3 = rr[0]
	var d: Vector3 = rr[1]
	if step == "Hull":
		if absf(d.z) < 0.12:
			return null
		var plane := Plane(Vector3(0, 0, 1), float(_ring(sel_ring)["z"]))
		return plane.intersects_ray(o, d)
	var m := ShipData.get_module(bp, sel_mod)
	if m.is_empty():
		return null
	var fwd := -cam.global_transform.basis.z
	var plane2 := Plane(fwd, ShipData.v3(m["pos"]).dot(fwd))
	return plane2.intersects_ray(o, d)


func _snapv(v: float) -> float:
	return roundf(v / snap) * snap


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = false
			panning = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = false
	elif event is InputEventMouseMotion:
		if orbiting:
			if Input.is_key_pressed(KEY_SHIFT):
				panning = true
			if panning or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
				var right := cam.global_transform.basis.x
				var up := cam.global_transform.basis.y
				cam_target += (-right * event.relative.x + up * event.relative.y) * cam_dist * 0.0016
			else:
				cam_yaw -= event.relative.x * 0.006
				cam_pitch = clampf(cam_pitch - event.relative.y * 0.006, -1.5, 1.5)
		elif panning:
			var right2 := cam.global_transform.basis.x
			var up2 := cam.global_transform.basis.y
			cam_target += (-right2 * event.relative.x + up2 * event.relative.y) * cam_dist * 0.0016
		elif dragging:
			_do_drag()


func _do_drag() -> void:
	var hit = _drag_hit()
	if hit == null:
		return
	var h: Vector3 = hit
	if step == "Hull":
		var nx := _snapv(h.x - drag_start.x + drag_orig.x)
		var ny := _snapv(h.y - drag_start.y + drag_orig.y)
		var dx := nx - drag_last.x
		var dy := ny - drag_last.y
		if absf(dx) < 1e-6 and absf(dy) < 1e-6:
			return
		drag_last = Vector3(nx, ny, 0)
		if sel_vert >= 0:
			_move_vertex_by(sel_ring, sel_vert, dx, dy)
		else:
			_move_ring_by(sel_ring, dx, dy)
		_changed()
	elif step == "Modules" and sel_mod >= 0:
		var m := ShipData.get_module(bp, sel_mod)
		var np := Vector3(_snapv(drag_orig.x + h.x - drag_start.x), _snapv(drag_orig.y + h.y - drag_start.y), _snapv(drag_orig.z + h.z - drag_start.z))
		if np != ShipData.v3(m["pos"]):
			m["pos"] = ShipData.a3(np)
			_changed()
			_maybe_auto_hull(sel_mod)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				cam_dist = maxf(cam_dist * 0.9, 0.5)
			MOUSE_BUTTON_WHEEL_DOWN:
				cam_dist = minf(cam_dist * 1.1, 1.0e7)
			MOUSE_BUTTON_RIGHT:
				orbiting = true
			MOUSE_BUTTON_MIDDLE:
				panning = true
			MOUSE_BUTTON_LEFT:
				_click()
	elif event is InputEventKey and event.pressed and not event.echo or (event is InputEventKey and event.pressed and event.echo):
		var k := event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_Z:
			_undo()
			return
		if k.ctrl_pressed and k.keycode == KEY_Y:
			_redo()
			return
		_nudge(k)


func _click() -> void:
	match step:
		"Hull":
			var h := _pick_handle()
			if h.x >= 0:
				sel_ring = h.x
				sel_vert = -1 if ring_mode else h.y
				_push_undo()
				var ring := _ring(sel_ring)
				var v := ShipData.ring_vertex(ring, h.y)
				var hit = _drag_hit()
				if hit != null:
					dragging = true
					drag_start = hit
					drag_last = Vector3(v.x, v.y, 0)
					drag_orig = Vector3(v.x, v.y, 0) if sel_vert >= 0 else Vector3(0, 0, 0)
					if sel_vert < 0:
						drag_last = Vector3(0, 0, 0)
				_changed(false)
		"Modules":
			var id := _pick_module()
			if id >= 0:
				sel_mod = id
				_push_undo()
				var m := ShipData.get_module(bp, id)
				var hit2 = _drag_hit()
				if hit2 != null:
					dragging = true
					drag_start = hit2
					drag_orig = ShipData.v3(m["pos"])
				_build_tools()
				_changed(false)
		"Links":
			var id2 := _pick_module()
			if id2 < 0:
				link_from = -1
			elif link_from < 0:
				link_from = id2
				say("Link from #%d - now click the target module." % id2)
			else:
				if id2 != link_from:
					_push_undo()
					if ShipData.add_link(bp, link_from, id2):
						say("Linked #%d - #%d" % [link_from, id2])
					else:
						say("Link not allowed between those module types (or already linked).")
				link_from = -1
				_build_tools()
			_changed(false)


func _nudge(k: InputEvent) -> void:
	var key := (k as InputEventKey).keycode
	var d := Vector3.ZERO
	match key:
		KEY_LEFT:
			d.x = -1
		KEY_RIGHT:
			d.x = 1
		KEY_UP:
			d.y = 1
		KEY_DOWN:
			d.y = -1
		KEY_PAGEUP:
			d.z = -1
		KEY_PAGEDOWN:
			d.z = 1
		KEY_DELETE:
			if step == "Modules":
				_delete_module()
			return
		_:
			return
	var amt := snap * (4.0 if (k as InputEventKey).shift_pressed else 1.0)
	d *= amt
	if _t - _last_undo_t > 0.6:
		_push_undo()
	_last_undo_t = _t
	if step == "Hull":
		if d.z != 0.0:
			_move_ring_z(sel_ring, d.z)
		elif sel_vert >= 0:
			_move_vertex_by(sel_ring, sel_vert, d.x, d.y)
		else:
			_move_ring_by(sel_ring, d.x, d.y)
		_changed()
	elif step == "Modules" and sel_mod >= 0:
		var m := ShipData.get_module(bp, sel_mod)
		m["pos"] = ShipData.a3(ShipData.v3(m["pos"]) + d)
		_changed()
	get_viewport().set_input_as_handled()
