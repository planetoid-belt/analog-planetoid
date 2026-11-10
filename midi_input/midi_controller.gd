extends Node

const CONFIG_VERSION := 1
const DEFAULT_MAPPING_PATH := "user://midi_controller_mappings.json"

const NOTE_NAMES: Array[String] = [
	"C", "C#", "D", "D#", "E", "F",
	"F#", "G", "G#", "A", "A#", "B",
]

func _note_name(pitch: int) -> String:
	if pitch < 0 or pitch > 127:
		return "Disabled"

	var octave := floori(float(pitch) / 12.0) - 1
	return "%s%d" % [NOTE_NAMES[pitch % 12], octave]


@export var filepath: String = DEFAULT_MAPPING_PATH

@onready var midi_player: MidiPlayer = $MidiPlayer

var default_pitch_targets: PackedInt32Array
var controller_profiles: Array[Dictionary] = []

# Input note key -> output note, saved at note-on so note-off
# releases the same output even if a profile changes.
var _active_note_targets: Dictionary = {}


func _ready() -> void:
	default_pitch_targets = _identity_map()
	_load_mapping_file(filepath)

	OS.open_midi_inputs()
	print("Connected MIDI inputs: ", OS.get_connected_midi_inputs())

	if midi_player.bank == null:
		push_error("MIDI player has no loaded SoundFont.")
	else:
		print("Loaded SoundFont presets: ", midi_player.bank.presets.size())


func _exit_tree() -> void:
	OS.close_midi_inputs()


func _input(event: InputEvent) -> void:
	if not event is InputEventMIDI:
		return

	var midi_event := event as InputEventMIDI

	# Ignore MIDI clock and active-sensing messages.
	if midi_event.message == 248 or midi_event.message == 254:
		return

	var note_key := _make_note_key(midi_event)
	var is_note_off := (
		midi_event.message == MIDI_MESSAGE_NOTE_OFF
		or (
			midi_event.message == MIDI_MESSAGE_NOTE_ON
			and midi_event.velocity == 0
		)
	)

	if is_note_off:
		if not _active_note_targets.has(note_key):
			return

		var target_pitch: int = _active_note_targets[note_key]
		_active_note_targets.erase(note_key)

		var note_off := _copy_event_with_pitch(midi_event, target_pitch)
		if midi_event.message == MIDI_MESSAGE_NOTE_ON:
			# MIDI allows velocity-zero note-on as note-off.
			note_off.message = MIDI_MESSAGE_NOTE_OFF

		midi_player.receive_raw_midi_message(note_off)
		return

	if midi_event.message == MIDI_MESSAGE_NOTE_ON:
		var targets := _targets_for_event(midi_event)
		var target_pitch: int = targets[midi_event.pitch]

		# -1 in the mapping disables this input pitch.
		if target_pitch < 0:
			return


		print(
			"Mapped %s (%d) → %s (%d)" % [
				_note_name(midi_event.pitch),
				midi_event.pitch,
				_note_name(target_pitch),
				target_pitch,
			]
		)

		_active_note_targets[note_key] = target_pitch
		midi_player.receive_raw_midi_message(
			_copy_event_with_pitch(midi_event, target_pitch)
		)
		return

	# Forward pitch bend, sustain, modulation, program changes, and other
	# MIDI messages unchanged.
	midi_player.receive_raw_midi_message(midi_event)


func _load_mapping_file(path: String) -> void:
	if path.is_empty():
		push_warning("MidiController filepath is empty; using the identity map.")
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning(
			"Could not open MIDI mapping file '%s'; using the identity map."
			% path
		)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning(
			"MIDI mapping file '%s' is not a JSON object; using identity map."
			% path
		)
		return

	if int(parsed.get("version", -1)) != CONFIG_VERSION:
		push_warning(
			"Unsupported MIDI mapping version in '%s'; using identity map."
			% path
		)
		return

	# Parse into temporary values first so a bad file does not leave the
	# controller with a partially loaded configuration.
	var loaded_default := _normalize_map(
		parsed.get("default_pitch_targets", [])
	)
	var loaded_profiles: Array[Dictionary] = []

	var raw_profiles: Variant = parsed.get("profiles", [])
	if raw_profiles is Array:
		for raw_profile in raw_profiles:
			if not raw_profile is Dictionary:
				continue

			var channel := int(raw_profile.get("channel", -1))
			if channel < -1 or channel > 15:
				continue

			loaded_profiles.append({
				"name": str(raw_profile.get("name", "MIDI Controller")),
				"device_id": int(raw_profile.get("device_id", -1)),
				"channel": channel,
				"pitch_targets": _normalize_map(
					raw_profile.get("pitch_targets", [])
				),
			})

	default_pitch_targets = loaded_default
	controller_profiles = loaded_profiles

	print(
		"Loaded MIDI mapping '%s' with %d controller profile(s)."
		% [path, controller_profiles.size()]
	)


func _targets_for_event(event: InputEventMIDI) -> PackedInt32Array:
	var profile_index := _find_profile_for_event(event)
	if profile_index < 0:
		return _normalize_map(default_pitch_targets)

	var profile := controller_profiles[profile_index]
	return _normalize_map(profile.get("pitch_targets", []))


func _find_profile_for_event(event: InputEventMIDI) -> int:
	var best_index := -1
	var best_specificity := -1

	for index in range(controller_profiles.size()):
		var profile := controller_profiles[index]
		var device_id := int(profile.get("device_id", -1))
		var channel := int(profile.get("channel", -1))

		if device_id != -1 and device_id != event.device:
			continue
		if channel != -1 and channel != event.channel:
			continue

		var specificity := 0
		if device_id != -1:
			specificity += 1
		if channel != -1:
			specificity += 1

		if specificity > best_specificity:
			best_index = index
			best_specificity = specificity

	return best_index


func _identity_map() -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(128)

	for pitch in range(128):
		result[pitch] = pitch

	return result


func _normalize_map(value: Variant) -> PackedInt32Array:
	var result := _identity_map()

	if value is Array:
		for pitch in range(mini(value.size(), 128)):
			var target := int(value[pitch])
			if target >= -1 and target <= 127:
				result[pitch] = target
	elif value is PackedInt32Array:
		for pitch in range(mini(value.size(), 128)):
			var target: int = value[pitch]
			if target >= -1 and target <= 127:
				result[pitch] = target

	return result


func _make_note_key(event: InputEventMIDI) -> String:
	return "%d:%d:%d" % [event.device, event.channel, event.pitch]


func _copy_event_with_pitch(
	source_event: InputEventMIDI,
	target_pitch: int
) -> InputEventMIDI:
	var copied_event := source_event.duplicate() as InputEventMIDI
	copied_event.pitch = target_pitch
	return copied_event
