@tool
class_name TerrainChunk
extends AnimatableBody3D

signal mesh_changed(chunk: TerrainChunk)

const COLLISION_UPDATE_DELAY := 0.1

class CollisionBakeResult:
	extends RefCounted

	var mutex := Mutex.new()
	var faces := PackedVector3Array()

@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		if is_inside_tree():
			_queue_collision_update()

var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var _collision_generation := 0
var _collision_tasks: Dictionary = {}


func _ready() -> void:
	_ensure_components()
	_queue_collision_update()


func _process(_delta: float) -> void:
	for task_id in _collision_tasks.keys():
		if not WorkerThreadPool.is_task_completed(task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		var task: Dictionary = _collision_tasks[task_id]
		_collision_tasks.erase(task_id)
		var result: CollisionBakeResult = task["result"]
		result.mutex.lock()
		var faces := result.faces
		result.mutex.unlock()
		if task["generation"] == _collision_generation:
			_apply_collision_faces(faces)
	set_process(not _collision_tasks.is_empty())


func _exit_tree() -> void:
	_collision_generation += 1
	for task_id in _collision_tasks:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_collision_tasks.clear()


func configure(mesh: ArrayMesh, enable_collision: bool = true) -> void:
	_ensure_components()
	collision_enabled = enable_collision
	mesh_instance.mesh = mesh
	_queue_collision_update()


func update_collision() -> void:
	_collision_generation += 1
	_rebuild_collision()


func brush_deform(local_position: Vector3, strength: float, radius: float) -> bool:
	if radius <= 0.0 or is_zero_approx(strength):
		return false
	_ensure_components()
	var source_mesh := mesh_instance.mesh as ArrayMesh
	if source_mesh == null:
		return false

	var mesh_local_position := mesh_instance.to_local(to_global(local_position))
	var deformed_mesh := ArrayMesh.new()
	var did_deform := false
	for surface_index in range(source_mesh.get_surface_count()):
		if source_mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			deformed_mesh.add_surface_from_arrays(
				source_mesh.surface_get_primitive_type(surface_index),
				source_mesh.surface_get_arrays(surface_index)
			)
			_copy_surface_properties(source_mesh, deformed_mesh, surface_index)
			continue

		var mesh_data_tool := MeshDataTool.new()
		var error := mesh_data_tool.create_from_surface(source_mesh, surface_index)
		if error != OK:
			push_error("Failed to load terrain surface %d into MeshDataTool: %s" % [surface_index, error_string(error)])
			return false

		var surface_deformed := false
		for vertex_index in range(mesh_data_tool.get_vertex_count()):
			var vertex := mesh_data_tool.get_vertex(vertex_index)
			var distance := vertex.distance_to(mesh_local_position)
			if distance >= radius:
				continue
			var falloff := 1.0 - distance / radius
			var direction := vertex.normalized()
			if direction.is_zero_approx():
				continue
			mesh_data_tool.set_vertex(
				vertex_index,
				vertex + direction * strength * falloff * falloff
			)
			did_deform = true
			surface_deformed = true

		if surface_deformed:
			var edited_surface := ArrayMesh.new()
			mesh_data_tool.set_material(source_mesh.surface_get_material(surface_index))
			error = mesh_data_tool.commit_to_surface(edited_surface)
			if error != OK:
				push_error("Failed to commit deformed terrain surface %d: %s" % [surface_index, error_string(error)])
				return false

			var surface_tool := SurfaceTool.new()
			surface_tool.create_from(edited_surface, 0)
			surface_tool.generate_normals()
			var surface_arrays := source_mesh.surface_get_arrays(surface_index)
			var surface_uvs: PackedVector2Array = surface_arrays[Mesh.ARRAY_TEX_UV]
			if not surface_uvs.is_empty():
				surface_tool.generate_tangents()
			var rebuilt_surface := surface_tool.commit()
			if rebuilt_surface == null or rebuilt_surface.get_surface_count() == 0:
				push_error("Failed to rebuild terrain surface %d." % surface_index)
				return false
			deformed_mesh.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES,
				rebuilt_surface.surface_get_arrays(0)
			)
		else:
			deformed_mesh.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES,
				source_mesh.surface_get_arrays(surface_index)
			)
		_copy_surface_properties(source_mesh, deformed_mesh, surface_index)

	if not did_deform or deformed_mesh.get_surface_count() == 0:
		return false

	mesh_instance.mesh = deformed_mesh
	_queue_collision_update()
	mesh_changed.emit(self)
	return true


func _copy_surface_properties(source_mesh: ArrayMesh, destination_mesh: ArrayMesh, source_surface: int) -> void:
	var destination_surface := destination_mesh.get_surface_count() - 1
	destination_mesh.surface_set_name(destination_surface, source_mesh.surface_get_name(source_surface))
	destination_mesh.surface_set_material(destination_surface, source_mesh.surface_get_material(source_surface))


func get_nearest_vertex(local_position: Vector3) -> int:
	_ensure_components()
	var mesh := mesh_instance.mesh
	if mesh == null:
		return -1

	var nearest_index := -1
	var nearest_distance_squared := INF
	var global_vertex_index := 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var chunk_local_vertex := mesh_instance.transform * vertex
			var distance_squared := chunk_local_vertex.distance_squared_to(local_position)
			if distance_squared < nearest_distance_squared:
				nearest_distance_squared = distance_squared
				nearest_index = global_vertex_index
			global_vertex_index += 1
	return nearest_index


func _ensure_components() -> void:
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh_instance == null:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "MeshInstance3D"
			add_child(mesh_instance)
			_set_editor_owner(mesh_instance)

	if collision_shape == null or not is_instance_valid(collision_shape):
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision_shape == null:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			add_child(collision_shape)
			_set_editor_owner(collision_shape)


func _queue_collision_update() -> void:
	_collision_generation += 1
	var generation := _collision_generation
	if not is_inside_tree():
		_rebuild_collision()
		return
	var timer := get_tree().create_timer(COLLISION_UPDATE_DELAY)
	timer.timeout.connect(_rebuild_collision_if_current.bind(generation), CONNECT_ONE_SHOT)


func _rebuild_collision_if_current(generation: int) -> void:
	if generation == _collision_generation:
		_start_collision_bake(generation)


func _rebuild_collision() -> void:
	_ensure_components()
	if not collision_enabled or mesh_instance.mesh == null:
		collision_shape.shape = null
		return

	var faces := _get_collision_faces(mesh_instance.mesh)
	_apply_collision_faces(faces)


func _start_collision_bake(generation: int) -> void:
	_ensure_components()
	if not collision_enabled or mesh_instance.mesh == null:
		collision_shape.shape = null
		return

	var surface_data := _get_collision_surface_data(mesh_instance.mesh)
	var result := CollisionBakeResult.new()
	var task_id := WorkerThreadPool.add_task(
		_build_collision_faces.bind(surface_data, result),
		false,
		"Build terrain collision"
	)
	_collision_tasks[task_id] = {
		"generation": generation,
		"result": result,
	}
	set_process(true)


func _apply_collision_faces(faces: PackedVector3Array) -> void:
	if faces.is_empty():
		collision_shape.shape = null
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision_shape.shape = shape


func _get_collision_surface_data(mesh: Mesh) -> Array[Dictionary]:
	var surface_data: Array[Dictionary] = []
	for surface_index in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface_index)
		surface_data.append({
			"vertices": arrays[Mesh.ARRAY_VERTEX],
			"indices": arrays[Mesh.ARRAY_INDEX],
		})
	return surface_data


func _build_collision_faces(surface_data: Array[Dictionary], result: CollisionBakeResult) -> void:
	var faces := PackedVector3Array()
	for surface in surface_data:
		var vertices: PackedVector3Array = surface["vertices"]
		var indices: PackedInt32Array = surface["indices"]
		var element_count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, element_count - 2, 3):
			var i0 := indices[offset] if not indices.is_empty() else offset
			var i1 := indices[offset + 1] if not indices.is_empty() else offset + 1
			var i2 := indices[offset + 2] if not indices.is_empty() else offset + 2
			faces.append(vertices[i0])
			faces.append(vertices[i1])
			faces.append(vertices[i2])
	result.mutex.lock()
	result.faces = faces
	result.mutex.unlock()


func _get_collision_faces(mesh: Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for surface_index in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var element_count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, element_count - 2, 3):
			var i0 := indices[offset] if not indices.is_empty() else offset
			var i1 := indices[offset + 1] if not indices.is_empty() else offset + 1
			var i2 := indices[offset + 2] if not indices.is_empty() else offset + 2
			faces.append(vertices[i0])
			faces.append(vertices[i1])
			faces.append(vertices[i2])
	return faces

# I am sorry but why the FUCK are you calculating normals? we DONT need to do this.
# We can use surfacetool or datameshtool to do it for us.
func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var scene_tree := get_tree()
	if scene_tree == null:
		return
	var edited_scene_root := scene_tree.edited_scene_root
	if edited_scene_root != null:
		node.owner = edited_scene_root
