@tool
class_name HexaSphereChunkHolder
extends Node3D

@export var hexasphere: HexaSphere:
	set(value):
		if hexasphere != null and hexasphere.changed.is_connected(_rebuild_chunks):
			hexasphere.changed.disconnect(_rebuild_chunks)

		hexasphere = value

		if hexasphere != null:
			# automatically turn on surface_splitting if its not on
			hexasphere.surface_splitting = true
			hexasphere.changed.connect(_rebuild_chunks)

		_rebuild_chunks()

@export var chunk_holders: Array[MeshInstance3D]
# divvy the mesh up into chunks based on something reasonable.


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _rebuild_chunks() -> void:
	if hexasphere == null or not hexasphere.surface_splitting or hexasphere.get_surface_count() < 6:
			return
	for c in range(6):
			var chunk_name: String = HexaSphere.CHUNK_NAMES[c]
			var chunk_instance := get_node_or_null(chunk_name) as MeshInstance3D

			if chunk_instance == null:
				chunk_instance = MeshInstance3D.new()
				chunk_instance.name = chunk_name
				add_child(chunk_instance)

			var chunk_mesh := ArrayMesh.new()
			chunk_mesh.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES,
				hexasphere.surface_get_arrays(c)
			)
			chunk_mesh.surface_set_name(0, chunk_name)
			chunk_instance.mesh = chunk_mesh
