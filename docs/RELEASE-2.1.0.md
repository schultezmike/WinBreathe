# WinBreathe 2.1.0 preview

Prepared for publication as a **prerelease**, not a claim of validated legacy performance.

## Updated v2.1.0 downloads

The replacement executable and portable package fix snapshot publication on Windows PowerShell 5.1 when `latest.json` already exists. The earlier build could fail with "The path is not of a legal form" and abort optimization. The corrected build passes an actual null backup path to .NET file replacement. A real-filesystem regression test verifies first creation, replacement, retained earlier backup, content hashes and temporary-file cleanup. The action log now uses "Click Optimization".

Report and isolated compatibility suites also pass. A user-provided Windows 11 log shows successful snapshot creation and 17 successful setting operations, with the Widgets registry write denied. This is not a legacy-OS or performance benchmark.

## Requirements and coverage

- x64 Windows; Windows PowerShell 5.1 and compatible .NET Framework must be installed. Windows 7 requires SP1 and WMF 5.1. Stock Windows 7/8.1 installations are not sufficient.
- Windows 7/8.1 paths are experimental: isolated regression checks do not replace target-OS execution.
- Update Guard is unavailable on Windows 7. No scheduled task is installed without the ScheduledTasks module.
- Disk fallback obtains a model through WMI and leaves media type unknown rather than guessing HDD/SSD.
- MMAgent snapshots retain only properties exposed by the OS. Unsupported compression is not restored on older systems.
- Default profiles do not resize pagefiles. Manual override replaces configured paging paths, requires restart, and must be sized against commit and crash-dump requirements. Fixed size does not guarantee contiguous allocation.
- Prefetch, compatibility-service changes, error-reporting suppression, and last-access tuning are opt-in. Their speed/memory benefits are unmeasured.
- Aero adjustment changes Peek/thumbnail preferences, not Glass composition or animations.

## Validation before stable promotion

On disposable Windows 7 SP1 x64 and Windows 8.1 x64 installations with prerequisites, verify launch, hardware detection, preview, selected application, restart, drift inspection, and snapshot Undo. Check absent/disabled services and denied permissions. Confirm Windows 7 Guard is unavailable and Windows 8.1 Guard installs/removes correctly.

Measure repeated baseline and treated runs of idle CPU/private memory, cold/warm app launch time, boot time, peak commit, hard faults, and disk latency on representative HDD hardware. Use identical workloads and report regressions as well as improvements. VM results establish functionality only, not physical HDD performance.

No target-OS execution, benchmark, crash-interruption test, code signing, or stable-release acceptance is claimed by this package.

## Local verification

Run `powershell -NoProfile -File tests/Compatibility.Tests.ps1` and `powershell -NoProfile -File Compile.ps1 -VerifyOnly`. Build with `Compile.ps1`. Publish the versioned executable, ZIP, and checksum manifest together as a prerelease. A locked root executable may remain older; use the versioned executable.
