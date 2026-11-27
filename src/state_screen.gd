# For UI screen, essentially 'on/off'
extends Control

# Dropdown in the inspector, order must match
@export_enum("Attract", "Prepare", "Create", "Finished", "Galaxy") var show_in: int = 0

func _ready() -> void:
	# When there is a state change, call _on_change_state function
	StateManager.change_state.connect(_on_change_state)
	# Show or hide at start too
	visible = (StateManager.state == show_in)

# Triggered for new states
func _on_change_state(new_state: int) -> void:
	visible = (new_state == show_in)
