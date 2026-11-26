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

#region exports
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


signal chunks_rebuilt(chunk_count: int) ## emitted whenever any chunk is rebuilt. Also emits number of chunks rebuilt.
signal terrain_changed(chunk: TerrainChunk) ## emitted when terrain of a chunk is rebuilt. will be emitted for each chunk.

var _rebuilding := false


#region Lifetime

# called when the entire class is fully loaded in.
func _ready() -> void:
	if quadsphere != null and not quadsphere.changed.is_connected(_on_quadsphere_changed):
		quadsphere.changed.connect(_on_quadsphere_changed)
	rebuild_chunks()

# destructor (sorta). We wanna disconnect any signals that we've established listeners for.
func _exit_tree() -> void:
	if quadsphere != null and quadsphere.changed.is_connected(_on_quadsphere_changed):
		quadsphere.changed.disconnect(_on_quadsphere_changed)

# helper function for creating interactable node hierarchies in the editor GUI.
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


#region Signal listeners
# This signal is emitted in quadsphere whenever it receives a change.
func _on_quadsphere_changed() -> void:
	rebuild_chunks()

# this listener routes signals from its child chunks to related places, such as terrain_gizmo.gd.
func _on_chunk_mesh_changed(chunk: TerrainChunk) -> void:
	terrain_changed.emit(chunk)


#endregion


#region Chunking
#region Rebuild flow
## Selects the full-mesh or subdivided-face rebuild path.
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


#endregion


#region Face subdivision
## Splits source faces into UV tiles and creates a mesh for each tile.
## this is the big bomba function. we can likely reduce it down by a bunch.
func _create_face_chunks(factor: int) -> int:
	var tiles_per_axis := 1 << (factor - 1)
	var groups: Array[Dictionary] = []
	var face_triangles: Array = []
	var face_uv_min: Array[Vector2] = []
	var face_uv_max: Array[Vector2] = []
	for face_index in range(6):
		face_triangles.append([])
		face_uv_min.append(Vector2(INF, INF))
		face_uv_max.append(Vector2(-INF, -INF))
		for tile_y in range(tiles_per_axis):
			for tile_x in range(tiles_per_axis):
				groups.append({
					"face": face_index,
					"x": tile_x,
					"y": tile_y,
					"vertices": PackedVector3Array(),
					"normals": PackedVector3Array(),
					"uvs": PackedVector2Array(),
				})

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
		var element_count := indices.size() if not indices.is_empty() else vertices.size()
		var named_face := QuadSphere.CHUNK_NAMES.find(quadsphere.surface_get_name(surface_index))

		for offset in range(0, element_count - 2, 3):
			var i0 := indices[offset] if not indices.is_empty() else offset
			var i1 := indices[offset + 1] if not indices.is_empty() else offset + 1
			var i2 := indices[offset + 2] if not indices.is_empty() else offset + 2
			var v0 := vertices[i0]
			var v1 := vertices[i1]
			var v2 := vertices[i2]
			var face_index := named_face if named_face >= 0 else _get_face_index(v0, v1, v2)
			var triangle: Array[Dictionary] = [
				_make_vertex_data(v0, normals, uvs, i0, vertices.size(), face_index),
				_make_vertex_data(v1, normals, uvs, i1, vertices.size(), face_index),
				_make_vertex_data(v2, normals, uvs, i2, vertices.size(), face_index),
			]
			for point in triangle:
				var uv: Vector2 = point["uv"]
				face_uv_min[face_index] = Vector2(
					minf(face_uv_min[face_index].x, uv.x),
					minf(face_uv_min[face_index].y, uv.y)
				)
				face_uv_max[face_index] = Vector2(
					maxf(face_uv_max[face_index].x, uv.x),
					maxf(face_uv_max[face_index].y, uv.y)
				)
			face_triangles[face_index].append(triangle)

	# Assign every source triangle to one tile by its UV-space center.
	var created_count := 0
	for face_index in range(6):
		if face_triangles[face_index].is_empty():
			continue
		var uv_min: Vector2 = face_uv_min[face_index]
		var uv_span: Vector2 = face_uv_max[face_index] - uv_min
		for triangle in face_triangles[face_index]:
			var triangle_center := Vector2.ZERO
			for point_index in range(triangle.size()):
				var point: Dictionary = triangle[point_index]
				var uv: Vector2 = point["uv"]
				var fallback_uv := _get_face_uv(point["vertex"], face_index)
				if not is_zero_approx(uv_span.x):
					fallback_uv.x = (uv.x - uv_min.x) / uv_span.x
				if not is_zero_approx(uv_span.y):
					fallback_uv.y = (uv.y - uv_min.y) / uv_span.y
				point["uv"] = fallback_uv.clamp(Vector2.ZERO, Vector2.ONE)
				triangle[point_index] = point
				triangle_center += fallback_uv

			triangle_center /= float(triangle.size())
			var tile_x := clampi(int(floor(triangle_center.x * tiles_per_axis)), 0, tiles_per_axis - 1)
			var tile_y := clampi(int(floor(triangle_center.y * tiles_per_axis)), 0, tiles_per_axis - 1)
			var group_index := face_index * tiles_per_axis * tiles_per_axis + tile_y * tiles_per_axis + tile_x
			var group: Dictionary = groups[group_index]
			var group_vertices: PackedVector3Array = group["vertices"]
			var group_normals: PackedVector3Array = group["normals"]
			var group_uvs: PackedVector2Array = group["uvs"]
			for point in triangle:
				group_vertices.append(point["vertex"])
				group_normals.append(point["normal"])
				group_uvs.append(point["uv"])
			group["vertices"] = group_vertices
			group["normals"] = group_normals
			group["uvs"] = group_uvs
			groups[group_index] = group

	for group in groups:
		var vertices: PackedVector3Array = group["vertices"]
		if vertices.is_empty():
			continue
		var mesh := _create_chunk_mesh(vertices, group["normals"], group["uvs"])
		if mesh == null:
			continue
		var face_index: int = group["face"]
		var tile_x: int = group["x"]
		var tile_y: int = group["y"]
		var surface_index := _get_source_surface_for_face(face_index)
		mesh.surface_set_material(0, quadsphere.surface_get_material(surface_index))
		_create_chunk("Face%d_%d_%d" % [face_index, tile_x, tile_y], mesh)
		created_count += 1

	var expected_count := 6 * tiles_per_axis * tiles_per_axis
	if created_count != expected_count:
		push_error(
			"TerrainManager generated %d chunks for factor %d; expected %d."
			% [created_count, factor, expected_count]
		)
	return created_count


#endregion


#region Face and UV mapping
func _make_vertex_data(
	vertex: Vector3,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	vertex_index: int,
	vertex_count: int,
	face_index: int
) -> Dictionary:
	var normal := normals[vertex_index] if normals.size() == vertex_count else vertex.normalized()
	var uv := uvs[vertex_index] if uvs.size() == vertex_count else _get_face_uv(vertex, face_index)
	return {"vertex": vertex, "normal": normal, "uv": uv}


func _get_face_uv(vertex: Vector3, face_index: int) -> Vector2:
	if is_zero_approx(quadsphere.uniform_size):
		return Vector2(0.5, 0.5)
	var point := vertex / quadsphere.uniform_size + Vector3.ONE * 0.5
	match face_index:
		0, 1:
			return Vector2(point.z, point.y)
		2, 3:
			return Vector2(point.x, point.z)
		_:
			return Vector2(point.x, point.y)


func _get_source_surface_for_face(face_index: int) -> int:
	if quadsphere.get_surface_count() == 1:
		return 0
	var face_name: String = QuadSphere.CHUNK_NAMES[face_index]
	for surface_index in range(quadsphere.get_surface_count()):
		if quadsphere.surface_get_name(surface_index) == face_name:
			return surface_index
	return mini(face_index, quadsphere.get_surface_count() - 1)


func _get_face_index(v0: Vector3, v1: Vector3, v2: Vector3) -> int:
	var center := (v0 + v1 + v2) / 3.0
	var absolute_center := Vector3(absf(center.x), absf(center.y), absf(center.z))
	if absolute_center.x >= absolute_center.y and absolute_center.x >= absolute_center.z:
		return 0 if center.x >= 0.0 else 1
	if absolute_center.y >= absolute_center.z:
		return 2 if center.y >= 0.0 else 3
	return 4 if center.z >= 0.0 else 5


#endregion


#region Mesh assembly
## Builds the ArrayMesh surface from the clipped triangle vertices.
func _create_chunk_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array) -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex_index in range(vertices.size()):
		surface_tool.set_normal(normals[vertex_index])
		surface_tool.set_uv(uvs[vertex_index])
		surface_tool.add_vertex(vertices[vertex_index])
	surface_tool.index()
	surface_tool.generate_tangents()
	return surface_tool.commit()


#endregion


#region Chunk lifecycle
## Instantiates and removes generated TerrainChunk nodes.
func _create_chunk(chunk_name: String, mesh: ArrayMesh) -> void:
	var chunk := TerrainChunk.new()
	chunk.name = chunk_name
	chunk.set_meta(&"generated_by_terrain_manager", true)
	add_child(chunk)
	_set_editor_owner(chunk)
	chunk.configure(mesh, collision_enabled)
	if not chunk.mesh_changed.is_connected(_on_chunk_mesh_changed):
		chunk.mesh_changed.connect(_on_chunk_mesh_changed)


func _clear_generated_chunks() -> void:
	for child in get_children():
		if child is TerrainChunk and child.has_meta(&"generated_by_terrain_manager"):
			remove_child(child)
			child.queue_free()


#endregion


#endregion


#region Misc/utility
func get_chunks() -> Array[TerrainChunk]:
	var chunks: Array[TerrainChunk] = []
	for child in get_children():
		if child is TerrainChunk and child.has_meta(&"generated_by_terrain_manager"):
			chunks.append(child)
	return chunks


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
