# KAH-CHAT-007 single escalated readiness retry

- Owner: `/root/4080_escalated_preflight_operator`
- Observed: 2026-10-14T10:00:32-06:00; command completed about 15 seconds earlier.
- Scope: one reviewed read-only stream preflight, standard sandbox escalation, default SSH config unchanged. No fallback or further invocation.
- Wrapper SHA256: `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354`
- Body SHA256: `D2127D7B2B5830D52074C9B4B971C20CC5E46A20AF3CDDF0B6D92DFAA987CFD2`
- Command: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\pending-fixes\rig4080-validation\chat007-session-reader-stream.review.sh`
- Result: exit 1, `RESULT KAH-CHAT-007 FAIL setup: remote read body exited with code 255`.

Fresh evidence before stop:

- `RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only`
- Host `DESKTOP-NQQPA73`, instance 3.
- Live PID `3452`, process `C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe`.
- Loaded Stobe path `C:\KenshiInst\3\mods\Stobe\Stobe.dll`; on-disk SHA `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`.
- Loaded Harness path `C:\KenshiInst\3\mods\AutomationHarness\AutomationHarness.dll`; on-disk SHA `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- Instance config reports localhost port `18084`.
- Private health response: `ok=true`, `database=true`, schema ready, no upgrade required or missing database entries; backend timestamp `1791993617`.
- Backend processes 31/39/41/42/43: `php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site`.
- Session reader: `{"exit_code":255,"failure_kind":"subprocess_failed","result":"FAIL","stderr_captured":true,"stderr_class":"php_error","stderr_line_count":8}`.
- Outer stderr summary is CLIXML progress, class `other`; it does not reveal the underlying eight PHP diagnostic lines.

SSH config access worked under escalation. Next blocker is the session-reader PHP subprocess. World, pause/time, isolation/focus, and roster sections were not reached and remain unknown. No game inputs, actor queries, chat, service/config/ACL/save changes or gameplay test occurred. Next action: delegate a narrowly reviewed diagnostic for the sanitized session-reader failure; do not infer readiness or PASS.
