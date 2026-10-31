# WinBreathe 2.3.0 - controlled RAM relief

This update restores an active relief option while preserving development work.
It does not close ChatGPT, ABOS, VPNs, browsers, or Windows hosts. It does not
delete chats, clear application data, suspend tasks, purge standby memory, or
promise to prevent every crash. It replaces the v2.2.0 download while preserving
historical source and recoverable packages. Version 1.1.0 remains available.

## Changes

- **RAM Relief** requests a working-set trim only for verified idle Windows
  Search/Widgets hosts in protected installation locations and the same user
  session. Native checks retain one process handle, verify creation time,
  executable and ownership, and reject visible or recently busy processes.
- **Auto RAM relief** is opt-in in the GUI. It waits for 30 seconds below 20%
  available RAM (or 768 MB on smaller systems), samples host CPU use, limits
  each pass to three hosts, and waits five minutes between attempts. An
  ineffective attempt backs off for fifteen minutes. Kernel pressure, low
  commit headroom, invalid readings and extreme RAM shortage defer relief.
- `-Watch` starts in the tray with auto relief enabled. Closing the window keeps
  monitoring active. Use **Exit and stop Memory Watch** in the tray to quit.
  This does not register a sign-in task or a service.
  Sign-in startup can be configured explicitly by the user; see the README.
- Bounded growth history can warn before fixed thresholds when commit is
  steadily rising toward exhaustion or kernel allocations keep increasing.
  Estimates reset after gaps, invalid readings or changes to the commit limit.
- Protected development and VPN names now include Codex helpers, ABOS workers,
  Python variants, VMs, local model runtimes and database servers. Manual app
  closure also checks ancestry and stops if it is incomplete or protected.
- Hidden charts no longer request redraws. Monitoring, history and automatic
  relief keep running in the tray.
- Child output is now read in fixed chunks. A huge line without a newline can
  no longer bypass the old per-line limit before the callback runs. Display
  failures dispose the output queue.

## What a smaller RAM reading means

Working-set trimming removes resident pageable pages. It does not make the
application free its allocations, and the pages can return when needed. Reading
them back can cost disk I/O, especially on HDDs. Results therefore show observed
available-RAM and commit changes separately without attributing every change to
WinBreathe. The old v2.1 flush killed hosts, including WebViews with missing
parent information; that behavior is intentionally not restored.

Permanent improvement requires reducing the allocation source. If a driver's
kernel allocations grow, trimming ChatGPT cannot repair the driver. If active
ChatGPT tasks need their memory, preserving those tasks limits safe reclamation.

## Compatibility and validation boundaries

The existing capability/profile checks remain in place. This is an x64 Windows
PowerShell 5.1/.NET application. Windows 7/8.1 remain experimental; XP, NT 4.0 and
Windows 2000 are not supported by this build. Unknown host executables are skipped.

The release gate runs `scripts/Test-Release.ps1 -Build`. The tests cover synthetic
growth, safety gates, cooldowns, identity rejection, GUI lifetime, protected
processes, packaging and launcher previews. They do not establish long-session
performance gains, crash prevention or legacy-system runtime compatibility.

A Windows 11 smoke check confirmed fresh tray-monitor readings after a manual
relaunch following a reboot. Initialization took about two minutes on that
machine; startup is not an instantaneous protection guarantee. Automatic
pagefile sizing and sign-in startup configured on a test PC are machine settings,
not changes silently applied by this release. No saved chats are modified.

GitHub builds the tagged source and prepares a draft. Release assets are
downloaded and verified before the draft is published as the latest release.
Older v2 downloads are retired only after the new public downloads verify.

References: [Microsoft working-set behavior](https://learn.microsoft.com/en-us/windows/win32/memory/working-set)
and [kernel leak investigation](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/using-poolmon-to-find-a-kernel-mode-memory-leak).
