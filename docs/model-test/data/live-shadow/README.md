# Live coordinator shadow kit (stage 2 of docs/COORD_SHADOW_PLAN.md)

Code: C:\KenshiModding\tools\automation\shadow\ (shadow_feed.py, shadow-wait.sh, shadow-say.sh, shadow_validate.py, shadow_selftest.py) and the read-only guard hook tools\automation\hooks\shadow-readonly-guard.py (registered in .claude\settings.json as a PreToolUse "*" entry; a no-op unless the calling subagent's spawn description contains [shadow:H] or [shadow:S]).
Runtime: this folder. Selftest: `python -I C:\KenshiModding\tools\automation\shadow\shadow_selftest.py` (uses a temp dir).

## Start (coordinator does this, both arms at the same moment, same message)
Feeder must be running first (pid in feeder.pid; log feeder.log; started detached by the kit). Then two Agent calls in ONE message:
1. description: `[case:bench] [model:haiku] [effort:high] [shadow:H] shadow coordinator H`
   prompt: `Read C:\KenshiTestRuns\shadow\bootstrap.md and follow it as arm H.`
   (run_in_background: true)
2. description: `[case:bench] [model:sonnet] [effort:high] [shadow:S] shadow coordinator S`
   prompt: `Read C:\KenshiTestRuns\shadow\bootstrap.md and follow it as arm S.`
   (run_in_background: true)
The shadows are long subagents: they loop shadow-wait -> shadow-say until the feeder writes END (100 min after feeder start, or when you create the file STOP in this folder), then hand back. Do not message them.

## Files
- feed.jsonl: batches {batch_id, ts, events:[{id, kind, ts, text<=3000}]} + final {"end":true}. Kinds: tool_result, task_notification, peer_message, subagent_handback, user_message, stop_hook_feedback, hook_context, meta_message, user_other. New batch after 20 s quiet or 8 events (or 45 s age).
- real-actions.jsonl: the real coordinator's own tool calls (kind tool_use, name, input JSON) and text turns, with transcript timestamps (for the blind comparison).
- ledger-H.jsonl / ledger-S.jsonl: one line per decision: ts, arm, batch_id, event_ids, class, actions[{type, exact_command_or_message, why, validator{ok,errors,warnings}}], latency_s_from_batch, validator_errors.
- cursor-H.txt / cursor-S.txt: last batch each arm has been shown. guard.log: denied tool calls of shadows (a nonzero count is a finding). guard.log.trace: every subagent tool call the guard saw (proof the hook fires; capped 300 KB).
- feeder.pid, feeder.log, feeder.state.json, END (written at the end).

## Audit after the run (read-only detection of any write, belt and braces)
`python -I C:\KenshiModding\tools\automation\shadow\shadow_audit.py snapshot` before the spawn and `... check` after: compares `git status --short` of tools/ docs/ testing/ pending-fixes/ and mtimes under C:\KenshiTestRuns (excluding this folder, agents\, inflight\, ledger\, alerts\, coordinator*), printing every change; judge by hand which belong to other agents.

## Stop early
`echo stop > C:\KenshiTestRuns\shadow\STOP` (feeder flushes, writes END; the shadows finish after their next wait).
