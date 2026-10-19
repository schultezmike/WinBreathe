# ==============================================================================
# WinBreathe.ps1 - Command-Line Interface & Automation Entrypoint (v2.0.0)
# Usage Examples:
#   .\src\WinBreathe.ps1 -GUI
#   .\src\WinBreathe.ps1 -Profile Balanced -WhatIf
#   .\src\WinBreathe.ps1 -Profile Balanced
#   .\src\WinBreathe.ps1 -Status
#   .\src\WinBreathe.ps1 -Undo
#   .\src\WinBreathe.ps1 -ResetDefaults
# ==============================================================================

param(
    [switch]$GUI,
    [ValidateSet("Conservative", "Balanced", "Aggressive")]
    [string]$Profile = "Balanced",
    [string[]]$TweakIds = @(),
    [switch]$WhatIf,
    [switch]$SkipSnapshot,
    [switch]$SkipFlush,
    [switch]$Snapshot,
    [switch]$Undo,
    [switch]$ResetDefaults,
    [switch]$Status,
    [switch]$Flush,
    [switch]$InstallGuard,
    [switch]$RemoveGuard,
    [switch]$ExportReport,
    [switch]$Help
)

$ErrorActionPreference = "SilentlyContinue"
$modulePath = Join-Path $PSScriptRoot "WinBreathe.Engine.psm1"
Import-Module $modulePath -Force

if ($Help) {
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  WinBreathe v2.0.0 - Windows 11 Memory & Latency Optimizer Help" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  -GUI                     Launch the 6-tab graphical dashboard"
    Write-Host "  -Profile <Name>          Select profile: Conservative, Balanced (default), Aggressive"
    Write-Host "  -TweakIds <id1,id2...>   Apply only specific tweak IDs from config/tweaks.json"
    Write-Host "  -WhatIf                  Preview every change without modifying the system"
    Write-Host "  -Status                  Check live tweak drift & hardware telemetry"
    Write-Host "  -Flush                   Safely flush transient Search/Widget WebView2 hosts"
    Write-Host "  -Snapshot                Save current registry/service/pagefile state to JSON"
    Write-Host "  -Undo                    Restore exact pre-optimization state from latest snapshot"
    Write-Host "  -ResetDefaults           Reset all tweaks back to stock Windows 11 defaults"
    Write-Host "  -InstallGuard            Install hardened SYSTEM boot task (Update Guard)"
    Write-Host "  -RemoveGuard             Remove the Update Guard scheduled task"
    Write-Host "  -ExportReport            Generate HTML and Markdown telemetry/drift reports"
    Write-Host ""
    exit 0
}

if ($GUI) {
    $guiPath = Join-Path $PSScriptRoot "WinBreathe.GUI.ps1"
    & $guiPath
    exit 0
}

if ($Status) {
    $sys   = Get-WBSystemProfile
    $guard = Get-WBUpdateGuardStatus
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  WinBreathe v2.0.0 - Live System Telemetry & Drift Status" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  OS         : $($sys.OSCaption) (Build $($sys.OSBuild))"
    Write-Host "  RAM Usage  : $($sys.UsedRAMMB) MB / $($sys.TotalRAMMB) MB ($($sys.LoadPercent)% Load | $($sys.AvailRAMMB) MB Free)"
    Write-Host "  Disk       : $($sys.DiskModel) [$($sys.DiskMediaType)] ($($sys.FreeDiskGB) GB Free on $($sys.SystemDrive))"
    Write-Host "  Recommended: $($sys.RecommendedProfile) Profile"
    Write-Host "  Boot Guard : $($guard.State) (Last Run: $($guard.LastRunTime))"
    Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
    $states = Test-WBTweakState -ProfileName $Profile
    foreach ($s in $states) {
        $tag = switch ($s.State) {
            "Applied"       { "[APPLIED] " }
            "NotApplicable" { "[N/A]     " }
            default         { "[DEFAULT] " }
        }
        $col = switch ($s.State) {
            "Applied"       { "Green" }
            "NotApplicable" { "DarkGray" }
            default         { "Yellow" }
        }
        Write-Host ("  {0} {1,-24} | {2} ({3})" -f $tag, $s.Id, $s.Title, $s.CurrentValue) -ForegroundColor $col
    }
    Write-Host "======================================================================" -ForegroundColor Cyan
    exit 0
}

if ($Snapshot) {
    New-WBSnapshot -Label "Manual CLI Snapshot" | Out-Null
    exit 0
}

if ($Undo) {
    Restore-WBSnapshot | Out-Null
    exit 0
}

if ($ResetDefaults) {
    Restore-WBStockDefaults | Out-Null
    exit 0
}

if ($Flush) {
    Invoke-WBSafeFlush | Out-Null
    exit 0
}

if ($InstallGuard) {
    Install-WBUpdateGuard -ProfileName $Profile | Out-Null
    exit 0
}

if ($RemoveGuard) {
    Uninstall-WBUpdateGuard | Out-Null
    exit 0
}

if ($ExportReport) {
    Export-WBReport -ProfileName $Profile | Out-Null
    exit 0
}

# Default action: Run optimization (or preview if -WhatIf)
Invoke-WBTweaks -ProfileName $Profile -TweakIds $TweakIds -WhatIf:$WhatIf -SkipSnapshot:$SkipSnapshot -SkipFlush:$SkipFlush | Out-Null
