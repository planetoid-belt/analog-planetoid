@tool
## AI-generated dev tool for visually debugging terrain manager.
class_name TerrainGizmo
extends Node3D

const LABEL_META := &"terrain_gizmo_vertex_label"
const AXIS_COLORS := [
	Color(1.0, 0.28, 0.28),
	Color(0.35, 1.0, 0.45),
	Color(0.35, 0.65, 1.0),
]
const INDEX_COLOR := Color(1.0, 1.0, 1.0)
const OUTLINE_COLOR := Color(0.015, 0.02, 0.035, 1.0)

@export var terrain_manager: TerrainManager:
	set(value):
		if terrain_manager == value:
			return
		_unbind_manager()
		terrain_manager = value
		if is_inside_tree() and not _resolving_manager:
			_bind_manager()
			_refresh_labels()

@export var show_vertex_indices := true:
	set(value):
		if show_vertex_indices == value:
			return
		show_vertex_indices = value
		if is_inside_tree():
			_update_entry_visibility()

@export var show_vertex_positions := true:
	set(value):
		if show_vertex_positions == value:
			return
		show_vertex_positions = value
		if is_inside_tree():
			_update_entry_visibility()

@export var cull_far_hemisphere := true:
	set(value):
		if cull_far_hemisphere == value:
			return
		cull_far_hemisphere = value
		if is_inside_tree():
			set_process(show_vertex_indices or show_vertex_positions)

@export_range(8, 48, 1) var font_size := 16:
	set(value):
		font_size = value
		if is_inside_tree():
			_refresh_labels()

@export_range(0.001, 0.01, 0.0005) var pixel_size := 0.003:
	set(value):
		pixel_size = value
		if is_inside_tree():
			_refresh_labels()

@export_range(0.01, 0.15, 0.005) var row_spacing := 0.045:
	set(value):
		row_spacing = value
		if is_inside_tree():
			_refresh_labels()

@export_range(0.0, 0.5, 0.005) var vertex_label_offset := 0.01:
	set(value):
		vertex_label_offset = value
		if is_inside_tree():
			_layout_duplicate_labels()

@export_range(0.0, 0.2, 0.005) var duplicate_label_spread := 0.05:
	set(value):
		duplicate_label_spread = value
		if is_inside_tree():
			_layout_duplicate_labels()

var _entries: Array[Dictionary] = []
var _resolving_manager := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_resolve_terrain_manager()
	_bind_manager()
	set_process(show_vertex_indices or show_vertex_positions)
	call_deferred("_refresh_labels")


func _exit_tree() -> void:
	_unbind_manager()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or (not show_vertex_indices and not show_vertex_positions):
		return

	var camera := get_viewport().get_camera_3d()
	var center_position := terrain_manager.global_position if is_instance_valid(terrain_manager) else global_position
	var camera_offset := camera.global_position - center_position if camera != null else Vector3.ZERO
	var can_cull_far_side := cull_far_hemisphere \
			and camera != null \
			and not camera_offset.is_zero_approx()

	for entry in _entries:
		var chunk: TerrainChunk = entry["chunk"]
		var mesh_instance: MeshInstance3D = entry["mesh_instance"]
		var anchor: Node3D = entry["anchor"]
		if not is_instance_valid(chunk) \
				or not is_instance_valid(mesh_instance) \
				or not is_instance_valid(anchor):
			continue

		var vertex_position: Vector3 = entry["vertex_position"]
		var world_position := mesh_instance.to_global(vertex_position)
		anchor.position = vertex_position + entry["anchor_offset"]
		if can_cull_far_side:
			anchor.visible = (world_position - center_position).dot(camera_offset) >= 0.0
		else:
			anchor.visible = true
		if show_vertex_positions \
				and world_position.distance_squared_to(entry["last_world_position"]) > 0.00000001:
			_update_position_text(entry, world_position)


func _resolve_terrain_manager() -> void:
	if terrain_manager != null or get_parent() == null:
		return
	_resolving_manager = true
	terrain_manager = get_parent().get_node_or_null("TerrainManager") as TerrainManager
	_resolving_manager = false


func _bind_manager() -> void:
	if terrain_manager == null:
		_resolve_terrain_manager()
	if terrain_manager == null:
		return
	if not terrain_manager.chunks_rebuilt.is_connected(_on_terrain_manager_chunks_rebuilt):
		terrain_manager.chunks_rebuilt.connect(_on_terrain_manager_chunks_rebuilt)
	if not terrain_manager.terrain_changed.is_connected(_on_terrain_manager_terrain_changed):
		terrain_manager.terrain_changed.connect(_on_terrain_manager_terrain_changed)


func _unbind_manager() -> void:
	if terrain_manager == null or not is_instance_valid(terrain_manager):
		return
	if terrain_manager.chunks_rebuilt.is_connected(_on_terrain_manager_chunks_rebuilt):
		terrain_manager.chunks_rebuilt.disconnect(_on_terrain_manager_chunks_rebuilt)
	if terrain_manager.terrain_changed.is_connected(_on_terrain_manager_terrain_changed):
		terrain_manager.terrain_changed.disconnect(_on_terrain_manager_terrain_changed)


func _refresh_labels() -> void:
	if not Engine.is_editor_hint():
		return
	_clear_entries()
	if not show_vertex_indices and not show_vertex_positions:
		return
	if terrain_manager == null:
		_resolve_terrain_manager()
	if terrain_manager == null:
		return

	for chunk in terrain_manager.get_chunks():
		_refresh_chunk_labels(chunk)
	_layout_duplicate_labels()


func _refresh_chunk_labels(chunk: TerrainChunk) -> void:
	_clear_chunk_entries(chunk)
	if (not show_vertex_indices and not show_vertex_positions) or not is_instance_valid(chunk):
		return

	var mesh_instance := chunk.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return

	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		if mesh_instance.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue

		var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for vertex_index in range(vertices.size()):
			var vertex_position := vertices[vertex_index]
			var normal := normals[vertex_index] if normals.size() == vertices.size() else vertex_position.normalized()
			var anchor := Node3D.new()
			anchor.name = "VertexLabel_s%d_v%d" % [surface_index, vertex_index]
			anchor.set_meta(LABEL_META, true)
			anchor.position = vertex_position + normal * vertex_label_offset
			mesh_instance.add_child(anchor, false, Node.INTERNAL_MODE_BACK)

			var index_mesh := Node3D.new()
			index_mesh.name = "VertexIndexMesh"
			index_mesh.visible = show_vertex_indices
			anchor.add_child(index_mesh)
			var index_label := _create_label("%04d" % vertex_index, INDEX_COLOR)
			index_mesh.add_child(index_label)

			var position_mesh := Node3D.new()
			position_mesh.name = "VertexPositionMesh"
			position_mesh.position.y = -row_spacing
			position_mesh.visible = show_vertex_positions
			anchor.add_child(position_mesh)
			var position_labels := _create_position_labels()
			for label in position_labels:
				position_mesh.add_child(label)

			var entry := {
				"chunk": chunk,
				"mesh_instance": mesh_instance,
				"vertex_position": vertex_position,
				"normal": normal,
				"anchor_offset": normal * vertex_label_offset,
				"anchor": anchor,
				"index_mesh": index_mesh,
				"position_mesh": position_mesh,
				"position_labels": position_labels,
				"last_world_position": Vector3(INF, INF, INF),
			}
			_entries.append(entry)
			_update_position_text(entry, mesh_instance.to_global(vertex_position))


func _create_label(text: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = OUTLINE_COLOR
	label.no_depth_test = false
	label.fixed_size = true
	label.shaded = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _create_position_labels() -> Array[Label3D]:
	var labels: Array[Label3D] = []
	for axis in range(3):
		var label := _create_label("0.0000", AXIS_COLORS[axis])
		label.position.y = -row_spacing * axis
		labels.append(label)
	return labels


func _update_position_text(entry: Dictionary, world_position: Vector3) -> void:
	var labels: Array[Label3D] = entry["position_labels"]
	labels[0].text = "%.4f" % world_position.x
	labels[1].text = "%.4f" % world_position.y
	labels[2].text = "%.4f" % world_position.z
	entry["last_world_position"] = world_position


func _update_entry_visibility() -> void:
	set_process(show_vertex_indices or show_vertex_positions)
	for entry in _entries:
		var index_mesh: Node3D = entry["index_mesh"]
		var position_mesh: Node3D = entry["position_mesh"]
		if is_instance_valid(index_mesh):
			index_mesh.visible = show_vertex_indices
		if is_instance_valid(position_mesh):
			position_mesh.visible = show_vertex_positions
	if show_vertex_positions:
		for entry in _entries:
			var mesh_instance: MeshInstance3D = entry["mesh_instance"]
			if is_instance_valid(mesh_instance):
				_update_position_text(entry, mesh_instance.to_global(entry["vertex_position"]))


func _layout_duplicate_labels() -> void:
	var entries_by_position: Dictionary = {}
	for entry in _entries:
		var mesh_instance: MeshInstance3D = entry["mesh_instance"]
		if not is_instance_valid(mesh_instance):
			continue
		var world_position: Vector3 = mesh_instance.to_global(entry["vertex_position"])
		var matching_entries: Array = entries_by_position.get(world_position, [])
		matching_entries.append(entry)
		entries_by_position[world_position] = matching_entries

	for entry in _entries:
		entry["anchor_offset"] = entry["normal"] * vertex_label_offset

	for matching_entries in entries_by_position.values():
		if matching_entries.size() < 2:
			continue

		var average_normal := Vector3.ZERO
		for entry in matching_entries:
			var mesh_instance: MeshInstance3D = entry["mesh_instance"]
			var normal: Vector3 = entry["normal"]
			average_normal += (mesh_instance.global_transform.basis * normal).normalized()
		if average_normal.is_zero_approx():
			average_normal = Vector3.UP
		else:
			average_normal = average_normal.normalized()

		var tangent := average_normal.cross(Vector3.UP)
		if tangent.is_zero_approx():
			tangent = average_normal.cross(Vector3.RIGHT)
		tangent = tangent.normalized()
		var bitangent := average_normal.cross(tangent).normalized()

		for index in range(matching_entries.size()):
			var entry: Dictionary = matching_entries[index]
			var mesh_instance: MeshInstance3D = entry["mesh_instance"]
			var angle: float = TAU * float(index) / float(matching_entries.size())
			var world_spread := (
				tangent * cos(angle) + bitangent * sin(angle)
			) * duplicate_label_spread
			var local_spread := mesh_instance.global_transform.basis.inverse() * world_spread
			entry["anchor_offset"] = entry["normal"] * vertex_label_offset + local_spread

	for entry in _entries:
		var anchor: Node3D = entry["anchor"]
		if is_instance_valid(anchor):
			anchor.position = entry["vertex_position"] + entry["anchor_offset"]


func _clear_entries() -> void:
	for entry in _entries:
		var anchor: Node3D = entry["anchor"]
		if is_instance_valid(anchor):
			_dispose_anchor(anchor)
	_entries.clear()


func _clear_chunk_entries(chunk: TerrainChunk) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		if entry["chunk"] != chunk:
			continue
		var anchor: Node3D = entry["anchor"]
		if is_instance_valid(anchor):
			_dispose_anchor(anchor)
		_entries.remove_at(index)


func _dispose_anchor(anchor: Node3D) -> void:
	var parent := anchor.get_parent()
	if parent != null:
		parent.remove_child(anchor)
	anchor.free()


func _on_terrain_manager_chunks_rebuilt(_chunk_count: int) -> void:
	_refresh_labels()


func _on_terrain_manager_terrain_changed(chunk: TerrainChunk) -> void:
	_refresh_chunk_labels(chunk)
	_layout_duplicate_labels()
