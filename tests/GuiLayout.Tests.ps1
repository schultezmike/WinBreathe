#Requires -Version 5.1
# Construct the real WinForms view with synthetic readings. Do not show a desktop
# window, send input, query live startup items or apply any system changes.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path $PSScriptRoot ('gui-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$script:GuiFixturePath=$fixture
$script:GuiFixtureMemory=[pscustomobject]@{LoadPercent=70;TotalRAMMB=8192;UsedRAMMB=5692;AvailRAMMB=2500;CommitTotalMB=20000;CommitUsedMB=7000;CommitAvailMB=13000;KernelPagedMB=400;KernelNonpagedMB=300}
$source=[IO.File]::ReadAllText((Join-Path $root 'src/WinBreathe.GUI.ps1'))
$path=(Join-Path $root 'src').Replace("'","''")
$source=$source.Replace('$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path',('$scriptDir = '''+$path+''''))
$source=$source.Replace('$ErrorActionPreference = "SilentlyContinue"','$ErrorActionPreference = "Stop"')
$fixtureFunctions=@'
function Get-WBMemorySnapshot { $script:GuiFixtureMemory }
function Invoke-WBMemoryRelief { param($State,$Snapshot,[switch]$Automatic,[switch]$ObserveOnly,[switch]$WhatIf,[switch]$Confirm) [pscustomobject]@{Attempted=$false} }
function Test-WBAdmin { $false }
function Get-WBSystemProfile { [pscustomobject]@{OSCaption='SYNTHETIC LAYOUT FIXTURE';OSFamily='Win11';TotalRAMMB=8192;UsedRAMMB=5692;AvailRAMMB=2500;LoadPercent=70;DiskMediaType='HDD';DiskModel='TEST ONLY';FreeDiskGB=100;RecommendedProfile='Balanced'} }
function Get-WBPaths { [pscustomobject]@{DataDir=$script:GuiFixturePath;LatestBackup=(Join-Path $script:GuiFixturePath 'none.json')} }
function Test-WBTweakState { @() }
function Get-WBTopProcesses { @() }
function Get-WBStartupItems { @() }
function Get-WBUpdateGuardStatus { [pscustomobject]@{State='Not Installed';LastRunTime='Unknown'} }
function New-WBSnapshot { throw 'No mutation is permitted in layout tests' }
function Invoke-WBTweaks { throw 'No mutation is permitted in layout tests' }
'@
$import='Import-Module $modulePath -Force -ErrorAction Stop'
$source=$source.Replace($import,($import+"`r`n"+$fixtureFunctions))
$source=$source.Replace('$memoryTray.Visible = $true','$memoryTray.Visible = $false')
$source=[regex]::Replace($source,'(?m)^.*\$memoryTray\.ShowBalloonTip.*$','# Balloon display suppressed in hidden construction tests.')
$checks=@'
    $form.CreateControl()
    $form.PerformLayout()
    if($form.Text -notmatch '2.3.0'){throw 'Incorrect GUI version'}
    if($btnMemoryDetails.Text -ne 'Investigate Memory' -or $btnWatchTray.Text -ne 'Keep watching in tray'){throw 'Missing monitoring actions'}
    if($lblMemoryWatch.Bounds.IntersectsWith($btnWatchTray.Bounds) -or $consoleBox.Bounds.IntersectsWith($btnMemoryDetails.Bounds)){throw 'Memory Watch controls overlap'}
    if($btnQuickFlush.Text -ne 'RAM Relief' -or $chkAutoRelief.Checked){throw 'Relief action missing or auto relief enabled without opt-in'}
    foreach($control in @($lblMemoryWatch,$btnMemoryDetails,$btnWatchTray,$btnWindowsMemory,$chkAutoRelief,$consoleBox)) {
        if($control.Left -lt 0 -or $control.Top -lt 0 -or $control.Right -gt 970 -or $control.Bottom -gt 545){throw 'Monitoring controls exceed the intended dashboard area'}
    }
    $script:GuiFixtureMemory=[pscustomobject]@{LoadPercent=85;TotalRAMMB=8192;UsedRAMMB=7000;AvailRAMMB=1192;CommitTotalMB=20000;CommitUsedMB=19760;CommitAvailMB=240;KernelPagedMB=10000;KernelNonpagedMB=400}
    Update-DashboardMetrics
    if($script:MemoryWatch.Level -ne 'Critical' -or $lblMemoryWatch.Text -notmatch 'Large kernel pools'){throw 'Critical kernel pressure is not visible in the real view'}
    $textSize=[Drawing.Size]::new($lblMemoryWatch.Width-16,1000)
    $measured=[Windows.Forms.TextRenderer]::MeasureText($lblMemoryWatch.Text,$lblMemoryWatch.Font,$textSize,[Windows.Forms.TextFormatFlags]::WordBreak)
    if($measured.Height -gt $lblMemoryWatch.Height-16){throw 'Memory warning text is clipped'}
    $script:GuiFixtureMemory=[pscustomobject]@{}
    Update-DashboardMetrics
    if($script:MemoryWatch.Level -ne 'Unknown' -or $lblMemoryWatch.Text -notmatch 'unavailable'){throw 'Invalid readings do not show monitoring unavailable'}
    1..600 | ForEach-Object { Write-GuiConsole ('test '+('x'*500)) }
    Write-GuiConsole 'LATEST OUTPUT RETAINED'
    if($consoleBox.TextLength -gt 105000 -or $consoleBox.Text -notmatch 'LATEST OUTPUT RETAINED'){throw "Console history is unbounded or loses the newest result (length $($consoleBox.TextLength))"}
    # Exercise the application-loop lifetime without displaying a desktop window.
    # A modal ShowDialog loop exits after Hide and would fail this check.
    $form.Opacity=0
    $form.ShowInTaskbar=$false
    $script:HiddenTicks=0
    $form.Add_Shown({$form.Hide()})
    $hiddenTimer=New-Object Windows.Forms.Timer
    $hiddenTimer.Interval=50
    $hiddenTimer.Add_Tick({$script:HiddenTicks++;if($script:HiddenTicks -eq 1){$form.Close();if(-not $form.IsDisposed -and $form.WindowState -eq 'Minimized'){$script:ClosePreservedWatch=$true}};if($script:HiddenTicks -ge 3){$script:ExitRequested=$true;$form.Close()}})
    $script:ClosePreservedWatch=$false
    $hiddenTimer.Start()
    try{[Windows.Forms.Application]::Run($form)}finally{$hiddenTimer.Stop();$hiddenTimer.Dispose()}
    if($script:HiddenTicks -lt 3){throw 'Hiding the window terminated the monitoring message loop'}
    if(-not $script:ClosePreservedWatch){throw 'Closing the window silently stopped monitoring'}
    Write-Host 'PASS: hidden main-window message loop continues until explicit Close.'
    Write-Host 'PASS: real GUI construction, action labels, control bounds, critical/unknown displays and bounded console.'
'@
if(-not $source.Contains('    [System.Windows.Forms.Application]::Run($form)')){throw 'GUI entrypoint changed; review hidden layout test harness'}
$source=$source.Replace('    [System.Windows.Forms.Application]::Run($form)',$checks)
try { & ([scriptblock]::Create($source)) }
finally {
    foreach($file in Get-ChildItem -LiteralPath $fixture -File){Remove-Item -LiteralPath $file.FullName}
    Remove-Item -LiteralPath $fixture
}
