# Security policy

## v2.3.0 monitoring and controlled relief

Memory Watch runs only while the GUI is open or minimized. It does not install persistence, make paging changes or terminate processes. Its two-file numeric journal, growth history, child-output queue and console are bounded. Task output is capped while reading fixed-size chunks, including output with no newline. Raw Windows event XML is parsed with external entities prohibited and a document-size limit. Incident queries read a bounded recent window; unreadable history is marked incomplete. These measures do not establish protection from kernel bugs or resource exhaustion.

Manual RAM Relief and opt-in automatic relief trim only verified idle Search/Widgets hosts in the same user session. A retained native handle checks creation time, executable path, user ownership, CPU use and visible/foreground windows before requesting a working-set trim. Critical commit pressure, kernel concerns, extreme physical shortage and invalid readings defer relief. Cooldowns limit repetition. AI, ABOS, VPN and generic WebView processes are excluded. Trimming is not termination or deallocation, and its benefit can be temporary.

## v2.1.2 preview trust model

The compiled launcher executes only embedded source. Unelevated runs use a fresh per-launch temporary folder with inherited restricted-token permissions. Elevated runs require a trusted Program Files parent and create an administrator/SYSTEM-only runtime. PowerShell is resolved by an absolute system path. Source scripts remain an explicit trust decision: do not run untrusted source elevated.

New SYSTEM Update Guard installation is disabled. Earlier Guard tasks are not automatically changed; users of previous versions should review and explicitly remove them if no longer needed. Generic factory reset is unavailable.

New backups live under `%ProgramFiles%\WinBreathe-State\<user SID>`. Owners, write ACLs and reparse points are checked before use. Undo validates schema, user identity and bounded targets before mutation. Older ProgramData snapshots are preserved but are not automatically trusted. Reports and logs live under the current user's LocalAppData. A protected operation lock prevents overlapping profile/snapshot/Undo writers.

Profile application and Memory Check do not terminate running apps, purge standby memory or force app working-set trimming. Explicit End Selected App remains a separate destructive action with a protected-name list, exact-name matching and ancestry checks that fail closed when incomplete or protected.

No audit can guarantee the absence of vulnerabilities. Elevated Undo acceptance, legacy operating systems and crash recovery remain unverified; see `docs/AUDIT-2.1.1.md`. The agent did not execute a live optimization during the audit; a subsequent user-supplied Windows 11 run is documented separately.

## Supported downloads

Use v2.3.0 for the current monitoring, controlled relief, output/resource bounds and earlier safety fixes described in `docs/RELEASE-2.3.0.md`. Superseded v2 builds lack some of these changes. Version 1.1.0 remains available by request as a legacy release; retention is not a security or compatibility certification. Release checks do not prove crash prevention or the absence of every vulnerability.

## Reporting

Report suspected vulnerabilities privately using GitHub security advisories. Do not include credentials or personal diagnostic reports in public issues.
