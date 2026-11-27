extends Node
## MIDI Controller
##
## MIDI controller controls sound mapping for a singular physical controller
class_name MidiController

signal raw_midi_event(event: InputEventMIDI)
signal mapped_midi_event(event: InputEventMIDI)
signal capture_note(event: InputEventMIDI)
signal mapping_changed(targets: PackedInt32Array)

const CONFIG_VERSION := 1

## Leave empty to accept events from any MIDI input.
@export var midi_input_name: String = ""

var _device_id := -1
var _input_name_resolved := true

## Leave empty to use the identity map.
@export_file("*.json") var mapping_path: String = ""

## Node path to the shared MidiPlayer that owns the SoundFont for this scene.
@export_node_path("MidiPlayer") var midi_player_path: NodePath

## MIDI channel to send mapped events to (0-15). Give each instrument controller
## a separate channel when they share one MidiPlayer.
@export_range(0, 15, 1) var output_channel: int = 0

## SoundFont preset program (0-127) selected for this controller's channel.
@export_range(0, 127, 1) var program_number: int = 0

## SoundFont bank selected for this controller's channel (0-16383).
@export_range(0, 16383, 1) var bank_number: int = 0

## Disable this in the mapper scene to prevent learned keys from playing.
@export var play_sound := true
@export var print_midi := false

@export_node_path("Node") var input_hub_path: NodePath

@onready var midi_player: MidiPlayer = get_node_or_null(midi_player_path) as MidiPlayer

var _input_hub: MidiInputHub
var _pitch_targets := _identity_map()
var _capture_mode := false

# Source note key -> target pitches queued at note-on. This preserves the
# note-on mapping until matching note-off events arrive.
var _active_note_targets: Dictionary = {}


func _ready() -> void:
	if not mapping_path.is_empty() and not load_mapping(mapping_path):
		push_warning(
			"Could not load MIDI mapping '%s'; using identity map."
			% mapping_path
		)

	_input_hub = get_node_or_null(input_hub_path) as MidiInputHub
	if _input_hub == null:
		push_error(
			"MidiController needs input_hub_path set to a MidiInputHub node."
		)
		return

	if not _input_hub.midi_event.is_connected(_on_midi_event):
		_input_hub.midi_event.connect(_on_midi_event)

	if not midi_input_name.is_empty():
		_device_id = _input_hub._connected_midi_inputs.find(midi_input_name)
		_input_name_resolved = _device_id >= 0

		if not _input_name_resolved:
			push_warning(
				"MIDI input '%s' is not connected; this controller will ignore MIDI events."
				% midi_input_name
			)

	_configure_output_channel()

	if play_sound:
		if midi_player == null:
			push_warning(
				"Sound playback is enabled, but midi_player_path does not point "
				+ "to a shared MidiPlayer."
			)
		elif midi_player.bank == null:
			push_warning("The shared MidiPlayer has no loaded SoundFont.")


func _exit_tree() -> void:
	if is_instance_valid(_input_hub):
		if _input_hub.midi_event.is_connected(_on_midi_event):
			_input_hub.midi_event.disconnect(_on_midi_event)


# Mapping API

func get_pitch_targets() -> PackedInt32Array:
	return _pitch_targets.duplicate()


func set_pitch_targets(targets: PackedInt32Array) -> bool:
	if targets.size() != 128:
		push_warning("A MIDI mapping must contain exactly 128 values.")
		return false

	for target in targets:
		if target < -1 or target > 127:
			push_warning("MIDI mapping values must be between -1 and 127.")
			return false

	_pitch_targets = targets.duplicate()
	mapping_changed.emit(get_pitch_targets())
	return true

func reset_mapping() -> void:
	_pitch_targets = _identity_map()
	mapping_changed.emit(get_pitch_targets())


func set_pitch_mapping(source_pitch: int, target_pitch: int) -> bool:
	if source_pitch < 0 or source_pitch > 127:
		push_warning("Source MIDI pitch must be between 0 and 127.")
		return false
	if target_pitch < -1 or target_pitch > 127:
		push_warning("Target MIDI pitch must be between -1 and 127.")
		return false

	_pitch_targets[source_pitch] = target_pitch
	mapping_changed.emit(get_pitch_targets())
	return true


# Capture API

func begin_capture() -> void:
	_capture_mode = true


func end_capture() -> void:
	_capture_mode = false


# Mapping file API

func load_mapping(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	if parsed.get("version", null) != CONFIG_VERSION:
		return false

	var raw_targets: Variant = parsed.get("pitch_targets", null)
	if not raw_targets is Array:
		return false
	if raw_targets.size() != 128:
		return false

	var loaded_targets := PackedInt32Array()
	loaded_targets.resize(128)

	for pitch in range(128):
		var value: Variant = raw_targets[pitch]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return false

		var target := int(value)
		if target < -1 or target > 127:
			return false

		loaded_targets[pitch] = target

	_pitch_targets = loaded_targets
	mapping_changed.emit(get_pitch_targets())
	return true


func save_mapping(path: String = "") -> bool:
	var destination := path
	if destination.is_empty():
		destination = mapping_path
	if destination.is_empty():
		return false

	var document := {
		"version": CONFIG_VERSION,
		"pitch_targets": Array(_pitch_targets),
	}

	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		push_error("Could not write MIDI mapping: %s" % destination)
		return false

	file.store_string(JSON.stringify(document, "\t"))
	return true


# MIDI input pipeline

func _on_midi_event(event: InputEventMIDI) -> void:
	if not _input_name_resolved:
		return
	if _device_id != -1 and event.device != _device_id:
		return

	if _capture_mode:
		raw_midi_event.emit(event)
		if _is_note_on(event):
			capture_note.emit(event)
		return

	raw_midi_event.emit(event)

	if _is_note_off(event):
		_forward_note_off(event)
		return

	if _is_note_on(event):
		_forward_note_on(event)
		return

	_forward_mapped_event(event.duplicate() as InputEventMIDI)


func _forward_note_on(event: InputEventMIDI) -> void:
	var target_pitch := _pitch_targets[event.pitch]
	
	if print_midi:
		var source_name := midi_input_name
		if source_name.is_empty():
			source_name = "Any MIDI input"
		print("[%s] %s" % [source_name, event])

	# -1 disables this source pitch.
	if target_pitch < 0:
		return

	var note_key := _make_note_key(event)
	if not _active_note_targets.has(note_key):
		_active_note_targets[note_key] = []

	var queued_targets: Array = _active_note_targets[note_key]
	queued_targets.append(target_pitch)

	var note_on := event.duplicate() as InputEventMIDI
	note_on.pitch = target_pitch
	_forward_mapped_event(note_on)


func _forward_note_off(event: InputEventMIDI) -> void:
	var note_key := _make_note_key(event)
	if not _active_note_targets.has(note_key):
		return

	
	if print_midi:
		var source_name := midi_input_name
		if source_name.is_empty():
			source_name = "Any MIDI input"
		print("[%s] %s" % [source_name, event])


	var queued_targets: Array = _active_note_targets[note_key]
	var target_pitch := int(queued_targets.pop_front())

	if queued_targets.is_empty():
		_active_note_targets.erase(note_key)
	else:
		_active_note_targets[note_key] = queued_targets

	var note_off := event.duplicate() as InputEventMIDI
	note_off.pitch = target_pitch
	note_off.message = MIDI_MESSAGE_NOTE_OFF
	_forward_mapped_event(note_off)


func _forward_mapped_event(event: InputEventMIDI) -> void:
	var output_event := event.duplicate() as InputEventMIDI
	output_event.channel = output_channel

	# The controller's inspector settings own the shared channel's instrument.
	# Ignore incoming program and bank changes so one physical controller cannot
	# change another controller's instrument or replace its configured preset.
	if output_event.message == MIDI_MESSAGE_PROGRAM_CHANGE:
		return
	if (
		output_event.message == MIDI_MESSAGE_CONTROL_CHANGE
		and output_event.controller_number in [0, 32]
	):
		return

	mapped_midi_event.emit(output_event)

	if play_sound and midi_player != null:
		midi_player.receive_raw_midi_message(output_event)


func _configure_output_channel() -> void:
	if midi_player == null:
		return
	if output_channel < 0 or output_channel >= midi_player.channel_status.size():
		push_warning("Output MIDI channel must be between 0 and 15.")
		return

	var channel_status = midi_player.channel_status[output_channel]
	channel_status.program = program_number
	channel_status.bank = bank_number


# Helpers

func _is_note_on(event: InputEventMIDI) -> bool:
	return event.message == MIDI_MESSAGE_NOTE_ON and event.velocity > 0


func _is_note_off(event: InputEventMIDI) -> bool:
	return (
		event.message == MIDI_MESSAGE_NOTE_OFF
		or (
			event.message == MIDI_MESSAGE_NOTE_ON
			and event.velocity == 0
		)
	)


func _make_note_key(event: InputEventMIDI) -> String:
	return "%d:%d:%d" % [event.device, event.channel, event.pitch]


func _identity_map() -> PackedInt32Array:
	var targets := PackedInt32Array()
	targets.resize(128)

	for pitch in range(128):
		targets[pitch] = pitch

	return targets
