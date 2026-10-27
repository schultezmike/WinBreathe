#Requires -Version 5.1
# Regression checks use synthetic state and disposable workspace files only.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/WinBreathe.MemoryWatch.ps1')
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/WinBreathe.Engine.psm1'),[ref]$tokens,[ref]$errors)
foreach ($name in @('Assert-WBSnapshot','Assert-WBProtectedPath','Get-WBRegistryState','Stop-WBAppGroup','Invoke-WBSafeFlush','Install-WBUpdateGuard','Invoke-WBTweaks','Test-WBTweakCondition','Enter-WBOperation','Exit-WBOperation')) {
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert($ok,$message) { if(-not $ok){throw $message}; Write-Host "PASS: $message" }
function MustReject([scriptblock]$Action,$message) { $rejected=$false;try {& $Action}catch{$rejected=$true};Assert $rejected $message }
$catalog=Get-Content (Join-Path $root 'config/tweaks.json') -Raw|ConvertFrom-Json
function Get-WBTweakCatalog {$catalog}
function Write-WBLog {param($Message,$Level)}
function Test-WBAdmin {$true}
$safe=[pscustomobject]@{
    SchemaVersion=3; UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Registry=@($catalog.tweaks | Where-Object type -eq 'registry' | ForEach-Object { $_.entries } | ForEach-Object { [pscustomobject]@{Path=$_.path;Name=$_.name;Kind=$_.kind;Exists=$true;Value=0} })
    Services=@();MMAgent=$null;Pagefile=[pscustomobject]@{AutoExists=$true;AutoValue=$true;PfExists=$false;PfValue=$null}
}
Assert-WBSnapshot $safe
Write-Host 'PASS: bounded valid snapshot accepted'
$originalPath=$safe.Registry[0].Path
$safe.Registry[0].Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
MustReject {Assert-WBSnapshot $safe} 'Undo rejects arbitrary startup registry writes before mutation'
$safe.Registry[0].Path=$originalPath
$safe.Services=@([pscustomobject]@{Name='*';StartType='Disabled';Status='Stopped'})
MustReject {Assert-WBSnapshot $safe} 'Undo rejects wildcard service targets'
$safe.Services=@();$safe.UserSid='S-1-5-18'
MustReject {Assert-WBSnapshot $safe} 'Undo rejects a snapshot from a different user'
MustReject {Assert-WBSnapshot ([pscustomobject]@{})} 'Undo rejects empty/incomplete JSON'
$script:stops=0
function Stop-Process { $script:stops++;throw 'Unexpected process termination' }
function Get-WBMemorySnapshot {[pscustomobject]@{UsedRAMMB=500;LoadPercent=10;AvailRAMMB=4500;TotalRAMMB=5000;CommitUsedMB=7000;CommitTotalMB=16000;KernelPagedMB=300;KernelNonpagedMB=200}}
Assert (-not (Stop-WBAppGroup '*')) 'Protected process list cannot be bypassed with a wildcard'
Assert (Invoke-WBSafeFlush) 'Legacy flush command is read-only'
Assert ($script:stops -eq 0) 'Memory check never terminates processes'
Assert (-not (Install-WBUpdateGuard)) 'Privileged task installation fails closed'
function Get-WBSystemProfile {[pscustomobject]@{OSCaption='Mock';OSFamily='Win11';TotalRAMMB=8192;DiskMediaType='HDD';FreeDiskGB=100}}
MustReject {Invoke-WBTweaks -TweakIds 'not-a-tweak'} 'Unknown tweak IDs abort without applying the full profile'
MustReject {Invoke-WBTweaks -SkipSnapshot} 'Live changes cannot bypass snapshots'
# Exact registry reads must preserve original unexpanded REG_EXPAND_SZ data.
function Resolve-WBRegistryPath {param($Path)$Path}
$key=[pscustomobject]@{}
$key|Add-Member ScriptMethod GetValueNames {,@('Mock')}
$key|Add-Member ScriptMethod GetValueKind {param($Name)[Microsoft.Win32.RegistryValueKind]::ExpandString}
$key|Add-Member ScriptMethod GetValue {param($Name,$Default,$Options) if($Options -ne [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames){throw 'Expanded registry read'}; '%SystemRoot%\original'}
function Get-Item {$key}
$state=Get-WBRegistryState 'MOCK' 'Mock'
Assert ($state.Value -eq '%SystemRoot%\original' -and $state.Kind -eq 'ExpandString') 'Registry backup preserves raw expandable strings and original type'
function Get-Item {throw 'Permission denied'}
MustReject {Get-WBRegistryState 'MOCK' 'Mock'} 'Unreadable registry key is not recorded as absent'
& {
    function Enter-WBOperation { $null }
    function Exit-WBOperation { param($Lease) }
    function Get-WBTweakCatalog { [pscustomobject]@{tweaks=@([pscustomobject]@{id='mock';type='registry';title='Mock';profiles=@('Balanced');entries=@([pscustomobject]@{path='MOCK';name='Mock';kind='DWord';value=1})})} }
    function Get-WBEntryTargetValue {1}
    function Get-WBRegistryState {[pscustomobject]@{Exists=$false;Value=$null}}
    function New-WBSnapshot {'MOCK'}
    function Test-Path {$true}
    $script:runLogs=@()
    function Write-WBLog {param($Message,$Level) $script:runLogs += [pscustomobject]@{Message=$Message;Level=$Level}}
    $script:writesAttempted=0
    function Set-WBRegistryValue {$script:writesAttempted++;throw 'Mock write denied'}
    $result=Invoke-WBTweaks
    Assert ($result.FailedCount -eq 1 -and $result.AppliedCount -eq 0 -and $result.SkippedCount -eq 0) 'Failed write is separate from applied and skipped counts'
    $summary=@($script:runLogs|Where-Object Message -match 'SUMMARY:')
    Assert ($summary.Count -eq 1 -and $summary[0].Level -eq 'WARN') 'A failed tweak produces a warning summary instead of a success summary'
    Assert (@($script:runLogs|Where-Object Message -match 'No immediate RAM reduction').Count -eq 1) 'No observed RAM reduction is stated explicitly'
    function Set-WBRegistryValue {$script:writesAttempted++;throw [UnauthorizedAccessException]::new('Synthetic access denied')}
    $script:runLogs=@()
    $result=Invoke-WBTweaks
    Assert ($result.FailedCount -eq 1 -and @($script:runLogs|Where-Object Message -match 'did not change its permissions').Count -eq 1) 'Access denial stays a failed tweak with a plain-language explanation'
    $result=Invoke-WBTweaks -WhatIf
    Assert ($result.PreviewCount -eq 1 -and $result.AppliedCount -eq 0 -and $script:writesAttempted -eq 2) 'Preview counts plans without registry writes'
    function New-WBSnapshot {$null}
    $result=Invoke-WBTweaks
    Assert ($result.Aborted -and $script:writesAttempted -eq 2) 'Backup failure aborts before any further writes'
    function Get-WBMemorySnapshot {[pscustomobject]@{UsedRAMMB=7000;LoadPercent=85;AvailRAMMB=1000;TotalRAMMB=8000;CommitUsedMB=15900;CommitTotalMB=16000;KernelPagedMB=300;KernelNonpagedMB=200}}
    function New-WBSnapshot {throw 'Critical memory must abort before backup capture'}
    $result=Invoke-WBTweaks
    Assert ($result.Aborted -and $script:writesAttempted -eq 2) 'Critical commit pressure defers optimization before backup or writes'
}
# Invoke the real CLI in a child process. Every alternate action with WhatIf
# must exit before calling any registry/process/service/scheduler routine.
$ps=Join-Path $PSHOME 'powershell.exe'
foreach($action in @('-Undo','-ResetDefaults','-Flush','-InstallGuard','-RemoveGuard','-Snapshot','-GUI','-ExportReport','-MemoryStatus')) {
    $output=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'src/WinBreathe.ps1') $action -WhatIf 2>&1
    Assert ($LASTEXITCODE -eq 0 -and ($output -join '') -match '\[PREVIEW\]') "WhatIf blocks alternate action $action"
}
# Compile and exercise the actual asynchronous output reader with delayed
# stdout/stderr. Empty pipes must return immediately; heavy stderr must drain.
if(-not ('WBProcessOutput' -as [type])) {Add-Type -Path (Join-Path $root 'src/WinBreathe.ProcessOutput.cs')}
# Exercise the GUI's actual child invocation without opening a form. The child
# emits progress, stdout, warning and error streams, then a known exit code.
& {
    $guiAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/WinBreathe.GUI.ps1'),[ref]$null,[ref]$null)
    $runner=$guiAst.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-WBAsyncCommand'},$true)
    . ([scriptblock]::Create($runner.Extent.Text))
    function Write-GuiConsole {param($Text,$Color)}
    $tabs=[pscustomobject]@{SelectedTab=$null};$tabDash='Dashboard'
    $btnQuickOpt=[pscustomobject]@{Enabled=$true};$btnPreviewSel=[pscustomobject]@{Enabled=$true};$btnApplySel=[pscustomobject]@{Enabled=$true}
    $procTimer=[pscustomobject]@{};$procTimer|Add-Member ScriptMethod Start {}
    $cliScript=Join-Path $PSScriptRoot ("child's output-"+[guid]::NewGuid().ToString('N')+'.ps1')
    @'
param([string]$Profile)
Write-Progress -Activity 'Synthetic module initialization' -Status 'Starting' -PercentComplete 50
Write-Output 'fixture-output'
Write-Warning 'fixture-warning'
if($Profile -eq 'Fail') { Write-Error 'fixture-error' -ErrorAction Continue; exit 1 }
exit 0
'@ | Set-Content -LiteralPath $cliScript -Encoding ASCII
    try {
        foreach($mode in @('Fail','Success')) {
            $script:ActiveProcess=$null;$script:ProcessOutput=$null
            try {
                Start-WBAsyncCommand -CliArguments "-Profile $mode" -BannerText 'Output regression fixture'
                Assert ($null -ne $script:ActiveProcess -and $null -ne $script:ProcessOutput) 'GUI child starts with a quoted script path'
                $lines=@();$limit=[Diagnostics.Stopwatch]::StartNew()
                while(-not $script:ProcessOutput.Complete -and $limit.Elapsed.TotalSeconds -lt 20) {
                    $line=$script:ProcessOutput.ReadAvailable()
                    if($null -ne $line){$lines+=$line}else{Start-Sleep -Milliseconds 5}
                }
                Assert $script:ProcessOutput.Complete 'GUI child output drains completely'
                Assert (($lines -join "`n") -notmatch '#< CLIXML|<Objs\b|<Obj\b') 'PowerShell progress is not displayed as raw XML'
                Assert ($lines -contains 'fixture-output' -and $lines -contains 'fixture-warning') 'Plain output and real warnings are retained'
                $expected=if($mode -eq 'Fail'){1}else{0}
                Assert ($script:ActiveProcess.ExitCode -eq $expected) "GUI child preserves the $mode exit code"
                if($mode -eq 'Fail'){Assert ($lines -contains 'fixture-error') 'Real errors remain visible when progress serialization is suppressed'}
            } finally {
                if($null -ne $script:ProcessOutput){$script:ProcessOutput.Dispose();$script:ProcessOutput=$null}
                if($null -ne $script:ActiveProcess){$script:ActiveProcess.Dispose();$script:ActiveProcess=$null}
            }
        }
    } finally { Remove-Item -LiteralPath $cliScript -Force }
}
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=$ps
$payload="Write-Output 'first'; Start-Sleep -Milliseconds 400; 1..400 | ForEach-Object { [Console]::Error.WriteLine('error-line-' + `$_) }; Write-Output 'last'; exit 7"
$info.Arguments='-NoProfile -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$process=[Diagnostics.Process]::Start($info)
$buffer=New-Object WBProcessOutput($process)
$watch=[Diagnostics.Stopwatch]::StartNew();$text=@()
try {
    $emptyWatch=[Diagnostics.Stopwatch]::StartNew();$line=$buffer.ReadAvailable();$emptyWatch.Stop()
    Assert ($emptyWatch.ElapsedMilliseconds -lt 250) 'Empty output queue returns without waiting for child output'
    if($null -ne $line){$text+=$line}
    while(-not $buffer.Complete -and $watch.Elapsed.TotalSeconds -lt 20){
        $line=$buffer.ReadAvailable();if($null -ne $line){$text+=$line}else{Start-Sleep -Milliseconds 5}
    }
    Assert ($buffer.Complete -and $text -contains 'last' -and @($text|Where-Object{$_ -like 'error-line-*'}).Count -eq 400) 'Delayed stdout and heavy stderr drain completely without a UI-thread pipe wait'
    Assert ($process.ExitCode -eq 7) 'Child failure code remains available'
}finally{$buffer.Dispose();$process.Dispose()}
$fixture=Join-Path $PSScriptRoot ('lock-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
function Get-WBPaths {[pscustomobject]@{BackupDir=$fixture}}
function Initialize-WBBackupStore {param($Path)}
function Assert-WBProtectedPath {param($Path)}
$lease=$null
try {
    $lease=Enter-WBOperation
    MustReject { [IO.File]::Open((Join-Path $fixture 'operation.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } 'A second writer cannot open the operation lock'
    Assert ($null -eq (Enter-WBOperation)) 'Nested snapshot shares the existing operation lease'
    Exit-WBOperation $lease
    $lease=Enter-WBOperation
    Assert ($null -ne $lease) 'Operation lock is released after completion'
}finally{
    Exit-WBOperation $lease
    Remove-Item -LiteralPath (Join-Path $fixture 'operation.lock') -Force
    Remove-Item -LiteralPath $fixture
}
Write-Host 'Security regressions passed.'
