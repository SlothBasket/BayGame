param(
    [string]$Godot = '',
    [switch]$Editor,
    [switch]$CheckOnly,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$GameArguments
)
$ErrorActionPreference = 'Stop'
$engine = & (Join-Path $PSScriptRoot 'tools/windows/Resolve-Godot.ps1') -Godot $Godot
$projectPath = Join-Path $PSScriptRoot 'godot'
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'project.godot'))) { throw "Missing project.godot in $projectPath" }
Write-Host "Live project: $projectPath"
Write-Host "Godot: $engine"
if ($CheckOnly) { exit 0 }
$logFolder = Join-Path $PSScriptRoot '.local/logs'
New-Item -ItemType Directory -Force -Path $logFolder | Out-Null
# Import saved resources and refresh global script classes before every source launch.
& $engine --headless --path $projectPath --editor --import --quit --log-file (Join-Path $logFolder 'import.log')
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed. See .local/logs/import.log.' }
$launchArgs = @('--path', $projectPath, '--log-file', (Join-Path $logFolder 'play.log'))
if ($Editor) { $launchArgs += '--editor' }
if ($GameArguments) { $launchArgs += '--'; $launchArgs += $GameArguments }
& $engine @launchArgs
if ($LASTEXITCODE -ne 0) { throw 'Godot exited with an error. See .local/logs/play.log.' }
