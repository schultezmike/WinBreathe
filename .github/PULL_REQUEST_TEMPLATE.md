## Summary of Changes

- **What does this PR do?**
- **Which tweak IDs or files are affected?**

## Verification Checklist

- [ ] Tested with `.\Compile.ps1 -VerifyOnly` (0 syntax errors, pure 7-bit ASCII verified)
- [ ] Tested dry-run preview (`.\WinBreathe.exe -Profile Balanced -WhatIf`)
- [ ] Confirmed tweak is 100% reversible via `Restore-WBSnapshot` (`-Undo`)
- [ ] Confirmed no Tier-1 Protected Processes (Kernel, Defender, VPNs, AI Dev Stacks) are impacted
