class_name Terrain
extends Node3D

@export var chunk_manager: ChunkManager

var _arrays: Array = []                      # mesh arrays per chunk
var _dirs: Array[PackedVector3Array] = []    # vertex directions
var _heights: Array[PackedFloat32Array] = [] # vertex heights
var _radius: float = 0.5
var _capture_queued := false


func _ready() -> void:
	_capture_chunks()
	chunk_manager.quadsphere.changed.connect(_on_quadsphere_changed)

## `changed` fires many times during a single quadsphere rebuild
##  only queue one capture and run it at the end of the frame
func _on_quadsphere_changed() -> void:
	if _capture_queued:
		return
	_capture_queued = true
	_capture_chunks.call_deferred()

## Reads every chunk's mesh and stores its directions & heights
func _capture_chunks() -> void:
	_capture_queued = false
	for chunk in chunk_manager.mesh_chunks:
		if chunk.mesh == null:
			return   # chunks not ready yet, skip
	
	# clear old data
	_arrays.clear()
	_dirs.clear()
	_heights.clear()

	for chunk in chunk_manager.mesh_chunks:
		var arrays := chunk.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

		var dirs := PackedVector3Array()
		dirs.resize(verts.size())
		for i in verts.size():
			dirs[i] = verts[i].normalized()

		var heights := PackedFloat32Array()
		heights.resize(verts.size()) # all 0.0

		_arrays.append(arrays)
		_dirs.append(dirs)
		_heights.append(heights)

	_radius = _arrays[0][Mesh.ARRAY_VERTEX][0].length()

	# TEST 
	var h := _heights[0]
	h.fill(0.1)
	_heights[0] = h
	_rebuild_chunk(0)

## Rebuilds chunk `c`'s mesh from its directions & heights
## Only vertex positions change, everything else in the mesh arrays is reused
func _rebuild_chunk(c: int) -> void:
	var dirs := _dirs[c]
	var heights := _heights[c]

	var verts := PackedVector3Array()
	verts.resize(dirs.size())
	for i in dirs.size():
		verts[i] = dirs[i] * (_radius + heights[i])

	var arrays: Array = _arrays[c]
	arrays[Mesh.ARRAY_VERTEX] = verts

	var mesh: ArrayMesh = chunk_manager.mesh_chunks[c].mesh
	var material := mesh.surface_get_material(0)
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
