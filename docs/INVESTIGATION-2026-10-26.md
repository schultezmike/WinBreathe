# October 26 restart investigation and WinBreathe update

## What happened

Windows recorded eight low-virtual-memory events between 4:15 and 5:33 p.m. Pacific time on October 26, 2026. A subsequent restart was recorded with stop code **0x000000EF, CRITICAL_PROCESS_DIED**. That establishes that a critical Windows process terminated. The underlying cause remains unproven without analysis of the crash dump.

The event at 5:33 p.m. recorded:

| Reading | Recorded value |
|---|---:|
| Total committed memory | 19.63 GiB |
| System commit limit | 19.87 GiB |
| Windows kernel paged pool | 9.96 GiB |
| Largest paged-pool allocation tag | FMfn |
| Allocation under that tag | 8.17 GiB |

At 4:15 p.m., the same tag accounted for 7.30 GiB. This growth and the very large kernel pool make kernel allocation a major suspect. A pool tag alone does not identify the driver or prove that it caused the crash. App-private memory totals cannot explain all kernel allocations.

The separate "Investigate Windows restart cause" chat also recorded an Everything out-of-memory error at 5:14 p.m. and a new boot around 5:40 p.m. Windows' retrospective shutdown time conflicts with later recorded activity, so it is not treated as the precise crash time.

WinBreathe applied the Balanced profile at approximately 3:39 p.m., before these warnings. Temporal order does not establish causation. There is no evidence here that the Widgets access denial caused the restart, or that any individual browser or AI app caused the kernel growth. The crash dump exists; its contents have not been analyzed in this update.

## Why v2.1.2 did not stop it

Version 2.1.2 applied settings and displayed physical memory and a commit bar. It did not provide a sustained-pressure alert, background tray monitoring or bounded pressure history. Its Memory Check action was read-only. It did not repair kernel leaks, increase memory capacity or guarantee protection from resource exhaustion.

The earlier release passed code and package checks. Those checks were not a long-running memory-pressure or crash-prevention acceptance test. The previous description of the release must not be interpreted as that assurance.

## Changes in v2.2.0

- Reads system-wide commit and kernel pools through GetPerformanceInfo, rather than treating MEMORYSTATUSEX process-limited pagefile fields as authoritative global commit.
- Adds Memory Watch, checking readings every three seconds while the GUI is running, including when minimized to its tray icon.
- Warns after sustained pressure, escalates critical readings immediately, rate-limits repeat notifications and requires sustained recovery before clearing a warning.
- Adds early detection of unusually large paged/nonpaged kernel pools, with advice to investigate drivers and filters rather than blame the largest ordinary app.
- Records a small numeric history every minute and on state changes, rotating within two 1 MiB files under the current user's WinBreathe data folder.
- Adds Investigate Memory and CLI `-MemoryStatus`: recent event 2004 details and restart stop codes, commit headroom, pagefile-management status and top private commitments.
- Defers live optimization if its initial memory assessment is Critical or Unknown, before taking a backup or applying changes. Preview remains available. This is a preflight check, not a reservation of future headroom.
- Includes pressure and kernel findings in narrative-first HTML/Markdown reports.
- Bounds the GUI console and child-output queue; disposes chart drawing resources that were previously retained.

No process is automatically terminated. No standby purge, app working-set trimming, driver disablement, automatic restart or silent pagefile change was introduced.

## What still needs attention on this PC

The inspected configuration uses a fixed 12 GiB pagefile, with automatic pagefile management disabled. Review Windows-managed paging before another heavy session. Additional commit headroom may delay exhaustion, but cannot stop an indefinitely growing kernel allocation and is not a substitute for RAM.

An administrator should analyze the existing crash dump to identify the critical process and relevant kernel allocations. If a responsible driver or filter is established, update or repair that component using its publisher's supported procedure. Do not disable security/storage drivers based on FMfn alone. Driver Verifier was not enabled; it can intentionally trigger crashes and is not an unattended fix.

After this morning's reboot, a read-only sample showed about 6.3 GiB committed against a 19.87 GiB limit, with approximately 301 MiB paged pool and 271 MiB nonpaged pool. That lower reading does not establish that the original leak is gone. Long-session observation and dump analysis remain necessary.

Memory Watch cannot guarantee prevention of another crash. It does not run after WinBreathe exits and is not installed as a service or startup task. Windows may suppress notifications; an unattended user may not see them. Keeping the window open or minimizing it to the tray enables observation and evidence, not a repair to an unknown driver.

## Evidence and privacy

The relevant Windows event XML was independently read and compared with the other chat's findings. Raw event records are stored locally in the ignored `.release-work/incident-20261026/` directory; the earlier chat also retained its own evidence. No raw event logs, usernames, machine identifiers, dump contents or command lines are included in release assets or uploaded as part of this work.

## Verification and remaining limits

The release validation command covers nine test suites: compatibility, reporting, snapshot files, security, catalog, Memory Watch, hidden GUI construction/layout, launcher and package. Memory Watch tests cover critical commit with physical RAM still available, large kernel pools, missing/invalid readings, sustained warnings, cooldown, recovery, interrupted sampling, XML parsing and bounded journal/output behavior. Tests use synthetic pressure; no real memory-exhaustion stress test was performed.

The read-only diagnostic was also exercised against this PC's live counters and real event history. All eight saved exhaustion records parsed with their 98.7-99.2% commitment and FMfn tag. Hidden WinForms tests construct the real view with synthetic data, check control bounds/message fit, verify that console retention preserves the newest output, and check that the message loop continues after the form is hidden until explicitly closed.

Interactive Windows automation could not be verified: the computer-use helper's `list_apps` request timed out, including its retry and reset recovery. Hidden layout tests do not prove mouse interaction, notification visibility, tray restore behavior or performance at a different display scale. Windows 7/8.1, elevated Undo, long-session stability and prevention of another real incident remain unverified. GitHub publication is gated on the tagged Windows build passing the release validation command; that gate does not replace these outstanding acceptance tests.

## References

- [Microsoft: CRITICAL_PROCESS_DIED](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0xef--critical-process-died)
- [Microsoft: system committed memory and pagefiles](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/introduction-to-the-page-file)
- [Microsoft: GetPerformanceInfo](https://learn.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-getperformanceinfo)
- [Microsoft: MEMORYSTATUSEX field semantics](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex)
