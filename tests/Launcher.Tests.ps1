#Requires -Version 5.1
# Exercises compiled launcher argument quoting and embedded-only runtime.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$exe=Join-Path $root 'releases/v2.1.2/WinBreathe-v2.1.2-x64.exe'
$assembly=[Reflection.Assembly]::LoadFile($exe)
$program=$assembly.GetType('WinBreatheHost.Program')
$flags=[Reflection.BindingFlags]'NonPublic,Static'
$quote=$program.GetMethod('QuoteWindowsArgument',$flags)
$native=@'
using System;
using System.Runtime.InteropServices;
public static class WBTestArgv {
 [DllImport("shell32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CommandLineToArgvW(string command, out int count);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr address);
 public static string ParseOne(string text) {
  int count; IntPtr argv=CommandLineToArgvW("program.exe " + text,out count);
  try { if(count!=2) throw new Exception("Unexpected argument count"); return Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv,IntPtr.Size)); }
  finally {LocalFree(argv);}
 }
}
'@
Add-Type -TypeDefinition $native
foreach($value in @('', 'with space', "with`ttab", 'quote"inside', 'C:\trailing space\', '$(literal); & text', "apostrophe'")) {
    $quoted=$quote.Invoke($null,@($value))
    if([WBTestArgv]::ParseOne($quoted) -cne $value){throw 'Launcher argv round trip failed'}
}
Write-Host 'PASS: native argv round trips for quotes, tabs, empty strings and trailing slashes'
# Run the executable through its real extraction path. It is in the repository
# beside mutable source but must use its own embedded scripts and return preview.
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName=$exe
$psi.Arguments='-GUI -WhatIf'
$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
$process=[Diagnostics.Process]::Start($psi)
try {
    if(-not $process.WaitForExit(20000)){throw 'Launcher failed to exit preview without opening GUI'}
    if($process.ExitCode -ne 0){throw 'Launcher preview exit code failed'}
}finally{$process.Dispose()}
Write-Host 'PASS: compiled launcher handles GUI plus WhatIf without opening a window'
foreach($name in @('WinBreathe.Engine.psm1','WinBreathe.ps1','WinBreathe.GUI.ps1','WinBreathe.ProcessOutput.cs','tweaks.json')) {
    $stream=$assembly.GetManifestResourceStream($name)
    if(-not $stream){throw "Missing embedded resource $name"}
    $sha=[Security.Cryptography.SHA256]::Create()
    $hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')
    $sha.Dispose();$stream.Dispose()
    $path=if($name -eq 'tweaks.json'){Join-Path $root 'config/tweaks.json'}else{Join-Path $root ('src/'+$name)}
    if($hash -ne (Get-FileHash $path).Hash){throw "Embedded resource mismatch: $name"}
}
Write-Host 'PASS: embedded engine, CLI, GUI, output reader and catalog match current source'
