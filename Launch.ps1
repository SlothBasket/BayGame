param([string]$Godot = '', [switch]$Editor)
$projectPath = Join-Path $PSScriptRoot 'godot'
if (-not $Godot) {
    $workspaceEngine = Join-Path $PSScriptRoot '../../work/engine/Godot_v4.5.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $workspaceEngine) { $Godot = (Resolve-Path -LiteralPath $workspaceEngine).Path }
    elseif (Get-Command godot -ErrorAction SilentlyContinue) { $Godot = 'godot' }
    else { throw 'Pass -Godot C:/path/to/Godot.exe or install Godot on PATH.' }
}
if ($Editor) { & $Godot --path $projectPath --editor }
else { & $Godot --path $projectPath }
