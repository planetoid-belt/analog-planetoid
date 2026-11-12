extends Node

const CONFIG_VERSION := 1
const LOCAL_CONFIG_PATH := "user://midi_controller_mappings.json"

const NOTE_NAMES: Array[String] = [
	"C", "C#", "D", "D#", "E", "F",
	"F#", "G", "G#", "A", "A#", "B",
]

@onready var midi_player: MidiPlayer = $MidiPlayer

var default_pitch_targets: PackedInt32Array
var controller_profiles: Array[Dictionary] = []

# -1 selects the default map; otherwise this is an index in controller_profiles.
var _selected_profile_index := -1

var _capture_active := false
var _capture_new_profile := false
var _capture_target_pitch := -1

# Captured key presses are consumed so their corresponding releases do not
# trigger a sound after learning has finished.
var _captured_note_releases: Dictionary = {}

# Store the output pitch selected at note-on so note-off always releases it.
var _active_note_targets: Dictionary = {}

var _profile_picker: OptionButton
var _mapping_rows_container: VBoxContainer
var _mapping_source_labels: Array[Label] = []
var _status_label: Label
var _import_dialog: FileDialog
var _export_dialog: FileDialog


func _ready() -> void:
	default_pitch_targets = _identity_map()

	OS.open_midi_inputs()
	_load_local_config()
	_build_runtime_ui()
	_refresh_profile_picker()
	_refresh_mapping_list()

	print("Connected MIDI inputs: ", OS.get_connected_midi_inputs())

	if midi_player.bank == null:
		push_error("MIDI player has no loaded SoundFont.")
	else:
		print("Loaded SoundFont presets: ", midi_player.bank.presets.size())


func _exit_tree() -> void:
	OS.close_midi_inputs()


func _build_runtime_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(560, 680)
	canvas.add_child(panel)

	var layout := VBoxContainer.new()
	panel.add_child(layout)

	var title := Label.new()
	title.text = "MIDI Controller Mapping"
	layout.add_child(title)

	var connected_label := Label.new()
	connected_label.text = "Connected MIDI inputs: %s" % str(
		OS.get_connected_midi_inputs()
	)
	connected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(connected_label)

	var profile_row := HBoxContainer.new()
	layout.add_child(profile_row)

	var profile_label := Label.new()
	profile_label.text = "Map"
	profile_row.add_child(profile_label)

	_profile_picker = OptionButton.new()
	_profile_picker.item_selected.connect(_on_profile_selected)
	profile_row.add_child(_profile_picker)

	var new_profile_button := Button.new()
	new_profile_button.text = "Add controller + learn key"
	new_profile_button.pressed.connect(_start_new_profile_capture)
	profile_row.add_child(new_profile_button)

	var remove_profile_button := Button.new()
	remove_profile_button.text = "Remove profile"
	remove_profile_button.pressed.connect(_remove_selected_profile)
	profile_row.add_child(remove_profile_button)

	var file_row := HBoxContainer.new()
	layout.add_child(file_row)

	var import_button := Button.new()
	import_button.text = "Import JSON"
	import_button.pressed.connect(_open_import_dialog)
	file_row.add_child(import_button)

	var export_button := Button.new()
	export_button.text = "Export JSON"
	export_button.pressed.connect(_open_export_dialog)
	file_row.add_child(export_button)

	_status_label = Label.new()
	_status_label.text = "Select a destination tone, then learn a MIDI key."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status_label)

	var instructions := Label.new()
	instructions.text = (
		"Each row is a soundfont note. Press its button, "
		+ "then press the controller key to assign."
	)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(instructions)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(510, 390)
	layout.add_child(scroll)

	_mapping_rows_container = VBoxContainer.new()
	_mapping_rows_container.custom_minimum_size.x = 490
	scroll.add_child(_mapping_rows_container)

	_build_mapping_rows()

	_import_dialog = _create_file_dialog(
		FileDialog.FILE_MODE_OPEN_FILE,
		_import_mapping_file
	)
	_export_dialog = _create_file_dialog(
		FileDialog.FILE_MODE_SAVE_FILE,
		_export_mapping_file
	)

func _build_mapping_rows() -> void:
	for target_pitch in range(128):
		var row := HBoxContainer.new()
		_mapping_rows_container.add_child(row)

		var note_label := Label.new()
		note_label.text = "Note %s" % _note_name(target_pitch)
		note_label.custom_minimum_size.x = 90
		row.add_child(note_label)

		var source_label := Label.new()
		source_label.text = "MIDI map: --"
		source_label.custom_minimum_size.x = 190
		row.add_child(source_label)
		_mapping_source_labels.append(source_label)

		var map_button := Button.new()
		map_button.text = "Map new pitch"
		map_button.pressed.connect(_start_key_capture.bind(target_pitch))
		row.add_child(map_button)

func _create_file_dialog(
	mode: FileDialog.FileMode,
	callback: Callable
) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json ; MIDI mapping configuration")
	dialog.file_selected.connect(callback)
	add_child(dialog)
	return dialog


func _start_new_profile_capture() -> void:
	_capture_new_profile = not _capture_new_profile
	_capture_active = false

	if _capture_new_profile:
		_status_label.text = (
			"New controller mode: choose a note row, click its button, "
			+ "then press a MIDI key."
		)
	else:
		_status_label.text = "New controller mode cancelled."


func _start_key_capture(target_pitch: int) -> void:
	_capture_target_pitch = target_pitch
	_capture_active = true

	var target_name := _note_name(target_pitch)
	if _capture_new_profile:
		_status_label.text = (
			"Listening for a controller key to map to %s. "
			+ "A controller profile will be created."
		) % target_name
	else:
		_status_label.text = (
			"Listening for a controller key to map to %s."
		) % target_name


func _input(event: InputEvent) -> void:
	if not event is InputEventMIDI:
		return

	var midi_event := event as InputEventMIDI

	# Ignore MIDI clock and active-sensing messages.
	if midi_event.message == 248 or midi_event.message == 254:
		return

	var note_key := _note_key(midi_event)
	var is_note_off := (
		midi_event.message == MIDI_MESSAGE_NOTE_OFF
		or (
			midi_event.message == MIDI_MESSAGE_NOTE_ON
			and midi_event.velocity == 0
		)
	)

	if is_note_off:
		if _captured_note_releases.erase(note_key):
			return

		if not _active_note_targets.has(note_key):
			return

		var target_pitch: int = _active_note_targets[note_key]
		_active_note_targets.erase(note_key)

		var note_off := _copy_event_with_pitch(midi_event, target_pitch)
		if midi_event.message == MIDI_MESSAGE_NOTE_ON:
			note_off.message = MIDI_MESSAGE_NOTE_OFF

		midi_player.receive_raw_midi_message(note_off)
		return

	if midi_event.message == MIDI_MESSAGE_NOTE_ON:
		if _capture_active:
			_capture_key(midi_event, note_key)
			return

		var target_pitch := _target_for_event(midi_event)
		if target_pitch < 0:
			return

		_active_note_targets[note_key] = target_pitch
		midi_player.receive_raw_midi_message(
			_copy_event_with_pitch(midi_event, target_pitch)
		)
		return

	# Sustain, pitch bend, modulation, and other MIDI messages pass through.
	midi_player.receive_raw_midi_message(midi_event)


func _capture_key(event: InputEventMIDI, note_key: String) -> void:
	if event.velocity <= 0:
		return

	if _capture_new_profile:
		_selected_profile_index = _find_or_add_profile(
			event.device,
			event.channel
		)
		_refresh_profile_picker()
	else:
		# Avoid learning a key from a different device/channel into a
		# specifically selected controller profile.
		if not _selected_profile_matches(event):
			_status_label.text = "That key came from a different controller profile."
			return

	var source_pitch := event.pitch
	var target_pitch := _capture_target_pitch
	_set_mapping(source_pitch, target_pitch)

	_captured_note_releases[note_key] = true
	_capture_active = false
	_capture_new_profile = false
	_capture_target_pitch = -1

	_save_local_config()
	_refresh_mapping_list()

	_status_label.text = "Mapped %s (%d) → %s (%d)." % [
		_note_name(source_pitch),
		source_pitch,
		_note_name(target_pitch),
		target_pitch,
	]


func _selected_profile_matches(event: InputEventMIDI) -> bool:
	if _selected_profile_index < 0:
		return true

	if _selected_profile_index >= controller_profiles.size():
		return false

	var profile := controller_profiles[_selected_profile_index]
	var device_id := int(profile.get("device_id", -1))
	var channel := int(profile.get("channel", -1))

	return (
		(device_id == -1 or device_id == event.device)
		and (channel == -1 or channel == event.channel)
	)


func _find_or_add_profile(device_id: int, channel: int) -> int:
	for index in range(controller_profiles.size()):
		var profile := controller_profiles[index]
		if (
			int(profile.get("device_id", -1)) == device_id
			and int(profile.get("channel", -1)) == channel
		):
			return index

	var profile := {
		"name": "Device %d, Channel %d" % [device_id, channel + 1],
		"device_id": device_id,
		"channel": channel,
		"pitch_targets": _identity_map(),
	}
	controller_profiles.append(profile)
	return controller_profiles.size() - 1


func _set_mapping(source_pitch: int, target_pitch: int) -> void:
	var targets := _current_map().duplicate()

	# The row may already have another input key assigned.
	var old_source_for_target := _source_for_target(targets, target_pitch)

	# This input key may currently belong to another output note.
	var old_target_for_source: int = targets[source_pitch]

	# Assign the newly pressed input key to the selected output note.
	targets[source_pitch] = target_pitch

	# Swap the previous input key for this row onto the destination that
	# the newly pressed input key used to play.
	if old_source_for_target >= 0 and old_source_for_target != source_pitch:
		targets[old_source_for_target] = old_target_for_source

	if _selected_profile_index < 0:
		default_pitch_targets = targets
	else:
		var profile := controller_profiles[_selected_profile_index]
		profile["pitch_targets"] = targets
		controller_profiles[_selected_profile_index] = profile


func _source_for_target(
	targets: PackedInt32Array,
	target_pitch: int
) -> int:
	for source_pitch in range(128):
		if targets[source_pitch] == target_pitch:
			return source_pitch

	return -1


func _refresh_mapping_list() -> void:
	if _mapping_source_labels.size() != 128:
		return

	var targets := _current_map()

	for target_pitch in range(128):
		var source_pitch := _source_for_target(targets, target_pitch)

		if source_pitch < 0:
			_mapping_source_labels[target_pitch].text = "MIDI map: --"
		else:
			_mapping_source_labels[target_pitch].text = (
				"MIDI map: %d" % source_pitch
			)


func _current_map() -> PackedInt32Array:
	if (
		_selected_profile_index >= 0
		and _selected_profile_index < controller_profiles.size()
	):
		var profile := controller_profiles[_selected_profile_index]
		return _normalize_map(profile.get("pitch_targets", []))

	return _normalize_map(default_pitch_targets)


func _target_for_event(event: InputEventMIDI) -> int:
	var map := default_pitch_targets
	var profile_index := _find_profile_for_event(event)

	if profile_index >= 0:
		map = _normalize_map(
			controller_profiles[profile_index].get("pitch_targets", [])
		)
	else:
		map = _normalize_map(default_pitch_targets)

	return map[event.pitch]


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


func _on_profile_selected(item_index: int) -> void:
	_selected_profile_index = item_index - 1
	_refresh_mapping_list()


func _refresh_profile_picker() -> void:
	if _profile_picker == null:
		return

	_profile_picker.clear()
	_profile_picker.add_item("Default map")

	for profile in controller_profiles:
		_profile_picker.add_item(str(profile.get("name", "Controller")))

	var selected_item := clampi(
		_selected_profile_index + 1,
		0,
		_profile_picker.item_count - 1
	)
	_profile_picker.select(selected_item)


func _remove_selected_profile() -> void:
	if (
		_selected_profile_index < 0
		or _selected_profile_index >= controller_profiles.size()
	):
		_status_label.text = "Select a controller profile to remove."
		return

	controller_profiles.remove_at(_selected_profile_index)
	_selected_profile_index = -1
	_refresh_profile_picker()
	_refresh_mapping_list()
	_save_local_config()
	_status_label.text = "Controller profile removed."


func _open_import_dialog() -> void:
	_import_dialog.popup_centered(Vector2i(900, 600))


func _open_export_dialog() -> void:
	_export_dialog.current_file = "midi_controller_mappings.json"
	_export_dialog.popup_centered(Vector2i(900, 600))


func _import_mapping_file(path: String) -> void:
	if not _load_mapping_file(path):
		_status_label.text = "Could not import that MIDI mapping JSON."
		return

	_selected_profile_index = -1
	_refresh_profile_picker()
	_refresh_mapping_list()
	_save_local_config()
	_status_label.text = "Imported mapping and saved it for this user."


func _export_mapping_file(path: String) -> void:
	if not path.to_lower().ends_with(".json"):
		path += ".json"

	if _save_mapping_file(path):
		_status_label.text = "Exported mapping to %s." % path
	else:
		_status_label.text = "Could not export mapping JSON."


func _load_local_config() -> void:
	if FileAccess.file_exists(LOCAL_CONFIG_PATH):
		_load_mapping_file(LOCAL_CONFIG_PATH)


func _load_mapping_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false

	if int(parsed.get("version", -1)) != CONFIG_VERSION:
		return false

	default_pitch_targets = _normalize_map(
		parsed.get("default_pitch_targets", [])
	)

	controller_profiles.clear()
	var profiles: Variant = parsed.get("profiles", [])
	if profiles is Array:
		for value in profiles:
			if not value is Dictionary:
				continue

			var channel := int(value.get("channel", -1))
			if channel < -1 or channel > 15:
				continue

			controller_profiles.append({
				"name": str(value.get("name", "MIDI Controller")),
				"device_id": int(value.get("device_id", -1)),
				"channel": channel,
				"pitch_targets": _normalize_map(
					value.get("pitch_targets", [])
				),
			})

	return true


func _save_local_config() -> void:
	_save_mapping_file(LOCAL_CONFIG_PATH)


func _save_mapping_file(path: String) -> bool:
	var profiles_for_json: Array[Dictionary] = []

	for profile in controller_profiles:
		profiles_for_json.append({
			"name": str(profile.get("name", "MIDI Controller")),
			"device_id": int(profile.get("device_id", -1)),
			"channel": int(profile.get("channel", -1)),
			"pitch_targets": _map_as_array(
				_normalize_map(profile.get("pitch_targets", []))
			),
		})

	var document := {
		"version": CONFIG_VERSION,
		"default_pitch_targets": _map_as_array(default_pitch_targets),
		"profiles": profiles_for_json,
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write MIDI mapping file: %s" % path)
		return false

	file.store_string(JSON.stringify(document, "\t"))
	return true


func _identity_map() -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(128)

	for pitch in range(128):
		result[pitch] = pitch

	return result


func _normalize_map(value: Variant) -> PackedInt32Array:
	var result := _identity_map()

	if value is PackedInt32Array:
		for pitch in range(mini(value.size(), 128)):
			if value[pitch] >= -1 and value[pitch] <= 127:
				result[pitch] = value[pitch]
	elif value is Array:
		for pitch in range(mini(value.size(), 128)):
			var target := int(value[pitch])
			if target >= -1 and target <= 127:
				result[pitch] = target

	return result


func _map_as_array(value: PackedInt32Array) -> Array[int]:
	var result: Array[int] = []
	for pitch in range(128):
		result.append(value[pitch])
	return result


func _note_name(pitch: int) -> String:
	if pitch < 0 or pitch > 127:
		return "Disabled"

	var octave := floori(float(pitch) / 12.0) - 1
	return "%s%d" % [NOTE_NAMES[pitch % 12], octave]


func _note_key(event: InputEventMIDI) -> String:
	return "%d:%d:%d" % [event.device, event.channel, event.pitch]


func _copy_event_with_pitch(
	source_event: InputEventMIDI,
	target_pitch: int
) -> InputEventMIDI:
	var copied_event := source_event.duplicate() as InputEventMIDI
	copied_event.pitch = target_pitch
	return copied_event
