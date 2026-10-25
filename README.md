# Tampa Bay — Godot geographic navigation prototype

A runnable Godot 4.5.2 vertical slice using downloaded NOAA Tampa Bay elevation and ENC vector geography. This is a software prototype, not a complete hydrographic survey or a navigation product. Generated assets are included, so the game runs offline without Python.

## Launch

**Windows: double-click `BayGame.exe` in the project root.** No Godot installation is needed. Keep the `godot/assets/generated` folder in its existing location beside the executable; it contains the map data. The executable embeds the game code and loads those geographic files offline.

For editing or running from source:

1. Install the standard (non-.NET) **Godot 4.5.2 stable** Windows build from https://godotengine.org/download/archive/4.5.2-stable/ .
2. Import `godot/project.godot` in Godot and press **F5**, or run:

```powershell
& 'C:/path/to/Godot_v4.5.2-stable_win64_console.exe' --path ./godot
```

Run commands from this repository root. The generated directory has `.gdignore`: these JSON/binary files are loaded using FileAccess, not Godot's importer. This avoids importing tens of thousands of data files. The Windows executable reads these ignored geographic files directly from the included folder. Its embedded PCK contains code and shaders. Export templates are build dependencies and are not bundled.

The initial view is the entire region. Press **Home**, then wheel up to see the 5.2 m boat. Nothing needs to download at runtime.

| Input | Action |
|---|---|
| W / S | Increase / decrease persistent throttle, including reverse |
| Space | Neutral throttle; momentum remains |
| A / D | Gradual speed-dependent steering |
| Wheel | Smooth zoom between presets down to 20 m vertical span |
| F / Home | Follow/free / recenter and follow boat |
| Right or middle drag | Free-camera pan |
| O | Full-world view |
| Tab / C | Chart contours, samples, channels / chunk grid |
| B | Run the 56-second benchmark; it moves boat/camera |
| 1–7 | Skyway, Port/Ybor, Alafia mouth area, Apollo Beach, upper Hillsborough, Old Tampa, Egmont Key |

## Geographic build

Use Python **3.12**, not the system's Python 3.15, for the pinned GIS wheels. Rasterio includes GDAL 3.9.3 in the tested environment; separate `osgeo` bindings are unnecessary.

```powershell
py -3.12 -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python -m tools.gis.acquire
.venv/Scripts/python -m tools.gis.acquire --url https://www.ngdc.noaa.gov/thredds/fileServer/regional/tampa_bay_13_navd88_2014.nc --output data/sources/tampa_bay_13_navd88_2014.nc
.venv/Scripts/python -m tools.gis.build
.venv/Scripts/python -m pytest -q
```

The NOAA download is approximately 505 MB. It is present in the working project but deliberately excluded from the portable ZIP and version control. Raw sources and projected caches stay in `data/`, outside runtime assets. The ZIP retains small vector source snapshots and their metadata to reproduce this shoreline; `acquire --force` explicitly refreshes them from NOAA's changing service.

`config/region.json` controls extent, CRS, chunk size, depth spacing, source selection, simplification tolerances, and runtime cache/LOD thresholds. Defaults: **W -82.90, S 27.35, E -82.15, N 28.18**, WGS84; **EPSG:32617**, UTM 17N meters. Fixed origin: easting 300000, northing 3120000. Game x = easting minus origin; game y = origin northing minus northing. Storage bounds are the projected envelope rounded outward to 1,024 m chunks, 76.8 × 94.208 km. A projected meter is one game unit; UTM grid-vs-ground distortion is tested below 0.1% in this region.

The builder caches each source reprojection by bytes, target grid, and processing version. Tile fingerprints skip unchanged mesh triangulation and asset writes; changed regions regenerate their intersecting tiles and ancestor levels. Global vector union, tile-intersection checks, source hashing, and manifest regeneration still run. It is not a remote distributed GIS build service.

For an explicitly separate procedural test world, even when real sources exist:

```powershell
.venv/Scripts/python -m tools.gis.build --config config/fixture.json --synthetic
& 'C:/path/to/godot.exe' --path ./godot -- --synthetic
```

The fixture writes `godot/assets/synthetic`, displays a synthetic banner, and never replaces real assets.

## Depth and corrections

The included depth surface is **NAVD88 elevation in meters**, positive upward, derived from NOAA's 2014 composite DEM. Displayed depth is `max(0, -elevation)`, relative to NAVD88 zero, **not instantaneous water depth or MLLW chart depth**. The pipeline does not convert between datums. MLLW and unknown/ellipsoidal sources are rejected. See `docs/SOURCES.md` for the candidate source audit.

A fixed-resolution, halo-padded leaf grid supplies simulation queries at every camera zoom. Strict bilinear stencil validity returns `null` when contributing samples are missing; no missing sample becomes zero. Nearest reprojected source masks retain missing-data locations. Coarser visual textures never replace simulation data. NOAA's composite DEM already includes interpolation, so results are labelled interpolated composite values, not individual measured soundings.

`DepthService` provides `get_depth_at`, `get_elevation_at`, `get_depth_metadata`, and `get_depth_profile` using GeoPosition. Queries can initially return unavailable/loading; callers must retry rather than treat loading as water or zero. Metadata includes datum, source contributors, quality, and resolution. Multi-source lists report composite contributors, not per-pixel lineage.

Copy the disabled example in `config/corrections.example.json` to `config/corrections.json`, intentionally enable it, and rebuild to demonstrate a circular depth override. Coordinates are absolute projected easting/northing, elevations NAVD88 meters. Last matching enabled correction wins. Remove it and rebuild to restore original readings. Corrections never alter source files. Numeric chart readouts reflect corrections; the color ramp and derived contours continue showing the original raster.

## Validation and measurements

```powershell
.venv/Scripts/python -m pytest -q
& 'C:/path/to/godot.exe' --headless --path ./godot --script ../tests/runtime.gd
& 'C:/path/to/godot.exe' --headless --path ./godot --script ../tests/runtime_navigation.gd
& 'C:/path/to/godot.exe' --path ./godot --resolution 1920x1080 -- --benchmark
```

Benchmark output defaults to Godot's user data directory. Pass `--report-dir=C:/absolute/report/folder` after `--` to save elsewhere. The directory must exist. `--capture`, optionally with `--view=close` or `--view=chart`, saves a screenshot and exits. `tools/benchmarks/summarize.py` turns benchmark JSON into a report. Actual results and conditions are in `docs/VALIDATION.md`; no benchmark target should be assumed from the architecture.

## Modules and delivered files

- `godot/project.godot`, `scenes/main.tscn`, `scripts/main.gd`: runnable app and scenario driver.
- `scripts/world/geo_position.gd`, `geography_store.gd`: double scalar coordinates, async bounded cache.
- `scripts/world/geographic_renderer.gd`, `region_view.gd`, `shaders/depth.gdshader`: hierarchical mesh/texture rendering, culling, chart and debug views.
- `scripts/depth/depth_service.gd`: geographic queries, NoData, correction layers, conservative land/coverage collision.
- `scripts/camera/map_camera.gd`, `scripts/boat/boat_model.gd`, `scripts/ui/debug_overlay.gd`: camera, vessel and measurements.
- `tools/gis/{acquire,build,coordinates,depth}.py`: source download, deterministic processing and reference query tools.
- `config/`: editable region, vessel, landmark, correction and fixture settings.
- `tests/`: Python geographic/export tests, GDScript runtime checks, and a real-map seam-crossing regression.
- `godot/assets/generated/manifest.json`: version, bounds, CRS, datum, provenance, checksums, resolutions, parameters and spatial index.
- `godot/assets/generated/chunks/`: eight mesh/raster LOD levels, with exact leaf collision rings and coverage polygons.
- `docs/`: source audit, architecture, validation, screenshots, benchmark data and file inventory.

## Known limits and next work

The first source is **coastal-scale ENC**. It captures the bay, islands and mapped river reaches, but it does not establish complete navigability of every creek or upstream tributary in the requested extent. Inland land polygons may fill waterways omitted at that chart scale. Unknown chart coverage blocks movement; this is deliberately conservative. The DEM ends near longitude -82.37, leaving much of the eastern configured region without depth. High zoom enlarges source geometry; it does not create new survey accuracy. Boat collision uses a conservative enclosing disc, so very narrow passages may be blocked.

Next, add higher-detail harbour/approach ENC or authoritative inland hydrography with an explicit coverage-precedence rule; audit the four named rivers and their tributaries. Add newer NAVD88 LiDAR tiles with per-cell lineage. Validate visual alignment at all seven reference locations and inspect transition recordings. Then tune chunk-size/LOD configurations on sustained travel, measure actual GPU allocation, and extend standalone export testing. No fishing, fish AI, tides, waves, wakes, wind, fuel, or hydrodynamics are implemented.

## Rebuild the Windows executable

Install Godot 4.5.2 export templates, set the Windows Desktop preset custom release template to your `windows_release_x86_64.exe` path, then run `godot --headless --path godot --export-release "Windows Desktop" ../BayGame.exe`. The checked-in template path matches the development workspace; adjust it on another machine. Ship the executable together with `godot/assets/generated`.
