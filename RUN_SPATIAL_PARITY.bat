@echo off
setlocal
cd /d "%~dp0"
if "%GODOT_CONSOLE%"=="" set "GODOT_CONSOLE=engine\Godot_v4.7.2-stable_win64_console.exe"
set "FXLAB_SPATIAL_EVIDENCE_DIR=%~dp0evidence\spatial_parity_final"
if not exist "%FXLAB_SPATIAL_EVIDENCE_DIR%" mkdir "%FXLAB_SPATIAL_EVIDENCE_DIR%"
"%GODOT_CONSOLE%" --path "." --script res://tests/lab_spatial_parity.gd --always-on-top
set RC=%ERRORLEVEL%
echo.
echo NRCU FX Lab spatial-parity gate exit code: %RC%
exit /b %RC%
