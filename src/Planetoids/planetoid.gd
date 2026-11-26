@tool
## the Planetoid script. This thing manages its children, and it should preferably NOT touch
## its grandchildren.
extends Node3D

## The anchor node. Attach cameras & other things that are meant to be stationary here.
@export var anchor_node: Node3D

## TerrainManager handles everything related to terrain <3 which happens to be A LOT. It handles
## mesh deformation and vertex coloring.
@export var terrain_manager: TerrainManager:
	set(value):
		terrain_manager = value
		if terrain_manager != null and quadsphere != null:
			terrain_manager.quadsphere = quadsphere

## QuadSphere resource. this is the base geometry of our scene.
@export var quadsphere: QuadSphere:
	set(value):
		quadsphere = value
		if terrain_manager != null:
			terrain_manager.quadsphere = value

## an array of textures that can be used to keep track of the planetoid's terrain.
## For instance, a height map. This is managed by the TerrainManager.
@export var maps: Array[Texture2D]

## the animation player that controls rotation of the planetoid.
## For any element that you want to have animated, use the animation player to manage it.
@export var animation_player: AnimationPlayer

var _source_mesh_instance: MeshInstance3D
var _source_mesh_was_visible := true


func _ready() -> void:
	_ensure_hierarchy()
	if quadsphere == null:
		_cache_quadsphere_source()
		if _source_mesh_instance != null:
			quadsphere = _source_mesh_instance.mesh as QuadSphere
	else:
		_cache_quadsphere_source()

	if terrain_manager != null and quadsphere != null:
		terrain_manager.quadsphere = quadsphere
		if terrain_manager.get_chunks().is_empty():
			terrain_manager.rebuild_chunks()
		_update_source_mesh_visibility(terrain_manager.get_chunks().size())
	if animation_player != null and not animation_player.is_playing() and animation_player.has_animation("revolution"):
		animation_player.play("revolution")

# helper function for making sure that we have everything ready :)
# ai generated.
func _ensure_hierarchy() -> void:
	if anchor_node == null:
		anchor_node = get_node_or_null("Anchor") as Node3D
	if anchor_node == null:
		anchor_node = Node3D.new()
		anchor_node.name = "Anchor"
		add_child(anchor_node)
		_set_editor_owner(anchor_node)

	if terrain_manager == null:
		terrain_manager = get_node_or_null("TerrainManager") as TerrainManager
	if terrain_manager == null:
		terrain_manager = TerrainManager.new()
		terrain_manager.name = "TerrainManager"
		add_child(terrain_manager)
		_set_editor_owner(terrain_manager)
	if not terrain_manager.chunks_rebuilt.is_connected(_on_chunks_rebuilt):
		terrain_manager.chunks_rebuilt.connect(_on_chunks_rebuilt)

	if animation_player == null:
		animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer


# ai generated. kinda pointless? like this is gonna run at most once.
func _find_quadsphere_source(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is TerrainManager:
			continue
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh is QuadSphere:
			return mesh_instance
		var nested_source := _find_quadsphere_source(child)
		if nested_source != null:
			return nested_source
	return null

# pointless? ai generated
func _cache_quadsphere_source() -> void:
	if _source_mesh_instance != null and is_instance_valid(_source_mesh_instance):
		return
	_source_mesh_instance = _find_quadsphere_source(self)
	if _source_mesh_instance != null:
		_source_mesh_was_visible = _source_mesh_instance.visible

# pointless? ai generated
func _update_source_mesh_visibility(chunk_count: int) -> void:
	if _source_mesh_instance != null and _source_mesh_instance.mesh == quadsphere:
		_source_mesh_instance.visible = _source_mesh_was_visible and chunk_count == 0


func _on_chunks_rebuilt(chunk_count: int) -> void:
	_cache_quadsphere_source()
	_update_source_mesh_visibility(chunk_count)


func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var scene_tree := get_tree()
	if scene_tree == null:
		return
	var edited_scene_root := scene_tree.edited_scene_root
	if edited_scene_root != null:
		node.owner = edited_scene_root
