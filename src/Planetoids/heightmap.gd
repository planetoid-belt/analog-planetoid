@tool
class_name Heightmap
extends Resource

var resolution: int
var faces: Array[Image] = []

func _init(res: int = 64) -> void:
	resolution = res
	for f in 6:
		faces.append(Image.create_empty(resolution, resolution, false, Image.FORMAT_RF))

## Get the face number from direction
static func dir_to_face(dir: Vector3) -> int:
	var axis := dir.abs().max_axis_index()
	return axis * 2 + (0 if dir[axis] > 0.0 else 1)

## Projects a 3D dir onto the normalized [0, 1] UV plane of a given cube face.
static func dir_to_uv(dir: Vector3, face: int) -> Vector2:
	var u := 0.5
	var v := 0.5
	match face:
		0: # Right (+X)
			if not is_zero_approx(dir.x):
				u = 0.5 - 0.5 * (dir.z / absf(dir.x))
				v = 0.5 + 0.5 * (dir.y / absf(dir.x))
		1: # Left (-X)
			if not is_zero_approx(dir.x):
				u = 0.5 + 0.5 * (dir.z / absf(dir.x))
				v = 0.5 + 0.5 * (dir.y / absf(dir.x))
		2: # Top (+Y)
			if not is_zero_approx(dir.y):
				u = 0.5 + 0.5 * (dir.x / absf(dir.y))
				v = 0.5 - 0.5 * (dir.z / absf(dir.y))
		3: # Bottom (-Y)
			if not is_zero_approx(dir.y):
				u = 0.5 + 0.5 * (dir.x / absf(dir.y))
				v = 0.5 + 0.5 * (dir.z / absf(dir.y))
		4: # Back (+Z)
			if not is_zero_approx(dir.z):
				u = 0.5 + 0.5 * (dir.x / absf(dir.z))
				v = 0.5 + 0.5 * (dir.y / absf(dir.z))
		5: # Front (-Z)
			if not is_zero_approx(dir.z):
				u = 0.5 - 0.5 * (dir.x / absf(dir.z))
				v = 0.5 + 0.5 * (dir.y / absf(dir.z))
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))
	
## Converts a 0–1 face coordinate to a pixel coordinate.
func _uv_to_pixel(uv: Vector2) -> Vector2i:
	var max_index := resolution - 1
	return Vector2i(roundi(uv.x * max_index), roundi(uv.y * max_index))
	
func get_height(dir: Vector3) -> float:
	var face := dir_to_face(dir)
	var uv := dir_to_uv(dir, face)
	var p := _uv_to_pixel(uv)
	return faces[face].get_pixel(p.x, p.y).r
	
func set_height(dir: Vector3, h: float) -> void:
	var face := dir_to_face(dir)
	var uv := dir_to_uv(dir, face)
	var p := _uv_to_pixel(uv)
	faces[face].set_pixel(p.x, p.y, Color(h, 0, 0))
