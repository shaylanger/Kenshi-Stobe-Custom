# 4080 private memory-summary producer audit (read-only)

Date: 2026-10-14 UTC. Scope: identify the producer for `memory_summary_generate` and a supported suppression boundary. No process was stopped, and no service, game, config, database, or request state was changed. No model/chat call was sent. Prompt, response, and credential fields were not read or emitted.

Route and collector evidence:
- Remote route: approved 4080 isolated i3 (`DESKTOP-NQQPA73` → `DwemerAI4Skyrim3`), explicit route preflight PASS; the wrapper's route guard accepted each body.
- Candidate transport SHA256: `9B2D73B0788D4A9F3A39747ABC96496DF8BCC14EBBB87F9A2EC4475A2CFAA9F8`.
- Existing guarded metadata collector SHA256: `5A2F8A2D7E35101BCF2B2533DAB9E0A7A6A3AAB5ED33EEB2186B0B5F66B69D6B`; Bash syntax PASS. The candidate wrapper's optional `-SelfTest` currently fails because its relative CHAT-007 fixture path resolves to a missing `testing/live-stobe-queue/pending-fixes/...` path. This did not affect the route guard or actual guarded runs.

Producer/process finding:
- No separate `memory_summary_generate` daemon was evidenced. The private backend is the ordinary loopback PHP built-in HTTP server on port 18084, rooted at `/tmp/stobe-standalone4080/site`.
- Process snapshot: PHP server parent PID 31, PPID 12 (`Relay(13)`), cwd `/mnt/c/Windows/system32`, exe `/usr/bin/php8.2`, exe SHA256 `9023792dfe95ec9d2a5c625210c433bec9aa792dfa9b6aa73fab1758c50c1e1d`. Four PHP children PID 39, 41, 42, 43 have PPID 31; PIDs 39 and 42 had cwd at the private site, PIDs 41 and 43 at `/mnt/c/Windows/system32`. PID 39 held the observed established connection to the private 18084 listener; PID 42 had a close-wait connection. All are ordinary PHP server/request processes; the snapshot cannot bind a completed summary event to a particular worker PID.
- A separate Python runtime process PID 30 (PPID 12, cwd `/mnt/c/Windows/system32`, exe `/usr/bin/python3.11`, SHA256 `44e5a74ce34ac8837cfbaa6273a9a2cb7542d7d5495781cc4bf48e7de7abe8ed`) was present, but no process, connection, or source evidence ties it to summary generation.

Source and route mapping:
- `lib/memory_helper_functions.php` SHA256 `f37f7ba74ac5dc72fa12cd9c2cb36f1932531361a9449459900692c32dcd25d9` defines `stobeRegularMemoryGenerateSummaryFromPacked` (line 1080) and `stobeRegularMemoryGenerateIndividualSummary` (line 1687). Their normal batch callers are `stobeRegularMemoryProcessOneGlobalBatch` (line 2153) and `stobeRegularMemoryProcessOneIndividualBatch` (line 2209).
- Automatic path: `service/manager.php` SHA256 `c811b1d55b370d0a9bc4515dab9050296c409d61920c4eff01f8473a39b29e72`, `stobeBackgroundRecordTick` (references at lines 88–89) → `stobeMaybeRunRegularMemoryCycle` in `memory_helper_functions.php` (definition line 2279) → global and individual batch processors (references lines 2294–2295) → summary generators → `memory_summary_generate`.
- Narrowest discovered automatic suppression point is the manager tick/cycle gate (`stobeBackgroundRecordTick` / `stobeMaybeRunRegularMemoryCycle`). A separate manual path remains in `ui/memories.php` SHA256 `89bc01e3aea61b4a5089264a63f3840324c56cfbbc0d75e84ee71c6dd3a9a052`, lines 174–175 → `stobeRunRegularMemorySyncNow` (definition at `memory_helper_functions.php` line 2321).
- No database query or write was made. Static scan of the cycle-body lines found no literal SQL table route; audit metadata proves the event type and usage but does not provide DB table/transaction metadata. The private audit log latest entry was `req_6acfbbaf794a3`, `memory_summary_generate`, Dust Bandit, 2026-10-14 17:29:02 UTC, status `ok`, prompt 1260 / completion 712 / cached 143 tokens.

Next supported action for the separate config-gate owner: gate the automatic manager tick/cycle at the code/config boundary, preserve the explicit manual action as intended, then validate via sanitized request metadata only. This audit made no such change.

## Fresh sanitized metadata refresh

- Captured through official wrapper `tools/automation/remote-bash-stdin-4080.ps1` SHA256 `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354` and guarded collector `packets/4080-readiness-env-fixed-20261014/backend-inference-source-metadata.sh` SHA256 `5A2F8A2D7E35101BCF2B2533DAB9E0A7A6A3AAB5ED33EEB2186B0B5F66B69D6B`; isolated-i3 route PASS.
- Latest completion: `req_6acfc3ec81c95`, `memory_summary_generate`, Captain Khenbish, 2026-10-14 18:04:18 UTC, `ok`, 987 prompt / 514 completion / 3 cached tokens. Previous: `req_6acfc329843a0`, Dust Bandit, 18:01:45 UTC, `ok`, 1403 / 1024 / 3.
- The collector reads `/tmp/stobe-standalone4080/site/log/audit_request.log` and `chat_llm_full_capture.log`, and emits request ID, event/status/NPC/time, and token counts only. It reports completed metadata and does not identify a pending lock holder.
