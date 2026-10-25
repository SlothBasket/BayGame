# Windows exported snapshot

`BayGame.exe` is optional. For live development use `Play BayGame.bat` at the repository root.

Run `Build Windows.ps1` at the root to refresh this executable and copy the current geographic/imagery data into `godot/assets/generated` here. Distribute this entire directory together. The duplicate data directory is deliberately not committed; an EXE run inside a Git checkout can use the root project's canonical assets instead.
