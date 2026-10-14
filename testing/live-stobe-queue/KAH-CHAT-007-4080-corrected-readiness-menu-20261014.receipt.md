# Corrected 4080 readiness: game menu blocker

Exact independently reviewed body `DEBE1258C549EB4598EEDD5D01647F3912C710B386023BF4F9499538519132F8` and wrapper candidate `9B2D73B0788D4A9F3A39747ABC96496DF8BCC14EBBB87F9A2EC4475A2CFAA9F8` executed once via standard escalation/default SSH config. Exit 1 in 3.154 seconds. This is FAIL setup, not a gameplay result.

Passed: route instance3 inbox clear, host DESKTOP-NQQPA73, PID3452 exact `C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe`; loaded module paths/on-disk Stobe `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`, Harness `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`; Stobe config127.0.0.1:18084, backend health/schema true, guarded fixed private listener/root.

Corrected environment reader returned clean JSON, without CLIXML contamination:

```json
{"gamets":122513,"generation_present":true,"load_id_sha256":"4e07408562bedb8b60ce05c1decfe3ad16b72230967de01f640b7e4729b49fce","manager_ready_matches":true,"session_present":true,"status":"ready"}
```

Actual native state then contradicted readiness for gameplay:

```text
phase=menu save=newgame:Empire Citizen last_saved=kah-stobe-4080-standalone-active paused=0 speed=1.0
ERROR: no game loaded (phase=menu)
```

Stopped before input isolation, FP, roster or actor queries. The DB environment and progress formatting fixes now have live proof, but backend ready alone does not prove game readiness. Next action: review and load the existing documented copied test fixture through KAH on instance3, bounded wait-world, then rerun fresh complete readiness before any test.

Local test reproducibility caveat: wrapper candidate self-test fixture lookup uses script location. Its full self-test passed from identical temporary bytes beside canonical wrapper; direct packet-path -SelfTest cannot find that fixture. Canonical wrapper was not modified or installed.
