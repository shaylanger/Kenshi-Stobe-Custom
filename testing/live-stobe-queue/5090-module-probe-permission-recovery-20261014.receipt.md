# 5090 module probe permission recovery

Owner: `/root/operator_5090_recover`. Scope: Agent Validator cleared one read-only exact module probe, then one same-command retry using `require_escalated` after access denial. No KAH, inbox, input, game launch, service, save, queue, or chat action.

Exact command: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\loaded-module-probe.ps1 -ExpectedExecutablePath D:\Steam\steamapps\common\Kenshi\RE_Kenshi\kenshi_x64.exe`.

Helper SHA256: `121956C2A61A4B59854BB12AC414C788A15B9A599D05680D98F78971D705A31F`.

First restricted-shell attempt: exit 1, `MODULE_GATE_FAIL name=enumeration error=Access denied`.

Authorized same-command elevated retry: exit 0. PID `86884`; executable `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\kenshi_x64.exe`.

| Loaded module path | File-at-loaded-path SHA256 |
|---|---|
| `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` | `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C` |
| `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\AutomationHarness.dll` | `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D` |

These are module enumeration plus on-disk hashes, not mapped-memory hashes. This result establishes the restricted-shell permission barrier for this probe. It does not prove the separate historical WSL denial has the same cause, session readiness, world/save identity, or an active in-game test.

Next: independently review the local one-shot sanitized 5090 reader/body, obtain fresh clearance for an elevated captured-WSL read-only diagnostic, then establish the row-specific gameplay gates.
