## FaceVertexDebugger draws debug meshes at the vertices that form a face. 
## The face is retrieved using a RayCast3D. 
extends Node3D

@export var ray: RayCast3D
@export_range(0.001, 0.1, 0.001) var marker_radius: float = 0.015
@export var marker_color: Color = Color.YELLOW

var _markers: MultiMeshInstance3D
var _collision_marker: MeshInstance3D
var _collision_marker_material: StandardMaterial3D
var _last_chunk_id := 0
var _last_face_index := -1

func _ready() -> void:
	if ray == null:
		push_error("FaceVertexDebugger requires a RayCast3D assigned to ray.")

func _physics_process(_delta: float) -> void:
	if ray == null or not ray.is_colliding():
		_clear_markers()
		_last_chunk_id = 0
		_last_face_index = -1
		return

	var chunk := ray.get_collider() as Chunk
	if chunk == null:
		_clear_markers()
		_last_chunk_id = 0
		_last_face_index = -1
		return

	var face_index := ray.get_collision_face_index()
	var chunk_id := chunk.get_instance_id()
	if chunk_id == _last_chunk_id and face_index == _last_face_index:
		_update_collision_point(chunk)
		return

	_clear_markers()
	_last_chunk_id = chunk_id
	_last_face_index = face_index
	_show_face_vertices(chunk, face_index)
	_update_collision_point(chunk)

func _show_face_vertices(chunk: Chunk, face_index: int) -> void:
	if chunk.mesh_instance == null or chunk.mesh_instance.mesh == null:
		push_error("Cannot show face vertices: hit chunk has no mesh.")
		return
	if chunk.mesh_instance.mesh.get_surface_count() != 1:
		push_error("Cannot show face vertices: hit chunk must have exactly one mesh surface.")
		return
	if chunk.mesh_instance.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		push_error("Cannot show face vertices: hit chunk surface is not triangle-based.")
		return

	var arrays := chunk.mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices = PackedInt32Array(range(vertices.size()))

	var first_index := face_index * 3
	if face_index < 0 or first_index + 2 >= indices.size():
		push_error("Cannot show face vertices: face index %d is outside the chunk mesh." % face_index)
		return

	var face_vertex_indices := PackedInt32Array([
		indices[first_index],
		indices[first_index + 1],
		indices[first_index + 2],
	])
	var local_positions := PackedVector3Array()
	for vertex_index in face_vertex_indices:
		if vertex_index < 0 or vertex_index >= vertices.size():
			push_error("Cannot show face vertices: mesh contains invalid vertex index %d." % vertex_index)
			return
		local_positions.append(
			chunk.to_local(chunk.mesh_instance.to_global(vertices[vertex_index]))
		)

	_mark_face_vertices(chunk, local_positions)

func _mark_face_vertices(chunk: Chunk, local_positions: PackedVector3Array) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = marker_radius
	sphere.height = marker_radius * 2.0

	var material := StandardMaterial3D.new()
	material.albedo_color = marker_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sphere
	multimesh.instance_count = local_positions.size()

	_markers = MultiMeshInstance3D.new()
	_markers.name = "FaceVertexMarkers"
	_markers.multimesh = multimesh
	chunk.add_child(_markers)
	for marker_index in range(local_positions.size()):
		multimesh.set_instance_transform(
			marker_index,
			Transform3D(Basis.IDENTITY, local_positions[marker_index])
		)

func _update_collision_point(chunk: Chunk) -> void:
	if not is_instance_valid(_collision_marker):
		var sphere := SphereMesh.new()
		sphere.radius = marker_radius
		sphere.height = marker_radius * 2.0

		_collision_marker_material = StandardMaterial3D.new()
		_collision_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = _collision_marker_material

		_collision_marker = MeshInstance3D.new()
		_collision_marker.name = "RayCollisionPoint"
		_collision_marker.mesh = sphere
		chunk.add_child(_collision_marker)

	_collision_marker_material.albedo_color = _get_raycast_debug_color()
	_collision_marker.position = chunk.to_local(ray.get_collision_point())

func _get_raycast_debug_color() -> Color:
	var color := ray.debug_shape_custom_color
	if color.is_equal_approx(Color.BLACK):
		color = ProjectSettings.get_setting(
			"debug/shapes/collision/shape_color",
			Color(0.0, 0.6, 0.7, 0.42)
		)
	return color

func _clear_markers() -> void:
	if is_instance_valid(_markers):
		_markers.queue_free()
		_markers = null
	if is_instance_valid(_collision_marker):
		_collision_marker.queue_free()
		_collision_marker = null
		_collision_marker_material = null
