# KAH-CHAT-005 captured-wrapper preflight failure

- Time: 2026-10-14 00:37 UTC (approx.; tool call began after the helper review was reported CLEAR).
- Scope: fresh read-only 5090 preflight before the already-cleared ASCII Sho-Battai invitation. No chat was sent.
- Helper: `tools/automation/invoke-wsl-captured.ps1`, SHA-256 at the outer PowerShell hash guard: `26D49B29B9294D031BBB182B26671B79430C7BCE9E38D83DFE8F070837AA19DC`.
- Review: `pending-fixes/stobe-chat-transport-empty-stdout-20261014/INDEPENDENT-REVIEW.md`, SHA-256 `BE42C4ED74C1D7D9CC7E0CD590CC3BD1930AD75E6520786A948D625CBF8D0F0A`.
- Process preflight passed: PID 86884 was responsive at `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\kenshi_x64.exe`; loaded Stobe SHA-256 `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`; loaded AutomationHarness SHA-256 `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- Exact invocation shape: elevated PowerShell hash-checked the helper and review, wrote a UTF-8 temporary Bash body, then invoked `& $helper -BashBodyPath $tmp`. The temporary filename was not printed and was removed by `finally`.
- Intended body was read-only: set `KAH_INSTANCE=1`, source `tools/automation/rig-env.sh`, query backend health, KAH status and input isolation, Stobe ping, nearby characters, exact Beak and Dealer location/state, and Sho-Battai lookup.
- Observed failure: the nested helper failed in PowerShell parsing at line 94 around the Unicode self-test string (`$unicodeBody = 'printf ... "you’d"' + ...`), reporting `ParserError` and `Unexpected token 'd"' + "`n"`. This occurred before `wsl.exe` ran; none of the intended Bash/KAH queries executed.
- Classification: `FAIL setup/tooling`. No WSL/KAH request, `TEST_INBOX`, or chat dispatch occurred. Do not retry until the parser issue is fixed, the candidate is self-tested and exact-hash reviewed, and a fresh preflight passes.
