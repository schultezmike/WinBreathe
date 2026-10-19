@echo off
setlocal EnableDelayedExpansion
title WinBreathe - Enterprise Memory and Latency Optimizer
color 0B

:: -----------------------------------------------------------------------------
:: UAC Elevation Check and Robust Self-Elevation
:: -----------------------------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ======================================================================
    echo  [*] Administrator privileges required. Requesting elevation...
    echo ======================================================================
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c', '\"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
set "ENGINE_SCRIPT=%~dp0scripts\Win11LowRamOptimizer.ps1"
set "GUI_SCRIPT=%~dp0scripts\WinBreatheGUI.ps1"

:MENU
cls
echo ======================================================================
echo   WinBreathe - Windows 11 Memory and Latency Optimizer (v1.1.0)
echo   Engineered for 8GB RAM Laptops, Mechanical HDDs, and AI Dev Stacks
echo ======================================================================
echo.
echo   [1] Launch WinBreathe Graphical User Interface (GUI) [RECOMMENDED]
echo       - Modern Dark UI with Live RAM Bar, 1-Click Safe Optimize,
echo         Update Guard installer, and background WebView flusher
echo.
echo   [2] Run Quick Safe Memory Optimization (CLI Mode)
echo       - Locks Edge and Chrome policies (Renderer limit, sleeping tabs)
echo       - Disables heavy telemetry (DiagTrack, CDPSvc) and Search Indexer
echo       - Configures adaptive static pagefile with free-disk space protection
echo       - Flushes transient background webviews and uninstalls bloatware
echo.
echo   [3] Run Deep Interactive Optimization (CLI Mode)
echo       - Includes Option 2 plus interactive prompts for local databases
echo         (PostgreSQL, Claude services, updater daemons)
echo.
echo   [4] Install Hardened Windows Update Persistence Guard
echo       - Installs a silent Windows Task Scheduler hook (SYSTEM level)
echo       - Hardened NTFS ACLs to prevent Local Privilege Escalation
echo       - 90s delayed trigger to eliminate HDD boot thrashing
echo.
echo   [5] Restore Windows Defaults (Rollback All Optimizations)
echo       - Removes Persistence Task, restores Automatic pagefile,
echo         clears Edge and Chrome policies, and re-enables Windows Search
echo.
echo   [6] Remove Windows Update Persistence Guard Only
echo.
echo   [7] View Live RAM Telemetry and System Specs
echo.
echo   [8] Help (Details of Each Option)
echo.
echo   [0] Exit
echo.
echo ======================================================================
set "CHOICE="
set /p "CHOICE=Select an option [0-8 or H]: "
if not defined CHOICE goto MENU

if "%CHOICE%"=="1" (
    cls
    echo [*] Launching WinBreathe GUI...
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%GUI_SCRIPT%"
    exit /b
)

if "%CHOICE%"=="2" (
    cls
    echo [*] Executing Standard Safe Optimization...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE_SCRIPT%" -Silent
    echo.
    echo [+] Standard optimization applied successfully!
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="3" (
    cls
    echo [*] Launching Interactive Deep Optimization...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE_SCRIPT%"
    echo.
    echo [+] Deep optimization process completed!
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="4" (
    cls
    echo [*] Installing Hardened Windows Update Persistence Guard...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE_SCRIPT%" -InstallPersistence
    echo.
    echo [+] Persistence Guard installed! Settings will auto-lock on every boot.
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="5" (
    cls
    echo [*] Restoring Windows Default Settings...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE_SCRIPT%" -RestoreDefaults
    echo.
    echo [+] Windows defaults restored successfully.
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="6" (
    cls
    echo [*] Removing Persistence Guard...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE_SCRIPT%" -UninstallPersistence
    echo.
    echo [-] Persistence task removed.
    echo.
    pause
    goto MENU
)

if "%CHOICE%"=="7" (
    cls
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE_SCRIPT%" -TelemetryOnly
    echo.
    pause
    goto MENU
)

if /i "%CHOICE%"=="8" goto HELP
if /i "%CHOICE%"=="H" goto HELP

if "%CHOICE%"=="0" exit /b

goto MENU

:HELP
cls
echo ======================================================================
echo   WinBreathe - Help and Feature Guide
echo ======================================================================
echo.
echo   [1] Launch WinBreathe Graphical User Interface (GUI)
echo       - Opens the native modern dark-mode desktop window.
echo       - Features a live color-coded memory utilization bar (updates every 3s).
echo       - Non-blocking asynchronous worker: UI remains completely fluid.
echo       - 1-Click buttons for Safe Optimize, Update Guard, Flush, and Rollback.
echo       - Recommended for visual real-time monitoring and one-click controls.
echo.
echo   [2] Run Quick Safe Memory Optimization (CLI Mode)
echo       - 100%% safe, zero-damage architectural optimization.
echo       - Chromium Lockdown: Caps Edge and Chrome renderer processes to 4
echo         (adaptive: 3 on 4GB, 4 on 8GB, 8 on 16GB), enables 30s tab sleeping,
echo         and enforces Efficiency Mode thread throttling.
echo       - Stops background persistence (StartupBoost and background daemons).
echo       - Stops HDD thrashing: Disables Windows Search Indexer and telemetry.
echo       - Halts ApplicationPreLaunch to eliminate boot-time disk contention.
echo       - Allocates adaptive static contiguous pagefile (with 12GB free disk guard).
echo       - Enables In-RAM Memory Compression (zRAM 3:1 ratio).
echo       - Parent-Aware Flush: Cleans orphaned WebViews while strictly protecting
echo         active developer toolchains (Antigravity, Claude, VS Code, Node).
echo.
echo   [3] Run Deep Interactive Optimization (CLI Mode)
echo       - Executes everything in Option 2, plus interactively prompts you
echo         before adjusting optional local services:
echo         * Local databases: PostgreSQL, MySQL (converts to Manual start on demand)
echo         * Third-party updaters: Foxit PDF Update, Claude CoworkVMService
echo       - Prompts with [Y/N] for each service so you retain full control.
echo.
echo   [4] Install Hardened Windows Update Persistence Guard
echo       - Installs a silent Windows Task Scheduler task (Win11LowRamAutoOptimizer)
echo         running under NT AUTHORITY\SYSTEM.
echo       - Solves the Windows Update problem: automatically re-enforces your
echo         optimization settings after Windows Updates reboot your laptop.
echo       - Security Hardened: Uses language-independent Well-Known SIDs to strip
echo         non-admin write permissions, preventing Local Privilege Escalation (LPE).
echo       - Delayed Trigger: 90s delay after boot so it never slows down startup.
echo.
echo   [5] Restore Windows Defaults (Rollback All Optimizations)
echo       - Complete 1-click safety switch that reverts everything to stock Windows:
echo         * Removes the Task Scheduler Persistence Guard task.
echo         * Clears all Edge and Chrome policy limits.
echo         * Deletes Start Menu cloud search restrictions.
echo         * Restores Windows Automatic Managed Pagefile.
echo         * Re-enables Windows Search (WSearch) and Connected Telemetry (DiagTrack).
echo         * Re-enables SuperFetch PreLaunch and desktop transparency blurs.
echo.
echo   [6] Remove Windows Update Persistence Guard Only
echo       - Unregisters the scheduled persistence task only.
echo       - Leaves current Edge, service, and pagefile optimizations intact.
echo.
echo   [7] View Live RAM Telemetry and System Specs
echo       - Instant kernel query via Win32 GlobalMemoryStatusEx (less than 0.001 ms).
echo       - Reports Windows build, storage media (HDD/SSD), Total Physical RAM,
echo         active memory load percentage, available RAM, and total pagefile commit.
echo       - Read-only: does not modify any system settings.
echo.
echo   [8] Help
echo       - Displays this detailed explanation screen.
echo.
echo   [0] Exit
echo       - Safely exits the optimizer launcher.
echo.
echo ======================================================================
echo Press any key to return to the main menu...
pause >nul
goto MENU
