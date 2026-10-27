# WinBreathe v2.2.0 - Memory Watch

Adds early visibility into commit exhaustion and unusually large Windows kernel pools following investigation of a real low-memory restart. This release replaces v2.1.2 as the current download. It improves monitoring and diagnostics; it does not repair the still-unidentified kernel component behind that incident.

## What's new

- Memory Watch runs every three seconds while the GUI is open, including when minimized to its tray icon. Sustained warnings, immediate critical escalation and recovery hysteresis limit alert noise.
- System-wide commit headroom and kernel paged/nonpaged pools complement physical RAM readings. Large pools prompt driver/filter investigation; no culprit is inferred from a pool tag alone.
- Investigate Memory and `-MemoryStatus` show bounded recent Windows resource-exhaustion and restart records, stop codes, pagefile-management status and the largest private app commitments.
- A rotating numeric journal retains at most two 1 MiB files. The live console and child output queue are bounded; chart drawing resources are disposed.
- Critical or unavailable memory readings defer new live optimization before backup or changes. Preview remains available.
- Exported reports explain commit and kernel pressure before technical details. Reports distinguish current readings from proof of a past crash cause.

## Use

Open WinBreathe and choose **Keep watching in tray** to keep alerts running while the window is hidden. Double-click its tray icon to return. **Exit and stop Memory Watch** closes monitoring. This update does not install an automatic-start task or service.

Choose **Investigate Memory** after a slowdown or restart. **Windows memory settings** opens Advanced System Properties; it does not change the pagefile. Review Performance > Settings > Advanced > Virtual memory with your administrator if paging is capped or disabled.

## Alert rules

These are conservative heuristics, not Microsoft failure thresholds or a diagnosis:

- Warning: at least 85% commit used, at most 1 GiB commit headroom, at most 10% physical RAM available or at most 512 MiB available. It must persist for six seconds before the alert is latched.
- Critical: at least 95% commit used, at most 512 MiB commit headroom, at most 5% physical RAM available or at most 256 MiB available. Escalation is immediate at the next reading.
- Kernel warning: paged pool at least 25% of RAM and 512 MiB, or nonpaged pool at least 20% and 512 MiB. Critical: paged at least 50% and 1 GiB, or nonpaged at least 35% and 1 GiB.
- Repeat alerts are limited to one per five minutes, except escalation. Recovery requires 15 seconds at lower pressure; returning to Healthy also requires more than 12%/640 MiB available, commit below 80% with more than 1.5 GiB headroom and no pool warning. Sampling gaps over 30 seconds reset pending observations. Failed readings show Unknown.

## Limits

WinBreathe does not fix driver leaks, prevent every crash, guarantee lower RAM use, close apps automatically, trim app working sets, purge standby memory or silently resize paging. Windows may suppress alerts, the GUI thread may be busy, and no monitoring occurs after the application exits. Notifications and extra pagefile headroom are not sufficient unattended protection against an indefinitely growing kernel allocation.

Windows 7/8.1 execution, elevated Undo, full crash recovery and long-session behavior still require acceptance testing. Synthetic low-memory tests avoid exhausting the real PC. See [the investigation](INVESTIGATION-2026-10-26.md) and run `scripts/Test-Release.ps1 -Build` for the reproducible checks.

Hidden WinForms construction/layout checks are included. Interactive mouse/tray tests could not be completed because the Windows computer-use helper timed out. Publication is gated on the tagged Windows build passing regression, read-only status/preview, launcher and package checks. Passing those checks does not establish the absence of every bug or prove crash prevention.
