@echo off
set "SCRIPT_DIR=%~dp0"
set "SELF_PATH=%~f0"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
title WinBreathe v2.1.2 - Windows Memory and Settings Utility
color 0B

:: -----------------------------------------------------------------------------
:: UAC Elevation Check and Safe Self-Elevation (Opus WB-08 Hardened)
:: -----------------------------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ======================================================================
    echo  [*] Administrator privileges required. Requesting UAC elevation...
    echo ======================================================================
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath ($env:SystemRoot + '\System32\cmd.exe') -ArgumentList @('/c', ('\"' + $env:SELF_PATH + '\"')) -Verb RunAs"
    exit /b
)

cd /d "%SCRIPT_DIR%"
set "CLI_SCRIPT=%SCRIPT_DIR%src\WinBreathe.ps1"
set "GUI_SCRIPT=%SCRIPT_DIR%src\WinBreathe.GUI.ps1"

:MENU
cls
set "CHOICE="
echo ======================================================================
echo   WinBreathe v2.1.2 - Windows Memory and Settings Utility
echo   Review settings first. Memory savings are not guaranteed.
echo ======================================================================
echo.
echo   [1] Launch WinBreathe Graphical Dashboard (GUI) [RECOMMENDED]
echo       - 6-Tab Dark UI: Live RAM Chart, Per-Tweak Checkboxes, Preview,
echo         Top Memory Consumers, Startup Manager, and Drift Status
echo.
echo   [2] Apply Balanced Optimization (Auto-Snapshots State First)
echo       - Applies reviewed browser and Windows settings with a backup.
echo         Open apps stay open. Pagefile changes are opt-in.
echo.
echo   [3] Preview Changes Only (Dry-Run / -WhatIf Mode)
echo       - Shows every registry, service, and memory change without
echo         modifying anything on your computer
echo.
echo   [4] Live Drift Status and Telemetry Check
echo       - Verifies which tweaks are active vs reverted by Windows Update
echo.
echo   [5] Update Guard installation unavailable in this version
echo.
echo   [6] Undo Optimization (Restore Exact Pre-Optimization Snapshot)
echo       - Reverts every setting back to your saved backup snapshot
echo.
echo   [7] Generic factory reset unavailable; use a valid Undo snapshot
echo.
echo   [8] Export HTML and Markdown System Report
echo.
echo   [9] Help
echo.
echo   [0] Exit
echo.
echo ======================================================================
set /p CHOICE="Select an option [0-9]: "

if "%CHOICE%"=="1" (
    echo.
    echo [*] Launching WinBreathe v2.1.2 Graphical Interface...
    start "" "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%GUI_SCRIPT%"
    exit /b
)

if "%CHOICE%"=="2" (
    cls
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Profile Balanced
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="3" (
    cls
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Profile Balanced -WhatIf
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="4" (
    cls
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Status
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="5" (
    cls
    echo Update Guard installation is unavailable. No task was installed.
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="6" (
    cls
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Undo
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="7" (
    cls
    echo Generic factory reset is unavailable. Use a valid protected Undo snapshot.
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="8" (
    cls
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -ExportReport
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="9" (
    cls
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Help
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="0" exit /b

goto MENU
