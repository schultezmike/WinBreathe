#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = '2.2.0'
$release = Join-Path $root "releases/v$version"
function Require($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function StreamHash($Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose(); $Stream.Dispose() }
}
$assets = @("WinBreathe-v$version-x64.exe", "WinBreathe-v$version-Portable.zip", 'SOURCE-MANIFEST.json', 'RELEASE-NOTES.md')
$lines = @(Get-Content -LiteralPath (Join-Path $release 'SHA256SUMS.txt'))
Require ($lines.Count -eq $assets.Count) 'Incomplete asset checksums.'
$seen = @{}
foreach ($line in $lines) {
    Require ($line -match '^([a-f0-9]{64})  ([^/\\]+)$') 'Malformed asset checksum.'
    $hash=$Matches[1]; $name=$Matches[2]
    Require ($name -in $assets -and -not $seen.ContainsKey($name)) "Unexpected or duplicate asset checksum: $name"
    $seen[$name]=$true
    Require ((Get-FileHash -LiteralPath (Join-Path $release $name)).Hash -eq $hash) "Asset checksum mismatch: $name"
}
$manifest = Get-Content -LiteralPath (Join-Path $release 'SOURCE-MANIFEST.json') -Raw | ConvertFrom-Json
Require ($manifest.Version -eq $version) 'Incorrect manifest version.'
if ($env:GITHUB_REF -like 'refs/tags/*') {
    Require ($env:GITHUB_REF -eq "refs/tags/v$version") 'The tag does not match this package version.'
    Require ($manifest.WorkingTreeDirty -eq $false -and $manifest.RepositoryCommit -eq $env:GITHUB_SHA) 'Tag publication requires the clean tagged source revision.'
}
$exePath=Join-Path $release "WinBreathe-v$version-x64.exe"
Require ((Get-Item -LiteralPath $exePath).VersionInfo.FileVersion -eq "$version.0") 'Wrong executable version.'
Require ((Get-FileHash -LiteralPath (Join-Path $root 'WinBreathe.exe')).Hash -eq (Get-FileHash -LiteralPath $exePath).Hash) 'The main executable was not replaced with this build.'
Require ((Get-FileHash -LiteralPath (Join-Path $release 'RELEASE-NOTES.md')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root "docs/RELEASE-$version.md")).Hash) 'Release notes are stale.'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $release "WinBreathe-v$version-Portable.zip"))
try {
    $entries=@{}
    foreach ($entry in $zip.Entries) {
        Require ($entry.FullName -notmatch '(^/|\\|(^|/)\.\.(/|$)|:)') "Unsafe archive entry: $($entry.FullName)"
        Require (-not $entries.ContainsKey($entry.FullName)) 'Duplicate ZIP entry.'
        $entries[$entry.FullName]=$entry
    }
    Require ($entries.Count -eq $manifest.Sources.Count+2) 'Unexpected or missing archive files.'
    foreach ($source in $manifest.Sources) {
        Require ($source.Path -notmatch '(^/|\\|(^|/)\.\.(/|$)|:)') 'Unsafe manifest path.'
        Require ($entries.ContainsKey($source.Path)) "Missing packaged source: $($source.Path)"
        Require ((Get-FileHash -LiteralPath (Join-Path $root $source.Path)).Hash -eq $source.SHA256) "Stale source manifest: $($source.Path)"
        Require ((StreamHash $entries[$source.Path].Open()) -eq $source.SHA256) "Stale packaged source: $($source.Path)"
    }
    foreach ($name in @('WinBreathe.exe','SOURCE-MANIFEST.json')) {
        $expectedPath=if ($name -eq 'WinBreathe.exe') { $exePath } else { Join-Path $release $name }
        Require ((StreamHash $entries[$name].Open()) -eq (Get-FileHash -LiteralPath $expectedPath).Hash) "Stale packaged file: $name"
    }
} finally { $zip.Dispose() }
Write-Host 'PASS: package version, asset checksums, complete ZIP contents, source hashes and executable parity.'
