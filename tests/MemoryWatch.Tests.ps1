#Requires -Version 5.1
# Synthetic pressure/event tests. No memory stress, process killing or system tweaks.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/WinBreathe.MemoryWatch.ps1')
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message};Write-Host "PASS: $Message"}
function Sample([double]$Commit=7000,[double]$Available=2500,[double]$Paged=400,[double]$Nonpaged=300){[pscustomobject]@{TotalRAMMB=8192;AvailRAMMB=$Available;CommitTotalMB=20000;CommitUsedMB=$Commit;KernelPagedMB=$Paged;KernelNonpagedMB=$Nonpaged}}
$normal=Sample
Assert ((Get-WBMemoryPressure $normal).Level -eq 'Healthy') 'Normal headroom is healthy'
$nearLimit=Sample -Commit 19760 -Available 1500
Assert ((Get-WBMemoryPressure $nearLimit).Level -eq 'Critical') 'Commit exhaustion alerts even when physical RAM remains available'
$largePool=Sample -Paged 10000 -Available 1500
$pressure=Get-WBMemoryPressure $largePool
Assert ($pressure.Level -eq 'Critical' -and $pressure.KernelConcern) 'Large kernel pools are detected independently of app/RAM usage'
Assert ((Get-WBMemoryPressure (Sample -Available 200)).Level -eq 'Critical') 'Very low available RAM triggers a critical assessment'
foreach($bad in @([pscustomobject]@{},(Sample -Commit -1),(Sample -Commit 21000),(Sample -Paged ([double]::NaN)),(Sample -Available 99999))){Assert ((Get-WBMemoryPressure $bad).Level -eq 'Unknown') 'Invalid telemetry is never reported as safe'}
$state=New-WBMemoryWatchState
$now=[DateTimeOffset]'2026-10-27T00:00:00Z'
$first=Update-WBMemoryWatch $state $normal $now
Assert ($first.Level -eq 'Healthy' -and -not $first.Notify -and $first.ShouldJournal) 'Initial healthy reading records state without a warning'
$warning=Sample -Commit 17500
$early=Update-WBMemoryWatch $state $warning ($now.AddSeconds(3))
Assert (-not $early.Notify) 'One warning sample does not cause alert chatter'
$sustained=Update-WBMemoryWatch $state $warning ($now.AddSeconds(9))
Assert ($sustained.Level -eq 'Warning' -and $sustained.Notify) 'Sustained pressure produces an early warning'
$repeat=Update-WBMemoryWatch $state $warning ($now.AddSeconds(12))
Assert (-not $repeat.Notify) 'Warnings are rate limited'
$escalated=Update-WBMemoryWatch $state $nearLimit ($now.AddSeconds(15))
Assert ($escalated.Level -eq 'Critical' -and $escalated.Notify) 'Critical pressure bypasses warning cooldown immediately'
$uncertain=Update-WBMemoryWatch $state ([pscustomobject]@{}) ($now.AddSeconds(18))
Assert ($uncertain.Level -eq 'Unknown') 'A failed reading marks monitoring unavailable'
[void](Update-WBMemoryWatch $state $normal ($now.AddSeconds(21)))
[void](Update-WBMemoryWatch $state $warning ($now.AddSeconds(24)))
[void](Update-WBMemoryWatch $state $warning ($now.AddSeconds(30)))
$borderline=Update-WBMemoryWatch $state (Sample -Commit 16600) ($now.AddSeconds(33))
Assert ($borderline.Level -eq 'Warning') 'Recovery requires more headroom than the alert entry threshold'
[void](Update-WBMemoryWatch $state $normal ($now.AddSeconds(36)))
[void](Update-WBMemoryWatch $state $normal ($now.AddSeconds(45)))
$recovered=Update-WBMemoryWatch $state $normal ($now.AddSeconds(51))
Assert ($recovered.Level -eq 'Healthy') 'Stable recovery clears the warning after hysteresis'
$gapState=New-WBMemoryWatchState
[void](Update-WBMemoryWatch $gapState $normal $now)
[void](Update-WBMemoryWatch $gapState $warning ($now.AddSeconds(3)))
$afterGap=Update-WBMemoryWatch $gapState $warning ($now.AddSeconds(90))
Assert (-not $afterGap.Notify -and $afterGap.Level -eq 'Unknown') 'A sleep/collection gap does not count as sustained observed pressure'
# Forecast before fixed thresholds, with no single-spike extrapolation.
$growing=New-WBMemoryWatchState
foreach($second in 0,15,30,45,60,75){$growth=Update-WBMemoryWatch $growing (Sample -Commit (12500+10*$second)) ($now.AddSeconds($second))}
Assert ($growth.Level -eq 'Warning' -and $growth.Trend.MinutesToCommitLimit -gt 0) 'Sustained commit growth warns before 85 percent usage'
$kernelGrowing=New-WBMemoryWatchState
foreach($second in 0,15,30,45,60,75){$growth=Update-WBMemoryWatch $kernelGrowing (Sample -Paged (700+5*$second)) ($now.AddSeconds($second))}
Assert ($growth.Trend.Warn -and $growth.Level -eq 'Warning') 'Steady kernel growth warns before fixed pool thresholds'
$spike=New-WBMemoryWatchState
foreach($second in 0,15,30,45){[void](Update-WBMemoryWatch $spike (Sample -Commit 12000) ($now.AddSeconds($second)))}
$one=Update-WBMemoryWatch $spike (Sample -Commit 15000) ($now.AddSeconds(60))
Assert (-not $one.Trend.Warn) 'One allocation spike is not labeled sustained growth'
[void](Update-WBMemoryWatch $growing ([pscustomobject]@{}) ($now.AddSeconds(78)))
Assert ($growing.Samples.Count -eq 0) 'Invalid reading clears forecast history'
$bounded=New-WBMemoryWatchState
for($i=0;$i -lt 400;$i++){[void](Update-WBMemoryWatch $bounded $normal ($now.AddSeconds(3*$i)))}
Assert ($bounded.Samples.Count -le 101) 'Growth history stays bounded in long sessions'
$xml=@'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><System><Provider Name="Microsoft-Windows-Resource-Exhaustion-Detector"/><EventID>2004</EventID><TimeCreated SystemTime="2026-10-27T00:33:57Z"/></System><UserData><MemoryExhaustionInfo xmlns="http://www.microsoft.com/Windows/Resource/Exhaustion/Detector/Events"><SystemInfo><SystemCommitLimit>21340155904</SystemCommitLimit><SystemCommitCharge>21073801216</SystemCommitCharge><PagedPoolUsage>10695479296</PagedPoolUsage><NonPagedPoolUsage>515018752</NonPagedPoolUsage></SystemInfo><PagedPoolInfo><Tag_1><Name>FMfn</Name><PoolUsed>8774238528</PoolUsed></Tag_1></PagedPoolInfo></MemoryExhaustionInfo></UserData></Event>
'@
$incident=ConvertFrom-WBMemoryEvent $xml
Assert ($incident.CommitPercent -gt 98 -and $incident.KernelPagedMB -gt 10000 -and $incident.TopPagedPoolTag -eq 'FMfn') 'Exhaustion event parser retains commit, kernel pool and allocation tag evidence'
$restart='<Event><System><Provider Name="Microsoft-Windows-Kernel-Power"/><EventID>41</EventID><TimeCreated SystemTime="2026-10-27T00:40:28Z"/></System><EventData><Data Name="BugcheckCode">239</Data></EventData></Event>'
Assert ((ConvertFrom-WBMemoryEvent $restart).BugcheckCode -eq '0x000000EF') 'Restart stop codes are decoded without guessing the cause'
Assert ($null -eq (ConvertFrom-WBMemoryEvent ($restart.Replace('239','0'))).BugcheckCode) 'A missing stop code is not invented'
$rejected=$false
try{ConvertFrom-WBMemoryEvent '<!DOCTYPE x [<!ENTITY e SYSTEM "file:///C:/never-read">]><Event>&e;</Event>'}catch{$rejected=$true}
Assert $rejected 'Event parser rejects external XML entities'
function Get-WinEvent {throw [UnauthorizedAccessException]::new('Synthetic history access denied')}
$history=Get-WBMemoryIncidents
Assert (-not $history.Complete -and $history.Events.Count -eq 0) 'Unreadable history is incomplete rather than a clean bill of health'
$fixture=Join-Path $PSScriptRoot ('memory-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
try {
    $path=Join-Path $fixture 'memory.jsonl'
    1..25|ForEach-Object{Assert (Write-WBMemoryJournal $path $normal 'Healthy' -MaxBytes 1024) 'Bounded journal append succeeds'}
    $files=@(Get-ChildItem -LiteralPath $fixture -File)
    Assert ($files.Count -le 2 -and @($files|Where-Object Length -gt 1024).Count -eq 0) 'Journal rotates within two bounded files'
    foreach($file in $files){foreach($line in Get-Content -LiteralPath $file.FullName){$record=$line|ConvertFrom-Json;Assert ($record.PSObject.Properties.Name -notcontains 'CommandLine') 'Journal excludes private command lines'}}
    Assert (-not (Write-WBMemoryJournal $fixture $normal 'Healthy')) 'Journal failure does not crash monitoring'
}finally{foreach($file in Get-ChildItem -LiteralPath $fixture -File){Remove-Item -LiteralPath $file.FullName};Remove-Item -LiteralPath $fixture}
# Bound actual asynchronous child output, not just a mirrored mock queue.
Add-Type -Path (Join-Path $root 'src/WinBreathe.ProcessOutput.cs')
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=Join-Path $PSHOME 'powershell.exe'
$payload="1..6000 | ForEach-Object { [Console]::WriteLine('row-' + `$_) }; [Console]::WriteLine(('x' * 20000))"
$start.Arguments='-NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
$child=[Diagnostics.Process]::Start($start);$buffer=New-Object WBProcessOutput($child)
try{
    Assert ($child.WaitForExit(15000)) 'High-output synthetic task terminates without a blocked pipe'
    $child.WaitForExit()
    $count=0;$omitted=$false
    while(-not $buffer.Complete){$line=$buffer.ReadAvailable();if($null -ne $line){$count++;if($line -match 'omitted to bound memory'){$omitted=$true}}}
    Assert ($count -le 2001 -and $omitted) 'Child output memory is capped and omitted output is disclosed'
}finally{$buffer.Dispose();$child.Dispose()}
$start.Arguments='-NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("1..10000 | ForEach-Object { [Console]::Write(('x' * 1024)) }"))
$child=[Diagnostics.Process]::Start($start);$buffer=New-Object WBProcessOutput($child)
try {
    Assert ($child.WaitForExit(30000)) 'A ten-megabyte line without newlines drains without blocking'
    $deadline=[DateTime]::UtcNow.AddSeconds(10);$longLine=$null
    while(-not $buffer.Complete -and [DateTime]::UtcNow -lt $deadline){$line=$buffer.ReadAvailable();if($null -ne $line){$longLine=$line}else{Start-Sleep -Milliseconds 10}}
    Assert ($buffer.Complete -and $null -ne $longLine -and $longLine.Length -lt 4200 -and $longLine.EndsWith('[truncated]')) 'Unterminated output is bounded before a full line is allocated'
}finally{$buffer.Dispose();$child.Dispose()}
# A source-module update in a long-lived PowerShell host must not reuse the
# v2.1.2 native class, which did not expose GetPerformanceInfo.
Add-Type -TypeDefinition 'public class Win32Mem { } public struct MEMORYSTATUSEX { public int Legacy; }'
Import-Module (Join-Path $root 'src/WinBreathe.Engine.psm1') -Force -ErrorAction Stop
$live=Get-WBMemorySnapshot
Assert ($live.CommitTotalMB -gt 0 -and $live.KernelPagedMB -ge 0) 'New native telemetry coexists with previously loaded legacy types'
Write-Host 'Memory Watch regressions passed.'
