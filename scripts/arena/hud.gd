class_name Hud
extends CanvasLayer
## Command console (GDD 4.2) as a riveted black-iron / ember-orange "war machine" bridge board.
## Layout follows the HUD mock-up: Panel 3 (modules, category tabs) bottom-left, round Panel 4 (radar),
## Panel 2 (modes) bottom-centre, round Panel 5 (objectives / log toggle), Panel 1 (3D ship model with
## Basic / Exploded / Onion tabs + telemetry) bottom-right, and a Sub Panel 2 that rises above Panel 2.
## Layout numbers are in a 1600x900 reference viewport and are shrunk by UI_SCALE around the bottom centre.

const UI_SCALE := 0.78
const MODES := ["Movement", "Combat", "Defense", "Sensors", "Comms", "Crew Cmd", "Boarding", "Hangar/Fleet", "Power & Systems", "AI/Auto"]
const MODE_SHORT := {"Hangar/Fleet": "Hangar", "Power & Systems": "Power/Sys"}
const MODE_NEEDS := {
	"Defense": "a Defense Bay (not in this prototype)", "Comms": "a Communication Room / Dish (roadmap step 3+)",
	"Crew Cmd": "crew simulation (roadmap step 6)", "Boarding": "Breach Pods and Doors (roadmap step 6)",
	"Hangar/Fleet": "a Hangar (roadmap step 7)", "AI/Auto": "AI core options (roadmap step 3+)",
}
const MOD_TABS := ["All", "Cmd", "Power", "Drive", "Arms", "Sens"]
const MOD_CATEGORY := {"commander_post": 1, "generator": 2, "engine_room": 2, "thruster": 3, "turret_bay": 4, "turret_control": 4, "barrel": 4, "radar_room": 5}

const AMBER := Color(1.0, 0.66, 0.22)
const ORANGE := Color(0.95, 0.42, 0.08)
const ORANGE_DIM := Color(0.6, 0.27, 0.07)
const EMBER := Color(1.0, 0.82, 0.45)
const RED := Color(0.9, 0.12, 0.08)
const BLUE := Color(0.35, 0.65, 1.0)
const IRON := Color(0.075, 0.065, 0.065)
const SCREEN := Color(0.03, 0.014, 0.012)

var arena
var ship: Ship
var mode := "Movement"
var sub_open := false
var radar_zoom := 1200.0
var speed_limit := 150.0
var _sub_was_open := false
var weapon_list: ItemList
var root: Control
var overlay: Control
var radar: Control
var preview: ShipPreview
var p1: ConsolePanel
var _p1_anchors := Vector4.ZERO
var sub_panel: ConsolePanel
var sub_body: VBoxContainer
var sub_text: RichTextLabel
var mod_list: VBoxContainer
var mod_filter := 0
var rows: Array = []
var lbl_telemetry: Label
var lbl_target: Label
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
static func chamfer(w: float, h: float, c: float, o := 0.0) -> PackedVector2Array:
	return PackedVector2Array([Vector2(c + o, o), Vector2(w - c - o, o), Vector2(w - o, c + o), Vector2(w - o, h - c - o), Vector2(w - c - o, h - o), Vector2(c + o, h - o), Vector2(o, h - c - o), Vector2(o, c + o)])


static func outlined(ci: CanvasItem, text: String, pos: Vector2, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font: Font = UiStyle.display_font() if size >= 14 else UiStyle.body_font()
	ci.draw_string_outline(font, pos, text, align, width, size, 3, Color(0, 0, 0, 0.95))
	ci.draw_string(font, pos, text, align, width, size, col)


class ConsolePanel extends Control:
	signal tab_changed(index: int)
	var title := ""
	var tag := "MK VII"
	var tabs: Array = []
	var tab_active := 0
	var body: VBoxContainer
	var inset := Vector4(13, 25, 13, 17)   # inner screen margins: left, top, right, bottom
	var _tab_rects: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 3)
		add_child(body)
		resized.connect(_layout)
		_layout()

	func set_tabs(names: Array) -> void:
		tabs = names
		inset.y = 25.0 + (18.0 if not names.is_empty() else 0.0)
		_layout()
		queue_redraw()

	func _layout() -> void:
		body.position = Vector2(inset.x + 5, inset.y + 4)
		body.size = Vector2(maxf(size.x - inset.x - inset.z - 10, 10.0), maxf(size.y - inset.y - inset.w - 8, 10.0))
		body.clip_contents = true

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in range(_tab_rects.size()):
				if (_tab_rects[i] as Rect2).has_point(event.position):
					tab_active = i
					tab_changed.emit(i)
					queue_redraw()
					accept_event()
					return

	func _draw() -> void:
		var W := size.x
		var H := size.y
		var ch := 10.0
		var frame := Hud.chamfer(W, H, ch)
		draw_colored_polygon(frame, IRON)
		for y in range(6, int(H), 6):
			draw_line(Vector2(5, y), Vector2(W - 5, y), Color(1, 1, 1, 0.018))
		var loop := frame.duplicate()
		loop.append(frame[0])
		draw_polyline(loop, Color(0, 0, 0), 3.0)
		var trim := Hud.chamfer(W, H, ch - 3.0, 4.0)
		var tl := trim.duplicate()
		tl.append(trim[0])
		draw_polyline(tl, Color(0, 0, 0), 3.0)
		draw_polyline(tl, ORANGE_DIM, 1.5)
		var x := ch + 8.0
		while x < W - ch - 6.0:
			draw_circle(Vector2(x, 4.5), 2.0, Color(0, 0, 0))
			draw_circle(Vector2(x, 4.5), 1.3, Color(0.42, 0.36, 0.32))
			x += 26.0
		# hazard stripe along the bottom edge
		var hy := H - 12.0
		var hx := ch + 6.0
		var flip := false
		while hx < W - ch - 14.0:
			var c := ORANGE if not flip else Color(0.04, 0.03, 0.03)
			draw_colored_polygon(PackedVector2Array([Vector2(hx, hy + 5), Vector2(hx + 4, hy), Vector2(hx + 11, hy), Vector2(hx + 7, hy + 5)]), c)
			hx += 7.0
			flip = not flip
		# title bar
		Hud.outlined(self, title, Vector2(inset.x + 2, 18), 11, AMBER)
		for v in range(4):
			draw_rect(Rect2(W - 62 + v * 6, 9, 3, 10), Color(0, 0, 0))
		draw_circle(Vector2(W - 28, 13), 3.2, Color(0, 0, 0))
		draw_circle(Vector2(W - 28, 13), 2.2, BLUE)
		draw_circle(Vector2(W - 18, 13), 3.2, Color(0, 0, 0))
		draw_circle(Vector2(W - 18, 13), 2.2, RED)
		# tabs
		_tab_rects.clear()
		if not tabs.is_empty():
			var tw := minf(78.0, (W - inset.x - inset.z) / float(tabs.size()))
			for i in range(tabs.size()):
				var tx := inset.x + float(i) * tw
				var y0 := 24.0
				var y1 := inset.y
				var poly := PackedVector2Array([Vector2(tx, y1), Vector2(tx + 4, y0), Vector2(tx + tw - 4, y0), Vector2(tx + tw, y1)])
				var active := i == tab_active
				draw_colored_polygon(poly, ORANGE if active else Color(0.11, 0.06, 0.045))
				var pl := poly.duplicate()
				pl.append(poly[0])
				draw_polyline(pl, Color(0, 0, 0), 2.5)
				draw_polyline(pl, EMBER if active else ORANGE_DIM, 1.0)
				var font: Font = UiStyle.body_font()
				var tcol := Color(0.05, 0.02, 0.01) if active else AMBER
				draw_string(font, Vector2(tx, y1 - 5), String(tabs[i]), HORIZONTAL_ALIGNMENT_CENTER, tw, 9, tcol)
				_tab_rects.append(Rect2(tx, y0, tw, y1 - y0))
		# recessed screen
		var s := Rect2(Vector2(inset.x, inset.y), size - Vector2(inset.x + inset.z, inset.y + inset.w))
		draw_rect(s.grow(2.0), Color(0, 0, 0))
		draw_rect(s, SCREEN)
		var yy := s.position.y
		while yy < s.end.y:
			draw_line(Vector2(s.position.x, yy), Vector2(s.end.x, yy), Color(1.0, 0.4, 0.1, 0.045), 1.0)
			yy += 3.0
		draw_rect(s, ORANGE_DIM, false, 1.0)
		for corner in [[s.position, 1, 1], [Vector2(s.end.x, s.position.y), -1, 1], [Vector2(s.position.x, s.end.y), 1, -1], [s.end, -1, -1]]:
			var cp: Vector2 = corner[0]
			draw_line(cp, cp + Vector2(9 * corner[1], 0), AMBER, 1.5)
			draw_line(cp, cp + Vector2(0, 9 * corner[2]), AMBER, 1.5)


class RoundPanel extends Control:
	var title := ""
	var body: Control      # inscribed square (text fits inside the circle)
	var full: Control      # the whole inner screen disc
	var screen_r := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		body = Control.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(body)
		full = Control.new()
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(full)
		resized.connect(_layout)

	func _layout() -> void:
		screen_r = minf(size.x, size.y) * 0.5 - 18.0
		var sq := screen_r * 1.36
		body.position = size * 0.5 - Vector2(sq, sq) * 0.5 + Vector2(0, 2)
		body.size = Vector2(sq, sq)
		full.position = size * 0.5 - Vector2(screen_r, screen_r)
		full.size = Vector2(screen_r, screen_r) * 2.0

	func _draw() -> void:
		_layout()
		var c := size * 0.5
		var R := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, R + 1.5, Color(0, 0, 0))
		draw_circle(c, R, IRON)
		draw_arc(c, R - 3.0, 0, TAU, 96, Color(0, 0, 0), 3.0)
		draw_arc(c, R - 3.0, 0, TAU, 96, ORANGE_DIM, 1.5)
		for i in 72:
			var a := float(i) * TAU / 72.0
			var d := Vector2(cos(a), sin(a))
			var l := 8.0 if i % 6 == 0 else 4.0
			draw_line(c + d * (R - 15.0 - l), c + d * (R - 15.0), ORANGE if i % 6 == 0 else ORANGE_DIM, 1.2)
		for i in 8:
			var a2 := float(i) * TAU / 8.0 + PI / 8.0
			var bp := c + Vector2(cos(a2), sin(a2)) * (R - 7.0)
			draw_circle(bp, 3.2, Color(0, 0, 0))
			draw_circle(bp, 2.0, Color(0.42, 0.36, 0.32))
		draw_circle(c, screen_r + 1.5, Color(0, 0, 0))
		draw_circle(c, screen_r, SCREEN)
		draw_arc(c, screen_r, 0, TAU, 96, ORANGE_DIM, 1.2)
		draw_arc(c, screen_r - 4.0, -0.9, 0.9, 24, Color(0.9, 0.2, 0.1, 0.55), 1.2)
		draw_arc(c, screen_r - 4.0, PI - 0.9, PI + 0.9, 24, Color(0.9, 0.2, 0.1, 0.55), 1.2)
		draw_circle(c + Vector2(-14, R - 9), 2.5, BLUE)
		draw_circle(c + Vector2(14, R - 9), 2.5, RED)
		Hud.outlined(self, title, Vector2(c.x - 60, size.y - 15), 8, AMBER, 120.0, HORIZONTAL_ALIGNMENT_CENTER)


class SegBar extends Control:
	var value := 0.0
	var label := ""
	var col := Hud.ORANGE
	var warn := false
	var cells := 12

	func _draw() -> void:
		var h := size.y - 12.0
		var ch := h / float(cells)
		var lit_col := col
		if warn:
			lit_col = RED if value < 0.25 else (AMBER if value < 0.5 else col)
		draw_rect(Rect2(-1, -1, size.x + 2, h + 2), Color(0, 0, 0))
		draw_rect(Rect2(0, 0, size.x, h), Color(0.05, 0.025, 0.02))
		for i in cells:
			var lit := float(i) / float(cells) < value - 0.001
			var y := h - float(i + 1) * ch
			draw_rect(Rect2(2, y + 1.0, size.x - 4, ch - 1.5), lit_col if lit else Color(0.14, 0.07, 0.05))
		Hud.outlined(self, label, Vector2(0, size.y - 1), 8, AMBER, size.x, HORIZONTAL_ALIGNMENT_CENTER)


class Overlay extends Control:
	var hud: Hud

	func _draw() -> void:
		if hud == null or hud.arena == null or hud.ship == null:
			return
		var cam: Camera3D = hud.arena.rig.cam
		var font: Font = UiStyle.body_font()
		if hud.arena.rig.first_person:
			var c := size * 0.5
			var col := Color(1.0, 0.75, 0.3, 0.9)
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
			var col2 := Color(1, 0.3, 0.2) if enemy else Color(0.4, 0.7, 1.0)
			var locked := hud.ship.target == o
			var r := 11.0 if locked else 6.0
			draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), col2, 2.0 if locked else 1.0)
			var d := hud.ship.global_position.distance_to(wp)
			Hud.outlined(self, "%s %s  %dm" % ["LOCK" if locked else "", o.name, int(d)], p + Vector2(r + 4, 4), 12, col2)
		_draw_waypoint(cam)
		_draw_assignments(cam)
		if hud.arena.rig.map_mode:
			_draw_map(cam)
		var tn: OrderTuner = hud.arena.tuner
		if tn.active:
			Hud.outlined(self, tn.banner, Vector2(20, 96), 13, Color(1.0, 0.8, 0.3), size.x - 40.0, HORIZONTAL_ALIGNMENT_CENTER)
			Hud.outlined(self, tn.status_line(), Vector2(20, 118), 12, Color(1.0, 0.95, 0.75), size.x - 40.0, HORIZONTAL_ALIGNMENT_CENTER)

	static func fmt_dist(m: float) -> String:
		return "%d m" % int(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)

	func _draw_assignments(cam: Camera3D) -> void:
		var counts := {}
		for u in hud.arena.weapon_units():
			if String(u["tmode"]) == "ship":
				var t = u["tgt"]
				if t != null and is_instance_valid(t) and t.alive:
					counts[t] = int(counts.get(t, 0)) + 1
		for t in counts:
			if cam.is_position_behind(t.global_position):
				continue
			var p := cam.unproject_position(t.global_position)
			Hud.outlined(self, "<< %d turret%s" % [counts[t], "" if counts[t] == 1 else "s"], p + Vector2(16, 20), 12, Color(1.0, 0.45, 0.3))

	func _draw_waypoint(cam: Camera3D) -> void:
		var ar = hud.arena
		if not ar.has_wp:
			return
		var w: Vector3 = ar.waypoint
		var col := Color(1.0, 0.78, 0.25)
		var dist: float = ar.wp_dist()
		var spd := hud.ship.linear_velocity.length()
		var rate := maxf(spd, 1.0) if ar.order == "goto" else 0.0
		var eta := "ETA %ds" % int(dist / rate) if rate > 5.0 else ""
		var txt := "WAYPOINT  %s  alt %+d m  %s" % [fmt_dist(dist), int(w.y - hud.ship.global_position.y), eta]
		var on_screen := not cam.is_position_behind(w)
		var p := cam.unproject_position(w) if on_screen else Vector2.ZERO
		if on_screen and Rect2(Vector2(30, 30), size - Vector2(60, 60)).has_point(p):
			Hud.outlined(self, txt, p + Vector2(18, -10), 13, col)
		else:
			# off screen: arrow on the edge pointing to it
			var local := cam.global_transform.affine_inverse() * w
			var dir := Vector2(local.x, -local.y)
			if local.z > 0.0:
				dir = -dir
			if dir.length() < 0.001:
				dir = Vector2(0, -1)
			dir = dir.normalized()
			var c := size * 0.5
			var k := minf((size.x * 0.5 - 50.0) / maxf(absf(dir.x), 0.001), (size.y * 0.5 - 50.0) / maxf(absf(dir.y), 0.001))
			var ep := c + dir * k
			var perp := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([ep + dir * 14.0, ep - dir * 8.0 + perp * 10.0, ep - dir * 8.0 - perp * 10.0]), col)
			Hud.outlined(self, "WAYPOINT  %s" % fmt_dist(dist), ep - dir * 22.0 + Vector2(-60 if dir.x > 0.0 else 12, 4), 12, col)

	func _draw_map(cam: Camera3D) -> void:
		var viz: WaypointViz = hud.arena.viz
		var sp: Vector3 = hud.ship.global_position
		for i in range(1, viz.ring_count + 1, 1):
			var wp := Vector3(sp.x + viz.ring_step * i, viz.plane_y, sp.z)
			if not cam.is_position_behind(wp):
				var p := cam.unproject_position(wp)
				if Rect2(Vector2.ZERO, size).has_point(p):
					Hud.outlined(self, fmt_dist(viz.ring_step * i), p + Vector2(3, -3), 11, Color(0.85, 0.35, 0.2, 0.9))
		var psp := cam.unproject_position(sp)
		var pf := cam.unproject_position(sp - hud.ship.global_transform.basis.z * viz.ring_step * 0.25)
		var hd := (pf - psp).normalized() if pf.distance_to(psp) > 1.0 else Vector2(0, -1)
		var pp := Vector2(-hd.y, hd.x)
		draw_colored_polygon(PackedVector2Array([psp + hd * 13.0, psp - hd * 9.0 + pp * 8.0, psp - hd * 4.0, psp - hd * 9.0 - pp * 8.0]), Color(0.5, 0.8, 1.0))
		Hud.outlined(self, "YOU", psp + Vector2(14, 14), 11, Color(0.5, 0.8, 1.0))
		if not hud.arena.tuner.active:
			Hud.outlined(self, "TACTICAL MAP   LMB set point (drag to slide it)   drag the diamond up/down: altitude   RMB orbit   MMB pan   wheel zoom   M exit", Vector2(20, 96), 13, Color(1.0, 0.8, 0.3), size.x - 40.0, HORIZONTAL_ALIGNMENT_CENTER)


class Radar3D extends Control:
	## True 3D tactical radar: a sphere/disc grid drawn in ship space (nose = up the screen),
	## contacts are 3D markers with an altitude stalk down to the plane. Drag to rotate, wheel to zoom range.
	var hud: Hud
	var vp: SubViewport
	var cam: Camera3D
	var root3: Node3D
	var yaw := 0.0
	var pitch := -0.8
	var dist := 2.55
	var pool: Array = []
	var shadows: Array = []
	var stalks: ImmediateMesh
	var dragging := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		svc.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(svc)
		vp = SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		svc.add_child(vp)
		root3 = Node3D.new()
		vp.add_child(root3)
		cam = Camera3D.new()
		cam.fov = 38.0
		cam.near = 0.05
		cam.far = 50.0
		root3.add_child(cam)
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.vertex_color_use_as_albedo = true
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var grid := ImmediateMesh.new()
		grid.surface_begin(Mesh.PRIMITIVE_LINES, lm)
		for k in [0.33, 0.66, 1.0]:
			_circle(grid, k, 0, Color(0.85, 0.38, 0.1, 0.8 if k == 1.0 else 0.45))
		_circle(grid, 1.0, 1, Color(0.8, 0.35, 0.1, 0.5))
		_circle(grid, 1.0, 2, Color(0.8, 0.35, 0.1, 0.5))
		for a in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)]:
			_line(grid, Vector3.ZERO, a, Color(0.7, 0.3, 0.1, 0.4))
		_line(grid, Vector3.ZERO, Vector3(0, 0, -1.12), Color(1.0, 0.8, 0.35, 0.95))
		_line(grid, Vector3(0, -1, 0), Vector3(0, 1, 0), Color(0.7, 0.3, 0.1, 0.25))
		grid.surface_end()
		var gi := MeshInstance3D.new()
		gi.mesh = grid
		root3.add_child(gi)
		stalks = ImmediateMesh.new()
		var si := MeshInstance3D.new()
		si.mesh = stalks
		si.material_override = lm
		root3.add_child(si)
		var me := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.05
		cone.height = 0.16
		me.mesh = cone
		me.rotate_x(-PI * 0.5)
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color(1.0, 0.85, 0.5)
		me.material_override = mm
		root3.add_child(me)

	func _line(m: ImmediateMesh, a: Vector3, b: Vector3, c: Color) -> void:
		m.surface_set_color(c)
		m.surface_add_vertex(a)
		m.surface_set_color(c)
		m.surface_add_vertex(b)

	func _circle(m: ImmediateMesh, r: float, plane: int, c: Color) -> void:
		var n := 56
		for i in n:
			var a0 := float(i) * TAU / n
			var a1 := float(i + 1) * TAU / n
			var p0 := Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := Vector3(cos(a1), 0, sin(a1)) * r
			if plane == 1:
				p0 = Vector3(cos(a0), sin(a0), 0) * r
				p1 = Vector3(cos(a1), sin(a1), 0) * r
			elif plane == 2:
				p0 = Vector3(0, sin(a0), cos(a0)) * r
				p1 = Vector3(0, sin(a1), cos(a1)) * r
			_line(m, p0, p1, c)

	func _process(_delta: float) -> void:
		var off := Vector3(0, 0, dist).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
		cam.look_at_from_position(off, Vector3.ZERO, Vector3.UP)
		stalks.clear_surfaces()
		var used := 0
		if hud != null and hud.ship != null and is_instance_valid(hud.ship):
			var me: Ship = hud.ship
			var rng := minf(hud.radar_zoom, me.radar_range())
			var begun := false
			for group in ["ships", "wrecks"]:
				for n in get_tree().get_nodes_in_group(group):
					var o := n as Ship
					if o == me:
						continue
					var l := me.to_local(o.global_position)
					if l.length() > rng:
						continue
					var p := l / rng
					var col := Color(0.5, 0.45, 0.42)
					if group == "ships":
						col = Color(1.0, 0.22, 0.12) if o.team != me.team else Color(0.4, 0.7, 1.0)
					var tgt := o == me.target
					if used >= pool.size():
						var mi := MeshInstance3D.new()
						var sm := SphereMesh.new()
						sm.radius = 0.065
						sm.height = 0.13
						sm.radial_segments = 10
						sm.rings = 5
						mi.mesh = sm
						var mat := StandardMaterial3D.new()
						mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						mi.material_override = mat
						root3.add_child(mi)
						pool.append(mi)
					if used >= shadows.size():
						var sh := MeshInstance3D.new()
						var shm := SphereMesh.new()
						shm.radius = 0.05
						shm.height = 0.1
						sh.mesh = shm
						sh.scale = Vector3(1, 0.12, 1)
						var shmat := StandardMaterial3D.new()
						shmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						sh.material_override = shmat
						root3.add_child(sh)
						shadows.append(sh)
					var shn := shadows[used] as MeshInstance3D
					shn.visible = true
					shn.position = Vector3(p.x, 0, p.z)
					(shn.material_override as StandardMaterial3D).albedo_color = col.darkened(0.45)
					var node := pool[used] as MeshInstance3D
					node.visible = true
					node.position = p
					node.scale = Vector3.ONE * (1.7 if tgt else 1.0)
					(node.material_override as StandardMaterial3D).albedo_color = Color(1, 0.95, 0.6) if tgt else col
					if not begun:
						stalks.surface_begin(Mesh.PRIMITIVE_LINES)
						begun = true
					stalks.surface_set_color(col)
					stalks.surface_add_vertex(Vector3(p.x, 0, p.z))
					stalks.surface_set_color(col)
					stalks.surface_add_vertex(p)
					used += 1
			if begun:
				stalks.surface_end()
		for i in range(used, pool.size()):
			(pool[i] as MeshInstance3D).visible = false
			(shadows[i] as MeshInstance3D).visible = false
		queue_redraw()

	func _draw() -> void:
		if hud == null or hud.ship == null:
			return
		var rng := minf(hud.radar_zoom, hud.ship.radar_range())
		var txt := "%d m%s" % [int(rng), "" if hud.ship.radar_range() > 1000.0 else "  DEGRADED"]
		Hud.outlined(self, txt, Vector2(0, size.y - 6), 9, Hud.AMBER, size.x, HORIZONTAL_ALIGNMENT_CENTER)
		Hud.outlined(self, "drag: rotate  wheel: range", Vector2(0, 11), 8, Hud.ORANGE_DIM, size.x, HORIZONTAL_ALIGNMENT_CENTER)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				dragging = event.pressed
				if event.pressed and event.double_click:
					yaw = 0.0
					pitch = -0.8
				accept_event()
			elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
				hud.radar_zoom = maxf(250.0, hud.radar_zoom / 1.4)
				accept_event()
			elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				hud.radar_zoom = minf(8000.0, hud.radar_zoom * 1.4)
				accept_event()
		elif event is InputEventMouseMotion and dragging:
			yaw -= event.relative.x * 0.01
			pitch = clampf(pitch - event.relative.y * 0.01, -1.5, 1.2)
			accept_event()


# ================================================================== theme + helpers
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UiStyle.body_font()
	t.default_font_size = 12
	for cls in ["Label", "Button", "CheckButton", "OptionButton", "RichTextLabel"]:
		t.set_color("font_color", cls, AMBER)
		t.set_color("font_outline_color", cls, Color(0, 0, 0, 0.95))
		t.set_constant("outline_size", cls, 3)
	t.set_color("default_color", "RichTextLabel", AMBER)
	t.set_color("font_outline_color", "RichTextLabel", Color(0, 0, 0, 0.95))
	t.set_constant("outline_size", "RichTextLabel", 3)
	t.set_color("font_hover_color", "Button", EMBER)
	t.set_color("font_pressed_color", "Button", Color(0.06, 0.02, 0.01))
	t.set_color("font_focus_color", "Button", AMBER)
	for st in [["normal", Color(0.1, 0.055, 0.045)], ["hover", Color(0.3, 0.13, 0.05)], ["pressed", ORANGE], ["disabled", Color(0.06, 0.05, 0.05)]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.border_color = ORANGE_DIM if st[0] != "pressed" else EMBER
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(1)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.shadow_color = Color(0, 0, 0, 0.8)
		sb.shadow_size = 1
		t.set_stylebox(st[0], "Button", sb)
		t.set_stylebox(st[0], "OptionButton", sb)
	for st2 in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var cb := StyleBoxFlat.new()
		cb.bg_color = Color(0, 0, 0, 0)
		cb.content_margin_left = 2
		cb.content_margin_right = 2
		t.set_stylebox(st2, "CheckButton", cb)
	for ck in ["font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(ck, "CheckButton", EMBER)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.025, 0.02)
	bg.set_border_width_all(1)
	bg.border_color = Color(0, 0, 0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ORANGE
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	return t


func _label(text: String, parent: Control, size := 11) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _button(text: String, parent: Control, cb: Callable, size := 10) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Reference coordinates (1600x900 mock-up) -> shrunk around the bottom centre.
func _tx(x: float, y: float) -> Vector2:
	return Vector2(800.0 + (x - 800.0) * UI_SCALE, 900.0 - (900.0 - y) * UI_SCALE)


func _rect_panel(title: String, x: float, y: float, w: float, h: float, scaled := true) -> ConsolePanel:
	var p := ConsolePanel.new()
	p.title = title
	var o := _tx(x, y) if scaled else Vector2(x, y)
	var sz := Vector2(w, h) * (UI_SCALE if scaled else 1.0)
	p.anchor_left = o.x / 1600.0
	p.anchor_right = (o.x + sz.x) / 1600.0
	p.anchor_top = o.y / 900.0
	p.anchor_bottom = (o.y + sz.y) / 900.0
	root.add_child(p)
	panels.append(p)
	return p


func _round_panel(title: String, cx: float, cy: float, d: float) -> RoundPanel:
	var p := RoundPanel.new()
	p.title = title
	var c := _tx(cx, cy)
	var r := d * UI_SCALE * 0.5
	p.anchor_left = c.x / 1600.0
	p.anchor_right = c.x / 1600.0
	p.anchor_top = c.y / 900.0
	p.anchor_bottom = c.y / 900.0
	p.offset_left = -r
	p.offset_right = r
	p.offset_top = -r
	p.offset_bottom = r
	root.add_child(p)
	panels.append(p)
	return p


func _seg(label: String, parent: Control, col: Color) -> SegBar:
	var b := SegBar.new()
	b.label = label
	b.col = col
	b.custom_minimum_size = Vector2(22, 100)
	parent.add_child(b)
	return b


# ================================================================== build
func setup(a) -> void:
	arena = a
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = make_theme()
	add_child(root)
	overlay = Overlay.new()
	(overlay as Overlay).hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	# Sub Panel 2 first, so it sits behind the other panels (as in the mock-up)
	sub_panel = _rect_panel("SUB", 411, 150, 756, 530)
	sub_body = sub_panel.body
	sub_panel.visible = false

	# Panel 4: round radar
	var p4 := _round_panel("TACTICAL RADAR", 475, 650, 312)
	radar = Radar3D.new()
	(radar as Radar3D).hud = self
	radar.set_anchors_preset(Control.PRESET_FULL_RECT)
	p4.full.add_child(radar)

	# Panel 5: round objectives / log, with a toggle (tabs)
	var p5 := _round_panel("OBJECTIVES / LOG", 1094, 638, 312)
	var vb5 := VBoxContainer.new()
	vb5.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb5.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb5.add_theme_constant_override("separation", 2)
	p5.body.add_child(vb5)
	var tabrow := HBoxContainer.new()
	tabrow.alignment = BoxContainer.ALIGNMENT_CENTER
	vb5.add_child(tabrow)
	var grp := ButtonGroup.new()
	for tname in ["Objectives", "Log"]:
		var tb := Button.new()
		tb.text = tname
		tb.toggle_mode = true
		tb.button_group = grp
		tb.button_pressed = tname == "Objectives"
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 9)
		var tn: String = tname
		tb.pressed.connect(func(): _p5_tab(tn == "Log"))
		tabrow.add_child(tb)
	lbl_score = _label("", vb5, 9)
	lbl_score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_score.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_score.clip_text = true
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.visible = false
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_size_override("normal_font_size", 9)
	log_box.add_theme_font_size_override("bold_font_size", 9)
	vb5.add_child(log_box)

	# Panel 3: module management with category tabs
	var p3 := _rect_panel("MODULES", 66, 681, 326, 219)
	p3.set_tabs(MOD_TABS)
	p3.tab_changed.connect(func(i: int): mod_filter = i; _apply_mod_filter())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 90)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mod_list = VBoxContainer.new()
	mod_list.add_theme_constant_override("separation", 0)
	mod_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(mod_list)
	p3.body.add_child(sc)

	# Panel 2: mode selection
	var p2 := _rect_panel("MODE SELECTION", 594, 611, 406, 289)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	p2.body.add_child(grid)
	for m in MODES:
		var mm: String = m
		var b := _button(String(MODE_SHORT.get(mm, mm)), grid, func(): set_mode(mm), 9)
		b.custom_minimum_size = Vector2(84, 24)
	lbl_mode = _label("", p2.body, 9)
	btn_giveup = _button("GIVE UP (no thrust)", p2.body, func(): arena.give_up(), 9)
	btn_giveup.visible = false

	# Panel 1: 3D ship model (Basic / Exploded / Onion tabs) + gauges + telemetry
	p1 = _rect_panel("SHIP STATUS", 1205, 653, 327, 247)
	p1.set_tabs(ShipPreview.TABS)
	p1.tab_changed.connect(func(i: int): preview.set_view(i))
	var hb1 := HBoxContainer.new()
	hb1.add_theme_constant_override("separation", 4)
	hb1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p1.body.add_child(hb1)
	preview = ShipPreview.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_requested.connect(_expand_p1)
	hb1.add_child(preview)
	var gauges := HBoxContainer.new()
	gauges.add_theme_constant_override("separation", 2)
	hb1.add_child(gauges)
	bar_hull = _seg("HUL", gauges, Color(0.95, 0.5, 0.1))
	bar_hull.warn = true
	bar_power = _seg("PWR", gauges, BLUE)
	bar_thr = _seg("THR", gauges, ORANGE)
	bar_wpn = _seg("WPN", gauges, RED)
	lbl_telemetry = _label("", p1.body, 9)
	lbl_target = _label("TGT none", p1.body, 9)

	# top-right name list
	var sb := PanelContainer.new()
	var sbs := StyleBoxFlat.new()
	sbs.bg_color = Color(0.03, 0.02, 0.02, 0.75)
	sbs.border_color = ORANGE_DIM
	sbs.border_width_left = 2
	sb.add_theme_stylebox_override("panel", sbs)
	sb.anchor_left = 1.0
	sb.anchor_right = 1.0
	sb.offset_left = -190
	sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sb)
	score_box = RichTextLabel.new()
	score_box.bbcode_enabled = true
	score_box.fit_content = true
	score_box.custom_minimum_size = Vector2(180, 20)
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
	help.add_theme_font_size_override("font_size", 10)
	help.text = "W/S A/D Space/C thrust | Q/E roll | arrows or mouse (FP) pitch-yaw | LMB fire | RMB-drag orbit, wheel zoom\nV view | M tactical map | G go to cursor | Tab free cursor | T lock | X assist | Z brake | Esc pause"
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


## Panel 1 can grow into an inspector: more room for the hover card, the exploded spread and the deck slices.
func _expand_p1(on: bool) -> void:
	if on:
		_p1_anchors = Vector4(p1.anchor_left, p1.anchor_top, p1.anchor_right, p1.anchor_bottom)
		p1.anchor_left = 1000.0 / 1600.0
		p1.anchor_right = 1590.0 / 1600.0
		p1.anchor_top = 410.0 / 900.0
		p1.anchor_bottom = 1.0
	else:
		p1.anchor_left = _p1_anchors.x
		p1.anchor_top = _p1_anchors.y
		p1.anchor_right = _p1_anchors.z
		p1.anchor_bottom = _p1_anchors.w
	p1.move_to_front()


func _p5_tab(show_log: bool) -> void:
	log_box.visible = show_log
	lbl_score.visible = not show_log


func _build_sandbox_panel() -> void:
	var p := _rect_panel("TEST RANGE", 8, 8, 262, 160, false)
	var vb := p.body
	var ships: Array = Game.all_ships()
	var row := HBoxContainer.new()
	vb.add_child(row)
	var pick := OptionButton.new()
	for s in ships:
		pick.add_item("%s%s" % [s["name"], "" if s["source"] == "premade" else " *"])
	pick.add_theme_font_size_override("font_size", 10)
	row.add_child(pick)
	var beh := OptionButton.new()
	for b in ["Static", "Drift", "Spin", "Sentry", "Hunter"]:
		beh.add_item(b)
	beh.add_theme_font_size_override("font_size", 10)
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
	wp.add_theme_font_size_override("font_size", 10)
	wp.item_selected.connect(func(i: int): arena.test_shot_weapon = ShipData.WEAPONS[i])
	tr.add_child(wp)


func _build_respawn() -> void:
	respawn_panel = ConsolePanel.new()
	respawn_panel.title = "RESPAWN"
	respawn_panel.anchor_left = 0.5
	respawn_panel.anchor_right = 0.5
	respawn_panel.anchor_top = 0.5
	respawn_panel.anchor_bottom = 0.5
	respawn_panel.offset_left = -160
	respawn_panel.offset_right = 160
	respawn_panel.offset_top = -75
	respawn_panel.offset_bottom = 75
	respawn_panel.visible = false
	root.add_child(respawn_panel)
	panels.append(respawn_panel)
	respawn_lbl = _label("", respawn_panel.body, 13)
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
	pause_panel.offset_left = -140
	pause_panel.offset_right = 140
	pause_panel.offset_top = -80
	pause_panel.offset_bottom = 80
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.visible = false
	root.add_child(pause_panel)
	panels.append(pause_panel)
	_button("Resume", pause_panel.body, func(): arena.set_paused(false), 13)
	var back := "Back to ship editor" if Game.session.get("return_scene", "") == "res://scenes/ship_editor.tscn" else "Back to main menu"
	_button(back, pause_panel.body, func(): arena.leave(), 13)


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
	var order := ["commander_post", "generator", "engine_room", "thruster", "turret_control", "turret_bay", "barrel", "radar_room"]
	var sorted := s.mods.duplicate()
	sorted.sort_custom(func(a, b): return order.find(a["type"]) < order.find(b["type"]))
	for m in sorted:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 3)
		var nm := _label("%s #%d" % [m["label"], m["id"]], hb, 9)
		nm.custom_minimum_size = Vector2(104, 0)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(52, 7)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		hb.add_child(bar)
		var pw := _label("", hb, 9)
		pw.custom_minimum_size = Vector2(36, 0)
		mod_list.add_child(hb)
		rows.append({"m": m, "bar": bar, "pw": pw, "nm": nm, "row": hb})
	preview.bind(s)
	_apply_mod_filter()


func _apply_mod_filter() -> void:
	for r in rows:
		var cat: int = MOD_CATEGORY.get(r["m"]["type"], 0)
		(r["row"] as Control).visible = mod_filter == 0 or cat == mod_filter


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
	sub_panel.title = m.to_upper()
	sub_panel.queue_redraw()
	for c in sub_body.get_children():
		c.queue_free()
	sub_text = null
	if MODE_NEEDS.has(m):
		_label("This mode needs %s." % MODE_NEEDS[m], sub_body, 13)
		_label("Every mode is always listed on the console (design doc 4.2);\nthis one stays inactive until that system exists.", sub_body, 10)
		_refresh_mode_label()
		return
	match m:
		"Movement":
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
		lbl_mode.text = "Mode: %s%s - click again to %s" % [mode, "" if sub_open else " (closed)", "close" if sub_open else "open"]


func _make_sub_text(min_h := 120) -> void:
	sub_text = RichTextLabel.new()
	sub_text.bbcode_enabled = true
	sub_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_text.custom_minimum_size = Vector2(0, min_h)
	sub_text.add_theme_font_size_override("normal_font_size", 11)
	sub_text.add_theme_font_size_override("bold_font_size", 11)
	sub_body.add_child(sub_text)


func _sub_movement() -> void:
	var ck := CheckButton.new()
	ck.text = "Assisted flight (X)"
	ck.button_pressed = arena.player.assist if arena.player else true
	ck.focus_mode = Control.FOCUS_NONE
	ck.add_theme_font_size_override("font_size", 10)
	ck.toggled.connect(func(on: bool): arena.set_assist(on))
	sub_body.add_child(ck)
	_label("Orders (most hide this panel and let you set them in the 3D view)", sub_body, 9)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 3)
	g.add_theme_constant_override("v_separation", 3)
	sub_body.add_child(g)
	for pair in [["Hold position", "hold"], ["Brake (Z)", "brake"], ["Manual control", "none"],
			["Drive to point", "point"], ["Drive to ship", "chase"], ["Orbit", "orbit"],
			["Face", "lookat"], ["Follow offset", "follow"], ["Route", "route"]]:
		var k: String = pair[1]
		var b := _button(pair[0], g, func(): _movement_button(k), 10)
		b.custom_minimum_size = Vector2(120, 22)
	_label("Facing while moving", sub_body, 9)
	var fr := HBoxContainer.new()
	sub_body.add_child(fr)
	_button("Auto (travel)", fr, func(): arena.set_facing_auto(), 10)
	_button("Lock heading", fr, func(): arena.lock_heading_now(), 10)
	_button("Lock direction", fr, func(): arena.tuner.begin("lockdir"), 10)
	_button("Face point", fr, func(): arena.tuner.begin("facepoint"), 10)
	var r2 := HBoxContainer.new()
	sub_body.add_child(r2)
	_label("Speed limiter", r2, 10)
	var val := _label("%d m/s" % int(speed_limit), r2, 10)
	var sl := HSlider.new()
	sl.min_value = 20
	sl.max_value = 800
	sl.value = speed_limit
	sl.custom_minimum_size = Vector2(240, 16)
	sl.value_changed.connect(func(v: float): speed_limit = v; val.text = "%d m/s" % int(v))
	r2.add_child(sl)
	var vr := HBoxContainer.new()
	sub_body.add_child(vr)
	_label("View", vr, 10)
	_button("Standard (V)", vr, func(): arena.set_map_mode(false), 10)
	_button("Tactical map (M)", vr, func(): arena.set_map_mode(true), 10)
	_button("Center map", vr, func(): arena.rig.map_follow = true, 10)
	_button("Go to cursor (G)", vr, func(): arena._go_to_cursor(), 10)
	_make_sub_text(48)


func _movement_button(k: String) -> void:
	match k:
		"hold", "brake", "none":
			arena.set_order(k)
		_:
			arena.tuner.begin(k)


func hide_sub() -> void:
	_sub_was_open = sub_open
	sub_open = false
	if sub_panel != null:
		sub_panel.visible = false
	_refresh_mode_label()


func restore_sub() -> void:
	if _sub_was_open and sub_panel != null:
		sub_open = true
		sub_panel.visible = true
		sub_panel.queue_redraw()
		_refresh_sub()
	_sub_was_open = false


func _sub_combat() -> void:
	var row := HBoxContainer.new()
	sub_body.add_child(row)
	_button("Lock target (T)", row, func(): arena.lock_target(), 10)
	_button("Clear lock", row, func(): arena.clear_lock(), 10)
	_label("Turrets: click to toggle selection. LMB fires them all, each at its own target.", sub_body, 9)
	weapon_list = ItemList.new()
	weapon_list.select_mode = ItemList.SELECT_TOGGLE
	weapon_list.custom_minimum_size = Vector2(0, 66)
	weapon_list.add_theme_font_size_override("font_size", 10)
	weapon_list.multi_selected.connect(func(_i: int, _on: bool): _weapon_list_changed())
	weapon_list.item_selected.connect(func(_i: int): _weapon_list_changed())
	sub_body.add_child(weapon_list)
	_label("Quick select", sub_body, 9)
	var q := GridContainer.new()
	q.columns = 5
	q.add_theme_constant_override("h_separation", 3)
	q.add_theme_constant_override("v_separation", 3)
	sub_body.add_child(q)
	for pair in [["All", "all"], ["None", "none"], ["Invert", "invert"], ["Best", "best"], ["In arc", "arc"],
			["Idle", "idle"], ["Kinetic", "kinetic"], ["Laser", "laser"], ["Missile", "missile"], ["Online", "online"]]:
		var k: String = pair[1]
		var qb := _button(pair[0], q, func(): arena.select_weapons(k), 10)
		qb.custom_minimum_size = Vector2(60, 20)
		if k == "best":
			qb.tooltip_text = "The strongest online turrets that can hit the locked (or nearest) target right now"
		elif k == "arc":
			qb.tooltip_text = "Turrets that can point at the locked (or nearest) target right now"
		elif k == "idle":
			qb.tooltip_text = "Turrets that follow the main lock (no own target)"
	_label("Send the selected turrets at", sub_body, 9)
	var ar := HBoxContainer.new()
	sub_body.add_child(ar)
	_button("Pick a ship...", ar, func(): arena.tuner.begin("wpick"), 10)
	_button("Nearest enemy", ar, func(): arena.assign_nearest(), 10)
	_button("Locked target", ar, func(): arena.assign_weapons(null, "main"), 10)
	_button("Cursor aim", ar, func(): arena.assign_weapons(null, "cursor"), 10)
	_make_sub_text(30)
	refresh_weapons()


func _weapon_list_changed() -> void:
	var ids: Array = []
	for i in weapon_list.get_selected_items():
		ids.append(weapon_list.get_item_metadata(i))
	arena.sel_weapons = ids
	_refresh_sub()


## Keeps the turret list in step with the ship (texts) and with arena.sel_weapons (selection).
func refresh_weapons() -> void:
	if weapon_list == null or not is_instance_valid(weapon_list) or arena == null:
		return
	var units: Array = arena.weapon_units()
	if weapon_list.item_count != units.size():
		weapon_list.clear()
		for u in units:
			var i := weapon_list.add_item(arena.weapon_unit_text(u))
			weapon_list.set_item_metadata(i, u["id"])
	else:
		for i in units.size():
			weapon_list.set_item_text(i, arena.weapon_unit_text(units[i]))
			weapon_list.set_item_metadata(i, units[i]["id"])
	for i in weapon_list.item_count:
		var want: bool = arena.sel_weapons.has(weapon_list.get_item_metadata(i))
		if want != weapon_list.is_selected(i):
			if want:
				weapon_list.select(i, false)
			else:
				weapon_list.deselect(i)


func _sub_sensors() -> void:
	var row := HBoxContainer.new()
	sub_body.add_child(row)
	_button("Zoom +", row, func(): radar_zoom = maxf(250.0, radar_zoom * 0.5), 10)
	_button("Zoom -", row, func(): radar_zoom = minf(8000.0, radar_zoom * 2.0), 10)
	_label("Range is limited by the Radar Room (400 m without one).", row, 10)
	_make_sub_text()


func _sub_power() -> void:
	var row := HBoxContainer.new()
	sub_body.add_child(row)
	for k in ["thrusters", "weapons", "radar", "gyro"]:
		var kk: String = k
		var ck := CheckButton.new()
		ck.text = kk
		ck.focus_mode = Control.FOCUS_NONE
		ck.add_theme_font_size_override("font_size", 10)
		ck.button_pressed = bool(arena.player.switches[kk]) if arena.player else true
		ck.toggled.connect(func(on: bool): arena.player.switches[kk] = on)
		row.add_child(ck)
	_label("Power goes to the modules closest to a Generator first.", sub_body, 10)
	_make_sub_text()


func _refresh_sub() -> void:
	if not sub_open or sub_text == null or ship == null or not is_instance_valid(ship):
		return
	var t := ""
	match mode:
		"Movement":
			t += "Order: [color=#ffe680]%s[/color]\n" % arena.order_text()
			t += "Facing: [color=#ffe680]%s[/color]\n" % arena.facing_text()
			var vl := ship.global_transform.basis.inverse() * ship.linear_velocity
			t += "Velocity (local)  right %.1f   up %.1f   fwd %.1f  m/s\n" % [vl.x, vl.y, -vl.z]
			t += "Speed %.1f m/s    Angular %.2f rad/s\n" % [ship.linear_velocity.length(), ship.angular_velocity.length()]
			t += "Thrust  fwd %.0f  back %.0f  right %.0f  left %.0f  up %.0f  down %.0f kN\n" % [ship.caps[0], ship.caps[1], ship.caps[2], ship.caps[3], ship.caps[4], ship.caps[5]]
			t += "RCS %.0f kN (10%% of best vector)   Mass %.0f t\n" % [ship.rcs_cap, ship.mass]

		"Combat":
			refresh_weapons()
			t += "%d turret(s) selected\n" % arena.sel_weapons.size()
			if ship.target != null and is_instance_valid(ship.target) and ship.target.alive:
				t += "Main lock: [color=#ffe680]%s[/color]  %d m  hull %d%%" % [ship.target.name, int(ship.global_position.distance_to(ship.target.global_position)), int(ship.target.hull_hp / ship.target.hull_hp_max * 100.0)]
			else:
				t += "No main lock (press T)"
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
				var col := "#ff4030" if o.team != ship.team else "#70b0ff"
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


func _objective_text() -> String:
	var t := ""
	if arena.mode == "freematch":
		match arena.ruleset:
			"elim":
				t = "TEAM ELIMINATION\nOne life each. Be the last\nteam standing.\n\n"
			"dm":
				t = "DEATHMATCH\nEveryone is an enemy.\nFirst to %d kills wins.\n\n" % arena.kill_limit
			_:
				t = "TEAM DEATHMATCH\nUnlimited respawns. First\nteam to %d kills wins.\n\n" % arena.kill_limit
	else:
		t = "TEST RANGE\nNo objectives. Spawn dummies,\nfly, and fire at your own hull.\n\n"
	return t + arena.score_text()


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
		var bar := r["bar"] as ProgressBar
		bar.value = float(m["hp"]) / float(m["max"]) * 100.0
		bar.modulate = Color(1, 0.35, 0.3) if bar.value < 35.0 else Color.WHITE
		var nm: Label = r["nm"]
		var pw: Label = r["pw"]
		if not m["alive"]:
			nm.add_theme_color_override("font_color", RED)
			pw.text = "DEAD"
		else:
			nm.remove_theme_color_override("font_color")
			var extra := ""
			if m["type"] == "barrel" and int(m["ammo"]) >= 0:
				extra = " x%d" % int(m["ammo"])
			pw.text = ("%d%%" % int(float(m["frac"]) * 100.0) if float(m["demand"]) > 0.0 else "-") + extra
	var f := ship.forward()
	var stuck := ship.alive and not ship.can_move()
	if not ship.alive:
		lbl_telemetry.text = "SHIP DESTROYED"
	elif stuck:
		lbl_telemetry.text = "NO THRUST - keep firing or give up"
	else:
		lbl_telemetry.text = "SPD %3.0f  HDG %03.0f  PIT %+03.0f  %s %s" % [ship.linear_velocity.length(), fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0), rad_to_deg(asin(clampf(f.y, -1, 1))), "AST" if ship.assist else "MAN", "FP" if arena.rig.first_person else "CMD"]
	lbl_telemetry.add_theme_color_override("font_color", RED if (stuck or not ship.alive) else AMBER)
	bar_hull.value = ship.hull_hp / ship.hull_hp_max
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
	for b in [bar_hull, bar_power, bar_thr, bar_wpn]:
		(b as SegBar).queue_redraw()
	if ship.target != null and is_instance_valid(ship.target) and ship.target.alive:
		lbl_target.text = "TGT %s  %dm  hull %d%%" % [ship.target.name, int(ship.global_position.distance_to(ship.target.global_position)), int(ship.target.hull_hp / ship.target.hull_hp_max * 100.0)]
	else:
		lbl_target.text = "TGT none"
	btn_giveup.visible = stuck
	lbl_score.text = _objective_text()
	_refresh_sub()
	if int(_slow) % 2 == 0:
		_refresh_scoreboard()


func _refresh_scoreboard() -> void:
	var t := "[color=#f26b14][b]NAME[/b][/color]\n"
	for s in get_tree().get_nodes_in_group("ships"):
		var o := s as Ship
		var col := "#ffd070" if o == ship else ("#70a8ff" if o.team == ship.team else "#ff4a30")
		t += "[color=%s]%s[/color]\n" % [col, o.name]
	for s in get_tree().get_nodes_in_group("wrecks"):
		t += "[color=#666060][s]%s[/s][/color]\n" % (s as Ship).name
	score_box.text = t
