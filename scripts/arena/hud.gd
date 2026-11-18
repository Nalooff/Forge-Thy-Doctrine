class_name Hud
extends CanvasLayer
## Command console (GDD 4.2): ship status, module management, tactical radar, mode selection with
## sub-panels, objectives/log. Every mode is listed; modes that need systems outside the prototype
## say so instead of pretending.

const MODES := ["Movement", "Combat", "Defense", "Sensors", "Comms", "Crew Cmd", "Boarding", "Hangar/Fleet", "Power & Systems", "AI/Auto", "Tactical Map"]
const MODE_NEEDS := {
	"Defense": "Defense Bay (not in this prototype)", "Comms": "Communication Room/Dish (roadmap step 3+)",
	"Crew Cmd": "Crew simulation (roadmap step 6)", "Boarding": "Breach Pods/Doors (roadmap step 6)",
	"Hangar/Fleet": "Hangar (roadmap step 7)", "AI/Auto": "AI core options (roadmap step 3+)", "Tactical Map": "Sub-view of Movement for now: use the radar zoom in Sensors",
}

var arena
var ship: Ship
var mode := "Movement"
var radar_zoom := 2000.0
var speed_limit := 150.0
var root: Control
var overlay: Control
var radar: Control
var sub: VBoxContainer
var mod_list: VBoxContainer
var rows: Array = []
var lbl_status: Label
var bar_hull: ProgressBar
var bar_power: ProgressBar
var lbl_power: Label
var lbl_target: Label
var lbl_warn: Label
var btn_giveup: Button
var lbl_score: Label
var log_box: RichTextLabel
var ticker: Label
var flash_rect: ColorRect
var help: Label
var panels: Array = []
var respawn_panel: PanelContainer
var respawn_lbl: Label
var respawn_pick: OptionButton
var pause_panel: PanelContainer
var _acc := 0.0
var _ticker_t := 0.0
var _ships_cache: Array = []


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
		var R := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, R, Color(0.02, 0.09, 0.06, 0.85))
		for k in [0.33, 0.66, 1.0]:
			draw_arc(c, R * k, 0, TAU, 48, Color(0.2, 0.7, 0.4, 0.5), 1.0)
		draw_line(c + Vector2(-R, 0), c + Vector2(R, 0), Color(0.2, 0.7, 0.4, 0.3))
		draw_line(c + Vector2(0, -R), c + Vector2(0, R), Color(0.2, 0.7, 0.4, 0.3))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 6), c + Vector2(-5, 6)]), Color(0.6, 1.0, 0.8))
		if hud == null or hud.ship == null:
			return
		var me := hud.ship
		var rng := minf(hud.radar_zoom, me.radar_range())
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(6, size.y - 6), "%d m%s" % [int(rng), "" if me.radar_range() > 1000.0 else "  DEGRADED"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 1, 0.7))
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


func _style(alpha := 0.78) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09, alpha)
	sb.border_color = Color(0.25, 0.5, 0.7, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _panel(title: String, parent: Control) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style())
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(pc)
	panels.append(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	var l := Label.new()
	l.text = title
	l.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	l.add_theme_font_size_override("font_size", 13)
	vb.add_child(l)
	return vb


func _label(text: String, parent: Control, size := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _button(text: String, parent: Control, cb: Callable, size := 12) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _column(left: bool, width: float, top: float, bottom: float) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.anchor_left = 0.0 if left else 1.0
	vb.anchor_right = 0.0 if left else 1.0
	vb.offset_left = 8.0 if left else -width - 8.0
	vb.offset_right = width + 8.0 if left else -8.0
	vb.offset_top = top
	vb.anchor_bottom = 1.0
	vb.offset_bottom = -bottom
	vb.add_theme_constant_override("separation", 6)
	root.add_child(vb)
	return vb


func setup(a) -> void:
	arena = a
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	overlay = Overlay.new()
	(overlay as Overlay).hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 0, 0, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)

	# left column: Panel 3 (modules) + Panel 4 (radar)
	var left := _column(true, 270.0, 40.0, 8.0)
	var p3 := _panel("PANEL 3 - MODULES", left)
	mod_list = VBoxContainer.new()
	mod_list.add_theme_constant_override("separation", 1)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(250, 250)
	sc.add_child(mod_list)
	p3.add_child(sc)
	var p4 := _panel("PANEL 4 - TACTICAL RADAR", left)
	radar = RadarView.new()
	(radar as RadarView).hud = self
	radar.custom_minimum_size = Vector2(250, 250)
	p4.add_child(radar)

	# right column: Panel 1 (status), Panel 5 (objectives / log)
	var right := _column(false, 290.0, 40.0, 8.0)
	var p1 := _panel("PANEL 1 - SHIP STATUS", right)
	lbl_status = _label("", p1)
	_label("Hull integrity", p1)
	bar_hull = ProgressBar.new()
	bar_hull.show_percentage = false
	bar_hull.custom_minimum_size = Vector2(0, 10)
	p1.add_child(bar_hull)
	lbl_power = _label("Power", p1)
	bar_power = ProgressBar.new()
	bar_power.show_percentage = false
	bar_power.custom_minimum_size = Vector2(0, 10)
	p1.add_child(bar_power)
	lbl_target = _label("Target: none", p1)
	lbl_warn = _label("", p1)
	lbl_warn.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	btn_giveup = _button("Give up (ship counts as dead)", p1, func(): arena.give_up())
	btn_giveup.visible = false
	var p5 := _panel("PANEL 5 - OBJECTIVES / LOG", right)
	lbl_score = _label("", p5)
	log_box = RichTextLabel.new()
	log_box.custom_minimum_size = Vector2(270, 170)
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 11)
	p5.add_child(log_box)
	if arena.mode == "sandbox":
		_build_sandbox_panel(right)

	# bottom centre: Panel 2 (mode selection) + sub-panel
	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -330.0
	bottom.offset_right = 330.0
	bottom.offset_top = -190.0
	bottom.offset_bottom = -8.0
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	var p2 := _panel("PANEL 2 - MODE SELECTION", bottom)
	var grid := GridContainer.new()
	grid.columns = 6
	p2.add_child(grid)
	for m in MODES:
		var mm: String = m
		_button(mm, grid, func(): set_mode(mm), 11)
	sub = VBoxContainer.new()
	p2.add_child(sub)

	ticker = Label.new()
	ticker.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ticker.anchor_left = 0.5
	ticker.anchor_right = 0.5
	ticker.offset_left = -300.0
	ticker.offset_right = 300.0
	ticker.offset_top = 8.0
	ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ticker.add_theme_font_size_override("font_size", 15)
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ticker)

	help = Label.new()
	help.position = Vector2(300, 40)
	help.add_theme_font_size_override("font_size", 12)
	help.text = "W/S A/D Space/C: thrust | Q/E roll | arrows or mouse(FP): pitch/yaw | LMB fire | RMB-drag orbit, wheel zoom\nV: first/third person | TAB: free cursor | T: lock target | X: assisted flight | Z: brake | ESC: pause"
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help)

	_build_respawn()
	_build_pause()
	set_mode("Movement")


func _build_sandbox_panel(parent: Control) -> void:
	var vb := _panel("TEST RANGE", parent)
	var ships: Array = Game.all_ships()
	var row := HBoxContainer.new()
	vb.add_child(row)
	var pick := OptionButton.new()
	for s in ships:
		pick.add_item("%s%s" % [s["name"], "" if s["source"] == "premade" else " *"])
	pick.add_theme_font_size_override("font_size", 11)
	row.add_child(pick)
	var beh := OptionButton.new()
	for b in ["Static", "Drift", "Spin", "Sentry", "Hunter"]:
		beh.add_item(b)
	beh.add_theme_font_size_override("font_size", 11)
	row.add_child(beh)
	_button("Spawn dummy", vb, func(): arena.spawn_dummy(ships[pick.selected]["bp"], ["static", "drift", "spin", "sentry", "hunter"][beh.selected]), 11)
	_button("Repair my ship", vb, func(): arena.repair_player(), 11)
	var tr := HBoxContainer.new()
	vb.add_child(tr)
	var cb := CheckButton.new()
	cb.text = "Test shot at my hull"
	cb.add_theme_font_size_override("font_size", 11)
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on: bool): arena.test_shot_on = on)
	tr.add_child(cb)
	var wp := OptionButton.new()
	for w in ShipData.WEAPONS:
		wp.add_item(w)
	wp.add_theme_font_size_override("font_size", 11)
	wp.item_selected.connect(func(i: int): arena.test_shot_weapon = ShipData.WEAPONS[i])
	tr.add_child(wp)
	_label("Commander view: click your own hull to fire the\nchosen round at it and read the damage log.", vb, 10)


func _build_respawn() -> void:
	respawn_panel = PanelContainer.new()
	respawn_panel.add_theme_stylebox_override("panel", _style(0.9))
	respawn_panel.set_anchors_preset(Control.PRESET_CENTER)
	respawn_panel.visible = false
	root.add_child(respawn_panel)
	panels.append(respawn_panel)
	var vb := VBoxContainer.new()
	respawn_panel.add_child(vb)
	respawn_lbl = _label("", vb, 16)
	respawn_pick = OptionButton.new()
	vb.add_child(respawn_pick)
	_button("Respawn now", vb, func(): arena.respawn_now())


func _build_pause() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.add_theme_stylebox_override("panel", _style(0.95))
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.visible = false
	root.add_child(pause_panel)
	panels.append(pause_panel)
	var vb := VBoxContainer.new()
	pause_panel.add_child(vb)
	_label("PAUSED", vb, 20)
	_button("Resume", vb, func(): arena.set_paused(false), 14)
	var back := "Back to ship editor" if Game.session.get("return_scene", "") == "res://scenes/ship_editor.tscn" else "Back to main menu"
	_button(back, vb, func(): arena.leave(), 14)


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
		var nm := _label("%s #%d" % [m["label"], m["id"]], hb, 11)
		nm.custom_minimum_size = Vector2(122, 0)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(70, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		hb.add_child(bar)
		var pw := _label("", hb, 11)
		pw.custom_minimum_size = Vector2(40, 0)
		mod_list.add_child(hb)
		rows.append({"m": m, "bar": bar, "pw": pw, "nm": nm})


func set_mode(m: String) -> void:
	mode = m
	for c in sub.get_children():
		c.queue_free()
	_label("MODE: " + m.to_upper(), sub, 12).add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	if MODE_NEEDS.has(m):
		_label("Requires: " + MODE_NEEDS[m], sub, 12)
		return
	var row := HBoxContainer.new()
	sub.add_child(row)
	match m:
		"Movement":
			var ck := CheckButton.new()
			ck.text = "Assisted (X)"
			ck.button_pressed = arena.player.assist if arena.player else true
			ck.focus_mode = Control.FOCUS_NONE
			ck.add_theme_font_size_override("font_size", 11)
			ck.toggled.connect(func(on: bool): arena.set_assist(on))
			row.add_child(ck)
			_button("Hold", row, func(): arena.set_order("hold"), 11)
			_button("Brake", row, func(): arena.set_order("brake"), 11)
			_button("Face target", row, func(): arena.set_order("face"), 11)
			_button("Drive toward", row, func(): arena.set_order("drive"), 11)
			_button("Orbit", row, func(): arena.set_order("orbit"), 11)
			_button("Manual", row, func(): arena.set_order("none"), 11)
			var r2 := HBoxContainer.new()
			sub.add_child(r2)
			_label("Speed limiter", r2, 11)
			var sl := HSlider.new()
			sl.min_value = 20
			sl.max_value = 800
			sl.value = speed_limit
			sl.custom_minimum_size = Vector2(300, 16)
			sl.value_changed.connect(func(v: float): speed_limit = v)
			r2.add_child(sl)
		"Combat":
			_button("Lock target (T)", row, func(): arena.lock_target(), 11)
			_button("Clear lock", row, func(): arena.clear_lock(), 11)
			_label("LMB = fire all linked barrels. Locked: barrels lead the target.", sub, 11)
		"Sensors":
			_button("Zoom +", row, func(): radar_zoom = maxf(250.0, radar_zoom * 0.5), 11)
			_button("Zoom -", row, func(): radar_zoom = minf(8000.0, radar_zoom * 2.0), 11)
			_label("Range is limited by the Radar Room (400 m without it).", sub, 11)
		"Power & Systems":
			for k in ["thrusters", "weapons", "radar", "gyro"]:
				var kk: String = k
				var ck2 := CheckButton.new()
				ck2.text = kk
				ck2.focus_mode = Control.FOCUS_NONE
				ck2.add_theme_font_size_override("font_size", 11)
				ck2.button_pressed = bool(arena.player.switches[kk]) if arena.player else true
				ck2.toggled.connect(func(on: bool): arena.player.switches[kk] = on)
				row.add_child(ck2)
			_label("Power goes to modules closest to a Generator first.", sub, 11)


func log_msg(t: String) -> void:
	log_box.append_text(t + "\n")


func say(t: String, color := Color.WHITE) -> void:
	ticker.text = t
	ticker.add_theme_color_override("font_color", color)
	ticker.modulate.a = 1.0
	_ticker_t = 5.0


func flash() -> void:
	flash_rect.color = Color(1, 0, 0, 0.35)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.5)


func is_mouse_over_ui() -> bool:
	var mp := root.get_viewport().get_mouse_position()
	for p in panels:
		if (p as Control).is_visible_in_tree() and (p as Control).get_global_rect().has_point(mp):
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
	var v := ship.linear_velocity
	var f := ship.forward()
	lbl_status.text = "%s  [%s]\nSpeed %.0f m/s   Heading %.0f / %.0f\nFlight: %s   View: %s" % [ship.name, ship.stats["class"], v.length(), rad_to_deg(atan2(f.x, -f.z)), rad_to_deg(asin(clampf(f.y, -1, 1))), "ASSISTED" if ship.assist else "MANUAL", "FIRST PERSON" if arena.rig.first_person else "COMMANDER"]
	bar_hull.value = ship.hull_hp / ship.hull_hp_max * 100.0
	bar_power.value = ship.power_frac * 100.0
	lbl_power.text = "Power %.0f / %.0f MW demand" % [ship.power_supply, ship.power_demand]
	if ship.target != null and is_instance_valid(ship.target) and ship.target.alive:
		lbl_target.text = "Target: %s  %d m  hull %d%%" % [ship.target.name, int(ship.global_position.distance_to(ship.target.global_position)), int(ship.target.hull_hp / ship.target.hull_hp_max * 100.0)]
	else:
		lbl_target.text = "Target: none"
	var stuck := ship.alive and not ship.can_move()
	lbl_warn.text = "NO THRUST - you can keep firing or give up." if stuck else ("SHIP DESTROYED" if not ship.alive else "")
	btn_giveup.visible = stuck
	lbl_score.text = arena.score_text()
