# KAH-CHAT-007 — 4080 current-stream preflight setup failure

- Result: **terminal `FAIL setup`**; this was the one cleared preflight attempt. No retry is authorized or was made.
- Observed UTC: 2026-10-14 04:35Z (clock sampled immediately after the command; exact second was not captured).
- Clearance: packet SHA-256 `080D2DCD6A42FBD2D4D81B86667CF6CA5B405F1648F56225A5E18FED9BC092C4` had independent exact-hash CLEAR; parent reported Agent Validator row-specific CLEAR for one read-only isolated-i3 preflight.
- Invocation: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\pending-fixes\rig4080-validation\chat007-session-reader-stream.review.sh`
- Exact pins before call: transport `190AA18D8ACB076F6BB06D208D0BEC6AD83A5A77D8F9B9730759F555F763184F`; body `D2127D7B2B5830D52074C9B4B971C20CC5E46A20AF3CDDF0B6D92DFAA987CFD2`; embedded/current reader `4515AA2ACBF0B0675D757257476BD0581A47C2D4490A42F87E60E58822D6E337`; informational path-based caller `1D10CF267DAD2FC6370A514777F74405BBE38FA703D908893B1CA13AA9FCD3B8` (not used as body); loaded-module probe `121956C2A61A4B59854BB12AC414C788A15B9A599D05680D98F78971D705A31F`.
- Observed tool/caller exit code: `1`.

## Evidence

Passed in the captured output: route PASS on `C:\KenshiInst\3`, inbox clear; host `DESKTOP-NQQPA73`, instance marker 3; PID 3452 at the exact i3 executable; Stobe and AutomationHarness module paths and expected on-disk hashes; config `127.0.0.1:18084`; private backend health/schema. The PHP listener section printed five process rows with the same `php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site` arguments. The presence check passed, but this transcript does not establish a unique listener process.

The terminal transport result was:

```text
RESULT KAH-CHAT-007 FAIL setup: captured read output is incomplete; missing=READY SESSION GENERATION (SANITIZED),KAH WORLD STATUS,KAH GAME TIME / PAUSE STATE,INPUT ISOLATION / FOCUS,FP STATE,FRESH ACTOR LIST (300),CHAT007 PREFLIGHT OUTPUT COMPLETE v1; stderr_captured=true stderr_class=other stderr_lines=2
```

The exact sanitized stderr excerpt available from the transport is only:

```text
stderr_captured=true
stderr_class=other
stderr_lines=2
```

The two raw stderr lines were not exposed by the reviewed sanitizer. Their text and cause are unknown; they are not reconstructed here. The session section emitted no result, so session presence/status/game time/load hash/generation/manager readiness are unverified. World/save/time/pause, isolation/focus, FP/speaker, actor roster, and target identity are also unverified. No resolver/actor-handle query, chat, order, game input, focus/window action, save change, queue change, service change, or game-state mutation occurred. No raw session ID or token was obtained.

## Complete captured transcript

```text
KAH_INSTANCE=3
KENSHI_DIR=/c/KenshiInst/3 (C:\KenshiInst\3)
KDIR=/c/KenshiInst/3 (C:\KenshiInst\3)
KAH_DIR=C:\KenshiInst\3\mods\AutomationHarness
RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only

=== HOST / INSTANCE ===
DESKTOP-NQQPA73
instance=3 synced=2026-10-13T12:00:52 from=C:\Program Files (x86)\Steam\steamapps\common\Kenshi

=== EXACT I3 PROCESS AND LOADED MODULE HASHES ===
PID=3452
PROCESS_PATH_PART=1/1:C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe
LOADED_MODULE=Stobe.dll
MODULE_PATH_PART=1/1:C:\KenshiInst\3\mods\Stobe\Stobe.dll
ON_DISK_SHA256=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C
LOADED_MODULE=AutomationHarness.dll
MODULE_PATH_PART=1/2:C:\KenshiInst\3\mods\AutomationHarness\Automa
MODULE_PATH_PART=2/2:tionHarness.dll
ON_DISK_SHA256=974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D

=== ON-DISK MOD HASHES ===
aef84c0a682df036eb2cd0dc30a809e52e19956933f142c3a1d5877c4eb1907c */c/KenshiInst/3/mods/Stobe/Stobe.dll
974dba03f136d6cb08153f29acc497c485c39baeceb8bf50c8b5291661d3025d */c/KenshiInst/3/mods/AutomationHarness/AutomationHarness.dll

=== INSTANCE CONFIG ===
ServerHost=127.0.0.1
ServerPort=18084
ServerHost=127.0.0.1
ServerPort=18084

=== PRIVATE BACKEND HEALTH ===
{"ok":true,"status":"ok","service":"StobeServer","database":true,"database_encoding":"UTF8","database_encoding_supported":true,"database_schema_ready":true,"database_upgrade_required":false,"database_repair_command":"sudo php /var/www/html/StobeServer/debug/run_db_updates.php","timestamp":1791952479,"database_missing":[]}

=== PRIVATE BACKEND PROCESS ===
     31 php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site
     39 php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site
     41 php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site
     42 php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site
     43 php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site
RESULT KAH-CHAT-007 FAIL setup: captured read output is incomplete; missing=READY SESSION GENERATION (SANITIZED),KAH WORLD STATUS,KAH GAME TIME / PAUSE STATE,INPUT ISOLATION / FOCUS,FP STATE,FRESH ACTOR LIST (300),CHAT007 PREFLIGHT OUTPUT COMPLETE v1; stderr_captured=true stderr_class=other stderr_lines=2

```

This is the sole attempt's captured output; the terminal result is setup failure, not a gameplay result. Preserve earlier receipts unchanged. Any future attempt needs fresh row-specific clearance and must diagnose the incomplete session section first.
