# Procedural Generation 

## Surface Tool 
The surface tool is similar to how OpenGL Immediate tool works. As someone who has never worked with OpenGL, this wasn't a particularly useful description, so here is my take on it instead: 

taken from [quadsphere.gd](../src/quadsphere.gd): The surface tool is stateful. It builds meshes based on attributes which are configured before adding vertices to a mesh.

Before beginning, we initialize the surface tool: `st := SurfaceTool.new()`. We then call `st.begin(Mesh.PRIMITIVE_TRIANGLES)` the `begin(...)` function specifies what type of mesh the surface tool is going produce. We can also use it to create simple lines too by passing `Mesh.PRIMITIVE_LINES`, which is super useful for debugging. Thereafter, we do the following to make a mesh:

1. 	Set attributes by calling various functions, e.g `st.set_color(...)`. Attributes are in a "waiting state" until the next step occurs.
2. 	call `st.add_vertex()` to append a vertex. This will load the vertex with all previously set attributes.
3. 	`st.commit(self)` creates a surface which is then appended to the ArrayMesh. Calling `st.commit(self)` again will create a a *new* surface, seperate from the previous. You can sort of see it as using Git: commiting doesn't override your previous work, unless you explicitly revert a commit. Make sure to use `st.clear()` after a commit so you don't accidentally commit already-commited geometry.
4. 	`clear_surfaces()` wipes all surfaces from the ArrayMesh, so it lets you reset it that way. You can also use `surface_remove(surface_idx: int)` to wipe a specific surface.
5. 	Surfaces can be named with `surface_set_name(idx: int, string: title)`.


## Planet generation & modification
A Planet holds a ChunkManager, which in turn holds Chunks. Chunks are AnimatableBody3D, which is like a StaticBody, except that it can affect other physics bodies when it's updated. Each Chunk has a MeshInstance3D, and a CollisionShape3D, which define its appearance & shape. Whenever a Chunk updates its mesh, it should rebuild the CollisionShape as well.

> [!TIP] 
> Because we are using CollisionShape3D, You can use AreaCast3D and RayCast3D to detect individual chunks with ease! It also gives you access to loads of other useful things, such as plane normals and tangents. 

![](embeds/planet_diagram.png)
### Quadsphere
A quadsphere is useful because it suffers far less from edge-clustering at the top & bottom vertices. Size Variance of Faces is also much smaller than on a traditional UV sphere. It also lets us divide the sphere into 6 equally sized regions with ease :) 

### Chunking 
Each surface of the quadsphere can be split up to into separate sets of `{MeshInstance3D, CollisionShape3D}`. An individual chunk can have its terrain be directly modified through scripts without needing to reload the entire QuadSphere Resource. It comes with the disadvantage of convoluted code (especially since I went out of my way to make it work in-editor). 

> [!TIP]
> modify individual chunk meshes via `chunk.gd`. Modify the entire hexapshere via `chunk_manager.gd`.
