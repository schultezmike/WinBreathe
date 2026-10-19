<div align="center">

<img src="assets/banner.png" alt="WinBreathe - Universal Windows Memory & Latency Optimizer" width="100%" />

# WinBreathe

**Adaptive Windows Memory & Latency Optimizer for Windows 11, 10, 8.1 & 7 SP1**  
*Tailored for 4–16 GB RAM PCs, Mechanical HDDs, Laptops & Developer Stacks*

[![Platform](https://img.shields.io/badge/Platform-Windows%2011%20%7C%2010%20%7C%208.1%20%7C%207%20SP1-0078D6?logo=windows)](https://microsoft.com)
[![Latest Release](https://img.shields.io/badge/Release-v2.1.0-89b4fa.svg)](releases/v2.1.0/)
[![Executable](https://img.shields.io/badge/Binary-Standalone%20x64%20.EXE-a6e3a1.svg)](WinBreathe.exe)
[![License](https://img.shields.io/badge/License-MIT-a6e3a1.svg)](LICENSE)
[![Security](https://img.shields.io/badge/Security-SID%20Hardened%20%26%20True%20Undo-94e2d5.svg)](SECURITY.md)

[Downloads (v2.1.0)](#-releases--downloads) • [What's New in v2.1](#-whats-new-in-v21) • [Quick Start](#-quick-start) • [Architecture](docs/ARCHITECTURE.md) • [Tweak Catalog](docs/TWEAKS.md) • [Release Gates](docs/RELEASE-2.1.0.md) • [FAQ](docs/FAQ.md)

</div>

---

<div align="center">
  <img src="assets/screenshot-dashboard.png" alt="WinBreathe Live Graphical Dashboard" width="95%" style="border-radius:8px; border:1px solid #313244;" />
  <p><em>Native 6-Tab WinForms Dark Dashboard with Circular RAM Gauge and 60-point Memory History Chart (< 18 MB footprint).</em></p>
</div>

---

## 🚀 What's New in v2.1

WinBreathe v2.1 expands beyond Windows 11 and 10 to provide **adaptive operating system detection and tailor-made tuning** for **Windows 7 SP1** and **Windows 8.1**:

1. **Automatic OS & Hardware Telemetry at Startup**:
   - WinBreathe inspects your host machine's exact Windows version, build number, RAM capacity, and drive media type (SSD vs. HDD) at launch.
   - Automatically recommends the appropriate profile and tailors available tweaks specifically to that platform.
   - Simulated OS preview dropdown (`Windows 7`, `Windows 8.1`, `Windows 10`, `Windows 11`) lets you inspect tailor-made settings for other Windows versions directly from the UI without modifying host settings.
2. **Dedicated Windows 7 SP1 & Windows 8.1 Catalog Support**:
   - **SuperFetch & Prefetcher Boot-Only Tuning**: Eliminates 100% active disk thrashing on mechanical HDDs while keeping boot acceleration intact. Automatically skipped on SSDs.
   - **NTFS Last-Access Timestamp Write Churn**: Disables repetitive background metadata writes to disk.
   - **Legacy Service Optimization**: Sets Application Experience (`AeLookupSvc`), Program Compatibility Assistant (`PcaSvc`), and Windows Error Reporting (`WerSvc`) to manual/disabled.
   - **DWM Aero Glass RAM Trimming**: Toggles memory-heavy Aero Peek and persistent thumbnail caching on Windows 7.
3. **Redesigned Narrative-First Reports (HTML & Markdown)**:
   - Natural language summary explaining host memory pressure, largest running applications, and specific next steps.
   - Strict separation of confirmed setting differences, settings requiring administrator privileges, and settings unsupported on that operating system.
   - High-contrast, responsive light-themed HTML document format with zero text overlap.
4. **Hardened True Snapshot & Rollback**:
   - Atomic staged snapshot publishing with temporary files prevents corrupted state saves.
   - Strict-mode verified undo engine: catches and reports access-denied registry key deletions and restores original value kinds accurately.
   - Live optimization strictly enforces host OS boundaries regardless of simulation previews.

---

## 📦 Releases & Downloads

| Release | Architecture | Files | Notes |
|---|---|---|---|
| **[v2.1.0](releases/v2.1.0/)** (Latest) | x64 Standalone | [`WinBreathe-v2.1.0-x64.exe`](releases/v2.1.0/WinBreathe-v2.1.0-x64.exe), [`WinBreathe-v2.1.0-Portable.zip`](releases/v2.1.0/WinBreathe-v2.1.0-Portable.zip) | Full universal release: Windows 11, 10, 8.1, 7 SP1 with narrative report export |
| **[v2.0.0](releases/v2.0.0/)** | x64 Standalone | [`WinBreathe-v2.0.0-x64.exe`](releases/v2.0.0/WinBreathe-v2.0.0-x64.exe), [`WinBreathe-v2.0.0-Portable.zip`](releases/v2.0.0/WinBreathe-v2.0.0-Portable.zip) | 6-Tab GUI, 24-tweak catalog, snapshot undo |
| **[v1.1.0](releases/v1.1.0/)** | x64 / Script | [`WinBreathe-v1.1.0-x64.exe`](releases/v1.1.0/WinBreathe-v1.1.0-x64.exe), [`WinBreathe-v1.1.0-Portable.zip`](releases/v1.1.0/WinBreathe-v1.1.0-Portable.zip) | Initial baseline release |

All release archives include cryptographic SHA-256 manifests (`SHA256SUMS.txt`).

---

## 💻 Requirements

- **Operating System**: Windows 11, Windows 10, Windows 8.1, or Windows 7 SP1 (64-bit).
  - *Windows 7 / 8.1 Notice*: Requires Windows Management Framework (WMF) 5.1 and .NET Framework 4.8.
- **Privileges**: Administrator privileges required to apply registry optimizations and service changes; telemetry, drift inspection, report export, and `-WhatIf` previews can run unprivileged.

---

## ⚡ Quick Start

### Graphical User Interface (GUI)
Double-click `WinBreathe.exe` (or run `.\WinBreathe.bat` as Administrator). The GUI starts in under 0.8 seconds:
- **Dashboard**: View circular RAM gauge, 60-sample memory graph, and running processes.
- **Optimize Tweaks**: Inspect tailor-made tweaks for your detected OS (or select another OS from the dropdown to preview options). Click **Preview Selected (-WhatIf)** to test without touching your system.
- **Export Report**: Click **Export Report** in the top navigation bar to generate an instant HTML and Markdown audit.

### Command Line Interface (CLI)
```powershell
# 1. Preview changes without modifying anything (-WhatIf Dry Run)
.\src\WinBreathe.ps1 -Profile Balanced -WhatIf

# 2. Preview tailor-made options for Windows 7 or 8.1
.\src\WinBreathe.ps1 -PreviewOS Win7

# 3. Check live drift status and hardware telemetry
.\src\WinBreathe.ps1 -Status

# 4. Generate system telemetry & recommendations report
.\src\WinBreathe.ps1 -ExportReport

# 5. Restore previous state from snapshot backup
.\src\WinBreathe.ps1 -Undo
```

---

## 🛡️ Safety & Reliability

- **Tier-1 Protected Processes**: WinBreathe never terminates or empties the working sets of critical processes (Windows Explorer, DWM, Defender, VPN tunnels, and developer IDEs/AI runtimes).
- **True Snapshot Undo**: Takes a full pre-optimization state snapshot before applying changes. Roll back anytime with `.\src\WinBreathe.ps1 -Undo`.
- **Verified Regression Suite**: Validated through isolated compatibility and report test suites (`tests/Compatibility.Tests.ps1`, `tests/Report.Tests.ps1`).

---

## 📄 License

Licensed under the [MIT License](LICENSE).
