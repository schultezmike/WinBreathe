# ==============================================================================
# WinBreathe.Engine.psm1 - Core Optimization, Telemetry & Guard Module (v2.3.0)
# Designed for Windows 11 / 10 (4-16 GB RAM, Mechanical HDDs & AI Dev Stacks)
# License: MIT | Pure PowerShell 5.1+ | Zero External Dependencies
# ==============================================================================

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ------------------------------------------------------------------------------
# Native system memory readings; versioned to coexist with older imported modules.
# ------------------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'WinBreatheV220.Win32Mem').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace WinBreatheV220 {
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
    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool GetPerformanceInfo(ref WBPERFORMANCE_INFORMATION info, uint size);
}
[StructLayout(LayoutKind.Sequential)]
public struct WBPERFORMANCE_INFORMATION {
    public uint cb;
    public UIntPtr CommitTotal, CommitLimit, CommitPeak;
    public UIntPtr PhysicalTotal, PhysicalAvailable, SystemCache;
    public UIntPtr KernelTotal, KernelPaged, KernelNonpaged, PageSize;
    public uint HandleCount, ProcessCount, ThreadCount;
}
}
"@ -ErrorAction Stop
}

# ------------------------------------------------------------------------------
# Paths & Directories
# ------------------------------------------------------------------------------
function Get-WBPaths {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $dataDir    = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "WinBreathe"
    $backupDir  = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) ("WinBreathe-State\" + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    $reportDir  = Join-Path $dataDir "reports"
    $logFile    = Join-Path $dataDir "winbreathe.log"
    $configFile = Join-Path (Join-Path $moduleRoot "config") "tweaks.json"

    foreach ($dir in @($dataDir, $reportDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    return [PSCustomObject]@{
        RootDir      = $moduleRoot
        DataDir      = $dataDir
        BackupDir    = $backupDir
        ReportDir    = $reportDir
        LogFile      = $logFile
        LatestBackup = (Join-Path $backupDir "latest.json")
        ConfigFile   = $configFile
    }
}

function Write-WBLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = "INFO"
    )
    $paths = Get-WBPaths
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $paths.LogFile -Value $line -ErrorAction SilentlyContinue

    $color = switch ($Level) {
        "OK"      { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "PREVIEW" { "Magenta" }
        "HEAD"    { "Cyan" }
        default   { "Gray" }
    }
    Write-Host $line -ForegroundColor $color
}

function Test-WBAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ------------------------------------------------------------------------------
# Catalog Loader
# ------------------------------------------------------------------------------
$script:CachedCatalog = $null

function Get-WBTweakCatalog {
    param([switch]$ForceReload)
    if ($null -eq $script:CachedCatalog -or $ForceReload) {
        $paths = Get-WBPaths
        if (-not (Test-Path $paths.ConfigFile)) {
            throw "Tweak catalog not found at: $($paths.ConfigFile)"
        }
        $raw = Get-Content -Path $paths.ConfigFile -Raw -Encoding UTF8
        $script:CachedCatalog = $raw | ConvertFrom-Json
    }
    return $script:CachedCatalog
}

# ------------------------------------------------------------------------------
# Hardware & Memory Telemetry
# ------------------------------------------------------------------------------
function Get-WBMemorySnapshot {
    $stat = New-Object WinBreatheV220.MEMORYSTATUSEX
    $stat.dwLength = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($stat)
    if (-not [WinBreatheV220.Win32Mem]::GlobalMemoryStatusEx([ref]$stat)) {
        throw 'Windows memory query failed. No memory reading is available.'
    }

    $totalMB  = [int][math]::Round($stat.ullTotalPhys / 1MB, 0)
    $availMB  = [int][math]::Round($stat.ullAvailPhys / 1MB, 0)
    $usedMB   = $totalMB - $availMB
    # GetPerformanceInfo exposes system-wide commit/pools. MEMORYSTATUSEX's
    # pagefile fields may instead be limited by the calling process/job.
    $perf = New-Object WinBreatheV220.WBPERFORMANCE_INFORMATION
    $perf.cb = [uint32][Runtime.InteropServices.Marshal]::SizeOf($perf)
    if (-not [WinBreatheV220.Win32Mem]::GetPerformanceInfo([ref]$perf, $perf.cb)) {
        throw 'Windows system commit query failed. Memory Watch cannot assess pressure.'
    }
    $pageBytes = [double]$perf.PageSize.ToUInt64()
    $commitTotalMB = [math]::Round($perf.CommitLimit.ToUInt64() * $pageBytes / 1MB, 2)
    $commitUsedMB = [math]::Round($perf.CommitTotal.ToUInt64() * $pageBytes / 1MB, 2)
    $commitAvailMB = [math]::Max(0, $commitTotalMB - $commitUsedMB)

    return [PSCustomObject]@{
        LoadPercent   = [int]$stat.dwMemoryLoad
        TotalRAMMB    = $totalMB
        UsedRAMMB     = $usedMB
        AvailRAMMB    = $availMB
        CommitTotalMB = $commitTotalMB
        CommitUsedMB  = $commitUsedMB
        CommitAvailMB = $commitAvailMB
        KernelPagedMB = [math]::Round($perf.KernelPaged.ToUInt64() * $pageBytes / 1MB, 2)
        KernelNonpagedMB = [math]::Round($perf.KernelNonpaged.ToUInt64() * $pageBytes / 1MB, 2)
        CollectedAtUTC = [DateTimeOffset]::UtcNow.ToString('o')
        Timestamp     = (Get-Date -Format "HH:mm:ss")
    }
}

$script:CachedHardwareInfo = $null

function Get-WBSystemProfile {
    param([switch]$RefreshHardware)
    $mem = Get-WBMemorySnapshot

    if ($null -eq $script:CachedHardwareInfo -or $RefreshHardware) {
        $sysDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\') } else { "C:" }
        $driveLetter = $sysDrive.TrimEnd(':')

        $mediaType = "Unspecified"
        $diskModel = "System Disk"
        try {
            $part = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop
            if ($part) {
                $disk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $part.DiskNumber } | Select-Object -First 1
                # An unrelated first disk cannot establish the system drive's
                # media type. Leave it unknown when no exact match is found.
                if ($disk) {
                    $mediaType = [string]$disk.MediaType
                    $diskModel = [string]$disk.FriendlyName
                }
            }
        } catch {
            # Win7 has no Storage module. WMI supplies the model; do not guess SSD/HDD.
            $disk = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($disk) { $diskModel = [string]$disk.Model }
        }

        $vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sysDrive'" -ErrorAction SilentlyContinue
        $freeDiskGB  = if ($vol) { [math]::Round($vol.FreeSpace / 1GB, 1) } else { 0.0 }
        $totalDiskGB = if ($vol) { [math]::Round($vol.Size / 1GB, 1) } else { 0.0 }

        # Account for existing pagefile.sys on the system drive (WB-06)
        $pfPath = "$sysDrive\pagefile.sys"
        $existingPfGB = 0.0
        $pfFile = Get-Item -Path $pfPath -Force -ErrorAction SilentlyContinue
        if ($pfFile) {
            $existingPfGB = [math]::Round($pfFile.Length / 1GB, 1)
        }

        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if (-not $os -or $os.BuildNumber -notmatch '^\d+$') { throw 'Cannot determine the Windows version; compatibility decisions have been stopped.' }
        $osCaption = $os.Caption
        $osBuild   = $os.BuildNumber

        $osVer = [System.Environment]::OSVersion.Version
        $osFamily = "Win11"
        if ($osCaption -match "Windows 7" -or ($osVer.Major -eq 6 -and $osVer.Minor -eq 1)) {
            $osFamily = "Win7"
        } elseif ($osCaption -match "Windows 8" -or ($osVer.Major -eq 6 -and ($osVer.Minor -eq 2 -or $osVer.Minor -eq 3))) {
            $osFamily = "Win8"
        } elseif ($osCaption -match "Windows 10" -or ($osVer.Major -ge 10 -and [int]$osBuild -lt 22000)) {
            $osFamily = "Win10"
        } elseif ($osCaption -match "Windows 11" -or ($osVer.Major -ge 10 -and [int]$osBuild -ge 22000)) {
            $osFamily = "Win11"
        }

        $isHDD    = ($mediaType -eq "HDD")
        $isLowRAM = ($mem.TotalRAMMB -le 12288)

        $recommendedProfile = "Balanced"
        if ($mem.TotalRAMMB -le 6144 -or ($isHDD -and $mem.TotalRAMMB -le 8192)) {
            $recommendedProfile = "Balanced"
        } elseif ($mem.TotalRAMMB -gt 16384 -and -not $isHDD) {
            $recommendedProfile = "Conservative"
        }

        $script:CachedHardwareInfo = [PSCustomObject]@{
            OSCaption          = $osCaption
            OSBuild            = $osBuild
            OSFamily           = $osFamily
            SystemDrive        = $sysDrive
            DiskModel          = $diskModel
            DiskMediaType      = $mediaType
            IsHDD              = $isHDD
            IsLowRAM           = $isLowRAM
            FreeDiskGB         = $freeDiskGB
            EffectiveFreeGB    = [math]::Round($freeDiskGB + $existingPfGB, 1)
            TotalDiskGB        = $totalDiskGB
            ExistingPagefileGB = $existingPfGB
            RecommendedProfile = $recommendedProfile
        }
    }

    $hw = $script:CachedHardwareInfo
    $activeFamily  = $hw.OSFamily
    $activeCaption = $hw.OSCaption

    return [PSCustomObject]@{
        OSCaption          = $activeCaption
        OSBuild            = $hw.OSBuild
        OSFamily           = $activeFamily
        SystemDrive        = $hw.SystemDrive
        DiskModel          = $hw.DiskModel
        DiskMediaType      = $hw.DiskMediaType
        IsHDD              = $hw.IsHDD
        IsLowRAM           = $hw.IsLowRAM
        FreeDiskGB         = $hw.FreeDiskGB
        EffectiveFreeGB    = $hw.EffectiveFreeGB
        TotalDiskGB        = $hw.TotalDiskGB
        ExistingPagefileGB = $hw.ExistingPagefileGB
        RecommendedProfile = $hw.RecommendedProfile
        TotalRAMMB         = $mem.TotalRAMMB
        UsedRAMMB          = $mem.UsedRAMMB
        AvailRAMMB         = $mem.AvailRAMMB
        LoadPercent        = $mem.LoadPercent
        CommitTotalMB      = $mem.CommitTotalMB
        CommitUsedMB       = $mem.CommitUsedMB
        CommitAvailMB      = $mem.CommitAvailMB
        KernelPagedMB      = $mem.KernelPagedMB
        KernelNonpagedMB   = $mem.KernelNonpagedMB
    }
}

# ------------------------------------------------------------------------------
# Context-Aware Registry Helpers (WB-07: Resolves interactive user when SYSTEM)
# ------------------------------------------------------------------------------
function Resolve-WBRegistryPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -notmatch '^HKCU:\\') {
        return $Path
    }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($currentSid -eq "S-1-5-18") {
        # Running as LocalSystem: resolve active logged-on user's hive in HKEY_USERS
        try {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            if ($cs -and $cs.UserName) {
                $ntAccount = New-Object System.Security.Principal.NTAccount($cs.UserName)
                $userSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
                if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
                    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
                }
                if (Test-Path "HKU:\$userSid") {
                    return ($Path -replace '^HKCU:\\', "HKU:\$userSid\")
                }
            }
        } catch { throw "Interactive-user registry resolution failed: $($_.Exception.Message)" }
        throw 'No interactive user hive available. Per-user changes were not applied.'
    }
    return $Path
}

function Get-WBRegistryState {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Name)
    $resolved = Resolve-WBRegistryPath -Path $Path
    try { $key = Get-Item -LiteralPath $resolved -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return [pscustomobject]@{ Exists=$false; Value=$null; Kind='Unknown' } }
    if ($key.GetValueNames() -notcontains $Name) { return [pscustomobject]@{ Exists=$false; Value=$null; Kind='Unknown' } }
    # Preserve raw ExpandString data, not the expanded environment-dependent value.
    return [pscustomobject]@{ Exists=$true; Value=$key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); Kind=$key.GetValueKind($Name).ToString() }
}

function Set-WBRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [string]$Kind = "DWord"
    )
    $resolved = Resolve-WBRegistryPath -Path $Path
    if (-not (Test-Path $resolved)) {
        New-Item -Path $resolved -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -Path $resolved -Name $Name -Value $Value -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
}

function Remove-WBRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $resolved = Resolve-WBRegistryPath -Path $Path
    if (Test-Path $resolved) {
        $key = Get-Item -Path $resolved -ErrorAction Stop
        if ($key.GetValueNames() -contains $Name) {
            Remove-ItemProperty -Path $resolved -Name $Name -Force -ErrorAction Stop
        }
    }
}

# ------------------------------------------------------------------------------
# Condition & Target Value Evaluation
# ------------------------------------------------------------------------------
function Test-WBTweakCondition {
    param(
        [Parameter(Mandatory = $true)]$Tweak,
        [Parameter(Mandatory = $true)]$SysProfile
    )
    if ($Tweak.PSObject.Properties.Name -contains "supportedOS" -and $null -ne $Tweak.supportedOS) {
        if (-not ($Tweak.supportedOS -contains $SysProfile.OSFamily)) {
            return $false
        }
    }
    if (-not ($Tweak.PSObject.Properties.Name -contains "condition") -or [string]::IsNullOrEmpty($Tweak.condition)) {
        return $true
    }
    switch ($Tweak.condition) {
        "hddOnly"     { return [bool]$SysProfile.IsHDD }
        "lowRamOrHdd" { return ([bool]$SysProfile.IsLowRAM -or [bool]$SysProfile.IsHDD) }
        default       { return $true }
    }
}

function Get-WBEntryTargetValue {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [string]$ProfileName = "Balanced"
    )
    if ($Entry.PSObject.Properties.Name -contains "valueByProfile" -and $null -ne $Entry.valueByProfile) {
        if ($Entry.valueByProfile.PSObject.Properties.Name -contains $ProfileName) {
            return $Entry.valueByProfile.$ProfileName
        }
    }
    return $Entry.value
}

function Get-WBAutomaticPagefileState {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    return [PSCustomObject]@{ Exists = $true; Value = [bool]$cs.AutomaticManagedPagefile }
}

function Set-WBAutomaticPagefile {
    param([bool]$Enabled)
    Get-CimInstance Win32_ComputerSystem -ErrorAction Stop |
        Set-CimInstance -Property @{ AutomaticManagedPagefile = $Enabled } -ErrorAction Stop | Out-Null
}

function Get-WBTargetPagefileMB {
    param([Parameter(Mandatory = $true)]$SysProfile)
    $installedGB = [math]::Max(4.0, [math]::Round($SysProfile.TotalRAMMB / 1024.0, 0))
    $calcMB = [int]($installedGB * 1024 * 1.5)
    return [int][math]::Min([math]::Max($calcMB, 4096), 12288)
}

# ------------------------------------------------------------------------------
# Live Drift Detection & Tweak State Inspection
# ------------------------------------------------------------------------------
function Test-WBTweakState {
    param(
        [string]$ProfileName = "Balanced",
        [string]$TargetOS = ""
    )
    $catalog    = Get-WBTweakCatalog
    $sysProfile = Get-WBSystemProfile
    if (-not [string]::IsNullOrEmpty($TargetOS)) {
        $sysProfile = [PSCustomObject]@{
            OSCaption          = switch ($TargetOS) {
                "Win7"  { "Microsoft Windows 7 Professional" }
                "Win8"  { "Microsoft Windows 8.1 Pro" }
                "Win10" { "Microsoft Windows 10 Pro" }
                "Win11" { "Microsoft Windows 11 Enterprise" }
                default { $sysProfile.OSCaption }
            }
            OSBuild            = $sysProfile.OSBuild
            OSFamily           = $TargetOS
            SystemDrive        = $sysProfile.SystemDrive
            DiskModel          = $sysProfile.DiskModel
            DiskMediaType      = $sysProfile.DiskMediaType
            IsHDD              = $sysProfile.IsHDD
            IsLowRAM           = $sysProfile.IsLowRAM
            FreeDiskGB         = $sysProfile.FreeDiskGB
            EffectiveFreeGB    = $sysProfile.EffectiveFreeGB
            TotalDiskGB        = $sysProfile.TotalDiskGB
            ExistingPagefileGB = $sysProfile.ExistingPagefileGB
            RecommendedProfile = $sysProfile.RecommendedProfile
            TotalRAMMB         = $sysProfile.TotalRAMMB
            UsedRAMMB          = $sysProfile.UsedRAMMB
            AvailRAMMB         = $sysProfile.AvailRAMMB
            LoadPercent        = $sysProfile.LoadPercent
            CommitTotalMB      = $sysProfile.CommitTotalMB
            CommitUsedMB       = $sysProfile.CommitUsedMB
        }
    }
    $mmAgent      = $null
    $mmPermission = $false
    if (Get-Command Get-MMAgent -ErrorAction SilentlyContinue) {
        try {
            $mmAgent = Get-MMAgent -ErrorAction Stop
        } catch {
            if ($_.CategoryInfo.Category -eq 'PermissionDenied' -or $_.Exception.Message -match 'Access is denied') {
                $mmPermission = $true
            }
        }
    }

    $results = @()
    foreach ($tweak in $catalog.tweaks) {
        $applicable = Test-WBTweakCondition -Tweak $tweak -SysProfile $sysProfile
        $inProfile  = ($tweak.profiles -contains $ProfileName)
        $isApplied  = $false
        $curText    = ""
        $tgtText    = ""

        switch ($tweak.type) {
            "registry" {
                $allMatch = $true
                $curParts = @()
                $tgtParts = @()
                foreach ($entry in $tweak.entries) {
                    $targetVal = Get-WBEntryTargetValue -Entry $entry -ProfileName $ProfileName
                    try { $regState = Get-WBRegistryState -Path $entry.path -Name $entry.name }
                    catch { $allMatch = $null; $curParts += "$($entry.name)=Could Not Verify"; continue }
                    $tgtParts += "$($entry.name)=$targetVal"
                    if ($regState.Exists -and ([string]$regState.Value -eq [string]$targetVal)) {
                        $curParts += "$($entry.name)=$($regState.Value)"
                    } else {
                        if ($null -ne $allMatch) { $allMatch = $false }
                        $curValStr = if ($regState.Exists) { [string]$regState.Value } else { "Not Set" }
                        $curParts += "$($entry.name)=$curValStr"
                    }
                }
                $isApplied = $allMatch
                $curText   = ($curParts -join ", ")
                $tgtText   = ($tgtParts -join ", ")
            }
            "service" {
                $svc = Get-Service -Name $tweak.service -ErrorAction SilentlyContinue
                $tgtText = $tweak.startupType
                if ($null -eq $svc) {
                    $applicable = $false
                    $curText    = "Service Not Installed"
                } else {
                    $curText   = [string]$svc.StartType
                    $isApplied = ($curText -eq $tweak.startupType)
                }
            }
            "mmagent" {
                $propName = $tweak.feature
                $tgtText  = [string]$tweak.enabled
                if (-not $applicable) {
                    $curText   = "Feature Not Available"
                    $isApplied = $false
                } elseif ($null -eq $mmAgent -or -not ($mmAgent.PSObject.Properties.Name -contains $propName)) {
                    $curText   = if ($mmPermission) { "Requires Admin" } else { "Could Not Verify" }
                    $isApplied = $null
                } else {
                    $curVal    = [bool]$mmAgent.$propName
                    $curText   = [string]$curVal
                    $isApplied = ($curVal -eq [bool]$tweak.enabled)
                }
            }
            "pagefile" {
                $targetMB = Get-WBTargetPagefileMB -SysProfile $sysProfile
                $mmPath   = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                try {
                    $autoReg = Get-WBAutomaticPagefileState
                    $pfReg = Get-WBRegistryState -Path $mmPath -Name "PagingFiles"
                } catch {
                    $curText = 'Could Not Verify'
                    $tgtText = "Fixed $targetMB MB"
                    $isApplied = $null
                    break
                }
                $tgtText  = "Fixed $targetMB MB"

                $pfValStr = if ($pfReg.Exists -and $pfReg.Value) { ($pfReg.Value -join "; ") } else { "Auto" }
                $curText  = $pfValStr

                $expected = "$($sysProfile.SystemDrive)\pagefile.sys $targetMB $targetMB"
                if (@($pfReg.Value).Count -eq 1 -and $pfValStr -ieq $expected -and $autoReg.Exists -and -not [bool]$autoReg.Value) {
                    $isApplied = $true
                } else {
                    $isApplied = $false
                }
            }
        }

        $stateLabel = if (-not $applicable) {
            "NotApplicable"
        } elseif ($null -eq $isApplied) {
            "Unknown"
        } elseif ($isApplied) {
            "Applied"
        } else {
            "Default"
        }

        $results += [PSCustomObject]@{
            Id           = $tweak.id
            Category     = $tweak.category
            Title        = $tweak.title
            Description  = $tweak.description
            Impact       = $tweak.impact
            Risk         = $tweak.risk
            InProfile    = $inProfile
            Applicable   = $applicable
            State        = $stateLabel
            IsApplied    = $isApplied
            CurrentValue = $curText
            TargetValue  = $tgtText
        }
    }

    return $results
}

# ------------------------------------------------------------------------------
# Snapshot & True Undo System (B5 Fix)
# ------------------------------------------------------------------------------
function Assert-WBProtectedPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $trusted = @('S-1-5-18','S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked path is not allowed: $cursor" }
        $acl = Get-Acl -LiteralPath $cursor -ErrorAction Stop
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw "Backup path is not owned by a trusted administrator: $cursor" }
        $writeMask = [Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
        foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq 'Allow' -and -not ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -and ($rule.FileSystemRights -band $writeMask) -and $rule.IdentityReference.Value -notin $trusted) {
                throw "Backup path allows untrusted writes: $cursor"
            }
        }
        # The Windows volume root can grant CreateDirectories to standard users.
        # Stop at Program Files: that directory itself was checked above.
        $programFiles = [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
        if ($cursor.TrimEnd('\') -ieq $programFiles.TrimEnd('\')) { return }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    throw 'Snapshot path must be beneath protected Program Files.'
}

function Initialize-WBBackupStore {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-WBAdmin)) { throw 'Administrator access is required to create a trusted system snapshot.' }
    $programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    $store = Join-Path $programFiles 'WinBreathe-State'
    $expected = Join-Path $store ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    if ([IO.Path]::GetFullPath($Path) -ine [IO.Path]::GetFullPath($expected)) { throw 'Unexpected backup store path.' }
    Assert-WBProtectedPath $programFiles
    foreach ($directory in @($store,$expected)) {
        if (-not [IO.Directory]::Exists($directory)) {
            $acl = New-Object Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true,$false)
            $admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
            $acl.SetOwner($admins)
            foreach ($sid in @('S-1-5-32-544','S-1-5-18')) {
                $identity = New-Object Security.Principal.SecurityIdentifier($sid)
                $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
                $acl.AddAccessRule($rule)
            }
            # Supply the DACL on creation, not after copying files into a mutable directory.
            [IO.Directory]::CreateDirectory($directory,$acl) | Out-Null
        }
        Assert-WBProtectedPath $directory
    }
}

function Assert-WBSnapshot {
    param([Parameter(Mandatory=$true)]$Snapshot)
    foreach ($field in @('SchemaVersion','UserSid','Registry','Services','MMAgent','Pagefile')) {
        if ($Snapshot.PSObject.Properties.Name -notcontains $field) { throw "Incomplete snapshot: $field" }
    }
    if ($Snapshot.SchemaVersion -ne 3 -or $Snapshot.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        throw 'Snapshot version or user identity does not match. Older backups are preserved but require manual review.'
    }
    $catalog = Get-WBTweakCatalog
    $registry = @{}
    foreach ($t in $catalog.tweaks) {
        if ($t.type -eq 'registry') { foreach ($entry in $t.entries) { $registry[($entry.path.TrimEnd('\') + '|' + $entry.name)] = $true } }
    }
    $seen = @{}
    foreach ($reg in $Snapshot.Registry) {
        $key = $reg.Path.TrimEnd('\') + '|' + $reg.Name
        if (-not $registry.ContainsKey($key) -or $seen.ContainsKey($key)) { throw 'Snapshot contains an unknown or duplicate registry target.' }
        $seen[$key] = $true
        if ($reg.Exists -isnot [bool] -or $reg.Kind -notin @('DWord','QWord','String','ExpandString','MultiString','Binary','None')) { throw 'Invalid registry snapshot type.' }
    }
    if ($seen.Count -ne $registry.Count) { throw 'Snapshot is missing required registry entries.' }
    $seenServices = @{}
    foreach ($svc in $Snapshot.Services) {
        $allowed = @($catalog.tweaks | Where-Object { $_.type -eq 'service' -and $_.service -ieq $svc.Name }).Count -gt 0
        if (-not $allowed -or [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($svc.Name) -or $svc.StartType -notin @('Automatic','Manual','Disabled','AutomaticDelayedStart') -or $svc.Status -notin @('Running','Stopped')) {
            throw 'Invalid service snapshot target or state.'
        }
        if ($seenServices.ContainsKey($svc.Name)) { throw 'Duplicate service snapshot target.' }
        $seenServices[$svc.Name] = $true
    }
    if ($Snapshot.MMAgent) {
        foreach ($prop in $Snapshot.MMAgent.PSObject.Properties) {
            if ($prop.Name -notin @('MemoryCompression','PageCombining','ApplicationPreLaunch') -or $prop.Value -isnot [bool]) { throw 'Invalid memory-feature snapshot.' }
        }
    }
    if (-not $Snapshot.Pagefile) { throw 'Snapshot is missing the pagefile state.' }
    if ($Snapshot.Pagefile) {
        foreach ($flag in @('AutoExists','AutoValue','PfExists')) { if ($Snapshot.Pagefile.$flag -isnot [bool]) { throw 'Invalid pagefile flags.' } }
        if (-not $Snapshot.Pagefile.AutoExists) { throw 'Automatic pagefile state was not captured.' }
        if ($Snapshot.Pagefile.PfExists) {
            foreach ($value in $Snapshot.Pagefile.PfValue) {
                if ($value -notmatch '^(?:[A-Za-z]:|\?:)\\[^\x00-\x1f"<>|*?]+(?:\s+\d+\s+\d+)?$') { throw 'Invalid pagefile path.' }
            }
        }
    }
}

function Enter-WBOperation {
    # Reentrant within this module invocation; exclusive across app instances.
    $current = Get-Variable -Name WBOperationLock -Scope Script -ErrorAction SilentlyContinue
    if ($current -and $null -ne $current.Value) { return $null }
    $path = (Get-WBPaths).BackupDir
    Initialize-WBBackupStore -Path $path
    $lockPath = Join-Path $path 'operation.lock'
    if (Test-Path -LiteralPath $lockPath) { Assert-WBProtectedPath -Path $lockPath }
    $stream = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $script:WBOperationLock = $stream
    return $stream
}

function Exit-WBOperation {
    param($Lease)
    if ($null -ne $Lease) { $Lease.Dispose(); $script:WBOperationLock = $null }
}

function New-WBSnapshot {
    param([string]$Label = "Pre-Optimization")
    $lease = $null
    try {
    $lease = Enter-WBOperation
    $paths      = Get-WBPaths
    Initialize-WBBackupStore -Path $paths.BackupDir
    $catalog    = Get-WBTweakCatalog
    $sysProfile = Get-WBSystemProfile

    $regBackup = @()
    $svcBackup = @()
    $mmBackup  = @{}
    # One successful enumeration distinguishes missing services from a failed
    # per-name query; an unreadable inventory cannot become an empty backup.
    $serviceInventory = @(Get-Service -ErrorAction Stop)

    foreach ($tweak in $catalog.tweaks) {
        if ($tweak.type -eq "registry") {
            foreach ($entry in $tweak.entries) {
                $st = Get-WBRegistryState -Path $entry.path -Name $entry.name
                $regBackup += [PSCustomObject]@{
                    Path   = $entry.path
                    Name   = $entry.name
                    Kind   = if ($st.Exists -and $st.Kind -ne "Unknown") { $st.Kind } else { $entry.kind }
                    Exists = $st.Exists
                    Value  = $st.Value
                }
            }
        } elseif ($tweak.type -eq "service") {
            $svc = $serviceInventory | Where-Object { $_.Name -ieq $tweak.service } | Select-Object -First 1
            if ($svc) {
                $svcBackup += [PSCustomObject]@{
                    Name      = $tweak.service
                    StartType = [string]$svc.StartType
                    Status    = [string]$svc.Status
                }
            }
        }
    }

    if (Get-Command Get-MMAgent -ErrorAction SilentlyContinue) {
        $mm = Get-MMAgent -ErrorAction Stop
        if ($mm) {
            $mmBackup = @{
            }
            foreach ($feature in @('MemoryCompression', 'PageCombining', 'ApplicationPreLaunch')) {
                if ($mm.PSObject.Properties.Name -contains $feature) {
                    $mmBackup[$feature] = [bool]$mm.$feature
                }
            }
        }
    }

    $mmPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    $autoReg = Get-WBAutomaticPagefileState
    $pfReg   = Get-WBRegistryState -Path $mmPath -Name "PagingFiles"

    $snapshotObj = [PSCustomObject]@{
        SchemaVersion = 3
        UserSid       = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Timestamp     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Label         = $Label
        SystemDrive   = $sysProfile.SystemDrive
        Registry      = $regBackup
        Services      = $svcBackup
        MMAgent       = $mmBackup
        Pagefile      = [PSCustomObject]@{
            AutoExists = $autoReg.Exists
            AutoValue  = $autoReg.Value
            PfExists   = $pfReg.Exists
            PfValue    = $pfReg.Value
        }
    }

    $stamp     = (Get-Date -Format "yyyyMMdd-HHmmss-fff") + "-" + [guid]::NewGuid().ToString("N")
    $file      = Join-Path $paths.BackupDir "backup-$stamp.json"
    $tmp       = "$file.tmp"
    $latestTmp = "$($paths.LatestBackup).$([guid]::NewGuid().ToString('N')).tmp"
    try {
        if (-not (Test-Path $paths.BackupDir)) {
            New-Item -ItemType Directory -Path $paths.BackupDir -Force -ErrorAction Stop | Out-Null
        }
        $json  = $snapshotObj | ConvertTo-Json -Depth 6
        if ([string]::IsNullOrEmpty($json) -or $json.Length -lt 20) {
            throw "Snapshot serialization produced invalid or empty JSON."
        }
        Assert-WBSnapshot -Snapshot ($json | ConvertFrom-Json -ErrorAction Stop)
        Set-Content -Path $tmp -Value $json -Encoding UTF8 -Force -ErrorAction Stop
        Copy-Item -Path $tmp -Destination $latestTmp -Force -ErrorAction Stop

        Move-Item -Path $tmp -Destination $file -Force -ErrorAction Stop
        if (Test-Path $paths.LatestBackup) {
            Assert-WBProtectedPath -Path $paths.LatestBackup
            # Windows PowerShell 5.1 converts $null to an empty string for this
            # .NET string argument. NullString passes a real null backup path.
            [System.IO.File]::Replace($latestTmp, $paths.LatestBackup, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [System.IO.File]::Move($latestTmp, $paths.LatestBackup)
        }

        Write-WBLog "Saved verified system state snapshot to: $file" "OK"
        return $file
    } catch {
        Write-WBLog "CRITICAL: Failed to write system snapshot: $($_.Exception.Message)" "ERROR"
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        if (Test-Path $latestTmp) { Remove-Item $latestTmp -Force -ErrorAction SilentlyContinue }
        return $null
    }
    } finally { Exit-WBOperation -Lease $lease }
}

function Restore-WBSnapshot {
    param([string]$SnapshotPath = "")
    if (-not (Test-WBAdmin)) {
        Write-WBLog "Administrator privileges required to restore snapshot." "ERROR"
        return $false
    }

    $lease = $null
    try {
    $lease = Enter-WBOperation
    $paths = Get-WBPaths
    if ([string]::IsNullOrEmpty($SnapshotPath)) {
        $SnapshotPath = $paths.LatestBackup
    }

    if (-not (Test-Path $SnapshotPath)) {
        Write-WBLog "No snapshot found at $SnapshotPath. Use -ResetDefaults to restore stock Windows settings." "WARN"
        return $false
    }

    Write-WBLog "Restoring exact pre-optimization state from: $SnapshotPath" "HEAD"
    try {
        Assert-WBProtectedPath -Path $SnapshotPath
        $snap = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        Assert-WBSnapshot -Snapshot $snap
    } catch {
        Write-WBLog "Snapshot rejected; no settings changed: $($_.Exception.Message)" 'ERROR'
        return $false
    }

    $restoreErrors = 0

    foreach ($reg in $snap.Registry) {
        try {
            if ($reg.Exists) {
                Set-WBRegistryValue -Path $reg.Path -Name $reg.Name -Value $reg.Value -Kind $reg.Kind
                Write-WBLog "Restored registry $($reg.Name) = $($reg.Value)" "INFO"
            } else {
                Remove-WBRegistryValue -Path $reg.Path -Name $reg.Name
                Write-WBLog "Removed policy key $($reg.Name) (was not present before)" "INFO"
            }
        } catch {
            Write-WBLog "Failed restoring registry $($reg.Name): $($_.Exception.Message)" "WARN"
            $restoreErrors++
        }
    }

    foreach ($svc in $snap.Services) {
        $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if (-not $s) { $restoreErrors++; Write-WBLog "Service $($svc.Name) is unavailable; restoration was incomplete." 'WARN' }
        if ($s) {
            try {
                Set-Service -Name $svc.Name -StartupType $svc.StartType -ErrorAction Stop
                if ($svc.Status -eq "Running" -and $svc.StartType -ne "Disabled") {
                    Start-Service -Name $svc.Name -ErrorAction Stop
                } elseif ($svc.Status -eq 'Stopped') {
                    Stop-Service -Name $svc.Name -ErrorAction Stop
                }
                Write-WBLog "Restored service $($svc.Name) -> $($svc.StartType)" "INFO"
            } catch {
                Write-WBLog "Failed restoring service $($svc.Name): $($_.Exception.Message)" "WARN"
                $restoreErrors++
            }
        }
    }

    if ($snap.MMAgent -and -not (Get-Command Enable-MMAgent -ErrorAction SilentlyContinue)) {
        $restoreErrors++
        Write-WBLog 'Memory settings could not be restored: MMAgent is unavailable.' 'WARN'
    }
    if ($snap.MMAgent -and (Get-Command Enable-MMAgent -ErrorAction SilentlyContinue)) {
        try {
            foreach ($feature in @('MemoryCompression', 'PageCombining', 'ApplicationPreLaunch')) {
                if ($snap.MMAgent.PSObject.Properties.Name -contains $feature) {
                    $cmdName = if ($snap.MMAgent.$feature) { 'Enable-MMAgent' } else { 'Disable-MMAgent' }
                    $cmd = Get-Command $cmdName -ErrorAction Stop
                    if (-not $cmd.Parameters.ContainsKey($feature)) { throw "Unsupported memory feature: $feature" }
                    $argsForFeature = @{ ErrorAction = 'Stop' }
                    $argsForFeature[$feature] = $true
                    & $cmd @argsForFeature
                }
            }
            Write-WBLog "Restored MMAgent memory compression & pre-launch state." "INFO"
        } catch {
            Write-WBLog "Failed restoring MMAgent state: $($_.Exception.Message)" "WARN"
            $restoreErrors++
        }
    }

    if ($snap.Pagefile) {
        $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        try {
            if ($snap.Pagefile.AutoExists) {
                Set-WBAutomaticPagefile -Enabled ([bool]$snap.Pagefile.AutoValue)
            } else {
                throw 'Snapshot does not contain the automatic pagefile state; cannot restore it safely.'
            }
            if ($snap.Pagefile.PfExists -and $null -ne $snap.Pagefile.PfValue) {
                Set-WBRegistryValue -Path $mmPath -Name "PagingFiles" -Value ([string[]]$snap.Pagefile.PfValue) -Kind "MultiString"
            } else {
                Remove-WBRegistryValue -Path $mmPath -Name "PagingFiles"
            }
            Write-WBLog "Restored pagefile configuration." "INFO"
        } catch {
            Write-WBLog "Failed restoring pagefile configuration: $($_.Exception.Message)" "WARN"
            $restoreErrors++
        }
    }

    if ($restoreErrors -gt 0) {
        Write-WBLog "Snapshot undo completed with $restoreErrors warning(s)/failure(s). Please review log output." "WARN"
        return $false
    }

    Write-WBLog "Snapshot undo completed successfully." "OK"
    return $true
    } finally { Exit-WBOperation -Lease $lease }
}

function Restore-WBStockDefaults {
    Write-WBLog 'Generic factory reset was removed because defaults vary by OS and device. Use Undo with a valid protected snapshot instead. No settings were changed.' 'ERROR'
    return $false
}

# ------------------------------------------------------------------------------
# Main Optimization Engine (Supports Profile, Specific TweakIds, and -WhatIf)
# ------------------------------------------------------------------------------
function Invoke-WBTweaks {
    param(
        [ValidateSet("Conservative", "Balanced", "Aggressive")]
        [string]$ProfileName = "Balanced",
        [string[]]$TweakIds = @(),
        [string]$TargetOS = "",
        [switch]$WhatIf,
        [switch]$SkipSnapshot,
        [switch]$SkipFlush
    )

    if (-not $WhatIf -and -not (Test-WBAdmin)) {
        Write-WBLog "Administrator privileges are required to apply optimizations. Use -WhatIf to preview." "ERROR"
        return $null
    }

    if ($SkipSnapshot -and -not $WhatIf) { throw 'Skipping the backup is no longer supported. No settings were changed.' }
    $catalog    = Get-WBTweakCatalog
    $sysProfile = Get-WBSystemProfile
    if (-not [string]::IsNullOrEmpty($TargetOS)) {
        if (-not $WhatIf) {
            Write-WBLog "SAFETY GUARD: Simulation target OS ($TargetOS) is ignored during live optimization. Live changes only apply to host OS ($($sysProfile.OSFamily))." "WARN"
            $TargetOS = ""
        } else {
            $sysProfile = [PSCustomObject]@{
                OSCaption          = switch ($TargetOS) {
                    "Win7"  { "Microsoft Windows 7 Professional (Simulated)" }
                    "Win8"  { "Microsoft Windows 8.1 Pro (Simulated)" }
                    "Win10" { "Microsoft Windows 10 Pro (Simulated)" }
                    "Win11" { "Microsoft Windows 11 Enterprise (Simulated)" }
                    default { $sysProfile.OSCaption }
                }
                OSBuild            = $sysProfile.OSBuild
                OSFamily           = $TargetOS
                SystemDrive        = $sysProfile.SystemDrive
                DiskModel          = $sysProfile.DiskModel
                DiskMediaType      = $sysProfile.DiskMediaType
                IsHDD              = $sysProfile.IsHDD
                IsLowRAM           = $sysProfile.IsLowRAM
                FreeDiskGB         = $sysProfile.FreeDiskGB
                EffectiveFreeGB    = $sysProfile.EffectiveFreeGB
                TotalDiskGB        = $sysProfile.TotalDiskGB
                ExistingPagefileGB = $sysProfile.ExistingPagefileGB
                RecommendedProfile = $sysProfile.RecommendedProfile
                TotalRAMMB         = $sysProfile.TotalRAMMB
                UsedRAMMB          = $sysProfile.UsedRAMMB
                AvailRAMMB         = $sysProfile.AvailRAMMB
                LoadPercent        = $sysProfile.LoadPercent
                CommitTotalMB      = $sysProfile.CommitTotalMB
                CommitUsedMB       = $sysProfile.CommitUsedMB
            }
        }
    }
    $memBefore  = Get-WBMemorySnapshot

    $modeBanner = if ($WhatIf) { "DRY-RUN PREVIEW MODE (No changes will be written)" } else { "LIVE OPTIMIZATION ($ProfileName Profile)" }
    Write-WBLog "======================================================================" "HEAD"
    Write-WBLog "  WinBreathe v2.3.0 - Universal Windows Optimizer - $modeBanner" "HEAD"
    Write-WBLog "  OS: $($sysProfile.OSCaption) [$($sysProfile.OSFamily)] | RAM: $($sysProfile.TotalRAMMB) MB | Disk: $($sysProfile.DiskMediaType) ($($sysProfile.FreeDiskGB) GB Free)" "HEAD"
    Write-WBLog "======================================================================" "HEAD"

    if (@($TweakIds | Where-Object { $_ -notin @($catalog.tweaks.id) }).Count -gt 0) {
        throw 'Unknown tweak ID. No settings were changed.'
    }
    # Select tweaks to apply
    $selectedTweaks = @()
    if ($TweakIds -and $TweakIds.Count -gt 0) {
        foreach ($t in $catalog.tweaks) {
            if ($TweakIds -contains $t.id) { $selectedTweaks += $t }
        }
    } else {
        foreach ($t in $catalog.tweaks) {
            if ($t.profiles -contains $ProfileName) { $selectedTweaks += $t }
        }
    }

    if (-not $WhatIf) {
        $pressure=Get-WBMemoryPressure -Snapshot $memBefore
        if ($pressure.Level -in @('Critical','Unknown')) {
            Write-WBLog "Optimization deferred: memory assessment is $($pressure.Level). Save work, pause new workloads and investigate memory before changing settings." 'ERROR'
            return [pscustomobject]@{Profile=$ProfileName;WhatIf=$false;AppliedCount=0;SkippedCount=$selectedTweaks.Count;FailedCount=0;PreviewCount=0;Aborted=$true;BeforeRAMMB=$memBefore.UsedRAMMB;AfterRAMMB=$memBefore.UsedRAMMB;ReclaimedMB=0}
        }
    }
    $lease = $null
    try {
    if (-not $WhatIf) { $lease = Enter-WBOperation }
    if (-not $WhatIf -and -not $SkipSnapshot) {
        $snapFile = try { New-WBSnapshot -Label "Auto-Backup before $ProfileName run" } catch { $null }
        if ([string]::IsNullOrEmpty($snapFile) -or -not (Test-Path $snapFile)) {
            Write-WBLog "CRITICAL: Snapshot backup failed! Aborting optimization to prevent irreversible system state." "ERROR"
            return [PSCustomObject]@{
                Profile      = $ProfileName
                WhatIf       = $false
                AppliedCount = 0
                SkippedCount = $selectedTweaks.Count
                FailedCount  = 0
                PreviewCount = 0
                Aborted      = $true
                BeforeRAMMB  = $memBefore.UsedRAMMB
                AfterRAMMB   = $memBefore.UsedRAMMB
                ReclaimedMB  = 0
            }
        }
    }

    $appliedCount = 0
    $skippedCount = 0
    $failedCount = 0
    $previewCount = 0

    foreach ($tweak in $selectedTweaks) {
        if (-not (Test-WBTweakCondition -Tweak $tweak -SysProfile $sysProfile)) {
            Write-WBLog "SKIP [$($tweak.id)]: OS or hardware applicability condition not met on this PC." "INFO"
            $skippedCount++
            continue
        }

        switch ($tweak.type) {
            "registry" {
                $tweakSuccess = $true
                $accessDenied = $false
                foreach ($entry in $tweak.entries) {
                    $targetVal = Get-WBEntryTargetValue -Entry $entry -ProfileName $ProfileName
                    if ($WhatIf) {
                        $cur = Get-WBRegistryState -Path $entry.path -Name $entry.name
                        $curStr = if ($cur.Exists) { $cur.Value } else { "<unset>" }
                        Write-WBLog "$($tweak.id): Set $($entry.path)\$($entry.name) = $targetVal (Current: $curStr)" "PREVIEW"
                    } else {
                        try {
                            Set-WBRegistryValue -Path $entry.path -Name $entry.name -Value $targetVal -Kind $entry.kind
                        } catch {
                            Write-WBLog "Failed writing $($entry.name): $($_.Exception.Message)" "WARN"
                            if ($_.CategoryInfo.Category -eq 'PermissionDenied' -or $_.Exception -is [UnauthorizedAccessException] -or $_.Exception -is [System.Security.SecurityException]) {
                                $accessDenied = $true
                            }
                            $tweakSuccess = $false
                        }
                    }
                }
                if ($WhatIf) {
                    $previewCount++
                } elseif ($tweakSuccess) {
                    Write-WBLog "APPLIED [$($tweak.id)]: $($tweak.title)" "OK"
                    $appliedCount++
                } else {
                    Write-WBLog "FAILED [$($tweak.id)]: $($tweak.title) - one or more registry writes failed or were denied." "ERROR"
                    if ($accessDenied) {
                        Write-WBLog "Windows denied access to this setting. WinBreathe did not change its permissions. Other changes marked APPLIED are kept." "WARN"
                    }
                    $failedCount++
                }
            }
            "service" {
                $svc = Get-Service -Name $tweak.service -ErrorAction SilentlyContinue
                if ($null -eq $svc) {
                    Write-WBLog "SKIP [$($tweak.id)]: Service '$($tweak.service)' not present." "INFO"
                    $skippedCount++
                } elseif ($WhatIf) {
                    Write-WBLog "$($tweak.id): Service '$($tweak.service)' -> $($tweak.startupType) (Current: $($svc.StartType)/$($svc.Status))" "PREVIEW"
                    $previewCount++
                } else {
                    try {
                        if ($tweak.startupType -eq "Disabled" -and $svc.Status -eq "Running") {
                            Stop-Service -Name $tweak.service -ErrorAction Stop
                        }
                        Set-Service -Name $tweak.service -StartupType $tweak.startupType -ErrorAction Stop
                        Write-WBLog "APPLIED [$($tweak.id)]: $($tweak.title) ($($tweak.service) -> $($tweak.startupType))" "OK"
                        $appliedCount++
                    } catch {
                        Write-WBLog "FAILED [$($tweak.id)]: $($tweak.title) - $($_.Exception.Message)" "ERROR"
                        $failedCount++
                    }
                }
            }
            "mmagent" {
                if (-not (Get-Command Get-MMAgent -ErrorAction SilentlyContinue)) {
                    Write-WBLog "SKIP [$($tweak.id)]: MMAgent cmdlets unavailable." "WARN"
                    $skippedCount++
                } elseif ($WhatIf) {
                    Write-WBLog "$($tweak.id): Set MMAgent $($tweak.feature) = $($tweak.enabled)" "PREVIEW"
                    $previewCount++
                } else {
                    try {
                        $feat = $tweak.feature
                        if ($tweak.enabled) {
                            switch ($feat) {
                                "MemoryCompression"    { Enable-MMAgent -MemoryCompression -ErrorAction Stop }
                                "PageCombining"        { Enable-MMAgent -PageCombining -ErrorAction Stop }
                                "ApplicationPreLaunch" { Enable-MMAgent -ApplicationPreLaunch -ErrorAction Stop }
                            }
                        } else {
                            switch ($feat) {
                                "MemoryCompression"    { Disable-MMAgent -MemoryCompression -ErrorAction Stop }
                                "PageCombining"        { Disable-MMAgent -PageCombining -ErrorAction Stop }
                                "ApplicationPreLaunch" { Disable-MMAgent -ApplicationPreLaunch -ErrorAction Stop }
                            }
                        }
                        Write-WBLog "APPLIED [$($tweak.id)]: $($tweak.title)" "OK"
                        $appliedCount++
                    } catch {
                        Write-WBLog "FAILED [$($tweak.id)]: $($tweak.title) - $($_.Exception.Message)" "ERROR"
                        $failedCount++
                    }
                }
            }
            "pagefile" {
                $targetMB  = Get-WBTargetPagefileMB -SysProfile $sysProfile
                $targetGB  = [math]::Round($targetMB / 1024, 1)
                $remaining = $sysProfile.EffectiveFreeGB - $targetGB

                if ($remaining -lt 15.0) {
                    Write-WBLog "SKIP [mem.pagefile]: Insufficient disk headroom ($($sysProfile.EffectiveFreeGB) GB available)." "WARN"
                    $skippedCount++
                } elseif ($WhatIf) {
                    Write-WBLog "mem.pagefile: Configure fixed-size pagefile at $targetMB MB ($targetGB GB) on $($sysProfile.SystemDrive)" "PREVIEW"
                    $previewCount++
                } else {
                    try {
                        $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                        $pfSpec = "$($sysProfile.SystemDrive)\pagefile.sys $targetMB $targetMB"
                        Set-WBAutomaticPagefile -Enabled $false
                        Set-WBRegistryValue -Path $mmPath -Name "PagingFiles" -Value @($pfSpec) -Kind "MultiString"
                        Write-WBLog "APPLIED [mem.pagefile]: Fixed-size pagefile (restart required) at $targetMB MB ($pfSpec)" "OK"
                        $appliedCount++
                    } catch {
                        Write-WBLog "FAILED [mem.pagefile]: $($_.Exception.Message)" "ERROR"
                        $failedCount++
                    }
                }
            }
        }
    }

    # Profile application never terminates apps or hosts. SkipFlush is retained
    # for compatibility with older callers; no flush runs automatically.

    $memAfter = Get-WBMemorySnapshot
    $reclaimedMB = [math]::Max(0, ($memBefore.UsedRAMMB - $memAfter.UsedRAMMB))

    Write-WBLog "----------------------------------------------------------------------" "HEAD"
    $summaryLevel = if ($failedCount -gt 0) { 'WARN' } else { 'OK' }
    Write-WBLog "  SUMMARY: $appliedCount applied; $previewCount previewed; $failedCount failed; $skippedCount skipped" $summaryLevel
    if ($failedCount -gt 0) {
        Write-WBLog "  Completed with errors. Changes marked APPLIED are kept; review the FAILED lines for changes that could not be completed." "WARN"
    }
    Write-WBLog "  RAM Before: $($memBefore.UsedRAMMB) MB ($($memBefore.LoadPercent)%) | RAM After: $($memAfter.UsedRAMMB) MB ($($memAfter.LoadPercent)%)" "INFO"
    if ($reclaimedMB -gt 0) {
        Write-WBLog "  Observed available-memory change: +$reclaimedMB MB (includes unrelated activity; not measured savings)" "INFO"
    } elseif (-not $WhatIf) {
        Write-WBLog "  No immediate RAM reduction was observed. These settings do not guarantee lower memory use in open apps." "INFO"
    }
    Write-WBLog "----------------------------------------------------------------------" "HEAD"

    return [PSCustomObject]@{
        Profile      = $ProfileName
        WhatIf       = [bool]$WhatIf
        AppliedCount = $appliedCount
        SkippedCount = $skippedCount
        FailedCount  = $failedCount
        PreviewCount = $previewCount
        BeforeRAMMB  = $memBefore.UsedRAMMB
        AfterRAMMB   = $memAfter.UsedRAMMB
        ReclaimedMB  = $reclaimedMB
    }
    } finally { Exit-WBOperation -Lease $lease }
}

# ------------------------------------------------------------------------------
# Safe Process Inspector & Transient Host Flusher (WB-03 Protected)
# ------------------------------------------------------------------------------
function Get-WBTopProcesses {
    param([int]$Top = 18,[ValidateSet('MemoryMB','PrivateCommitMB')][string]$SortBy='MemoryMB')
    $catalog = Get-WBTweakCatalog
    $protectedSet = @{}
    foreach ($p in $catalog.protectedProcesses) {
        $protectedSet[$p.ToLowerInvariant()] = $true
    }

    $groups = Get-Process -ErrorAction SilentlyContinue |
        Group-Object -Property ProcessName |
        ForEach-Object {
            $nameLower = $_.Name.ToLowerInvariant()
            $totalWS   = ($_.Group | Measure-Object -Property WorkingSet64 -Sum).Sum
            $totalPrivate = ($_.Group | Measure-Object -Property PrivateMemorySize64 -Sum).Sum
            $ramMB     = [int][math]::Round($totalWS / 1MB, 1)
            $isProt    = (Test-WBProtectedProcessName $nameLower) -or $protectedSet.ContainsKey($nameLower)
            [PSCustomObject]@{
                AppName      = $_.Name
                ProcessCount = $_.Count
                MemoryMB     = $ramMB
                PrivateCommitMB = [math]::Round($totalPrivate/1MB,1)
                IsProtected  = $isProt
                SafetyStatus = if ($isProt) { "Protected (Untouchable)" } else { "User / App" }
            }
        } |
        Sort-Object -Property $SortBy -Descending |
        Select-Object -First $Top

    return $groups
}

function Test-WBProtectedProcessName {
    param([string]$Name)
    # This minimum cannot be removed by editing the tweak catalog.
    if($Name -match '^(chatgpt|codex.*|abos.*|node.*|python.*|vmmem.*|wsl.*|winbreathe.*|openvpn.*|wireguard.*|tailscale.*|happ|sing-box|xray|ollama.*|lm studio|lmstudio.*|llama.*|antigravity.*|claude.*|cursor.*|code|msedgewebview2|powershell|pwsh|postgres.*|redis.*|mysqld|sqlservr)$'){return $true}
    return @((Get-WBTweakCatalog).protectedProcesses) -icontains $Name
}

function Stop-WBAppGroup {
    param([Parameter(Mandatory = $true)][string]$AppName)
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($AppName)) {
        Write-WBLog 'Process wildcards are not allowed. Select one exact app name.' 'ERROR'
        return $false
    }
    if(Test-WBProtectedProcessName $AppName){Write-WBLog "BLOCKED: '$AppName' is protected development, AI, VPN or system software." 'WARN';return $false}
    $catalog = Get-WBTweakCatalog
    foreach ($p in $catalog.protectedProcesses) {
        if ($p.Equals($AppName, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-WBLog "BLOCKED: '$AppName' is in the Protected Processes safety list and cannot be terminated." "WARN"
            return $false
        }
    }

    # Additional check for msedgewebview2: never kill children of protected IDE/AI processes (WB-03)
    if ($AppName -ieq "msedgewebview2") {
        return (Invoke-WBSafeFlush)
    }

    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -ieq $AppName })
    if (-not $procs) {
        Write-WBLog "Process '$AppName' is no longer running." "INFO"
        return $false
    }

    # An unknown executable can still be an AI/development child. Fail closed if
    # ancestry cannot be read; never treat missing parent data as permission.
    try {
        $tree=@{}
        foreach($item in @(Get-CimInstance Win32_Process -ErrorAction Stop)){$tree[[int]$item.ProcessId]=$item}
        foreach($proc in $procs){
            $cursor=[int]$proc.Id;$seen=@{}
            while($cursor -ne 0){
                if($seen.ContainsKey($cursor) -or -not $tree.ContainsKey($cursor)){throw 'Process ancestry is incomplete.'}
                $seen[$cursor]=$true;$node=$tree[$cursor]
                $parent=[int]$node.ParentProcessId
                # Stop at the desktop shell: it is the root of normal user apps.
                if($cursor -ne $proc.Id -and $node.Name -ieq 'explorer.exe'){break}
                if($cursor -ne $proc.Id -and (Test-WBProtectedProcessName ([IO.Path]::GetFileNameWithoutExtension($node.Name)))){throw 'A protected application owns this process.'}
                $cursor=$parent
            }
        }
    } catch {Write-WBLog "BLOCKED: cannot safely close '$AppName'. $($_.Exception.Message)" 'WARN';return $false}

    $count = @($procs).Count
    $freedMB = [int][math]::Round((($procs | Measure-Object -Property WorkingSet64 -Sum).Sum) / 1MB, 0)
    $failures = 0
    foreach ($proc in $procs) {
        try { $proc | Stop-Process -ErrorAction Stop }
        catch { $failures++; Write-WBLog "Could not close '$AppName': $($_.Exception.Message)" 'WARN' }
    }
    Write-WBLog "Closed $($count - $failures) of $count instance(s) of '$AppName'. Prior working set: $freedMB MB; this is not guaranteed recovered RAM." 'INFO'
    return ($failures -eq 0)
}

function Invoke-WBSafeFlush {
    Write-WBLog 'Host termination was removed. No apps or Windows hosts were stopped. Standby memory is already reusable by Windows.' 'INFO'
    $mem = Get-WBMemorySnapshot
    Write-WBLog "Memory check: $($mem.LoadPercent)% used; $($mem.AvailRAMMB) MB available. This command does not trim working sets." 'INFO'
    return $true
}

# ------------------------------------------------------------------------------
# Startup Apps Manager (Run Keys + Startup Folder with Non-Destructive Disable)
# ------------------------------------------------------------------------------
function Get-WBStartupItems {
    $items = @()

    $locations = @(
        @{ Scope = "CurrentUser"; ActivePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; DisabledPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WinBreatheDisabledRun" },
        @{ Scope = "AllUsers";    ActivePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; DisabledPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\WinBreatheDisabledRun" }
    )

    foreach ($loc in $locations) {
        $activeResolved = Resolve-WBRegistryPath -Path $loc.ActivePath
        if (Test-Path $activeResolved) {
            $props = Get-ItemProperty -Path $activeResolved -ErrorAction SilentlyContinue
            if ($props) {
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {
                        $items += [PSCustomObject]@{
                            Name     = $p.Name
                            Command  = [string]$p.Value
                            Scope    = $loc.Scope
                            State    = "Enabled"
                            Source   = $loc.ActivePath
                        }
                    }
                }
            }
        }

        $disabledResolved = Resolve-WBRegistryPath -Path $loc.DisabledPath
        if (Test-Path $disabledResolved) {
            $props = Get-ItemProperty -Path $disabledResolved -ErrorAction SilentlyContinue
            if ($props) {
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {
                        $items += [PSCustomObject]@{
                            Name     = $p.Name
                            Command  = [string]$p.Value
                            Scope    = $loc.Scope
                            State    = "Disabled"
                            Source   = $loc.DisabledPath
                        }
                    }
                }
            }
        }
    }

    return $items
}

function Set-WBStartupItemState {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("CurrentUser", "AllUsers")][string]$Scope,
        [Parameter(Mandatory = $true)][bool]$Enable
    )
    $activePath   = if ($Scope -eq "AllUsers") { "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" } else { "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" }
    $disabledPath = if ($Scope -eq "AllUsers") { "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\WinBreatheDisabledRun" } else { "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WinBreatheDisabledRun" }

    if ($Enable) {
        $st = Get-WBRegistryState -Path $disabledPath -Name $Name
        if ($st.Exists) {
            Set-WBRegistryValue -Path $activePath -Name $Name -Value $st.Value -Kind $st.Kind
            Remove-WBRegistryValue -Path $disabledPath -Name $Name
            Write-WBLog "Re-enabled startup item '$Name' ($Scope)." "OK"
            return $true
        }
    } else {
        $st = Get-WBRegistryState -Path $activePath -Name $Name
        if ($st.Exists) {
            Set-WBRegistryValue -Path $disabledPath -Name $Name -Value $st.Value -Kind $st.Kind
            Remove-WBRegistryValue -Path $activePath -Name $Name
            Write-WBLog "Disabled startup item '$Name' ($Scope) (backed up for 1-click re-enable)." "OK"
            return $true
        }
    }
    return $false
}

# ------------------------------------------------------------------------------
# Hardened Windows Update Persistence Guard (WB-02: WellKnownSidType ACLs)
# ------------------------------------------------------------------------------
function Get-WBUpdateGuardStatus {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Installed = $false; TaskName = 'WinBreathe_UpdateGuard'; State = 'Unsupported on this system'; LastRunTime = 'N/A' }
    }
    $task = Get-ScheduledTask -TaskName "WinBreathe_UpdateGuard" -ErrorAction SilentlyContinue
    if (-not $task) {
        $legacy = Get-ScheduledTask -TaskName "Win11LowRamOptimizer_AutoGuard" -ErrorAction SilentlyContinue
        if ($legacy) { $task = $legacy }
    }
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue
        return [PSCustomObject]@{
            Installed   = $true
            TaskName    = $task.TaskName
            State       = [string]$task.State
            LastRunTime = if ($info -and $info.LastRunTime) { [string]$info.LastRunTime } else { "Never" }
        }
    }
    return [PSCustomObject]@{
        Installed   = $false
        TaskName    = "WinBreathe_UpdateGuard"
        State       = "Not Installed"
        LastRunTime = "N/A"
    }
}

function Install-WBUpdateGuard {
    param([ValidateSet('Conservative','Balanced','Aggressive')][string]$ProfileName = 'Balanced')
    Write-WBLog 'New Update Guard installations are disabled pending a secure installation mechanism. No files, permissions or scheduled tasks were changed. Existing tasks can be removed with -RemoveGuard.' 'WARN'
    return $false
}

function Uninstall-WBUpdateGuard {
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
        Write-WBLog 'Update Guard requires the Windows 8/8.1 or later ScheduledTasks module. No task was changed.' 'WARN'
        return $false
    }
    if (-not (Test-WBAdmin)) {
        Write-WBLog "Administrator privileges required to remove Update Guard." "ERROR"
        return $false
    }
    foreach ($name in @("WinBreathe_UpdateGuard", "Win11LowRamOptimizer_AutoGuard")) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
            Write-WBLog "Removed scheduled task: $name" "OK"
        }
    }
    return $true
}

# ------------------------------------------------------------------------------
# HTML & Markdown System Telemetry Report Exporter
# ------------------------------------------------------------------------------
function Export-WBReport {
    param([string]$ProfileName = 'Balanced')
    $paths = Get-WBPaths
    $sys = Get-WBSystemProfile
    $states = @(Test-WBTweakState -ProfileName $ProfileName)
    $apps = @(Get-WBTopProcesses -Top 10)
    $guard = Get-WBUpdateGuardStatus
    $stamp = Get-Date -Format 'dd MMM yyyy, HH:mm'
    $fileStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $mdPath = Join-Path $paths.ReportDir "WinBreathe-Report-$fileStamp.md"
    $htmlPath = Join-Path $paths.ReportDir "WinBreathe-Report-$fileStamp.html"
    # Encode dynamic values in both formats, including app names and catalog text.
    function Html($Value) { [System.Net.WebUtility]::HtmlEncode([string]$Value) }
    function ConvertTo-WBReportMarkdown($Value) { (Html $Value).Replace('|', '&#124;').Replace("`r", ' ').Replace("`n", ' ') }
    $recommended = @($states | Where-Object { $_.InProfile -and $_.Applicable })
    $matching = @($recommended | Where-Object IsApplied).Count
    $remaining = $recommended.Count - $matching
    $usedGB = '{0:N1}' -f ($sys.UsedRAMMB / 1024.0)
    $totalGB = '{0:N1}' -f ($sys.TotalRAMMB / 1024.0)
    $freeGB = '{0:N1}' -f ($sys.AvailRAMMB / 1024.0)
    $memoryText = "$usedGB of $totalGB GB in use ($($sys.LoadPercent)%); $freeGB GB available."
    $pressure = Get-WBMemoryPressure -Snapshot $sys
    $commitText = if($pressure.Level -eq 'Unknown'){'Could not verify total memory commitment and kernel pools.'}else{
        "Windows has committed $([math]::Round($sys.CommitUsedMB/1024,2)) of $([math]::Round($sys.CommitTotalMB/1024,2)) GiB ($($pressure.CommitPercent)%); $($pressure.CommitHeadroomMB) MB headroom remains. Kernel paged memory: $([math]::Round($sys.KernelPagedMB)) MB; nonpaged: $([math]::Round($sys.KernelNonpagedMB)) MB."
    }
    $advice = if ($pressure.Level -in @('Critical','Warning')) {$pressure.Summary}
    elseif ($sys.LoadPercent -ge 90) {
        'Memory is nearly full right now. Save your work and close apps or tabs you no longer need.'
    } elseif ($sys.LoadPercent -ge 75) {
        'Much of your memory is in use right now. If the PC feels slow, review the apps below and close unused tabs.'
    } else {
        'Memory has room available right now. No action is needed based on this reading alone.'
    }
    $settingsText = if ($recommended.Count -eq 0) {
        'No settings from this profile are available for this computer.'
    } else {
        "$matching of $($recommended.Count) available settings in the $ProfileName profile match the suggested values."
    }
    $findings = @("Your computer is using $($sys.LoadPercent)% of its memory. It has about $freeGB GB left for opening apps and doing more work.")
    $findings += $commitText
    $findings += "Memory Watch assessment: $($pressure.Level). $($pressure.Summary)"
    if($pressure.KernelConcern){$findings+='Windows kernel pools are unusually large. This memory is not listed under ordinary app working sets. A driver or filter investigation is needed; this reading alone cannot identify the responsible component.'}
    $userApps = @($apps | Where-Object { $_.AppName -notmatch '^(svchost|System|Idle|Memory Compression|MsMpEng|explorer|dwm|Registry|services|lsass|csrss)$' } | Select-Object -First 3)
    if ($userApps.Count -gt 0) {
        $appText = ($userApps | ForEach-Object { "$($_.AppName) ($($_.MemoryMB) MB)" }) -join ', '
        $findings += "The largest apps listed are $appText. If your computer feels slow, save your work and close windows or tabs you no longer need. Start there before changing more Windows settings."
    }
    $unmatched = @($recommended | Where-Object { $_.IsApplied -eq $false })
    $unknown = @($recommended | Where-Object { $null -eq $_.IsApplied })
    $findings += "WinBreathe checked the settings in your $ProfileName profile. $matching out of $($recommended.Count) are already in place."
    if ($unmatched.Count -gt 0) {
        $names = ($unmatched | ForEach-Object { $_.Title }) -join '; '
        $findings += "These settings are confirmed not in place: $names. Leave the settings that already match alone. Some changes need an app restart or a Windows restart to take effect."
    }
    if ($unknown.Count -gt 0) {
        $adminUnk = @($unknown | Where-Object { $_.CurrentValue -eq 'Requires Admin' })
        $otherUnk = @($unknown | Where-Object { $_.CurrentValue -ne 'Requires Admin' })
        if ($adminUnk.Count -gt 0) {
            $admNames = ($adminUnk | ForEach-Object { $_.Title }) -join '; '
            $findings += "Could not verify - administrator access required: $admNames. Their current state could not be inspected without elevation."
        }
        if ($otherUnk.Count -gt 0) {
            $othNames = ($otherUnk | ForEach-Object { $_.Title }) -join '; '
            $findings += "Could not verify: $othNames. Their current state could not be determined."
        }
    }
    if ($unmatched.Count -eq 0 -and $unknown.Count -eq 0 -and $recommended.Count -gt 0) {
        $findings += 'All available settings in this profile are already in place. You do not need to apply the same profile again.'
    }
    $findings += "Your $($sys.SystemDrive) drive has $($sys.FreeDiskGB) GB free. Free space tells us how much room is left, but not how fast the drive is working."
    $guardText = if ($guard.Installed) { 'On: selected profile settings are reapplied after startup.' }
        elseif ($guard.State -like 'Unsupported*') { 'Unavailable on this version of Windows.' }
        else { 'Off: settings are not automatically reapplied after startup.' }
    $nextSteps = @()
    if ($pressure.KernelConcern) {
        $nextSteps += 'Save your work now. Use Investigate Memory to inspect recent resource-exhaustion events. Review the pagefile setting with your administrator and investigate kernel-memory growth before applying more optimization tweaks. Do not disable security or storage drivers based on an allocation tag alone.'
    } elseif ($pressure.Level -eq 'Critical') {
        $nextSteps += $advice
    } elseif ($sys.LoadPercent -ge 75 -and $userApps.Count -gt 0) {
        $nextSteps += "Start with $($userApps[0].AppName): save your work and close windows or tabs you no longer need. Then refresh the dashboard and check whether more memory is available. Leave Windows services, security software and your VPN running."
    } else { $nextSteps += $advice }
    foreach ($item in $unmatched) {
        if ($item.Id -eq 'win.widgets') {
            $nextSteps += 'If you do not use Windows Widgets (the news and weather panel), open Optimize Tweaks and select only Turn off Windows Widgets. Preview the change before applying it. This report does not tell us whether Widgets is currently running.'
        } else {
            $nextSteps += "Review '$($item.Title)' in Optimize Tweaks and preview it before applying. What it changes: $($item.Description) A different value may be intentional."
        }
    }
    if ($unknown.Count -gt 0) {
        $nextSteps += 'To inspect or configure unverified memory compression, page combining, or pre-launch settings, re-run WinBreathe as Administrator.'
    }
    $nextSteps += 'Try the task that felt slow again. If it still feels slow, open Task Manager and check whether CPU or Disk usage stays high while the problem happens.'
    $nextSteps += 'This report shows your computer now. Without a before-and-after comparison, it cannot tell you how much WinBreathe improved performance.'
    $nextSteps += 'Memory Watch alerts work only while WinBreathe is open or minimized to its tray icon. They cannot guarantee prevention of crashes. Notifications may be suppressed by Windows; no apps are automatically closed.'
    $md = @('# Your WinBreathe computer report', '', "Created: $stamp | Windows: $(ConvertTo-WBReportMarkdown $sys.OSCaption)", '', '## 1. What is happening on your computer', '')
    foreach ($finding in $findings) { $md += @((ConvertTo-WBReportMarkdown $finding), '') }
    $md += @('## What to do next', '')
    foreach ($step in $nextSteps) { $md += "- $(ConvertTo-WBReportMarkdown $step)" }
    $md += @('', '---', '', '## 2. Technical details', '', '### Computer readings', '', "- Memory: $memoryText", "- Commit and kernel pools: $commitText", "- Memory pressure: $($pressure.Level)", "- Free storage: $($sys.FreeDiskGB) GB", "- Profile: $ProfileName ($matching / $($recommended.Count) settings match)", "- Automatic reapply: $guardText", '', '### Settings', '', 'Matching means the current value agrees with the selected profile. Optional settings are outside that profile; they do not need to be enabled.', '',
        '| Setting | Status | What it does |', '|---|---|---|')
    $settingCards = ''
    $technicalRows = ''
    foreach ($item in $states) {
        $status = if (-not $item.Applicable) { 'Not available on this PC' }
            elseif ($null -eq $item.IsApplied) { if ($item.CurrentValue -eq 'Requires Admin') { 'Could not verify - administrator access required' } else { 'Could not verify' } }
            elseif (-not $item.InProfile) { if ($item.IsApplied) { 'Optional - currently matches' } else { 'Optional - not set' } }
            elseif ($item.IsApplied) { 'Matches this profile' } else { 'Not set for this profile' }
        # Avoid emitting multiple labels for optional settings.
        if ($status -is [array]) { $status = $status[-1] }
        $md += "| $(ConvertTo-WBReportMarkdown $item.Title) | $(ConvertTo-WBReportMarkdown $status) | $(ConvertTo-WBReportMarkdown $item.Description) |"
        $settingCards += "<tr><td>$(Html $item.Title)</td><td>$(Html $status)</td><td>$(Html $item.Description)</td></tr>"
        $technicalRows += "<tr><td>$(Html $item.Id)</td><td>$(Html $item.CurrentValue)</td><td>$(Html $item.TargetValue)</td></tr>"
    }
    $md += @('', '### Apps using the most memory', '', 'Larger memory use is not automatically a problem. Save your work before closing an app. These figures describe current app memory use, not guaranteed recoverable memory.', '', '| App | Memory in use |', '|---|---|')
    $appRows = ''
    foreach ($app in $apps) {
        $md += "| $(ConvertTo-WBReportMarkdown $app.AppName) | $($app.MemoryMB) MB |"
        $appRows += "<tr><td>$(Html $app.AppName)</td><td>$($app.MemoryMB) MB</td></tr>"
    }
    $md += @('', '### Values for support', '', '| Setting reference | Current value | Profile value |', '|---|---|---|')
    foreach ($item in $states) { $md += "| $(ConvertTo-WBReportMarkdown $item.Id) | $(ConvertTo-WBReportMarkdown $item.CurrentValue) | $(ConvertTo-WBReportMarkdown $item.TargetValue) |" }
    $stepsHtml = ($nextSteps | ForEach-Object { "<li>$(Html $_)</li>" }) -join ''
    $findingsHtml = ($findings | ForEach-Object { "<p>$(Html $_)</p>" }) -join ''
    $html = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Your WinBreathe computer report</title>
<style>
body{margin:0;background:#f3f5f8;color:#243247;font:16px/1.6 'Segoe UI',sans-serif}main{max-width:960px;margin:auto;padding:32px 20px}h1{font-size:32px;line-height:1.2}h2{margin-top:32px}h3{font-size:17px;margin:0}.intro{color:#526278}.cards{display:flex;flex-wrap:wrap;gap:16px}.card,.setting,details,.advice{background:white;border:1px solid #dce2ea;border-radius:12px;padding:20px}.card{flex:1;min-width:200px}.card strong{display:block;font-size:21px}.setting{margin:12px 0}.setting p{margin:8px 0 0}.badge{font-size:14px;color:#245381;font-weight:600}table{width:100%;border-collapse:collapse;background:white}td,th{text-align:left;padding:12px;border-bottom:1px solid #dce2ea;overflow-wrap:anywhere}th{background:#e9eef5}.technical{margin-top:48px;padding-top:24px;border-top:3px solid #b6c8df}.narrative{max-width:760px}details{margin-top:40px;border-top:4px solid #b6c8df}details[open]>summary{margin-bottom:20px}.scroll{overflow-x:auto}footer{margin-top:28px;color:#526278;font-size:14px}@media print{body{background:white}main{padding:0}.setting{break-inside:avoid}.technical{break-before:page}}
</style></head><body><main>
<h1>Your computer report</h1><p class="intro">WinBreathe 2.3.0 &middot; $stamp &middot; $(Html $sys.OSCaption)</p>
<!-- Technical readings are presented after the narrative. -->
<!-- <div class="cards"><div class="card">Memory in use<strong>$usedGB / $totalGB GB</strong>$($sys.LoadPercent)% in use &middot; $freeGB GB available</div><div class="card">Storage space available<strong>$($sys.FreeDiskGB) GB</strong>On $(Html $sys.SystemDrive)</div><div class="card">Settings matching your profile<strong>$matching / $($recommended.Count)</strong>$(Html $ProfileName) profile &middot; available settings only</div></div> -->
<section class="narrative"><h2>1. What is happening on your computer</h2>$findingsHtml
<h2>What to do next</h2><div class="advice"><ol>$stepsHtml</ol><p><strong>Automatic reapply:</strong> $(Html $guardText) This is a preference, not a performance fault.</p></div>
</section><section class="technical"><h2>2. Technical details</h2><p>The readings and settings below support the explanation above.</p><table><tbody><tr><th>Memory</th><td>$memoryText</td></tr><tr><th>Commit and kernel pools</th><td>$(Html $commitText)</td></tr><tr><th>Memory pressure</th><td>$(Html $pressure.Level)</td></tr><tr><th>Free storage</th><td>$($sys.FreeDiskGB) GB on $(Html $sys.SystemDrive)</td></tr><tr><th>Profile</th><td>$(Html $ProfileName): $matching / $($recommended.Count) settings match</td></tr><tr><th>Automatic reapply</th><td>$(Html $guardText)</td></tr></tbody></table><h2>Settings</h2><p>$(Html $settingsText) Matching means the current value agrees with this profile. Optional settings do not need to be enabled. Unavailable settings are excluded from the count above.</p><div class="scroll"><table><thead><tr><th>Setting</th><th>Status</th><th>Explanation</th></tr></thead><tbody>$settingCards</tbody></table></div>
<h2>Apps using the most memory</h2><p>Larger memory use is not automatically a problem. Save your work before closing an app. These figures are current readings, not guaranteed recoverable memory.</p><table><thead><tr><th>App</th><th>Memory in use</th></tr></thead><tbody>$appRows</tbody></table>
<h2>Values for support</h2><p>These values help troubleshoot settings; you do not need to interpret them to use this report.</p><div class="scroll"><table><thead><tr><th>Setting reference</th><th>Current value</th><th>Profile value</th></tr></thead><tbody>$technicalRows</tbody></table></div></section>
<footer>This report records the current state only. Legacy Windows compatibility and performance remain experimental.</footer>
</main></body></html>
"@
    Set-Content -Path $mdPath -Value ($md -join "`r`n") -Encoding UTF8 -Force -ErrorAction Stop
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8 -Force -ErrorAction Stop
    Write-WBLog "Saved your computer report: $htmlPath" 'OK'
    return [PSCustomObject]@{ MarkdownPath = $mdPath; HtmlPath = $htmlPath }
}


. (Join-Path $PSScriptRoot 'WinBreathe.MemoryWatch.ps1')
. (Join-Path $PSScriptRoot 'WinBreathe.MemoryRelief.ps1')

Export-ModuleMember -Function @(
    'Get-WBPaths',
    'Write-WBLog',
    'Test-WBAdmin',
    'Get-WBTweakCatalog',
    'Get-WBMemorySnapshot',
    'Get-WBMemoryPressure',
    'Test-WBProtectedProcessName',
    'New-WBReliefState',
    'Invoke-WBMemoryRelief',
    'New-WBMemoryWatchState',
    'Update-WBMemoryWatch',
    'Write-WBMemoryJournal',
    'Get-WBMemoryIncidents',
    'Get-WBSystemProfile',
    'Test-WBTweakState',
    'New-WBSnapshot',
    'Restore-WBSnapshot',
    'Restore-WBStockDefaults',
    'Invoke-WBTweaks',
    'Get-WBTopProcesses',
    'Stop-WBAppGroup',
    'Invoke-WBSafeFlush',
    'Get-WBStartupItems',
    'Set-WBStartupItemState',
    'Get-WBUpdateGuardStatus',
    'Install-WBUpdateGuard',
    'Uninstall-WBUpdateGuard',
    'Export-WBReport'
)
