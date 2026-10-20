#Requires -Version 5.1
# Read-only host diagnostics. Never terminates processes or changes settings.
param([ValidateRange(1,12)][int]$Samples = 4, [ValidateRange(1,30)][int]$IntervalSeconds = 10)
$ErrorActionPreference = 'Stop'
$rows = @()
for ($i = 0; $i -lt $Samples; $i++) {
    $os = Get-CimInstance Win32_OperatingSystem
    $m = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
    $rows += [pscustomobject]@{
        TimeUTC = [DateTime]::UtcNow.ToString('o')
        TotalMB = [int]($os.TotalVisibleMemorySize / 1024)
        AvailableMB = $m.AvailableMBytes
        UsedPercent = [math]::Round(100 * (1 - $m.AvailableMBytes / ($os.TotalVisibleMemorySize / 1024)), 1)
        StandbyMB = [int](($m.StandbyCacheNormalPriorityBytes + $m.StandbyCacheReserveBytes + $m.StandbyCacheCoreBytes) / 1MB)
        CommitMB = [int]($m.CommittedBytes / 1MB)
        CommitLimitMB = [int]($m.CommitLimit / 1MB)
        NonpagedPoolMB = [int]($m.PoolNonpagedBytes / 1MB)
        PagedPoolMB = [int]($m.PoolPagedBytes / 1MB)
        PagesInputPerSecond = $m.PagesInputPersec
        DiskReadsForPagingPerSecond = $m.PageReadsPersec
    }
    if ($i -lt ($Samples - 1)) { Start-Sleep -Seconds $IntervalSeconds }
}
$apps = @(Get-Process | Group-Object ProcessName | ForEach-Object {
    [pscustomobject]@{
        App = $_.Name; Processes = $_.Count
        WorkingSetMB = [int](($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
        PrivateCommitMB = [int](($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum / 1MB)
    }
} | Sort-Object WorkingSetMB -Descending | Select-Object -First 20)
$memoryFeatures = $null
$featureError = $null
try { $memoryFeatures = Get-MMAgent -ErrorAction Stop | Select-Object MemoryCompression, PageCombining, ApplicationPreLaunch }
catch { $featureError = $_.Exception.Message }
[pscustomobject]@{
    Note = 'Read-only observations. Working sets contain shared pages; do not sum them as total physical RAM. Standby is part of available memory. Private commit is not resident RAM.'
    Samples = $rows
    Apps = $apps
    MemoryFeatures = $memoryFeatures
    MemoryFeatureReadError = $featureError
    Pagefiles = @(Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage)
    Guard = @(Get-ScheduledTask -TaskName 'WinBreathe_UpdateGuard' -ErrorAction SilentlyContinue | Select-Object TaskName, State)
} | ConvertTo-Json -Depth 6
