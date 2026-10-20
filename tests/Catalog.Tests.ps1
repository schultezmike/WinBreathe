#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$catalog = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/tweaks.json') -Raw | ConvertFrom-Json
function Require($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
Require ($catalog.schemaVersion -eq 2) 'Unsupported catalog schema.'
Require ($catalog.tweaks.Count -ge 20) 'Catalog is unexpectedly incomplete.'
$profiles = @($catalog.profiles.PSObject.Properties.Name)
Require ((($profiles | Sort-Object) -join ',') -eq 'Aggressive,Balanced,Conservative') 'Unexpected profile names.'
$ids = @{}
foreach ($tweak in $catalog.tweaks) {
    Require ($tweak.id -match '^[a-z][a-zA-Z0-9.]+$' -and -not $ids.ContainsKey($tweak.id)) "Invalid or duplicate ID: $($tweak.id)"
    $ids[$tweak.id] = $true
    foreach ($field in @('title','description','impact','category')) { Require (-not [string]::IsNullOrWhiteSpace($tweak.$field)) "Missing $field in $($tweak.id)" }
    Require ($tweak.risk -in @('Safe','Moderate','Advanced')) "Unknown risk in $($tweak.id)"
    Require ($tweak.supportedOS.Count -gt 0) "Missing supported OS in $($tweak.id)"
    foreach ($os in $tweak.supportedOS) { Require ($os -in @('Win7','Win8','Win10','Win11')) "Unknown OS in $($tweak.id)" }
    foreach ($profile in $tweak.profiles) { Require ($profile -in $profiles) "Unknown profile in $($tweak.id)" }
    if ($tweak.PSObject.Properties.Name -contains 'condition') { Require ($tweak.condition -in @('hddOnly','lowRamOrHdd')) "Unknown condition in $($tweak.id)" }
    switch ($tweak.type) {
        'registry' {
            Require ($tweak.entries.Count -gt 0) "Empty registry tweak: $($tweak.id)"
            $targets = @{}
            foreach ($entry in $tweak.entries) {
                Require ($entry.path -match '^HK(LM|CU):\\' -and $entry.path -notmatch '[*?\[\]\r\n]') "Unexpected registry path in $($tweak.id)"
                Require (-not [string]::IsNullOrWhiteSpace($entry.name)) "Empty registry value in $($tweak.id)"
                Require ($entry.kind -in @('DWord','QWord','String','ExpandString','MultiString','Binary')) "Unknown registry type in $($tweak.id)"
                Require ($entry.PSObject.Properties.Name -contains 'value') "Missing target value in $($tweak.id)"
                $target = $entry.path + '|' + $entry.name
                Require (-not $targets.ContainsKey($target)) "Duplicate registry target in $($tweak.id)"
                $targets[$target] = $true
                if ($entry.PSObject.Properties.Name -contains 'valueByProfile') { foreach ($profile in $entry.valueByProfile.PSObject.Properties.Name) { Require ($profile -in $profiles) "Unknown value profile in $($tweak.id)" } }
            }
        }
        'service' { Require ($tweak.service -match '^[a-zA-Z0-9_.-]+$' -and $tweak.startupType -in @('Automatic','Manual','Disabled')) "Invalid service tweak: $($tweak.id)" }
        'mmagent' { Require ($tweak.feature -in @('MemoryCompression','PageCombining','ApplicationPreLaunch') -and $tweak.enabled -is [bool]) "Invalid MMAgent tweak: $($tweak.id)" }
        'pagefile' { Require ($tweak.id -eq 'mem.pagefile' -and $tweak.profiles.Count -eq 0) 'Pagefile configuration must remain opt-in.' }
        default { throw "Unknown tweak type: $($tweak.type)" }
    }
}
Write-Host "PASS: $($ids.Count) unique catalog entries, valid types, targets, profiles and applicability."
