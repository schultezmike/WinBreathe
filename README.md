# WinBreathe 2.1.2 preview

A native Windows memory monitor and settings utility. Version 2.1.2 fixes reliability and security problems in earlier v2 builds. It does not promise a particular RAM percentage or performance improvement.

## Current package

[Download v2.1.2](https://github.com/schultezmike/WinBreathe/releases/tag/v2.1.2) or browse the [package files](releases/v2.1.2/). The release includes an x64 executable, portable ZIP, SHA-256 checksums, release notes and source manifest.

Earlier v2 downloads are retired because they lack these fixes. Their Git tags and source history are retained. The local-only v2.1.1 preview is superseded. [Version 1.1.0](https://github.com/schultezmike/WinBreathe/releases/tag/v1.1.0) remains available as a legacy release; keeping it available does not certify its security or compatibility.

## What's new in 2.1.2

- Profile application leaves running apps and Windows hosts open. **Memory Check** is read-only; the legacy `-Flush` alias no longer kills processes.
- `-WhatIf` blocks all alternate actions; failures return error codes. The GUI reads task output without waiting on pipes and no longer displays raw PowerShell progress XML.
- Executables use embedded source and an absolute Windows PowerShell path. Elevated runtimes and backups require protected ownership and permissions.
- Undo validates snapshot identity and targets before making changes. New protected backups require administrator access; older backups are preserved for manual review.
- New Update Guard installs and generic factory reset are disabled. Existing Guard tasks can be removed explicitly.
- Fixed-size paging and legacy performance tuning remain opt-in. The patch does not purge standby memory or trim app working sets.
- Runs with failed tweaks show warning summaries. Access denial is explained without changing Windows permissions. Memory readings explicitly state when there was no immediate reduction.
- The release workflow tests the catalog, regressions, launcher, archive contents and checksums before publishing. Actions use fixed commit references and release-writing permission is isolated to the publishing job.

See [the release notes](docs/RELEASE-2.1.2.md), [changelog](CHANGELOG.md) and [audit and RAM investigation](docs/AUDIT-2.1.1.md) for details.

## Requirements

Windows x64, Windows PowerShell 5.1 and a compatible .NET Framework runtime. Windows 7 requires SP1 and WMF 5.1. Windows 7/8.1 support remains experimental and unverified on those operating systems. Administrator access is needed to change machine settings and create or restore protected snapshots. Monitoring and reports can run without elevation.

## Usage

```powershell
# Inspect only
.\src\WinBreathe.ps1 -Status
.\src\WinBreathe.ps1 -Profile Balanced -WhatIf
# Read memory without terminating apps
.\src\WinBreathe.ps1 -Flush
# Export a report
.\src\WinBreathe.ps1 -ExportReport
# Launch the source GUI (trust this source folder before running elevated)
.\src\WinBreathe.ps1 -GUI
```

Apply only settings you have reviewed. A backup is mandatory. Some changes require an app restart, sign-out or reboot; they do not necessarily reduce current RAM use.

## Validation

```powershell
.\scripts\Test-Release.ps1 -Build
```

Tests use synthetic state, disposable files and non-mutating preview invocations. A user-supplied Windows 11 run reported a saved snapshot and 17 applied tweaks, with the Widgets write denied; it did not demonstrate immediate RAM savings. Elevated Undo, full GUI operation, legacy OS execution and power-loss behavior still need disposable-machine acceptance tests. Historical docs and screenshots may show older features and defaults. This remains a preview while those checks are incomplete.

Licensed under MIT. Security reports: use GitHub private security advisories.
