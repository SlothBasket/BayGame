# BayGame

An offline Godot 4.5.2 geographic boating prototype for Tampa Bay. One projected meter is one game unit. The active project is an ordinary, unzipped Git checkout.

## Play the current project

Double-click **Play BayGame.bat** in this folder. It imports the latest saved resources, then runs `godot/project.godot` directly. It does not launch the exported EXE or extract an archive. Save edits, close the game, and double-click again to run the new version.

Godot is resolved in this order:

1. `Launch.ps1 -Godot 'C:\path\to\Godot.exe'` (explicit override).
2. The `GODOT_EXE` environment variable.
3. `godot-path.txt` in this folder: one line containing the full executable path, without arguments.
4. Godot on PATH, then common Godot installation/download folders.

Use standard **Godot 4.5.2**, with its matching export templates for builds. `godot-path.txt` is machine-specific and ignored by Git. The current checkout is configured to the existing portable Godot installation in the sibling Codex `work/engine` directory. If that engine is moved or removed, update this one-line file. Downloading the project from GitHub does not include Godot.

Useful PowerShell commands from this folder:

```powershell
.\Launch.ps1 -CheckOnly                    # show the resolved engine and project
.\Launch.ps1 -Editor                       # optional editor launch
.\Launch.ps1 -GameArguments '--view=alafia' # inspect the imagery pilot
```

Launcher/import logs are in `.local/logs/`, excluded from Git.

## Permanent working folder and updates

The current permanent checkout is:

```text
C:\Users\Sloth\Documents\Codex\2026-10-25\files-pasted-by-the-user-project\outputs\tampa-bay
```

The actual Godot project is its `godot` subfolder. Open this repository folder in Codex for future edits. Keep using this directory; no ZIP extraction is involved.

This checkout is not automatically synchronized with any separate BayGame folder you may already have. **A GitHub push does not update another local checkout.** To update this or another clean clone:

```powershell
cd 'C:\path\to\BayGame'
git pull --ff-only origin main
```

Save/commit local work before pulling. To establish a different permanent location, choose a new empty folder, then:

```powershell
git clone https://github.com/SlothBasket/BayGame.git C:\Games\BayGame
cd C:\Games\BayGame
Set-Content godot-path.txt 'C:\path\to\Godot_v4.5.2-stable_win64_console.exe'
.\Launch.ps1 -CheckOnly
```

Open **C:\Games\BayGame** in Codex and import **C:\Games\BayGame\godot\project.godot** in Godot if desired. Choose one checkout for ongoing development; changes in the Codex checkout do not appear in the new location until you pull them. Existing older archives are legacy snapshots, not working directories.

## Optional standalone Windows build

**builds/windows/BayGame.exe** is an exported snapshot. It does not incorporate source edits until rebuilt. Prefer **Play BayGame.bat** during development.

```powershell
.\'Build Windows.ps1'
# Or supply a matching portable export template explicitly:
.\'Build Windows.ps1' -ExportTemplate 'C:\path\to\windows_release_x86_64.exe'
```

The script exports the current code and copies all required runtime geography, imagery and structure files to `builds/windows/godot/assets/generated`. Copy the **entire builds/windows folder** to distribute a portable build; copying only the executable is insufficient. No ZIP is required.

Only one exported executable is tracked. Duplicate build data, logs, local engine configuration and ZIP files are ignored. In a fresh Git checkout, the EXE can also find the canonical `godot/assets/generated` two levels above it; run the build script before distributing the standalone folder. Raw GIS downloads and the Godot engine are not runtime dependencies.

## Controls and implemented gameplay

The compact HUD shows actual boat speed (MPH by default), depth in feet relative to NAVD88 zero, and throttle. Missing depth reads **Unknown**. Chart contours are spaced at **5 ft**. These are datum-relative DEM values, not tide-corrected navigation soundings.

| Default | Action |
|---|---|
| W / S | Increase / decrease persistent throttle |
| A / D | Steer |
| Space | Neutral throttle, retaining momentum |
| Wheel | Zoom |
| Right / middle drag | Pan |
| F / Home / O | Toggle follow / recenter / world overview |
| T | Teleport to mouse cursor, after collision/coverage validation |
| R | Toggle controller targeting reticle |
| Tab / V | Toggle chart / cycle visual mode |
| Escape or controller Start | Pause/settings |
| F3 | Toggle developer overlay |

Xbox-style defaults: left stick steers, triggers adjust throttle proportionally, right stick moves the map/targeting reticle, Y toggles targeting, A teleports, B selects neutral, X toggles follow, D-pad zooms. Menu face buttons provide confirm/back. All listed gameplay actions use InputMap. Controls settings support multiple keyboard/mouse/controller bindings, signed axes, deadzones, conflict replacement/swap/cancel, clear and restore defaults. Settings persist under Godot's `user://settings.json`. The on-screen Settings button remains available if menu bindings are removed. Benchmark controls require developer mode.

The boat approaches **50 mph** forward, caps reverse at 5 m/s, retains momentum, and uses movement subdivisions of at most 1 m for shoreline checks. Teleport resets speed, yaw and throttle, preserves zoom, and follows the relocated boat. Land, missing collision data and disallowed water are rejected; retry briefly if a destination is still loading.

## Phase 2 geography and imagery

Choose **Settings → Gameplay → View lower Alafia imagery pilot**. Video settings select Natural Hybrid, Hybrid Chart or Original Chart. The default overview uses simplified geography.

- USDA NAIP 2023: 30 georeferenced tiles, 0.5 m exported pixels from 0.3 m Florida source imagery captured January 6/11, 2023. Four imagery resolutions share one indexed WebP pack (~19.3 MiB), covering the Williams Park/lower Alafia pilot. Land masks preserve stylized water. Texture decoding uses workers, one upload per frame and a 96 MiB texture-cache target.
- USGS NHDPlus HR: polygons and flowlines acquired within **W -82.43, S 27.80, E -82.23, N 27.94**. 471 intersecting/ancestor vector tiles patched; NOAA depth rasters unchanged. Water components, flowlines, width availability and independently unknown fish passage/bathymetry are recorded in `waterways.json`. Flowlines are never given invented widths.
- Conservative navigation requires known depth and chart coverage. The optional permissive mode also admits mapped estuary-connected water without known depth, subject to land/footprint checks. Unknown depths remain unknown.
- Three approximate, sourced visual structure records identify Williams Park ramp/dock and a US 41 bridge segment. These are not surveyed collision polygons. Most over-water docks still need individual masking.

**Incomplete:** wider Hillsborough/Little Manatee/Manatee/Old Tampa tributary expansion; full upstream/barrier audit; complete hydrological routing and fish-passage model; exhaustive shoreline/structure alignment; sustained imagery-streaming benchmark; physical-controller hardware testing; full Williams Park-to-bay gameplay traversal validation. No barriers were returned by the filtered pilot barrier query, which does not establish that the area is barrier-free. The NOAA DEM has limited eastern coverage. Coastal masks retain source-scale inaccuracies.

## GIS development

Normal gameplay needs no Python or network. To regenerate data, use Python 3.12 and `requirements.txt`; raw downloads/caches remain untracked under `data/`.

```powershell
python -m tools.gis.acquire
python -m tools.gis.pilot_acquire hydro
python -m tools.gis.pilot_acquire imagery
python -m tools.gis.pilot_build hydro
python -m tools.gis.pilot_build imagery
```

The base `tools.gis.build` also requires the NOAA DEM described in `docs/SOURCES.md`. A base rebuild replaces patched vectors: rerun `pilot_build hydro` and `pilot_build imagery` afterward. The pilot patch only touches its intersecting regions/ancestors; it does not recompute bathymetry or the whole 9,336-tile map.

The existing EPSG:32617 projection, scalar-double geographic coordinates, floating origin, multiresolution renderer and separate depth queries remain. See `docs/ARCHITECTURE.md` and `docs/SOURCES.md` for the original design, and **docs/PHASE2-STATUS.md** for the current audit. Older validation/benchmark documents describe the earlier prototype, not an automatic performance guarantee for this update.
