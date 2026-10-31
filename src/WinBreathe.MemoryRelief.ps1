#Requires -Version 5.1
# Narrow, non-terminating relief. Never target arbitrary apps, AI, VPN or WebView.
function Test-WBReliefTarget {
    param([string]$Name,[string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $windows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows).TrimEnd('\')
    $programFiles=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles).TrimEnd('\')
    # Exact protected installation roots and known package names, not name alone.
    $rules=@{
        SearchHost = '^'+[regex]::Escape($windows)+'\\SystemApps\\MicrosoftWindows\.Client\.(CBS|Core)_[^\\]+\\SearchHost\.exe$'
        SearchUI = '^'+[regex]::Escape($windows)+'\\SystemApps\\Microsoft\.Windows\.Cortana_[^\\]+\\SearchUI\.exe$'
        Widgets = '^'+[regex]::Escape($programFiles)+'\\WindowsApps\\MicrosoftWindows\.Client\.WebExperience_[^\\]+\\Dashboard\\Widgets\.exe$'
    }
    return $rules.ContainsKey($Name) -and $Path -match $rules[$Name] -and $Path -notmatch '\\.\.\\'
}

function New-WBReliefState {
    [pscustomobject]@{Previous=@{};LastSample=[DateTimeOffset]::MinValue;LastAttempt=[DateTimeOffset]::MinValue;CooldownSeconds=300;PressureSince=[DateTimeOffset]::MinValue}
}

function Get-WBReliefCandidates {
    $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
    foreach($process in @(Get-Process -Name SearchHost,SearchUI,Widgets -ErrorAction SilentlyContinue)) {
        try {
            if($process.SessionId -eq 0 -or $process.SessionId -ne $session){continue}
            $path=$process.Path
            if(-not (Test-WBReliefTarget $process.ProcessName $path)){continue}
            [pscustomobject]@{Id=$process.Id;Name=$process.ProcessName;Path=$path;Started=$process.StartTime.ToUniversalTime().ToFileTimeUtc();CpuMs=$process.TotalProcessorTime.TotalMilliseconds;WorkingMB=$process.WorkingSet64/1MB}
        } catch { } finally {$process.Dispose()}
    }
}

function Invoke-WBReliefNative {
    param($Candidate)
    if(-not ([Management.Automation.PSTypeName]'WinBreatheV230.MemoryRelief').Type){Add-Type -Path (Join-Path $PSScriptRoot 'WinBreathe.MemoryRelief.cs') -ErrorAction Stop}
    [WinBreatheV230.MemoryRelief]::Trim($Candidate.Id,$Candidate.Started,$Candidate.Path,$Candidate.CpuMs)
}

function Invoke-WBMemoryRelief {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)]$Snapshot,[switch]$Automatic,[switch]$ObserveOnly,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $pressure=Get-WBMemoryPressure $Snapshot
    $gap=($Now-$State.LastSample).TotalSeconds
    if($State.LastSample -ne [DateTimeOffset]::MinValue -and ($gap -gt 30 -or $gap -le 0)){$State.Previous=@{};$State.PressureSince=[DateTimeOffset]::MinValue}
    $State.LastSample=$Now
    $rows=@();$eligible=@();$current=@{}
    foreach($candidate in @(Get-WBReliefCandidates)) {
        $key=[string]$candidate.Id
        if($State.Previous.ContainsKey($key)) {
            $old=$State.Previous[$key];$seconds=($Now-$old.Time).TotalSeconds
            if($old.Started -eq $candidate.Started -and $seconds -ge 2 -and $seconds -le 30 -and
                $candidate.CpuMs -ge $old.CpuMs -and $candidate.CpuMs-$old.CpuMs -le 100 -and $candidate.WorkingMB -ge 32) {$eligible+=$candidate}
        }
        $current[$key]=[pscustomobject]@{Time=$Now;Started=$candidate.Started;CpuMs=$candidate.CpuMs}
    }
    $State.Previous=$current
    $lowRam=$pressure.Level -ne 'Unknown' -and $Snapshot.AvailRAMMB -le [math]::Max(768,0.20*$Snapshot.TotalRAMMB)
    if(-not $lowRam){$State.PressureSince=[DateTimeOffset]::MinValue}
    elseif($State.PressureSince -eq [DateTimeOffset]::MinValue -or $Now -lt $State.PressureSince){$State.PressureSince=$Now}
    $reason=''
    if($ObserveOnly){$reason='Idle host samples updated; relief is off.'}
    elseif($pressure.Level -eq 'Unknown'){$reason='Memory reading unavailable; no relief attempted.'}
    elseif($pressure.KernelConcern){$reason='Kernel pressure needs investigation; trimming apps cannot repair it.'}
    elseif($Snapshot.AvailRAMMB -le 256){$reason='Too little RAM for relief work; save work and pause new tasks.'}
    elseif($pressure.CommitPercent -ge 90 -or $pressure.CommitHeadroomMB -le 1024){$reason='Commit headroom is too low; trimming does not release committed memory. Save work and pause new tasks.'}
    elseif($Automatic -and (-not $lowRam -or ($Now-$State.PressureSince).TotalSeconds -lt 30)){$reason='Waiting for sustained low available RAM.'}
    elseif(($Now-$State.LastAttempt).TotalSeconds -lt $State.CooldownSeconds){$reason='Relief cooldown is active.'}
    elseif($eligible.Count -eq 0){$reason='No verified idle optional Windows hosts are eligible.'}
    if($reason){return [pscustomobject]@{Attempted=$false;Trimmed=0;Reason=$reason;Results=@();AvailableChangeMB=$null;CommitChangeMB=$null}}
    $attempted=$false
    foreach($candidate in @($eligible|Sort-Object WorkingMB -Descending|Select-Object -First 3)) {
        if($PSCmdlet.ShouldProcess("$($candidate.Name) ($($candidate.Id))",'Release pageable working-set pages; do not close the process')) {
            $attempted=$true
            try {$result=Invoke-WBReliefNative $candidate} catch {$result='Skipped: relief API unavailable'}
            $rows+=[pscustomobject]@{Name=$candidate.Name;Id=$candidate.Id;Status=$result}
        }
    }
    $trimmed=@($rows|Where-Object Status -eq 'Trimmed').Count
    $availableChange=$null;$commitChange=$null
    if($attempted) {
        $State.LastAttempt=$Now
        try {$after=Get-WBMemorySnapshot -ErrorAction Stop;$availableChange=$after.AvailRAMMB-$Snapshot.AvailRAMMB;$commitChange=[math]::Round($after.CommitUsedMB-$Snapshot.CommitUsedMB,1)}catch{}
        # Stop repeated ineffective paging; never chase a RAM percentage.
        $State.CooldownSeconds=if($trimmed -eq 0 -or $null -eq $availableChange -or $availableChange -lt 32){900}else{300}
    }
    [pscustomobject]@{Attempted=$attempted;Trimmed=$trimmed;Reason='No apps closed. Any working-set reduction can refill; commit and kernel allocations are not repaired.';Results=$rows;AvailableChangeMB=$availableChange;CommitChangeMB=$commitChange}
}
