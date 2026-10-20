#Requires -Version 5.1
# ==============================================================================
# WinBreathe.ps1 - Command-Line Interface & Automation Entrypoint (v2.1.2)
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
    [ValidateSet("Win7", "Win8", "Win10", "Win11", "")]
    [string]$TargetOS = "",
    [ValidateSet("Win7", "Win8", "Win10", "Win11", "")]
    [string]$PreviewOS = "",
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

$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "WinBreathe.Engine.psm1"
Import-Module $modulePath -Force

if ($PreviewOS) {
    $TargetOS = $PreviewOS
    $WhatIf = $true
}

if (-not [string]::IsNullOrEmpty($TargetOS) -and -not $WhatIf -and -not $Status) {
    Write-Host "[WARN] Simulation TargetOS '$TargetOS' ignored for live execution. Live optimization strictly targets the host operating system." -ForegroundColor Yellow
    $TargetOS = ""
}

if ($Help) {
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  WinBreathe v2.1.2 - Universal Windows Memory & Latency Optimizer Help" -ForegroundColor Cyan
    Write-Host "  OS Coverage: Windows 11 | Windows 10 | Windows 8.1 | Windows 7" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  -GUI                              Launch the 6-tab graphical dashboard"
    Write-Host "  -Profile <Name>                   Select profile: Conservative, Balanced (default), Aggressive"
    Write-Host "  -PreviewOS <Win7|Win8|Win10|Win11> View tailor-made options and status for that OS"
    Write-Host "  -TweakIds <id1,id2...>            Apply only specific tweak IDs from config/tweaks.json"
    Write-Host "  -WhatIf                           Preview every change without modifying the system"
    Write-Host "  -Status                           Check live tweak drift & hardware telemetry"
    Write-Host "  -Flush                            Read memory without closing apps (legacy alias)"
    Write-Host "  -Snapshot                         Save current registry/service/pagefile state to JSON"
    Write-Host "  -Undo                             Restore exact pre-optimization state from latest snapshot"
    Write-Host "  -ResetDefaults                    Disabled: use a valid protected Undo snapshot instead"
    Write-Host "  -InstallGuard                     Disabled pending secure installation support"
    Write-Host "  -RemoveGuard                      Remove the Update Guard scheduled task"
    Write-Host "  -ExportReport                     Generate HTML and Markdown telemetry/drift reports"
    Write-Host ""
    exit 0
}

# WhatIf is global: alternate action switches must never bypass preview mode.
if ($WhatIf -and ($GUI -or $Snapshot -or $Undo -or $ResetDefaults -or $Flush -or $InstallGuard -or $RemoveGuard -or $ExportReport)) {
    Write-Host '[PREVIEW] The requested action was not executed. No settings or processes were changed.'
    exit 0
}
if (@(@($GUI,$Snapshot,$Undo,$ResetDefaults,$Status,$Flush,$InstallGuard,$RemoveGuard,$ExportReport) | Where-Object { $_ }).Count -gt 1) {
    Write-Error 'Choose one action at a time.'
    exit 2
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
    Write-Host "  WinBreathe v2.1.2 - Live System Telemetry & Drift Status" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  OS         : $($sys.OSCaption) (Build $($sys.OSBuild))"
    Write-Host "  RAM Usage  : $($sys.UsedRAMMB) MB / $($sys.TotalRAMMB) MB ($($sys.LoadPercent)% Load | $($sys.AvailRAMMB) MB Free)"
    Write-Host "  Disk       : $($sys.DiskModel) [$($sys.DiskMediaType)] ($($sys.FreeDiskGB) GB Free on $($sys.SystemDrive))"
    Write-Host "  Recommended: $($sys.RecommendedProfile) Profile"
    Write-Host "  Boot Guard : $($guard.State) (Last Run: $($guard.LastRunTime))"
    Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
    $states = Test-WBTweakState -ProfileName $Profile -TargetOS $TargetOS
    foreach ($s in $states) {
        $tag = switch ($s.State) {
            "Applied"       { "[APPLIED] " }
            "NotApplicable" { "[N/A]     " }
            "Unknown"       { "[UNKNOWN] " }
            default         { "[DEFAULT] " }
        }
        $col = switch ($s.State) {
            "Applied"       { "Green" }
            "NotApplicable" { "DarkGray" }
            "Unknown"       { "DarkYellow" }
            default         { "Yellow" }
        }
        Write-Host ("  {0} {1,-24} | {2} ({3})" -f $tag, $s.Id, $s.Title, $s.CurrentValue) -ForegroundColor $col
    }
    Write-Host "======================================================================" -ForegroundColor Cyan
    exit 0
}

if ($Snapshot) {
    $result = New-WBSnapshot -Label "Manual CLI Snapshot"
    if (-not $result) { exit 1 }
    exit 0
}

if ($Undo) {
    $result = Restore-WBSnapshot
    if (-not $result) { exit 1 }
    exit 0
}

if ($ResetDefaults) {
    $result = Restore-WBStockDefaults
    if (-not $result) { exit 1 }
    exit 0
}

if ($Flush) {
    $result = Invoke-WBSafeFlush
    if (-not $result) { exit 1 }
    exit 0
}

if ($InstallGuard) {
    $result = Install-WBUpdateGuard -ProfileName $Profile
    if (-not $result) { exit 1 }
    exit 0
}

if ($RemoveGuard) {
    $result = Uninstall-WBUpdateGuard
    if (-not $result) { exit 1 }
    exit 0
}

if ($ExportReport) {
    $result = Export-WBReport -ProfileName $Profile
    if (-not $result) { exit 1 }
    exit 0
}

# Default action: Run optimization (or preview if -WhatIf)
$result = Invoke-WBTweaks -ProfileName $Profile -TweakIds $TweakIds -TargetOS $TargetOS -WhatIf:$WhatIf -SkipSnapshot:$SkipSnapshot -SkipFlush:$SkipFlush
if (-not $result -or $result.FailedCount -gt 0 -or ($result.PSObject.Properties.Name -contains 'Aborted' -and $result.Aborted)) { exit 1 }
exit 0
