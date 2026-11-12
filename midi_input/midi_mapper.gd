extends Node

const NOTE_NAMES: Array[String] = [
	"C", "C#", "D", "D#", "E", "F",
	"F#", "G", "G#", "A", "A#", "B",
]

@onready var controller: MidiController = $MidiController
@onready var _mapping_rows_container: VBoxContainer = (
	$UI/Mapper/Layout/MappingScroll/MappingRows
)
@onready var _connected_label: Label = $UI/Controller/Layout/ConnectedLabel
@onready var _status_label: Label = $UI/Controller/Layout/StatusLabel
@onready var _key_status: Label = $UI/Controller/Layout/KeyStatusLabel
@onready var _import_dialog: FileDialog = $ImportDialog
@onready var _export_dialog: FileDialog = $ExportDialog

var _mapping_source_labels: Array[Label] = []
var _capture_target_pitch := -1


func _ready() -> void:
	controller.raw_midi_event.connect(_on_raw_midi_event)
	controller.capture_note.connect(_on_capture_note)
	controller.mapping_changed.connect(_on_mapping_changed)

	_connected_label.text = "Connected MIDI inputs: %s" % str(
		OS.get_connected_midi_inputs()
	)

	_build_mapping_rows()
	_refresh_mapping_list()


# Mapping UI

func _build_mapping_rows() -> void:
	_mapping_source_labels.clear()

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

		var reset_button := Button.new()
		reset_button.text = "Reset"
		reset_button.pressed.connect(_reset_row_mapping.bind(target_pitch))
		row.add_child(reset_button)


func _refresh_mapping_list() -> void:
	if _mapping_source_labels.size() != 128:
		return

	var targets := controller.get_pitch_targets()

	for target_pitch in range(128):
		var source_pitch := _source_for_target(targets, target_pitch)

		if source_pitch < 0:
			_mapping_source_labels[target_pitch].text = "MIDI map: --"
		else:
			_mapping_source_labels[target_pitch].text = (
				"MIDI map: %s (%d)"
				% [_note_name(source_pitch), source_pitch]
			)


func _source_for_target(
	targets: PackedInt32Array,
	target_pitch: int
) -> int:
	for source_pitch in range(128):
		if targets[source_pitch] == target_pitch:
			return source_pitch

	return -1


# Key capture

func _start_key_capture(target_pitch: int) -> void:
	_capture_target_pitch = target_pitch
	controller.begin_capture()
	_status_label.text = (
		"Press a MIDI key to map it to %s."
		% _note_name(target_pitch)
	)


func _on_capture_note(event: InputEventMIDI) -> void:
	if _capture_target_pitch < 0:
		return

	var source_pitch := event.pitch
	var target_pitch := _capture_target_pitch
	_set_mapping_with_swap(source_pitch, target_pitch)

	controller.end_capture()
	_capture_target_pitch = -1

	_status_label.text = "Mapped %s (%d) to %s (%d)." % [
		_note_name(source_pitch),
		source_pitch,
		_note_name(target_pitch),
		target_pitch,
	]


func _cancel_capture() -> void:
	controller.end_capture()
	_capture_target_pitch = -1


# Mapping edits

func _set_mapping_with_swap(source_pitch: int, target_pitch: int) -> void:
	var targets := controller.get_pitch_targets()
	var previous_source := _source_for_target(targets, target_pitch)
	var previous_target := targets[source_pitch]

	targets[source_pitch] = target_pitch

	if previous_source >= 0 and previous_source != source_pitch:
		targets[previous_source] = previous_target

	controller.set_pitch_targets(targets)


func _reset_row_mapping(target_pitch: int) -> void:
	_set_mapping_with_swap(target_pitch, target_pitch)
	_cancel_capture()
	_status_label.text = (
		"Reset %s to its default pitch."
		% _note_name(target_pitch)
	)


# Retained for the existing ResetMapButton connection in midi_mapper.tscn.
func _on_reset_map_button_pressed() -> void:
	controller.reset_mapping()
	_cancel_capture()
	_status_label.text = "Reset the mapping to the default pitches."


func _on_mapping_changed(_targets: PackedInt32Array) -> void:
	_refresh_mapping_list()


# MIDI status display

func _on_raw_midi_event(event: InputEventMIDI) -> void:
	_key_status.text = "Received: \n %s" % str(event).split(":", true, 1)[1]


# Import and export

func _open_import_dialog() -> void:
	_import_dialog.popup_centered(Vector2i(900, 600))


func _open_export_dialog() -> void:
	_export_dialog.current_file = "midi_mapping.json"
	_export_dialog.popup_centered(Vector2i(900, 600))


func _import_mapping_file(path: String) -> void:
	if not controller.load_mapping(path):
		_status_label.text = "Could not import that MIDI mapping JSON."
		return

	_cancel_capture()
	_status_label.text = "Imported mapping from %s." % path


func _export_mapping_file(path: String) -> void:
	var destination := path
	if not destination.to_lower().ends_with(".json"):
		destination += ".json"

	if controller.save_mapping(destination):
		_status_label.text = "Exported mapping to %s." % destination
	else:
		_status_label.text = "Could not export mapping JSON."


# Helpers

func _note_name(pitch: int) -> String:
	if pitch < 0 or pitch > 127:
		return "Disabled"

	var octave := floori(float(pitch) / 12.0) - 1
	return "%s%d" % [NOTE_NAMES[pitch % 12], octave]
