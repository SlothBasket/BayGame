# Phase 3 implementation notes

The permanent development project remains in this repository. `Play BayGame.bat` imports and runs current saved sources. `builds/windows/BayGame.exe` is an optional snapshot and must be rebuilt after edits; pushing GitHub does not update another checkout.

Implemented:
- One muted green land fill; original geographic shoreline/collision and islands retained. Procedural land and separate structure drawing disabled.
- Existing Alafia NAIP downloads repacked as water-only imagery, with a 200 m outer coverage feather. Separate aerial and bathymetric opacity controls, optional 5 ft contours, Chart alternative, cached imagery LOD fallback/fade. Photography coverage remains the existing Alafia pilot, not the entire bay.
- Boat-local, geographically anchored soundings in feet, zoom-adaptive spacing, configurable 0.5–10 km radius, hidden at full-world scale. `L` / controller Back toggle, rebindable through Controls. Compact boat depth remains visible.
- Separate numerical survey and reconstruction layers. Precedence: manual corrections, newer USF survey, NOAA composite DEM, reconstruction, unavailable. Original NOAA rasters are unchanged. Developer provenance view: blue source/interpolated survey, gold reconstruction, pink unavailable; exact query classification appears in diagnostics. Manual corrections appear in query diagnostics, but their circular footprints are not rasterized into the color view.
- Packed fish identities and absolute geographic coordinates, route spatial buckets, bounded near/distant updates, depth checks, connected habitat-segment movement, versioned save/load. No fish nodes or fishing mechanics. Species behavior, population ecology, robust migration and verified biological passage remain future work.

Survey decisions:
- **Hillsborough:** imported 519,436 USF echosounder measurements collected September–October 2022, distributed by GRIIDC under CC0. NAVD88 elevations and meters are documented in the file. The file identifies State Plane Florida West meters without a horizontal datum realization; EPSG:26959/NAD83 is an explicit interpretation, not claimed survey-grade horizontal registration. Four-neighbor IDW is limited to 16 m from measurements. Attribution: Wang, Ping, Kendal Jackson, Elizabeth Royer (2024), [DOI 10.7266/j1gj835p](https://doi.org/10.7266/j1gj835p). Source metadata and tile coverage: `godot/assets/generated/river-surveys.json`.
- **Alafia:** existing NOAA-5163 NAVD88 composite remains. The downloaded 2025 USACE survey metadata specifies MLLW/US survey feet; not merged without a validated tidal-datum conversion.
- **Manatee:** existing NOAA-5163 remains. Downloaded USACE river metadata specifies MLW/US survey feet; not silently treated as NAVD88. County depth-range polygons do not document sufficient datum/date/unit metadata in the service response and were not used numerically.
- **Little Manatee / Old Tampa tributaries:** existing NOAA-5163 where available; no additional compatible survey imported in this pass.

Reconstruction is intentionally bounded: mapped connected polygons, 16 m canonical grid, width/shore-distance profile, smooth transition toward nearby wet survey values, maximum 1.2 km from an anchor. Parameters are in `config/reconstruction.json`. It does not infer depth from photography. Unvalidated upstream water levels, centerline-only narrow reaches, missing geometry and distant gaps remain unavailable. This does **not** complete continuous upstream bathymetry or a river-slope model. All present depths use the game's fixed zero water surface; no tides or upstream water-level model is implemented.

Connectivity uses USGS NHDPlus HR fromnode/tonode topology rooted in existing Tampa Bay coastal water. Connected polygons alter water geometry; centerlines do not invent widths. Original pilot retention ponds without a supported network connection are excluded. Mapped barriers block boat footprints and exclude fish habitat routes. Hydrological connections do not certify boat access or fish passage. Some broad tributary acquisition requests timed out; exact outstanding requests are recorded in `water-network.json`. World bounds remain unchanged, so headwaters outside them are not included.

Rebuild with the Python dependencies in `requirements.txt`, from the repository root:

```powershell
python -m tools.gis.phase3_acquire
python -m tools.gis.river_survey
python -m tools.gis.river_network
python -m tools.gis.river_reconstruction
python -m tools.gis.fish_habitat
python -m tools.gis.pilot_build imagery
.\'Build Windows.ps1'
```

Acquisition caches are local and ignored. GIS source archives are input datasets, not development workspaces or user deliverables. No new game ZIP is required. The original base build predates these patches; rerun the Phase 3 pipeline after rebuilding base geography.

Validation results and per-river numerical coverage are recorded alongside this document after the final build.
