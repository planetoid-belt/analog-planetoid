@tool
class_name TerrainManager
extends Node3D
## Builds and manages editable terrain chunks for a [QuadSphere].
##
## The manager creates [TerrainChunk] nodes, configures their collision shapes, and
## forwards mesh-edit notifications. It can keep the source mesh whole or split it
## into face-aligned chunks.
##
## [b]Chunking:[/b][br]
## [code]chunking_factor = 0[/code] keeps the mesh as one chunk. Values above zero
## split each of the six faces into [code]4^(chunking_factor - 1)[/code] regions.
## The factor is limited by the source mesh's subdivision level.
##
## [b]Signals:[/b][br]
## [signal chunks_rebuilt] reports when a rebuild finishes and how many chunks were created.[br]
## [signal terrain_changed] reports mesh changes from a [TerrainChunk].

const MAX_CHUNKING_FACTOR := 6

#region Exports
## The quadsphere resource from which we build terrain. You can make direct edits
## to the quadsphere resource from here, or from the Planetoid node.
@export var quadsphere: QuadSphere:
	set(value):
		if quadsphere == value:
			return
		if quadsphere != null and quadsphere.changed.is_connected(_on_quadsphere_changed):
			quadsphere.changed.disconnect(_on_quadsphere_changed)
		quadsphere = value
		if quadsphere != null and not quadsphere.changed.is_connected(_on_quadsphere_changed):
			quadsphere.changed.connect(_on_quadsphere_changed)
		if is_inside_tree():
			rebuild_chunks()


## chunking factor decides how many times pieces Terrain Manager will split the quadsphere. [br]
	## [br]
	## 0 => 1 chunk (no chunking) [br]
	##
	## 1 => 6*4⁰ = 6 (each face of the cube is its own chunk) [br]
	##
	## 2 => 6*4¹ = 24 (each face of the cube is subdivided into 4 chunks) [br]
	##
	## 3 => 6*4² = 96 (etc...) [br]
	## [br]
	##
	## [b]NOTE: chunking factor cannot be greater than the quadsphere subdivision factor.
	## if you set it higher than the subdivision factor, it will quietly default to a safer value.
@export_range(0, MAX_CHUNKING_FACTOR, 1) var chunking_factor := 1:
	set(value):
		chunking_factor = clampi(value, 0, MAX_CHUNKING_FACTOR)
		if is_inside_tree() and not _rebuilding:
			rebuild_chunks()

## whether to enable collisions for each chunk. Keep this on during run-time, or if you are going to
## do any sort of raycasting or collisions debugging. disabling it will make raycasts ignore this planetoid's terrain.
@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		for child in get_children():
			if child is TerrainChunk:
				child.collision_enabled = value
#endregion


#region Signals & State
signal chunks_rebuilt(chunk_count: int) ## emitted whenever any chunk is rebuilt. Also emits number of chunks rebuilt.
signal terrain_changed(chunk: TerrainChunk) ## emitted when terrain of a chunk is rebuilt. will be emitted for each chunk.

var _rebuilding := false
#endregion


#region Lifecycle & Events
## Connects to [member quadsphere] signals and triggers initial chunk generation upon entering the tree.
func _ready() -> void:
	if quadsphere != null and not quadsphere.changed.is_connected(_on_quadsphere_changed):
		quadsphere.changed.connect(_on_quadsphere_changed)
	rebuild_chunks()

## Disconnects listeners from [member quadsphere] before leaving the scene tree.
func _exit_tree() -> void:
	if quadsphere != null and quadsphere.changed.is_connected(_on_quadsphere_changed):
		quadsphere.changed.disconnect(_on_quadsphere_changed)


## Sets the edited scene root as owner for the node in the editor.
func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var scene_tree := get_tree()
	if scene_tree == null:
		return
	var edited_scene_root := scene_tree.edited_scene_root
	if edited_scene_root != null:
		node.owner = edited_scene_root


## Rebuilds all chunks when the underlying QuadSphere resource changes.
func _on_quadsphere_changed() -> void:
	rebuild_chunks()


## Relays mesh alteration notifications from child chunks by emitting [signal terrain_changed].
func _on_chunk_mesh_changed(chunk: TerrainChunk) -> void:
	terrain_changed.emit(chunk)
#endregion


#region Chunk Generation
## Reconstructs all terrain chunks based on current chunking factor and QuadSphere geometry.
func rebuild_chunks() -> void:
	if _rebuilding:
		return
	_rebuilding = true
	_clear_generated_chunks()

	var chunk_count := 0 # we will emit this later
	if quadsphere != null and quadsphere.get_surface_count() > 0: #redundant 2nd statement?
		var maximum_factor := mini(MAX_CHUNKING_FACTOR, quadsphere.subdivisions)
		if chunking_factor > maximum_factor:
			push_warning(
				"TerrainManager chunking_factor %d exceeds QuadSphere subdivisions; using %d."
				% [chunking_factor, maximum_factor]
			)
			chunking_factor = maximum_factor

		if chunking_factor == 0:
			_create_chunk("Sphere", quadsphere)
			chunk_count = 1
		else:
			chunk_count = _create_face_chunks(chunking_factor)

	_rebuilding = false
	chunks_rebuilt.emit(chunk_count)


## Splits QuadSphere surfaces into face-aligned UV grid chunks and returns the total number created.
func _create_face_chunks(factor: int) -> int:
	var tiles_per_axis := 1 << (factor - 1)
	var chunks: Array[ChunkData] = []
	chunks.resize(6 * tiles_per_axis * tiles_per_axis)
	for face_index in range(6):
		for tile_y in range(tiles_per_axis):
			for tile_x in range(tiles_per_axis):
				var idx := face_index * tiles_per_axis * tiles_per_axis + tile_y * tiles_per_axis + tile_x
				chunks[idx] = ChunkData.new(face_index, tile_x, tile_y)

	for surface_index in range(quadsphere.get_surface_count()):
		if quadsphere.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := quadsphere.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.size() < 3:
			continue
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var has_indices := not indices.is_empty()
		var element_count := indices.size() if has_indices else vertices.size()
		var named_face := QuadSphere.CHUNK_NAMES.find(quadsphere.surface_get_name(surface_index))

		var offset := 0
		while offset < element_count - 2:
			var i0 := indices[offset] if has_indices else offset
			var i1 := indices[offset + 1] if has_indices else offset + 1
			var i2 := indices[offset + 2] if has_indices else offset + 2
			var v0 := vertices[i0]
			var v1 := vertices[i1]
			var v2 := vertices[i2]
			var face_a := named_face if named_face >= 0 else _get_face_index(v0, v1, v2)

			var is_quad := false
			var i3 := 0
			var i4 := 0
			var i5 := 0
			var v3 := Vector3.ZERO
			var v4 := Vector3.ZERO
			var v5 := Vector3.ZERO

			if offset + 5 < element_count:
				i3 = indices[offset + 3] if has_indices else offset + 3
				i4 = indices[offset + 4] if has_indices else offset + 4
				i5 = indices[offset + 5] if has_indices else offset + 5
				var shared := 0
				if i3 == i0 or i3 == i1 or i3 == i2: shared += 1
				if i4 == i0 or i4 == i1 or i4 == i2: shared += 1
				if i5 == i0 or i5 == i1 or i5 == i2: shared += 1
				if shared >= 2:
					v3 = vertices[i3]
					v4 = vertices[i4]
					v5 = vertices[i5]
					var face_b := named_face if named_face >= 0 else _get_face_index(v3, v4, v5)
					if face_a == face_b:
						is_quad = true

			var uv0 := _get_face_uv(v0, face_a)
			var uv1 := _get_face_uv(v1, face_a)
			var uv2 := _get_face_uv(v2, face_a)

			var center: Vector2
			if is_quad:
				var uv3 := _get_face_uv(v3, face_a)
				var uv4 := _get_face_uv(v4, face_a)
				var uv5 := _get_face_uv(v5, face_a)
				center = (uv0 + uv1 + uv2 + uv3 + uv4 + uv5) / 6.0
			else:
				center = (uv0 + uv1 + uv2) / 3.0

			var tile_x := clampi(int(floor(center.x * tiles_per_axis)), 0, tiles_per_axis - 1)
			var tile_y := clampi(int(floor(center.y * tiles_per_axis)), 0, tiles_per_axis - 1)
			var chunk_idx := face_a * tiles_per_axis * tiles_per_axis + tile_y * tiles_per_axis + tile_x
			var target_chunk: ChunkData = chunks[chunk_idx]

			target_chunk.add_triangle(surface_index, i0, i1, i2, vertices, normals, uvs, face_a, self)
			if is_quad:
				target_chunk.add_triangle(surface_index, i3, i4, i5, vertices, normals, uvs, face_a, self)
				offset += 6
			else:
				offset += 3

	var created_count := 0
	for chunk in chunks:
		if chunk.vertices.is_empty():
			continue
		var mesh := _create_chunk_mesh(chunk)
		if mesh == null:
			continue
		var surface_index := _get_source_surface_for_face(chunk.face)
		mesh.surface_set_material(0, quadsphere.surface_get_material(surface_index))
		_create_chunk("Face%d_%d_%d" % [chunk.face, chunk.x, chunk.y], mesh)
		created_count += 1

	var expected_count := 6 * tiles_per_axis * tiles_per_axis
	if created_count != expected_count:
		push_error(
			"TerrainManager generated %d chunks for factor %d; expected %d."
			% [created_count, factor, expected_count]
		)
	return created_count


## Constructs an indexed [ArrayMesh] with generated tangents from pre-indexed chunk buffers.
func _create_chunk_mesh(chunk: ChunkData) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = chunk.vertices
	arrays[Mesh.ARRAY_NORMAL] = chunk.normals
	arrays[Mesh.ARRAY_TEX_UV] = chunk.uvs
	arrays[Mesh.ARRAY_INDEX] = chunk.indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if not chunk.uvs.is_empty():
		var surface_tool := SurfaceTool.new()
		surface_tool.create_from(mesh, 0)
		surface_tool.generate_tangents()
		return surface_tool.commit()
	return mesh


## Instantiates, configures, and attaches a new [TerrainChunk] child node.
func _create_chunk(chunk_name: String, mesh: ArrayMesh) -> void:
	var chunk := TerrainChunk.new()
	chunk.name = chunk_name
	chunk.set_meta(&"generated_by_terrain_manager", true)
	add_child(chunk)
	_set_editor_owner(chunk)
	chunk.configure(mesh, collision_enabled)
	if not chunk.mesh_changed.is_connected(_on_chunk_mesh_changed):
		chunk.mesh_changed.connect(_on_chunk_mesh_changed)


## Destroys and removes all previously generated [TerrainChunk] child nodes.
func _clear_generated_chunks() -> void:
	for child in get_children():
		if child is TerrainChunk and child.has_meta(&"generated_by_terrain_manager"):
			remove_child(child)
			child.queue_free()


## Holds pre-indexed geometry buffers for a single generated chunk.
class ChunkData:
	extends RefCounted

	var face: int
	var x: int
	var y: int
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var vertex_map: Dictionary = {}

	## Initializes a new chunk buffer for a specific cube face and tile coordinate.
	func _init(p_face: int, p_x: int, p_y: int) -> void:
		face = p_face
		x = p_x
		y = p_y

	## Appends an indexed triangle to the chunk's geometry buffer, resolving deduplicated vertices.
	func add_triangle(
		surface_idx: int,
		i0: int, i1: int, i2: int,
		src_verts: PackedVector3Array,
		src_norms: PackedVector3Array,
		src_uvs: PackedVector2Array,
		face_idx: int,
		manager: TerrainManager
	) -> void:
		indices.append(_resolve_vertex(surface_idx, i0, src_verts, src_norms, src_uvs, face_idx, manager))
		indices.append(_resolve_vertex(surface_idx, i1, src_verts, src_norms, src_uvs, face_idx, manager))
		indices.append(_resolve_vertex(surface_idx, i2, src_verts, src_norms, src_uvs, face_idx, manager))

	## Resolves a source vertex to a deduplicated local chunk vertex index.
	func _resolve_vertex(
		surface_idx: int,
		idx: int,
		src_verts: PackedVector3Array,
		src_norms: PackedVector3Array,
		src_uvs: PackedVector2Array,
		face_idx: int,
		manager: TerrainManager
	) -> int:
		var key := (surface_idx << 32) | idx
		var local_idx: int = vertex_map.get(key, -1)
		if local_idx != -1:
			return local_idx
		local_idx = vertices.size()
		vertex_map[key] = local_idx
		var pos := src_verts[idx]
		var norm := src_norms[idx] if src_norms.size() == src_verts.size() else pos.normalized()
		var uv := src_uvs[idx] if src_uvs.size() == src_verts.size() else manager._get_face_uv(pos, face_idx)
		vertices.append(pos)
		normals.append(norm)
		uvs.append(uv)
		return local_idx


## Projects a 3D vertex onto the normalized [0, 1] UV plane of a given cube face.
func _get_face_uv(vertex: Vector3, face_index: int) -> Vector2:
	return Heightmap.dir_to_uv(vertex, face_index)

## Finds the matching source mesh surface index on [member quadsphere] for a given cube face.
func _get_source_surface_for_face(face_index: int) -> int:
	if quadsphere.get_surface_count() == 1:
		return 0
	var face_name: String = QuadSphere.CHUNK_NAMES[face_index]
	for surface_index in range(quadsphere.get_surface_count()):
		if quadsphere.surface_get_name(surface_index) == face_name:
			return surface_index
	return mini(face_index, quadsphere.get_surface_count() - 1)


## Determines which of the six cube faces (0-5) a triangle belongs to based on its center position.
func _get_face_index(v0: Vector3, v1: Vector3, v2: Vector3) -> int:
	var center := (v0 + v1 + v2) / 3.0
	var absolute_center := Vector3(absf(center.x), absf(center.y), absf(center.z))
	if absolute_center.x >= absolute_center.y and absolute_center.x >= absolute_center.z:
		return 0 if center.x >= 0.0 else 1
	if absolute_center.y >= absolute_center.z:
		return 2 if center.y >= 0.0 else 3
	return 4 if center.z >= 0.0 else 5
#endregion


#region Terrain Operations
## Retrieves all active [TerrainChunk] children generated by this manager.
func get_chunks() -> Array[TerrainChunk]:
	var chunks: Array[TerrainChunk] = []
	for child in get_children():
		if child is TerrainChunk and child.has_meta(&"generated_by_terrain_manager"):
			chunks.append(child)
	return chunks


## Applies a spherical sculpt brush to terrain chunks, returning the number of modified chunks.
func brush_deform(local_position: Vector3, strength: float, radius: float, affected_chunks: Array[TerrainChunk] = []) -> int:
	if radius <= 0.0:
		return 0

	var targets := affected_chunks if not affected_chunks.is_empty() else get_chunks()
	var changed_count := 0
	for chunk in targets:
		if is_instance_valid(chunk) and chunk.brush_deform(local_position, strength, radius):
			changed_count += 1
	return changed_count
#endregion
