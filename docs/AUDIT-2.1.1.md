# v2.1.1 local security and reliability audit

This is a local patch of v2.1.0. No system optimization was run during the audit. Existing apps, services, pagefile settings and tasks were left unchanged. This is not a claim of a complete security certification or validated Windows 7/8.1 support.

## Corrected behavior

- CLI `-WhatIf` now blocks alternate actions including Undo, reset, snapshot, flush and Guard commands. Conflicting actions are rejected. Failed operations return a failing exit code.
- Explicit app termination accepts only an exact process name. Wildcards can no longer bypass the protected-process list. Failed termination is not reported as full success.
- Profile application no longer implicitly terminates Search, Widgets or WebView2 processes. The Memory Check button and legacy `-Flush` alias only read memory. No working-set trimming, standby purge or forced collection in another process is used.
- The compiled executable runs its embedded scripts and catalog, not mutable neighboring files. PowerShell is resolved by its full Windows system path rather than PATH. Each launch has a fresh runtime directory; elevated launches use a protected Program Files parent with an administrator/SYSTEM DACL. Unelevated launches inherit their own temporary-folder permissions, including restricted-token/package access. CLI startup errors return an error code instead of leaving a modal dialog.
- Windows argument quoting handles embedded quotes, tabs, empty arguments and trailing backslashes.
- The GUI drains stdout and stderr through native event callbacks into a queue. Its timer no longer blocks on `ReadLine`/`EndOfStream`. Child PowerShell requests text output and suppresses progress serialization, preventing raw CLIXML in the console while retaining real warnings, errors and exit codes. Closing while a change is running is blocked rather than killing a half-finished operation. Catalog IDs are quoted before child invocation.
- New boot Guard installation is disabled. The old implementation hardened only a reused parent directory, which did not establish trusted ownership/permissions of every child script. The previous SYSTEM task was not installed on the inspected host. Existing installations on other machines are not changed by this patch; removal remains available.
- Generic stock reset is disabled because it cannot reliably reconstruct device/OS defaults. Use a valid snapshot instead.
- New snapshots use an admin-only, per-user store under `%ProgramFiles%\WinBreathe-State\<SID>`. Paths are checked for ownership, write permissions and reparse points. Undo validates schema, user identity, complete catalog registry targets, service names and state types before any mutation. Older ProgramData backups remain untouched but are not automatically trusted/restored. Keep them for manual review.
- Registry capture preserves raw expandable-string values and original value types. Read failures abort capture instead of pretending the value was absent. Missing restore services/MMAgent are counted as failures. Startup item moves retain registry value types.
- Failed tweak operations are counted separately from skipped operations; previews are counted separately from writes. Partial runs show warning summaries and explain that successful changes remain applied. Access denial is explained without altering permissions. Short-term RAM changes are labelled observations, not proven savings; no immediate reduction is stated explicitly when applicable. An unknown Windows version stops compatibility decisions; unknown disk space is not replaced with fictional free space. Pagefile matching checks the exact configured target.
- A protected operation lock serializes profile application, snapshot creation and Undo across instances, with nested snapshot capture sharing the current lease. This prevents one app instance from replacing the baseline while another changes settings.

## Verification

Run with Windows PowerShell 5.1:

```powershell
.\tests\Compatibility.Tests.ps1
.\tests\Report.Tests.ps1
.\tests\SnapshotFile.Tests.ps1
.\tests\Security.Tests.ps1
.\Compile.ps1
.\tests\Launcher.Tests.ps1
```

Coverage includes synthetic denied writes/deletes, real filesystem latest-backup replacement, malicious snapshot targets and identity, process wildcard rejection, eight alternate-action preview combinations, argument round trips through Windows argv parsing, delayed stdout plus 400 stderr lines, the actual GUI child runner against synthetic progress/warnings/errors with success and failure exits, and a compiled launcher preview with embedded resource parity.

Protected-store creation and elevated live apply/Undo still require acceptance testing in a disposable elevated Windows session. The agent did not run a live optimization. A subsequent user-supplied log from this computer is described below; it does not establish full acceptance. Windows 7/8.1 execution, full GUI interaction and crash/power-loss behavior remain unverified. Concurrent elevated source-script modification by an administrator is outside this protection; explicitly running source scripts trusts that source directory.

## User-supplied live run

The October 20, 2026 01:28 local-time log reports a protected snapshot saved successfully, 17 applied tweaks, one failed tweak and no skipped tweaks. The failed operation was the Widgets `AllowNewsAndInterests` registry write, which Windows denied. This is the [documented Widgets policy target](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests#allownewsandinterests); the denial alone does not establish whether device management, key permissions or another protection caused it. No permission bypass was attempted.

The run recorded 7208 MB used before and 7245 MB after, an increase of 37 MB. It therefore shows no immediate RAM reduction. Successful command returns do not establish measured memory savings or acceptance of every policy by its target application. No independent elevated readback or Undo was performed for this run. The progress XML visible in the submitted log is corrected by the subsequent local rebuild.

## RAM findings (local read-only observation)

On the inspected 8064 MB Windows 11 HDD system, four readings over roughly 31 seconds showed 86.6-87.6% physical usage, 999-1080 MB available, and 866-894 MB on standby. Standby is already included in available memory. Commit was approximately 7.8-8.0 GB against a 20.4 GB limit. Paged/nonpaged pools were stable in this short sample. Paging reads were zero for three readings, with one burst at the last reading. This does not establish a long-term leak or identify the cause of a slowdown.

The largest grouped working sets were ChatGPT (~1875 MB), Windows service hosts (~955 MB), Antigravity (~769 MB), Node (~730 MB), the language server (~551 MB) and Codex (~440 MB). Working sets share pages; their sum is not an exact physical RAM breakdown. Private commit is also not resident RAM. A Memory Compression process was present; detailed MMAgent settings could not be read with this token.

There is no verified multi-gigabyte pool of unused RAM to reclaim while leaving every app and its background work unchanged. Windows can reuse standby automatically. Disabling or restarting arbitrary services, forcing app pages to disk, or killing unknown runtimes would violate the requested boundary and may hurt HDD responsiveness. No such action was taken. Background-work settings can be reviewed individually later; the sample does not justify changing them automatically. Additional physical RAM is the direct capacity solution if all current workloads must remain active.

References: [Microsoft memory metrics](https://learn.microsoft.com/en-us/windows/win32/memory/memory-performance-information), [available and standby memory](https://learn.microsoft.com/en-us/windows-hardware/test/assessments/results-for-the-memory-footprint-assessment), [working sets](https://learn.microsoft.com/en-us/windows/win32/memory/working-set).
