extends Node
## MIDI Input hub
##
## Reads all MIDI input controllers and serializes them accordingly. Receives MIDI inputs and propagates them down to respective controller children
class_name MidiInputHub

signal midi_event(event: InputEventMIDI)

var _midi_inputs_open := false
var _connected_midi_inputs := []

func _enter_tree() -> void:
	if _midi_inputs_open:
		return

	OS.open_midi_inputs()
	_midi_inputs_open = true
	_connected_midi_inputs = OS.get_connected_midi_inputs()
	print("Connected MIDI inputs: ", _connected_midi_inputs)


func _input(event: InputEvent) -> void:
	if event is InputEventMIDI:
		midi_event.emit(event as InputEventMIDI)


func _exit_tree() -> void:
	if _midi_inputs_open:
		OS.close_midi_inputs()
		_midi_inputs_open = false
