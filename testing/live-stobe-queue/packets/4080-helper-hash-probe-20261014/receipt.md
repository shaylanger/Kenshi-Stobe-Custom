# 4080 i3 sanitizer helper hash probe receipt

- Time: 2026-10-14T09:25:43Z
- Scope: one authorized setup probe via 	ools/automation/remote-bash-stdin-4080.ps1; no gameplay, chat, service, or retry.
- Local preflight: all five required SHA256 pins matched exactly (probe, sanitizer, wrapper, rig-env, venc). The wrapper enforced its exact isolated i3 preamble and fixed SSH alias/remote-host gate.
- Result: **FAIL setup**; wrapper exit code 1, sanitized diagnostic READINESS_STDERR captured=true category=permission_denied lines=1.
- Helper presence/hash: unconfirmed; no SANITIZER_HELPER result was returned. The sanitized diagnostic does not identify whether denial occurred at SSH authentication, host command, or Bash body. One-shot is consumed; do not retry without fresh exact review/clearance.
- No gameplay was run; this receipt is setup evidence only.
