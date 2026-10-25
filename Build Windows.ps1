param([string]$Godot = '', [string]$ExportTemplate = '')
$ErrorActionPreference = 'Stop'
$engine = & (Join-Path $PSScriptRoot 'tools/windows/Resolve-Godot.ps1') -Godot $Godot
$project = Join-Path $PSScriptRoot 'godot'
$output = Join-Path $PSScriptRoot 'builds/windows'
$logs = Join-Path $PSScriptRoot '.local/logs'
New-Item -ItemType Directory -Force -Path $output,$logs | Out-Null
$preset = Join-Path $project 'export_presets.cfg'
$original = [IO.File]::ReadAllText($preset)
try {
    if ($ExportTemplate) {
        $resolved = (Resolve-Path -LiteralPath $ExportTemplate).Path.Replace('\','/')
        [IO.File]::WriteAllText($preset, ($original -replace 'custom_template/release="[^"]*"', ('custom_template/release="' + $resolved + '"')))
    }
    & $engine --headless --path $project --editor --import --quit --log-file (Join-Path $logs 'build-import.log')
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    & $engine --headless --path $project --export-release 'Windows Desktop' (Join-Path $output 'BayGame.exe') --log-file (Join-Path $logs 'export.log')
    if ($LASTEXITCODE -ne 0) { throw 'Godot export failed. Install the matching export templates or pass -ExportTemplate.' }
    $source = Join-Path $project 'assets/generated'
    $destination = Join-Path $output 'godot/assets/generated'
    & robocopy.exe $source $destination /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1
    if ($LASTEXITCODE -ge 8) { throw 'Geographic data copy failed.' }
    Write-Host "Standalone build ready: $output (keep this entire folder together)."
} finally {
    [IO.File]::WriteAllText($preset,$original)
}
exit 0
