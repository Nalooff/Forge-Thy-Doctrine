class_name OrderTuner
extends Node3D
## "Tuning mode" for movement orders. Pressing an order button hides the sub panel and lets the player
## shape the order in the 3D view (plane, circle, ghost ship...). A click confirms, Esc cancels.
## Common controls: Alt + mouse (or PageUp/PageDown) = height, click-drag = optional final heading.
##
## kinds: point, route, chase, orbit, lookat, follow, lockdir, facepoint
## steps: plane (cursor on a horizontal plane), ship (pick a ship), ring (radius circle), offset (ghost ship)

var arena: Node
var active := false
var kind := ""
var step := ""
var plane_y := 0.0
var hover := Vector3.ZERO
var has_hover := false
var hover_ship: Ship
var target: Ship
var center := Vector3.ZERO
var radius := 300.0
var orbit_dir := 1.0
var points: Array = []
var banner := ""
var _press := false
var _press_pos := Vector2.ZERO
var _drag := false
var _anchor := Vector3.ZERO
var _head_dir := Vector3.ZERO     # horizontal unit vector of the dragged heading
var _head_pitch := 0.0
var _head_on := false
var _shift := false
var _prev_order := ""
var _prev_p := {}
var _mi: MeshInstance3D
var _im: ImmediateMesh


func _ready() -> void:
	_im = ImmediateMesh.new()
	_mi = WaypointViz.make_instance(_im)
	add_child(_mi)


# ------------------------------------------------------------------ start / end
func begin(k: String) -> void:
	if arena.player == null or not arena.player.alive:
		return
	if active:
		_end(true)
	kind = k
	active = true
	points = []
	target = null
	orbit_dir = 1.0
	_reset_press()
	_prev_order = arena.order
	_prev_p = (arena.order_p as Dictionary).duplicate(true)
	arena.rig.first_person = false
	arena._apply_mouse_mode()
	plane_y = arena.player.global_position.y
	step = "ship" if k in ["chase", "orbit", "lookat", "follow", "facepoint"] else "plane"
	has_hover = false
	_update_banner()
	arena.hud.hide_sub()


func _end(cancel: bool) -> void:
	active = false
	step = ""
	_reset_press()
	if cancel:
		arena.order = _prev_order
		arena.order_p = _prev_p
	if _im != null:
		_im.clear_surfaces()
	arena.hud.restore_sub()


func abort() -> void:
	active = false
	step = ""
	_reset_press()
	if _im != null:
		_im.clear_surfaces()


func cancel() -> void:
	if active:
		_end(true)
		arena.hud.say("Cancelled", Color(1.0, 0.8, 0.3))


func _reset_press() -> void:
	_press = false
	_drag = false
	_head_on = false
	_head_dir = Vector3.ZERO
	_head_pitch = 0.0


## While choosing a point or a direction the ship turns to look at the cursor.
func look_point() -> Variant:
	if active and step == "plane" and has_hover and kind in ["point", "route", "lockdir"]:
		return hover
	return null


func _update_banner() -> void:
	var common := "   Alt+mouse: height   Esc: cancel"
	match kind:
		"point":
			banner = "DRIVE TO POINT   move over the plane (your ship turns to look at it)   click: go   click-drag: also choose the final heading" + common
		"route":
			banner = "ROUTE   Shift+click adds a point, a plain click ends the route (drag = final heading)   points: %d" % points.size() + common
		"chase":
			banner = ("DRIVE TO SHIP   click the ship to follow" if step == "ship" else "DRIVE TO SHIP   mouse distance = distance to keep   click: confirm") + common
		"orbit":
			banner = ("ORBIT   click a ship, or empty space for a point" if step == "ship" else "ORBIT   mouse distance = radius   R: flip direction   click: confirm") + common
		"lookat":
			banner = "FACE   click a ship or a point (the ship turns and keeps its speed)" + common
		"follow":
			banner = ("FOLLOW OFFSET   click the leader ship" if step == "ship" else "FOLLOW OFFSET   place your ship relative to the leader   click: confirm   click-drag: also choose its heading") + common
		"lockdir":
			banner = "LOCK DIRECTION   point the arrow with the mouse   click: lock it (the ship keeps this heading while moving)" + common
		"facepoint":
			banner = "FACE POINT WHILE MOVING   click a ship or a point" + common


func status_line() -> String:
	var p: Ship = arena.player
	var s := "plane altitude %+d m" % int(plane_y - p.global_position.y)
	if step == "ring":
		s += "   radius %s" % WaypointViz.fmt_dist(radius)
	return s


# ------------------------------------------------------------------ input
func handle(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and kind == "orbit" and step == "ring":
			orbit_dir = -orbit_dir
			return true
		if event.keycode == KEY_PAGEUP or event.keycode == KEY_PAGEDOWN:
			plane_y += _alt_step() * 8.0 * (1.0 if event.keycode == KEY_PAGEUP else -1.0)
			hover.y = plane_y
			return true
		return false
	if event is InputEventMouseMotion:
		if event.alt_pressed or Input.is_key_pressed(KEY_ALT):
			if _drag:
				_head_pitch = clampf(_head_pitch - event.relative.y * 0.01, -1.4, 1.4)
			else:
				plane_y -= event.relative.y * _alt_step()
				hover.y = plane_y
				_anchor.y = plane_y if _press else _anchor.y
			return true
		_update_hover(event.position)
		if _press and (event.position - _press_pos).length() > 14.0 and has_hover:
			var d := hover - _anchor
			d.y = 0.0
			if d.length() > 0.001:
				_drag = true
				_head_on = true
				_head_dir = d.normalized()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if arena.hud.is_mouse_over_ui():
				return false
			_on_press(event.position, event.shift_pressed)
			return true
		if _press:
			_on_release()
			return true
	return false


func _alt_step() -> float:
	return clampf(arena.rig.cam.global_position.distance_to(arena.player.global_position) * 0.0025, 0.1, 300.0)


func heading() -> Vector3:
	if not _head_on:
		return Vector3.ZERO
	return Vector3(_head_dir.x * cos(_head_pitch), sin(_head_pitch), _head_dir.z * cos(_head_pitch)).normalized()


func _center_pos() -> Vector3:
	if target != null and is_instance_valid(target):
		return target.global_position
	return center


func _update_hover(mp: Vector2) -> void:
	hover_ship = arena.pick_ship(mp) if step == "ship" else null
	var h = arena._plane_hit(mp, plane_y)
	if h != null:
		hover = h
		has_hover = true
	if step == "ring" and has_hover:
		var c := _center_pos()
		var min_r := maxf(float(arena.player.stats["longest"]) * 1.2, 30.0)
		radius = clampf(Vector2(hover.x - c.x, hover.z - c.z).length(), min_r, 30000.0)


func _enter_ring() -> void:
	step = "ring"
	plane_y = _center_pos().y
	var pp: Vector3 = arena.player.global_position
	var c := _center_pos()
	radius = clampf(Vector2(pp.x - c.x, pp.z - c.z).length(), maxf(float(arena.player.stats["longest"]) * 1.2, 30.0), 30000.0)
	has_hover = false
	_update_banner()


func _enter_offset() -> void:
	step = "offset"
	plane_y = target.global_position.y
	has_hover = false
	_update_banner()


func _on_press(mp: Vector2, shift: bool) -> void:
	_update_hover(mp)
	match step:
		"plane":
			if not has_hover:
				return
			if kind == "lockdir":
				var d: Vector3 = hover - arena.player.global_position
				arena.set_facing_lock(d)
				_end(false)
				return
			_anchor = hover
			_press = true
			_press_pos = mp
			_drag = false
			_head_on = false
			_shift = shift
		"ship":
			if hover_ship != null:
				target = hover_ship
				match kind:
					"chase", "orbit":
						_enter_ring()
					"follow":
						_enter_offset()
					"lookat":
						arena.order_lookat(target, Vector3.ZERO)
						_end(false)
					"facepoint":
						arena.set_facing_point(target, Vector3.ZERO)
						_end(false)
			elif kind in ["orbit", "lookat", "facepoint"] and has_hover:
				center = hover
				match kind:
					"orbit":
						_enter_ring()
					"lookat":
						arena.order_lookat(null, hover)
						_end(false)
					"facepoint":
						arena.set_facing_point(null, hover)
						_end(false)
		"ring":
			if has_hover:
				var c := _center_pos()
				if kind == "orbit":
					arena.order_orbit(target, center, radius, plane_y - c.y, orbit_dir)
				else:
					arena.order_chase(target, radius)
				_end(false)
		"offset":
			if not has_hover:
				return
			_anchor = hover
			_press = true
			_press_pos = mp
			_drag = false
			_head_on = false


func _on_release() -> void:
	_press = false
	var hd := heading()
	if step == "plane":
		if kind == "point":
			arena.order_goto(_anchor, hd)
			_end(false)
		elif kind == "route":
			points.append(_anchor)
			if _shift:
				_reset_press()
				_update_banner()
			else:
				arena.order_route(points, hd)
				_end(false)
	elif step == "offset":
		var inv: Basis = target.global_transform.basis.inverse()
		arena.order_follow(target, inv * (_anchor - target.global_position), inv * hd if hd.length() > 0.1 else Vector3.ZERO)
		_end(false)


# ------------------------------------------------------------------ drawing
func _process(_delta: float) -> void:
	if _im == null:
		return
	_im.clear_surfaces()
	if not active or arena.player == null or not is_instance_valid(arena.player) or not arena.player.alive:
		return
	var cam: Camera3D = arena.rig.cam
	var sp: Vector3 = arena.player.global_position
	var amber := Color(1.0, 0.72, 0.22, 0.95)
	var dim := Color(1.0, 0.7, 0.2, 0.35)
	var grid := Color(0.9, 0.42, 0.12, 0.22)
	var origin := sp
	if step in ["ring", "offset"]:
		origin = _center_pos()
	var camd := cam.global_position.distance_to(origin)
	var ext := WaypointViz.nice(maxf(camd * 0.9, 200.0))
	var sp_grid := WaypointViz.nice(ext / 8.0)
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	# the plane
	var n := int(ceil(ext / sp_grid))
	var gx: float = floorf(origin.x / sp_grid) * sp_grid
	var gz: float = floorf(origin.z / sp_grid) * sp_grid
	for i in range(-n, n + 1):
		WaypointViz.s_line(_im, Vector3(gx + i * sp_grid, plane_y, origin.z - ext), Vector3(gx + i * sp_grid, plane_y, origin.z + ext), grid)
		WaypointViz.s_line(_im, Vector3(origin.x - ext, plane_y, gz + i * sp_grid), Vector3(origin.x + ext, plane_y, gz + i * sp_grid), grid)
	# height reference: from the ship straight to the plane
	if absf(plane_y - sp.y) > 0.5:
		WaypointViz.s_line(_im, sp, Vector3(sp.x, plane_y, sp.z), dim)
		WaypointViz.s_circle(_im, Vector3(sp.x, plane_y, sp.z), maxf(float(arena.player.stats["longest"]) * 0.5, 2.0), dim)
	if hover_ship != null and is_instance_valid(hover_ship):
		WaypointViz.s_circle(_im, hover_ship.global_position, maxf(float(hover_ship.stats["longest"]) * 0.9, 6.0), amber)
	if target != null and is_instance_valid(target):
		WaypointViz.s_circle(_im, target.global_position, maxf(float(target.stats["longest"]) * 0.9, 6.0), amber)
	var u := clampf(cam.global_position.distance_to(hover) * 0.012, 1.5, 4000.0)
	if step == "plane" and has_hover:
		var at := _anchor if _press else hover
		WaypointViz.s_circle(_im, Vector3(at.x, plane_y, at.z), u * 2.2, amber)
		WaypointViz.s_diamond(_im, at, u * 0.8, amber)
		WaypointViz.s_line(_im, sp, at, dim)
		var prev := sp
		for q in points:
			WaypointViz.s_diamond(_im, q, u * 0.8, amber)
			WaypointViz.s_line(_im, prev, q, dim)
			prev = q
		if _head_on:
			WaypointViz.s_arrow(_im, _anchor, heading(), u * 14.0, amber)
	elif step == "ring" and has_hover:
		var c := _center_pos()
		var cc := Vector3(c.x, plane_y, c.z)
		WaypointViz.s_circle(_im, cc, radius, amber)
		if kind == "orbit":
			WaypointViz.s_chevrons(_im, cc, radius, orbit_dir, amber)
		WaypointViz.s_line(_im, cc, hover, dim)
		WaypointViz.s_diamond(_im, hover, u * 0.6, amber)
	elif step == "offset" and has_hover and target != null and is_instance_valid(target):
		var at2 := _anchor if _press else hover
		var tb: Basis = target.global_transform.basis
		var gb := tb
		if _head_on:
			gb = Basis.looking_at(heading(), Vector3.UP)
		WaypointViz.s_box(_im, at2, gb, Vector3(float(arena.player.stats["beam"]), float(arena.player.stats["height"]), float(arena.player.stats["length"])), amber)
		WaypointViz.s_line(_im, target.global_position, at2, dim)
		WaypointViz.s_arrow(_im, at2, gb * Vector3(0, 0, -1), float(arena.player.stats["longest"]) * 1.4, amber)
	_im.surface_end()
