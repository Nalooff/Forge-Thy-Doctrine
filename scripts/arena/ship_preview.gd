class_name ShipPreview
extends Control
## Panel 1 of the command console: the live 3D model of the player's ship.
##
## Tabs (set by the HUD, see TABS):
##   Basic 3D  - the hull as glass with every module visible inside it. Hover a module or a piece of
##               hull for its info card, click to pin it.
##   Exploded  - the hull is cut into sections that slide apart and every module is pushed away from
##               the others (no two modules overlap), with leader lines back to where they sit.
##   Onion     - the ship is cut into decks (horizontal layers). Pick a deck: everything above it is
##               hidden, the cut shows the hull outline and the footprint of the modules on that deck.
##   Systems   - command / engine / turret links, or the power grid, drawn on the model.
## Drag = orbit, wheel = zoom, double click = reset the camera.

signal expand_requested(on: bool)

const BASIC := 0
const EXPLODED := 1
const ONION := 2
const SYSTEMS := 3
const TABS := ["Basic 3D", "Exploded", "Onion", "Systems"]
const HULL_MODES := ["Glass", "Solid", "Wire", "Off"]
const ABBR := {
	"commander_post": "CMD", "generator": "GEN", "engine_room": "ENG", "turret_bay": "BAY",
	"turret_control": "TCU", "radar_room": "RAD", "thruster": "THR", "barrel": "BRL",
}
const AMBER := Color(1.0, 0.66, 0.22)
const ORANGE_DIM := Color(0.6, 0.27, 0.07)
const EMBER := Color(1.0, 0.82, 0.45)
const RED := Color(0.9, 0.12, 0.08)
const BLUE := Color(0.35, 0.65, 1.0)
const GREEN := Color(0.45, 0.9, 0.4)
const GREY := Color(0.5, 0.46, 0.44)
const FAR := 1.0e9

## One shader for hull skin and module boxes: clip height (onion), dimming below the chosen deck,
## back faces in a dark colour (so a cut looks capped), fresnel rim so a glass hull keeps its outline.
const SKIN_SRC := """
shader_type spatial;
render_mode cull_disabled, @DEPTH@;
uniform vec4 col : source_color = vec4(0.6, 0.55, 0.5, 1.0);
uniform vec4 back_col : source_color = vec4(0.12, 0.06, 0.04, 1.0);
uniform float emit = 0.3;
uniform float alpha_mul = 1.0;
uniform float rim = 0.0;
uniform float clip_y = 1.0e9;
uniform float dim_y = -1.0e9;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (wpos.y > clip_y) {
		discard;
	}
	vec3 c = FRONT_FACING ? col.rgb : back_col.rgb;
	float a = (FRONT_FACING ? col.a : back_col.a) * alpha_mul;
	float k = 1.0;
	if (wpos.y < dim_y) {
		k = 0.45;
		a *= 0.6;
	}
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	ALBEDO = c * k;
	EMISSION = c * emit * k + col.rgb * f * rim;
	ALPHA = clamp(a + f * rim * 0.45, 0.0, 1.0);
	ROUGHNESS = 0.7;
}
"""

const LINE_SRC := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0);
uniform float clip_y = 1.0e9;
uniform float dim_y = -1.0e9;
uniform float ghost = 0.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float a = col.a;
	if (wpos.y > clip_y) {
		if (ghost > 0.5) {
			a *= 0.16;
		} else {
			discard;
		}
	}
	if (wpos.y < dim_y) {
		a *= 0.5;
	}
	ALBEDO = col.rgb;
	ALPHA = a;
}
"""

static var _skin_shaders := {}
static var _line_shader: Shader
static var _wire_cache: ArrayMesh

var ship: Ship
var view := BASIC
var expanded := false

# 3D scene
var vp: SubViewport
var root3: Node3D
var world: Node3D
var cam: Camera3D
var items: Array = []        # one entry per module: node, fill, wire, materials, home / exploded / displayed position
var sections: Array = []     # one entry per hull segment between two rings
var by_item := {}
var all_tris: Array = []
var hull_box := AABB()
var longest := 10.0
var ov_lines: ImmediateMesh
var cut_fill: ImmediateMesh
var cut_lines: ImmediateMesh
var deck_lines: ImmediateMesh
var com_mi: MeshInstance3D
var fwd_mi: MeshInstance3D

# camera
var yaw := 0.7
var pitch := -0.35
var zoom := 1.0
var dist := 12.0
var center := Vector3.ZERO
var radius := 6.0
var dragging := false
var _moved := 0.0
var _t := 0.0
var _hover_t := 0.0
var _inside := false

# view state
var hull_mode := 0
var show_com := true
var labels := [false, true, true, true]
var spread := 1.0
var spread_cur := 0.0
var show_lines := true
var layers := 6
var layer := 3               # 0 = lowest deck, layers = all decks
var ghost_above := true
var sys_mode := 0            # 0 links, 1 power
var hover := {}
var selected := {}
var _cut_dirty := true
var sys_segs: Array = []     # [world a, world b, colour] of the links / power lines, drawn thick in 2D
var _onion_seen := false

# overlay controls
var ui: Control
var layer2d: Control
var bars: Array = []
var btn_hull: Button
var btn_expand: Button
var layer_box: VBoxContainer
var layer_slider: VSlider
var layer_label: Label
var decks_label: Label


# ================================================================== setup
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(108, 100)
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
	layer2d = Control.new()
	layer2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer2d.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer2d.draw.connect(_draw_overlay)
	add_child(layer2d)
	root3 = Node3D.new()
	vp.add_child(root3)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.5)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	root3.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 34.0
	root3.add_child(cam)
	_build_ui()


static func _skin_shader(depth_always: bool) -> Shader:
	var key := "always" if depth_always else "opaque"
	if not _skin_shaders.has(key):
		var sh := Shader.new()
		sh.code = SKIN_SRC.replace("@DEPTH@", "depth_draw_always" if depth_always else "depth_draw_opaque")
		_skin_shaders[key] = sh
	return _skin_shaders[key]


static func _lines_shader() -> Shader:
	if _line_shader == null:
		_line_shader = Shader.new()
		_line_shader.code = LINE_SRC
	return _line_shader


static func _unit_wire() -> ArrayMesh:
	if _wire_cache != null:
		return _wire_cache
	var corners: Array = []
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				corners.append(Vector3(sx, sy, sz))
	var v := PackedVector3Array()
	for i in 8:
		for j in range(i + 1, 8):
			var d: Vector3 = (corners[i] as Vector3) - (corners[j] as Vector3)
			var n := int(absf(d.x) > 0.1) + int(absf(d.y) > 0.1) + int(absf(d.z) > 0.1)
			if n == 1:
				v.append(corners[i])
				v.append(corners[j])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	_wire_cache = ArrayMesh.new()
	_wire_cache.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return _wire_cache


func _line_mat(col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _lines_shader()
	m.render_priority = 1
	m.set_shader_parameter("col", col)
	return m


func _dyn_mesh(vertex_colors_no_depth: bool, priority := 3) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = vertex_colors_no_depth
	mat.render_priority = priority
	mi.material_override = mat
	world.add_child(mi)
	return mesh


static func _tris_mesh(tris: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if tris.is_empty():
		return mesh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for t in tris:
		var n: Vector3 = -((t[1] as Vector3) - (t[0] as Vector3)).cross((t[2] as Vector3) - (t[0] as Vector3))
		n = n.normalized() if n.length() > 1e-9 else Vector3.UP
		for k in 3:
			verts.append(t[k])
			norms.append(n)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _section_wire(rings: Array, i: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var np := ShipData.RING_PTS
	for r in [i, i + 1]:
		for p in np:
			v.append(ShipData.ring_vertex(rings[r], p))
			v.append(ShipData.ring_vertex(rings[r], (p + 1) % np))
	for p in np:
		v.append(ShipData.ring_vertex(rings[i], p))
		v.append(ShipData.ring_vertex(rings[i + 1], p))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return mesh


## Build the model of `s` (called when the ship is spawned or respawned).
func bind(s: Ship) -> void:
	ship = s
	hover = {}
	selected = {}
	if world != null:
		world.queue_free()
	world = Node3D.new()
	root3.add_child(world)
	items.clear()
	sections.clear()
	by_item.clear()
	var rings: Array = s.bp["rings"]
	longest = maxf(float(s.stats["longest"]), 2.0)
	hull_box = ShipData.hull_bounds(rings)
	all_tris = ShipData.hull_triangles(rings)
	# hull sections
	var ns := rings.size() - 1
	var np := ShipData.RING_PTS
	var per := np * 2
	for i in range(ns):
		var st: Array = all_tris.slice(i * per, (i + 1) * per)
		if i == 0:
			st.append_array(all_tris.slice(ns * per, ns * per + np))
		if i == ns - 1:
			st.append_array(all_tris.slice(ns * per + np, ns * per + 2 * np))
		var node := Node3D.new()
		world.add_child(node)
		var skin := MeshInstance3D.new()
		skin.mesh = _tris_mesh(st)
		var mat := ShaderMaterial.new()
		mat.shader = _skin_shader(false)
		mat.render_priority = 2
		skin.material_override = mat
		node.add_child(skin)
		var wi := MeshInstance3D.new()
		wi.mesh = _section_wire(rings, i)
		var wmat := _line_mat(Color(0.85, 0.4, 0.12, 0.5))
		wi.material_override = wmat
		node.add_child(wi)
		var bmin := Vector3(INF, INF, INF)
		var bmax := Vector3(-INF, -INF, -INF)
		for t in st:
			for k in 3:
				bmin = bmin.min(t[k])
				bmax = bmax.max(t[k])
		sections.append({
			"i": i, "node": node, "skin": skin, "wire": wi, "mat": mat, "wmat": wmat, "tris": st,
			"z0": float(rings[i]["z"]), "z1": float(rings[i + 1]["z"]), "exp": Vector3.ZERO,
			"box": AABB(bmin, bmax - bmin),
		})
	# modules
	var unit := _unit_wire()
	for m in s.mods:
		var node := Node3D.new()
		world.add_child(node)
		var sz: Vector3 = m["size"]
		var fill := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz * 0.97
		fill.mesh = bm
		var fmat := ShaderMaterial.new()
		fmat.shader = _skin_shader(true)
		fmat.render_priority = 0
		fmat.set_shader_parameter("rim", 0.35)
		fill.material_override = fmat
		node.add_child(fill)
		var wire := MeshInstance3D.new()
		wire.mesh = unit
		wire.scale = sz
		var wmat2 := _line_mat(Color.WHITE)
		wire.material_override = wmat2
		node.add_child(wire)
		var it := {
			"m": m, "id": int(m["id"]), "node": node, "fill": fill, "wire": wire, "fmat": fmat, "wmat": wmat2,
			"home": m["pos"], "exp": m["pos"], "disp": m["pos"],
		}
		items.append(it)
		by_item[int(m["id"])] = it
		node.position = m["pos"]
		hull_box = hull_box.merge(AABB((m["pos"] as Vector3) - sz * 0.5, sz))
	_layout_explode()
	# dynamic overlays
	ov_lines = _dyn_mesh(true, 5)
	cut_fill = _dyn_mesh(false, 4)
	cut_lines = _dyn_mesh(true, 5)
	deck_lines = _dyn_mesh(false, 3)
	# centre of mass marker + bow arrow
	com_mi = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = longest * 0.018
	sm.height = longest * 0.036
	sm.radial_segments = 12
	sm.rings = 6
	com_mi.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = EMBER
	cmat.no_depth_test = true
	cmat.render_priority = 6
	com_mi.material_override = cmat
	com_mi.position = s.stats["com"]
	world.add_child(com_mi)
	fwd_mi = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = longest * 0.022
	cone.height = longest * 0.07
	fwd_mi.mesh = cone
	fwd_mi.rotate_x(-PI * 0.5)
	fwd_mi.material_override = cmat
	fwd_mi.position = Vector3(hull_box.get_center().x, hull_box.get_center().y, hull_box.position.z - longest * 0.06)
	world.add_child(fwd_mi)
	# decks: about one per metre-ish of height, scaled with the ship
	var hh := maxf(hull_box.size.y, 0.5)
	layers = clampi(int(round(hh / maxf(longest * 0.05, 1.0))), 4, 12)
	layer = layers / 2
	_sync_layer_ui()
	_cut_dirty = true
	var b := _view_bounds()
	center = b.get_center()
	radius = maxf(b.size.length() * 0.5, 1.0)
	dist = _target_dist()
	_apply_view()
	refresh()


# ================================================================== exploded layout
func _section_of(z: float) -> int:
	for sc in sections:
		if z <= float(sc["z1"]) + 1e-4:
			return int(sc["i"])
	return maxi(sections.size() - 1, 0)


func _layout_explode() -> void:
	var rings: Array = ship.bp["rings"]
	var ns := sections.size()
	var gap := longest * 0.22
	for sc in sections:
		sc["exp"] = Vector3(0, 0, (float(sc["i"]) - float(ns - 1) * 0.5) * gap)
	var n := items.size()
	var pos: Array = []
	var half: Array = []
	var idx := 0
	for it in items:
		var m: Dictionary = it["m"]
		var p: Vector3 = it["home"]
		var sz: Vector3 = m["size"]
		var si := _section_of(p.z)
		var off: Vector3 = (sections[si]["exp"] as Vector3) if si < ns else Vector3.ZERO
		var poly := ShipData.ring_pts_at(rings, clampf(p.z, float(rings[0]["z"]), float(rings[rings.size() - 1]["z"])))
		var c2 := Vector2.ZERO
		for q in poly:
			c2 += q
		if not poly.is_empty():
			c2 /= float(poly.size())
		var d2 := Vector2(p.x, p.y) - c2
		var push := Vector3.ZERO
		if String(m["kind"]) == "external":
			var dir := d2.normalized() if d2.length() > 0.05 else Vector2(0, 1)
			push = Vector3(dir.x, dir.y, 0.0) * longest * 0.2
		else:
			var ang := float(idx) * 2.399963
			push = Vector3(cos(ang), sin(ang), 0.0) * longest * 0.2 + Vector3(d2.x, d2.y, 0.0) * 1.2
		pos.append(p + off + push)
		half.append(sz * 0.5)
		idx += 1
	# relax: push overlapping boxes apart along the axis of least penetration
	var pad := longest * 0.04
	var iters := 70 if n <= 60 else 18
	for _it in range(iters):
		var moved := false
		for i in range(n):
			for j in range(i + 1, n):
				var d: Vector3 = (pos[j] as Vector3) - (pos[i] as Vector3)
				var hs: Vector3 = (half[i] as Vector3) + (half[j] as Vector3) + Vector3(pad, pad, pad)
				var ox := hs.x - absf(d.x)
				var oy := hs.y - absf(d.y)
				var oz := hs.z - absf(d.z)
				if ox <= 0.0 or oy <= 0.0 or oz <= 0.0:
					continue
				moved = true
				var sgn := 1.0 if (i + j) % 2 == 0 else -1.0
				if ox <= oy and ox <= oz:
					var s := (1.0 if d.x > 0.0 else (-1.0 if d.x < 0.0 else sgn)) * ox * 0.5
					pos[i] = (pos[i] as Vector3) - Vector3(s, 0, 0)
					pos[j] = (pos[j] as Vector3) + Vector3(s, 0, 0)
				elif oy <= oz:
					var s2 := (1.0 if d.y > 0.0 else (-1.0 if d.y < 0.0 else sgn)) * oy * 0.5
					pos[i] = (pos[i] as Vector3) - Vector3(0, s2, 0)
					pos[j] = (pos[j] as Vector3) + Vector3(0, s2, 0)
				else:
					var s3 := (1.0 if d.z > 0.0 else (-1.0 if d.z < 0.0 else sgn)) * oz * 0.5
					pos[i] = (pos[i] as Vector3) - Vector3(0, 0, s3)
					pos[j] = (pos[j] as Vector3) + Vector3(0, 0, s3)
		if not moved:
			break
	for k in range(n):
		(items[k] as Dictionary)["exp"] = pos[k]


# ================================================================== decks
func deck_range(k: int) -> Vector2:
	var y0 := hull_box.position.y
	var h := hull_box.size.y / float(maxi(layers, 1))
	return Vector2(y0 + float(k) * h, y0 + float(k + 1) * h)


func _clip_y() -> float:
	if view != ONION or layer >= layers:
		return FAR
	return deck_range(layer).y


func _dim_y() -> float:
	if view != ONION or layer >= layers or layer <= 0:
		return -FAR
	return deck_range(layer).x


func deck_of_y(y: float) -> int:
	var h := hull_box.size.y / float(maxi(layers, 1))
	if h <= 0.0:
		return 0
	return clampi(int(floor((y - hull_box.position.y) / h)), 0, layers - 1)


func set_layer(k: int) -> void:
	layer = clampi(k, 0, layers)
	_sync_layer_ui()
	_cut_dirty = true
	refresh()


func set_layers(n: int) -> void:
	layers = clampi(n, 2, 16)
	layer = mini(layer, layers)
	_sync_layer_ui()
	_cut_dirty = true
	refresh()


func _item_above_clip(it: Dictionary) -> bool:
	var cy := _clip_y()
	if cy >= FAR:
		return false
	var m: Dictionary = it["m"]
	var p: Vector3 = it["disp"]
	var sz: Vector3 = m["size"]
	return p.y - sz.y * 0.5 >= cy


## Intersection of the hull skin with the plane y = h, as a list of [Vector2(x, z), Vector2(x, z)].
func _slice_segments(h: float) -> Array:
	var segs: Array = []
	for t in all_tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var pts: Array = []
		for e in [[a, b], [b, c], [c, a]]:
			var p: Vector3 = e[0]
			var q: Vector3 = e[1]
			var dp := p.y - h
			var dq := q.y - h
			if (dp < 0.0) != (dq < 0.0):
				var k := dp / (dp - dq)
				pts.append(Vector2(lerpf(p.x, q.x, k), lerpf(p.z, q.z, k)))
		if pts.size() == 2:
			segs.append([pts[0], pts[1]])
	return segs


static func _qk(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 400.0), roundi(p.y * 400.0))


## Chain loose segments into closed polygons.
static func _chain(segs: Array) -> Array:
	var ends := {}
	for i in range(segs.size()):
		for e in [0, 1]:
			var k := _qk(segs[i][e])
			if not ends.has(k):
				ends[k] = []
			(ends[k] as Array).append(i)
	var used := {}
	var polys: Array = []
	for i in range(segs.size()):
		if used.has(i):
			continue
		used[i] = true
		var poly: Array = [segs[i][0]]
		var cur: Vector2 = segs[i][1]
		var guard := 0
		while guard < 4000:
			guard += 1
			poly.append(cur)
			var nxt := -1
			for cand in ends.get(_qk(cur), []):
				if not used.has(cand):
					nxt = cand
					break
			if nxt < 0:
				break
			used[nxt] = true
			var s0: Vector2 = segs[nxt][0]
			var s1: Vector2 = segs[nxt][1]
			cur = s1 if _qk(s0) == _qk(cur) else s0
		if poly.size() >= 4:
			polys.append(poly)
	return polys


func _rebuild_cut() -> void:
	_cut_dirty = false
	var fp := PackedVector3Array()
	var fc := PackedColorArray()
	var lp := PackedVector3Array()
	var lc := PackedColorArray()
	var dp := PackedVector3Array()
	var dc := PackedColorArray()
	if view == ONION and ship != null:
		var cy := _clip_y()
		# every deck boundary as a faint outline (the "onion rings")
		for k in range(layers + 1):
			var y := hull_box.position.y + hull_box.size.y * float(k) / float(maxi(layers, 1))
			if y > cy and not ghost_above:
				continue
			var lit := layer < layers and (k == layer or k == layer + 1)
			var col := Color(1.0, 0.6, 0.2, 0.55) if lit else Color(0.9, 0.4, 0.12, 0.2)
			if y > cy:
				col.a *= 0.5
			for sg in _slice_segments(clampf(y, hull_box.position.y + 0.001, hull_box.end.y - 0.001)):
				dp.append(Vector3(sg[0].x, y, sg[0].y))
				dp.append(Vector3(sg[1].x, y, sg[1].y))
				dc.append(col)
				dc.append(col)
		# cut face at the top of the chosen deck
		if cy < FAR:
			var hy := clampf(cy, hull_box.position.y + 0.001, hull_box.end.y - 0.001)
			for poly in _chain(_slice_segments(hy)):
				var poly2 := PackedVector2Array()
				for q in poly:
					poly2.append(q)
				var tri := Geometry2D.triangulate_polygon(poly2)
				var fillc := Color(0.9, 0.38, 0.1, 0.26)
				for ti in tri:
					fp.append(Vector3(poly2[ti].x, cy, poly2[ti].y))
					fc.append(fillc)
				for i in range(poly2.size() - 1):
					lp.append(Vector3(poly2[i].x, cy, poly2[i].y))
					lp.append(Vector3(poly2[i + 1].x, cy, poly2[i + 1].y))
					lc.append(Color(1.0, 0.75, 0.3, 0.95))
					lc.append(Color(1.0, 0.75, 0.3, 0.95))
			# footprints of the modules the plane cuts through
			var eps := longest * 0.002
			for it in items:
				var m: Dictionary = it["m"]
				var p: Vector3 = it["disp"]
				var sz: Vector3 = m["size"]
				if p.y - sz.y * 0.5 < cy and p.y + sz.y * 0.5 > cy:
					var mc := _module_color(m)
					var x0 := p.x - sz.x * 0.5
					var x1 := p.x + sz.x * 0.5
					var z0 := p.z - sz.z * 0.5
					var z1 := p.z + sz.z * 0.5
					var y2 := cy + eps
					var f2 := Color(mc.r, mc.g, mc.b, 0.6)
					for v in [Vector3(x0, y2, z0), Vector3(x1, y2, z0), Vector3(x1, y2, z1), Vector3(x0, y2, z0), Vector3(x1, y2, z1), Vector3(x0, y2, z1)]:
						fp.append(v)
						fc.append(f2)
					var corners := [Vector3(x0, y2, z0), Vector3(x1, y2, z0), Vector3(x1, y2, z1), Vector3(x0, y2, z1)]
					for k2 in 4:
						lp.append(corners[k2])
						lp.append(corners[(k2 + 1) % 4])
						lc.append(mc.lightened(0.35))
						lc.append(mc.lightened(0.35))
	_flush(cut_fill, Mesh.PRIMITIVE_TRIANGLES, fp, fc)
	_flush(cut_lines, Mesh.PRIMITIVE_LINES, lp, lc)
	_flush(deck_lines, Mesh.PRIMITIVE_LINES, dp, dc)


func _flush(mesh: ImmediateMesh, prim: int, pts: PackedVector3Array, cols: PackedColorArray) -> void:
	mesh.clear_surfaces()
	if pts.is_empty():
		return
	mesh.surface_begin(prim)
	for i in range(pts.size()):
		mesh.surface_set_color(cols[i])
		mesh.surface_add_vertex(pts[i])
	mesh.surface_end()


# ================================================================== colours / state
func _module_color(m: Dictionary) -> Color:
	if not bool(m["alive"]):
		return Color(0.09, 0.08, 0.08)
	if view == SYSTEMS and sys_mode == 1:
		return _power_color(m)
	var def: Dictionary = ShipData.MODULES[String(m["type"])]
	var base: Color = def["color"]
	var f := clampf(float(m["hp"]) / maxf(float(m["max"]), 0.001), 0.0, 1.0)
	return base.lerp(Color(0.75, 0.06, 0.03), (1.0 - f) * 0.75)


func _needs_power(m: Dictionary) -> bool:
	return float(m["demand"]) > 0.0 or float(m["ms"]["idle"]) > 0.0


func _power_color(m: Dictionary) -> Color:
	if String(m["type"]) == "generator":
		return Color(1.0, 0.85, 0.25)
	if not _needs_power(m):
		return GREY
	var f := float(m["frac"])
	return GREEN if f >= 0.95 else (AMBER if f >= 0.5 else RED)


func module_status(m: Dictionary) -> Array:
	if not bool(m["alive"]):
		return ["DESTROYED", RED]
	if not bool(m["enabled"]):
		return ["OFFLINE (switched off)", AMBER]
	if float(m["demand"]) > 0.0 and float(m["frac"]) < 0.2:
		return ["UNPOWERED", RED]
	if float(m["demand"]) > 0.0 and float(m["frac"]) < 0.95:
		return ["LOW POWER  %d%%" % int(float(m["frac"]) * 100.0), AMBER]
	return ["ONLINE", GREEN]


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	if a["kind"] != b["kind"]:
		return false
	return int(a.get("id", a.get("sec", -1))) == int(b.get("id", b.get("sec", -1)))


func _is(h: Dictionary, kind: String, key: String, value: int) -> bool:
	return not h.is_empty() and String(h["kind"]) == kind and int(h[key]) == value


func set_view(v: int) -> void:
	view = clampi(v, 0, TABS.size() - 1)
	if view == ONION and not _onion_seen:
		_onion_seen = true
		layer = layers / 2
		_sync_layer_ui()
	_cut_dirty = true
	_apply_view()
	refresh()


## Everything that depends on the tab or on the hull mode.
func _apply_view() -> void:
	for i in range(bars.size()):
		(bars[i] as Control).visible = i == view
	if layer_box != null:
		layer_box.visible = view == ONION
	if com_mi != null:
		com_mi.visible = show_com and view != EXPLODED
		fwd_mi.visible = view != EXPLODED
	for sc in sections:
		(sc["skin"] as MeshInstance3D).visible = hull_mode <= 1
		(sc["wire"] as MeshInstance3D).visible = hull_mode != 3
	_hull_btn_text()


func _hull_btn_text() -> void:
	if btn_hull != null:
		btn_hull.text = "Hull: %s" % HULL_MODES[hull_mode]


## Re-colour everything (called a few times a second, and whenever the hover or a setting changes).
func refresh() -> void:
	if ship == null or not is_instance_valid(ship) or items.is_empty() and sections.is_empty():
		return
	var cy := _clip_y()
	var dy := _dim_y()
	var ghost := 1.0 if (view == ONION and ghost_above) else 0.0
	var integrity := clampf(ship.hull_hp / ship.hull_hp_max, 0.0, 1.0)
	var hc := Color(0.62, 0.55, 0.5).lerp(Color(0.5, 0.1, 0.06), 1.0 - integrity)
	var a_mul := 0.22
	var rim := 1.0
	match view:
		EXPLODED:
			a_mul = 0.16
		ONION:
			a_mul = 0.3
		SYSTEMS:
			a_mul = 0.12
	if hull_mode == 1:
		a_mul = 0.95 if view != ONION else 0.6
		rim = 0.15
	for sc in sections:
		var mat: ShaderMaterial = sc["mat"]
		var hov := _is(hover, "hull", "sec", int(sc["i"]))
		var sel := _is(selected, "hull", "sec", int(sc["i"]))
		mat.set_shader_parameter("col", hc)
		mat.set_shader_parameter("alpha_mul", a_mul + (0.14 if hov else 0.0) + (0.08 if sel else 0.0))
		mat.set_shader_parameter("rim", rim + (1.3 if hov else 0.0) + (0.6 if sel else 0.0))
		mat.set_shader_parameter("emit", 0.25)
		mat.set_shader_parameter("clip_y", cy)
		mat.set_shader_parameter("dim_y", dy)
		var wm: ShaderMaterial = sc["wmat"]
		wm.set_shader_parameter("col", EMBER if (hov or sel) else Color(0.85, 0.4, 0.12, 0.55))
		wm.set_shader_parameter("clip_y", cy)
		wm.set_shader_parameter("dim_y", dy)
		wm.set_shader_parameter("ghost", ghost)
	for it in items:
		var m: Dictionary = it["m"]
		var c := _module_color(m)
		var hov := _is(hover, "module", "id", int(it["id"]))
		var sel := _is(selected, "module", "id", int(it["id"]))
		var above := _item_above_clip(it)
		var fm: ShaderMaterial = it["fmat"]
		fm.set_shader_parameter("col", Color(c.r, c.g, c.b, 1.0 if bool(m["alive"]) else 0.8))
		fm.set_shader_parameter("back_col", c.darkened(0.55))
		fm.set_shader_parameter("emit", 1.0 if hov else (0.7 if sel else 0.4))
		fm.set_shader_parameter("clip_y", cy)
		fm.set_shader_parameter("dim_y", dy)
		var wm2: ShaderMaterial = it["wmat"]
		wm2.set_shader_parameter("col", Color.WHITE if (hov or sel) else Color(c.lightened(0.4), 0.95))
		wm2.set_shader_parameter("clip_y", cy)
		wm2.set_shader_parameter("dim_y", dy)
		wm2.set_shader_parameter("ghost", ghost)
		(it["fill"] as MeshInstance3D).visible = not above
		(it["wire"] as MeshInstance3D).visible = (not above) or (view == ONION and ghost_above)
	if _cut_dirty:
		_rebuild_cut()
	_rebuild_overlay()
	layer2d.queue_redraw()


func _rebuild_overlay() -> void:
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	sys_segs.clear()
	if ship != null and view == EXPLODED and show_lines and spread_cur > 0.02:
		for it in items:
			var a: Vector3 = it["home"]
			var b: Vector3 = it["disp"]
			if a.distance_to(b) > longest * 0.01:
				pts.append(a)
				pts.append(b)
				cols.append(Color(0.95, 0.55, 0.2, 0.15))
				cols.append(Color(0.95, 0.55, 0.2, 0.6))
	elif ship != null and view == SYSTEMS:
		if sys_mode == 0:
			for l in ship.bp["links"]:
				var ia := int(l[0])
				var ib := int(l[1])
				if not by_item.has(ia) or not by_item.has(ib):
					continue
				var ma: Dictionary = ship.by_id[ia]
				var mb: Dictionary = ship.by_id[ib]
				var col := _link_color(ma, mb)
				if _is(hover, "module", "id", ia) or _is(hover, "module", "id", ib):
					col = col.lightened(0.5)
				pts.append((by_item[ia] as Dictionary)["disp"])
				pts.append((by_item[ib] as Dictionary)["disp"])
				cols.append(col)
				cols.append(col)
		else:
			for m in ship.mods:
				if String(m["type"]) == "generator" or not _needs_power(m):
					continue
				var gen: Dictionary = {}
				var best := INF
				for g in ship.mods:
					if String(g["type"]) == "generator" and bool(g["alive"]):
						var dd := ((by_item[int(g["id"])] as Dictionary)["disp"] as Vector3).distance_to((by_item[int(m["id"])] as Dictionary)["disp"])
						if dd < best:
							best = dd
							gen = g
				if gen.is_empty():
					continue
				var col2 := _power_color(m)
				if not bool(m["alive"]):
					col2 = Color(0.3, 0.27, 0.27)
				col2.a = 0.85
				pts.append((by_item[int(gen["id"])] as Dictionary)["disp"])
				pts.append((by_item[int(m["id"])] as Dictionary)["disp"])
				cols.append(col2)
				cols.append(col2)
	if view == SYSTEMS:
		for i in range(0, pts.size() - 1, 2):
			sys_segs.append([pts[i], pts[i + 1], cols[i]])
	_flush(ov_lines, Mesh.PRIMITIVE_LINES, pts, cols)


func _link_color(ma: Dictionary, mb: Dictionary) -> Color:
	if not bool(ma["alive"]) or not bool(mb["alive"]):
		return Color(0.4, 0.34, 0.34, 0.7)
	var ta := String(ma["type"])
	var tb := String(mb["type"])
	if ta == "commander_post" or tb == "commander_post":
		return Color(0.4, 0.7, 1.0, 0.95)
	if ta == "thruster" or tb == "thruster":
		return Color(1.0, 0.6, 0.2, 0.95)
	return Color(1.0, 0.32, 0.25, 0.95)


# ================================================================== per frame
func _view_bounds() -> AABB:
	var b := AABB()
	var first := true
	for sc in sections:
		var bx: AABB = sc["box"]
		bx.position += (sc["node"] as Node3D).position
		b = bx if first else b.merge(bx)
		first = false
	for it in items:
		var m: Dictionary = it["m"]
		var sz: Vector3 = m["size"]
		var bx2 := AABB((it["disp"] as Vector3) - sz * 0.5, sz)
		b = bx2 if first else b.merge(bx2)
		first = false
	return b


func _target_dist() -> float:
	return radius * 0.8 / sin(deg_to_rad(cam.fov * 0.5)) / zoom


func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship) or sections.is_empty():
		return
	_t += delta
	# explode animation
	var target := spread if view == EXPLODED else 0.0
	spread_cur = lerpf(spread_cur, target, 1.0 - exp(-delta * 7.0))
	if absf(spread_cur - target) < 0.006:
		spread_cur = target
	for it in items:
		var p: Vector3 = (it["home"] as Vector3).lerp(it["exp"], spread_cur)
		it["disp"] = p
		(it["node"] as Node3D).position = p
	for sc in sections:
		(sc["node"] as Node3D).position = (sc["exp"] as Vector3) * spread_cur
	# camera
	var b := _view_bounds()
	center = center.lerp(b.get_center(), 1.0 - exp(-delta * 6.0))
	radius = lerpf(radius, maxf(b.size.length() * 0.5, 1.0), 1.0 - exp(-delta * 6.0))
	dist = lerpf(dist, _target_dist(), 1.0 - exp(-delta * 8.0))
	_inside = is_visible_in_tree() and get_global_rect().has_point(get_global_mouse_position())
	if not dragging and not _inside and selected.is_empty():
		yaw += delta * 0.3
	var off := Vector3(0, 0, dist).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	cam.look_at_from_position(center + off, center, Vector3.UP)
	cam.near = maxf(dist * 0.02, 0.05)
	cam.far = dist * 12.0 + radius * 4.0
	_hover_t += delta
	if _hover_t > 0.05:
		_hover_t = 0.0
		_update_hover()
	if view == EXPLODED or view == SYSTEMS:
		_rebuild_overlay()
	if _t > 0.25:
		_t = 0.0
		refresh()
	layer2d.queue_redraw()


func _update_hover() -> void:
	var nh := {}
	if _inside and not dragging and get_viewport().gui_get_hovered_control() == self:
		nh = pick_at(get_local_mouse_position())
	var changed := not _same(hover, nh)
	hover = nh
	if changed:
		refresh()


# ================================================================== picking
## What is under a point of this control? {} / {kind:"module", id} / {kind:"hull", sec, tri, face, y}
func pick_at(p: Vector2) -> Dictionary:
	if ship == null or items.is_empty() and sections.is_empty():
		return {}
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	var cy := _clip_y()
	var best_id := -1
	var best_mt := INF
	for it in items:
		if _item_above_clip(it):
			continue
		var m: Dictionary = it["m"]
		var sz: Vector3 = m["size"]
		var box := AABB((it["disp"] as Vector3) - sz * 0.5, sz)
		var hit = box.intersects_ray(o, d)
		if hit == null or (hit as Vector3).y > cy:
			continue
		var t := o.distance_to(hit as Vector3)
		if t < best_mt:
			best_mt = t
			best_id = int(it["id"])
	var best_hull := {}
	var best_ht := INF
	if hull_mode <= 2:
		for sc in sections:
			var so: Vector3 = (sc["node"] as Node3D).position
			var lo := o - so
			var tris: Array = sc["tris"]
			for ti in range(tris.size()):
				var tr: Array = tris[ti]
				var hit2 = Geometry3D.ray_intersects_triangle(lo, d, tr[0], tr[1], tr[2])
				if hit2 == null:
					continue
				var gh: Vector3 = (hit2 as Vector3) + so
				if gh.y > cy:
					continue
				var t2 := o.distance_to(gh)
				if t2 < best_ht:
					best_ht = t2
					var nrm: Vector3 = -((tr[1] as Vector3) - (tr[0] as Vector3)).cross((tr[2] as Vector3) - (tr[0] as Vector3))
					best_hull = {"kind": "hull", "sec": int(sc["i"]), "tri": ti, "face": _face_name(nrm), "y": gh.y}
	if best_id >= 0 and not (hull_mode == 1 and best_ht < best_mt):
		return {"kind": "module", "id": best_id}
	return best_hull


static func _face_name(n: Vector3) -> String:
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	if az >= ax and az >= ay:
		return "Bow" if n.z < 0.0 else "Stern"
	if ay >= ax:
		return "Dorsal (top)" if n.y > 0.0 else "Ventral (bottom)"
	return "Starboard (right)" if n.x > 0.0 else "Port (left)"


## Screen position (in this control) of a module's centre, for labels and tests.
func module_screen_pos(id: int) -> Vector2:
	if not by_item.has(id):
		return Vector2(-1, -1)
	return cam.unproject_position((by_item[id] as Dictionary)["disp"])


# ================================================================== info card
func _ln(text: String, col := EMBER) -> Dictionary:
	return {"t": text, "c": col}


func info_lines(h: Dictionary, max_lines := 99) -> Array:
	var out: Array = []
	if ship == null or h.is_empty():
		return out
	if String(h["kind"]) == "module":
		var id := int(h["id"])
		if not ship.by_id.has(id):
			return out
		var m: Dictionary = ship.by_id[id]
		var def: Dictionary = ShipData.MODULES[String(m["type"])]
		var ms: Dictionary = m["ms"]
		var sz: Vector3 = m["size"]
		out.append(_ln("%s #%d   %s" % [String(m["label"]), id, "INTERNAL" if String(m["kind"]) == "internal" else "EXTERNAL"], (def["color"] as Color).lightened(0.3)))
		var st := module_status(m)
		out.append(_ln(String(st[0]), st[1]))
		out.append({"t": "HP %d / %d" % [int(m["hp"]), int(m["max"])], "bar": clampf(float(m["hp"]) / maxf(float(m["max"]), 1.0), 0.0, 1.0)})
		if String(m["type"]) == "generator":
			out.append(_ln("Output %.1f MW" % float(ms["out"])))
		elif float(m["demand"]) > 0.0:
			out.append(_ln("Power draw %.1f MW  (%d%% supplied)" % [float(m["demand"]), int(float(m["frac"]) * 100.0)]))
		match String(m["type"]):
			"thruster":
				out.append(_ln("Thrust %.0f kN  %s" % [float(ms["thrust"]) * float(m["ef"]), ShipData.DIR_NAMES[int(m["dir"])]]))
				out.append(_ln(("Fed by Engine Room #%d" % int(m["engine"])) if int(m["engine"]) >= 0 else "NO ENGINE LINK", EMBER if int(m["engine"]) >= 0 else RED))
			"engine_room":
				out.append(_ln("Drives %d thruster(s)" % ShipData.linked_ids(ship.bp, id, "thruster").size()))
			"turret_bay":
				out.append(_ln("Rotates %d barrel(s), %d deg cone" % [(m["barrels"] as Array).size(), int(float(m["limit"]))]))
			"turret_control":
				out.append(_ln("Controls %d fixed barrel(s)" % ShipData.linked_ids(ship.bp, id, "barrel").size()))
			"barrel":
				var ws: Dictionary = m["ws"]
				out.append(_ln("%s  dmg %d  %.1f shots/s  range %d m" % [String(ws["kind"]).capitalize(), int(float(ws["damage"])), 1.0 / maxf(float(ws["interval"]), 0.01), int(float(ws["range"]))]))
				var mount := "Mounted on Bay #%d" % int(m["bay"]) if int(m["bay"]) >= 0 else "Fixed (aim with the ship)"
				out.append(_ln(mount + ("   ammo %d" % int(m["ammo"]) if int(m["ammo"]) >= 0 else "")))
			"radar_room":
				out.append(_ln("Detection range %d m" % int(ship.radar_range())))
			"commander_post":
				out.append(_ln("Commands %d module(s)" % ShipData.linked_ids(ship.bp, id).size()))
		out.append(_ln("Size %.1f x %.1f x %.1f m   mass %.1f t" % [sz.x, sz.y, sz.z, float(ms["mass"])], GREY))
		var names: Array = []
		for oid in ShipData.linked_ids(ship.bp, id):
			if ship.by_id.has(int(oid)):
				names.append("%s #%d" % [ABBR.get(String((ship.by_id[int(oid)] as Dictionary)["type"]), "?"), int(oid)])
		out.append(_ln("Links: %s" % (", ".join(names) if not names.is_empty() else "none"), GREY))
		var d0 := deck_of_y((m["pos"] as Vector3).y - sz.y * 0.5) + 1
		var d1 := deck_of_y((m["pos"] as Vector3).y + sz.y * 0.5 - 0.001) + 1
		out.append(_ln("Deck %s of %d" % [str(d0) if d0 == d1 else "%d-%d" % [d0, d1], layers], GREY))
	else:
		var sc: Dictionary = sections[int(h["sec"])]
		var ns := sections.size()
		var i := int(sc["i"])
		var sname := "Hull" if ns == 1 else ("Bow section" if i == 0 else ("Stern section" if i == ns - 1 else "Mid section %d" % i))
		out.append(_ln("HULL  -  %s" % String(h["face"]), AMBER))
		out.append(_ln("%s   (%d of %d)" % [sname, i + 1, ns]))
		var integ := clampf(ship.hull_hp / ship.hull_hp_max, 0.0, 1.0)
		out.append({"t": "Hull integrity %d / %d" % [int(ship.hull_hp), int(ship.hull_hp_max)], "bar": integ})
		var th := float(ship.bp["thickness"])
		out.append(_ln("Plating %.2f m   armour rating %.1f" % [th, th * ShipData.ARMOR_PROTECTION]))
		var ni := 0
		var ne := 0
		for it in items:
			var pz := (it["home"] as Vector3).z
			if pz >= float(sc["z0"]) - 1e-4 and pz <= float(sc["z1"]) + 1e-4 and _section_of(pz) == i:
				if String((it["m"] as Dictionary)["kind"]) == "internal":
					ni += 1
				else:
					ne += 1
		out.append(_ln("Section holds %d internal, %d external module(s)" % [ni, ne], GREY))
		out.append(_ln("z %+.1f .. %+.1f m   deck %d of %d" % [float(sc["z0"]), float(sc["z1"]), deck_of_y(float(h["y"])) + 1, layers], GREY))
	return out.slice(0, max_lines)


func _status_line() -> String:
	match view:
		EXPLODED:
			return "Hull sections and modules pulled apart.  Spread %d%%" % int(spread * 100.0)
		ONION:
			if layer >= layers:
				return "ALL %d DECKS" % layers
			var r := deck_range(layer)
			return "DECK %d / %d   y %+.1f .. %+.1f m   (above hidden)" % [layer + 1, layers, r.x, r.y]
		SYSTEMS:
			if sys_mode == 0:
				return "Links:  blue command   orange engine   red turret   grey broken"
			if ship.power_supply <= 0.0:
				return "NO POWER SOURCE"
			return "Power  %.1f / %.1f MW (%d%%)   green ok  amber short  red starved" % [ship.power_demand, ship.power_supply, int(clampf(ship.power_frac, 0.0, 1.0) * 100.0)]
	return "%.0f m   %.0f t   %d modules" % [longest, float(ship.stats["mass"]), ship.mods.size()]


func _draw_overlay() -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var font: Font = UiStyle.body_font()
	var fs := 10 if expanded else 8
	# links / power lines, thick and above the 3D
	for sg in sys_segs:
		var pa: Vector3 = sg[0]
		var pb: Vector3 = sg[1]
		if cam.is_position_behind(pa) or cam.is_position_behind(pb):
			continue
		var sa := cam.unproject_position(pa)
		var sb2 := cam.unproject_position(pb)
		var lc: Color = sg[2]
		layer2d.draw_line(sa, sb2, Color(0, 0, 0, 0.8), 4.0 if expanded else 3.0, true)
		layer2d.draw_line(sa, sb2, lc, 2.2 if expanded else 1.6, true)
		layer2d.draw_circle(sa, 2.6, lc)
		layer2d.draw_circle(sb2, 2.6, lc)
	# module labels
	if labels[view]:
		for it in items:
			if _item_above_clip(it) or not (it["fill"] as MeshInstance3D).visible:
				continue
			var wp: Vector3 = (it["node"] as Node3D).position
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			if not Rect2(Vector2.ZERO, layer2d.size).has_point(sp):
				continue
			var m: Dictionary = it["m"]
			var txt := "%s %d" % [ABBR.get(String(m["type"]), "?"), int(it["id"])]
			Hud.outlined(layer2d, txt, sp + Vector2(-10, 3), fs, _module_color(m).lightened(0.45))
	# status line above the bottom bar
	Hud.outlined(layer2d, _status_line(), Vector2(5, layer2d.size.y - 23), fs, Color(1.0, 0.8, 0.4))
	# info card: what is under the mouse, else the pinned part
	var shown := hover if not hover.is_empty() else selected
	if not shown.is_empty():
		var lines := info_lines(shown, 15 if expanded else 5)
		var lh := float(fs) + 3.0
		var w := 0.0
		for l in lines:
			w = maxf(w, font.get_string_size(String(l["t"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		w = minf(w + 14.0, layer2d.size.x - 68.0 if not expanded else layer2d.size.x * 0.55)
		var h := lines.size() * lh + 9.0
		var r := Rect2(4, 4, w, h)
		layer2d.draw_rect(r, Color(0.02, 0.01, 0.01, 0.84))
		layer2d.draw_rect(r, ORANGE_DIM, false, 1.0)
		var y := 4.0 + lh
		for l in lines:
			if l.has("bar"):
				var bw := w - 10.0
				layer2d.draw_rect(Rect2(9, y - fs + 1, bw, fs - 1), Color(0.14, 0.07, 0.05))
				var f: float = l["bar"]
				layer2d.draw_rect(Rect2(9, y - fs + 1, bw * f, fs - 1), RED if f < 0.35 else (AMBER if f < 0.7 else GREEN))
				layer2d.draw_string(font, Vector2(12, y - 1), String(l["t"]), HORIZONTAL_ALIGNMENT_LEFT, bw, fs - 1, Color(0.04, 0.02, 0.01))
			else:
				layer2d.draw_string(font, Vector2(9, y), String(l["t"]), HORIZONTAL_ALIGNMENT_LEFT, w - 10.0, fs, l["c"])
			y += lh
		if hover.is_empty():
			Hud.outlined(layer2d, "pinned - click empty space to release", Vector2(8, r.end.y + lh), fs - 1, GREY)
	elif not expanded:
		Hud.outlined(layer2d, "hover / click a part", Vector2(5, 12), fs - 1, Color(0.6, 0.35, 0.15))


# ================================================================== input
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				dragging = true
				_moved = 0.0
				if mb.double_click:
					yaw = 0.7
					pitch = -0.35
					zoom = 1.0
			else:
				if dragging and _moved < 5.0:
					selected = pick_at(mb.position)
					refresh()
				dragging = false
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 1.12, 0.4, 4.0)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 1.12, 0.4, 4.0)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		_moved += mm.relative.length()
		yaw -= mm.relative.x * 0.01
		pitch = clampf(pitch - mm.relative.y * 0.01, -1.4, 1.4)
		accept_event()


# ================================================================== controls
func _btn(text: String, parent: Control, cb: Callable, toggle := false, pressed := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 8)
	b.custom_minimum_size = Vector2(0, 15)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _btn_style(st))
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.02, 0.01))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.05, 0.02, 0.01))
	if toggle:
		b.toggled.connect(cb)
	else:
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func _btn_style(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var pressed := state.contains("pressed")
	sb.bg_color = Color(0.95, 0.42, 0.08) if pressed else (Color(0.2, 0.1, 0.06) if state.contains("hover") else Color(0.09, 0.05, 0.04, 0.92))
	sb.border_color = ORANGE_DIM if not pressed else EMBER
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func _build_ui() -> void:
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	for v in range(TABS.size()):
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.anchor_left = 0.0
		hb.anchor_right = 1.0
		hb.anchor_top = 1.0
		hb.anchor_bottom = 1.0
		hb.offset_left = 3
		hb.offset_right = -3
		hb.offset_top = -19
		hb.offset_bottom = -2
		hb.add_theme_constant_override("separation", 2)
		ui.add_child(hb)
		bars.append(hb)
	_build_controls()


func _build_controls() -> void:
	# Basic: centre of mass, labels
	var b0: HBoxContainer = bars[BASIC]
	_btn("CoM", b0, func(on: bool): show_com = on; _apply_view(), true, true)
	_btn("Labels", b0, func(on: bool): labels[BASIC] = on; layer2d.queue_redraw(), true, labels[BASIC])
	# Exploded: spread slider, leader lines, labels
	var b1: HBoxContainer = bars[EXPLODED]
	var sl := Label.new()
	sl.text = "Spread"
	sl.add_theme_font_size_override("font_size", 8)
	b1.add_child(sl)
	var hs := HSlider.new()
	hs.min_value = 0.0
	hs.max_value = 1.0
	hs.step = 0.01
	hs.value = spread
	hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hs.custom_minimum_size = Vector2(40, 12)
	hs.focus_mode = Control.FOCUS_NONE
	hs.value_changed.connect(func(v: float): spread = v)
	b1.add_child(hs)
	_btn("Lines", b1, func(on: bool): show_lines = on; refresh(), true, true)
	_btn("Labels", b1, func(on: bool): labels[EXPLODED] = on; layer2d.queue_redraw(), true, labels[EXPLODED])
	# Onion: deck count, ghost, labels
	var b2: HBoxContainer = bars[ONION]
	decks_label = Label.new()
	decks_label.add_theme_font_size_override("font_size", 8)
	b2.add_child(decks_label)
	_btn("-", b2, func(): set_layers(layers - 1))
	_btn("+", b2, func(): set_layers(layers + 1))
	_btn("Ghost", b2, func(on: bool): ghost_above = on; _cut_dirty = true; refresh(), true, true)
	_btn("Labels", b2, func(on: bool): labels[ONION] = on; layer2d.queue_redraw(), true, labels[ONION])
	# Systems: links / power, labels
	var b3: HBoxContainer = bars[SYSTEMS]
	var grp := ButtonGroup.new()
	var bl := _btn("Links", b3, func(on: bool): if on: sys_mode = 0; refresh(), true, true)
	var bp := _btn("Power", b3, func(on: bool): if on: sys_mode = 1; refresh(), true, false)
	bl.button_group = grp
	bp.button_group = grp
	_btn("Labels", b3, func(on: bool): labels[SYSTEMS] = on; layer2d.queue_redraw(), true, labels[SYSTEMS])
	# top right: hull mode + expand
	var tr := VBoxContainer.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -62
	tr.offset_right = -3
	tr.offset_top = 3
	tr.add_theme_constant_override("separation", 2)
	ui.add_child(tr)
	btn_hull = _btn("Hull: Glass", tr, func(): hull_mode = (hull_mode + 1) % HULL_MODES.size(); _apply_view(); refresh())
	btn_expand = _btn("Expand", tr, func(): _toggle_expand())
	# onion deck selector (right edge, under the buttons)
	layer_box = VBoxContainer.new()
	layer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_box.anchor_left = 1.0
	layer_box.anchor_right = 1.0
	layer_box.anchor_top = 0.0
	layer_box.anchor_bottom = 1.0
	layer_box.offset_left = -30
	layer_box.offset_right = -3
	layer_box.offset_top = 40
	layer_box.offset_bottom = -26
	layer_box.add_theme_constant_override("separation", 2)
	layer_box.visible = false
	ui.add_child(layer_box)
	_btn("Up", layer_box, func(): set_layer(layer + 1))
	layer_slider = VSlider.new()
	layer_slider.min_value = 0
	layer_slider.max_value = layers
	layer_slider.step = 1
	layer_slider.value = layer
	layer_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer_slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layer_slider.custom_minimum_size = Vector2(14, 30)
	layer_slider.focus_mode = Control.FOCUS_NONE
	layer_slider.value_changed.connect(func(v: float): if int(v) != layer: set_layer(int(v)))
	layer_box.add_child(layer_slider)
	_btn("Dn", layer_box, func(): set_layer(layer - 1))
	layer_label = Label.new()
	layer_label.add_theme_font_size_override("font_size", 8)
	layer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer_box.add_child(layer_label)
	_apply_view()


func _toggle_expand() -> void:
	expanded = not expanded
	btn_expand.text = "Shrink" if expanded else "Expand"
	expand_requested.emit(expanded)


func _sync_layer_ui() -> void:
	if layer_slider != null:
		layer_slider.max_value = layers
		layer_slider.set_value_no_signal(layer)
	if layer_label != null:
		layer_label.text = "ALL" if layer >= layers else "D%d" % (layer + 1)
	if decks_label != null:
		decks_label.text = "Decks %d" % layers
