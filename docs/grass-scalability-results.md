# Grass ecosystem scalability — November 27, 2026

Built and tested in Godot 4.5.2 with the rendered Fish Lab, seed 18472. The entire bay remains simulated using the existing detailed/intermediate/background scheduling. Initial population: 8,000 game fish, 34,973 bait records, 80 large predators, and 1,641 bottom resources (44,694 records). Bait records represent about two million prey units; these are not two million individually steered animals.

Final sweep (20 seconds per speed): 20× and 40× kept up without growing debt. 60× achieved 58.89× and accumulated 23.08 simulated seconds of debt; it is not exposed as a normal speed.

A separate 60-second 40× run moved the camera between busy habitats every 20 seconds. Achieved 39.97×, 59.89 FPS, p95 frame 16.82 ms, worst frame 58.74 ms. Ending debt change 0.000 simulated seconds; maximum observed queue 0.597 simulated seconds (0.015 real seconds at 40×). These are short measurements on this machine, not an unlimited-population or long-session guarantee. Frame timing and queue lag are measured; visual movement quality is not exhaustively verified.

44,217 irregular grass openings passed polygon validity and 1–5 ft width checks (2 mm coordinate-rounding tolerance). They are embedded habitat records, not new population regions or Godot nodes. Grass height and density affect bait cover, holding depth, and shelter choices. Larger trout and flounder can choose opening locations for ambushes. Whole pods relocate more slowly toward cover while detached individuals retain fast escapes.

Existing native checks passed: conservation, rejoining, escape caps, stable handles, one-time consumption, route continuity, event-clock invariance, school pressure, prey priority, directional senses, orphan survival and smooth steering. Native DLL rebuilt locally; no standalone EXE exported. Detailed raw measurements: `grass-scalability-results.json`.
