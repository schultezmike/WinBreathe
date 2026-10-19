# Security Policy

## Security Architecture

WinBreathe requires Administrator privileges to configure machine-wide Group Policy registry keys (`HKLM:\SOFTWARE\Policies\...`), Windows Services, `MMAgent` kernel memory settings, and pagefile parameters.

To prevent Local Privilege Escalation (LPE) when the optional **Windows Update Persistence Guard** (`WinBreathe_UpdateGuard`) is installed:
1. **Isolated Execution Path**: The scheduled task executes a copy of the engine stored inside `%ProgramData%\WinBreathe\src\`, never from a user-writable download or workspace folder.
2. **Locale-Independent SID ACLs**: During installation, `Install-WBUpdateGuard` strips inherited permissions on `%ProgramData%\WinBreathe` and grants write access exclusively to `WellKnownSidType::BuiltinAdministratorsSid` (`S-1-5-32-544`) and `WellKnownSidType::LocalSystemSid` (`S-1-5-18`). Standard users (`BuiltinUsersSid`, `S-1-5-32-545`) receive `ReadAndExecute` only.
3. **No Network Activity**: WinBreathe makes zero outbound network requests, collects zero telemetry, and installs no kernel drivers or third-party binaries.

## Reporting a Vulnerability

If you discover a security issue (such as an ACL bypass, command injection, or unintended process termination), please open a private security advisory on GitHub rather than a public issue so a fix can be released promptly.
