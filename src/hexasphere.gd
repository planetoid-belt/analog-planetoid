@tool
# hihi an icon <3
@icon("res://src/hexasphere.svg")

## HexaSphere is a box mesh that can be subdivided and smoothed to create a sphere-like mesh. It extends the regular Box Mesh.
class_name HexaSphere
extends ArrayMesh

## Number of times the box will be smoothed.
@export_range(0, 32, 1, "prefer_slider") var subdivisions = 0:
	set(value):
		subdivisions = clampi(value, 0, 32)
		_init_mesh()

## How much the mesh will be smoothed by.
@export_range(0.0, 1.0, 0.01) var smoothness = 0.0:
	set(value):
		smoothness = clampf(value, 0.0, 1.0)
		_init_mesh()


## Uniformally changes the box's size in meter units.
@export var uniform_size: float = 1.0:
	set(value):
		uniform_size = maxf(value, 0.0)
		_init_mesh()


# surface tool! we will use this to modify the mesh.
var st := SurfaceTool.new()

func _init() -> void:
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
