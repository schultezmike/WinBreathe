# ==============================================================================
# WinBreathe.Engine.psm1 - Core Optimization, Telemetry & Guard Module (v2.0.0)
# Designed for Windows 11 / 10 (4-16 GB RAM, Mechanical HDDs & AI Dev Stacks)
# License: MIT | Pure PowerShell 5.1+ | Zero External Dependencies
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ------------------------------------------------------------------------------
# Win32 Native Memory API (Sub-millisecond, zero CPU/Disk overhead)
# ------------------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'Win32Mem').Type) {
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
}

# ------------------------------------------------------------------------------
# Paths & Directories
# ------------------------------------------------------------------------------
function Get-WBPaths {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $dataDir    = Join-Path $env:ProgramData "WinBreathe"
    $backupDir  = Join-Path $dataDir "backups"
    $reportDir  = Join-Path $dataDir "reports"
    $logFile    = Join-Path $dataDir "winbreathe.log"
    $configFile = Join-Path (Join-Path $moduleRoot "config") "tweaks.json"

    foreach ($dir in @($dataDir, $backupDir, $reportDir)) {
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
    $stat = New-Object MEMORYSTATUSEX
    $stat.dwLength = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($stat)
    [Win32Mem]::GlobalMemoryStatusEx([ref]$stat) | Out-Null

    $totalMB  = [int][math]::Round($stat.ullTotalPhys / 1MB, 0)
    $availMB  = [int][math]::Round($stat.ullAvailPhys / 1MB, 0)
    $usedMB   = $totalMB - $availMB
    $commitTotalMB = [int][math]::Round($stat.ullTotalPageFile / 1MB, 0)
    $commitAvailMB = [int][math]::Round($stat.ullAvailPageFile / 1MB, 0)
    $commitUsedMB  = $commitTotalMB - $commitAvailMB

    return [PSCustomObject]@{
        LoadPercent   = [int]$stat.dwMemoryLoad
        TotalRAMMB    = $totalMB
        UsedRAMMB     = $usedMB
        AvailRAMMB    = $availMB
        CommitTotalMB = $commitTotalMB
        CommitUsedMB  = $commitUsedMB
        CommitAvailMB = $commitAvailMB
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
                if (-not $disk) {
                    $disk = Get-PhysicalDisk | Select-Object -First 1
                }
                if ($disk) {
                    $mediaType = [string]$disk.MediaType
                    $diskModel = [string]$disk.FriendlyName
                }
            }
        } catch {
            $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($disk) {
                $mediaType = [string]$disk.MediaType
                $diskModel = [string]$disk.FriendlyName
            }
        }

        $vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sysDrive'" -ErrorAction SilentlyContinue
        $freeDiskGB  = if ($vol) { [math]::Round($vol.FreeSpace / 1GB, 1) } else { 50.0 }
        $totalDiskGB = if ($vol) { [math]::Round($vol.Size / 1GB, 1) } else { 256.0 }

        # Account for existing pagefile.sys on the system drive (WB-06)
        $pfPath = "$sysDrive\pagefile.sys"
        $existingPfGB = 0.0
        $pfFile = Get-Item -Path $pfPath -Force -ErrorAction SilentlyContinue
        if ($pfFile) {
            $existingPfGB = [math]::Round($pfFile.Length / 1GB, 1)
        }

        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $osCaption = if ($os) { $os.Caption } else { "Windows 11" }
        $osBuild   = if ($os) { $os.BuildNumber } else { "Unknown" }

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
    return [PSCustomObject]@{
        OSCaption          = $hw.OSCaption
        OSBuild            = $hw.OSBuild
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
        } catch {}
    }
    return $Path
}

function Get-WBRegistryState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $resolved = Resolve-WBRegistryPath -Path $Path
    if (-not (Test-Path $resolved)) {
        return [PSCustomObject]@{ Exists = $false; Value = $null }
    }
    $item = Get-ItemProperty -Path $resolved -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not ($item.PSObject.Properties.Name -contains $Name)) {
        return [PSCustomObject]@{ Exists = $false; Value = $null }
    }
    return [PSCustomObject]@{ Exists = $true; Value = $item.$Name }
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
        Remove-ItemProperty -Path $resolved -Name $Name -Force -ErrorAction SilentlyContinue
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
        [string]$ProfileName = "Balanced"
    )
    $catalog    = Get-WBTweakCatalog
    $sysProfile = Get-WBSystemProfile
    $mmAgent    = $null
    if (Get-Command Get-MMAgent -ErrorAction SilentlyContinue) {
        $mmAgent = Get-MMAgent -ErrorAction SilentlyContinue
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
                    $regState  = Get-WBRegistryState -Path $entry.path -Name $entry.name
                    $tgtParts += "$($entry.name)=$targetVal"
                    if ($regState.Exists -and ([string]$regState.Value -eq [string]$targetVal)) {
                        $curParts += "$($entry.name)=$($regState.Value)"
                    } else {
                        $allMatch = $false
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
                if ($null -eq $mmAgent -or -not ($mmAgent.PSObject.Properties.Name -contains $propName)) {
                    $curText   = "Requires Admin"
                    $isApplied = $false
                } else {
                    $curVal    = [bool]$mmAgent.$propName
                    $curText   = [string]$curVal
                    $isApplied = ($curVal -eq [bool]$tweak.enabled)
                }
            }
            "pagefile" {
                $targetMB = Get-WBTargetPagefileMB -SysProfile $sysProfile
                $mmPath   = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                $autoReg  = Get-WBRegistryState -Path $mmPath -Name "AutomaticManagedPagefile"
                $pfReg    = Get-WBRegistryState -Path $mmPath -Name "PagingFiles"
                $tgtText  = "Fixed $targetMB MB"

                $pfValStr = if ($pfReg.Exists -and $pfReg.Value) { ($pfReg.Value -join "; ") } else { "Auto" }
                $curText  = $pfValStr

                if ($pfValStr -match '(\d+)\s+(\d+)' -and ($Matches[1] -eq $Matches[2]) -and ([int]$Matches[1] -ge 4096) -and ((-not $autoReg.Exists) -or ([int]$autoReg.Value -eq 0))) {
                    $isApplied = $true
                } else {
                    $isApplied = $false
                }
            }
        }

        $stateLabel = if (-not $applicable) {
            "NotApplicable"
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
function New-WBSnapshot {
    param([string]$Label = "Pre-Optimization")
    $paths      = Get-WBPaths
    $catalog    = Get-WBTweakCatalog
    $sysProfile = Get-WBSystemProfile

    $regBackup = @()
    $svcBackup = @()
    $mmBackup  = @{}

    foreach ($tweak in $catalog.tweaks) {
        if ($tweak.type -eq "registry") {
            foreach ($entry in $tweak.entries) {
                $st = Get-WBRegistryState -Path $entry.path -Name $entry.name
                $regBackup += [PSCustomObject]@{
                    Path   = $entry.path
                    Name   = $entry.name
                    Kind   = $entry.kind
                    Exists = $st.Exists
                    Value  = $st.Value
                }
            }
        } elseif ($tweak.type -eq "service") {
            $svc = Get-Service -Name $tweak.service -ErrorAction SilentlyContinue
            if ($svc) {
                $svcBackup += [PSCustomObject]@{
                    Name      = $tweak.service
                    StartType = [string]$svc.StartType
                    Status    = [string]$svc.Status
                }
            }
        }
    }

    foreach ($optSvc in $catalog.optionalServices) {
        $matched = Get-Service -Name $optSvc.pattern -ErrorAction SilentlyContinue
        foreach ($s in $matched) {
            if (-not ($svcBackup | Where-Object { $_.Name -eq $s.Name })) {
                $svcBackup += [PSCustomObject]@{
                    Name      = $s.Name
                    StartType = [string]$s.StartType
                    Status    = [string]$s.Status
                }
            }
        }
    }

    if (Get-Command Get-MMAgent -ErrorAction SilentlyContinue) {
        $mm = Get-MMAgent -ErrorAction SilentlyContinue
        if ($mm) {
            $mmBackup = @{
                MemoryCompression    = [bool]$mm.MemoryCompression
                PageCombining        = [bool]$mm.PageCombining
                ApplicationPreLaunch = [bool]$mm.ApplicationPreLaunch
            }
        }
    }

    $mmPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    $autoReg = Get-WBRegistryState -Path $mmPath -Name "AutomaticManagedPagefile"
    $pfReg   = Get-WBRegistryState -Path $mmPath -Name "PagingFiles"

    $snapshotObj = [PSCustomObject]@{
        SchemaVersion = 2
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

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $file  = Join-Path $paths.BackupDir "backup-$stamp.json"
    $json  = $snapshotObj | ConvertTo-Json -Depth 6
    Set-Content -Path $file -Value $json -Encoding UTF8 -Force
    Set-Content -Path $paths.LatestBackup -Value $json -Encoding UTF8 -Force

    Write-WBLog "Saved system state snapshot to: $file" "OK"
    return $file
}

function Restore-WBSnapshot {
    param([string]$SnapshotPath = "")
    if (-not (Test-WBAdmin)) {
        Write-WBLog "Administrator privileges required to restore snapshot." "ERROR"
        return $false
    }

    $paths = Get-WBPaths
    if ([string]::IsNullOrEmpty($SnapshotPath)) {
        $SnapshotPath = $paths.LatestBackup
    }

    if (-not (Test-Path $SnapshotPath)) {
        Write-WBLog "No snapshot found at $SnapshotPath. Use -ResetDefaults to restore stock Windows settings." "WARN"
        return $false
    }

    Write-WBLog "Restoring exact pre-optimization state from: $SnapshotPath" "HEAD"
    $snap = Get-Content -Path $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($reg in $snap.Registry) {
        if ($reg.Exists) {
            Set-WBRegistryValue -Path $reg.Path -Name $reg.Name -Value $reg.Value -Kind $reg.Kind
            Write-WBLog "Restored registry $($reg.Name) = $($reg.Value)" "INFO"
        } else {
            Remove-WBRegistryValue -Path $reg.Path -Name $reg.Name
            Write-WBLog "Removed policy key $($reg.Name) (was not present before)" "INFO"
        }
    }

    foreach ($svc in $snap.Services) {
        $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc.Name -StartupType $svc.StartType -ErrorAction SilentlyContinue
            if ($svc.Status -eq "Running" -and $svc.StartType -ne "Disabled") {
                Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
            }
            Write-WBLog "Restored service $($svc.Name) -> $($svc.StartType)" "INFO"
        }
    }

    if ($snap.MMAgent -and (Get-Command Enable-MMAgent -ErrorAction SilentlyContinue)) {
        if ($snap.MMAgent.MemoryCompression) { Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue } else { Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue }
        if ($snap.MMAgent.PageCombining) { Enable-MMAgent -PageCombining -ErrorAction SilentlyContinue } else { Disable-MMAgent -PageCombining -ErrorAction SilentlyContinue }
        if ($snap.MMAgent.ApplicationPreLaunch) { Enable-MMAgent -ApplicationPreLaunch -ErrorAction SilentlyContinue } else { Disable-MMAgent -ApplicationPreLaunch -ErrorAction SilentlyContinue }
        Write-WBLog "Restored MMAgent memory compression & pre-launch state." "INFO"
    }

    if ($snap.Pagefile) {
        $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        if ($snap.Pagefile.AutoExists) {
            Set-WBRegistryValue -Path $mmPath -Name "AutomaticManagedPagefile" -Value $snap.Pagefile.AutoValue -Kind "DWord"
        }
        if ($snap.Pagefile.PfExists -and $null -ne $snap.Pagefile.PfValue) {
            Set-WBRegistryValue -Path $mmPath -Name "PagingFiles" -Value ([string[]]$snap.Pagefile.PfValue) -Kind "MultiString"
        }
        Write-WBLog "Restored pagefile configuration." "INFO"
    }

    Write-WBLog "Snapshot undo completed successfully." "OK"
    return $true
}

function Restore-WBStockDefaults {
    if (-not (Test-WBAdmin)) {
        Write-WBLog "Administrator privileges required to restore stock Windows defaults." "ERROR"
        return $false
    }

    Write-WBLog "Resetting all WinBreathe policies to Windows 11 stock defaults..." "HEAD"
    $catalog = Get-WBTweakCatalog

    foreach ($tweak in $catalog.tweaks) {
        if ($tweak.type -eq "registry") {
            foreach ($entry in $tweak.entries) {
                if ($entry.path -match '\\Policies\\') {
                    Remove-WBRegistryValue -Path $entry.path -Name $entry.name
                } elseif ($entry.name -eq "EnableTransparency") {
                    Set-WBRegistryValue -Path $entry.path -Name $entry.name -Value 1 -Kind "DWord"
                }
            }
            Write-WBLog "Reset registry policy: $($tweak.title)" "INFO"
        } elseif ($tweak.type -eq "service") {
            $defaultStart = switch ($tweak.service) {
                "DiagTrack"        { "Automatic" }
                "MapsBroker"       { "Automatic" }
                "dmwappushservice" { "Manual" }
                "CDPSvc"           { "Automatic" }
                "WSearch"          { "Automatic" }
                default            { "Manual" }
            }
            if (Get-Service -Name $tweak.service -ErrorAction SilentlyContinue) {
                Set-Service -Name $tweak.service -StartupType $defaultStart -ErrorAction SilentlyContinue
                if ($defaultStart -eq "Automatic") {
                    Start-Service -Name $tweak.service -ErrorAction SilentlyContinue
                }
                Write-WBLog "Reset service $($tweak.service) to $defaultStart" "INFO"
            }
        }
    }

    if (Get-Command Enable-MMAgent -ErrorAction SilentlyContinue) {
        Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        Enable-MMAgent -ApplicationPreLaunch -ErrorAction SilentlyContinue
        Write-WBLog "Restored stock Windows MMAgent settings." "INFO"
    }

    $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    Set-WBRegistryValue -Path $mmPath -Name "AutomaticManagedPagefile" -Value 1 -Kind "DWord"
    Set-WBRegistryValue -Path $mmPath -Name "PagingFiles" -Value @("?:\pagefile.sys") -Kind "MultiString"
    Write-WBLog "Restored Windows automatic pagefile management." "INFO"

    Write-WBLog "All settings reset to stock Windows 11 defaults." "OK"
    return $true
}

# ------------------------------------------------------------------------------
# Main Optimization Engine (Supports Profile, Specific TweakIds, and -WhatIf)
# ------------------------------------------------------------------------------
function Invoke-WBTweaks {
    param(
        [ValidateSet("Conservative", "Balanced", "Aggressive")]
        [string]$ProfileName = "Balanced",
        [string[]]$TweakIds = @(),
        [switch]$WhatIf,
        [switch]$SkipSnapshot,
        [switch]$SkipFlush
    )

    if (-not $WhatIf -and -not (Test-WBAdmin)) {
        Write-WBLog "Administrator privileges are required to apply optimizations. Use -WhatIf to preview." "ERROR"
        return $null
    }

    $catalog    = Get-WBTweakCatalog
    $sysProfile = Get-WBSystemProfile
    $memBefore  = Get-WBMemorySnapshot

    $modeBanner = if ($WhatIf) { "DRY-RUN PREVIEW MODE (No changes will be written)" } else { "LIVE OPTIMIZATION ($ProfileName Profile)" }
    Write-WBLog "======================================================================" "HEAD"
    Write-WBLog "  WinBreathe v2.0 - $modeBanner" "HEAD"
    Write-WBLog "  Hardware: $($sysProfile.TotalRAMMB) MB RAM | Disk: $($sysProfile.DiskMediaType) ($($sysProfile.FreeDiskGB) GB Free)" "HEAD"
    Write-WBLog "======================================================================" "HEAD"

    if (-not $WhatIf -and -not $SkipSnapshot) {
        New-WBSnapshot -Label "Auto-Backup before $ProfileName run" | Out-Null
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

    $appliedCount = 0
    $skippedCount = 0

    foreach ($tweak in $selectedTweaks) {
        if (-not (Test-WBTweakCondition -Tweak $tweak -SysProfile $sysProfile)) {
            Write-WBLog "SKIP [$($tweak.id)]: Hardware condition ($($tweak.condition)) not met on this PC." "INFO"
            $skippedCount++
            continue
        }

        switch ($tweak.type) {
            "registry" {
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
                        }
                    }
                }
                if (-not $WhatIf) {
                    Write-WBLog "APPLIED [$($tweak.id)]: $($tweak.title)" "OK"
                }
                $appliedCount++
            }
            "service" {
                $svc = Get-Service -Name $tweak.service -ErrorAction SilentlyContinue
                if ($null -eq $svc) {
                    Write-WBLog "SKIP [$($tweak.id)]: Service '$($tweak.service)' not present." "INFO"
                    $skippedCount++
                } elseif ($WhatIf) {
                    Write-WBLog "$($tweak.id): Service '$($tweak.service)' -> $($tweak.startupType) (Current: $($svc.StartType)/$($svc.Status))" "PREVIEW"
                    $appliedCount++
                } else {
                    if ($tweak.startupType -eq "Disabled" -and $svc.Status -eq "Running") {
                        Stop-Service -Name $tweak.service -Force -ErrorAction SilentlyContinue
                    }
                    Set-Service -Name $tweak.service -StartupType $tweak.startupType -ErrorAction SilentlyContinue
                    Write-WBLog "APPLIED [$($tweak.id)]: $($tweak.title) ($($tweak.service) -> $($tweak.startupType))" "OK"
                    $appliedCount++
                }
            }
            "mmagent" {
                if (-not (Get-Command Get-MMAgent -ErrorAction SilentlyContinue)) {
                    Write-WBLog "SKIP [$($tweak.id)]: MMAgent cmdlets unavailable." "WARN"
                    $skippedCount++
                } elseif ($WhatIf) {
                    Write-WBLog "$($tweak.id): Set MMAgent $($tweak.feature) = $($tweak.enabled)" "PREVIEW"
                    $appliedCount++
                } else {
                    $feat = $tweak.feature
                    if ($tweak.enabled) {
                        switch ($feat) {
                            "MemoryCompression"    { Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue }
                            "PageCombining"        { Enable-MMAgent -PageCombining -ErrorAction SilentlyContinue }
                            "ApplicationPreLaunch" { Enable-MMAgent -ApplicationPreLaunch -ErrorAction SilentlyContinue }
                        }
                    } else {
                        switch ($feat) {
                            "MemoryCompression"    { Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue }
                            "PageCombining"        { Disable-MMAgent -PageCombining -ErrorAction SilentlyContinue }
                            "ApplicationPreLaunch" { Disable-MMAgent -ApplicationPreLaunch -ErrorAction SilentlyContinue }
                        }
                    }
                    Write-WBLog "APPLIED [$($tweak.id)]: $($tweak.title)" "OK"
                    $appliedCount++
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
                    Write-WBLog "mem.pagefile: Lock contiguous pagefile at $targetMB MB ($targetGB GB) on $($sysProfile.SystemDrive)" "PREVIEW"
                    $appliedCount++
                } else {
                    $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                    $pfSpec = "$($sysProfile.SystemDrive)\pagefile.sys $targetMB $targetMB"
                    Set-WBRegistryValue -Path $mmPath -Name "AutomaticManagedPagefile" -Value 0 -Kind "DWord"
                    Set-WBRegistryValue -Path $mmPath -Name "PagingFiles" -Value @($pfSpec) -Kind "MultiString"
                    Write-WBLog "APPLIED [mem.pagefile]: Fixed contiguous pagefile at $targetMB MB ($pfSpec)" "OK"
                    $appliedCount++
                }
            }
        }
    }

    if (-not $WhatIf -and -not $SkipFlush) {
        Invoke-WBSafeFlush | Out-Null
    }

    $memAfter = Get-WBMemorySnapshot
    $reclaimedMB = [math]::Max(0, ($memBefore.UsedRAMMB - $memAfter.UsedRAMMB))

    Write-WBLog "----------------------------------------------------------------------" "HEAD"
    Write-WBLog "  SUMMARY: $appliedCount tweaks processed ($skippedCount skipped)" "OK"
    Write-WBLog "  RAM Before: $($memBefore.UsedRAMMB) MB ($($memBefore.LoadPercent)%) | RAM After: $($memAfter.UsedRAMMB) MB ($($memAfter.LoadPercent)%)" "OK"
    if ($reclaimedMB -gt 0) {
        Write-WBLog "  Immediate Physical RAM Reclaimed: +$reclaimedMB MB" "OK"
    }
    Write-WBLog "----------------------------------------------------------------------" "HEAD"

    return [PSCustomObject]@{
        Profile      = $ProfileName
        WhatIf       = [bool]$WhatIf
        AppliedCount = $appliedCount
        SkippedCount = $skippedCount
        BeforeRAMMB  = $memBefore.UsedRAMMB
        AfterRAMMB   = $memAfter.UsedRAMMB
        ReclaimedMB  = $reclaimedMB
    }
}

# ------------------------------------------------------------------------------
# Safe Process Inspector & Transient Host Flusher (WB-03 Protected)
# ------------------------------------------------------------------------------
function Get-WBTopProcesses {
    param([int]$Top = 18)
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
            $ramMB     = [int][math]::Round($totalWS / 1MB, 1)
            $isProt    = $protectedSet.ContainsKey($nameLower)
            [PSCustomObject]@{
                AppName      = $_.Name
                ProcessCount = $_.Count
                MemoryMB     = $ramMB
                IsProtected  = $isProt
                SafetyStatus = if ($isProt) { "Protected (Untouchable)" } else { "User / App" }
            }
        } |
        Sort-Object -Property MemoryMB -Descending |
        Select-Object -First $Top

    return $groups
}

function Stop-WBAppGroup {
    param([Parameter(Mandatory = $true)][string]$AppName)
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

    $procs = Get-Process -Name $AppName -ErrorAction SilentlyContinue
    if (-not $procs) {
        Write-WBLog "Process '$AppName' is no longer running." "INFO"
        return $false
    }

    $count = @($procs).Count
    $freedMB = [int][math]::Round((($procs | Measure-Object -Property WorkingSet64 -Sum).Sum) / 1MB, 0)
    foreach ($proc in $procs) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Write-WBLog "Terminated $count instance(s) of '$AppName' (~$freedMB MB released)." "OK"
    return $true
}

function Invoke-WBSafeFlush {
    $catalog = Get-WBTweakCatalog
    $memBefore = Get-WBMemorySnapshot

    foreach ($target in $catalog.flushTargets) {
        $procs = Get-Process -Name $target.name -ErrorAction SilentlyContinue
        if ($procs) {
            foreach ($p in $procs) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
            Write-WBLog "Flushed transient host: $($target.name) ($($target.label))" "INFO"
        }
    }

    # Safely flush orphaned/Search/Widgets msedgewebview2 while protecting IDE/AI parent processes (WB-03)
    $protectedSet = @{}
    foreach ($p in $catalog.protectedProcesses) {
        $protectedSet[$p.ToLowerInvariant()] = $true
    }

    $wvProcs = Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue
    $killedWv = 0
    foreach ($wv in $wvProcs) {
        $parent = Get-Process -Id $wv.ParentProcessId -ErrorAction SilentlyContinue
        $parentName = if ($parent) { $parent.ProcessName.ToLowerInvariant() } else { "" }
        $cmdLine = [string]$wv.CommandLine

        # Only flush WebView2 instances belonging to SearchHost, Widgets, or dead parents; never protected apps
        if ($protectedSet.ContainsKey($parentName)) {
            continue
        }
        if ([string]::IsNullOrEmpty($parentName) -or $parentName -in @("searchhost", "widgets", "widgetservice") -or $cmdLine -match "Windows\.Client\.WebExperience|SearchHost") {
            Stop-Process -Id $wv.ProcessId -Force -ErrorAction SilentlyContinue
            $killedWv++
        }
    }
    if ($killedWv -gt 0) {
        Write-WBLog "Flushed $killedWv background Search/Widget WebView2 host process(es) (AI/IDE WebViews untouched)." "OK"
    }

    Start-Sleep -Milliseconds 350
    $memAfter = Get-WBMemorySnapshot
    $freed = [math]::Max(0, ($memBefore.UsedRAMMB - $memAfter.UsedRAMMB))
    Write-WBLog "Safe flush complete. Active RAM reclaimed: +$freed MB." "OK"
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
            Set-WBRegistryValue -Path $activePath -Name $Name -Value $st.Value -Kind "String"
            Remove-WBRegistryValue -Path $disabledPath -Name $Name
            Write-WBLog "Re-enabled startup item '$Name' ($Scope)." "OK"
            return $true
        }
    } else {
        $st = Get-WBRegistryState -Path $activePath -Name $Name
        if ($st.Exists) {
            Set-WBRegistryValue -Path $disabledPath -Name $Name -Value $st.Value -Kind "String"
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
    param([string]$ProfileName = "Balanced")
    if (-not (Test-WBAdmin)) {
        Write-WBLog "Administrator privileges required to install the Update Guard." "ERROR"
        return $false
    }

    $paths = Get-WBPaths
    $secureDir = $paths.DataDir

    # Harden NTFS ACLs using locale-independent WellKnownSidType (WB-02 Fix)
    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)

        $adminSid  = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $usersSid  = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)

        $inheritFlags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
        $propFlags    = [System.Security.AccessControl.PropagationFlags]::None

        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid,  "FullControl",    $inheritFlags, $propFlags, "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl",    $inheritFlags, $propFlags, "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($usersSid,  "ReadAndExecute", $inheritFlags, $propFlags, "Allow")))

        Set-Acl -Path $secureDir -AclObject $acl -ErrorAction Stop
    } catch {
        Write-WBLog "Warning hardening ACL on ${secureDir}: $($_.Exception.Message)" "WARN"
    }

    # Copy module, CLI, and config to secure ProgramData directory
    $secSrc = Join-Path $secureDir "src"
    $secCfg = Join-Path $secureDir "config"
    New-Item -ItemType Directory -Path $secSrc, $secCfg -Force -ErrorAction SilentlyContinue | Out-Null

    Copy-Item -Path (Join-Path $PSScriptRoot "WinBreathe.Engine.psm1") -Destination (Join-Path $secSrc "WinBreathe.Engine.psm1") -Force
    $cliSrc = Join-Path $PSScriptRoot "WinBreathe.ps1"
    if (Test-Path $cliSrc) {
        Copy-Item -Path $cliSrc -Destination (Join-Path $secSrc "WinBreathe.ps1") -Force
    }
    Copy-Item -Path $paths.ConfigFile -Destination (Join-Path $secCfg "tweaks.json") -Force

    $targetScript = Join-Path $secSrc "WinBreathe.ps1"
    $argStr = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetScript`" -Profile $ProfileName -SkipSnapshot"

    $action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argStr
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = "PT90S"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName "WinBreathe_UpdateGuard" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Re-enforces WinBreathe ($ProfileName) optimizations 90s after boot to counter Windows Update policy resets." -Force | Out-Null

    Write-WBLog "Installed Hardened Update Guard ('WinBreathe_UpdateGuard') under SYSTEM with 90s boot delay." "OK"
    return $true
}

function Uninstall-WBUpdateGuard {
    if (-not (Test-WBAdmin)) {
        Write-WBLog "Administrator privileges required to remove Update Guard." "ERROR"
        return $false
    }
    foreach ($name in @("WinBreathe_UpdateGuard", "Win11LowRamOptimizer_AutoGuard")) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
            Write-WBLog "Removed scheduled task: $name" "OK"
        }
    }
    return $true
}

# ------------------------------------------------------------------------------
# HTML & Markdown System Telemetry Report Exporter
# ------------------------------------------------------------------------------
function Export-WBReport {
    param([string]$ProfileName = "Balanced")
    $paths      = Get-WBPaths
    $sys        = Get-WBSystemProfile
    $states     = Test-WBTweakState -ProfileName $ProfileName
    $topProcs   = Get-WBTopProcesses -Top 10
    $guard      = Get-WBUpdateGuardStatus
    $stamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $fileStamp  = Get-Date -Format "yyyyMMdd-HHmmss"

    $mdPath   = Join-Path $paths.ReportDir "WinBreathe-Report-$fileStamp.md"
    $htmlPath = Join-Path $paths.ReportDir "WinBreathe-Report-$fileStamp.html"

    $appliedCount = @($states | Where-Object { $_.State -eq "Applied" }).Count
    $totalCount   = @($states).Count

    $mdLines = @(
        "# WinBreathe v2.0 - System Optimization & Drift Report",
        "**Generated:** $stamp  ",
        "**OS:** $($sys.OSCaption) (Build $($sys.OSBuild))  ",
        "**Memory:** $($sys.UsedRAMMB) MB / $($sys.TotalRAMMB) MB ($($sys.LoadPercent)% Load, $($sys.AvailRAMMB) MB Available)  ",
        "**Storage:** $($sys.DiskModel) ($($sys.DiskMediaType)) - $($sys.FreeDiskGB) GB Free on $($sys.SystemDrive)  ",
        "**Update Guard:** $($guard.State)  ",
        "**Active Tweaks:** $appliedCount / $totalCount  ",
        "",
        "## Tweak Drift Status ($ProfileName Profile)",
        "| ID | Category | Title | Risk | Status | Current Value |",
        "|---|---|---|---|---|---|"
    )
    foreach ($s in $states) {
        $mdLines += "| `$($s.Id)` | $($s.Category) | $($s.Title) | $($s.Risk) | **$($s.State)** | `$($s.CurrentValue)` |"
    }
    $mdLines += ""
    $mdLines += "## Top 10 Memory Consumers"
    $mdLines += "| Application | Processes | RAM (MB) | Protection |"
    $mdLines += "|---|---|---|---|"
    foreach ($p in $topProcs) {
        $mdLines += "| **$($p.AppName)** | $($p.ProcessCount) | $($p.MemoryMB) MB | $($p.SafetyStatus) |"
    }

    Set-Content -Path $mdPath -Value ($mdLines -join "`r`n") -Encoding UTF8 -Force

    # Build clean Catppuccin Dark HTML Report
    $rowsHtml = ""
    foreach ($s in $states) {
        $badgeColor = switch ($s.State) {
            "Applied"       { "#a6e3a1" }
            "NotApplicable" { "#9399b2" }
            default         { "#f9e2af" }
        }
        $rowsHtml += "<tr><td><code>$($s.Id)</code></td><td>$($s.Category)</td><td>$($s.Title)</td><td>$($s.Risk)</td><td style='color:$badgeColor;font-weight:bold;'>$($s.State)</td><td><code>$($s.CurrentValue)</code></td></tr>`n"
    }

    $procHtml = ""
    foreach ($p in $topProcs) {
        $protColor = if ($p.IsProtected) { "#89b4fa" } else { "#cdd6f4" }
        $procHtml += "<tr><td><strong>$($p.AppName)</strong></td><td>$($p.ProcessCount)</td><td>$($p.MemoryMB) MB</td><td style='color:$protColor'>$($p.SafetyStatus)</td></tr>`n"
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>WinBreathe v2.0 Telemetry Report</title>
<style>
  body { background:#1e1e2e; color:#cdd6f4; font-family:'Segoe UI',sans-serif; margin:32px; }
  h1, h2 { color:#89b4fa; margin-bottom:8px; }
  .cards { display:flex; gap:16px; flex-wrap:wrap; margin:20px 0; }
  .card { background:#181825; border:1px solid #313244; border-radius:8px; padding:16px 20px; min-width:200px; }
  .card .label { color:#a6adc8; font-size:12px; text-transform:uppercase; }
  .card .val { color:#a6e3a1; font-size:22px; font-weight:bold; margin-top:4px; }
  table { width:100%; border-collapse:collapse; background:#181825; border-radius:8px; overflow:hidden; margin-top:12px; }
  th { background:#313244; color:#89b4fa; text-align:left; padding:10px 12px; font-size:13px; }
  td { padding:9px 12px; border-bottom:1px solid #313244; font-size:13px; }
  code { background:#313244; padding:2px 6px; border-radius:4px; color:#94e2d5; }
</style>
</head>
<body>
  <h1>WinBreathe v2.0 &mdash; System Optimization &amp; Drift Report</h1>
  <p style="color:#a6adc8">Generated: $stamp | OS: $($sys.OSCaption) (Build $($sys.OSBuild))</p>
  <div class="cards">
    <div class="card"><div class="label">RAM Usage</div><div class="val">$($sys.UsedRAMMB) / $($sys.TotalRAMMB) MB ($($sys.LoadPercent)%)</div></div>
    <div class="card"><div class="label">Available RAM</div><div class="val">$($sys.AvailRAMMB) MB</div></div>
    <div class="card"><div class="label">System Disk</div><div class="val">$($sys.DiskMediaType) ($($sys.FreeDiskGB) GB Free)</div></div>
    <div class="card"><div class="label">Active Tweaks</div><div class="val">$appliedCount / $totalCount</div></div>
    <div class="card"><div class="label">Update Guard</div><div class="val">$($guard.State)</div></div>
  </div>
  <h2>Tweak Status &amp; Drift Verification ($ProfileName Profile)</h2>
  <table>
    <thead><tr><th>ID</th><th>Category</th><th>Tweak</th><th>Risk</th><th>Status</th><th>Current Value</th></tr></thead>
    <tbody>$rowsHtml</tbody>
  </table>
  <h2>Top 10 Memory Consumers</h2>
  <table>
    <thead><tr><th>Application</th><th>Processes</th><th>Working Set (MB)</th><th>Safety Tier</th></tr></thead>
    <tbody>$procHtml</tbody>
  </table>
</body>
</html>
"@
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8 -Force
    Write-WBLog "Exported telemetry reports to:`n  - $htmlPath`n  - $mdPath" "OK"

    return [PSCustomObject]@{
        MarkdownPath = $mdPath
        HtmlPath     = $htmlPath
    }
}

Export-ModuleMember -Function @(
    'Get-WBPaths',
    'Write-WBLog',
    'Test-WBAdmin',
    'Get-WBTweakCatalog',
    'Get-WBMemorySnapshot',
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
