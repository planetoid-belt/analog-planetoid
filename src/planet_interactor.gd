extends Node3D

@export var ray: RayCast3D
@export var log_ray_hits_each_physics_tick: bool = false
@export var toggle_ray_periodically: bool = false
@export_range(0.1, 60.0, 0.1) var ray_toggle_interval_seconds: float = 1.0

var _last_collider_id := 0
var _last_shape_index := -2
var _last_face_index := -2
var _ray_toggle_elapsed := 0.0

func _ready() -> void:
	if ray == null:
		push_error("PlanetInteractor requires a RayCast3D assigned to ray.")

func _physics_process(delta: float) -> void:
	if ray == null:
		_last_collider_id = 0
		_last_shape_index = -2
		_last_face_index = -2
		return

	if toggle_ray_periodically:
		_ray_toggle_elapsed += delta
		var interval := maxf(ray_toggle_interval_seconds, 0.1)
		if _ray_toggle_elapsed >= interval:
			_ray_toggle_elapsed = fmod(_ray_toggle_elapsed, interval)
			toggle_ray()
	else:
		_ray_toggle_elapsed = 0.0

	if not ray.is_colliding():
		_last_collider_id = 0
		_last_shape_index = -2
		_last_face_index = -2
		return

	var collider := ray.get_collider() as CollisionObject3D
	var collider_id := collider.get_instance_id() if collider != null else 0
	var shape_index := ray.get_collider_shape()
	var face_index := ray.get_collision_face_index()
	if log_ray_hits_each_physics_tick:
		print_ray_hit_diagnostics(collider, shape_index, face_index)
	if collider_id != _last_collider_id \
			or shape_index != _last_shape_index \
			or face_index != _last_face_index:
		print_collision_face_index()
		_last_collider_id = collider_id
		_last_shape_index = shape_index
		_last_face_index = face_index

func toggle_ray() -> void:
	if ray == null:
		push_error("Cannot toggle RayCast3D: ray is not assigned.")
		return

	ray.enabled = not ray.enabled
	print("RayCast3D enabled: %s" % ray.enabled)

func print_ray_hit_diagnostics(collider: CollisionObject3D, shape_index: int, face_index: int) -> void:
	var hit_position := ray.get_collision_point()
	var collider_local_position := collider.to_local(hit_position) if collider != null else Vector3.ZERO
	var collider_name := str(collider.name) if collider != null else "<unknown>"
	print("Ray hit %s | shape %d | face %d | world %s | collider-local %s" % [
		collider_name,
		shape_index,
		face_index,
		hit_position,
		collider_local_position,
	])

func print_collision_face_index() -> void:
	if ray == null:
		push_error("Cannot print collision face index: ray is not assigned.")
		return
	if not ray.is_colliding():
		print("Ray is not colliding.")
		return

	var collider := ray.get_collider() as CollisionObject3D
	var collider_name := str(collider.name) if collider != null else "<unknown>"
	var shape_index := ray.get_collider_shape()
	var face_index := ray.get_collision_face_index()
	var hit_position := ray.get_collision_point()
	if face_index < 0:
		print("Ray hit %s, shape %d, face %d at %s (no valid face index)." % [
			collider_name,
			shape_index,
			face_index,
			hit_position,
		])
		return
	print("Ray hit %s, shape %d, face %d at %s." % [
		collider_name,
		shape_index,
		face_index,
		hit_position,
	])
