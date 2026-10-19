> Historical documentation: defaults and compatibility claims below may predate v2.1.0. Use [current release notes](RELEASE-2.1.0.md) and the current catalog for supported behavior. Legacy performance remains unverified.

# WinBreathe v2.0 — Complete Tweak Catalog Reference

All optimizations in WinBreathe are declaratively defined in [`config/tweaks.json`](../config/tweaks.json). Nothing is hidden in compiled binaries. Every tweak is captured by `New-WBSnapshot` before execution and can be reverted via `Restore-WBSnapshot` (`-Undo`) or `Restore-WBStockDefaults` (`-ResetDefaults`).

---

## Risk Badge Legend

| Risk Tier | Meaning |
| :--- | :--- |
| **Safe** | Zero day-to-day workflow loss. Stops background pre-loading, idle tab waste, or telemetry. |
| **Moderate** | Noticeable behavior change (e.g., Store apps only update while open, or fixed pagefile requires disk space). |
| **Advanced** | Opt-in only (not enabled in any default profile). Only enable if you understand the trade-off. |

---

## 1. Browser Optimizations (`Browser`)

| ID | Title | Risk | Profiles | Registry Target (`HKLM:\SOFTWARE\Policies\...`) | Effect & Trade-Off |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `edge.startupBoost` | Disable Edge Startup Boost | **Safe** | Conservative, Balanced, Aggressive | `Microsoft\Edge\StartupBoostEnabled = 0` | Stops Edge from pre-loading at Windows sign-in. Saves 100–300 MB while Edge is closed. |
| `edge.backgroundMode` | Stop Edge running in background | **Safe** | Conservative, Balanced, Aggressive | `Microsoft\Edge\BackgroundModeEnabled = 0` | Makes Edge fully exit when its last window closes. |
| `edge.sleepingTabs` | Put idle Edge tabs to sleep | **Safe** | Conservative (15m), Balanced (5m), Aggressive (30s) | `Microsoft\Edge\SleepingTabsEnabled = 1`, `SleepingTabsTimeout = 900/300/30` | Inactive tabs release working-set memory after timeout and reload when clicked. |
| `edge.efficiencyMode` | Enable Edge Efficiency Mode | **Safe** | Conservative, Balanced, Aggressive | `Microsoft\Edge\EfficiencyModeEnabled = 1` | Throttles background tab CPU and memory activity. |
| `edge.sidebar` | Turn off the Edge sidebar | **Safe** | Balanced, Aggressive | `Microsoft\Edge\HubsSidebarEnabled = 0`, `StandaloneHubsSidebarEnabled = 0` | Removes hidden sidebar web views (Copilot, Shopping, Tools). |
| `edge.copilot` | Turn off Copilot in Edge | **Safe** | Balanced, Aggressive | `Microsoft\Edge\EdgeCopilotEnabled = 0`, `DiscoverPageContextEnabled = 0` | Disables the built-in Copilot sidebar web view and page context reader. |
| `edge.networkPrediction` | Stop Edge pre-loading pages | **Safe** | Balanced, Aggressive | `Microsoft\Edge\NetworkPredictionOptions = 2` | Stops speculative pre-rendering of links. Fewer hidden renderer processes. |
| `edge.extras` | Turn off Edge shopping, recommendations & Math Solver | **Safe** | Balanced, Aggressive | `EdgeShoppingAssistantEnabled = 0`, `ShowRecommendationsEnabled = 0`, `MathSolverEnabled = 0` | Reduces background script injection on visited pages. |
| `edge.diskCache` | Cap Edge disk cache at 256 MB | **Safe** | Balanced, Aggressive | `Microsoft\Edge\DiskCacheSize = 268435456` | Limits disk cache growth and reduces disk I/O churn on HDDs. |
| `chrome.backgroundMode` | Stop Chrome and Brave running in background | **Safe** | Conservative, Balanced, Aggressive | `Google\Chrome\BackgroundModeEnabled = 0`, `BraveSoftware\Brave\BackgroundModeEnabled = 0` | Makes Chrome and Brave fully exit when closed. |

---

## 2. Windows Shell & Experience (`Windows`)

| ID | Title | Risk | Profiles | Registry Target | Effect & Trade-Off |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `win.widgets` | Turn off Windows Widgets | **Safe** | Balanced, Aggressive | `HKLM:\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests = 0` | Disables the taskbar Widgets board (`Widgets.exe` + `msedgewebview2.exe`), saving 100–250 MB. |
| `win.webSearch` | Remove Bing web results from Start search | **Safe** | Balanced, Aggressive | `Windows Search\DisableWebSearch = 1`, `ConnectedSearchUseWeb = 0`, `Explorer\DisableSearchBoxSuggestions = 1` | Start menu searches local apps/files only without spawning network queries to Bing. |
| `win.gameDvr` | Turn off Game DVR background recording | **Safe** | Balanced, Aggressive | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR = 0` | Frees background video capture buffers. |
| `win.backgroundApps` | Block Store apps from running in background | **Moderate** | Aggressive | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy\LetAppsRunInBackground = 2` | Prevents UWP Store apps from running background tasks when closed. |
| `win.transparency` | Turn off transparency effects | **Safe** | Aggressive | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\EnableTransparency = 0` | Disables acrylic/mica blur to reduce DWM compositor memory. |

---

## 3. System Services (`Services`)

| ID | Title | Risk | Profiles | Service & Target Startup | Effect & Trade-Off |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `svc.diagTrack` | Disable Connected User Experiences and Telemetry | **Safe** | Balanced, Aggressive | `DiagTrack` -> `Disabled` | Stops background diagnostic collection and upload. Does not affect Windows Update or Defender. |
| `svc.mapsBroker` | Set Downloaded Maps Manager to Manual | **Safe** | Balanced, Aggressive | `MapsBroker` -> `Manual` | Offline maps service only starts when Maps is opened. |
| `svc.dmwappush` | Disable WAP Push message routing | **Moderate** | Aggressive | `dmwappushservice` -> `Disabled` | Disables telemetry/MDM push router. Do not use on Intune/MDM-managed work PCs. |
| `svc.cdpSvc` | Disable Connected Devices Platform | **Moderate** | Aggressive | `CDPSvc` -> `Disabled` | Saves memory and network chatter; disables Nearby Sharing and Phone Link. |
| `svc.wsearch` | Disable Windows Search indexer *(Opt-In)* | **Advanced** | *None (Opt-In)* | `WSearch` -> `Disabled` | Eliminates background disk indexing I/O on HDDs, but degrades Start, Outlook, and File Explorer search. |

---

## 4. Kernel Memory & Storage (`Memory`)

| ID | Title | Risk | Profiles | Mechanism | Effect & Trade-Off |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `mem.compression` | Enable memory compression | **Safe** | Conservative, Balanced, Aggressive | `Enable-MMAgent -MemoryCompression` | Compresses cold pages in RAM instead of paging them out to slow disk storage. |
| `mem.pageCombining` | Enable memory page combining | **Safe** | Balanced, Aggressive | `Enable-MMAgent -PageCombining` | Merges identical read-only/copy-on-write pages across processes. |
| `mem.preLaunch` | Stop app pre-launch on mechanical drives | **Moderate** | Balanced, Aggressive *(HDD Only)* | `Disable-MMAgent -ApplicationPreLaunch` | Stops speculative Store app pre-loading on spinning HDDs. |
| `mem.pagefile` | Use a fixed-size contiguous page file | **Moderate** | Balanced, Aggressive *(Low RAM or HDD)* | `HKLM:\...\Memory Management\PagingFiles` (`1.5x RAM`, `4096–12288 MB`) | Prevents runtime pagefile growth and fragmentation stutters. Automatically skipped if remaining free disk space would fall below 15 GB. |
