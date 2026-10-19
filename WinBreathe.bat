@echo off
set "SCRIPT_DIR=%~dp0"
set "SELF_PATH=%~f0"
title WinBreathe v2.0 - Windows 11 Memory and Latency Optimizer
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
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', ('\"' + $env:SELF_PATH + '\"')) -Verb RunAs"
    exit /b
)

cd /d "%SCRIPT_DIR%"
set "CLI_SCRIPT=%SCRIPT_DIR%src\WinBreathe.ps1"
set "GUI_SCRIPT=%SCRIPT_DIR%src\WinBreathe.GUI.ps1"

:MENU
cls
set "CHOICE="
echo ======================================================================
echo   WinBreathe v2.0.0 - Windows 11 Memory and Latency Optimizer
echo   Give Windows 11 Room to Breathe (4-16 GB RAM, HDDs and AI Stacks)
echo ======================================================================
echo.
echo   [1] Launch WinBreathe Graphical Dashboard (GUI) [RECOMMENDED]
echo       - 6-Tab Dark UI: Live RAM Chart, Per-Tweak Checkboxes, Preview,
echo         Top Memory Consumers, Startup Manager, and Drift Status
echo.
echo   [2] Apply Balanced Optimization (Auto-Snapshots State First)
echo       - Locks browser background bloat, disables telemetry/Widgets,
echo         enables Memory Compression, and sets fixed HDD pagefile
echo.
echo   [3] Preview Changes Only (Dry-Run / -WhatIf Mode)
echo       - Shows every registry, service, and memory change without
echo         modifying anything on your computer
echo.
echo   [4] Live Drift Status and Telemetry Check
echo       - Verifies which tweaks are active vs reverted by Windows Update
echo.
echo   [5] Install Hardened Windows Update Guard (Boot Persistence)
echo       - Registers LPE-hardened SYSTEM task to keep settings active
echo.
echo   [6] Undo Optimization (Restore Exact Pre-Optimization Snapshot)
echo       - Reverts every setting back to your saved backup snapshot
echo.
echo   [7] Reset to Windows 11 Stock Defaults
echo       - Resets all policies and pagefile to factory Windows defaults
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
    echo [*] Launching WinBreathe v2.0 Graphical Interface...
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%GUI_SCRIPT%"
    exit /b
)

if "%CHOICE%"=="2" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Profile Balanced
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="3" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Profile Balanced -WhatIf
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="4" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Status
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="5" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -InstallGuard
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="6" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Undo
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="7" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -ResetDefaults
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="8" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -ExportReport
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="9" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLI_SCRIPT%" -Help
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="0" exit /b

goto MENU
