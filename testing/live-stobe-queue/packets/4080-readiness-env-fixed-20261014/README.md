# Isolated 4080 corrected readiness transport

This candidate repairs the demonstrated missing DB environment preservation in the old sanitized session reader. Successful corrected diagnostic query is recorded in `testing/live-stobe-queue/KAH-CHAT-007-4080-corrected-db-diagnostic-20261014.receipt.md`. It does not change server PHP, services, config, ACLs, routes, saves, or game state.

`body.sh` SHA256 `DEBE1258C549EB4598EEDD5D01647F3912C710B386023BF4F9499538519132F8` embeds the exact `chat007-session-read-once.py`. It is generated from the pinned existing stream using `build-candidate.py`, with a strict listener argv/private root guard before the session query. The reader parses allowlisted DB assignments without evaluating shell, preserves only those keys to sudo PHP, keeps the existing sanitized session result allowlist, and has a 20-second child timeout. World/status/time/isolation/FP/roster reads remain bounded as before.

`remote-bash-stdin-4080.candidate.ps1` SHA256 `9B2D73B0788D4A9F3A39747ABC96496DF8BCC14EBBB87F9A2EC4475A2CFAA9F8` differs from the canonical wrapper only by receiver `$ProgressPreference='SilentlyContinue'` and a focused self-test assertion. Meaningful stdout/stderr and exit handling are preserved. Full wrapper self-test passed with identical bytes temporarily placed beside canonical wrapper for fixture resolution; that temporary copy was removed. No canonical wrapper replacement is required for invoking the candidate with BodyPath.

Local tests: seven reader regression tests passed; full exact body passed candidate Assert-IsolatedI3Body extracted via PowerShell AST. Independent review pending at authoring time. Only after technical CLEAR, run one bounded corrected preflight via standard escalation and default SSH config:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\KenshiModding\testing\live-stobe-queue\packets\4080-readiness-env-fixed-20261014\remote-bash-stdin-4080.candidate.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-readiness-env-fixed-20261014\body.sh
```

Readiness success is not gameplay PASS. Inspect fresh save/world, advancing/unpaused game, session readiness and generation match, loaded/on-disk hashes, private backend schema/config, isolation, speaker, and roster before running the separate exact reviewed actor lookup comparison. If incomplete or failed, record FAIL setup with the observed cause and recover it rather than counting the row as tested.

## Live outcomes and command compatibility

Corrected session read and receiver progress suppression were validated live. The game was initially on its menu, so existing copied save `kah-stobe-4080-standalone-active` was loaded once. A45-second observation timeout saw loading; re-polling the same load confirmed world/unpaused. Full metadata stream then exceeded120seconds with no partial output; its owned local SSH/wrapper were stopped and bounded receiver capture is under repair. Split native/readiness/config sections completed in1–3seconds.

On installed Harness SHA `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`, bare `state <npc>` is unsupported. Query current `help`; native life/health uses `hp <npc>`, actor identity/position uses `where <npc>`, and Stobe-specific state uses `stobe_state <npc>`. Do not infer supported verbs from newer docs or broad FP `state` descriptions.

The first resolver body stopped as FAIL setup on unsupported `state`; exact reviewed v2 uses `hp` then both original name/serial `where` queries. It passed with living Cind#2529907200/2 at identical coordinates. See `testing/live-stobe-queue/KAH-CHAT-007-4080-native-resolver-pass-20261014.receipt.md`. This is a completed native resolver regression only, not a travel test.
