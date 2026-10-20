# Changelog

All notable changes to **WinBreathe** are documented in this file.

## [2.1.2-preview] - 2026-10-20

- Publishes the security and reliability fixes developed in the local-only 2.1.1 preview, including the launcher startup fix, safe preview handling, protected snapshots, non-blocking output and readable failure summaries.
- Updates the executable, window, console and exported report to show version 2.1.2 consistently.
- Replaces outdated batch-menu claims and unmeasured memory-saving promises with descriptions of actual behavior.
- Requires regression, catalog, build, launcher and package checks before release publication. Actions are pinned to immutable commits; only the publishing job can write releases.
- Adds release notes, checksums and a source manifest. Retires previous v2 downloads while preserving version 1.1.0 and historical Git tags/source.
- Fixes portable-package source paths when Windows uses a shortened temporary-folder name, as on GitHub's Windows runners.
- Remains a preview: elevated Undo, Windows 7/8.1 runtime support and performance benefits have not been fully validated.

## [2.1.1-preview] - 2026-10-20 (local only; superseded)

- Fixed preview bypasses, protected-process wildcard handling, GUI output blocking, child exit reporting and launcher argument quoting.
- Use embedded-only runtimes and absolute PowerShell paths; elevated runtimes and new backups require protected ownership and permissions.
- Validate Undo content and identity before changing settings; preserve raw registry value types and reject unreadable backups.
- Disabled new SYSTEM Guard installs and generic factory reset pending trustworthy implementations.
- Removed automatic host termination. Memory Check is read-only and does not touch open apps.
- Fixed raw PowerShell progress XML in the GUI log while keeping real errors and exit codes. Partial runs now show warning summaries, explain denied access without changing permissions, and explicitly state when no immediate RAM reduction is observed.
- Added security/launcher regression suites and a repeatable read-only memory diagnostic. See docs/AUDIT-2.1.1.md for limits and migration notes.

## [2.1.0-preview] - 2026-10-19

- Fixed the GUI encoding validation failure; the compiler now enforces ASCII across source, tests and build script before packaging. Updated GitHub Actions to current releases.

- Fixed Windows PowerShell 5.1 snapshot replacement when latest.json already exists; added a real-filesystem regression test.

- Redesigned HTML and Markdown reports with plain-language summaries, next steps, setting explanations, and optional support details.

- Added guarded legacy hardware detection and capability-based MMAgent snapshots/Undo.
- Windows 7 Update Guard now reports unsupported instead of attempting missing commands.
- Made legacy performance tuning and fixed-size pagefiles opt-in; corrected descriptions and unsupported savings claims.
- Use the WMI automatic-pagefile property, not a fabricated registry switch.
- Added temporary-file replacement for latest snapshots and isolated compatibility regression checks.
- Corrected header overlap and renamed the action to Click Optimization.
- Added source provenance manifests and prerelease acceptance gates. Legacy runtime/performance and crash-interruption behavior remain unverified.

## [2.0.0] - 2026-10-19

### Added
- **Standalone Modular Architecture**: Extracted `WinBreathe.Engine.psm1`, `WinBreathe.ps1`, `WinBreathe.GUI.ps1`, and declarative `config/tweaks.json` into a clean standalone repository.
- **True State Snapshot & Undo (`New-WBSnapshot` / `Restore-WBSnapshot`)**: Saves exact pre-optimization registry values, service start types, `MMAgent` flags, and pagefile settings to `backup-<timestamp>.json` before making changes.
- **Preview / Dry-Run Mode (`-WhatIf`)**: Inspect every planned registry, service, and kernel memory action without modifying the system.
- **Hardware-Adaptive Profiles**: Added **Conservative**, **Balanced**, and **Aggressive** profiles with automatic hardware recommendation.
- **6-Tab Native Dark GUI**:
  - Custom GDI+ **Circular RAM Arc Gauge** and **Live 60-Sample Memory History Line Chart**.
  - Interactive **Optimize Tweaks** checklist with **Safe**, **Moderate**, and **Advanced** risk badges.
  - **Processes (RAM)** inspector grouped by application with strict Tier-1 protection.
  - **Startup Apps** manager with non-destructive backup/restore for disabled startup items.
  - **Status & Guard** live drift detector and 1-click Update Guard installer.
  - **HTML & Markdown Report Exporter** (`Export-WBReport`).
- **Brand Graphics**: Added `assets/banner.png`, `assets/feature-art.png`, `assets/logo.png`, and `assets/icon.ico`.

### Fixed & Hardened (Opus 5.5 & Gemini 4 Argon Audit)
- **B1/B2/WB-01**: Replaced broken `BackgroundWorker` event subscriptions and synchronous stderr pipe deadlocks with a non-blocking, runspace-safe process runner.
- **WB-02 (Security)**: Hardened `%ProgramData%\WinBreathe` NTFS ACLs using locale-independent `WellKnownSidType` SIDs (`BuiltinAdministratorsSid`, `LocalSystemSid`, `BuiltinUsersSid`).
- **WB-03 (Safety)**: Implemented parent-PID and command-line inspection before flushing `msedgewebview2.exe` so active AI IDEs (Antigravity, VS Code, Claude, Cursor) are never disrupted.
- **WB-04 & WB-06**: Switched pagefile configuration to kernel-authoritative `Memory Management\PagingFiles` registry keys and accounted for existing `pagefile.sys` allocation when checking free disk space.
- **WB-05**: Added deterministic GDI+ resource disposal on form exit.
- **WB-07**: Added automatic `HKEY_USERS\<SID>` resolution when running under `NT AUTHORITY\SYSTEM`.
- **Opt-In Windows Search (`svc.wsearch`)**: Moved `WSearch` to opt-in (`Advanced`) so Start Menu and Outlook search remain intact by default.

## [1.1.0] - 2026-10-19
- Initial release with Tier 1/2/3 optimization engine, basic WinForms window, and batch launcher.
