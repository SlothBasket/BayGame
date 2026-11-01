# Native bait ecology evaluation — November 1, 2026

The native worker remains authoritative. Ordinary sardine, mojarra, pinfish and mullet pods cannot be eaten directly, even when only one member remains. Fry and explicitly configured shrimp/crab groups remain directly consumable; attached bottom forage stays separate. Hungry predators pressure schools, then prioritize detected individuals. Schools flee cohesively and detach 1–3 members with a shared six-member cap and six-second cooldown. Consumption, rejoining and slot reuse preserve quantities and identities.

Mobile prey has no hunger-driven destinations. Schools choose nearby shelter using existing depth, shoreline and habitat tags; graph route costs prefer coastal cover. Solitary/orphaned prey shelters or joins compatible schools. Survivors track moving parents. Directional acquisition uses a configurable 160° cone plus short omnidirectional awareness; existing targets have bounded tracking. Parameters are in ecosystem-config.json and hunting-config.json.

Initial population: **4,818 → 9,635 pods**, **2,613 → 7,837 solitary prey**, **433,959 → 866,038 represented prey**, **15,814 → 25,855 native records**. Both launches start with zero temporary escapees, 8,000 game fish and 80 additional predators. All 1,000 snapper remain; inspection found 175 schools, maximum eight members, plus solitary fish.

## Measured performance

Same seed 18472, Godot 4.5.2/OpenGL on GTX 1660 Ti, Fish Lab visible at the boat-start camera with a 1,000 m span. Four-second warmup; two-second settling and twelve-second samples at each speed sequentially. Values are **before / after**. Hunting is worker processing wall time, not OS CPU utilization; the old build did not expose a separate hunting timer.

| Requested | FPS | Median ms | p95 ms | Achieved speed | After hunting ms / wall second |
| --- | --- | --- | --- | --- | --- |
| 1× | 60.03 / 60.02 | 16.66 / 16.66 | 16.82 / 16.88 | 0.996× / 0.999× | 3.43 |
| 5× | 60.03 / 60.03 | 16.67 / 16.67 | 16.81 / 16.86 | 4.998× / 4.994× | 8.57 |
| 10× | 60.03 / 60.04 | 16.66 / 16.67 | 16.81 / 16.86 | 10.053× / 9.955× | 11.69 |

Backlog and backlog growth were zero in every before/after sample. Native record/mask allocation increased from 22.75 to 46.05 MiB; this excludes routes, indexes and snapshots. Total process private memory increased from approximately 664–666 to 765–768 MiB, including Godot/graphics. Native record slots remained at 25,855 during the measured run rather than growing with each escape event. Full active-population, prey-quantity, memory and processing counters are in [native-bait-evaluation.json](native-bait-evaluation.json).

## Verification and limits

Focused native checks cover scheduled school approach → detachment → pursuit → capture, direct-pod rejection including a one-member pod, fry consumption, shared detach cooldown/cap, competing predators, safe recycling, survivor rejoining, orphan adoption/sheltering, directional senses, continuous trajectories, event-clock invariance, coastal route preference and land rejection. Quantity conservation was zero-error in every rendered measurement. Selected pod/fish/predator inspectors, close-zoom rendering and pause ran without errors after fixing initial-selection defaults and marker triangulation precision.

The Windows native extension is rebuilt locally; use the existing Play BayGame.bat launcher (build prerequisites in native/README.md). No standalone EXE export in this pass. These short tests do not establish long-term ecological balance or performance at every bay hotspot. Native selected-path lines still show a destination segment rather than the complete navigation route; some legacy history/aggregate inspectors remain compatibility views. Existing habitat evidence labels remain; this pass adds no surveyed habitat data or new species.
