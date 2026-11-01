param([string]$Python = '', [int]$Jobs = 4)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$cmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source
if (-not $cmake -and (Test-Path $vswhere)) {
 $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
 $cmake = Join-Path $vs 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
}
if (-not $cmake -or -not (Test-Path $cmake)) { throw 'Install Visual Studio Build Tools 2022: Desktop development with C++, Windows SDK, and CMake tools.' }
$build = Join-Path $repo '.local/native-build'
$args = @('-S',(Join-Path $repo 'native'),'-B',$build,'-G','Visual Studio 17 2022','-A','x64')
if ($Python) { $args += "-DPython3_EXECUTABLE=$Python" }
$cachedBindings = Join-Path $repo '.local/godot-cpp'
if (Test-Path (Join-Path $cachedBindings 'CMakeLists.txt')) { $args += "-DFETCHCONTENT_SOURCE_DIR_GODOT_CPP=$cachedBindings" }
& $cmake @args
if ($LASTEXITCODE) { throw 'Native configuration failed.' }
& $cmake --build $build --config Release --parallel $Jobs
if ($LASTEXITCODE) { throw 'Native compilation failed.' }
Write-Host 'Native ecosystem built: godot/native/bay_ecosystem.dll'
