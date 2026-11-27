@tool
## A chunk is a segment of a larger Mesh,
## which has its own collision_shape and mesh_instance.
##
## A Chunk is initialized by a ChunkManager.
extends AnimatableBody3D
class_name Chunk

const FACE_POSITION_TOLERANCE := 0.0001

@export var mesh: ArrayMesh:
	set(value):
		mesh = value

		# mesh is not allowed to be a null value if its gonna get assigned
		if mesh != null:
			mesh_instance.mesh = value
			if collision_shape != null:
				collision_shape.shape = value.create_trimesh_shape()



@export var collision_shape: CollisionShape3D:
	set(value):
		collision_shape = value

@export_category("Debugging")
@export_range(0, 10000, 1) var max_indices_to_print: int = 8
@export_tool_button("print mesh & collision shapes") var print_action = print_shapes
@export_tool_button("check mesh & collision mapping") var check_action = check_face_indices


# private mesh instance, we propagate down the array mesh rather than
# a brand new mesh instance.
var mesh_instance: MeshInstance3D = MeshInstance3D.new()

## pretty prints each face index and their middle position. ai generated.
func print_shapes() -> void:
	if mesh_instance.mesh == null:
		print_rich("[color=yellow]Mesh: <null>[/color]")
	else:
		var mesh_rows: Array[String] = []
		var mesh_index_count := 0
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var surface_arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			var face_indices: PackedInt32Array = surface_arrays[Mesh.ARRAY_INDEX]
			if face_indices.is_empty():
				var vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
				face_indices = PackedInt32Array(range(vertices.size()))
			var surface_vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
			for vertex_index in face_indices:
				mesh_index_count += 1
				if vertex_index < 0 or vertex_index >= surface_vertices.size():
					push_error("Cannot print mesh indices: surface %d contains invalid vertex index %d." % [
						surface_index,
						vertex_index,
					])
					continue
				if mesh_rows.size() < max_indices_to_print:
					mesh_rows.append("surface %d | index %d | %s" % [
						surface_index,
						vertex_index,
						mesh_instance.to_global(surface_vertices[vertex_index]),
					])
		print_rich("[color=yellow]Mesh face indices | global positions[/color]")
		for row in mesh_rows:
			print_rich("[color=yellow]%s[/color]" % row)
		if mesh_index_count > mesh_rows.size():
			print_rich("[color=yellow]Showing %d of %d mesh indices.[/color]" % [
				mesh_rows.size(),
				mesh_index_count,
			])

	if collision_shape == null or collision_shape.shape == null:
		print_rich("[color=cyan]Collision: <null>[/color]")
	else:
		var collision_faces: PackedVector3Array
		if collision_shape.shape is ConcavePolygonShape3D:
			collision_faces = (collision_shape.shape as ConcavePolygonShape3D).get_faces()
		else:
			var debug_mesh := collision_shape.shape.get_debug_mesh()
			if debug_mesh == null:
				print_rich("[color=cyan]Collision shape has no debug mesh.[/color]")
				return
			collision_faces = debug_mesh.get_faces()
		var collision_rows: Array[String] = []
		for collision_index in range(collision_faces.size()):
			if collision_rows.size() >= max_indices_to_print:
				break
			collision_rows.append("index %d | %s" % [
				collision_index,
				collision_shape.to_global(collision_faces[collision_index]),
			])
		print_rich("[color=cyan]Collision face vertices | global positions[/color]")
		for row in collision_rows:
			print_rich("[color=cyan]%s[/color]" % row)
		if collision_faces.size() > collision_rows.size():
			print_rich("[color=cyan]Showing %d of %d collision indices.[/color]" % [
				collision_rows.size(),
				collision_faces.size(),
			])


## pretty prints stuff. ai generated
func check_face_indices() -> bool:
	if mesh_instance.mesh == null:
		push_error("Cannot check face indices: mesh is null.")
		return false
	if collision_shape == null or collision_shape.shape == null:
		push_error("Cannot check face indices: collision shape is null.")
		return false
	if not (collision_shape.shape is ConcavePolygonShape3D):
		push_error("Cannot check face indices: collision shape is not a ConcavePolygonShape3D.")
		return false

	var collision_faces: PackedVector3Array = (collision_shape.shape as ConcavePolygonShape3D).get_faces()
	var collision_vertex_index := 0
	var mapping_rows: Array[String] = []

	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		if mesh_instance.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			push_error("Cannot check face indices: mesh surface %d is not triangle-based." % surface_index)
			return false

		var surface_arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
		var face_indices: PackedInt32Array = surface_arrays[Mesh.ARRAY_INDEX]
		if face_indices.is_empty():
			face_indices = PackedInt32Array(range(vertices.size()))
		if face_indices.size() % 3 != 0:
			push_error("Cannot check face indices: mesh surface %d has an incomplete triangle." % surface_index)
			return false

		for index_offset in range(face_indices.size()):
			if collision_vertex_index >= collision_faces.size():
				push_error("Face index mapping mismatch: collision shape has fewer face vertices than the mesh.")
				return false

			var vertex_index := face_indices[index_offset]
			if vertex_index < 0 or vertex_index >= vertices.size():
				push_error("Cannot check face indices: mesh surface %d contains invalid vertex index %d." % [
					surface_index,
					vertex_index,
				])
				return false

			var mesh_position := mesh_instance.to_global(vertices[vertex_index])
			var collision_position := collision_shape.to_global(collision_faces[collision_vertex_index])
			if mesh_position.distance_squared_to(collision_position) > FACE_POSITION_TOLERANCE * FACE_POSITION_TOLERANCE:
				push_error("Face index mapping mismatch at mesh surface %d, face %d, corner %d: mesh index %d maps to %s, collision has %s." % [
					surface_index,
					int(index_offset / 3),
					index_offset % 3,
					vertex_index,
					mesh_position,
					collision_position,
				])
				return false

			if mapping_rows.size() < max_indices_to_print:
				var mesh_columns := "%s | %s | %s | %s" % [
					("%d:%d" % [surface_index, int(index_offset / 3)]).rpad(12),
					str(index_offset % 3).rpad(6),
					str(vertex_index).rpad(10),
					str(mesh_position).rpad(32),
				]
				var collision_columns := "%s | %s" % [
					str(collision_vertex_index).rpad(15),
					str(collision_position),
				]
				mapping_rows.append(mesh_columns + " || " + collision_columns)
			collision_vertex_index += 1

	if collision_vertex_index != collision_faces.size():
		push_error("Face index mapping mismatch: collision shape has %d extra face vertices." % [
			collision_faces.size() - collision_vertex_index,
		])
		return false

	print_rich("[color=yellow]%s | %s | %s | %s[/color] || [color=cyan]%s | %s[/color]" % [
		"Surface:Face".rpad(12),
		"Corner".rpad(6),
		"Mesh index".rpad(10),
		"Mesh global position".rpad(32),
		"Collision index".rpad(15),
		"Collision global position",
	])
	print("------------|--------|------------|----------------------------------||-----------------|------------------------")
	for row in mapping_rows:
		var columns := row.split(" || ")
		print_rich("[color=yellow]%s[/color] | [color=cyan]%s[/color]" % [
			columns[0],
			columns[1],
		])
	if collision_vertex_index > mapping_rows.size():
		print("Showing %d of %d mapped indices." % [
			mapping_rows.size(),
			collision_vertex_index,
		])
	print_rich("[color=yellow]Mesh face indices match[/color] [color=cyan]collision face positions.[/color]")
	return true

func _ready() -> void:
	# 1. Get or Create MeshInstance3D
	if not has_node("ChunkMesh"):
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "ChunkMesh"
		add_child(mesh_instance)

		if Engine.is_editor_hint() and is_inside_tree():
			var root := get_tree().edited_scene_root
			if root != null:
				mesh_instance.owner = root
	else:
		mesh_instance = get_node("ChunkMesh")

	# Ensure mesh syncs when node enters tree
	mesh_instance.mesh = self.mesh

	# 2. Get or Create CollisionShape3D
	if not has_node("ChunkCollision"):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "ChunkCollision"
		collision_shape.shape = mesh_instance.mesh.create_trimesh_shape() if mesh_instance.mesh != null else null
		add_child(collision_shape)

		if Engine.is_editor_hint() and is_inside_tree():
			var root := get_tree().edited_scene_root
			if root != null:
				collision_shape.owner = root
	else:
		collision_shape = get_node("ChunkCollision")
