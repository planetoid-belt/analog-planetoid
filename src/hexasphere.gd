@tool
# hihi an icon <3
@icon("res://src/hexasphere.svg")

## HexaSphere is a box mesh that can be subdivided and smoothed to create a sphere-like mesh. It extends the regular Box Mesh.
class_name HexaSphere
extends ArrayMesh

const REBUILD_DEBOUNCE_SECONDS := 0.3

## Number of times the box will be smoothed.
@export_range(0, 32, 1, "prefer_slider") var subdivisions = 0:
	set(value):
		subdivisions = clampi(value, 0, 32)
		_queue_mesh_rebuild()

## How much the mesh will be smoothed by.
@export_range(0.0, 1.0, 0.01) var smoothness = 0.0:
	set(value):
		smoothness = clampf(value, 0.0, 1.0)
		_queue_mesh_rebuild()


## Uniformally changes the box's size in meter units.
@export var uniform_size: float = 1.0:
	set(value):
		uniform_size = maxf(value, 0.0)
		_queue_mesh_rebuild()


# surface tool! we will use this to modify the mesh.
var st := SurfaceTool.new()
var _rebuild_generation := 0

func _init() -> void:
	_init_mesh()


func _queue_mesh_rebuild() -> void:
	_rebuild_generation += 1
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		_init_mesh()
		return

	scene_tree.create_timer(REBUILD_DEBOUNCE_SECONDS).timeout.connect(
		_rebuild_if_current.bind(_rebuild_generation),
		CONNECT_ONE_SHOT
	)


func _rebuild_if_current(generation: int) -> void:
	if generation == _rebuild_generation:
		_init_mesh()


func _set_subdivision(value: int, mesh: BoxMesh) -> void:
	mesh.subdivide_width = value
	mesh.subdivide_height = value
	mesh.subdivide_depth = value


func _init_mesh() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * uniform_size
	_set_subdivision(subdivisions, box)

	st = SurfaceTool.new()
	st.create_from(box, 0)
	var arrays := st.commit_to_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		clear_surfaces()
		return

	var average_radius := 0.0
	for vertex in vertices:
		average_radius += vertex.length()
	average_radius /= vertices.size()

	for index in range(vertices.size()):
		var vertex := vertices[index]
		if vertex.length_squared() > 0.0:
			var projected_vertex := vertex.normalized() * average_radius
			vertices[index] = vertex.lerp(projected_vertex, smoothness)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	st.clear()
	st.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
	st.generate_normals()
	st.generate_tangents()
	clear_surfaces()
	st.commit(self)
