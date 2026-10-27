# Contributing to WinBreathe

Thank you for your interest in contributing to **WinBreathe**!

## Design Principles

1. **Zero Harm to User Workflows**: Never add tweaks that break networking, VPNs, Windows Defender, audio, or developer tools. Any tweak with visible side effects must be labeled `Moderate` or `Advanced` (opt-in) in [`config/tweaks.json`](config/tweaks.json).
2. **Declarative & Reversible**: Prefer adding tweaks declaratively in `config/tweaks.json` so `New-WBSnapshot`, `Restore-WBSnapshot`, `Test-WBTweakState`, and `-WhatIf` support them automatically.
3. **Pure ASCII Scripts**: Keep all `.ps1`, `.psm1`, and `.bat` files strictly clean 7-bit ASCII so Windows PowerShell 5.1 and `cmd.exe` never encounter UTF-8/ANSI encoding bugs across locales.
4. **No External Binary Dependencies**: WinBreathe must run out-of-the-box on stock Windows 10/11 installations using native PowerShell 5.1+ and .NET WinForms/GDI+.

## Testing Your Changes

Before submitting a Pull Request, run the verification suite from an elevated or standard PowerShell prompt:

```powershell
# Run the release checks, compiler, real executable preview and package validation
.\scripts\Test-Release.ps1 -Build

# 1. Verify zero syntax errors across all scripts
Get-ChildItem .\src\*.ps* | ForEach-Object {
    $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$err)
    if ($err) { throw "Syntax error in $($_.Name): $err" }
}

# 2. Run read-only drift status & dry-run preview
.\src\WinBreathe.ps1 -Status
.\src\WinBreathe.ps1 -Profile Balanced -WhatIf
```
