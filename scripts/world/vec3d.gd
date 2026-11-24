class_name Vec3D
extends RefCounted
## A position in 64-bit floats. Godot's Vector3 is 32-bit: at 100 km from the origin it is good to about 1 cm,
## at 1,000,000 km (the biggest map of the design doc) to about 100 m. Absolute positions live here; the scene
## only ever holds small coordinates relative to a floating origin (see WorldSpace).

var x := 0.0
var y := 0.0
var z := 0.0


static func make(px: float, py: float, pz: float) -> Vec3D:
	var v := Vec3D.new()
	v.x = px
	v.y = py
	v.z = pz
	return v


static func from_v3(v: Vector3) -> Vec3D:
	return make(v.x, v.y, v.z)


func copy() -> Vec3D:
	return make(x, y, z)


## This position moved by a (small) vector, as a new Vec3D.
func plus(v: Vector3) -> Vec3D:
	return make(x + v.x, y + v.y, z + v.z)


func add_in_place(v: Vector3) -> void:
	x += v.x
	y += v.y
	z += v.z


## Vector from `o` to this position. The subtraction is done in 64 bits, so the result is accurate when the two are close.
func minus(o: Vec3D) -> Vector3:
	return Vector3(x - o.x, y - o.y, z - o.z)


func dist(o: Vec3D) -> float:
	var dx := x - o.x
	var dy := y - o.y
	var dz := z - o.z
	return sqrt(dx * dx + dy * dy + dz * dz)


func length() -> float:
	return sqrt(x * x + y * y + z * z)


func equals(o: Vec3D, eps := 1e-6) -> bool:
	return absf(x - o.x) <= eps and absf(y - o.y) <= eps and absf(z - o.z) <= eps


func _to_string() -> String:
	return "(%.3f, %.3f, %.3f)" % [x, y, z]
