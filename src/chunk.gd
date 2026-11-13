@tool
## A chunk is a segment of a larger Mesh,
## which has its own collision_shape and mesh_instance.
##
## A Chunk is initialized by a ChunkManager.
extends AnimatableBody3D
class_name Chunk

@export var mesh: ArrayMesh:
	set(value):
		mesh = value

		# mesh is not allowed to be a null value if its gonna get assigned
		if mesh != null:
			mesh_instance.mesh = value

@export var collision_shape: CollisionShape3D:
	set(value):
		collision_shape = value

# private mesh instance, we propagate down the array mesh rather than
# a brand new mesh instance.
var mesh_instance: MeshInstance3D = MeshInstance3D.new()


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
		add_child(collision_shape)

		if Engine.is_editor_hint() and is_inside_tree():
			var root := get_tree().edited_scene_root
			if root != null:
				collision_shape.owner = root
	else:
		collision_shape = get_node("ChunkCollision")
