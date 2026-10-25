# Recorded benchmark

Engine: 4.5.2-stable (official); OS: Windows; GPU: NVIDIA GeForce GTX 1660 Ti; viewport: (1920.0, 1080.0); headless: False

Frame times use consecutive monotonic wall-clock timestamps. First two seconds of each phase are excluded from routine statistics; all-phase maxima and >50 ms counts remain reported. Vsync is enabled. This is a short scenario run, not a sustained acceptance certification.

| Scenario | Routine FPS | Routine p95 ms | All max ms | All >50 ms | Estimated geography MiB |
|---|---:|---:|---:|---:|---:|
| World overview | 60.00 | 16.70 | 93.17 | 2 | 3.71 |
| Overview to 20 m | 60.00 | 16.71 | 16.92 | 0 | 16.26 |
| Boat across chunk boundaries | 60.00 | 16.71 | 16.92 | 0 | 16.52 |
| Repeated panning | 60.00 | 16.70 | 16.88 | 0 | 22.67 |
| Distant jumps | 60.00 | 16.70 | 16.74 | 0 | 26.69 |
| Far-origin close view | 60.00 | 16.71 | 16.76 | 0 | 26.69 |
| Island/coast zoom cycling | 60.00 | 16.70 | 16.80 | 0 | 28.68 |

Whole-run mean FPS: 59.87.
Peak engine static memory: 64.42 MiB.
Peak reported video memory: 27.20 MiB (backend-dependent; zero means unavailable).
Peak draw calls: 408.
Boat traversal visited 3 geographic chunks; blocked frames: 0.
