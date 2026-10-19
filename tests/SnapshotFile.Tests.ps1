#Requires -Version 5.1
# Real filesystem operations with synthetic state; no system or registry changes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/WinBreathe.Engine.psm1'),[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-WBSnapshot'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$testDir=Join-Path $PSScriptRoot ('snapshot-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
function Get-WBPaths { [pscustomobject]@{BackupDir=$testDir;LatestBackup=(Join-Path $testDir 'latest.json')} }
function Get-WBTweakCatalog { [pscustomobject]@{tweaks=@();optionalServices=@()} }
function Get-WBSystemProfile { [pscustomobject]@{SystemDrive='C:'} }
function Get-Command { $null }
function Get-WBRegistryState { [pscustomobject]@{Exists=$false;Value=$null} }
function Get-WBAutomaticPagefileState { [pscustomobject]@{Exists=$true;Value=$true} }
function Write-WBLog { param($Message,$Level) Write-Host "$Level $Message" }
try {
    $first=New-WBSnapshot -Label 'First synthetic snapshot'
    if (-not $first -or -not (Test-Path $first)) {throw 'First snapshot failed'}
    $second=New-WBSnapshot -Label 'Replacement synthetic snapshot'
    if (-not $second -or -not (Test-Path $second)) {throw 'Replacing existing latest.json failed'}
    $latest=Join-Path $testDir 'latest.json'
    $data=Get-Content $latest -Raw | ConvertFrom-Json
    if($data.Label -ne 'Replacement synthetic snapshot'){throw 'Latest snapshot did not update'}
    if((Get-Content $first -Raw | ConvertFrom-Json).Label -ne 'First synthetic snapshot'){throw 'Original timestamped backup was changed'}
    if((Get-FileHash $latest).Hash -ne (Get-FileHash $second).Hash){throw 'Published contents mismatch'}
    if(@(Get-ChildItem $testDir -Filter '*.tmp').Count){throw 'Temporary files were left behind'}
    Write-Host 'PASS: first snapshot, replacement of existing latest.json, retained original backup, content hashes and temporary-file cleanup'
} finally {
    # Only files created in this invocation-specific test directory are removed.
    Get-ChildItem -LiteralPath $testDir -File | Remove-Item -Force
    Remove-Item -LiteralPath $testDir
}
