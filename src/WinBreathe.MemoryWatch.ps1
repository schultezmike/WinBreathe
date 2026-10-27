#Requires -Version 5.1
# Advisory monitoring only. No process termination, kernel changes or pagefile writes.
function Get-WBMemoryPressure {
    param([Parameter(Mandatory=$true)]$Snapshot)
    $valid = $true
    foreach ($name in @('TotalRAMMB','AvailRAMMB','CommitTotalMB','CommitUsedMB','KernelPagedMB','KernelNonpagedMB')) {
        $number=0.0
        if ($null -eq $Snapshot.PSObject.Properties[$name] -or $null -eq $Snapshot.$name -or
            -not [double]::TryParse([string]$Snapshot.$name, [ref]$number) -or
            [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0) { $valid=$false }
    }
    if ($valid) {
        $valid = $Snapshot.TotalRAMMB -gt 0 -and $Snapshot.CommitTotalMB -gt 0 -and
            $Snapshot.AvailRAMMB -le $Snapshot.TotalRAMMB -and $Snapshot.CommitUsedMB -le $Snapshot.CommitTotalMB
    }
    if (-not $valid) { return [pscustomobject]@{Level='Unknown';CommitPercent=$null;CommitHeadroomMB=$null;KernelConcern=$false;CanClear=$false;Summary='Memory reading unavailable. Monitoring cannot assess risk.';Reasons=@('Invalid or incomplete memory reading.')} }
    $commitPercent=100.0 * $Snapshot.CommitUsedMB / $Snapshot.CommitTotalMB
    $headroom=$Snapshot.CommitTotalMB-$Snapshot.CommitUsedMB
    $availablePercent=100.0*$Snapshot.AvailRAMMB/$Snapshot.TotalRAMMB
    $pagedRatio=$Snapshot.KernelPagedMB/$Snapshot.TotalRAMMB
    $nonpagedRatio=$Snapshot.KernelNonpagedMB/$Snapshot.TotalRAMMB
    $kernelWarning=($Snapshot.KernelPagedMB -ge 512 -and $pagedRatio -ge 0.25) -or ($Snapshot.KernelNonpagedMB -ge 512 -and $nonpagedRatio -ge 0.20)
    $kernelCritical=($Snapshot.KernelPagedMB -ge 1024 -and $pagedRatio -ge 0.50) -or ($Snapshot.KernelNonpagedMB -ge 1024 -and $nonpagedRatio -ge 0.35)
    $reasons=@()
    if ($commitPercent -ge 85 -or $headroom -le 1024) { $reasons+='Windows is close to its total memory commitment limit.' }
    if ($availablePercent -le 10 -or $Snapshot.AvailRAMMB -le 512) { $reasons+='Little physical RAM is available for new work.' }
    if ($kernelWarning) { $reasons+='Windows kernel memory is unusually large. Investigate drivers and filters; closing browser tabs may not resolve it.' }
    $level=if ($commitPercent -ge 95 -or $headroom -le 512 -or $availablePercent -le 5 -or $Snapshot.AvailRAMMB -le 256 -or $kernelCritical) { 'Critical' }
        elseif ($reasons.Count) { 'Warning' } else { 'Healthy' }
    $summary=switch ($level) {
        'Critical' { 'Memory pressure is critical. Save work now and pause new workloads. WinBreathe cannot guarantee prevention of a crash.' }
        'Warning' { 'Memory pressure is rising. Save work and avoid starting more memory-heavy tasks.' }
        default { 'Memory headroom is available at this reading.' }
    }
    [pscustomobject]@{
        Level=$level;CommitPercent=[math]::Round($commitPercent,1);CommitHeadroomMB=[math]::Round($headroom,1)
        KernelConcern=[bool]$kernelWarning;Reasons=$reasons;Summary=$summary
        CanClear=($commitPercent -lt 80 -and $headroom -gt 1536 -and $availablePercent -gt 12 -and $Snapshot.AvailRAMMB -gt 640 -and -not $kernelWarning)
    }
}

function New-WBMemoryWatchState {
    [pscustomobject]@{Level='Unknown';Pending='';PendingSince=[DateTimeOffset]::MinValue;LastSample=[DateTimeOffset]::MinValue;LastAlert=[DateTimeOffset]::MinValue;LastJournal=[DateTimeOffset]::MinValue}
}

function Update-WBMemoryWatch {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)]$Snapshot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $reading=Get-WBMemoryPressure $Snapshot
    $previous=$State.Level
    $gap=($Now-$State.LastSample).TotalSeconds
    if ($State.LastSample -ne [DateTimeOffset]::MinValue -and ($gap -gt 30 -or $gap -lt 0)) { $State.Pending='';$State.Level='Unknown' }
    $State.LastSample=$Now
    if ($reading.Level -eq 'Unknown') { $State.Level='Unknown';$State.Pending='' }
    elseif ($reading.Level -eq 'Critical') { $State.Level='Critical';$State.Pending='' }
    elseif ($State.Level -eq 'Unknown' -and $reading.Level -eq 'Healthy') { $State.Level='Healthy';$State.Pending='' }
    elseif ($reading.Level -eq $State.Level) { $State.Pending='' }
    else {
        $allowChange=$reading.Level -ne 'Healthy' -or $reading.CanClear
        if (-not $allowChange) { $State.Pending='' }
        else {
            if ($State.Pending -ne $reading.Level) { $State.Pending=$reading.Level;$State.PendingSince=$Now }
            $delay=if ($State.Level -eq 'Healthy' -or $State.Level -eq 'Unknown') {6} else {15}
            if (($Now-$State.PendingSince).TotalSeconds -ge $delay) { $State.Level=$reading.Level;$State.Pending='' }
        }
    }
    $changed=$previous -ne $State.Level
    $notify=$State.Level -in @('Warning','Critical') -and ($changed -or ($Now-$State.LastAlert).TotalSeconds -ge 300)
    if ($notify) { $State.LastAlert=$Now }
    $journal=$changed -or ($Now-$State.LastJournal).TotalSeconds -ge 60
    if ($journal) {$State.LastJournal=$Now}
    [pscustomobject]@{Level=$State.Level;Reading=$reading;Changed=$changed;Notify=[bool]$notify;ShouldJournal=[bool]$journal}
}

function Write-WBMemoryJournal {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Snapshot,[Parameter(Mandatory=$true)][ValidateSet('Healthy','Warning','Critical','Unknown')][string]$Level,[ValidateRange(1024,4194304)][int]$MaxBytes=1048576)
    # Fixed small rows and two bounded files. Do not retain process command lines,
    # user names or an ever-growing in-memory sample list.
    $row=[ordered]@{UTC=[DateTimeOffset]::UtcNow.ToString('o');Level=$Level}
    foreach($name in @('TotalRAMMB','AvailRAMMB','CommitUsedMB','CommitTotalMB','KernelPagedMB','KernelNonpagedMB')) {
        $value=$null
        if ($null -ne $Snapshot.PSObject.Properties[$name]) {
            $number=0.0
            if([double]::TryParse([string]$Snapshot.$name,[ref]$number) -and -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)){$value=$number}
        }
        $row[$name]=$value
    }
    $bytes=[Text.Encoding]::UTF8.GetBytes(($row|ConvertTo-Json -Compress)+"`n")
    try {
        foreach($candidate in @((Split-Path -Parent $Path),$Path,"$Path.previous")) {
            if((Test-Path -LiteralPath $candidate) -and ((Get-Item -LiteralPath $candidate -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Untrusted journal path'}
        }
        if((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length+$bytes.Length -gt $MaxBytes) {
            Move-Item -LiteralPath $Path -Destination "$Path.previous" -Force -ErrorAction Stop
        }
        $file=[IO.File]::Open($Path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{$file.Write($bytes,0,$bytes.Length)}finally{$file.Dispose()}
        return $true
    } catch { return $false }
}

function ConvertFrom-WBMemoryEvent {
    param([Parameter(Mandatory=$true)][ValidateLength(1,262144)][string]$Xml)
    # Disable external entities. Read only known fields; do not include usernames,
    # event messages, dump payloads or process command lines in app reports.
    $settings=New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
    $settings.MaxCharactersInDocument=262144
    $settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create([IO.StringReader]::new($Xml),$settings)
    $document=New-Object Xml.XmlDocument
    $document.XmlResolver=$null
    try{$document.Load($reader)}finally{$reader.Dispose()}
    $eventId=[int]$document.SelectSingleNode('/*[local-name()="Event"]/*[local-name()="System"]/*[local-name()="EventID"]').InnerText
    $provider=$document.SelectSingleNode('/*[local-name()="Event"]/*[local-name()="System"]/*[local-name()="Provider"]').GetAttribute('Name')
    $time=$document.SelectSingleNode('/*[local-name()="Event"]/*[local-name()="System"]/*[local-name()="TimeCreated"]').GetAttribute('SystemTime')
    if($eventId -eq 2004 -and $provider -eq 'Microsoft-Windows-Resource-Exhaustion-Detector') {
        $info=$document.SelectSingleNode('//*[local-name()="MemoryExhaustionInfo"]')
        if($null -eq $info){throw 'Missing memory exhaustion details'}
        $values=@{}
        foreach($name in @('SystemCommitLimit','SystemCommitCharge','PagedPoolUsage','NonPagedPoolUsage')) {
            $node=$info.SelectSingleNode('./*[local-name()="SystemInfo"]/*[local-name()="'+$name+'"]')
            $number=0.0
            if($null -eq $node -or -not [double]::TryParse($node.InnerText,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0){throw 'Invalid event memory values'}
            $values[$name]=$number
        }
        if($values.SystemCommitLimit -le 0){throw 'Invalid commit limit'}
        $tag=$info.SelectSingleNode('./*[local-name()="PagedPoolInfo"]/*[local-name()="Tag_1"]/*[local-name()="Name"]')
        $tagName=if($null -ne $tag -and $tag.InnerText -match '^[a-zA-Z0-9 ]{1,4}$'){$tag.InnerText}else{'Unknown'}
        return [pscustomobject]@{Id=2004;TimeUTC=$time;Kind='MemoryExhaustion';CommitPercent=[math]::Round(100*$values.SystemCommitCharge/$values.SystemCommitLimit,1);CommitUsedMB=[math]::Round($values.SystemCommitCharge/1MB);CommitTotalMB=[math]::Round($values.SystemCommitLimit/1MB);KernelPagedMB=[math]::Round($values.PagedPoolUsage/1MB);KernelNonpagedMB=[math]::Round($values.NonPagedPoolUsage/1MB);TopPagedPoolTag=$tagName;BugcheckCode=$null}
    }
    if($eventId -eq 41 -and $provider -eq 'Microsoft-Windows-Kernel-Power') {
        $codeNode=$document.SelectSingleNode('//*[local-name()="Data" and @Name="BugcheckCode"]')
        $code=0L
        $hasCode=$null -ne $codeNode -and [long]::TryParse($codeNode.InnerText,[ref]$code)
        $codeText=if($hasCode -and $code -gt 0){'0x{0:X8}' -f $code}else{$null}
        return [pscustomobject]@{Id=41;TimeUTC=$time;Kind='UnexpectedRestart';CommitPercent=$null;CommitUsedMB=$null;CommitTotalMB=$null;KernelPagedMB=$null;KernelNonpagedMB=$null;TopPagedPoolTag=$null;BugcheckCode=$codeText}
    }
}

function Get-WBMemoryIncidents {
    param([ValidateRange(1,30)][int]$Days=7)
    $rows=@();$errors=@()
    foreach($spec in @(@{Id=2004;ProviderName='Microsoft-Windows-Resource-Exhaustion-Detector'},@{Id=41;ProviderName='Microsoft-Windows-Kernel-Power'})) {
        try {
            $events=@(Get-WinEvent -FilterHashtable @{LogName='System';Id=$spec.Id;ProviderName=$spec.ProviderName;StartTime=(Get-Date).AddDays(-$Days)} -MaxEvents 20 -ErrorAction Stop)
            foreach($event in $events) {try{$row=ConvertFrom-WBMemoryEvent $event.ToXml();if($null -ne $row){$rows+=$row}}catch{$errors+='A memory event could not be parsed.'}}
        } catch { if($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound'){$errors+='Windows event history could not be read.'} }
    }
    [pscustomobject]@{Events=@($rows|Sort-Object TimeUTC -Descending);Complete=($errors.Count -eq 0);ReadErrors=$errors;Note='Bounded recent events only. Resource exhaustion near a restart does not identify a driver or prove the cause of the crash.'}
}
