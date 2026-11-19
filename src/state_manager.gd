# Autoloads at startup (In project settings -> Globals -> Autoload
extends Node

# Possible/allowed states
enum curr_state { Attract, Prepare, Create, Finished, Galaxy }

signal change_state(new_state: curr_state)

# Which states we can move to from the current state: 
const allowed_states := {
curr_state.Attract : [curr_state.Prepare, curr_state.Galaxy],
curr_state.Prepare: [curr_state.Attract, curr_state.Create],
curr_state.Create: [curr_state.Prepare, curr_state.Finished, curr_state.Attract],
curr_state.Finished: [curr_state.Create, curr_state.Galaxy, curr_state.Attract],
curr_state.Galaxy: [curr_state.Finished, curr_state.Attract]}


var state: curr_state = curr_state.Attract

# Move to next state, block unallowed 
func go(next:curr_state) -> void: 
	if next == state: return
	if not (next in allowed_states[state]):
		push_warning("Not an allowed transition")
		return
	print("State: ", curr_state.keys()[state], " -> ", curr_state.keys()[next])
	state = next
	change_state.emit(next) # signal
	
	
# Listen to keyboard and call go()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("host_next"):
		# step forward through the flow to test screens
		match state:
			curr_state.Attract:  go(curr_state.Prepare)
			curr_state.Prepare:  go(curr_state.Create)
			curr_state.Create:   go(curr_state.Finished)
			curr_state.Finished: go(curr_state.Galaxy)
	elif event.is_action_pressed("host_cancel"):
		go(curr_state.Attract)
	elif event.is_action_pressed("host_galaxy"):
		go(curr_state.Galaxy)

func _ready() -> void:
	print("StateManager is running")

#Debug 
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		print("key: ", event.as_text(), " | host_next? ", event.is_action_pressed("host_next"))

# Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass
