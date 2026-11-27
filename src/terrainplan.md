# Planetoid Rewrite Plan

This plan outlines the rewrite of the Planetoid system to follow a specific Node3D hierarchy and implement chunking, mapping, and interaction logic.

## Objective
Implement a scalable, designer-friendly Planetoid system with high-performance deformation and collision support using a Quadsphere-to-Chunk architecture.

## Key Files & Context
- `src/Planetoids/planetoid.gd`: Main bootstrap script.
- `src/Planetoids/terrain_manager.gd`: Manages chunks and maps.
- `src/Planetoids/terrain_chunk.gd`: Handles local mesh and collision.
- `src/planet_interactor.gd`: Handles raycast/shapecast interaction.
- `src/quadsphere.gd`: Base geometry generator.

## Implementation Steps

### 1. Refactor `QuadSphere` (Geometry Consumption)
- **Current State**: `QuadSphere` currently builds one or six `ArrayMesh` surfaces but doesn't easily expose the raw `PackedVector3Array` data for specific faces without re-parsing the entire mesh.
- **Goal**: Add a function `get_face_data(face_index: int) -> Dictionary` that returns a struct containing:
  - `vertices`: The raw positions on the cube-sphere.
  - `normals`: Pre-calculated spherical normals.
  - `indices`: Face-specific indices.
  - `uvs`: Standard cube-mapped UVs.
- This allows `TerrainManager` to consume just the data it needs for a specific face without creating intermediary `ArrayMesh` objects.

### 2. Implement `TerrainChunk` (Local Logic)
- **Node Structure**:
  - `TerrainChunk` (extends `AnimatableBody3D`)
    - `MeshInstance3D`: For visual rendering.
    - `CollisionShape3D`: For physics.
- **Features**:
  - `@tool` support for real-time editor updates.
  - `update_collision()`: Uses `WorkerThreadPool` to bake a `ConcavePolygonShape3D` from the current mesh data.
  - `brush_deform(local_pos: Vector3, strength: float, radius: float)`: Calculates dot-product based deformation for vertices within the radius (similar to `terrain.gd`).
  - `get_nearest_vertex(local_pos: Vector3) -> int`: Fast spatial lookup (starting with distance-check, optimizing to grid-lookup if resolution is fixed).

### 3. Implement `TerrainManager` (Chunking & Mapping)
- **Chunking Scaling**:
  - The system uses a `chunking_factor`.
  - **Factor 0**: 1 Chunk (Full sphere).
  - **Factor 1**: 6 Chunks (1 per face).
  - **Factor 2**: 24 Chunks (6 faces * 4 sub-quads).
  - **Factor 3**: 96 Chunks (6 * 4 * 4).
  - **Factor 4**: 384 Chunks (6 * 4 * 4 * 4).
  - **Formula**: Total Chunks = `6 * 4^(chunking_factor - 1)` (for factor > 0).
- **Logic**:
  - Automatically subdivides the Quadsphere data based on the factor.
  - Manages the lifecycle of `TerrainChunk` nodes (instantiating, naming, and connecting signals).
  - **Validation**: Ensure `chunking_factor <= quadsphere.subdivisions`. Print a warning and clamp if invalid.

### 4. Implement `Planetoid` (Bootstrap & Hierarchy)
- **Node Hierarchy Enforcement**:
  - `Planetoid` (Node3D)
    - `Anchor` (Node3D)
    - `TerrainManager` (Node3D)
      - `TerrainChunk` (AnimatableBody3D) ...
    - `AnimationPlayer`
- **Bootstrap**: `@tool` script that creates `TerrainManager` if missing. Propagates the `QuadSphere` resource down to the manager.

### 5. Implement `PlanetInteractor` (Interaction Pipeline)
- **Pipeline**:
  - `RayCast3D` detects the hit point.
  - `ShapeCast3D` (Sphere) is moved to the hit point and forced to update.
  - `ShapeCast3D.get_collision_result()` identifies all `TerrainChunk` nodes in the brush area.
  - Signal `interaction_requested` is emitted with `(hit_point, affected_chunks, radius, strength)`.
- **Routing**: `TerrainManager` listens to this signal and calls `brush_deform` on the provided list of chunks.

## Verification & Testing
- **Editor Sync**: Verify that changing `chunking_factor` in the inspector updates the node tree immediately.
- **Threaded Bake**: Confirm that deforming the mesh doesn't cause frame-spikes (using the Godot Profiler).
- **Physics**: Drop a RigidBody onto a deformed area to verify collision accuracy.

## Future Considerations
- Mapping: `generate_maps()` for Heightmap persistence.
- "Global Edits" via 2D texture inputs.
- Seam stitching (neighbor vertex synchronization).
