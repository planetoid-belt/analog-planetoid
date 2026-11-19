@tool
# hihi an icon <3
@icon("res://src/quadsphere.svg")

## QuadSphere is a box mesh that can be subdivided and smoothed to create a sphere-like mesh. It extends the regular Box Mesh.
class_name QuadSphere

# The ArrayMesh can hold multiple *surfaces* in an array.
# A surface holds mesh data, such as vertices and such.
extends ArrayMesh

const REBUILD_DEBOUNCE_SECONDS := 0.3
const CHUNK_NAMES := ["chunk_right", "chunk_left", "chunk_top", "chunk_bottom", "chunk_back", "chunk_front"]

#region exports
@export_category("Mesh Settings")
## Number of times the box will be smoothed.
@export_range(0, 32, 1) var subdivisions = 4:
	set(value):
		subdivisions = clampi(value, 0, 32)
		_queue_mesh_rebuild()
## How much the mesh will be smoothed by.
@export_range(0.0, 1.0, 0.01) var smoothness = 1.0:
	set(value):
		smoothness = clampf(value, 0.0, 1.0)
		_queue_mesh_rebuild()
## Uniformally changes the box's size in meter units.
@export var uniform_size: float = 1.0:
	set(value):
		uniform_size = maxf(value, 0.0)
		_queue_mesh_rebuild()
## split up the sphere into six distinct surfaces
@export var surface_splitting: bool = true:
	set(value):
		surface_splitting = value
		_queue_mesh_rebuild()

@export_group("QuadSphere Debug")
## Shows vertices on the mesh
@export var debug_vertices: bool = false:
	set(value):
		debug_vertices = value
		_queue_mesh_rebuild()
## Shows normals
@export var debug_normals: bool = false:
	set(value):
		debug_normals = value
		_queue_mesh_rebuild()
## length of normal vectors drawn by debugging
@export_range(0.01, 6.0, 0.01) var debug_line_length: float = 0.5:
	set(value):
		debug_line_length = maxf(value, 0.005)
		_queue_mesh_rebuild()
#endregion

var _rebuild_generation := 0
var _surface_materials: Dictionary = {}


func _ready() -> void:
	_init_mesh()


## this bad boy does aaaaaall the work
func _init_mesh() -> void:
	_cache_surface_materials()

	## start from a box!
	var box := BoxMesh.new()
	box.size = Vector3.ONE * uniform_size
	_set_subdivision(subdivisions, box)

	# Fetch base arrays directly from the primitive (much faster than SurfaceTool extraction)
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		self.clear_surfaces()
		return

	# used for smoothing.
	var average_radius := 0.0
	for vertex in vertices:
		average_radius += vertex.length()
	average_radius /= vertices.size()

	# We duplicate the original box normals to accurately identify cube faces later
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var orig_normals := normals.duplicate()

	for index in range(vertices.size()):
		var vertex := vertices[index]
		if vertex.length_squared() > 0.0:
			var sphere_dir := vertex.normalized()
			var projected_vertex := sphere_dir * average_radius
			vertices[index] = vertex.lerp(projected_vertex, smoothness)
			# Blend the original flat normal into a seamless sphere normal
			normals[index] = orig_normals[index].lerp(sphere_dir, smoothness).normalized()

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]

	# resets ArrayMesh to an empty state
	self.clear_surfaces()

	if surface_splitting:
		# Create 6 SurfaceTools, one for each cube face
		var chunk_tools: Array[SurfaceTool] = []
		for c in range(6):
			var chunk_st := SurfaceTool.new()
			chunk_st.begin(Mesh.PRIMITIVE_TRIANGLES)
			chunk_tools.append(chunk_st)

		# Route every triangle to its matching chunk SurfaceTool
		for i in range(0, indices.size(), 3):
			var i0 := indices[i]
			var i1 := indices[i + 1]
			var i2 := indices[i + 2]

			# Use the UNMODIFIED box normal to sort the triangle to the correct chunk
			var chunk_idx := _get_chunk_index(orig_normals[i0])
			var active_st := chunk_tools[chunk_idx]

			for idx in [i0, i1, i2]:
				active_st.set_uv(uvs[idx])
				active_st.set_normal(normals[idx]) # Assign our perfect math normals
				active_st.add_vertex(vertices[idx])

		# Finalize and commit all 6 surfaces (Surfaces 0..5)
		for c in range(6):
			var active_st := chunk_tools[c]
			active_st.index()
			# NO generate_normals() call here! We use our calculated normals.
			active_st.generate_tangents()
			active_st.commit(self)
			self.surface_set_name(c, CHUNK_NAMES[c])
	else:
		# Blazing fast Single-surface mode using the pre-modified arrays
		self.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		self.surface_set_name(0, "quadsphere")

	if debug_normals or debug_vertices:
		_add_debug_lines_surface()

	_restore_surface_materials()
	emit_changed()


## function for drawing debug lines across all geometry surfaces
func _add_debug_lines_surface() -> void:
	var geo_surface_count := get_surface_count()
	var line_st := SurfaceTool.new()
	line_st.begin(Mesh.PRIMITIVE_LINES)

	for s in range(geo_surface_count):
		var final_arrays := surface_get_arrays(s)
		var verts: PackedVector3Array = final_arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = final_arrays[Mesh.ARRAY_NORMAL]

		if debug_normals:
			line_st.set_color(Color.CYAN)
			for i in range(verts.size()):
				var start_pos := verts[i]
				var end_pos := start_pos + (norms[i] * debug_line_length)
				line_st.add_vertex(start_pos)
				line_st.add_vertex(end_pos)

		if debug_vertices:
			line_st.set_color(Color.DARK_MAGENTA)
			var half_size := debug_line_length * 0.25
			for v in verts:
				# X-axis line segment
				line_st.add_vertex(v - Vector3.RIGHT * half_size)
				line_st.add_vertex(v + Vector3.RIGHT * half_size)
				# Y-axis line segment
				line_st.add_vertex(v - Vector3.UP * half_size)
				line_st.add_vertex(v + Vector3.UP * half_size)
				# Z-axis line segment
				line_st.add_vertex(v - Vector3.BACK * half_size)
				line_st.add_vertex(v + Vector3.BACK * half_size)

	var debug_mat := StandardMaterial3D.new()
	debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_mat.vertex_color_use_as_albedo = true

	line_st.commit(self)
	var debug_surface_idx := get_surface_count() - 1
	surface_set_name(debug_surface_idx, "debug")
	surface_set_material(debug_surface_idx, debug_mat)


func _cache_surface_materials() -> void:
	for surface_index in range(get_surface_count()):
		_surface_materials[surface_get_name(surface_index)] = surface_get_material(surface_index)


func _restore_surface_materials() -> void:
	for surface_index in range(get_surface_count()):
		var surface_name := surface_get_name(surface_index)
		if _surface_materials.has(surface_name):
			surface_set_material(surface_index, _surface_materials[surface_name])


## ------------------- HELPER FUNCTIONS ------------------- ##
## Debouncing to prevent editor hickups during reconstruction
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

## Determines which of the 6 box faces (0..5) a triangle came from
func _get_chunk_index(orig_normal: Vector3) -> int:
	if orig_normal.x > 0.5:  return 0 # Right (+X)
	if orig_normal.x < -0.5: return 1 # Left (-X)
	if orig_normal.y > 0.5:  return 2 # Top (+Y)
	if orig_normal.y < -0.5: return 3 # Bottom (-Y)
	if orig_normal.z > 0.5:  return 4 # Back (+Z)
	return 5                          # Front (-Z)
## -------------------------------------------------------- ##
