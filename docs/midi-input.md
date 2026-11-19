# MIDI input

This folder contains three pieces:

- `MidiInputHub` opens Godot's MIDI inputs and broadcasts incoming MIDI events.
- `MidiController` filters events for a device, remaps notes, and optionally
  sends them to its `MidiPlayer` child for SoundFont playback.
- `MidiMapper` is a UI scene for learning, editing, importing, and exporting a
  controller's note mapping.

## Scene setup

Add one `MidiInputHub` to the scene tree shared by the controllers that should
receive MIDI. The hub opens MIDI input when it enters the tree and closes it
when it leaves. MIDI input is process-wide, so do not make a separate hub for
every controller.

For example:

```text
GameScene
├── MidiInputHub              # instance midi_input_hub.tscn once
├── PianoController           # instance midi_controller.tscn
└── SynthController           # another controller instance
```

For each controller, set `input_hub_path` to the shared hub. If the controller
and hub are siblings, the value is:

```text
../MidiInputHub
```

Set each controller's `device_id` to the MIDI device it should handle. Use
`-1` to accept events from all devices. If more than one controller uses `-1`,
each one will receive and process the same events.

The mapper scene already contains a hub and a controller instance. Its
controller also needs `input_hub_path` set to `../MidiInputHub`. Set that
controller instance's `play_sound` property to `false` if you want the mapper
to edit mappings without playing the keys as they are learned.

## MidiInputHub

The hub exposes one signal:

| Signal | Payload | Meaning |
| --- | --- | --- |
| `midi_event(event)` | `InputEventMIDI` | Every MIDI event received by Godot, before controller filtering or note remapping. |

The hub also prints the connected input names when it starts. The event's
`device` property is the runtime device identifier used by `MidiController`'s
`device_id` filter.

Controllers subscribe to the hub signal in `_ready()` and disconnect when they
leave the tree. Other scripts can connect to the hub directly when they need
unfiltered MIDI input.

## MidiController

The controller is a `Node` with an optional `MidiPlayer` child. The packed
scene `midi_controller.tscn` includes a player with the project's SoundFont.

### Inspector properties

| Property | Default | Use |
| --- | --- | --- |
| `device_id` | `-1` | Runtime MIDI device ID to accept; `-1` accepts any device. |
| `mapping_path` | empty | Optional JSON mapping path. Empty uses the identity mapping. |
| `play_sound` | `true` | Send mapped events to the child `MidiPlayer`. |
| `input_hub_path` | empty | NodePath to the shared `MidiInputHub`. This must be assigned. |

Set `mapping_path` to a `res://` or `user://` JSON file. If the path is empty,
the controller starts with the identity mapping: MIDI pitch 0 maps to output
pitch 0, pitch 1 to 1, and so on. A mapping value of `-1` disables that input
pitch.

### Signals

| Signal | Payload | Meaning |
| --- | --- | --- |
| `raw_midi_event(event)` | `InputEventMIDI` | Event from the selected device, before note mapping. Emitted during capture too. |
| `mapped_midi_event(event)` | `InputEventMIDI` | Event forwarded after note mapping. Non-note events pass through unchanged. |
| `capture_note(event)` | `InputEventMIDI` | Positive-velocity note-on received while capture mode is active. |
| `mapping_changed(targets)` | `PackedInt32Array` | Emitted after a mapping is set, reset, or loaded successfully. The array has 128 entries. |

While capture is active, the controller emits raw and capture signals but does
not forward events for playback or through `mapped_midi_event`. The caller
that began capture should call `end_capture()` when it is finished. The mapper
does this after learning a note.

### Methods

| Method | Result | Use |
| --- | --- | --- |
| `get_pitch_targets()` | `PackedInt32Array` | Get a copy of the 128-entry map. |
| `set_pitch_targets(targets)` | `bool` | Replace the map after validating its size and values. |
| `set_pitch_mapping(source_pitch, target_pitch)` | `bool` | Set one mapping; use `-1` to disable a source pitch. |
| `reset_mapping()` | — | Restore the identity map and emit `mapping_changed`. |
| `begin_capture()` / `end_capture()` | — | Suppress forwarded events while learning a note. |
| `load_mapping(path)` | `bool` | Load a valid mapping JSON file. Failed loads leave the current map unchanged. |
| `save_mapping(path = "")` | `bool` | Save JSON to `path`, or to `mapping_path` if the argument is empty. |

The current JSON format is:

```json
{
  "version": 1,
  "pitch_targets": [0, 1, 2, 3]
}
```

`pitch_targets` must contain exactly 128 integer values from `-1` through
`127`. The short array above is illustrative; a usable file needs all 128
entries. `save_mapping()` writes the complete array.

For note-on events, the controller emits and plays a copy of the event with
the mapped pitch. It records that output pitch and uses it for the matching
note-off, even if the map changes while the note is held. A note-on with
velocity zero is treated as note-off. Other MIDI messages, such as control
changes, sustain, and pitch bend, are copied and forwarded unchanged.

## MidiMapper

The mapper scene edits the `MidiController` child instance rather than owning
its own MIDI playback or mapping data. It builds rows for all 128 output
pitches. To assign an input key:

1. Click **Map new pitch** beside the desired output note.
2. Press a MIDI key on a device accepted by the controller's `device_id`.
3. The mapper assigns that source pitch to the selected output pitch and
   updates the rows through `mapping_changed`.

The mapper swaps the old assignment when possible, keeping its learned map
one-to-one. **Reset** restores one output row to its same-numbered input pitch;
**Reset all rows** restores the full identity map. Import and export use the
controller's `load_mapping()` and `save_mapping()` methods.

## Reading MIDI in another script

Connect to `mapped_midi_event` when a script should use remapped note pitches
and the controller's device filtering. Connect to `raw_midi_event` when it
needs the original pitch or wants MIDI data during mapper capture. Connect to
`MidiInputHub.midi_event` only when the script intentionally needs events from
all devices before controller filtering.

For example, a script with a `MidiController` node at `../MidiController` can
read a MIDI continuous controller (CC) and drive a shader uniform:

```python
extends Node

@export var midi_controller_path: NodePath = ^"../MidiController"
@export var mesh_path: NodePath

var _controller: MidiController
var _shader_material: ShaderMaterial


func _ready() -> void:
	_controller = get_node(midi_controller_path) as MidiController
	var mesh := get_node(mesh_path) as MeshInstance3D

	# Duplicate the active material so this script changes only this mesh.
	var active_material := mesh.get_active_material(0) as ShaderMaterial
	if active_material == null:
		push_error("The mesh surface needs a ShaderMaterial.")
		return

	_shader_material = active_material.duplicate() as ShaderMaterial
	mesh.set_surface_override_material(0, _shader_material)
	_controller.mapped_midi_event.connect(_on_midi_event)


func _on_midi_event(event: InputEventMIDI) -> void:
	if event.message != MIDI_MESSAGE_CONTROL_CHANGE:
		return

	# MIDI CC values normally range from 0 to 127.
	var normalized := float(event.controller_value) / 127.0

	match event.controller_number:
		1:
			_shader_material.set_shader_parameter("wave_amount", normalized)
		74:
			_shader_material.set_shader_parameter("cutoff", normalized)
```

Create matching shader uniforms, for example:

```glsl
uniform float wave_amount : hint_range(0.0, 1.0) = 0.0;
uniform float cutoff : hint_range(0.0, 1.0) = 0.5;
```

The controller currently remaps note pitches only. CC number and value are
forwarded unchanged, so the shader example reads `controller_number` and
`controller_value` directly. Use `raw_midi_event` instead if the script
should still receive the controller data while the mapper is capturing a
note.

To use note velocity instead, connect to `mapped_midi_event`, check for
`MIDI_MESSAGE_NOTE_ON`, and normalize `event.velocity` by `127.0`. In that
signal, `event.pitch` is the mapped output pitch.
