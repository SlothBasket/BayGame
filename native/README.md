# Native ecosystem (Windows)

Install Visual Studio Build Tools 2022 with **Desktop development with C++**, Windows SDK, and CMake tools; install Python 3 and Git.

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File tools/native/Build.ps1
.\"Play BayGame.bat"
```

Use `-Python C:\path\python.exe` if Python is not discoverable. The build downloads the official godot-cpp commit pinned in `native/CMakeLists.txt`; generated files stay in `.local/`. No DLL is committed. Stop the game before rebuilding a loaded DLL.

Godot 4.5.2 loads `godot/native/bay_ecosystem.gdextension`. The existing geographic and population initialization hands records to a single native worker. GDScript retains read-only compatibility data for Fish Lab, not a second running ecosystem. `--gdscript-ecosystem` explicitly selects the reference engine for comparisons. `--ecosystem-seed=18472` sets a repeatable initial population.

The worker uses its own monotonic clock, indexed spatial occupancy, scheduled ecological decisions, generation-checked prey handles, and immutable snapshots. `native_cpu_budget_ms` in ecosystem-config.json controls a worker processing slice (default 12 ms, followed by a 5 ms wait). This is independent of rendered frame budgets; simulation debt is retained. Pause stops ecological advancement without losing debt.
