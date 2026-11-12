@tool
## Chunk manager node for hexapsherical terrain. This node divides up a Hexasphere into 6 seperate mesh instances,
## which are appended to a mesh_chunks array. Each of these mesh_chunks can be edited individually via mesh_chunks[i].mesh
## The ordering of chunks in the array goes like this: +x, -x, +y, -y, +z, -z.
class_name ChunkManager
extends Node3D

## the hexasphere mesh itself. This can be modified to
@export var hexasphere: HexaSphere:
	set(value):
		if hexasphere != null and hexasphere.changed.is_connected(_rebuild_chunks):
			hexasphere.changed.disconnect(_rebuild_chunks)

		hexasphere = value

		if hexasphere != null:
			hexasphere.surface_splitting = true
			if not hexasphere.changed.is_connected(_rebuild_chunks):
				hexasphere.changed.connect(_rebuild_chunks)

		if is_inside_tree():
			_validate_mesh_chunks()
			_rebuild_chunks()

## an array of mesh chunks. These are children to the ChunkManager.
@export var mesh_chunks: Array[MeshInstance3D]

## a script that will be attached to each chunk.
## TODO: on script update, set existing chunk children
## to hold the new script.
@export var chunk_script: GDScript = load("res://src/chunk.gd")

func _ready() -> void:
	if hexasphere == null:
		hexasphere = HexaSphere.new()

	_validate_mesh_chunks()
	_rebuild_chunks()

# ensures that mesh_chunks is in a valid state.
func _validate_mesh_chunks() -> void:
	if hexasphere == null:
		mesh_chunks.clear()
		return

	var validated_chunk_holders: Array[MeshInstance3D] = []
	for chunk_name in HexaSphere.CHUNK_NAMES:
		var chunk_instance := get_node_or_null(chunk_name) as MeshInstance3D
		if chunk_instance == null:
			chunk_instance = MeshInstance3D.new()
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

# called whenever the hexasphere resource receives an update.
# Can also be used to reset chunks to the initial hexasphere configuration.
# TODO: maybe give it a better name?
func _rebuild_chunks() -> void:
	if hexasphere == null:
		return

	_validate_mesh_chunks()
	if not hexasphere.surface_splitting or hexasphere.get_surface_count() < 6:
		for chunk_instance in mesh_chunks:
			chunk_instance.mesh = null
		return

	for chunk_index in range(6):
		var chunk_mesh := ArrayMesh.new()
		chunk_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			hexasphere.surface_get_arrays(chunk_index)
		)
		chunk_mesh.surface_set_name(0, HexaSphere.CHUNK_NAMES[chunk_index])

		var material := hexasphere.surface_get_material(chunk_index)
		if material != null:
			chunk_mesh.surface_set_material(0, material)

		mesh_chunks[chunk_index].mesh = chunk_mesh
