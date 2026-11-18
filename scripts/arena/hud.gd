class_name Hud
extends CanvasLayer
## Cockpit command console (GDD 4.2). Layout follows the HUD mock-up: Panel 3 (modules) bottom-left,
## round Panel 4 (radar), Panel 2 (modes) bottom-centre, round Panel 5 (objectives/log), Panel 1 (status)
## bottom-right, and a big Sub Panel 2 that rises above Panel 2 when a mode is opened.
## Coordinates below are pixels in a 1600x900 reference viewport (stretch mode keeps them proportional).

const MODES := ["Movement", "Combat", "Defense", "Sensors", "Comms", "Crew Cmd", "Boarding", "Hangar/Fleet", "Power & Systems", "AI/Auto", "Tactical Map"]
const MODE_NEEDS := {
	"Defense": "a Defense Bay (not in this prototype)", "Comms": "a Communication Room / Dish (roadmap step 3+)",
	"Crew Cmd": "crew simulation (roadmap step 6)", "Boarding": "Breach Pods and Doors (roadmap step 6)",
	"Hangar/Fleet": "a Hangar (roadmap step 7)", "AI/Auto": "AI core options (roadmap step 3+)",
}
const CYAN := Color(0.45, 0.88, 1.0)
const STEEL := Color(0.075, 0.095, 0.135)
const SCREEN := Color(0.012, 0.035, 0.07)

var arena
var ship: Ship
var mode := "Movement"
var sub_open := false
var radar_zoom := 2000.0
var speed_limit := 150.0
var root: Control
var overlay: Control
var radar: Control
var sub_panel: ConsolePanel
var sub_body: VBoxContainer
var sub_text: RichTextLabel
var mod_list: VBoxContainer
var rows: Array = []
var lbl_status: Label
var lbl_target: Label
var lbl_warn: Label
var lbl_mode: Label
var btn_giveup: Button
var bar_hull: SegBar
var bar_power: SegBar
var bar_thr: SegBar
var bar_wpn: SegBar
var lbl_score: Label
var log_box: RichTextLabel
var ticker: Label
var flash_rect: ColorRect
var help: Label
var score_box: RichTextLabel
var panels: Array = []
var respawn_panel: ConsolePanel
var respawn_lbl: Label
var respawn_pick: OptionButton
var pause_panel: ConsolePanel
var _acc := 0.0
var _slow := 0.0
var _ticker_t := 0.0


# ================================================================== custom drawn widgets
class ConsolePanel extends Control:
	var title := ""
	var tag := "6000 SERIES"
	var body: VBoxContainer
	var inset := Vector4(16, 26, 16, 14)   # left, top, right, bottom of the inner screen

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 3)
		add_child(body)
		resized.connect(_layout)
		_layout()

	func _layout() -> void:
		body.position = Vector2(inset.x + 6, inset.y + 4)
		body.size = Vector2(maxf(size.x - inset.x - inset.z - 12, 10.0), maxf(size.y - inset.y - inset.w - 8, 10.0))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, STEEL)
		draw_rect(r, Color(0.3, 0.4, 0.52), false, 2.0)
		draw_rect(r.grow(-4.0), Color(0.15, 0.2, 0.28), false, 1.0)
		draw_line(Vector2(6, 2), Vector2(size.x - 6, 2), Color(0.5, 0.62, 0.75, 0.7), 1.0)
		var s := Rect2(Vector2(inset.x, inset.y), size - Vector2(inset.x + inset.z, inset.y + inset.w))
		draw_rect(s, SCREEN)
		var y := s.position.y
		while y < s.end.y:
			draw_line(Vector2(s.position.x, y), Vector2(s.end.x, y), Color(0.15, 0.4, 0.6, 0.07), 1.0)
			y += 4.0
		draw_rect(s, Color(0.2, 0.6, 0.85, 0.85), false, 1.5)
		for p in [Vector2(8, 8), Vector2(size.x - 8, 8), Vector2(8, size.y - 8), Vector2(size.x - 8, size.y - 8)]:
			draw_circle(p, 3.5, Color(0.38, 0.44, 0.52))
			draw_circle(p, 1.6, Color(0.1, 0.12, 0.16))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(inset.x + 2, 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.82, 1.0))
		draw_string(font, Vector2(size.x - 100, 17), tag, HORIZONTAL_ALIGNMENT_RIGHT, 84, 8, Color(0.4, 0.5, 0.62))


class RoundPanel extends Control:
	var title := ""
	var body: Control
	var screen_r := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		body = Control.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(body)
		resized.connect(_layout)

	func _layout() -> void:
		screen_r = minf(size.x, size.y) * 0.5 - 20.0
		var sq := screen_r * 1.4
		body.position = size * 0.5 - Vector2(sq, sq) * 0.5
		body.size = Vector2(sq, sq)

	func _draw() -> void:
		var c := size * 0.5
		var R := minf(size.x, size.y) * 0.5 - 2.0
		_layout()
		draw_circle(c, R, STEEL)
		draw_arc(c, R, 0, TAU, 96, Color(0.3, 0.4, 0.52), 2.0)
		draw_arc(c, R - 5.0, 0, TAU, 96, Color(0.15, 0.2, 0.28), 1.0)
		for i in 72:
			var a := float(i) * TAU / 72.0
			var d := Vector2(cos(a), sin(a))
			var len := 9.0 if i % 6 == 0 else 5.0
			draw_line(c + d * (R - 8.0 - len), c + d * (R - 8.0), Color(0.35, 0.75, 0.95, 0.8 if i % 6 == 0 else 0.45), 1.0)
		draw_circle(c, screen_r, SCREEN)
		draw_arc(c, screen_r, 0, TAU, 96, Color(0.2, 0.6, 0.85, 0.9), 1.5)
		for p in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
			draw_circle(c + p * (R - 3.0), 3.0, Color(0.38, 0.44, 0.52))
		draw_string(ThemeDB.fallback_font, Vector2(c.x - 60, size.y - 4), title, HORIZONTAL_ALIGNMENT_CENTER, 120, 9, Color(0.5, 0.82, 1.0))


class SegBar extends Control:
	var value := 0.0
	var label := ""
	var col := Color(0.45, 0.88, 1.0)
	var warn := false
	var cells := 14

	func _draw() -> void:
		var h := size.y - 14.0
		var ch := h / float(cells)
		var lit_col := col
		if warn:
			lit_col = Color(1.0, 0.3, 0.25) if value < 0.25 else (Color(1.0, 0.75, 0.25) if value < 0.5 else col)
		draw_rect(Rect2(0, 0, size.x, h), Color(0.02, 0.05, 0.09))
		for i in cells:
			var lit := float(i) / float(cells) < value - 0.001
			var y := h - float(i + 1) * ch
			draw_rect(Rect2(3, y + 1.0, size.x - 6, ch - 2.0), lit_col if lit else Color(0.06, 0.12, 0.18))
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y - 2), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color(0.6, 0.85, 1.0))


class Overlay extends Control:
	var hud: Hud

	func _draw() -> void:
		if hud == null or hud.arena == null or hud.ship == null:
			return
		var cam: Camera3D = hud.arena.rig.cam
		var font := ThemeDB.fallback_font
		if hud.arena.rig.first_person:
			var c := size * 0.5
			var col := Color(0.6, 1.0, 0.8, 0.8)
			draw_arc(c, 14.0, 0, TAU, 32, col, 1.5)
			draw_line(c + Vector2(-26, 0), c + Vector2(-8, 0), col, 1.5)
			draw_line(c + Vector2(26, 0), c + Vector2(8, 0), col, 1.5)
			draw_line(c + Vector2(0, -26), c + Vector2(0, -8), col, 1.5)
		for s in get_tree().get_nodes_in_group("ships"):
			var o := s as Ship
			if o == hud.ship:
				continue
			var wp := o.global_position
			if cam.is_position_behind(wp):
				continue
			var p := cam.unproject_position(wp)
			var enemy := o.team != hud.ship.team
			var col2 := Color(1, 0.35, 0.3) if enemy else Color(0.4, 0.7, 1.0)
			var locked := hud.ship.target == o
			var r := 11.0 if locked else 6.0
			draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), col2, 2.0 if locked else 1.0)
			var d := hud.ship.global_position.distance_to(wp)
			draw_string(font, p + Vector2(r + 4, 4), "%s %s  %dm" % ["LOCK" if locked else "", o.name, int(d)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col2)


class RadarView extends Control:
	var hud: Hud

	func _draw() -> void:
		var c := size * 0.5
		var R := minf(size.x, size.y) * 0.5 - 2.0
		for k in [0.33, 0.66, 1.0]:
			draw_arc(c, R * k, 0, TAU, 48, Color(0.2, 0.65, 0.85, 0.45), 1.0)
		draw_line(c + Vector2(-R, 0), c + Vector2(R, 0), Color(0.2, 0.65, 0.85, 0.3))
		draw_line(c + Vector2(0, -R), c + Vector2(0, R), Color(0.2, 0.65, 0.85, 0.3))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 6), c + Vector2(-5, 6)]), Color(0.7, 1.0, 1.0))
		if hud == null or hud.ship == null:
			return
		var me := hud.ship
		var rng := minf(hud.radar_zoom, me.radar_range())
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(c.x - 50, size.y - 8), "%d m%s" % [int(rng), "" if me.radar_range() > 1000.0 else " DEGRADED"], HORIZONTAL_ALIGNMENT_CENTER, 100, 10, Color(0.5, 0.9, 1.0))
		for group in ["ships", "wrecks"]:
			for s in get_tree().get_nodes_in_group(group):
				var o := s as Ship
				if o == me:
					continue
				var l := me.to_local(o.global_position)
				if l.length() > rng:
					continue
				var p := c + Vector2(l.x, l.z) / rng * R
				var col := Color(0.5, 0.5, 0.5)
				if group == "ships":
					col = Color(1, 0.3, 0.3) if o.team != me.team else Color(0.4, 0.7, 1.0)
				draw_circle(p, 4.0 if o == me.target else 3.0, col)
				draw_line(p, p + Vector2(0, -clampf(l.y / rng * R, -R, R)), col, 1.0)
				if o == me.target:
					draw_arc(p, 7.0, 0, TAU, 16, Color(1, 1, 0.4), 1.5)


# ================================================================== theme + helpers
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 12
	var txt := Color(0.72, 0.93, 1.0)
	for cls in ["Label", "Button", "CheckButton", "OptionButton", "RichTextLabel"]:
		t.set_color("font_color", cls, txt)
	t.set_color("default_color", "RichTextLabel", txt)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(0.02, 0.1, 0.15))
	for st in [["normal", Color(0.07, 0.12, 0.18)], ["hover", Color(0.12, 0.22, 0.32)], ["pressed", Color(0.4, 0.85, 1.0)], ["disabled", Color(0.05, 0.07, 0.1)]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.border_color = Color(0.25, 0.6, 0.85)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		t.set_stylebox(st[0], "Button", sb)
		t.set_stylebox(st[0], "OptionButton", sb)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.07, 0.11)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.15, 0.35, 0.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.8, 1.0)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	return t


func _label(text: String, parent: Control, size := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _button(text: String, parent: Control, cb: Callable, size := 11) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _rect_panel(title: String, x: float, y: float, w: float, h: float) -> ConsolePanel:
	var p := ConsolePanel.new()
	p.title = title
	p.anchor_left = x / 1600.0
	p.anchor_right = (x + w) / 1600.0
	p.anchor_top = y / 900.0
	p.anchor_bottom = (y + h) / 900.0
	root.add_child(p)
	panels.append(p)
	return p


func _round_panel(title: String, cx: float, cy: float, d: float) -> RoundPanel:
	var p := RoundPanel.new()
	p.title = title
	p.anchor_left = cx / 1600.0
	p.anchor_right = cx / 1600.0
	p.anchor_top = cy / 900.0
	p.anchor_bottom = cy / 900.0
	p.offset_left = -d * 0.5
	p.offset_right = d * 0.5
	p.offset_top = -d * 0.5
	p.offset_bottom = d * 0.5
	root.add_child(p)
	panels.append(p)
	return p


func _seg(label: String, parent: Control, col := CYAN) -> SegBar:
	var b := SegBar.new()
	b.label = label
	b.col = col
	b.custom_minimum_size = Vector2(32, 120)
	parent.add_child(b)
	return b


# ================================================================== build
func setup(a) -> void:
	arena = a
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	overlay = Overlay.new()
	(overlay as Overlay).hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	# --- Sub Panel 2 (drawn first so it sits behind the other panels, like the mock-up)
	sub_panel = _rect_panel("SUB PANEL 2", 411, 290, 756, 530)
	sub_body = sub_panel.body
	sub_panel.visible = false

	# --- Panel 4 (round radar) and Panel 5 (round objectives/log) behind the rectangular panels
	var p4 := _round_panel("PANEL 4 - RADAR", 475, 650, 312)
	radar = RadarView.new()
	(radar as RadarView).hud = self
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.position = Vector2(156 - 136, 156 - 136)
	radar.size = Vector2(272, 272)
	p4.add_child(radar)
	var p5 := _round_panel("PANEL 5 - OBJECTIVES", 1094, 638, 312)
	var vb5 := VBoxContainer.new()
	vb5.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb5.position = Vector2(52, 52)
	vb5.size = Vector2(208, 208)
	p5.add_child(vb5)
	lbl_score = _label("", vb5, 10)
	lbl_score.autowrap_mode = TextServer.AUTOWRAP_WORD
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_size_override("normal_font_size", 10)
	log_box.add_theme_font_size_override("bold_font_size", 10)
	vb5.add_child(log_box)

	# --- Panel 3 (modules), Panel 2 (modes), Panel 1 (status)
	var p3 := _rect_panel("PANEL 3 - MODULES", 66, 681, 326, 219)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(290, 170)
	mod_list = VBoxContainer.new()
	mod_list.add_theme_constant_override("separation", 1)
	sc.add_child(mod_list)
	p3.body.add_child(sc)

	var p2 := _rect_panel("PANEL 2 - MODE SELECTION", 594, 611, 406, 289)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	p2.body.add_child(grid)
	for m in MODES:
		var mm: String = m
		var b := _button(mm, grid, func(): set_mode(mm), 10)
		b.custom_minimum_size = Vector2(112, 30)
	lbl_mode = _label("", p2.body, 11)

	var p1 := _rect_panel("PANEL 1 - SHIP STATUS", 1205, 653, 327, 247)
	var hb1 := HBoxContainer.new()
	p1.body.add_child(hb1)
	var gauges := HBoxContainer.new()
	gauges.add_theme_constant_override("separation", 2)
	hb1.add_child(gauges)
	bar_hull = _seg("HULL", gauges, Color(0.4, 1.0, 0.6))
	bar_hull.warn = true
	bar_power = _seg("PWR", gauges, Color(1.0, 0.85, 0.3))
	bar_thr = _seg("THR", gauges)
	bar_wpn = _seg("WPN", gauges, Color(1.0, 0.5, 0.4))
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(150, 0)
	hb1.add_child(side)
	lbl_status = _label("", side, 11)
	lbl_target = _label("Target: none", side, 11)
	lbl_target.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl_warn = _label("", side, 11)
	lbl_warn.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl_warn.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	btn_giveup = _button("Give up", side, func(): arena.give_up())
	btn_giveup.visible = false

	# --- extras: scoreboard (top right), test range tools, ticker, help
	var sb := PanelContainer.new()
	var sbs := StyleBoxFlat.new()
	sbs.bg_color = Color(0.02, 0.03, 0.05, 0.7)
	sb.add_theme_stylebox_override("panel", sbs)
	sb.anchor_left = 1.0
	sb.anchor_right = 1.0
	sb.offset_left = -210
	sb.offset_right = 0
	sb.offset_top = 0
	sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sb)
	score_box = RichTextLabel.new()
	score_box.bbcode_enabled = true
	score_box.fit_content = true
	score_box.custom_minimum_size = Vector2(200, 20)
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sb.add_child(score_box)
	if arena.mode == "sandbox":
		_build_sandbox_panel()
	ticker = Label.new()
	ticker.anchor_left = 0.5
	ticker.anchor_right = 0.5
	ticker.offset_left = -300.0
	ticker.offset_right = 300.0
	ticker.offset_top = 8.0
	ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ticker.add_theme_font_size_override("font_size", 16)
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ticker)
	help = Label.new()
	help.anchor_left = 0.5
	help.anchor_right = 0.5
	help.offset_left = -330.0
	help.offset_right = 330.0
	help.offset_top = 34.0
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.6, 0.75, 0.85, 0.75))
	help.text = "W/S A/D Space/C thrust | Q/E roll | arrows or mouse (FP) pitch-yaw | LMB fire | RMB-drag orbit, wheel zoom\nV view | Tab free cursor | T lock | X assist | Z brake | Esc pause"
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 0, 0, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	_build_respawn()
	_build_pause()
	_refresh_mode_label()


func _build_sandbox_panel() -> void:
	var p := _rect_panel("TEST RANGE", 8, 8, 300, 205)
	var vb := p.body
	var ships: Array = Game.all_ships()
	var row := HBoxContainer.new()
	vb.add_child(row)
	var pick := OptionButton.new()
	for s in ships:
		pick.add_item("%s%s" % [s["name"], "" if s["source"] == "premade" else " *"])
	row.add_child(pick)
	var beh := OptionButton.new()
	for b in ["Static", "Drift", "Spin", "Sentry", "Hunter"]:
		beh.add_item(b)
	row.add_child(beh)
	var r2 := HBoxContainer.new()
	vb.add_child(r2)
	_button("Spawn dummy", r2, func(): arena.spawn_dummy(ships[pick.selected]["bp"], ["static", "drift", "spin", "sentry", "hunter"][beh.selected]), 10)
	_button("Repair me", r2, func(): arena.repair_player(), 10)
	var tr := HBoxContainer.new()
	vb.add_child(tr)
	var cb := CheckButton.new()
	cb.text = "Shoot my hull"
	cb.add_theme_font_size_override("font_size", 10)
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on: bool): arena.test_shot_on = on)
	tr.add_child(cb)
	var wp := OptionButton.new()
	for w in ShipData.WEAPONS:
		wp.add_item(w)
	wp.item_selected.connect(func(i: int): arena.test_shot_weapon = ShipData.WEAPONS[i])
	tr.add_child(wp)
	_label("Click your hull (commander view) to\nfire the chosen round at it.", vb, 9)


func _build_respawn() -> void:
	respawn_panel = ConsolePanel.new()
	respawn_panel.title = "RESPAWN"
	respawn_panel.anchor_left = 0.5
	respawn_panel.anchor_right = 0.5
	respawn_panel.anchor_top = 0.5
	respawn_panel.anchor_bottom = 0.5
	respawn_panel.offset_left = -170
	respawn_panel.offset_right = 170
	respawn_panel.offset_top = -80
	respawn_panel.offset_bottom = 80
	respawn_panel.visible = false
	root.add_child(respawn_panel)
	panels.append(respawn_panel)
	respawn_lbl = _label("", respawn_panel.body, 14)
	respawn_pick = OptionButton.new()
	respawn_panel.body.add_child(respawn_pick)
	_button("Respawn now", respawn_panel.body, func(): arena.respawn_now(), 12)


func _build_pause() -> void:
	pause_panel = ConsolePanel.new()
	pause_panel.title = "PAUSED"
	pause_panel.anchor_left = 0.5
	pause_panel.anchor_right = 0.5
	pause_panel.anchor_top = 0.5
	pause_panel.anchor_bottom = 0.5
	pause_panel.offset_left = -150
	pause_panel.offset_right = 150
	pause_panel.offset_top = -90
	pause_panel.offset_bottom = 90
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.visible = false
	root.add_child(pause_panel)
	panels.append(pause_panel)
	_button("Resume", pause_panel.body, func(): arena.set_paused(false), 14)
	var back := "Back to ship editor" if Game.session.get("return_scene", "") == "res://scenes/ship_editor.tscn" else "Back to main menu"
	_button(back, pause_panel.body, func(): arena.leave(), 14)


func show_pause(on: bool) -> void:
	pause_panel.visible = on


func show_respawn(on: bool, ships: Array = []) -> void:
	respawn_panel.visible = on
	if on and respawn_pick.item_count == 0:
		for s in ships:
			respawn_pick.add_item(s["name"])


func bind_ship(s: Ship) -> void:
	ship = s
	for c in mod_list.get_children():
		c.queue_free()
	rows.clear()
	var order := ["commander_post", "generator", "engine_room", "thruster", "turret_bay", "barrel", "radar_room"]
	var sorted := s.mods.duplicate()
	sorted.sort_custom(func(a, b): return order.find(a["type"]) < order.find(b["type"]))
	for m in sorted:
		var hb := HBoxContainer.new()
		var nm := _label("%s #%d" % [m["label"], m["id"]], hb, 10)
		nm.custom_minimum_size = Vector2(120, 0)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(72, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		hb.add_child(bar)
		var pw := _label("", hb, 10)
		pw.custom_minimum_size = Vector2(44, 0)
		mod_list.add_child(hb)
		rows.append({"m": m, "bar": bar, "pw": pw, "nm": nm})


# ================================================================== modes and sub panel
func set_mode(m: String) -> void:
	if sub_open and mode == m:
		sub_open = false
		sub_panel.visible = false
		_refresh_mode_label()
		return
	mode = m
	sub_open = true
	sub_panel.visible = true
	sub_panel.title = "SUB PANEL 2 - " + m.to_upper()
	sub_panel.queue_redraw()
	for c in sub_body.get_children():
		c.queue_free()
	sub_text = null
	if MODE_NEEDS.has(m):
		_label("This mode needs %s." % MODE_NEEDS[m], sub_body, 14)
		_label("It is listed because the console always shows every mode\n(design doc 4.2); it stays inactive until that system exists.", sub_body, 11)
		_refresh_mode_label()
		return
	match m:
		"Movement", "Tactical Map":
			_sub_movement()
		"Combat":
			_sub_combat()
		"Sensors":
			_sub_sensors()
		"Power & Systems":
			_sub_power()
	_refresh_mode_label()


func _refresh_mode_label() -> void:
	if lbl_mode:
		lbl_mode.text = "Mode: %s%s   (click again to close)" % [mode, "" if sub_open else " (closed)"]


func _make_sub_text() -> void:
	sub_text = RichTextLabel.new()
	sub_text.bbcode_enabled = true
	sub_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_text.custom_minimum_size = Vector2(0, 150)
	sub_text.add_theme_font_size_override("normal_font_size", 12)
	sub_body.add_child(sub_text)


func _sub_movement() -> void:
	var top := HBoxContainer.new()
	sub_body.add_child(top)
	var ck := CheckButton.new()
	ck.text = "Assisted flight (X)"
	ck.button_pressed = arena.player.assist if arena.player else true
	ck.focus_mode = Control.FOCUS_NONE
	ck.toggled.connect(func(on: bool): arena.set_assist(on))
	top.add_child(ck)
	var g := GridContainer.new()
	g.columns = 3
	sub_body.add_child(g)
	for pair in [["Hold position", "hold"], ["Brake (Z)", "brake"], ["Face target", "face"], ["Drive toward target", "drive"], ["Orbit target", "orbit"], ["Manual control", "none"]]:
		var k: String = pair[1]
		var b := _button(pair[0], g, func(): arena.set_order(k), 12)
		b.custom_minimum_size = Vector2(150, 34)
	var r2 := HBoxContainer.new()
	sub_body.add_child(r2)
	_label("Speed limiter", r2, 12)
	var val := _label("%d m/s" % int(speed_limit), r2, 12)
	var sl := HSlider.new()
	sl.min_value = 20
	sl.max_value = 800
	sl.value = speed_limit
	sl.custom_minimum_size = Vector2(380, 18)
	sl.value_changed.connect(func(v: float): speed_limit = v; val.text = "%d m/s" % int(v))
	r2.add_child(sl)
	_make_sub_text()


func _sub_combat() -> void:
	var row := HBoxContainer.new()
	sub_body.add_child(row)
	_button("Lock target (T)", row, func(): arena.lock_target(), 12)
	_button("Clear lock", row, func(): arena.clear_lock(), 12)
	_label("  LMB fires every linked barrel; with a lock, barrels lead the target.", sub_body, 11)
	_make_sub_text()


func _sub_sensors() -> void:
	var row := HBoxContainer.new()
	sub_body.add_child(row)
	_button("Zoom +", row, func(): radar_zoom = maxf(250.0, radar_zoom * 0.5), 12)
	_button("Zoom -", row, func(): radar_zoom = minf(8000.0, radar_zoom * 2.0), 12)
	_label("  Range is limited by the Radar Room (400 m without one).", row, 11)
	_make_sub_text()


func _sub_power() -> void:
	var row := HBoxContainer.new()
	sub_body.add_child(row)
	for k in ["thrusters", "weapons", "radar", "gyro"]:
		var kk: String = k
		var ck := CheckButton.new()
		ck.text = kk
		ck.focus_mode = Control.FOCUS_NONE
		ck.button_pressed = bool(arena.player.switches[kk]) if arena.player else true
		ck.toggled.connect(func(on: bool): arena.player.switches[kk] = on)
		row.add_child(ck)
	_label("Power goes to the modules closest to a Generator first.", sub_body, 11)
	_make_sub_text()


func _refresh_sub() -> void:
	if not sub_open or sub_text == null or ship == null or not is_instance_valid(ship):
		return
	var t := ""
	match mode:
		"Movement", "Tactical Map":
			var vl := ship.global_transform.basis.inverse() * ship.linear_velocity
			t += "Velocity (local)  right %.1f   up %.1f   fwd %.1f  m/s\n" % [vl.x, vl.y, -vl.z]
			t += "Speed %.1f m/s    Angular %.2f rad/s\n" % [ship.linear_velocity.length(), ship.angular_velocity.length()]
			t += "Thrust capacity  fwd %.0f   back %.0f   right %.0f   left %.0f   up %.0f   down %.0f kN\n" % [ship.caps[0], ship.caps[1], ship.caps[2], ship.caps[3], ship.caps[4], ship.caps[5]]
			t += "RCS %.0f kN (10%% of best thruster vector)   Mass %.0f t\n" % [ship.rcs_cap, ship.mass]
			t += "Order: [color=#ffe680]%s[/color]" % arena.order
		"Combat":
			for m in ship.mods_of("barrel"):
				var ws: Dictionary = m["ws"]
				var state := "[color=#ff6060]OFFLINE[/color]"
				if ship.module_online(m):
					state = "[color=#80ff90]READY[/color]" if float(m["cool"]) <= 0.0 else "[color=#ffd060]CYCLING[/color]"
				var ammo := "" if int(m["ammo"]) < 0 else "  ammo %d" % int(m["ammo"])
				t += "Barrel #%d  %s  dmg %.0f  pen %.2f  %s%s\n" % [m["id"], String(ws["kind"]).to_upper(), ws["damage"], ws["pen"], state, ammo]
			if ship.target != null and is_instance_valid(ship.target) and ship.target.alive:
				t += "\nTarget: [color=#ffe680]%s[/color]  %d m  hull %d%%" % [ship.target.name, int(ship.global_position.distance_to(ship.target.global_position)), int(ship.target.hull_hp / ship.target.hull_hp_max * 100.0)]
		"Sensors":
			var contacts: Array = []
			for s in get_tree().get_nodes_in_group("ships"):
				var o := s as Ship
				if o != ship:
					contacts.append(o)
			contacts.sort_custom(func(a, b): return ship.global_position.distance_to(a.global_position) < ship.global_position.distance_to(b.global_position))
			t += "Contacts (radar range %d m)\n" % int(minf(radar_zoom, ship.radar_range()))
			for o in contacts:
				var d := ship.global_position.distance_to(o.global_position)
				var l := ship.to_local(o.global_position)
				var col := "#ff6060" if o.team != ship.team else "#70b0ff"
				t += "[color=%s]%s[/color]  %s  %d m  bearing %d  hull %d%%\n" % [col, o.name, o.stats["class"], int(d), int(rad_to_deg(atan2(l.x, -l.z))), int(o.hull_hp / o.hull_hp_max * 100.0)]
		"Power & Systems":
			t += "Supply %.0f MW   Demand %.0f MW   Satisfied %d%%\n\n" % [ship.power_supply, ship.power_demand, int(ship.power_frac * 100.0)]
			var consumers: Array = []
			for m in ship.mods:
				if float(m["demand"]) > 0.0:
					consumers.append(m)
			consumers.sort_custom(func(a, b): return float(a["prio"]) < float(b["prio"]))
			for m in consumers:
				t += "%s #%d   %.1f MW   %d%%\n" % [m["label"], m["id"], m["demand"], int(float(m["frac"]) * 100.0)]
	sub_text.text = t


# ================================================================== feedback
func log_msg(t: String) -> void:
	log_box.append_text(t + "\n")


func say(t: String, color := Color.WHITE) -> void:
	ticker.text = t
	ticker.add_theme_color_override("font_color", color)
	ticker.modulate.a = 1.0
	_ticker_t = 5.0


func flash() -> void:
	flash_rect.color = Color(1, 0, 0, 0.3)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.5)


func is_mouse_over_ui() -> bool:
	var mp := root.get_viewport().get_mouse_position()
	for p in panels:
		var c := p as Control
		if not c.is_visible_in_tree():
			continue
		if c is RoundPanel:
			if mp.distance_to(c.get_global_rect().get_center()) < c.size.x * 0.5:
				return true
		elif c.get_global_rect().has_point(mp):
			return true
	return false


func _process(delta: float) -> void:
	overlay.queue_redraw()
	radar.queue_redraw()
	if _ticker_t > 0.0:
		_ticker_t -= delta
		if _ticker_t < 1.0:
			ticker.modulate.a = _ticker_t
	_acc += delta
	if _acc < 0.2 or ship == null or not is_instance_valid(ship):
		return
	_acc = 0.0
	_slow += 1.0
	for r in rows:
		var m: Dictionary = r["m"]
		(r["bar"] as ProgressBar).value = float(m["hp"]) / float(m["max"]) * 100.0
		var nm: Label = r["nm"]
		var pw: Label = r["pw"]
		if not m["alive"]:
			nm.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			pw.text = "DEAD"
		else:
			nm.remove_theme_color_override("font_color")
			var extra := ""
			if m["type"] == "barrel" and int(m["ammo"]) >= 0:
				extra = " x%d" % int(m["ammo"])
			pw.text = ("%d%%" % int(float(m["frac"]) * 100.0) if float(m["demand"]) > 0.0 else "-") + extra
	var f := ship.forward()
	lbl_status.text = "%s [%s]\nSpd %.0f m/s\nHdg %.0f  Pit %.0f\n%s | %s" % [ship.name, ship.stats["class"], ship.linear_velocity.length(), rad_to_deg(atan2(f.x, -f.z)), rad_to_deg(asin(clampf(f.y, -1, 1))), "ASSIST" if ship.assist else "MANUAL", "FP" if arena.rig.first_person else "CMDR"]
	bar_hull.value = ship.hull_hp / ship.hull_hp_max
	for b in [bar_hull, bar_power, bar_thr, bar_wpn]:
		(b as SegBar).queue_redraw()
	bar_power.value = ship.power_frac
	var th_d := 0.0
	var th_p := 0.0
	var wp_d := 0.0
	var wp_p := 0.0
	for m in ship.mods:
		if m["type"] == "thruster":
			th_p += float(m["ms"]["peak"])
			th_d += float(m["demand"])
		elif m["type"] == "barrel":
			wp_p += float(m["ms"]["peak"])
			wp_d += float(m["demand"])
	bar_thr.value = th_d / th_p if th_p > 0.0 else 0.0
	bar_wpn.value = wp_d / wp_p if wp_p > 0.0 else 0.0
	if ship.target != null and is_instance_valid(ship.target) and ship.target.alive:
		lbl_target.text = "TGT %s\n%d m  hull %d%%" % [ship.target.name, int(ship.global_position.distance_to(ship.target.global_position)), int(ship.target.hull_hp / ship.target.hull_hp_max * 100.0)]
	else:
		lbl_target.text = "TGT none"
	var stuck := ship.alive and not ship.can_move()
	lbl_warn.text = "NO THRUST - keep firing or give up." if stuck else ("SHIP DESTROYED" if not ship.alive else "")
	btn_giveup.visible = stuck
	lbl_score.text = arena.score_text()
	_refresh_sub()
	if int(_slow) % 2 == 0:
		_refresh_scoreboard()


func _refresh_scoreboard() -> void:
	var t := "[b]Name[/b]\n"
	for s in get_tree().get_nodes_in_group("ships"):
		var o := s as Ship
		var col := "#ffe680" if o == ship else ("#70b0ff" if o.team == ship.team else "#ff7070")
		t += "[color=%s]%s[/color]\n" % [col, o.name]
	for s in get_tree().get_nodes_in_group("wrecks"):
		t += "[color=#777777][s]%s[/s][/color]\n" % (s as Ship).name
	score_box.text = t
