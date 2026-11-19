@tool
extends Node3D

enum RotationMode { ORBIT_ORIGIN, PING_PONG }

## Angular speed in radians per second.
@export var rotation_speed: float = 0.1
@export var rotation_mode: RotationMode = RotationMode.ORBIT_ORIGIN
## Maximum orbital angle on either side of the starting position in ping-pong mode.
@export_range(0.0, 180.0, 0.1) var rotation_margin_degrees: float = 15.0
## World-space axis to orbit and rotate around.
@export var rotation_axis: Vector3 = Vector3.UP

var _initial_global_basis: Basis
var _initial_global_position: Vector3
var _elapsed_time := 0.0

func _ready() -> void:
	_initial_global_basis = global_basis
	_initial_global_position = global_position

func _process(delta: float) -> void:
	if rotation_axis.is_zero_approx():
		return

	if rotation_mode == RotationMode.PING_PONG:
		var margin := deg_to_rad(rotation_margin_degrees)
		if is_zero_approx(margin):
			global_transform = Transform3D(_initial_global_basis, _initial_global_position)
			return

		_elapsed_time += delta
		var angle := pingpong(
			_elapsed_time * absf(rotation_speed) + margin,
			margin * 2.0
		) - margin
		if rotation_speed < 0.0:
			angle = -angle

		var orbit_rotation := Basis(rotation_axis.normalized(), angle)
		global_transform = Transform3D(
			orbit_rotation * _initial_global_basis,
			orbit_rotation * _initial_global_position
		)
		return

	var orbit_rotation := Basis(rotation_axis.normalized(), rotation_speed * delta)
	global_transform = Transform3D(
		orbit_rotation * global_basis,
		orbit_rotation * global_position
	)
