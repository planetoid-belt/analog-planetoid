@tool
## Chunk manager node for hexapsherical terrain.
##
## This node divides up a quadsphere into 6 seperate mesh instances, which are appended to a mesh_chunks array.
## Each of these mesh_chunks can be edited individually via mesh_chunks[i].mesh. ordering in the array goes like this:
	## +x, -x, +y, -y, +z, -z.
class_name ChunkManager
extends Node3D

## the quadsphere mesh itself. This can be modified to
@export var quadsphere: QuadSphere:
	set(value):
		if quadsphere != null and quadsphere.changed.is_connected(_rebuild_chunks):
			quadsphere.changed.disconnect(_rebuild_chunks)

		quadsphere = value

		if quadsphere != null:
			quadsphere.surface_splitting = true
			if not quadsphere.changed.is_connected(_rebuild_chunks):
				quadsphere.changed.connect(_rebuild_chunks)

		if is_inside_tree():
			_validate_mesh_chunks()
			_rebuild_chunks()

## an array of chunks. In the scene tree, these are children to the ChunkManager.
@export var mesh_chunks: Array[Chunk]

## a script that will be attached to each chunk.
## TODO: on script update, set existing chunk children
## to hold the new script.
@export var chunk_script: GDScript = load("res://src/chunk.gd")

func _ready() -> void:
	if quadsphere == null:
		quadsphere = QuadSphere.new()

	_validate_mesh_chunks()
	_rebuild_chunks()

# ensures that mesh_chunks is in a valid state.
func _validate_mesh_chunks() -> void:
	if quadsphere == null:
		mesh_chunks.clear()
		return

	var validated_chunk_holders: Array[Chunk] = []
	for chunk_name in QuadSphere.CHUNK_NAMES:
		var chunk_instance := get_node_or_null(chunk_name) as Chunk
		if chunk_instance == null:
			chunk_instance = Chunk.new()
			chunk_instance.name = chunk_name
			chunk_instance.set_script(chunk_script)
			add_child(chunk_instance)

		if Engine.is_editor_hint() and is_inside_tree():
			var scene_tree := get_tree()
			if scene_tree != null:
				var edited_scene_root := scene_tree.edited_scene_root
				if edited_scene_root != null and edited_scene_root.is_ancestor_of(chunk_instance):
					chunk_instance.owner = edited_scene_root

		validated_chunk_holders.append(chunk_instance)

	mesh_chunks = validated_chunk_holders

# called whenever the quadsphere resource receives an update.
# Can also be used to reset chunks to the initial quadsphere configuration.
# TODO: maybe give it a better name?
func _rebuild_chunks() -> void:
	_validate_mesh_chunks()
	# check if we have 6 surfaces. if we dont, clear every chunk_instance.
	if not quadsphere.surface_splitting or quadsphere.get_surface_count() < 6:
		for chunk_instance in mesh_chunks:
			chunk_instance.mesh = null
		return

	for chunk_index in range(6):
		var chunk_mesh := ArrayMesh.new()
		chunk_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			quadsphere.surface_get_arrays(chunk_index)
		)
		chunk_mesh.surface_set_name(0, QuadSphere.CHUNK_NAMES[chunk_index])

		var material := quadsphere.surface_get_material(chunk_index)
		if material != null:
			chunk_mesh.surface_set_material(0, material)

		mesh_chunks[chunk_index].mesh = chunk_mesh
