# WinBreathe v2.1.2 - Security and reliability update (preview)

This release replaces earlier v2 downloads and includes the fixes tested in the local-only v2.1.1 preview. Version 1.1.0 remains available as a legacy release. Earlier v2 Git tags and source history are retained; their downloadable releases are retired.

## What's new

- **Readable task output:** removed raw PowerShell progress XML, retained real errors and warnings, and prevented the GUI from waiting on redirected output pipes.
- **Honest results:** failed tweaks are counted separately, partial runs show a warning, and unsuccessful operations return an error code. If RAM did not fall, the summary says so. An applied setting is not a measured memory saving.
- **Safer previews:** `-WhatIf` also blocks Undo, snapshot, report, Guard and other alternate actions. Unknown tweak IDs and conflicting actions are rejected.
- **Protected launch and backups:** executables use embedded source, fresh runtime folders and the Windows system PowerShell path. Elevated runtime folders and new snapshots require trusted ownership and permissions.
- **Bounded Undo:** restore validates the snapshot schema, user identity, registry targets and services before making changes. Original registry types and raw expandable strings are preserved. A shared operation lock prevents overlapping profile, snapshot and Undo writers.
- **Open apps stay open:** profile application no longer kills Search, Widgets or WebView2 hosts. Memory Check only reads memory. Process wildcards cannot bypass the explicit termination protection list.
- **Safer available features:** new Update Guard installation and generic factory reset are disabled pending reliable implementations. Existing Guard removal remains explicit. Pagefile and legacy performance changes remain opt-in.
- **Consistent packaging:** updated version labels, batch-menu descriptions, portable source, SHA-256 checksums and source manifest. Publishing requires regression, catalog, build, launcher and package checks.

## Upgrading

Close WinBreathe before replacing its executable. Download the executable or portable ZIP from this release. Compare its SHA-256 hash with `SHA256SUMS.txt` before running it. For machine-wide changes, run as administrator and review the preview first.

New snapshots are stored under `%ProgramFiles%\WinBreathe-State\<user SID>`. Older ProgramData backups remain untouched but are not automatically trusted for Undo; keep them for manual review. Upgrading does not reset existing Windows settings or silently remove an older Guard task.

## Known limits

- Windows may deny individual policy writes, including Widgets. WinBreathe reports the failure and does not take ownership or weaken permissions to force the change. Other successfully applied settings remain in place.
- There is no guaranteed RAM reduction, speed increase or target usage percentage. Current app workloads can keep memory use high. The submitted Windows 11 run used 7208 MB before and 7245 MB after.
- Windows 7 SP1 and Windows 8.1 paths remain experimental. They require Windows PowerShell 5.1 and a compatible .NET Framework. Target-OS runtime and performance testing is incomplete.
- Elevated Undo, full GUI interaction and crash/power-loss recovery still need disposable-machine acceptance tests. The executable is not code-signed.

## Validation

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Release.ps1 -Build` from the repository or portable source package. This runs compatibility, reporting, snapshot-file, security and catalog regressions, syntax/encoding checks, compilation, compiled-launcher checks and archive/checksum validation. These checks do not apply system tweaks.

The source manifest records exact packaged source hashes, the source revision and whether the source tree was dirty before building. GitHub tag builds must use a clean checkout of the tagged commit. Release assets are published from that tested build.

See the [changelog](../CHANGELOG.md) and [audit notes](AUDIT-2.1.1.md) for details.
