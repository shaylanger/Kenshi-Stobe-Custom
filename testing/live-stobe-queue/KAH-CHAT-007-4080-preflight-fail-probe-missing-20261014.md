# KAH-CHAT-007 4080 fresh preflight setup failure — loaded-module probe absent

- Timestamp: 2026-10-14 02:39:22 UTC.
- Outcome: `RESULT KAH-CHAT-007 FAIL setup: isolated i3 route passed, but required loaded-module probe script is absent on the rig.`
- Scope: one parent-authorized, read-only fresh CHAT-007 preflight through the guarded SSH route. No fallback path or retry was attempted.
- Independent exact review: `loaded_module_probe_review3` returned CLEAR for the corrected fail-closed route guard and explicit `ON_DISK_SHA256` semantics.
- Invocation: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\pending-fixes\rig4080-validation\chat007-preflight-once.sh` with elevated read-only execution after the sandbox denied local SSH-config access.
- Local preflight body SHA-256: `7A3EABFF86155AEAB6C64B1FA5DCD4AFD2CDA6966EB2E7F81B8952A90C0A5F0A`.
- Guarded wrapper SHA-256: `4183EFF82B0DF15E77C34DC1FD3A3101ED29334282551314762CB82FE3ECFC31`.
- Fresh isolated i3 route check passed: `RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only`; remote hostname output identified `DESKTOP-NQQPA73`; `instance.txt` reported instance 3.
- The next required gate failed. Remote Windows PowerShell reported: `The argument 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' to the -File parameter does not exist.` The probe produced no process/module markers; exit code was 1. The caller was configured to stop, so installed-hash, backend, session-generation, world, isolation, and actor gates were not reached.
- No KAH actor query, exact-name/handle lookup, chat, input, queue mutation, game launch, focus/window change, or service change occurred. The status supplied by the parent is not treated as a test result. Earlier setup-failure receipts remain unchanged.
- Next step: stop. The exact reviewed loaded-module probe must be present at the expected remote path before a new authorized preflight; no CHAT-007 resolver query is cleared by this receipt.
