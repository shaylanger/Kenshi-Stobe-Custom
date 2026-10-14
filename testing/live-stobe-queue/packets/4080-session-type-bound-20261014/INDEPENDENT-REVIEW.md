# Independent diagnostic review

## Final revision review (supersedes earlier body below)

**CLEAR** for one corrected setup diagnostic, subject to coordinator/Validator clearance and sandbox enforcement. Exact body SHA256: `32F77C786C112C51CF11D2A47891EC14CB76C35B34FC0C8A89D7FC65C5B7EC6D`; transport remains `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354`.

The reviewer independently ran the permanent pure wrapper assertion extraction over the complete body: `RESULT PACKET-ROUTE-GUARD PASS complete exact wrapper assertion; no transport invoked`. Independently ran the synthetic Python driver tests: three tests PASS. These execute no SSH/WSL/backend calls. Inspection confirms the exact required preamble, valid stdin PHP execution, MSYS conversion suppression, fixed private listener/root and reflected retention-source hash binding remain.

The extra shell source of `env.sh` is removed. Python reads that file as data, handles the provisioning recipe's multiple exported assignments with `shlex`, accepts only the five named STOBE database keys, rejects selected substitutions/control bytes/duplicate selected keys, and never evaluates unknown settings. Required key names and the optional password agree with `pending-fixes/basic-ingame-smoke/standalone4080-provision.sh` and `pending-fixes/chat005-5090-provenance/current-archive-baseline/lib/playthrough_preferences.php`. Those references identify the existing private setup; they are not proof of current runtime settings until this diagnostic reads the actual private file. No parsed values are printed. The child receives the selected database variables through an explicit sudo preserve list and has a 20-second timeout.

This environment preservation deliberately changes the earlier reader's execution environment. `query_ok` can establish that this corrected diagnostic reads the session; it cannot establish that the original reader worked or prove original failure provenance by itself. `type_error` supplies safe argument types at the failing call; `other_error` remains unresolved. Game readiness and gameplay are still unproven. No remote operation was performed by this reviewer.

The listener/WSL portion still needs the operator's bounded outer timeout. Existing PHP helper internals remain runtime dependencies rather than independently source-audited components in this review.

Verdict: **CLEAR for one diagnostic invocation after coordinator/Validator clearance.** This is a setup diagnosis, not a gameplay test or readiness PASS.

Reviewer: `/root/4080_diagnostic_packet_review`.

- Exact body SHA256: `28523C63F5511D45F0A79056A0FC53DEBB2596C6FC7A70DD6554B6C04C497685`.
- Exact transport SHA256: `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354`.
- Body: `testing/live-stobe-queue/packets/4080-session-type-bound-20261014/body.sh`.

The requested outcome is recovery of real Stobe NPC validation on the 4080. Diagnosing the observed session-reader PHP failure directly supports that priority. This packet does not authorize unrelated FP/PG work, game input, source installation, service restart, shared service access, or configuration/ACL changes.

The final body now matches the pinned wrapper's exact exported i3 preamble. The wrapper inserts readonly instance variables after sourcing `rig-env.sh`. The earlier readonly-first draft would have been rejected before execution and is superseded. WSL execution disables MSYS path conversion; PHP reads its script from stdin without the invalid filename `-`.

The Linux socket check targets localhost port 18084, permits multiple legitimate workers sharing its one listener, and requires each owner's exact private PHP server argv. The canonical root is fixed. Reflection binds the hash to the actual loaded `ptr_query` source at the canonical private retention file, rejecting a symlink at that file. The packet performs the same connection/session read involved in the failed setup; it issues no explicit writes or actor queries. Existing application helper internals are runtime dependencies, not independently source-audited by this review.

PHP output and errors are buffered/suppressed. Only version, source hash, safe argument types, and fixed result labels leave PHP; no raw session values, tokens, SQL arguments, or stack trace are printed. Unknown exceptions produce `other_error`, which must not be interpreted as diagnosis success. Source/root or transport failure yields setup failure. Runtime behavior remains unverified until the single invocation returns.

The body has no internal wall-clock timeout; the operator must retain a bounded outer tool/process timeout and investigate a stalled call rather than silently retrying it. Standard sandbox escalation remains a separate enforcement decision.

Review consisted of local text and exact hash inspection. No rig was contacted by the reviewer.
