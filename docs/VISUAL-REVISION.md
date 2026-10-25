# Stylized visual/navigation revision

The live project and optional Windows build now default to Stylized. Chart adds contours/channels to the same land/water palette. Saved pre-revision visual modes migrate to Stylized without replacing input bindings. Aerial imagery is retained as developer-only reference, fading to 30% opacity with per-tile fade-in. Normal mode cycling never enters reference mode.

Land uses a world-anchored procedural texture that stays aligned across chunks and floating-origin shifts. Shorelines receive a soft vegetation-colored band and a light edge. This is decorative styling, not a claimed marsh/mangrove or developed-land classification. Existing sourced ramp/dock/bridge records have simple filled symbols and overlapping text is suppressed. The bridge geometry remains a partial visual segment.

The water shader uses a teal visual fallback and blends neighboring available samples toward it at missing-data edges. The appearance-only fallback has no effect on DepthService, soundings, collision, waterway connectivity or navigation permissions. Unknown remains Unknown; no numeric bathymetry is manufactured. Contours are only drawn where samples are valid.

Low-speed yaw authority now comes from motor throttle as well as motion. Gentle throttle and steering can produce near-pivot turns, including in reverse, while speed reduces yaw authority smoothly. Yaw still ramps and decays rather than snapping. The 50 MPH forward cap and existing swept/disc collision checks remain.

The main HUD explicitly reads `Depth: ... ft` or `Depth: Unknown`. Local floating soundings default off even in Chart, and can be enabled in Gameplay settings. No new gameplay key is required.

## Focused validation

- Five targeted steering/default checks passed: low-throttle near-pivot, wider high-speed turns/cap, reverse yaw, smooth yaw decay and clean defaults.
- Sixteen existing runtime/depth/collision checks passed, including missing depth and thin land-barrier collision.
- All-NaN water texture rendered on the GPU as teal (approximately RGB 0.145, 0.455, 0.447), with chart mode enabled. The test uses an independent 256x256 viewport to avoid project window scaling.
- Inspected the Alafia view for land/water consistency and HUD readability; corrected overlapping structure labels.
- Updated standalone executable launched and exited 0. Short stationary GTX 1660 Ti / 1080p capture: 60 FPS at capture, p95 16.786 ms, zero imagery-cache allocation. See `visual-revision-smoke.json`. This is not a sustained travel benchmark.
- Existing sandbox shader-cache write warning remains; actual rendering succeeded.
- No map chunks, bathymetry rasters, connectivity files or navigation code were changed. No large asset regeneration, full-world benchmark, ZIP or new working directory was created.

Remaining: geometry LOD switches can still shift shoreline detail slightly; the developer reference can expose its limited coverage; shoreline bands are not real habitat masks; structure coverage/bridge footprints remain incomplete. Wider watershed expansion and hardware-controller testing remain outstanding from Phase 2.
