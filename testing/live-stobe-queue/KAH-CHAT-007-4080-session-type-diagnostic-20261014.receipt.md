# 4080 session diagnostic execution receipt

Owner: `/root/4080_session_diagnostic_operator`.
Date: 2026-10-14. Classification: **FAIL setup; stopped locally before host contact**.

Exactly one approved invocation was attempted using standard sandbox escalation, unchanged default SSH configuration and a hidden owned PowerShell process with a 110-second outer deadline. No retry, route override, config/ACL edit, input, source mutation, install or service action occurred.

- Body: `testing/live-stobe-queue/packets/4080-session-type-bound-20261014/body.sh`, SHA256 `28523C63F5511D45F0A79056A0FC53DEBB2596C6FC7A70DD6554B6C04C497685`.
- Wrapper: `tools/automation/remote-bash-stdin-4080.ps1`, SHA256 `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354`.
- Both pins verified immediately before invocation; independent review and latest Validator exact-action CLEAR read.
- Invocation: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-session-type-bound-20261014\body.sh`.
- Process exit: 1 after approximately 0.335 seconds. Outer timeout did not fire.
- Stdout: empty. Stderr: 514 bytes, only local wrapper rejection/PowerShell error formatting.

`RESULT KAH-CHAT-007 FAIL setup: exact diagnostic body rejected locally by Assert-IsolatedI3Body; no SSH or PHP execution`

Observed error: `Refusing remote body that could override or unset isolated-i3 routing`, wrapper line 360.

Local inspection identifies the rejected construct inside the quoted WSL command: `. /tmp/stobe-standalone4080/env.sh >/dev/null 2>&1`. The pinned wrapper forbids an additional source/dot command after trusted rig-env setup, including this quoted command. This invalidates prior review's execution-readiness assessment; it is not evidence about private PHP or session state.

Next step: author a locally compatible diagnostic candidate without weakening the wrapper routing guard, independently review its exact bytes and obtain new exact-action clearance before any remote invocation. This receipt is not gameplay evidence or a readiness PASS.

Local raw outputs (sanitized local-only wrapper failure): packet `execution.stdout.txt` and `execution.stderr.txt`.
