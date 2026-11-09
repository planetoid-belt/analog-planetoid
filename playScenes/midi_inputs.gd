extends Node

@onready var midi_player: MidiPlayer = $MidiPlayer

func _ready() -> void:
	OS.open_midi_inputs()
	print("Connected MIDI inputs: ", OS.get_connected_midi_inputs())

	if midi_player.bank == null:
		push_error("MIDI player has no loaded SoundFont.")
	else:
		print("Loaded SoundFont presets: ", midi_player.bank.presets.size())


func _input(event: InputEvent) -> void:
	if event is InputEventMIDI:
		# Filtered event inputs due to SubZero MIDI interface
		# message=348, midi in 1
		# message=354, midi in 2
		if event.message == 248 or event.message == 254:
			return
		var midi_event := event as InputEventMIDI
		print(midi_event)
		midi_player.receive_raw_midi_message(midi_event)
