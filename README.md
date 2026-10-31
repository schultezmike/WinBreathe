# WinBreathe v2.3.0 - Memory Watch and controlled RAM relief

A native Windows memory monitor and settings utility. Version 2.3.0 adds controlled relief of idle optional Windows hosts and earlier growth warnings. AI, ABOS and VPN workloads are protected. It cannot guarantee crash prevention or repair a driver leak.

## New in 2.3.0

- **RAM Relief** trims verified idle Search/Widgets hosts without terminating them; results distinguish available RAM from committed allocations.
- Opt-in **Auto RAM relief** acts on sustained low RAM with cooldowns and backs off when ineffective. It never trims ChatGPT, ABOS, VPNs or generic WebViews.
- Growth warnings look for sustained increases before fixed limits are reached.
- Closing the window keeps Memory Watch in the tray; use the tray's explicit Exit action to stop it. Hidden charts stop repainting.
- Hard protection for development helpers and protected process ancestry.

See [2.3.0 changes and limits](docs/RELEASE-2.3.0.md). Working-set relief can be temporary and can cause pages to be read back from disk. It is not a permanent cure for allocation growth.

## What's new in 2.2.0

- Commit-headroom and kernel-pool alerts, including tray operation, rate limiting and stable recovery detection.
- Investigate Memory, recent exhaustion/restart details, private-commit readings and a small rotating journal.
- Optimization is deferred when its initial memory reading is critical or unavailable.
- Bounded task output and console history, chart-resource disposal, and pressure findings in reports.

See [the v2.2.0 notes](docs/RELEASE-2.2.0.md) and [the October 26 restart investigation](docs/INVESTIGATION-2026-10-26.md). This release does not silently change paging, stop apps or disable drivers.

## Published package

[Download v2.3.0](https://github.com/schultezmike/WinBreathe/releases/tag/v2.3.0) or browse the [package files](releases/v2.3.0/). The release includes an x64 executable, portable ZIP, SHA-256 checksums, release notes and source manifest.

Versions 2.0.0, 2.1.0 and 2.1.2 are retired because they lack later safety fixes. Version 2.2.0 is superseded by 2.3.0, which adds controlled relief, growth warnings and protection against very large unterminated task-output lines. Historical tags, source and packages are retained for recovery; older package directories are not recommended downloads. [Version 1.1.0](https://github.com/schultezmike/WinBreathe/releases/tag/v1.1.0) remains available as a legacy release; keeping it available does not certify its security or compatibility.

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
# Controlled manual relief, or keep monitoring in the tray with auto relief
.\src\WinBreathe.ps1 -RelieveMemory
.\src\WinBreathe.ps1 -Watch
# Export a report
.\src\WinBreathe.ps1 -ExportReport
# Launch the source GUI (trust this source folder before running elevated)
.\src\WinBreathe.ps1 -GUI
```

Apply only settings you have reviewed. A backup is mandatory. Some changes require an app restart, sign-out or reboot; they do not necessarily reduce current RAM use.

For optional sign-in startup, create a shortcut to the downloaded executable with `-Watch` as its argument and put it in your current-user Startup folder. Keep the executable at that location. Startup is opt-in: WinBreathe does not register itself or a service. Windows can delay startup applications, and hardware/provider initialization can delay the first reading. Confirm the tray monitor is active before relying on its alerts.

## Validation

```powershell
.\scripts\Test-Release.ps1 -Build
```

Tests use synthetic state, disposable files and non-mutating preview invocations, including critical commit, kernel-pool growth, recovery, invalid telemetry, event parsing and bounded history/output. Elevated Undo, legacy OS execution, power-loss behavior and long-session memory-pressure behavior remain incompletely tested. GitHub checks verify the tested code paths and package, not protection from every crash.

Publication requires passing local checks, pull-request and main-branch GitHub checks, and the tagged build. The tagged workflow creates a draft; downloaded assets are checked against their hashes, source manifest and embedded resources before publication. Superseded v2 releases are retired recoverably only after the new downloads are verified. Version 1.1.0 is retained.

Licensed under MIT. Security reports: use GitHub private security advisories.
