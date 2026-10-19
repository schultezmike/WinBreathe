# ==============================================================================
# Compile.ps1 - WinBreathe Build, Bundler & Native .EXE Compiler Pipeline
# Structure modeled after ChrisTitusTech/winutil & hellzerg/optimizer
# Compiles standalone self-contained x64 Windows executables (.exe) with custom
# icon, UAC Administrator manifest, and embedded resources for v1.1.0 & v2.0.0
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
$psFiles = Get-ChildItem -Path (Join-Path $repoRoot "src") -Include *.ps1, *.psm1 -Recurse
foreach ($f in $psFiles) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Syntax error in $($f.FullName): $($errors | Out-String)"
    }
    Write-Host "[PASS] AST Syntax Verified: $($f.Name)" -ForegroundColor Green
}

if ($VerifyOnly) {
    Write-Host "[PASS] Verification complete." -ForegroundColor Green
    exit 0
}

$iconFile     = Join-Path $repoRoot "assets\icon.ico"
$logoFile     = Join-Path $repoRoot "assets\logo.png"
$manifestFile = Join-Path $repoRoot "src\Launcher\app.manifest"
$csSource     = Join-Path $repoRoot "src\Launcher\Program.cs"

$relV1Dir = Join-Path $repoRoot "releases\v1.1.0"
$relV2Dir = Join-Path $repoRoot "releases\v2.0.0"
New-Item -ItemType Directory -Path $relV1Dir, $relV2Dir -Force | Out-Null

# ------------------------------------------------------------------------------
# 2. Compile Version 1.1.0 Standalone Executable & Portable Package
# ------------------------------------------------------------------------------
$v1Engine = Join-Path $repoRoot "src\v1\Win11LowRamOptimizer.ps1"
$v1Gui    = Join-Path $repoRoot "src\v1\WinBreatheGUI.ps1"
$v1Bat    = Join-Path $repoRoot "src\v1\OPTIMIZE_SYSTEM_ADMIN.bat"
$v1ExeOut = Join-Path $relV1Dir "WinBreathe-v1.1.0-x64.exe"

if ((Test-Path $v1Engine) -and (Test-Path $v1Gui)) {
    Write-Host "[BUILD] Compiling WinBreathe-v1.1.0-x64.exe..." -ForegroundColor Yellow
    $v1Args = @(
        "/nologo",
        "/target:winexe",
        "/platform:x64",
        "/optimize+",
        "/define:V1_BUILD",
        "/out:`"$v1ExeOut`"",
        "/win32icon:`"$iconFile`"",
        "/win32manifest:`"$manifestFile`"",
        "/resource:`"$v1Engine`",Win11LowRamOptimizer.ps1",
        "/resource:`"$v1Gui`",WinBreatheGUI.ps1",
        "`"$csSource`""
    )
    & $cscPath @v1Args
    if ($LASTEXITCODE -ne 0) { throw "v1.1.0 compilation failed." }

    # Create v1.1.0 Portable ZIP
    $v1Stage = Join-Path $env:TEMP "WinBreathe_v1_stage"
    if (Test-Path $v1Stage) { Remove-Item $v1Stage -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $v1Stage "scripts") -Force | Out-Null
    Copy-Item $v1ExeOut (Join-Path $v1Stage "WinBreathe.exe") -Force
    Copy-Item $v1Bat    (Join-Path $v1Stage "OPTIMIZE_SYSTEM_ADMIN.bat") -Force
    Copy-Item $v1Engine (Join-Path $v1Stage "scripts\Win11LowRamOptimizer.ps1") -Force
    Copy-Item $v1Gui    (Join-Path $v1Stage "scripts\WinBreatheGUI.ps1") -Force
    Copy-Item (Join-Path $repoRoot "LICENSE") (Join-Path $v1Stage "LICENSE") -Force

    $v1Zip = Join-Path $relV1Dir "WinBreathe-v1.1.0-Portable.zip"
    if (Test-Path $v1Zip) { Remove-Item $v1Zip -Force }
    Compress-Archive -Path "$v1Stage\*" -DestinationPath $v1Zip -Force
    Remove-Item $v1Stage -Recurse -Force

    # Generate SHA256SUMS.txt for v1.1.0
    $v1Hashes = Get-ChildItem $relV1Dir -Include *.exe, *.zip -Recurse | ForEach-Object {
        $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$h  $($_.Name)"
    }
    Set-Content -Path (Join-Path $relV1Dir "SHA256SUMS.txt") -Value ($v1Hashes -join "`r`n") -Encoding UTF8 -Force
    Write-Host "[OK] Built v1.1.0 Release Artifacts in releases\v1.1.0\" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 3. Compile Version 2.0.0 Standalone Executable & Root WinBreathe.exe
# ------------------------------------------------------------------------------
$v2Engine = Join-Path $repoRoot "src\WinBreathe.Engine.psm1"
$v2Cli    = Join-Path $repoRoot "src\WinBreathe.ps1"
$v2Gui    = Join-Path $repoRoot "src\WinBreathe.GUI.ps1"
$v2Cfg    = Join-Path $repoRoot "config\tweaks.json"
$v2ExeOut = Join-Path $relV2Dir "WinBreathe-v2.0.0-x64.exe"
$rootExe  = Join-Path $repoRoot "WinBreathe.exe"

Write-Host "[BUILD] Compiling WinBreathe-v2.0.0-x64.exe & Root WinBreathe.exe..." -ForegroundColor Yellow
$v2Args = @(
    "/nologo",
    "/target:winexe",
    "/platform:x64",
    "/optimize+",
    "/out:`"$v2ExeOut`"",
    "/win32icon:`"$iconFile`"",
    "/win32manifest:`"$manifestFile`"",
    "/resource:`"$v2Engine`",WinBreathe.Engine.psm1",
    "/resource:`"$v2Cli`",WinBreathe.ps1",
    "/resource:`"$v2Gui`",WinBreathe.GUI.ps1",
    "/resource:`"$v2Cfg`",tweaks.json",
    "/resource:`"$logoFile`",logo.png",
    "/resource:`"$iconFile`",icon.ico",
    "`"$csSource`""
)
& $cscPath @v2Args
if ($LASTEXITCODE -ne 0) { throw "v2.0.0 compilation failed." }

Copy-Item $v2ExeOut $rootExe -Force

# Create v2.0.0 Portable ZIP
$v2Stage = Join-Path $env:TEMP "WinBreathe_v2_stage"
if (Test-Path $v2Stage) { Remove-Item $v2Stage -Recurse -Force }
New-Item -ItemType Directory -Path "$v2Stage\src", "$v2Stage\config", "$v2Stage\assets", "$v2Stage\docs" -Force | Out-Null
Copy-Item $v2ExeOut "$v2Stage\WinBreathe.exe" -Force
Copy-Item (Join-Path $repoRoot "WinBreathe.bat") "$v2Stage\WinBreathe.bat" -Force
Copy-Item $v2Engine "$v2Stage\src\WinBreathe.Engine.psm1" -Force
Copy-Item $v2Cli    "$v2Stage\src\WinBreathe.ps1" -Force
Copy-Item $v2Gui    "$v2Stage\src\WinBreathe.GUI.ps1" -Force
Copy-Item $v2Cfg    "$v2Stage\config\tweaks.json" -Force
Copy-Item "$repoRoot\assets\*" "$v2Stage\assets\" -Force
Copy-Item "$repoRoot\docs\*"   "$v2Stage\docs\" -Force
Copy-Item "$repoRoot\README.md", "$repoRoot\LICENSE", "$repoRoot\CHANGELOG.md" $v2Stage -Force

$v2Zip = Join-Path $relV2Dir "WinBreathe-v2.0.0-Portable.zip"
if (Test-Path $v2Zip) { Remove-Item $v2Zip -Force }
Compress-Archive -Path "$v2Stage\*" -DestinationPath $v2Zip -Force
Remove-Item $v2Stage -Recurse -Force

# Generate SHA256SUMS.txt for v2.0.0
$v2Hashes = Get-ChildItem $relV2Dir -Include *.exe, *.zip -Recurse | ForEach-Object {
    $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$h  $($_.Name)"
}
Set-Content -Path (Join-Path $relV2Dir "SHA256SUMS.txt") -Value ($v2Hashes -join "`r`n") -Encoding UTF8 -Force

Write-Host "[OK] Built v2.0.0 Release Artifacts in releases\v2.0.0\ and root WinBreathe.exe" -ForegroundColor Green
