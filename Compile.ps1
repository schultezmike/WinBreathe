# ==============================================================================
# Compile.ps1 - WinBreathe Build, Bundler & Native .EXE Compiler Pipeline
# Structure modeled after ChrisTitusTech/winutil & hellzerg/optimizer
# Compiles standalone self-contained x64 Windows executables (.exe) with custom
# icon, asInvoker manifest, and embedded resources for the current v2.1.2 release
# ==============================================================================

param(
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$cscPath  = Get-ChildItem "C:\Windows\Microsoft.NET\Framework64\*\csc.exe" | Select-Object -Last 1 -ExpandProperty FullName
if (-not $cscPath) {
    throw "Microsoft .NET Framework x64 C# Compiler (csc.exe) not found."
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  WinBreathe Build & Native Executable Compiler Pipeline" -ForegroundColor Cyan
Write-Host "  Compiler: $cscPath" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. AST Syntax & Pure ASCII Verification
$psFiles = @(Get-ChildItem -Path (Join-Path $repoRoot "scripts") -Filter *.ps1) + @(Get-ChildItem -Path (Join-Path $repoRoot "src") -Include *.ps1, *.psm1 -Recurse) + @(Get-ChildItem -Path (Join-Path $repoRoot "tests") -Filter *.ps1) + @(Get-Item $PSCommandPath)
foreach ($f in $psFiles) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Syntax error in $($f.FullName): $($errors | Out-String)"
    }
    if (@([System.IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 }).Count -gt 0) {
        throw "Non-ASCII bytes in $($f.FullName). Use ASCII script text for Windows PowerShell compatibility."
    }
    Write-Host "[PASS] AST and ASCII verified: $($f.Name)" -ForegroundColor Green
}

if ($VerifyOnly) {
    Write-Host "[PASS] Verification complete." -ForegroundColor Green
    exit 0
}

$iconFile     = Join-Path $repoRoot "assets\icon.ico"
$logoFile     = Join-Path $repoRoot "assets\logo.png"
$manifestFile = Join-Path $repoRoot "src\Launcher\app.manifest"
$csSource     = Join-Path $repoRoot "src\Launcher\Program.cs"

# Build only the current version; never rewrite historical version 1 files.
$sourceRevision = $null; $sourceDirty = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    $sourceRevision = & git -C $repoRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { $sourceDirty = [bool](& git -C $repoRoot status --porcelain) } else { $sourceRevision = $null }
}
$relV2Dir = Join-Path $repoRoot "releases\v2.1.2"
New-Item -ItemType Directory -Path $relV2Dir -Force | Out-Null

$v2Engine = Join-Path $repoRoot "src\WinBreathe.Engine.psm1"
$v2Cli    = Join-Path $repoRoot "src\WinBreathe.ps1"
$v2Gui    = Join-Path $repoRoot "src\WinBreathe.GUI.ps1"
$v2Cfg    = Join-Path $repoRoot "config\tweaks.json"
$v2ExeOut = Join-Path $relV2Dir "WinBreathe-v2.1.2-x64.exe"
$rootExe  = Join-Path $repoRoot "WinBreathe.exe"

Write-Host "[BUILD] Compiling WinBreathe-v2.1.2-x64.exe & Root WinBreathe.exe..." -ForegroundColor Yellow
$v2Args = @(
    "/nologo",
    "/target:winexe",
    "/platform:x64",
    "/optimize+",
    "/out:`"$v2ExeOut`"",
    "/win32icon:`"$iconFile`"",
    "/win32manifest:`"$manifestFile`"",
    "/resource:`"$v2Engine`",WinBreathe.Engine.psm1",
    "/resource:`"$repoRoot\src\WinBreathe.ProcessOutput.cs`",WinBreathe.ProcessOutput.cs",
    "/resource:`"$v2Cli`",WinBreathe.ps1",
    "/resource:`"$v2Gui`",WinBreathe.GUI.ps1",
    "/resource:`"$v2Cfg`",tweaks.json",
    "/resource:`"$logoFile`",logo.png",
    "/resource:`"$iconFile`",icon.ico",
    "`"$csSource`""
)
& $cscPath @v2Args
if ($LASTEXITCODE -ne 0) { throw "v2.1.2 compilation failed." }

try { Copy-Item $v2ExeOut $rootExe -Force -ErrorAction Stop }
catch { Write-Warning "Root executable was not updated (it may be running). Use the versioned release executable. $($_.Exception.Message)" }

# Create v2.1.2 Portable ZIP
$v2Stage = Join-Path $env:TEMP ("WinBreathe_stage_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path "$v2Stage\src", "$v2Stage\config", "$v2Stage\assets", "$v2Stage\docs" -Force | Out-Null
Copy-Item $v2ExeOut "$v2Stage\WinBreathe.exe" -Force
Copy-Item (Join-Path $repoRoot "WinBreathe.bat") "$v2Stage\WinBreathe.bat" -Force
Copy-Item $v2Engine "$v2Stage\src\WinBreathe.Engine.psm1" -Force
Copy-Item $v2Cli    "$v2Stage\src\WinBreathe.ps1" -Force
Copy-Item $v2Gui    "$v2Stage\src\WinBreathe.GUI.ps1" -Force
New-Item -ItemType Directory -Path "$v2Stage\src\Launcher" -Force | Out-Null
Copy-Item "$repoRoot\src\Launcher\*" "$v2Stage\src\Launcher"
Copy-Item "$repoRoot\src\WinBreathe.ProcessOutput.cs" "$v2Stage\src\WinBreathe.ProcessOutput.cs" -Force
New-Item -ItemType Directory -Path "$v2Stage\scripts" -Force | Out-Null
Copy-Item "$repoRoot\scripts\*.ps1" "$v2Stage\scripts"
Copy-Item $v2Cfg    "$v2Stage\config\tweaks.json" -Force
Copy-Item "$repoRoot\assets\*" "$v2Stage\assets\" -Force
Copy-Item "$repoRoot\docs\*"   "$v2Stage\docs\" -Force
Copy-Item "$repoRoot\README.md", "$repoRoot\LICENSE", "$repoRoot\CHANGELOG.md", "$repoRoot\SECURITY.md", "$repoRoot\Compile.ps1" $v2Stage -Force

# Bind the package to the source inputs used in this invocation.
New-Item -ItemType Directory -Path (Join-Path $v2Stage 'tests') -Force | Out-Null
Copy-Item (Join-Path $repoRoot 'tests/*.ps1') (Join-Path $v2Stage 'tests')
# Relative names do not depend on TEMP using an 8.3 or expanded directory name.
$sourcePaths = @(Get-ChildItem -LiteralPath $v2Stage -Recurse -File -Name | Where-Object { $_ -ne 'WinBreathe.exe' } | ForEach-Object { $_.Replace('\','/') } | Sort-Object)
$sourceManifest = [ordered]@{
    Version = '2.1.2-preview'
    RepositoryCommit = $sourceRevision
    WorkingTreeDirty = $sourceDirty
    BuiltAtUTC = [DateTime]::UtcNow.ToString('o')
    Sources = @($sourcePaths | ForEach-Object {
        [ordered]@{ Path = $_; SHA256 = (Get-FileHash (Join-Path $repoRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
}
$sourceManifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $relV2Dir 'SOURCE-MANIFEST.json') -Encoding UTF8
Copy-Item (Join-Path $relV2Dir 'SOURCE-MANIFEST.json') $v2Stage
Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/RELEASE-2.1.2.md') -Destination (Join-Path $relV2Dir 'RELEASE-NOTES.md') -Force

$v2Zip = Join-Path $relV2Dir "WinBreathe-v2.1.2-Portable.zip"
if (Test-Path $v2Zip) {
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    Remove-Item $v2Zip -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 150
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($v2Zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relativeName in Get-ChildItem -LiteralPath $v2Stage -Recurse -File -Name) {
        $entryName = $relativeName.Replace('\','/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $v2Stage $relativeName), $entryName, [IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $zip.Dispose()
    $resolvedStage = [IO.Path]::GetFullPath($v2Stage)
    $expectedParent = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($resolvedStage) -ne $expectedParent -or [IO.Path]::GetFileName($resolvedStage) -notmatch '^WinBreathe_stage_[a-f0-9]{32}$') { throw 'Unsafe build staging cleanup path.' }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}

# Generate SHA256SUMS.txt for v2.1.2
$v2Hashes = Get-ChildItem $relV2Dir -Include *.exe, *.zip, SOURCE-MANIFEST.json, RELEASE-NOTES.md -Recurse | ForEach-Object {
    $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$h  $($_.Name)"
}
Set-Content -Path (Join-Path $relV2Dir "SHA256SUMS.txt") -Value ($v2Hashes -join "`r`n") -Encoding UTF8 -Force

Write-Host "[OK] Built v2.1.2 release artifacts in releases\v2.1.2\ (see warning above if the root executable was locked)." -ForegroundColor Green
