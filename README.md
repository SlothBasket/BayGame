# BayGame

An offline Godot 4.5.2 geographic boating prototype for Tampa Bay. One projected meter is one game unit. The active project is an ordinary, unzipped Git checkout.

## Fish ecosystem and Fish Lab

The default is **8,000 persistent game fish**. Existing populations keep their identities and counts. The entire bay uses the same fixed-step behavior, water-valid movement and physical hunting rules; camera position and selection do not change the simulation. Accelerated time queues work when the CPU cannot keep up, rather than skipping elapsed time.

Habitat now comprises **3,768 overlapping opportunity areas**, including **291 bottom-forage habitats**. Mobile prey groups search, scatter, split and regroup. Game fish, sharks and dolphins must physically reach prey and complete a capture before feeding. Substrate and vegetation classifications remain inferred where mapped evidence is unavailable.

Press **F4** for a compact toolbar and one selected-entity inspector. Fish, bait schools, predators and habitat areas have distinct contextual views. Use **Follow Selected**, **Center**, optional selection lock, display modes, paths and advanced details. Bait markers show species, group ID, abundance, direction and recent splits/merges. Simulation-rate and queued-time readouts distinguish requested acceleration from actual progress. Displayed movement is interpolated; authoritative positions and captures remain unchanged.

Close zoom now has additional intermediate stops. UI lengths/depths use inches/feet, longer distances yards/miles, and speed MPH. Internal geography remains SI. [Current implementation and limits](docs/WORLD-SIMULATION.md).

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

The compact HUD shows actual boat speed (MPH by default), depth in feet relative to NAVD88 zero, and throttle. Missing depth reads **Unknown**. Chart contours are spaced at **5 ft**. Floating depth numbers default off; enable Local soundings in Gameplay settings if desired. These are datum-relative DEM values, not tide-corrected navigation soundings.

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
| L or controller Back | Toggle local depth soundings |
| Escape or controller Start | Pause/settings |
| F3 | Toggle developer overlay |
| F4 | Toggle fish ecosystem map |

Xbox-style defaults: left stick steers, triggers adjust throttle proportionally, right stick moves the map/targeting reticle, Y toggles targeting, A teleports, B selects neutral, X toggles follow, D-pad zooms. Menu face buttons provide confirm/back. All listed gameplay actions use InputMap. Controls settings support multiple keyboard/mouse/controller bindings, signed axes, deadzones, conflict replacement/swap/cancel, clear and restore defaults. Settings persist under Godot's `user://settings.json`. The on-screen Settings button remains available if menu bindings are removed. Benchmark controls require developer mode.

The boat approaches **50 mph** forward, caps reverse at 5 m/s, retains momentum, and uses movement subdivisions of at most 1 m for shoreline checks. Thrust-assisted yaw permits near-pivot low-speed turns and reverse maneuvering, while high-speed turns widen smoothly. Teleport resets speed, yaw and throttle, preserves zoom, and follows the relocated boat. Land, missing collision data and disallowed water are rejected; retry briefly if a destination is still loading.

## Geographic data and limits

Choose **Settings → Gameplay → View lower Alafia** to inspect the imagery pilot. The existing 30-tile Alafia pilot is retained above the new 152-tile full-bay pack. Decoding uses workers, one GPU upload per frame and a 96 MiB cache target. Areas outside the bay imagery footprint use a consistent water-color fallback. Source shoreline inaccuracies remain visible along some photographed banks.

NOAA-5163 remains the baseline NAVD88 composite. Separate USF Hillsborough survey rasters take priority where supplied; deterministic reconstruction fills a small set of supported lower-river gaps. `river-surveys.json`, `reconstruction.json` and `water-network.json` under `godot/assets/generated` record source references, parameters, connectivity and remaining gaps. Original NOAA depth files remain unchanged. The older `waterways.json` is retained as historical pilot data; the Phase 3 network is authoritative for this revision.

Conservative boat navigation requires known game depth plus chart or connected mapped-water coverage and collision clearance. Permissive navigation admits mapped water with unavailable depth, still subject to shoreline and barrier checks. No advanced draft grounding, tide model or upstream water-surface model is implemented. Separate structure graphics are disabled; the source records remain preserved.

## GIS development

Normal gameplay needs no Python or network. Bay imagery and population-zone rebuild instructions are in [ecosystem status](docs/BAY-ECOSYSTEM.md); river development is paused. Use Python 3.12 with `requirements.txt`; raw input downloads and caches remain ignored under `data/`. Reuse existing imagery downloads. A base geography rebuild replaces patched vectors, so rerun the Phase 3 pipeline afterward. Do not run the historical Phase 2 hydro patch over a completed Phase 3 build.

EPSG:32617, scalar-double geographic positions, floating origin and geographic LOD rendering remain unchanged. `docs/ARCHITECTURE.md` and `docs/SOURCES.md` describe the original foundation. Phase 2 and visual-revision reports are historical; [ecosystem status](docs/BAY-ECOSYSTEM.md) records the current implementation and limitations.

Development sessions start with a fresh, weighted-size fish population. Fish identities persist within the session. Automatic ecosystem loading and saving are disabled; old save files are left untouched. Fish Lab speeds: **Pause | 1× | 5× | 10×**. Advanced shows achieved speed and backlog; a CPU-limit notice appears when processing falls behind.
