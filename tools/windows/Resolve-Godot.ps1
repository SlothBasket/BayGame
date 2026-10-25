param([string]$Godot = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$candidates = @()
if ($Godot) { $candidates += $Godot }
elseif ($env:GODOT_EXE) { $candidates += $env:GODOT_EXE }
elseif (Test-Path -LiteralPath (Join-Path $repo 'godot-path.txt')) {
    $candidates += (Get-Content -LiteralPath (Join-Path $repo 'godot-path.txt') -Raw).Trim().Trim('"')
}
if ($candidates.Count -gt 0) {
    if (-not (Test-Path -LiteralPath $candidates[0] -PathType Leaf)) { throw "Configured Godot executable not found: $($candidates[0]). Edit godot-path.txt or GODOT_EXE." }
    return (Resolve-Path -LiteralPath $candidates[0]).Path
}
foreach ($name in @('godot','godot4','Godot_v4.5.2-stable_win64_console','Godot_v4.5.2-stable_win64')) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
}
foreach ($directory in @("$env:ProgramFiles\Godot", "$env:LOCALAPPDATA\Programs\Godot", "$env:USERPROFILE\Downloads\Godot", "$env:USERPROFILE\Downloads")) {
    if (Test-Path -LiteralPath $directory) {
        $found = Get-ChildItem -LiteralPath $directory -Filter 'Godot*.exe' -File | Sort-Object Name -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
}
throw 'Godot was not found. Create godot-path.txt in the repository root with the full path to Godot 4.5.2, or set GODOT_EXE, or put Godot on PATH.'
