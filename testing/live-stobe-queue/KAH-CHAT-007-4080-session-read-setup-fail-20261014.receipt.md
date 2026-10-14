# KAH-CHAT-007 — 4080 isolated i3 setup failure

- Result: `FAIL setup`
- Observed UTC: 2026-10-14 01:46:25
- Scope: direct WSL session/generation/manager-ready read only; no KAH command, game action, focus change, or input was issued.
- Failure: local OpenSSH could not open the configured `C:\Users\Shay\.ssh\config` (`Permission denied`). Both invocation attempts exited 255 before connecting; a local `Test-Path` check also returned access denied. No remote WSL/PHP command ran, so route, process/world, session generation, manager readiness, and actor identity remain unverified.
- Decision: stop this row at setup. No unchanged retry. Do not infer current state from the previously recorded PID or manifests.
- Redaction: no session values, tokens, or actor identities were read or recorded.
- Read-only helper source SHA256: `CAE177182348D0EA9F0386CEBECBA947CD4F22168143554E7DD1AE4D099C55B6`.
- Immutable row emitter SHA256: `1CD9FC1F3303E60E51B6D2DA3139959EE6E976202B952BE8C58AE469013243EC`.
- Guarded SSH wrapper SHA256 (unchanged): `4183EFF82B0DF15E77C34DC1FD3A3101ED29334282551314762CB82FE3ECFC31`.
- Next: resolve authorized read access to the configured 4080 transport, then obtain a fresh validator-cleared setup before any continuation.
