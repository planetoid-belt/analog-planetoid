@tool
class_name TerrainChunk
extends AnimatableBody3D
## Manages mesh rendering, collision baking, and localized sculpting for an individual terrain chunk.
##
## Each chunk holds a child [MeshInstance3D] and [CollisionShape3D]. It supports real-time
## spherical brush deformation and asynchronous physics collision baking via [WorkerThreadPool].

signal mesh_changed(chunk: TerrainChunk) ## Emitted whenever the chunk's mesh geometry is modified.

#region State & Components
const COLLISION_UPDATE_DELAY := 0.1

## Data container for triangle face buffers generated on worker threads.
class CollisionBakeResult:
	extends RefCounted
	var faces := PackedVector3Array()


## Controls whether physics collision is enabled for this chunk.
@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		if is_inside_tree():
			_queue_collision_update()

var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var _collision_generation := 0
var _collision_tasks: Dictionary = {}

var _arrays: Array = []                       # mesh arrays, reused on every rebuild
var _base_dirs := PackedVector3Array()        # direction of each vertex
var _base_lengths := PackedFloat32Array()     # original distance from center of each vertex
#endregion


#region Lifecycle & Events
## Initializes component references and queues initial collision generation.
func _ready() -> void:
	_ensure_components()
	_queue_collision_update()


## Polls pending background collision baking tasks and applies completed physics shapes.
func _process(_delta: float) -> void:
	for task_id in _collision_tasks.keys():
		if not WorkerThreadPool.is_task_completed(task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		var task: Dictionary = _collision_tasks[task_id]
		_collision_tasks.erase(task_id)
		var result: CollisionBakeResult = task["result"]
		if task["generation"] == _collision_generation:
			_apply_collision_faces(result.faces)
	set_process(not _collision_tasks.is_empty())


## Awaits any pending background collision tasks before leaving the tree.
func _exit_tree() -> void:
	_collision_generation += 1
	for task_id in _collision_tasks:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_collision_tasks.clear()


## Lazily creates MeshInstance3D and CollisionShape3D child nodes if missing.
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


## Sets the edited scene root as owner for the node in editor mode.
func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var scene_tree := get_tree()
	if scene_tree == null:
		return
	var edited_scene_root := scene_tree.edited_scene_root
	if edited_scene_root != null:
		node.owner = edited_scene_root
#endregion


#region Configuration & Queries
## Assigns a mesh and collision state to this chunk, queuing a collision rebuild.
func configure(mesh: ArrayMesh, enable_collision: bool = true) -> void:
	_ensure_components()
	collision_enabled = enable_collision
	mesh_instance.mesh = mesh
	_capture_base_shape(mesh)
	_queue_collision_update()

## Remembers the chunk's undeformed shape, so heights can be re-applied from scratch.
func _capture_base_shape(mesh: ArrayMesh) -> void:
	_arrays = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	_base_dirs.resize(verts.size())
	_base_lengths.resize(verts.size())
	for i in verts.size():
		_base_dirs[i] = verts[i].normalized()   # which way the vertex points from the center
		_base_lengths[i] = verts[i].length()    # how far from the center it originally was
		
## Finds the index of the closest vertex to a local position across all surfaces, or -1 if empty.
func get_nearest_vertex(local_position: Vector3) -> int:
	_ensure_components()
	var mesh := mesh_instance.mesh
	if mesh == null:
		return -1

	var target := mesh_instance.transform.affine_inverse() * local_position
	var nearest_index := -1
	var nearest_distance_squared := INF
	var global_vertex_index := 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var distance_squared := vertex.distance_squared_to(target)
			if distance_squared < nearest_distance_squared:
				nearest_distance_squared = distance_squared
				nearest_index = global_vertex_index
			global_vertex_index += 1
	return nearest_index
#endregion


#region Deformation
## Rebuilds the mesh from the base shape plus heights sampled from the heightmap.
func apply_heightmap(hm: Heightmap) -> void:
	if _base_dirs.is_empty():
		return # not configured yet

	var verts := PackedVector3Array()
	verts.resize(_base_dirs.size())
	for i in _base_dirs.size():
		verts[i] = _base_dirs[i] * (_base_lengths[i] + hm.sample(_base_dirs[i]))
	_arrays[Mesh.ARRAY_VERTEX] = verts

	# a new mesh each time
	var old_mesh := mesh_instance.mesh as ArrayMesh
	var new_mesh := ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	_copy_surface_properties(old_mesh, new_mesh, 0)
	mesh_instance.mesh = new_mesh

	_queue_collision_update()
	mesh_changed.emit(self)

## Radially deforms vertex positions within a spherical radius and queues a collision update.
## Returns true if any vertex was modified.
func brush_deform(local_position: Vector3, strength: float, radius: float) -> bool:
	if radius <= 0.0 or is_zero_approx(strength):
		return false
	_ensure_components()
	var source_mesh := mesh_instance.mesh as ArrayMesh
	if source_mesh == null:
		return false

	var target_pos := mesh_instance.to_local(to_global(local_position))
	var deformed_mesh := ArrayMesh.new()
	var did_deform := false

	for surface_index in range(source_mesh.get_surface_count()):
		var prim_type := source_mesh.surface_get_primitive_type(surface_index)
		var arrays := source_mesh.surface_get_arrays(surface_index)
		if prim_type != Mesh.PRIMITIVE_TRIANGLES:
			deformed_mesh.add_surface_from_arrays(prim_type, arrays)
			_copy_surface_properties(source_mesh, deformed_mesh, surface_index)
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var surface_deformed := false

		for i in range(vertices.size()):
			var v := vertices[i]
			var dist := v.distance_to(target_pos)
			if dist >= radius:
				continue
			var falloff := 1.0 - dist / radius
			var direction := v.normalized()
			if direction.is_zero_approx():
				continue
			var delta := direction * (strength * falloff * falloff)
			vertices[i] = v + delta
			if not normals.is_empty():
				normals[i] = (v + delta).normalized()
			surface_deformed = true
			did_deform = true

		if surface_deformed:
			arrays[Mesh.ARRAY_VERTEX] = vertices
			if not normals.is_empty():
				arrays[Mesh.ARRAY_NORMAL] = normals

			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			if not uvs.is_empty() and not normals.is_empty():
				var temp_mesh := ArrayMesh.new()
				temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var surface_tool := SurfaceTool.new()
				surface_tool.create_from(temp_mesh, 0)
				surface_tool.generate_tangents()
				var rebuilt := surface_tool.commit()
				if rebuilt and rebuilt.get_surface_count() > 0:
					arrays = rebuilt.surface_get_arrays(0)

		deformed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_copy_surface_properties(source_mesh, deformed_mesh, surface_index)

	if not did_deform or deformed_mesh.get_surface_count() == 0:
		return false

	mesh_instance.mesh = deformed_mesh
	_queue_collision_update()
	mesh_changed.emit(self)
	return true


## Copies surface name and material from a source mesh to a destination mesh surface.
func _copy_surface_properties(source_mesh: ArrayMesh, destination_mesh: ArrayMesh, source_surface: int) -> void:
	var destination_surface := destination_mesh.get_surface_count() - 1
	destination_mesh.surface_set_name(destination_surface, source_mesh.surface_get_name(source_surface))
	destination_mesh.surface_set_material(destination_surface, source_mesh.surface_get_material(source_surface))
#endregion


#region Collision Baking
## Forces an immediate synchronous collision shape rebuild.
func update_collision() -> void:
	_collision_generation += 1
	_rebuild_collision()


## Debounces collision shape baking using a scene tree timer.
func _queue_collision_update() -> void:
	_collision_generation += 1
	var generation := _collision_generation
	if not is_inside_tree():
		_rebuild_collision()
		return
	var timer := get_tree().create_timer(COLLISION_UPDATE_DELAY)
	timer.timeout.connect(_rebuild_collision_if_current.bind(generation), CONNECT_ONE_SHOT)


## Triggers a collision bake if the generation matches the latest request.
func _rebuild_collision_if_current(generation: int) -> void:
	if generation == _collision_generation:
		_start_collision_bake(generation)


## Synchronously extracts triangle faces and updates the collision shape.
func _rebuild_collision() -> void:
	if not collision_enabled or mesh_instance.mesh == null:
		collision_shape.shape = null
		return

	var surface_data := _get_collision_surface_data(mesh_instance.mesh)
	var faces := _extract_collision_faces(surface_data)
	_apply_collision_faces(faces)


## Dispatches an asynchronous collision face baking task to [WorkerThreadPool].
func _start_collision_bake(generation: int) -> void:
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


## Assigns triangle face coordinates to [member collision_shape] as a [ConcavePolygonShape3D].
func _apply_collision_faces(faces: PackedVector3Array) -> void:
	if faces.is_empty():
		collision_shape.shape = null
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision_shape.shape = shape


## Extracts vertex and index arrays from all triangle surfaces of a mesh.
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


## Worker thread task entry point that builds the flattened triangle list.
func _build_collision_faces(surface_data: Array[Dictionary], result: CollisionBakeResult) -> void:
	result.faces = _extract_collision_faces(surface_data)


## Unrolls indexed surfaces into a flat triangle list suitable for [ConcavePolygonShape3D].
func _extract_collision_faces(surface_data: Array[Dictionary]) -> PackedVector3Array:
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
	return faces
#endregion
