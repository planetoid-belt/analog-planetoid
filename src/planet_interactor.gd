extends Node3D

@export var ray: RayCast3D

var _last_collider_id := 0
var _last_face_index := -2

func _ready() -> void:
	if ray == null:
		push_error("PlanetInteractor requires a RayCast3D assigned to ray.")

func _physics_process(_delta: float) -> void:
	if ray == null or not ray.is_colliding():
		_last_collider_id = 0
		_last_face_index = -2
		return

	var collider := ray.get_collider() as CollisionObject3D
	var collider_id := collider.get_instance_id() if collider != null else 0
	var face_index := ray.get_collision_face_index()
	if collider_id != _last_collider_id or face_index != _last_face_index:
		print_collision_face_index()
		_last_collider_id = collider_id
		_last_face_index = face_index

func print_collision_face_index() -> void:
	if ray == null:
		push_error("Cannot print collision face index: ray is not assigned.")
		return
	if not ray.is_colliding():
		print("Ray is not colliding.")
		return

	var face_index := ray.get_collision_face_index()
	if face_index < 0:
		print("Ray hit a shape without a valid face index.")
		return
	print("Ray hit face index: %d" % face_index)
