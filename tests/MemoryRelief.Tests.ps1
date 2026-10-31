#Requires -Version 5.1
# No user processes are trimmed or terminated. Only the disposable child below.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/WinBreathe.MemoryWatch.ps1')
. (Join-Path $root 'src/WinBreathe.MemoryRelief.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message};Write-Host "PASS: $Message"}
$windows=[Environment]::GetFolderPath('Windows')
Assert (Test-WBReliefTarget 'SearchHost' "$windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\SearchHost.exe") 'Known Windows Search package qualifies'
foreach($item in @(@('SearchHost','C:\Users\user\SearchHost.exe'),@('SearchHost',"$windows\SystemApps\other\SearchHost.exe"),@('ChatGPT','C:\Program Files\ChatGPT.exe'),@('msedgewebview2',"$windows\SystemApps\MicrosoftWindows.Client.CBS_x\msedgewebview2.exe"),@('SearchHost',"$windows\SystemApps\MicrosoftWindows.Client.CBS_x\..\SearchHost.exe"))) {
    Assert (-not (Test-WBReliefTarget $item[0] $item[1])) 'Unverified or protected target cannot qualify for relief'
}
$script:nativeCalls=0
$script:candidate=[pscustomobject]@{Id=123;Name='SearchHost';Path='synthetic';Started=1L;CpuMs=100.0;WorkingMB=200}
function Get-WBReliefCandidates {$script:candidate}
function Invoke-WBReliefNative {param($Candidate);$script:nativeCalls++;'Trimmed'}
function Snapshot([int]$Available=1400,[int]$Commit=8000,[int]$Paged=400){[pscustomobject]@{TotalRAMMB=8192;AvailRAMMB=$Available;CommitUsedMB=$Commit;CommitTotalMB=20000;KernelPagedMB=$Paged;KernelNonpagedMB=300}}
function Get-WBMemorySnapshot {Snapshot 1500}
$t=[DateTimeOffset]'2026-10-30T00:00:00Z'
$state=New-WBReliefState
[void](Invoke-WBMemoryRelief $state (Snapshot) -Automatic -Now $t)
Assert ($script:nativeCalls -eq 0) 'A single sample cannot trim a host'
[void](Invoke-WBMemoryRelief $state (Snapshot) -Automatic -Now ($t.AddSeconds(15)))
Assert ($script:nativeCalls -eq 0) 'Automatic relief waits for sustained pressure'
$result=Invoke-WBMemoryRelief $state (Snapshot) -Automatic -Now ($t.AddSeconds(30)) -Confirm:$false
Assert ($script:nativeCalls -eq 1 -and $result.Trimmed -eq 1 -and $result.AvailableChangeMB -eq 100) 'Sustained pressure permits one bounded relief attempt'
[void](Invoke-WBMemoryRelief $state (Snapshot) -Now ($t.AddSeconds(33)) -Confirm:$false)
Assert ($script:nativeCalls -eq 1) 'Manual and automatic actions share a cooldown'
foreach($bad in @([pscustomobject]@{},(Snapshot -Commit 19500),(Snapshot -Paged 5000),(Snapshot -Available 100))) {
    $s=New-WBReliefState
    [void](Invoke-WBMemoryRelief $s $bad -Now $t)
    [void](Invoke-WBMemoryRelief $s $bad -Now ($t.AddSeconds(3)))
}
Assert ($script:nativeCalls -eq 1) 'Invalid, commit, kernel and extreme physical pressure cannot trigger trims'
$s=New-WBReliefState
[void](Invoke-WBMemoryRelief $s (Snapshot) -Now $t)
[void](Invoke-WBMemoryRelief $s (Snapshot) -Now ($t.AddSeconds(3)) -WhatIf)
Assert ($script:nativeCalls -eq 1 -and $s.LastAttempt -eq [DateTimeOffset]::MinValue) 'Preview never trims or consumes cooldown'
$script:candidate.Started=2L
[void](Invoke-WBMemoryRelief $s (Snapshot) -Now ($t.AddSeconds(6)))
Assert ($script:nativeCalls -eq 1) 'PID reuse invalidates eligibility'
$script:candidate.CpuMs=1000
[void](Invoke-WBMemoryRelief $s (Snapshot) -Now ($t.AddSeconds(9)))
Assert ($script:nativeCalls -eq 1) 'Busy process is skipped'
[void](Invoke-WBMemoryRelief $s (Snapshot) -Now ($t.AddSeconds(100)))
Assert ($script:nativeCalls -eq 1) 'Stale idle samples are discarded'
function Get-WBMemorySnapshot {Snapshot}
$r=Invoke-WBMemoryRelief $s (Snapshot) -Now ($t.AddSeconds(103)) -Confirm:$false
Assert ($s.CooldownSeconds -eq 900) 'Ineffective relief backs off for fifteen minutes'
$gapState=New-WBReliefState
[void](Invoke-WBMemoryRelief $gapState (Snapshot) -Automatic -Now $t)
[void](Invoke-WBMemoryRelief $gapState (Snapshot) -Automatic -Now ($t.AddSeconds(15)))
$calls=$script:nativeCalls
[void](Invoke-WBMemoryRelief $gapState (Snapshot) -Automatic -Now ($t.AddSeconds(90)))
[void](Invoke-WBMemoryRelief $gapState (Snapshot) -Automatic -Now ($t.AddSeconds(93)))
Assert ($script:nativeCalls -eq $calls) 'A sleep or collection gap restarts the sustained-pressure timer'
# Compile and exercise the real native guard against this test process with a
# deliberately wrong identity. It must reject BEFORE EmptyWorkingSet is reached.
Add-Type -Path (Join-Path $root 'src/WinBreathe.MemoryRelief.cs')
$native=[WinBreatheV230.MemoryRelief]::Trim($PID,0L,'C:\invalid.exe',0)
Assert ($native -like 'Skipped:*') 'Native handle identity guard rejects a mismatched live process'
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=Join-Path $PSHOME 'powershell.exe'
$payload="[Console]::WriteLine('READY'); Start-Sleep -Seconds 10"
$start.Arguments='-NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true
$child=[Diagnostics.Process]::Start($start)
try {
    $ready=$child.StandardOutput.ReadLineAsync()
    Assert ($ready.Wait(10000) -and $ready.Result -eq 'READY') 'Disposable native-test child is idle and ready'
    Start-Sleep -Milliseconds 500
    $child.Refresh()
    $native=[WinBreatheV230.MemoryRelief]::Trim($child.Id,$child.StartTime.ToUniversalTime().ToFileTimeUtc(),$child.MainModule.FileName,$child.TotalProcessorTime.TotalMilliseconds)
    Assert ($native -eq 'Trimmed') 'Real native relief succeeds on the verified idle test child without closing it'
    Assert (-not $child.HasExited) 'Trimming keeps the test child running'
} finally {
    # This handle was created above by the test; never discover/kill by name.
    if(-not $child.HasExited){$child.Kill();$child.WaitForExit(5000)|Out-Null}
    $child.Dispose()
}
Write-Host 'Memory relief regressions passed.'
