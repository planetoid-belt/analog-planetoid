# Procedural Generation 

## Surface Tool 
The surface tool is similar to how OpenGL Immediate tool works. As someone who has never worked with OpenGL, this wasn't a particularly useful description, so here is my take on it instead: 

taken from [hexasphere.gd](../src/hexasphere.gd): The surface tool is stateful. It builds meshes based on attributes which are configured before adding vertices to a mesh.

Before beginning, we initialize the surface tool: `st := SurfaceTool.new()`. We then call `st.begin(Mesh.PRIMITIVE_TRIANGLES)` the `begin(...)` function specifies what type of mesh the surface tool is going produce. We can also use it to create simple lines too by passing `Mesh.PRIMITIVE_LINES`, which is super useful for debugging. Thereafter, we do the following to make a mesh:

1. 	Set attributes by calling various functions, e.g `st.set_color(...)`. Attributes are in a "waiting state" until the next step occurs.
2. 	call `st.add_vertex()` to append a vertex. This will load the vertex with all previously set attributes.
3. 	`st.commit(self)` creates a surface which is then appended to the ArrayMesh. Calling `st.commit(self)` again will create a a *new* surface, seperate from the previous. You can sort of see it as using Git: commiting doesn't override your previous work, unless you explicitly revert a commit. Make sure to use `st.clear()` after a commit so you don't accidentally commit already-commited geometry.
4. 	`clear_surfaces()` wipes all surfaces from the ArrayMesh, so it lets you reset it that way. You can also use `surface_remove(surface_idx: int)` to wipe a specific surface.
5. 	Surfaces can be named with `surface_set_name(idx: int, string: title)`.


## Planet generation 

### Hexasphere
A hexasphere is useful because it suffers far less from edge-clustering at certain vertices. It also lets us divide the sphere into 6 equally sized regions. 

### Chunking 
Each chunk of the hexasphere corresponds to a surface. This is how we do chunking. Each chunk from there-on can be subdivided into chunks (if need-be)

