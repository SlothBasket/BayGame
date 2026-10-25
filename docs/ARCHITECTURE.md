# Geographic architecture

## Independent systems

GeographyStore owns immutable source-derived chunks, their manifest and asynchronous cache. DepthService accesses level-zero data and correction polygons without referring to Camera2D or renderer state. BoatModel consumes DepthService and double-valued geographic positions. GeographicRenderer alone chooses visual LOD. Changing zoom cannot change collision rings or numerical depth sampling.

Authoritative GeoPosition uses two GDScript scalar doubles. Vector2 is only created after subtracting a moving 1,024 m render origin. Source projection conversion happens offline with PyProj and is recorded in the manifest. Save files should store CRS, origin/asset version and double coordinates, not Node2D positions. A different configured origin requires migration through projected coordinates.

## Assets and rendering

Level zero is 1,024 m square. Every higher level doubles edge size. Levels 0–7 form an implicit quadtree addressed `level_x_y`; floor division works for negative coordinates. Each JSON contains chunk-relative triangulated land, original coastal boundary lines, optional ENC fairway edges and, at level zero, unsimplified land rings/holes and valid chart coverage. Earcut triangulates holes and islands. Geometry is repaired and globally simplified once per level before clipping. Adjacent same-level regions therefore share consistent edges. The renderer selects one uniform LOD for all visible chunks and retains a complete parent level until the desired set is ready, avoiding mixed-level T-junctions. Simplification introduces bounded shape changes; zero visible motion at every arbitrary zoom has not been established.

The `.f32` file is little-endian float32 elevation, `(n+3)²` values. Indices 1 through n+1 span the tile boundaries; one sample halo lies outside each edge. NaN is NoData. The level-zero spacing is `depth_cell_m`; visual levels use `texture_cells`. GPU upload converts NaN to a sentinel and the shader performs mask-aware bilinear sampling, preventing missing data from becoming shallow water. Float textures hold real meter values. There is no full-world close-resolution image or TileMap.

Visible index lookup is grid arithmetic at each candidate hierarchical level, not a scan of 9,336 nodes. Only visible regions produce GPU mesh/texture objects. Root data stays resident. WorkerThreadPool handles file reads and parsing, with at most eight jobs in flight; main-thread mesh creation is checked against a configurable 3 ms budget between chunks. A single chunk can exceed that budget, so recorded spikes are the acceptance evidence. Data cache uses a conservative five-times-serialized-size estimate for decoded objects; visual objects have a separate 128-region cap. These are estimates, not exact allocator measurements. Engine static/video-memory monitors are recorded in benchmarks where the backend exposes them.

## Boat and safety model

Throttle changes gradually and persists until Space or opposite input. Thrust, linear/quadratic drag, speed-dependent yaw target and exponential yaw response provide momentum. The vessel is 5.2 m long, with an enclosing collision disc. Motion is subdivided to at most 1 m steps; land polygon containment and edge distance prevent tunneling through thin mapped barriers. Missing/loading collision chunks and missing chart coverage stop the vessel. A depth value is not used to infer land: chart geometry and datum-relative elevation are different facts. Grounding based on tide/draft is outside scope.

## Future fish contract (no fish AI implementation)

A persistent fish record can contain `{id, east: float64, south: float64, population_id, habitat_id, simulation_timestamp}` plus the geographic asset/CRS version. A region key comes from the fixed geographic grid, never the visual LOD. Fish systems call DepthService for elevation, datum, confidence and unavailable/loading status, and GeographyStore for geometry/coverage. They must defer decisions when depth is missing. Near-player individuals and distant aggregate schools can use different update rates in a separate scheduler. Crossing a region boundary updates region membership while preserving fish identity and geographic position. Save/load serializes double coordinates independently of the current render origin. No renderer nodes or camera state belong in this contract.

## Incremental semantics

Each source raster has a cached target projection keyed by source bytes and target configuration. Multiple compatible rasters are applied in explicit config order; later valid samples win. A tile's input fingerprint includes local simplified geometry, fixed sampled values, local collision/coverage geometry, channels and format parameters. Unchanged inputs preserve output file timestamps. Changed regions update intersecting tiles and ancestors. Source metadata/manifest always refreshes. Global vector preparation and per-tile fingerprints are still evaluated; this is incremental export, not elimination of all global work. Snapshots and exact dependency versions are required for byte-identical reproduction across machines; NOAA live endpoints can change.
