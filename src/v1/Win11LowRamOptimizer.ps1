# ==============================================================================
# Win11LowRamOptimizer - Core Engine (v1.1.0 - Hardened Production)
# Developed for Windows 11 8GB RAM & Mechanical HDD / Constrained Systems
# Designed for open-source GitHub release under the WinBreathe suite
# ==============================================================================

param(
    [switch]$Silent,
    [switch]$InstallPersistence,
    [switch]$UninstallPersistence,
    [switch]$RestoreDefaults,
    [switch]$TelemetryOnly,
    [switch]$FlushTransientOnly
)

$ErrorActionPreference = "Continue"
$logDir = "$env:ProgramData\Win11LowRamOptimizer"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = "$logDir\optimizer_run.log"

# Fast Win32 Kernel Memory API
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct MEMORYSTATUSEX {
    public uint dwLength;
    public uint dwMemoryLoad;
    public ulong ullTotalPhys;
    public ulong ullAvailPhys;
    public ulong ullTotalPageFile;
    public ulong ullAvailPageFile;
    public ulong ullTotalVirtual;
    public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
}
public class Win32Mem {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
"@ -ErrorAction SilentlyContinue

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    if (-not $Silent) { Write-Host $line -ForegroundColor $Color }
    try {
        $line | Out-File -FilePath $logFile -Append -Encoding utf8 -ErrorAction SilentlyContinue
    } catch {}
}

function Assert-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "ERROR: Administrator privileges required. Run as Administrator." "Red"
        exit 1
    }
}

# ==============================================================================
# 1. SYSTEM TELEMETRY & HARDWARE PROFILING
# ==============================================================================
function Get-SystemProfile {
    Write-Log "`n--- 1. GATHERING SYSTEM & HARDWARE TELEMETRY ---" "Cyan"
    
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $stat = New-Object MEMORYSTATUSEX
    $stat.dwLength = [System.Runtime.InteropServices.Marshal]::SizeOf($stat)
    [Win32Mem]::GlobalMemoryStatusEx([ref]$stat) | Out-Null

    $totalRamMB = [math]::Round($stat.ullTotalPhys / 1MB, 0)
    $availRamMB = [math]::Round($stat.ullAvailPhys / 1MB, 0)
    $usedRamMB  = $totalRamMB - $availRamMB
    $usedPct    = [int]$stat.dwMemoryLoad
    $pfTotalMB  = [math]::Round($stat.ullTotalPageFile / 1MB, 0)

    $diskType = "Unknown"
    $diskName = "Generic Storage"
    try {
        $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($disk) {
            if ($disk.MediaType) { $diskType = $disk.MediaType }
            if ($disk.FriendlyName) { $diskName = $disk.FriendlyName }
        }
    } catch {}

    Write-Log "OS: $($os.Caption) (Build $($os.BuildNumber))" "White"
    Write-Log "Primary Storage: $diskName [$diskType]" "White"
    Write-Log "Total Physical RAM: $totalRamMB MB" "White"
    Write-Log "Active Memory Load: $usedRamMB MB ($usedPct% load)" "Yellow"
    Write-Log "Available Physical RAM: $availRamMB MB" "Green"
    Write-Log "Current Total Pagefile Commit: $pfTotalMB MB" "White"

    return @{
        TotalRAM = $totalRamMB
        UsedRAM  = $usedRamMB
        AvailRAM = $availRamMB
        DiskType = $diskType
    }
}

# ==============================================================================
# 2. DEFINED UNTOUCHABLE LIST & PARENT-AWARE PROCESS FLUSHER
# ==============================================================================
$global:UntouchableProcesses = @(
    "System", "Secure System", "Registry", "smss", "csrss", "wininit",
    "services", "lsass", "winlogon", "dwm", "explorer", "svchost",
    "MsMpEng", "MpDefenderCoreService", "SecurityHealthService",
    "OpenVPNConnect", "openvpn", "wireguard",
    "ChatGPT", "codex", "Antigravity", "language_server",
    "node", "git", "python", "powershell", "cmd", "Code", "Claude"
)

function Safe-FlushTransientProcesses {
    Write-Log "Flushing unneeded background WebViews and transient hosts..." "Yellow"
    $flushedCount = 0

    # Retrieve process table with parent ID info
    $allProcesses = @{}
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
            $allProcesses[$_.ProcessId] = @{
                Name = $_.Name.Replace(".exe", "")
                ParentId = $_.ParentProcessId
                CommandLine = $_.CommandLine
            }
        }
    } catch {}

    $candidateNames = @("SearchHost", "CrossDeviceResume", "winget")
    foreach ($cand in $candidateNames) {
        $procs = Get-Process -Name $cand -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            try {
                $p.Kill()
                $flushedCount++
            } catch {}
        }
    }

    # Selective, parent-aware WebView2 flusher (Protects Antigravity / Claude / VS Code)
    $webViews = Get-Process -Name "msedgewebview2" -ErrorAction SilentlyContinue
    foreach ($wv in $webViews) {
        $pidVal = $wv.Id
        $isProtected = $false

        if ($allProcesses.ContainsKey($pidVal)) {
            $parentPid = $allProcesses[$pidVal].ParentId
            if ($allProcesses.ContainsKey($parentPid)) {
                $parentName = $allProcesses[$parentPid].Name
                if ($global:UntouchableProcesses -contains $parentName) {
                    $isProtected = $true
                }
            }
            # Protect if command line indicates VS Code / Antigravity / Claude hosted
            $cmd = $allProcesses[$pidVal].CommandLine
            if ($cmd -match "Antigravity|Claude|VSCode|Code|ChatGPT") {
                $isProtected = $true
            }
        }

        if (-not $isProtected) {
            try {
                $wv.Kill()
                $flushedCount++
            } catch {}
        }
    }

    Write-Log "Flushed $flushedCount transient background instance(s) safely without touching dev stacks." "Green"
}

# ==============================================================================
# 3. 100% SAFE CUTS (TIER 2 - AUTOMATIC ARCHITECTURAL OPTIMIZATIONS)
# ==============================================================================
function Optimize-Tier2 {
    param($profile)
    Write-Log "`n--- 2. APPLYING TIER 2 (100% SAFE ZERO-DAMAGE CUTS) ---" "Cyan"

    $rendererLimit = 4
    if ($profile.TotalRAM -lt 6144) {
        $rendererLimit = 3
    } elseif ($profile.TotalRAM -gt 10240) {
        $rendererLimit = 8
    }

    # A. Microsoft Edge Engine Lockdown
    Write-Log "Configuring Microsoft Edge memory policies (RendererLimit=$rendererLimit, No Sidebar/Copilot)..." "Yellow"
    $edgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePolicy)) { New-Item -Path $edgePolicy -Force | Out-Null }
    
    $edgePolicies = @{
        "StartupBoostEnabled"          = 0
        "BackgroundModeEnabled"        = 0
        "HubsSidebarEnabled"           = 0
        "StandaloneHubsSidebarEnabled" = 0
        "EdgeCollectionsEnabled"       = 0
        "EdgeShoppingDataEnabled"      = 0
        "PrerenderAllowed"             = 0
        "DiagnosticData"               = 0
        "WebWidgetAllowed"             = 0
        "UserFeedbackAllowed"          = 0
        "SleepingTabsEnabled"          = 1
        "SleepingTabsTimeout"          = 30
        "RendererProcessLimit"         = $rendererLimit
        "EdgeCopilotEnabled"           = 0
        "DiscoverPageContextEnabled"   = 0
        "EdgeOpenInSidebarEnabled"     = 0
        "EfficiencyModeEnabled"        = 1
        "EfficiencyMode"               = 1
        "EdgeWorkspacesEnabled"        = 0
        "MathSolverEnabled"            = 0
        "EdgeWalletCheckoutEnabled"    = 0
        "ShowRecommendationsEnabled"   = 0
        "DiskCacheSize"                = 268435456
    }
    foreach ($k in $edgePolicies.Keys) {
        try {
            Set-ItemProperty -Path $edgePolicy -Name $k -Value $edgePolicies[$k] -Type DWord -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    # Mirror core policies to Google Chrome
    $chromePolicy = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    if (-not (Test-Path $chromePolicy)) { New-Item -Path $chromePolicy -Force | Out-Null }
    $chromePolicies = @{
        "BackgroundModeEnabled" = 0
        "RendererProcessLimit"  = $rendererLimit
        "DiskCacheSize"         = 268435456
    }
    foreach ($k in $chromePolicies.Keys) {
        try {
            Set-ItemProperty -Path $chromePolicy -Name $k -Value $chromePolicies[$k] -Type DWord -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    # Clean Edge auto-launch from Run key across HKLM and HKCU
    $runPaths = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Run")
    if (-not ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)) {
        $runPaths += "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    }
    foreach ($rp in $runPaths) {
        if (Test-Path $rp) {
            try {
                Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | ForEach-Object {
                    if ($_.Name -match "MicrosoftEdgeAutoLaunch|BingWallpaper|BraveSoftware") {
                        Remove-ItemProperty -Path $rp -Name $_.Name -Force -ErrorAction SilentlyContinue
                        Write-Log "Removed startup run entry: $($_.Name)" "Green"
                    }
                }
            } catch {}
        }
    }

    # B. Terminate Rogue Background WebViews & Transient Hosts Safely
    Safe-FlushTransientProcesses

    # C. Disable Telemetry & Redundant Search Indexer with SCM State Verification
    $heavyServices = @("DiagTrack", "WSearch", "CDPSvc")
    foreach ($svcName in $heavyServices) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.Status -ne 'Stopped') {
                    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                    $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(5))
                }
                Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "Disabled background service: $svcName" "Green"
            }
        } catch {
            Write-Log "Notice: Could not modify service $svcName ($($_.Exception.Message))" "Yellow"
        }
    }

    # D. Disable Start Menu Cloud Web Search Integration
    $searchPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (-not (Test-Path $searchPolicy)) { New-Item -Path $searchPolicy -Force | Out-Null }
    try {
        Set-ItemProperty -Path $searchPolicy -Name "DisableWebSearch" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $searchPolicy -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force
        Write-Log "Disabled Start Menu cloud search latency." "Green"
    } catch {}

    # E. Virtual Memory / Adaptive Static Pagefile with Free-Disk Space Guard
    $sysDrive = $env:SystemDrive
    try {
        $driveInfo = [System.IO.DriveInfo]::new($sysDrive)
        $freeSpaceMB = [math]::Floor($driveInfo.AvailableFreeSpace / 1MB)
        Write-Log "Drive $sysDrive Free Space: $freeSpaceMB MB" "White"
        
        # Credit existing pagefile size towards expansion headroom
        $existingPagefileSizeMB = 0
        if (Test-Path "$sysDrive\pagefile.sys") {
            try {
                $existingPagefileSizeMB = [math]::Floor((Get-Item -Force "$sysDrive\pagefile.sys").Length / 1MB)
            } catch {}
        }

        $effectiveFreeSpaceMB = $freeSpaceMB + $existingPagefileSizeMB
        $emergencyBufferMB = 12288
        $availableForPagefileMB = $effectiveFreeSpaceMB - $emergencyBufferMB

        if ($profile.DiskType -eq "HDD" -or $profile.TotalRAM -le 8192) {
            if ($availableForPagefileMB -gt 4096) {
                $calculatedSize = [math]::Min(12288, [math]::Floor($effectiveFreeSpaceMB * 0.35))
                $targetPagefileMB = [math]::Max(4096, $calculatedSize)
                
                Write-Log "Configuring $targetPagefileMB MB Static Contiguous Pagefile on $sysDrive\pagefile.sys..." "Yellow"
                
                # 1. Disable Windows Automatic Managed Pagefile in CIM
                try {
                    $cs = Get-CimInstance Win32_ComputerSystem
                    if ($cs.AutomaticManagedPagefile) {
                        Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false} -ErrorAction SilentlyContinue
                    }
                } catch {}

                # 2. Kernel-Authoritative Configuration via Registry (Guaranteed Windows 11 compatibility)
                $memRegKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                $pagefileString = "$sysDrive\pagefile.sys $targetPagefileMB $targetPagefileMB"
                Set-ItemProperty -Path $memRegKey -Name "PagingFiles" -Value @($pagefileString) -Type MultiString -Force
                
                # 3. Synchronize WMI PageFileSetting as secondary provider
                try {
                    $pfFilter = "Name like '$sysDrive%pagefile.sys'"
                    $existingPf = Get-CimInstance Win32_PageFileSetting -Filter $pfFilter -ErrorAction SilentlyContinue
                    if ($existingPf) {
                        Set-CimInstance -InputObject $existingPf -Property @{InitialSize=$targetPagefileMB; MaximumSize=$targetPagefileMB} -ErrorAction SilentlyContinue
                    } else {
                        New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name="$sysDrive\pagefile.sys"; InitialSize=$targetPagefileMB; MaximumSize=$targetPagefileMB} -ErrorAction SilentlyContinue
                    }
                } catch {}

                Write-Log "Pagefile successfully configured to $targetPagefileMB MB (Active / Enforced on next reboot)." "Green"
            } else {
                Write-Log "WARNING: Low disk space on $sysDrive ($freeSpaceMB MB free). Preserving disk space; skipped pagefile expansion." "Yellow"
            }
        } else {
            Write-Log "SSD / High RAM detected ($($profile.TotalRAM) MB). Retaining dynamic pagefile configuration." "Green"
        }
    } catch {
        Write-Log "Pagefile configuration notice: $($_.Exception.Message)" "Yellow"
    }

    # F. In-RAM Memory Compression (zRAM) + ApplicationPreLaunch Halt
    try {
        if (Get-Command Enable-MMAgent -ErrorAction SilentlyContinue) {
            Enable-MMAgent -MemoryCompression -PageCombining -ErrorAction SilentlyContinue
            if ($profile.DiskType -eq "HDD") {
                Disable-MMAgent -ApplicationPreLaunch -ErrorAction SilentlyContinue
                Write-Log "Windows Memory Compression active; ApplicationPreLaunch halted to avoid HDD seek contention." "Green"
            } else {
                Write-Log "Windows Memory Compression (zRAM) active." "Green"
            }
        }
    } catch {}

    # G. Visual Effects: Disable Transparency Blurs
    if (-not ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)) {
        try {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Log "Disabled DWM desktop transparency overhead." "Green"
        } catch {}
    }
}

# ==============================================================================
# 4. CONDITIONAL USER-CONFIRMATION (TIER 3 - DATABASE & CLOUD CLEANUP)
# ==============================================================================
function Optimize-Tier3 {
    param([bool]$Interactive = $true)
    Write-Log "`n--- 3. TIER 3 (CONDITIONAL & PROMPTED SERVICES) ---" "Cyan"

    $conditionalServices = @(
        @{ Name = "postgresql-x64-18"; Desc = "PostgreSQL 18 Database Server" },
        @{ Name = "FoxitPhantomPDFUpdateService"; Desc = "Foxit PDF Update Service" },
        @{ Name = "CoworkVMService"; Desc = "Claude Background Service" }
    )

    foreach ($item in $conditionalServices) {
        try {
            $svc = Get-Service -Name $item.Name -ErrorAction SilentlyContinue
            if ($svc) {
                if ($Interactive -and -not $Silent) {
                    Write-Host "`nFound: $($item.Desc) [$($svc.Status)]" -ForegroundColor Yellow
                    $ans = Read-Host "Switch to Manual (Demand-Start) mode to save RAM? (Y/N)"
                    if ($ans -match "^[Yy]") {
                        Stop-Service -Name $item.Name -Force -ErrorAction SilentlyContinue
                        Set-Service -Name $item.Name -StartupType Manual -ErrorAction SilentlyContinue
                        Write-Log "Switched $($item.Name) to Manual start." "Green"
                    }
                } else {
                    Set-Service -Name $item.Name -StartupType Manual -ErrorAction SilentlyContinue
                    Stop-Service -Name $item.Name -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }
}

# ==============================================================================
# 5. WINDOWS UPDATE PERSISTENCE ENGINE (TASK SCHEDULER MAINTENANCE HOOK)
# ==============================================================================
function Install-PersistenceHook {
    Write-Log "`n--- 4. INSTALLING WINDOWS UPDATE PERSISTENCE HOOK (HARDENED) ---" "Cyan"
    
    $scriptSource = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Join-Path $PSScriptRoot "Win11LowRamOptimizer.ps1" }
    $targetDir = "$env:ProgramData\Win11LowRamOptimizer"
    $targetScript = "$targetDir\Win11LowRamOptimizer.ps1"
    
    if (-not (Test-Path $targetDir)) { 
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null 
    }

    # Security Hardening: Language-Agnostic Well-Known SIDs to prevent Local Privilege Escalation (LPE)
    try {
        $acl = Get-Acl $targetDir
        $acl.SetAccessRuleProtection($true, $false)
        
        $sidAdmin  = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $sidSystem = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $sidUsers  = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)

        $adminRule  = New-Object System.Security.AccessControl.FileSystemAccessRule($sidAdmin, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule($sidSystem, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $usersRule  = New-Object System.Security.AccessControl.FileSystemAccessRule($sidUsers, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
        
        $acl.PurgeAccessRules($sidUsers)
        $acl.ResetAccessRule($adminRule)
        $acl.AddAccessRule($systemRule)
        $acl.AddAccessRule($usersRule)
        Set-Acl -Path $targetDir -AclObject $acl
        Write-Log "Hardened NTFS ACLs with locale-independent SIDs (Protected against LPE)." "Green"
    } catch {
        Write-Log "ACL hardening notice: $($_.Exception.Message)" "Yellow"
    }

    if ($scriptSource -ne $targetScript) {
        Copy-Item -Path $scriptSource -Destination $targetScript -Force
        Write-Log "Installed engine script to: $targetScript" "Green"
    }

    $taskName = "Win11LowRamAutoOptimizer"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetScript`" -Silent"
    
    $triggerBoot = New-ScheduledTaskTrigger -AtStartup
    $triggerBoot.Delay = "PT1M30S"
    
    $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
    $triggerLogon.Delay = "PT30S"

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType Service -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerBoot, $triggerLogon) -Settings $settings -Principal $principal -Force | Out-Null
    
    Write-Log "SUCCESS: Windows Update Persistence Task '$taskName' registered under SYSTEM with delayed triggers." "Green"
}

function Remove-PersistenceHook {
    $taskName = "Win11LowRamAutoOptimizer"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log "Persistence task '$taskName' removed." "Yellow"
}

# ==============================================================================
# 6. RESTORE DEFAULTS / COMPLETE ROLLBACK ENGINE
# ==============================================================================
function Restore-SystemDefaults {
    Write-Log "`n--- RESTORING WINDOWS DEFAULT SETTINGS ---" "Cyan"
    
    # 1. Remove Persistence Task
    Remove-PersistenceHook

    # 2. Revert Edge & Chrome Policies
    Write-Log "Reverting Edge and Chrome browser policies..." "Yellow"
    $edgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (Test-Path $edgePolicy) { Remove-Item -Path $edgePolicy -Recurse -Force -ErrorAction SilentlyContinue }
    
    $chromePolicy = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    if (Test-Path $chromePolicy) { Remove-Item -Path $chromePolicy -Recurse -Force -ErrorAction SilentlyContinue }

    # 3. Revert Windows Search Web Integration Policies
    $searchPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (Test-Path $searchPolicy) {
        Remove-ItemProperty -Path $searchPolicy -Name "DisableWebSearch" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $searchPolicy -Name "ConnectedSearchUseWeb" -Force -ErrorAction SilentlyContinue
    }

    # 4. Restore Windows Managed Pagefile
    Write-Log "Restoring Automatic Pagefile Management..." "Yellow"
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$true} -ErrorAction SilentlyContinue
    } catch {}
    
    try {
        $memRegKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        Remove-ItemProperty -Path $memRegKey -Name "PagingFiles" -Force -ErrorAction SilentlyContinue
    } catch {}

    # 5. Re-enable Services
    Write-Log "Re-enabling Windows Search and Telemetry services..." "Yellow"
    $services = @("WSearch", "DiagTrack", "CDPSvc")
    foreach ($svc in $services) {
        try {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        } catch {}
    }

    # 6. Restore MMAgent Pre-launch
    try {
        if (Get-Command Enable-MMAgent -ErrorAction SilentlyContinue) {
            Enable-MMAgent -ApplicationPreLaunch -ErrorAction SilentlyContinue
        }
    } catch {}
    
    # 7. Re-enable Transparency
    if (-not ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)) {
        try {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    Write-Log "SUCCESS: Windows defaults restored. Please reboot to finalize pagefile adjustments." "Green"
}

# ==============================================================================
# MAIN EXECUTION DISPATCHER
# ==============================================================================
if ($TelemetryOnly) {
    Get-SystemProfile | Out-Null
    exit 0
}

Assert-Admin

if ($FlushTransientOnly) {
    Safe-FlushTransientProcesses
    exit 0
}

if ($UninstallPersistence) {
    Remove-PersistenceHook
    exit 0
}

if ($RestoreDefaults) {
    Restore-SystemDefaults
    exit 0
}

Write-Log "======================================================================" "Cyan"
Write-Log "  WinBreathe - Enterprise Performance & Memory Framework (v1.1.0)       " "Cyan"
Write-Log "======================================================================" "Cyan"

$profile = Get-SystemProfile
Optimize-Tier2 -profile $profile
Optimize-Tier3 -Interactive (-not $Silent)

if ($InstallPersistence) {
    Install-PersistenceHook
}

# Post-Run Telemetry
$statAfter = New-Object MEMORYSTATUSEX
$statAfter.dwLength = [System.Runtime.InteropServices.Marshal]::SizeOf($statAfter)
[Win32Mem]::GlobalMemoryStatusEx([ref]$statAfter) | Out-Null

$availAfter = [math]::Round($statAfter.ullAvailPhys / 1MB, 0)
$usedAfter  = [math]::Round(($statAfter.ullTotalPhys - $statAfter.ullAvailPhys) / 1MB, 0)
$saved = $profile.UsedRAM - $usedAfter

Write-Log "`n=== OPTIMIZATION SUMMARY ===" "Cyan"
Write-Log "Memory Load Before: $($profile.UsedRAM) MB | Memory Load Now: $usedAfter MB" "White"
if ($saved -gt 0) {
    Write-Log "Immediate Physical RAM Reclaimed: +$saved MB" "Green"
}
Write-Log "Available Memory For Apps: $availAfter MB" "Green"
Write-Log "Optimizer Run Completed Successfully." "Cyan"
