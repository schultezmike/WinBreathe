# WinBreathe v2.0 — Frequently Asked Questions (FAQ)

### 1. Why does Microsoft Edge say *"Managed by your organization"* after optimizing?
WinBreathe uses official Microsoft Edge Group Policy registry keys under `HKLM:\SOFTWARE\Policies\Microsoft\Edge` (such as `StartupBoostEnabled = 0`, `BackgroundModeEnabled = 0`, and `SleepingTabsEnabled = 1`) because consumer preferences inside Edge are frequently overridden by Edge updates. Windows and Chromium browsers display *"Managed by your organization"* whenever any key under `Policies\Microsoft\Edge` is present.
- You can verify every exact policy key in [`docs/TWEAKS.md`](TWEAKS.md) or at `edge://policy`.
- Running **Undo (`-Undo`)** or **Reset Stock Defaults (`-ResetDefaults`)** removes these policy keys and the banner disappears immediately.

### 2. Does WinBreathe use `EmptyWorkingSet` like other RAM cleaners?
**No.** Calling `EmptyWorkingSet()` forces active application pages out of physical RAM and onto your pagefile on disk. On an 8 GB RAM laptop or mechanical HDD, the moment you switch back to your IDE or browser, Windows must read thousands of evicted pages back from disk—causing severe UI freezes. WinBreathe reclaims memory by stopping background bloat, enabling kernel Memory Compression, and putting inactive browser tabs to sleep.

### 3. Will WinBreathe disconnect my VPN or crash my AI coding tools?
**No.** All VPN clients (`OpenVPNConnect`, `openvpn`, `wireguard`, `tailscaled`) and AI/developer tools (`Antigravity`, `ChatGPT`, `codex`, `Claude`, `Code`, `Cursor`, `node`, `python`, `git`) are strictly listed in `protectedProcesses` inside [`config/tweaks.json`](../config/tweaks.json). Furthermore, WinBreathe checks parent process IDs before flushing `msedgewebview2.exe` so IDE webviews are never killed.

### 4. What is the difference between **Undo (Restore Backup)** and **Reset Stock Defaults**?
- **Undo (`-Undo`)**: Restores your computer's exact state from the JSON snapshot (`%ProgramData%\WinBreathe\backups\latest.json`) taken right before you ran WinBreathe. If you already had a custom pagefile or a specific service disabled before using WinBreathe, **Undo** preserves your custom setup.
- **Reset Stock Defaults (`-ResetDefaults`)**: Removes all WinBreathe policy keys and resets services, `MMAgent`, and pagefile management back to Windows 11 factory defaults.

### 5. Why is disabling Windows Search (`svc.wsearch`) unchecked by default?
While stopping the `WSearch` indexer eliminates heavy background disk I/O on mechanical hard drives, it also breaks instant file searching in the Start Menu, File Explorer, and classic Outlook. Therefore, `svc.wsearch` is marked **Advanced (Opt-In)** and is never applied unless you explicitly check it in the **Optimize Tweaks** tab (recommended only if you use a third-party search utility like [Voidtools Everything](https://www.voidtools.com/)).

### 6. Which Windows versions are supported?
- **Windows 11 & Windows 10 (1809+)**: Fully supported out of the box with zero external dependencies.
- **Windows Server (2016, 2019, 2022, 2025)**: Fully supported with automatic bypass of consumer features.
- **Windows 7 & Windows 8.1**: Scheduled for full legacy support in the upcoming **v2.1.0 release**, including legacy kernel memory tuning, Superfetch controls, and classic Chromium optimization for older student laptops.
