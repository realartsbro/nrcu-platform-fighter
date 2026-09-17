@echo off
setlocal
cd /d "%~dp0"
if "%GODOT_CONSOLE%"=="" set "GODOT_CONSOLE=engine\Godot_v4.7.2-stable_win64_console.exe"
"%GODOT_CONSOLE%" --path "." --script res://tests/lab_authoring_parity_acceptance.gd
set RC=%ERRORLEVEL%
echo.
echo NRCU FX Lab authoring/parity runtime logic exit code: %RC%
exit /b %RC%
