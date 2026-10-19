#Requires -Version 5.1
# Isolated regression checks. No module import, registry writes, or system changes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/WinBreathe.Engine.psm1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Engine parse failure' }
foreach ($name in @('Test-WBTweakCondition', 'New-WBSnapshot', 'Restore-WBSnapshot', 'Remove-WBRegistryValue', 'Get-WBSystemProfile', 'Get-WBUpdateGuardStatus')) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message }; Write-Host "PASS: $Message" }
$catalog = Get-Content (Join-Path $root 'config/tweaks.json') -Raw | ConvertFrom-Json
foreach ($os in @('Win7', 'Win8', 'Win10', 'Win11')) {
    $sys = [pscustomobject]@{ OSFamily = $os; IsHDD = $false; IsLowRAM = $true }
    $prefetch = $catalog.tweaks | Where-Object id -eq 'legacy.prefetcher'
    Assert (-not (Test-WBTweakCondition $prefetch $sys)) "Prefetch rejects SSD on $os"
    foreach ($profile in @('Conservative', 'Balanced', 'Aggressive')) {
        $selected = @($catalog.tweaks | Where-Object { $_.profiles -contains $profile })
        Assert (-not ($selected.id -contains 'mem.pagefile')) "Pagefile remains opt-in for $os/$profile"
    }
}
function Get-WBPaths { [pscustomobject]@{ BackupDir = 'MOCK'; LatestBackup = 'MOCK/latest.json' } }
function Get-WBTweakCatalog { [pscustomobject]@{ tweaks = @(); optionalServices = @() } }
function Get-WBSystemProfile { [pscustomobject]@{ SystemDrive = 'C:' } }
function Get-WBRegistryState { [pscustomobject]@{ Exists = $false; Value = $null; Kind = 'Unknown' } }
function Get-WBAutomaticPagefileState { [pscustomobject]@{ Exists = $true; Value = $true } }
function Get-Command { $true }
function Get-MMAgent { [pscustomobject]@{ PageCombining = $true; ApplicationPreLaunch = $false } }
function Join-Path { param($Path, $ChildPath) "$Path/$ChildPath" }
function Test-Path { $true }
function Write-WBLog { param($Message, $Level) }
function Set-Content { [CmdletBinding()]param($Path,$Value,$Encoding,[switch]$Force) throw 'Mock write denied' }
function Remove-Item { }
# Reaching the mocked write proves the Win8-shaped object passed capture.
$script:serialized = $false
function ConvertTo-Json { param([Parameter(ValueFromPipeline)]$InputObject, $Depth) process {
    Assert (-not $InputObject.MMAgent.ContainsKey('MemoryCompression')) 'Win8 snapshot omits unsupported MemoryCompression'
    $script:serialized = $true
    '{"mock":"snapshot payload"}'
} }
Assert ($null -eq (New-WBSnapshot)) 'Denied snapshot write returns null'
Assert $script:serialized 'Win8 snapshot reaches serialization'
function ConvertTo-Json { throw 'Mock serialization failure' }
Assert ($null -eq (New-WBSnapshot)) 'Serialization failure cleans up under strict mode'
function Resolve-WBRegistryPath { param($Path) $Path }
function Get-Item { $key = [pscustomobject]@{}; $key | Add-Member ScriptMethod GetValueNames { ,@('Mock') }; $key }
function Remove-ItemProperty { [CmdletBinding()]param($Path,$Name,[switch]$Force) Write-Error 'Mock access denied' }
function Get-Content { '{"Registry":[{"Path":"MOCK","Name":"Mock","Exists":false}],"Services":[],"MMAgent":null,"Pagefile":null}' }
function Test-WBAdmin { $true }
Assert (-not (Restore-WBSnapshot -SnapshotPath 'MOCK')) 'Undo detects denied deletion through actual helper'
function Get-Command { $null }
Assert ((Get-WBUpdateGuardStatus).State -eq 'Unsupported on this system') 'Guard reports absent ScheduledTasks module'
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-WBSystemProfile' }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
$script:CachedHardwareInfo = $null
function Get-WBMemorySnapshot { [pscustomobject]@{ TotalRAMMB=8192; UsedRAMMB=4096; AvailRAMMB=4096; LoadPercent=50; CommitTotalMB=16384; CommitUsedMB=4096 } }
function Get-Partition { throw 'Storage module absent' }
function Get-PhysicalDisk { throw 'Fallback must not call unavailable Storage commands' }
function Get-Item { $null }
function Get-CimInstance { param($ClassName, $Filter)
    switch ($ClassName) {
        'Win32_DiskDrive' { [pscustomobject]@{ Model='Legacy disk' } }
        'Win32_LogicalDisk' { [pscustomobject]@{ FreeSpace=50GB; Size=100GB } }
        'Win32_OperatingSystem' { [pscustomobject]@{ Caption='Microsoft Windows 7 Professional'; BuildNumber='7601' } }
    }
}
$legacy = Get-WBSystemProfile
Assert ($legacy.OSFamily -eq 'Win7' -and $legacy.DiskMediaType -eq 'Unspecified') 'Win7 hardware fallback works without Storage module and does not guess disk type'
Write-Host 'All isolated compatibility checks passed.'
