# Living handoff standard (Shay 2026-10-16)

Why: the session is auto-compacted at ~150k to stay light and cheap. A compaction summary is lossy; anything not on disk may be unrecoverable.
So `testing/COORDINATOR_LIVE.md` (narrative) + `testing/HANDOFF.md` "Right now" (program state) + `testing/SHAY_DECISIONS.md` (open questions) + the mechanical snapshot `C:\KenshiTestRuns\handoff-auto.md` must let a session with ZERO context continue.

## Update triggers (same turn as the event, never "later")
| event | update |
|---|---|
| agent finishes / hands back | its roster row (section 5), the next owner's instruction, what the result means, commit |
| Shay message with an order, preference or decision | section 2 (his words), section 4 (why) or SHAY_DECISIONS "Decided" |
| new question for Shay | SHAY_DECISIONS (problem, options, in-game effect, code consequence, default) |
| agent spawned | roster row with agentId, role, what to do when it finishes, `agent-ids.ps1 add` |
| install / build / deploy / swap | what, hash, backup path, where applied |
| gotcha learned the hard way | section 8 |
| process snag, wasted tokens/time, or an improvement idea | docs/PROCESS_IDEAS.md at once (`process-ideas.ps1 add`, concrete evidence + cost); evidence on an existing idea that recurred; at 12+ active entries `progress`/`done` finished ones; a compaction otherwise loses the moment |
| startable work found, or a held-back task | testing/AGENT_BACKLOG.md |
| deliverable promised to Shay | section 3 |

## Rules
- Rewrite the line that changed; no stacked "correction" paragraphs. Keep COORDINATOR_LIVE.md under ~250 lines, move finished history to `archive/`.
- Record WHY next to every decision, and the exact command to resume anything in flight.
- Zero-context test before a compact (or when the meter warns): can a new session do the next 10 things from the files alone?
- The meter's warn message at ~120k means: run the zero-context test now, file new PROCESS IDEAS (docs/PROCESS_IDEAS.md), commit + push the files, then continue; auto-compact follows at ~150k.
- Agent results and agentIds, Shay's exact orders and unfinished promises are the things a summary loses first: they live in sections 2, 3, 5.
