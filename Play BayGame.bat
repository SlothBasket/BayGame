@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch.ps1" %*
if errorlevel 1 (
  echo.
  echo BayGame could not start. See the message above and README.md.
  pause
  exit /b 1
)
