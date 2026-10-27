# Bay imagery and observable ecosystem — 2026-10-26

Initial checkpoint pushed before this pass: `c80d5797`. River geometry and bathymetry are preserved; this pass does not expand or reconstruct rivers.

## Previous fish implementation: what was real

The previous foundation used **100,000**, not 10,000, packed records. It had stable IDs, absolute geographic positions, simple connected-segment movement, spatial buckets, and save/load. Its recorded two-route fixture test measured 119 ms initialization, 10.0 MiB engine memory increase, and 1.59 ms mean batched update; it did not update every record every frame. The integrated prior scene also instantiated 100,000 records. It had no species, sizes, hunger, food seeking or selectable ecosystem map. Existing record/storage/update code was extended rather than discarded. Historical reports remain in `phase3-fish-test.json` and `phase3-integrated.json`.

## Current implementation

- **10,000 fish**, **1,380 stable geographic zones**, **2,494 undirected water connections**. Zone centers use a fixed 750 m geographic grid independent of the 1,024 m render chunks. Links require water clearance and positive sampled depths; the zone graph is connected to the bay spawn. Land and existing mapped barrier paths are excluded.
- Each fish retains ID, species, size, preferred depth, hunger, behavior, geographic position, source zone and destination. Red drum, spotted seatrout and snook use deliberately simple authored gameplay preferences, not calibrated ecological predictions.
- Hungry fish probabilistically favor food and suitable depths, with individual variation, crowding pressure and a nonzero exploration chance. Fish consume food while feeding; zones replenish toward their own carrying capacity. Travel follows verified water corridors. There are no fish scene nodes.
- Distant records update in bounded batches; nearby records receive finer updates. Camera, zoom and render chunk visibility never determine existence or location. Teleporting moves the player, not populations.
- `user://bay-fish-population.dat` stores fish attributes, destinations, hunger, zone food, simulation time and RNG state. Autosave runs every 60 real seconds and on normal exit. This new versioned bay save leaves any old `fish-population.dat` foundation save untouched. An incompatible zone fingerprint is rejected explicitly. There is no off-session elapsed-time simulation.

## Observe and interact

Press **F4**, or open **Settings → Developer → Fish ecosystem map**. F4 is rebindable.

- Colored circles show population density and dominant species; the selected zone lists exact species counts. Lines show water connectivity. Close views show individual positions and movement direction; selected fish show their destination line.
- Switch the map between density/species, food availability, and selected-fish depth suitability.
- Click a zone or a nearby fish. **Select fish in zone (next)** cycles overlapping individuals.
- Inspect ID, species, size, preferred depth, hunger, position, state and destination. **Center map on selected fish** finds the same fish again after leaving the area.
- **Add food to selected zone** replenishes that zone. The simulation speed button cycles **1× / 10× / 60×**, making otherwise gradual travel observable. The debug speed is not persisted.
- Existing **L** local soundings, adjustable water/chart opacity, optional contours, boat handling, teleportation and live launcher remain.

## Satellite coverage and storage

All **152 planned NAIP tiles** were acquired for the bay bounding area **82.80°W–82.36°W, 27.48°N–28.08°N**, including Tampa Bay, Old Tampa Bay and Hillsborough Bay. Tiles align outside that box to avoid edge gaps. Water is masked using existing geographic assets; land remains opaque muted green.

- **121 shoreline tiles at 4 m**, **31 open-water tiles at 8 m**.
- New four-resolution offline pack: **8,686,444 bytes (8.28 MiB)**.
- Existing finer Alafia pack retained: **5,957,434 bytes (5.68 MiB)**.
- Combined imagery packs: **13.97 MiB**. Raw new acquisition cache: **378.40 MiB**, ignored by Git and not required for gameplay.
- Source: USDA NAIP 2023 public-domain imagery via the [Geoplatform ImageServer](https://imagery.geoplatform.gov/iipp/rest/services/NAIP/NAIP2023_CONUS/ImageServer). No duplicate Alafia download. Rebuild/acquisition scripts are `tools/gis/bay_imagery.py`; runtime keeps worker decoding, bounded uploads, LOD fallback/fade and the 96 MiB cache target. Outer coverage fades; internal tiles have no individual edge fades.

NAIP gaps are filled from the approximately 10 m **2016 Sentinel-2 cloudless** mosaic, blended across a 256 m transition. This older fallback uses 19 cached tiles (2,499,447 bytes). All 1,380 population-zone centers pass the final no-black-imagery check. The 4/8 m pack spacing does not imply finer source detail in fallback areas. The final measurement includes the fallback imagery and working overlay.

Attribution (also shown in-game): **Sentinel-2 cloudless — https://s2maps.eu by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016 & 2017)**, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), [WMS source](https://tiles.maps.eox.at/wms). Newer noncommercial mosaics were not used.

## Validation and measured limits

Targeted checks passed for water-connected zone links, reciprocal adjacency, barrier avoidance, probabilistic food choice, individual depth preference, corridor movement, feeding, identity preservation after relocation, and full save/load including reproducible future RNG-driven decisions. The food-choice fixture chose the favorable food zone 971/1,000 times and other choices 29 times.

The final 12-second performance run used **10,000 fish**, the debug overlay, **60× simulation**, and overview-to-close zoom on the GTX 1660 Ti. Earlier checks exposed JSON numeric-ID typing and a packed-array overlay API error. Both were corrected; the final run completed with a working overlay and no script errors. See `bay-ecosystem-performance.json`.

- Storage initialization: **87 ms**; measured engine memory increase **4.72 MiB**; packed records/food **649.9 KiB**. The memory delta includes zones and indexes, not just fish bytes.
- Actual behavior updates: **0.78 ms mean**, **1.45 ms p95**, across **16,486 decisions** and **177 migrations** in about 719 simulated seconds. These are bounded batch costs, not an all-fish-per-frame update.
- Whole scene: **18.82 ms mean (~53 FPS)**, **31.59 ms p95**, **57.35 ms maximum**; imagery cache **64.48 MiB**. Window content was 1280×720. First two seconds excluded.
- **60 FPS is not locked during the combined debug/streaming/accelerated-zoom stress case.** Further overlay/streaming optimization remains. No larger benchmark was run in this pass.

Remaining scope: authored food/species heuristics rather than a full ecosystem; corridor-centered movement rather than free roaming or schooling; narrow passages below zone spacing are omitted; no fishing mechanics, fish animations, spawning/mortality, migrations driven by seasons/tides, or offline-time catch-up. 4–8 m photography becomes soft at extreme close zoom outside the Alafia pilot. Source-photo color seams and source shoreline inaccuracies can remain. Earlier river and vertical-datum gaps remain unchanged.

The rebuilt Windows executable also passed two normal-save-folder launches: both restored 10,000 fish with load status OK and no script errors.

## Build and launch

Double-click `Play BayGame.bat` to run the latest saved source. `builds/windows/BayGame.exe` is the optional exported snapshot; keep its entire folder with geographic data when distributing. A GitHub push does not update another local checkout.

To rebuild only this pass's data, without touching rivers:

```powershell
python -m tools.gis.bay_imagery acquire
python -m tools.gis.bay_imagery_fallback
python -m tools.gis.bay_imagery pack
python -m tools.gis.bay_population_zones
.\'Build Windows.ps1'
```
