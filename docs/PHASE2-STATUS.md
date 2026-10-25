# Phase 2 audit and launch-workflow update

Audited in the existing unzipped checkout on 2026-10-25. This is a completed gameplay/workflow update and a limited Alafia geographic pilot, not completion of the entire Phase 2 specification.

## Implemented and included

- Boat: configurable 22.352 m/s (~50 MPH) forward cap, 5 m/s reverse cap, gradual acceleration, persistent throttle, drag/momentum and smooth yaw. Movement checks retain <=1 m substeps.
- HUD/depth: compact MPH speedometer, optional knots/km/h, feet/NAVD88 depth and Unknown state; actual 5-foot contour interval; developer overlay hidden by default.
- Teleport: mouse or controller-targeting reticle; geographic conversion, footprint/coverage validation, no fallback location, resets speed/yaw/throttle, preserves zoom and follows destination. Loading destinations are rejected with a retry message.
- Controls: InputMap keyboard/mouse/controller actions, proportional axes, deadzones, multiple bindings, settings persistence, conflict replacement/swap/cancel, defaults, and an always-accessible Settings button. Pause/settings pages and developer-gated benchmark controls.
- Imagery: acquired and rendered USDA NAIP 2023 lower Alafia imagery, including Williams Park. Thirty georeferenced exports cover approximately 31.46 km2 on the tile-aligned grid, at 0.5 m output resolution. Intersecting Florida source imagery is 0.3 m, captured January 6/11, 2023. Four resolutions, one 20,184,278-byte indexed WebP pack, worker decoding, bounded prefetch/cache, natural/hybrid-chart/original-chart modes and geographic water masking.
- Hydrography: acquired 21 NHD area, 1,653 waterbody and 985 flowline features intersecting the Alafia study rectangle (-82.43,27.80,-82.23,27.94), plus source line/point layers. Filtering retains 1,249 supported polygon features. Applied the vector patch to 471 tiles/ancestors. Existing NOAA `.f32` depth grids are unchanged. Connected mapped-water eligibility and conservative/permissive navigation are separate from numeric depth. 1,236 polygon components and flowline width-status records are retained; no widths are inferred from centerlines.
- Structures: separate persistent records for Williams Park ramp, a dock and a US 41 bridge segment, identified on georeferenced imagery. Approximate visual masks only; no invented collision polygons.
- Workflow: `Play BayGame.bat` runs saved source via configurable/detected Godot, imports current resources first, and writes local logs. `Build Windows.ps1` updates the single `builds/windows/BayGame.exe` and includes the required data beside it. Copied build data, machine paths and archives are ignored. The root EXE was relocated; no new ZIP was generated.

## Focused validation

- Baseline before Phase 2: 16 runtime checks passed.
- Final Phase A checks: 16 passed, covering speed/momentum/reverse, binding serialization/conflicts, simulated signed controller steering/proportional trigger input, valid/invalid teleport, reset state/zoom preservation and hidden diagnostics. Initial simulated-input checks required flushing Godot's buffered events; the corrected harness passes. No physical controller was tested.
- Existing real-world chunk-seam navigation regression: passed after initializing the new InputMap in its harness.
- Geometry check: mapped estuary-connected water covers ~38.913 km2 inside the study rectangle, with ~0.013 m2 aggregate land intersection from 0.1 mm serialization rounding. A 2.8 m-radius water footprint beside Williams Park is covered and does not intersect land. This does not substitute for a complete boat traversal audit.
- Source and exported Alafia views rendered successfully; inspected land imagery, water masking, island and bridge alignment. Coastline/source-resolution inaccuracies remain visible.
- Launcher BAT `-CheckOnly` resolves the actual project and installed portable Godot; the build script completed export and data copy. Exported executable exited 0 after its graphical capture.
- Five-second stationary exported check: GTX 1660 Ti, 1920x1080, 60 FPS at capture, mean 18.285 ms including startup, p95 16.753 ms, 80 MiB imagery texture cache, no imagery decode errors. See `phase2-smoke.json`. This is not a sustained-travel benchmark or a controlled before/after regression measurement.
- The sandbox prevented Godot from creating its shader cache under user://; rendering still succeeded. Normal user-account settings persistence was not tested outside the sandbox; serialization/restore was tested at a writable test path.

## Still incomplete

- Hillsborough, Little Manatee, Manatee, Old Tampa tributary and broader watershed expansion; bounds have not been extended.
- Full upstream coverage to physical barriers. No features matching the pilot barrier filter were returned; this is not proof that barriers do not exist.
- Full directed hydrographic network routing, verified fish passage and complete navigability metadata. Current connectivity describes polygon adjacency to mapped estuary water and retains source flowlines.
- A fully validated Williams Park-to-bay boat trip, complete dock/bridge masks and detailed collision/clearance geometry.
- Broad imagery coverage, full-resolution source downloads, byte-range resumption of interrupted individual TIFFs (completed tiles are cached and failed transfers retried), and automated cancellation of stale imagery requests.
- Physical controller testing, sustained streaming/travel performance profiling and exhaustive UI usability checks.
- Fishing, fish AI, tides, waves and wakes remain outside this implemented prototype.

## Sources

- USDA NAIP: https://imagery.geoplatform.gov/iipp/rest/services/NAIP/NAIP2023_CONUS/ImageServer
- Federal catalog/public-domain terms: https://catalog.data.gov/dataset/national-agriculture-imagery-program-naip-imagery
- USGS NHDPlus HR: https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer
- USGS data terms: https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits
- Williams Park facility reference: https://gis.myfwc.com/boating_guides/tampa_bay/pages/boat_ramps/williams_park/index.html

Florida FHD metadata was investigated; distributed pilot geometry uses the USGS alternative. Raw source downloads remain local and untracked. Runtime source metadata accompanies the imagery index, geographic manifest, structures and waterways files.
