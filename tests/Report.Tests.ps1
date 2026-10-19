#Requires -Version 5.1
# Synthetic report fixture; no live telemetry, module import or system changes.
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reports/sample'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens=$null; $errors=$null
$root=Split-Path -Parent $PSScriptRoot
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/WinBreathe.Engine.psm1'),[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Export-WBReport'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
function Get-WBPaths { [pscustomobject]@{ReportDir=$OutputDirectory} }
function Get-WBSystemProfile { [pscustomobject]@{OSCaption='SAMPLE DATA - Windows 11'; UsedRAMMB=4096;TotalRAMMB=8192;AvailRAMMB=4096;LoadPercent=50;FreeDiskGB=100;SystemDrive='C:'} }
function Get-WBUpdateGuardStatus { [pscustomobject]@{Installed=$false;State='Not Installed'} }
function Get-WBTopProcesses { [pscustomobject]@{AppName='<script>alert(1)</script>|Example';MemoryMB=400} }
function Write-WBLog { param($Message,$Level) }
function Test-WBTweakState {
    foreach ($fixture in @(
        @('Matching',$true,$true,$true,'Applied','1'),
        @('Optional',$true,$false,$false,'Default','0'),
        @('Unavailable',$false,$true,$false,'NotApplicable','0'),
        @('Review',$true,$true,$false,'Default','<unsafe>'),
        @('UnknownAdmin',$true,$true,$null,'Unknown','Requires Admin'),
        @('UnknownGeneric',$true,$true,$null,'Unknown','Could Not Verify')
    )) {
        $id = if ($fixture[0] -eq 'Review') { 'win.widgets' } else { $fixture[0] }
        [pscustomobject]@{Title=$fixture[0];Applicable=$fixture[1];InProfile=$fixture[2];IsApplied=$fixture[3];State=$fixture[4];Description='Plain explanation';Id=$id;CurrentValue=$fixture[5];TargetValue=0}
    }
}
$result=Export-WBReport
$html=Get-Content $result.HtmlPath -Raw
$md=Get-Content $result.MarkdownPath -Raw
foreach($expected in @(
    'What to do next',
    '1 / 4',
    'Optional - not set',
    'Not available on this PC',
    'Not set for this profile',
    'Could not verify - administrator access required',
    'Could not verify',
    '2. Technical details',
    '&lt;script&gt;',
    '1. What is happening on your computer',
    'These settings are confirmed not in place: Review',
    'Could not verify - administrator access required: UnknownAdmin',
    'Could not verify: UnknownGeneric',
    'select only Turn off Windows Widgets',
    '100 GB free'
)) {
    if (-not $html.Contains($expected)) { throw "Missing report content: $expected" }
}
if($html.IndexOf('What to do next') -gt $html.IndexOf('<section class="technical">')) {throw 'Narrative must precede technical section'}
if($html.Contains('<script>')) {throw 'Unsafe app name was not escaped'}
if(-not $md.Contains('&#124;Example')) {throw 'Markdown table delimiter was not escaped'}
Write-Host 'PASS: plain-language statuses, applicable-profile counts, optional details and escaping'
Write-Host "Sample report: $($result.HtmlPath)"
