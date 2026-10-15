# Process ideas (Shay 2026-10-15): the review kept at every coordinator handoff

Purpose: the coordination process keeps getting cheaper and faster. At every handoff the OLD coordinator spends ~5 minutes on this file; the NEW coordinator asks Shay about the open entries ONCE, together, in its first summary (session-start.ps1 prints them under "PROCESS IDEAS FOR SHAY"). Ideas are recorded, never applied by the review.

Tool: `tools/automation/process-ideas.ps1` (`list`, `add`, `review <decisions.json>`, `asked`, `answer <id> no|yes|approve`, `done <id> -Measured ".."`); selftest `process-ideas-selftest.ps1`. Do not hand-edit the status lines: use the tool.

Entry fields: id, status (open | asked | confirmed | rejected x1 | rejected x2 | done), idea, evidence (what happened and what it cost, measured where possible), saving (expected speed or tokens), risk (to monitoring and the stall / idle / dead-agent catches), hooks (yes = touches hooks/settings), weakens (yes = would weaken a timeout/stall/idle/dead-agent catch; only allowed with hooks=yes and then FOR SHAY ONLY), log.

Rules:
- At most 10 active entries (open | asked | confirmed). Above that `add` and `review` refuse a new one until one is retired; a warning shows from 8.
- Handoff review, at most 3 new entries (the biggest of the session, each with a concrete example) and one step per existing entry, judged against what happened THIS session, never against silence: open + does not apply -> rejected x1; rejected x1 + does not apply -> rejected x2; rejected x2 + does not apply -> removed (moved to Retired with a log line); rejected x1 + applies -> open; rejected x2 + applies -> rejected x1; no decision -> unchanged. `confirmed` only when the decision names a specific moment where the idea would have helped.
- Shay answers: `answer <id> no` removes the entry (logged in Retired); `yes`/`approve` marks it confirmed. If he has not answered by the next handoff the review runs again and asks again.
- When an idea is built, record measured before/after numbers (`done <id> -Measured ...`).
- Nothing in this process may weaken a timeout, stall catch, idle catch or dead-agent catch.

## Active

### PI-06 | open
- idea: Enforce the one-debug-attempt-per-row budget mechanically: go-row.sh / go-batch.sh count attempts per row per lane and, on the second attempt of a failed row, record the cause and stop with ROW-NEEDS-FIXER instead of letting the operator keep debugging.
- evidence: 2026-10-15 operator imm26-5090-ctxop3 reached the 200k-token limit debugging row 07-a (one operator, one row, a whole 200k budget, then a respawn as ctxop32/ctxop322). The DEBUG BUDGET rule exists since 2026-10-15 only as text in briefs/COMMON.md; nothing counts attempts.
- saving: up to one operator context (~200k tokens, ~1 h of a lane) per stuck row; rows after the stuck one start sooner.
- risk: none to monitoring; a wrongly counted attempt could stop a legitimate retry (log every attempt so the coordinator can reset the counter).
- hooks: no
- weakens: no
- added: 2026-10-15 17:40

### PI-07 | open
- idea: Give session-start.ps1 -Brief a hard output budget (e.g. 12 KB): per-section line caps, only agents not DONE, ledger lines cut to 300 chars, tail/cold-start sections only when non-empty.
- evidence: measured 2026-10-15 17:35: session-start.ps1 -Brief prints 36617 characters (~9k tokens) on the live workspace; the full run was ~94 KB before -Brief (482ab59), so -Brief is only ~2.5x smaller now, not 10x, because the ledger/tail/rollcall sections grew. Every new coordinator pays it once, and every fresh agent that runs it again.
- saving: ~6k tokens per coordinator or agent session start (about 25 KB less to read).
- risk: low; truncation must never drop ORPHANED / NO SUCCESSOR / DEAD / WAKER STATUS lines (keep those uncapped, cap the rest).
- hooks: no
- weakens: no
- added: 2026-10-15 17:40

### PI-08 | open
- idea: Archive the old "Right now" entries of testing/HANDOFF.md at each handoff (move everything older than the current coordinator number to archive/HANDOFF_history_<date>.md), so the live file stays under ~30 KB.
- evidence: measured 2026-10-15 17:35: testing/HANDOFF.md is 268469 bytes / 539 lines (~67k tokens if read whole); its "Right now" section alone is lines 8-143, with coordinator #1..#6 entries interleaved out of order (the newest #6 handoff is at line 10, #5 at line 535). Agents and coordinators that open the file whole burn that much context; session-start -Brief has to cut it to 12 lines.
- saving: ~60k tokens for any agent that reads HANDOFF.md whole; fewer wrong-order reads.
- risk: none to monitoring; history stays in git and archive/. Do not move text other tools grep (check session-start.ps1 anchor "## Right now" and handoff-ready.ps1 stay valid).
- hooks: no
- weakens: no
- added: 2026-10-15 17:40

### PI-09 | open
- idea: Measure the first live use of go-row.sh / go-batch.sh / preflight.sh (rowtools3) against the hand-run baseline and record per-row time and tokens, then fix or keep the tools on that evidence.
- evidence: HANDOFF #6 (2026-10-15): rowtools3 selftest is 23/23 but "NOT yet run on a live lane"; the baseline is the hand-run row 07-a that took ctxop3 a whole 200k-token context. Until a live row is timed the saving is a claim, and the first live row may need rowcheck/ini fixes.
- saving: unknown until measured; target: one RESULT line per row at < 5k tokens per row instead of the ~200k spent on 07-a.
- risk: none to monitoring (measurement only); rows must keep running on isolated lanes only.
- hooks: no
- weakens: no
- added: 2026-10-15 17:40

## Retired

### PI-01 | done
- idea: The agent monitor must not kill a working agent after 20 minutes of "silence": count status-file, log AND evidence-dir activity as the heartbeat.
- evidence: 2026-10-15 the agent-host monitor killed a working agent (imm26-4080-i4op4 "killed by agent-host", KNOWN_BLOCKERS) after 20 min of silence (no status write) although it was still working; its run and context were lost and a fresh operator had to be respawned.
- saving: avoids one lost agent run per long row (a respawn costs the coordinator a turn plus the agent's re-read of its brief, ~20-40k tokens).
- risk: a genuinely hung agent that keeps writing evidence is killed later; mitigated because process-alive AND evidence age < 10 min are both required (the 20 min kill rule itself is unchanged for agents with no activity).
- hooks: no
- weakens: no
- added: 2026-10-15
- measured: commit 6376cff agent-rollcall (evidence-dir activity counts as heartbeat), monitor selftest 11/11. Before: 1 working agent killed (observed). After: no repeat in the rest of the session; no time/token delta could be measured beyond that.
- retired: 2026-10-15 built

### PI-02 | done
- idea: Quiet waker: re-check an AGENT STALL / AGENT ORPHANED inbox message against agent-rollcall (process alive and evidence < 10 min) and suppress it when the agent is working; DEAD/KILLED/WALL-CLOCK/FAILED/DONE/peer messages always wake.
- evidence: 2026-10-15 false ORPHANED / STALL wakes interrupted the coordinator repeatedly while the named agents were working; each wake costs a coordinator turn (read inbox, check status, decide) of estimated 3-8k tokens (not measured) plus the lost focus.
- saving: removes the false wakes (about one coordinator turn each).
- risk: a real stall is suppressed if rollcall evidence is wrong; mitigated: only STALL/ORPHANED are filtered, and only when process alive AND evidence < 10 min; every other class still wakes.
- hooks: no
- weakens: no
- added: 2026-10-15
- measured: commit 878aef6, selftests 23/23 (wakertools) and 13/13 (agent-host); suppressed messages are kept in inbox\coordinator\delivered\suppressed\ for audit. Wakes per hour before/after were not counted (no counter existed); recorded as a known gap.
- retired: 2026-10-15 built

### PI-03 | done
- idea: Waker per-lane activity check (lane-idle.ps1): wake with LANE IDLE / LANE NO-OPERATOR when a rig lane has no row activity.
- evidence: 2026-10-15 the 5090 i4 lane sat idle for ~8 min while its operator read briefs; Shay noticed it, not the waker (breaks "no rig idle > 2 min while work exists").
- saving: up to ~8 idle lane-minutes per occurrence caught within the waker interval (<= 2 min) instead of by Shay.
- risk: none to existing catches (adds a catch); a wrong lane->operator map yields false wakes (map lives in lane-idle.ps1).
- hooks: no
- weakens: no
- added: 2026-10-15
- measured: commit 42a18ac (+ 7929692 5090 i5 operator mapping). Before: 8 min idle found by Shay; after: detection within one waker cycle (<= 120 s), no new idle episode reported in the session after the fix.
- retired: 2026-10-15 built

### PI-04 | done
- idea: Agents write the FULL report to a file (save-report.ps1 -> agents\out\<name>\) and hand back at most 8 lines; fixers hand back the patch path only.
- evidence: 2026-10-15 long agent reports (30+ lines, pasted code and logs) filled the coordinator context; with about 12 agents a session that is a large share of the 300k handoff budget.
- saving: from ~30 lines (+ pasted logs) to <= 8 lines per agent result (rough 70% less per report; the coordinator opens the file only when it needs it).
- risk: the coordinator may skip reading a FAIL detail; mitigated by the file path in every hand-back and one-line verdicts.
- hooks: no
- weakens: no
- added: 2026-10-15
- measured: rule in agents/briefs/COMMON.md (REPORTING) and docs/COORDINATOR_IMPROVEMENTS.md; hand-back size 30 -> 8 lines. Token totals before/after were not measured.
- retired: 2026-10-15 built

### PI-05 | done
- idea: session-start.ps1 -Brief: only live agents, cut long lines, skip rig-runner/stale sections.
- evidence: 2026-10-15 the full session-start output was ~94 KB (about 23k tokens) at every coordinator start and every agent that re-ran it.
- saving: ~94 KB -> 36.6 KB (measured 2026-10-15 17:35 with -Brief); further cut proposed as PI-07.
- risk: a hidden section could hide a problem; mitigated because the WAKER STATUS, ORPHANED, NO SUCCESSOR, DEAD and TAIL lines are always printed.
- hooks: no
- weakens: no
- added: 2026-10-15
- measured: commit 482ab59 (-Brief), 2e93c9c (CLAUDE.md uses -Brief). Before ~94 KB (Shay's figure), after 36617 chars measured now; the "10x smaller" claim holds only for the state at that commit, not today.
- retired: 2026-10-15 built
