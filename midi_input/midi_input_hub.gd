extends Node
class_name MidiInputHub

signal midi_event(event: InputEventMIDI)

var _midi_inputs_open := false


func _ready() -> void:
	OS.open_midi_inputs()
	_midi_inputs_open = true
	print("Connected MIDI inputs: ", OS.get_connected_midi_inputs())


func _input(event: InputEvent) -> void:
	if event is InputEventMIDI:
		midi_event.emit(event as InputEventMIDI)


func _exit_tree() -> void:
	if _midi_inputs_open:
		OS.close_midi_inputs()
		_midi_inputs_open = false