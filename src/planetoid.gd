extends Node3D


## anchor node position depends on the quadsphere's unit size.
@export var anchor_node: Node3D

@export var chunk_manager: ChunkManager

## the quadsphere is the source of truth that the chunk manager uses.
## sort of the same thing as making a variable "public", but in node language instead.
@export var quadsphere: QuadSphere

@export var animation_player: AnimationPlayer

## planetoid script does everything related to the planetoid:
## This includes rotation, applying planetoid-wide changes, and more.

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if animation_player != null:
		animation_player.current_animation = "revolution"
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
