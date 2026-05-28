@echo off
REM ============================================================================
REM  OpenLab Recorder — one-click Windows installer.
REM  Double-click this file. That's it.
REM
REM  What it does:
REM    1. Re-launches itself in PowerShell with ExecutionPolicy Bypass
REM       (so the .ps1 below can actually run without policy prompts).
REM    2. Installs Python 3.12 via winget if missing.
REM    3. Runs install.py (pip-installs brainflow / pylsl / pyserial / pyxdf
REM       and downloads LabRecorder 1.17.0 into vendor/).
REM    4. Creates an "OpenLab Recorder" shortcut on the user's Desktop.
REM
REM  If anything fails the window stays open so the error is readable.
REM ============================================================================

setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install_windows.ps1"
set EXITCODE=%ERRORLEVEL%

echo.
if %EXITCODE% EQU 0 (
  echo  [SUCCESS] OpenLab Recorder installed. Look on your Desktop for the icon.
) else (
  echo  [ERROR] Installer exited with code %EXITCODE%. Scroll up to see what went wrong.
)
echo.
pause
endlocal
exit /b %EXITCODE%
