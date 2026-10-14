# KAH-CHAT-007 — 4080 isolated i3 route setup failure

- Result: `FAIL setup`
- Observed UTC: 2026-10-14 01:57:29
- Attempt: one elevated read-only invocation through `tools/automation/remote-bash-stdin-4080.ps1`; the wrapper was not modified or bypassed.
- Observed: remote host identity printed `DESKTOP-NQQPA73`. The body then stopped at `rig4080_i3_preflight`: `/mnt/c/Program Files/Git/usr/bin/bash: line 9: rig4080_i3_preflight: command not found` (exit 127).
- Consequence: `stobe-auto status`, the exact CIM process query, WSL session/generation/manager-ready query, and actor/position reads did not run. Instance-3 route preflight therefore did not pass; process/world/session/build/actor gates remain unverified.
- Decision: stop this row. No retry, KAH resolver query, chat, game input, focus change, or other game action. No queue or waker data changed.
- Redaction: no session values, tokens, or actor identities were read or recorded.
- Read-only session helper SHA256: `CAE177182348D0EA9F0386CEBECBA947CD4F22168143554E7DD1AE4D099C55B6`.
- Guarded SSH wrapper SHA256 (unchanged): `4183EFF82B0DF15E77C34DC1FD3A3101ED29334282551314762CB82FE3ECFC31`.
- Prior transport access failure receipt: `testing/live-stobe-queue/KAH-CHAT-007-4080-session-read-setup-fail-20261014.receipt.md` SHA256 `DEA4AB105ACC41822B02F2E4A9BD79635FC4C670969F43C84AE84F3608046FCF`.
- Next: investigate why the documented 4080 Git Bash route does not define `rig4080_i3_preflight`; obtain fresh setup clearance before resuming the row.
