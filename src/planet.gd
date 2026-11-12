@tool
extends Node3D

## rotation speed is given in radians. The amount specified will be multiplied by delta.
@export var rotation_speed = 0.1:
	set(value):
		rotation_speed = value

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	rotate_y(rotation_speed*delta)
