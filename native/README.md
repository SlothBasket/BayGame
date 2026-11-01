# Native ecosystem (Windows)

Install Visual Studio Build Tools 2022 with **Desktop development with C++**, Windows SDK, and CMake tools; install Python 3 and Git.

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File tools/native/Build.ps1
& '.\Play BayGame.bat'
```

Use `-Python C:\path\python.exe` if Python is not discoverable. The build downloads the official godot-cpp commit pinned in `native/CMakeLists.txt`; generated files stay in `.local/`. No DLL is committed. Stop the game before rebuilding a loaded DLL.

Godot 4.5.2 loads `godot/native/bay_ecosystem.gdextension`. The existing geographic and population initialization hands records to a single native worker. GDScript retains read-only compatibility data for Fish Lab, not a second running ecosystem. `--gdscript-ecosystem` explicitly selects the reference engine for comparisons. `--ecosystem-seed=18472` sets a repeatable initial population.

The worker uses its own monotonic clock, indexed spatial occupancy, scheduled ecological decisions, generation-checked prey handles, and immutable snapshots. `native_cpu_budget_ms` in ecosystem-config.json controls a worker processing slice (default 12 ms, followed by a 5 ms wait). This is independent of rendered frame budgets; simulation debt is retained. Pause stops ecological advancement without losing debt.


## Checkpoint evaluation — November 1, 2026

Implemented: an integrated C++ worker with typed animals, stable generation-checked prey handles, detailed/intermediate/background scheduling, water-valid routing, mathematical capture, conserved escapee detachment/rejoining, schooling goals, recruitment, and batched Fish Lab snapshots. The live launcher builds the extension when required. The GDScript engine remains an explicitly selectable reference; only one engine advances ecology.

Previously completed graphical measurements used seed 18472, Fish Lab visible, a 1,000 m view, four seconds of warmup, then two seconds of settling and twelve seconds measured per speed. These are short tests, not an endurance guarantee.

| Requested | Reference achieved | Native achieved | Native FPS | Native worst frame | Native debt growth |
| --- | --- | --- | --- | --- | --- |
| 1× | 1.00× | 1.00× | 60.05 | 17.00 ms | 0 s |
| 5× | 2.08× | 4.97× | 60.03 | 17.00 ms | 0 s |
| 10× | 1.54× | 10.03× | 60.03 | 17.01 ms | 0 s |
| 20× | 1.46× | 19.91× | 60.03 | 19.93 ms | 0 s |

At 5× the reference accumulated 35.01 seconds of debt over its twelve-second measurement. Native process private memory was approximately 663–665 MiB across these samples; this includes Godot and graphics. Native record/mask allocation was about 22.75 MiB and excludes other native containers. The reported worker `cpu_ms` measures processing wall time, not OS thread CPU time. `tools/native/profile.gd` retains the comparison harness.

Earlier native core checks passed for conserved detachment/rejoining, escape caps, one-time consumption, recycled-handle safety, isolated-prey hunger, analytic route continuity and event-clock invariance. The final conservation counters, distant-threat tier guard, and added competition/land checks have not been rebuilt or tested. No new tests were run for this documentation/push checkpoint.

Remaining: detailed steering still advances in decision-sized steps; continuous between-decision trajectory publication and depth interpolation need finishing. Selected-path rendering uses a destination segment rather than the complete native route, and some legacy Fish Lab history/aggregate inspectors still use compatibility shadows. Extended camera/boat/follow/detail-transition testing and long-duration population balance remain unverified. The existing local DLL predates the final source edits; rebuild through the live launcher before evaluating them. No updated standalone EXE was exported.


## Subsequent bait ecology pass

See [the current evaluation](../docs/native-bait-evaluation.md) for the expanded population, completed ecology checks and before/after measurements. The extension has now been rebuilt, conservation checks pass, and detailed trajectory/depth publishing is continuous. The historical checkpoint limitations above describe that earlier commit. The current pass retains the live launcher and does not export a standalone EXE.
