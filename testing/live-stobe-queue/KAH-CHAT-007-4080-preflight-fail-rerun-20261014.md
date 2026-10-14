# KAH-CHAT-007 4080 fresh preflight setup failure

- Timestamp: 2026-10-14 02:35:36 UTC.
- Outcome: `RESULT KAH-CHAT-007 FAIL setup: trusted SSH config access denied before SSH; no remote preflight gates could be read.`
- Scope: one fresh attempt at the exact authorized read-only CHAT-007 preflight on isolated 4080 i3. No fallback route or retry was attempted.
- Independent exact review: `loaded_module_probe_review3` returned CLEAR for the corrected fail-closed guard and on-disk hash labeling before this attempt.
- Invocation: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\pending-fixes\rig4080-validation\chat007-preflight-once.sh`.
- Local preflight body SHA-256: `7A3EABFF86155AEAB6C64B1FA5DCD4AFD2CDA6966EB2E7F81B8952A90C0A5F0A`.
- Guarded wrapper SHA-256: `4183EFF82B0DF15E77C34DC1FD3A3101ED29334282551314762CB82FE3ECFC31`.
- The wrapper failed at its local `Test-Path` check for `C:\Users\Shay\.ssh\config` with `Access is denied` / `ItemExistsUnauthorizedAccessException`, exit code 1. It did not start `ssh.exe`; no remote command was sent.
- Therefore no fresh rig process, loaded-module, installed DLL, backend, session-generation, world, isolation, speaker, or actor/target evidence was obtained. The rig's current state remains unknown from this attempt.
- No `stobe-auto` query, chat, input, queue mutation, game launch, focus/window change, or service change occurred. Prior setup-failure receipts were preserved unchanged.
- Next step: stop. Do not retry via another SSH config, alternate route, or privilege escalation under this clearance. A future attempt requires the trusted route to become readable and a fresh authorized preflight.
