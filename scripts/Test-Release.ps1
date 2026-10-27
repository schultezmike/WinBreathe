#Requires -Version 5.1
param([switch]$Build)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$powershell = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
function Invoke-Check([string]$Path, [string[]]$Arguments = @()) {
    Write-Host "Checking $Path"
    & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root $Path) @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Check failed: $Path (exit $LASTEXITCODE)" }
}
foreach ($name in @('Compatibility','Report','SnapshotFile','Security','Catalog','MemoryWatch','GuiLayout')) { Invoke-Check "tests/$name.Tests.ps1" }
Invoke-Check 'src/WinBreathe.ps1' @('-Status')
Invoke-Check 'src/WinBreathe.ps1' @('-Profile','Balanced','-WhatIf')
if ($Build) {
    Invoke-Check 'Compile.ps1'
    Invoke-Check 'tests/Launcher.Tests.ps1'
    Invoke-Check 'tests/Package.Tests.ps1'
} else {
    Invoke-Check 'Compile.ps1' @('-VerifyOnly')
}
Write-Host 'PASS: every requested release check completed.'
