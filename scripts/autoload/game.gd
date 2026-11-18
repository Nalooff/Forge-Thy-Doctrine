extends Node
## Global state: scene switching, input map, ship library (premade + user files).

const USER_SHIPS := "user://ships"
const DRAFTS := "user://drafts"

var editing_bp: Dictionary = {}   # blueprint being edited (survives the trip to the test range)
var session: Dictionary = {}      # data handed to the arena scene
var settings := {"assist": true, "shake": true, "mouse_sens": 0.0022}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USER_SHIPS)
	DirAccess.make_dir_recursive_absolute(DRAFTS)
	_setup_input()


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_key("thrust_fwd", [KEY_W])
	_key("thrust_back", [KEY_S])
	_key("strafe_left", [KEY_A])
	_key("strafe_right", [KEY_D])
	_key("thrust_up", [KEY_SPACE])
	_key("thrust_down", [KEY_C, KEY_CTRL])
	_key("roll_left", [KEY_Q])
	_key("roll_right", [KEY_E])
	_key("pitch_up", [KEY_UP])
	_key("pitch_down", [KEY_DOWN])
	_key("yaw_left", [KEY_LEFT])
	_key("yaw_right", [KEY_RIGHT])
	_key("toggle_assist", [KEY_X])
	_key("brake", [KEY_Z])
	_key("toggle_view", [KEY_V])
	_key("free_cursor", [KEY_TAB])
	_key("lock_target", [KEY_T])
	_key("pause", [KEY_ESCAPE])


func goto_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)


# ---------------------------------------------------------------- ship library
func all_ships() -> Array:
	var out: Array = []
	for bp in Premades.all():
		out.append({"name": bp["name"], "source": "premade", "path": "", "bp": bp})
	var d := DirAccess.open(USER_SHIPS)
	if d:
		for f in d.get_files():
			if f.ends_with(".json"):
				var bp := load_ship_file(USER_SHIPS + "/" + f)
				if not bp.is_empty():
					out.append({"name": bp["name"], "source": "user", "path": USER_SHIPS + "/" + f, "bp": bp})
	return out


func load_ship_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return ShipData.normalize(data)


func save_ship(bp: Dictionary, dir := USER_SHIPS) -> String:
	var fname: String = String(bp.get("name", "ship")).to_lower().strip_edges()
	var clean := ""
	for c in fname:
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	if clean == "":
		clean = "ship"
	var path := "%s/%s.json" % [dir, clean]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(bp, "\t"))
	return path
