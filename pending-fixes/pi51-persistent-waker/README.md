# PI-51 persistent waker: built, awaiting swap

Replaces "wake, read output, restart waker" by ONE daemon that appends actionable events to a file the coordinator watches with the Monitor tool.

## What is new (all committed, nothing live changed yet)
- `tools/automation/waker-persist.sh` (WSL): `watch | start | status | set-batch <dir|none> | stop`. Loops the UNCHANGED `event-wait.sh` (all detection/digest/quiet filter/backstop stay there), appends each event as `<iso time> EVENT ...` to `C:\KenshiTestRuns\waker\events.log` (digest items folded into one line; a clean backstop goes to `waker\quiet.log`). Heartbeat `waker\coordinator.hb` rewritten every 2 s by the daemon loop; single instance by `flock waker\coordinator.lock` + pidfile; refuses to start while a stand-alone `event-wait.sh` runs (two wakers would eat each other's inbox messages; `WP_FORCE=1` overrides); ends after 12 h (`WP_MAX_HOURS`) or `stop`.
- `tools/automation/hooks/kenshi-waker-guard.ps1.candidate` (CRLF, parses clean): the live hook plus (1) `Get-PersistWaker`: Stop hook accepts the persistent waker when `waker\<me>.hb` (`me` = `$env:KAH_WAKER_ME` or `coordinator`) has `epoch=` younger than 150 s; every old process check (sleep>=30, batch-health, rig-health, lane-waker, event-wait under this session) is unchanged, the heartbeat is only an extra OR; `KAH_GUARD_TEST_NO_WAKER` still forces the block; new selftest switch `KAH_GUARD_TEST_NO_PROCWAKER`; (2) PreToolUse denies starting a second `bash ...event-wait.sh` while the heartbeat is fresh (exempt: command contains `KAH_RUNS=`; with a stale/no heartbeat it is allowed as before); sleep>120 / `timeout /t` / ScheduleWakeup>120 denial untouched; (3) `$WAKER` advice text keeps the old text (an existing selftest asserts it) and appends the persistent command.
- Selftests: `tools/automation/waker-persist-selftest.sh` (WSL, 25 checks incl. one real `event-wait.sh` run) and `tools/automation/waker-persist-hook-selftest.ps1` (28 checks on the candidate; `-Legacy -Guard hooks\kenshi-waker-guard.ps1` = 11 checks proving the live hook does not know the heartbeat, everything else identical).
- Verification vs the existing hook selftests (agent-guard, agent-session-hooks, agent-successor, alert-ledger, stobe-auto-guard, tail-close, tail-hooks, waker-lanes): run from a relocated copy (`Z:\KenshiModding\...` via subst) once with the candidate and once with the live hook as control: results IDENTICAL (agent-guard 80/80, alert-ledger, stobe-auto, waker-lanes pass; the failures in agent-session-hooks meter cases, agent-successor, tail-close, tail-hooks meter cases occur identically with the live hook, i.e. relocation/state artifacts, not the candidate).

## Swap steps (coordinator, at a quiet moment; hooks run on every call)
1. Hook swap (PowerShell, atomic-ish):
   `Copy-Item C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1 C:\KenshiTestRuns\backup\kenshi-waker-guard.ps1.pre-pi51 -Force; Copy-Item C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1.candidate C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1.new; Move-Item -Force C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1.new C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1`
   Then run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\waker-persist-hook-selftest.ps1` (expect 0 fail) and `waker-lanes-selftest.ps1`. `.claude/settings.json` needs no change (same hook file, same args).
2. The live legacy waker (`event-wait.sh`) must be gone before the daemon starts: let it end on its next wake, or `wsl.exe -d DwemerAI4Skyrim3 -u root -- pkill -f 'bash .*event-wait.sh'`, and keep `touch C:\KenshiTestRuns\inflight\<x>` markers as they are (the Stop hook blocks in the gap, so do steps 2+3 in one turn).
3. Start the ONE watcher with the Monitor tool (persistent), command:
   `MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/waker-persist.sh watch [--batch /mnt/c/<out-dir>]`
   Each new line in `events.log` is one notification. Re-running `watch` is harmless (never a second daemon; it only re-attaches the tail). Batch change without restart: `... waker-persist.sh set-batch /mnt/c/<out-dir>` (or `none`). Status: `... waker-persist.sh status`. Stop: `... waker-persist.sh stop`.
4. Check: `status` prints RUNNING; `C:\KenshiTestRuns\waker\coordinator.hb` is < 5 s old; try a Stop with work in flight: no "no waker is running" block. Kill test: `stop`, wait 150 s (or delete the hb) and the Stop hook blocks again.
5. Docs (coordinator edits): CLAUDE.md "Batches and wakers" / "Waker guard" bullets and `testing/AGENT_PROMPTS.md` standard block: replace "run event-wait.sh in the background and restart it each time it wakes you" by the Monitor command above; keep event-wait.sh as the engine. `session-start.ps1` WAKER STATUS line could additionally print `waker-persist.sh status` (optional).

## Rollback
`Copy-Item C:\KenshiTestRuns\backup\kenshi-waker-guard.ps1.pre-pi51 C:\KenshiModding\tools\automation\hooks\kenshi-waker-guard.ps1 -Force`; `waker-persist.sh stop`; start `event-wait.sh` the old way.

## Known limits
- The daemon is detached (setsid). It lives as long as the WSL VM does (the Monitor's wsl.exe session keeps it up). If WSL shuts down, the heartbeat goes stale within 150 s and the Stop hook blocks as before: re-run `watch`.
- A hard-killed daemon leaves its last heartbeat; the hook keeps accepting it for up to 150 s.
- Status files rewritten in the ~0.1 s between two inner waits are not seen by the inner wait; the 10-min backstop sweep covers them (legacy had the same gap, but a manual one of tens of seconds).
- Tail sessions keep `tail-wait.ps1` (unchanged). Other sessions can use `--me <name>` and `KAH_WAKER_ME=<name>`; events then go to `events-<name>.log`.
- The Stop hook cannot see the WSL pid from Windows; "pid alive" is proven by the fresh heartbeat, which only the daemon loop writes.
