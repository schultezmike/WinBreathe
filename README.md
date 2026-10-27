# WinBreathe v2.2.0 - Memory Watch

A native Windows memory monitor and settings utility. Version 2.2.0 adds **Memory Watch** for commit exhaustion and unusually large kernel pools. It warns and records evidence while open or minimized; it cannot guarantee crash prevention or repair a driver leak.

## What's new in 2.2.0

- Commit-headroom and kernel-pool alerts, including tray operation, rate limiting and stable recovery detection.
- Investigate Memory, recent exhaustion/restart details, private-commit readings and a small rotating journal.
- Optimization is deferred when its initial memory reading is critical or unavailable.
- Bounded task output and console history, chart-resource disposal, and pressure findings in reports.

See [the v2.2.0 notes](docs/RELEASE-2.2.0.md) and [the October 26 restart investigation](docs/INVESTIGATION-2026-10-26.md). This release does not silently change paging, stop apps or disable drivers.

## Published package

[Download v2.2.0](https://github.com/schultezmike/WinBreathe/releases/tag/v2.2.0) or browse the [package files](releases/v2.2.0/). The release includes an x64 executable, portable ZIP, SHA-256 checksums, release notes and source manifest.

Versions 2.0.0 and 2.1.0 are retired because they lack later safety fixes. Their Git tags and source history are retained. Version 2.1.2 is superseded by this update; it did not include Memory Watch or the bounded console and chart fixes. [Version 1.1.0](https://github.com/schultezmike/WinBreathe/releases/tag/v1.1.0) remains available as a legacy release; keeping it available does not certify its security or compatibility.

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
.\src\WinBreathe.ps1 -MemoryStatus
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

Tests use synthetic state, disposable files and non-mutating preview invocations, including critical commit, kernel-pool growth, recovery, invalid telemetry, event parsing and bounded history/output. Elevated Undo, legacy OS execution, power-loss behavior and long-session memory-pressure behavior remain incompletely tested. GitHub checks verify the tested code paths and package, not protection from every crash.

Licensed under MIT. Security reports: use GitHub private security advisories.
