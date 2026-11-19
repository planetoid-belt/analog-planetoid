extends MeshInstance3D

@export var midi_controller_path: NodePath = ^"../MidiController"

var _controller: MidiController
var _material: BaseMaterial3D


func _ready() -> void:
	_controller = get_node_or_null(midi_controller_path) as MidiController
	if _controller == null:
		push_error("MidiController was not found at midi_controller_path.")
		return

	if mesh == null or mesh.get_surface_count() == 0:
		push_error("MeshInstance3D has no mesh surface.")
		return

	# Read the material assigned directly to the Mesh resource.
	_material = mesh.surface_get_material(0) as BaseMaterial3D
	if _material == null:
		push_error("Mesh surface 0 has no BaseMaterial3D assigned.")
		return

	_controller.mapped_midi_event.connect(_on_midi_event)


const LOW_PITCH := 36
const HIGH_PITCH := 84


func _on_midi_event(event: InputEventMIDI) -> void:
	if event.message != MIDI_MESSAGE_NOTE_ON or event.velocity == 0:
		return

	var amount := clampf(
		float(event.pitch - LOW_PITCH) / float(HIGH_PITCH - LOW_PITCH),
		0.0,
		1.0
	)

	_material.albedo_color = Color.BLUE.lerp(Color.RED, amount)
