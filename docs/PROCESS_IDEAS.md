# Process ideas (Shay 2026-10-15): the review kept at every coordinator handoff

Purpose: the coordination process keeps getting cheaper and faster. At every handoff the OLD coordinator spends ~5 minutes on this file; the NEW coordinator asks Shay about the open entries ONCE, together, in its first summary (session-start.ps1 prints them under "PROCESS IDEAS FOR SHAY"). Ideas are recorded, never applied by the review.

Tool: `tools/automation/process-ideas.ps1` (`list`, `add`, `review <decisions.json>`, `asked`, `answer <id> no|yes|approve`, `done <id> -Measured ".."`); selftest `process-ideas-selftest.ps1`. Do not hand-edit the status lines: use the tool.

Entry fields: id, status (open | asked | confirmed | rejected x1 | rejected x2 | done), idea, evidence (what happened and what it cost, measured where possible), saving (expected speed or tokens), risk (to monitoring and the stall / idle / dead-agent catches), hooks (yes = touches hooks/settings), weakens (yes = would weaken a timeout/stall/idle/dead-agent catch; only allowed with hooks=yes and then FOR SHAY ONLY), log.

Rules:
- At most 15 active entries (open | asked | confirmed). Above that `add` and `review` refuse a new one until one is retired; a warning shows from 12.
- Handoff review, at most 3 new entries (the biggest of the session, each with a concrete example) and one step per existing entry, judged against what happened THIS session, never against silence: open + does not apply -> rejected x1; rejected x1 + does not apply -> rejected x2; rejected x2 + does not apply -> removed (moved to Retired with a log line); rejected x1 + applies -> open; rejected x2 + applies -> rejected x1; no decision -> unchanged. `confirmed` only when the decision names a specific moment where the idea would have helped.
- Shay answers: `answer <id> no` removes the entry (logged in Retired); `yes`/`approve` marks it confirmed. If he has not answered by the next handoff the review runs again and asks again.
- When an idea is built, record measured before/after numbers (`done <id> -Measured ...`).
- Nothing in this process may weaken a timeout, stall catch, idle catch or dead-agent catch.

## Active

### PI-13 | confirmed
- idea: Run every selftest at each handoff (selftest-all.ps1: agent-guard, tail-*, process-ideas, event-wait, rowtools, session-start-budget) and make selftests use fixtures, never live state.
- evidence: 2026-10-15 two selftests drifted silently: process-ideas-selftest 2d/8a failed once the live idea list changed, and agent-guard 'event-sweep.sh LF only' had failed unnoticed since be37f58 because event-sweep.sh line 39 had a mangled rollcall path (backslash-t and backslash-a became control characters) so the waker roll call returned nothing and every stall check failed open for hours.
- saving: catches a broken waker/hook script the same hour instead of hours later; ~5 min per handoff
- risk: low; selftests that start games or take > 2 min must be skipped by a flag
- hooks: no
- weakens: no
- added: 2026-10-15 18:51
- moment: 19:36 hookq ran the full selftest set after its hook edit and discovered the pre-existing failure only because it ran everything.
- last_review: coordinator8-19:50
- log: 2026-10-15 18:51 review 'coordinator #7 handoff 2026-10-15': added
- log: 2026-10-15 18:52 asked Shay
- log: 2026-10-15 19:43 review 'coordinator8-19:50': asked -> confirmed (applies: imm26-hookq found agent-session-hooks-selftest meter-coordinator-text failing the same way on the untouched original hook: a drifted selftest nobody ran.)

### PI-18 | confirmed
- idea: Tail Stop hook: let a tail end once every owned agent is DONE and its relay file was delivered (or after a 5 min ack grace), without requiring the explicit tail-ack.
- evidence: 2026-10-15 19:52-20:10: coordinator #8 tail waited for the ack of imm26-5090-i5-op6; its Stop hook re-prompted ~50 times, each replaying ~400k context, until the tail hit its 400k limit and left with tail-mode leave -Force.
- saving: ~50 wasted turns (tens of millions of cache-read tokens) per overlap handoff
- risk: a result could be dropped if delivery is marked without the new coordinator reading it; keep the ack for the ledger but do not hold the tail on it
- hooks: yes
- weakens: no
- added: 2026-10-15 19:57
- log: 2026-10-15 19:58 Shay answered yes

### PI-21 | confirmed
- idea: Open-alert ledger: every urgent waker event (LANE IDLE, LANE NO-OPERATOR, AGENT STALL/ORPHANED, DEAD, KILLED, FAILED, 402) is written to C:\KenshiTestRuns\alerts\open\<id>.json and stays open until alert-ack.ps1 <id> '<action taken>' is run or the condition clears by itself (lane-idle OK, agent DONE); a PostToolUse reminder prints 'OPEN ALERTS n: oldest <min>' after tool calls while any alert is older than 3 min; the Stop hook blocks the coordinator from ending a turn with an unacked alert older than 5 min; operators get their own lane alerts in their inbox with the same ack.
- evidence: 2026-10-15 20:0x: waker event 'LANE IDLE 4080-i4 7m' arrived while I was mid-edit and I did not act on it; I only found the 5090-i4 lane idle 16.7 min after Shay asked 'are we running tests on all lanes'. The waker alerts once and nothing tracks whether anyone acted.
- saving: removes silent ignored alerts; catches a blocked lane within one alert cycle instead of when Shay asks (the 5090-i4 lane lost ~17 min)
- risk: adds a Stop block, so a stale or false alert must clear itself or be ackable with a reason, otherwise it loops turns (see the PI-18 tail loop); it must never be able to hide an alert, ack only closes it
- hooks: yes
- weakens: no
- added: 2026-10-15 20:04
- log: 2026-10-15 20:05 Shay answered yes

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

### PI-10 | done
- idea: Batch waker events: after the first non-urgent event wait 60-120 s and print everything that happened in one wake (DEAD/KILLED/FAILED/question/peer messages still wake at once).
- evidence: 2026-10-15 17:00-18:00 this coordinator session had about 30 waker exits/restarts, each costing a turn plus a restart tool call (~1.5-3k tokens each, ~60k tokens total); many fired seconds apart (e.g. STATUS wpT4 DONE then wpT1/T2 DONE reports).
- saving: ~30-40k tokens per coordinator hour and fewer turns
- risk: must never delay DEAD, KILLED, WALL-CLOCK, FAILED, STOPPED, question or peer wakes; only DONE/INFO events are batched
- hooks: no
- weakens: no
- added: 2026-10-15 17:57
- measured: batched waker (EW_BATCH_SEC 90): selftest 20/20 batch + 13/13 filter; baseline ~30 wakes/h at ~1.5-3k tokens; live saving to be measured next hour
- retired: 2026-10-15 built
- log: 2026-10-15 17:57 review 'coordinator #6 handoff 2026-10-15': added
- log: 2026-10-15 18:04 asked Shay
- log: 2026-10-15 18:04 Shay answered yes

### PI-12 | done
- idea: Generate a one-page lane operator brief from the ledger (state, helpers, next 5 rows, NC DLL SHA, known blockers) so a new operator starts testing within 2 minutes.
- evidence: 2026-10-15 5090 lane i4 had no game activity from 16:18 to 17:28 and imm26-5090-i4op3 spent 8+ min 'reading briefs' (2.5 MB transcript) before its first row; lane-idle flagged 5090 i3 idle 9.9 min while its operator did setup.
- saving: ~8 min of lane time per operator spawn (5 spawns this session = ~40 lane-minutes)
- risk: a stale generated brief could point to a wrong DLL SHA: the generator reads the ledger and lane files at spawn time
- hooks: no
- weakens: no
- added: 2026-10-15 17:57
- measured: lane-brief.ps1 generates ~5-6 KB brief per lane, selftest 14/14; baseline operators spent 8+ min reading briefs (2.5 MB transcript)
- retired: 2026-10-15 built
- log: 2026-10-15 17:57 review 'coordinator #6 handoff 2026-10-15': added
- log: 2026-10-15 18:04 asked Shay
- log: 2026-10-15 18:04 Shay answered yes

### PI-07 | done
- idea: Give session-start.ps1 -Brief a hard output budget (e.g. 12 KB): per-section line caps, only agents not DONE, ledger lines cut to 300 chars, tail/cold-start sections only when non-empty.
- evidence: measured 2026-10-15 17:35: session-start.ps1 -Brief prints 36617 characters (~9k tokens) on the live workspace; the full run was ~94 KB before -Brief (482ab59), so -Brief is only ~2.5x smaller now, not 10x, because the ledger/tail/rollcall sections grew. Every new coordinator pays it once, and every fresh agent that runs it again.
- saving: ~6k tokens per coordinator or agent session start (about 25 KB less to read).
- risk: low; truncation must never drop ORPHANED / NO SUCCESSOR / DEAD / WAKER STATUS lines (keep those uncapped, cap the rest).
- hooks: no
- weakens: no
- added: 2026-10-15 17:40
- moment: session start 17:01: the full output was truncated to a file and cost ~3 extra tool calls before the coordinator knew the live agents; a capped -Brief would have fit on one screen.
- last_review: coordinator #6 handoff 2026-10-15
- measured: session-start -Brief 43715 B -> 10.8 KB (budget 12 KB), must-keep lines uncapped, selftest 19/19
- retired: 2026-10-15 built
- log: 2026-10-15 17:57 review 'coordinator #6 handoff 2026-10-15': open -> confirmed (applies: first session-start.ps1 call of this session returned 93.8 KB (persisted-output) and needed 3 follow-up reads (sed/cut/grep) to find handoff state.)
- log: 2026-10-15 18:04 Shay answered yes

### PI-08 | done
- idea: Archive the old "Right now" entries of testing/HANDOFF.md at each handoff (move everything older than the current coordinator number to archive/HANDOFF_history_<date>.md), so the live file stays under ~30 KB.
- evidence: measured 2026-10-15 17:35: testing/HANDOFF.md is 268469 bytes / 539 lines (~67k tokens if read whole); its "Right now" section alone is lines 8-143, with coordinator #1..#6 entries interleaved out of order (the newest #6 handoff is at line 10, #5 at line 535). Agents and coordinators that open the file whole burn that much context; session-start -Brief has to cut it to 12 lines.
- saving: ~60k tokens for any agent that reads HANDOFF.md whole; fewer wrong-order reads.
- risk: none to monitoring; history stays in git and archive/. Do not move text other tools grep (check session-start.ps1 anchor "## Right now" and handoff-ready.ps1 stay valid).
- hooks: no
- weakens: no
- added: 2026-10-15 17:40
- moment: 17:02: tail -60 of HANDOFF.md dumped ~25 KB of old-handoff text into context; an archived, short 'Right now' would have shown only coordinator #5's block.
- last_review: coordinator #6 handoff 2026-10-15
- measured: testing/HANDOFF.md 270827 B -> 27233 B (244 KB archived verbatim, 0 lines lost), handoff-archive.ps1 runs at every handoff, selftest 17/17
- retired: 2026-10-15 built
- log: 2026-10-15 17:57 review 'coordinator #6 handoff 2026-10-15': open -> confirmed (applies: reading testing/HANDOFF.md 'Right now' at start needed grep -n + tail of a 268 KB file; the first tail printed 60 very long lines.)
- log: 2026-10-15 18:04 Shay answered yes

### PI-11 | done
- idea: Stop-hook successor recognition: accept a successor listed in the program ledger (successors/agent field) or any RUNNING agent on the same wp, not only names with a b/2/-2 suffix.
- evidence: 2026-10-15 the Stop hook blocked the coordinator 3 times for agents that already had live successors under other names (batch2c->batch2d, i4op4->i4op5, ctxop32->ctxop322 and setupfail-scope2->scope2b); each cost a turn plus a manual agent-abandon.ps1.
- saving: ~3 blocked stops per hour, ~3-5k tokens each, no manual abandon
- risk: a wrongly accepted successor could hide a really dead agent: require the successor's status RUNNING < 45 min and the same wp in the ledger
- hooks: yes
- weakens: no
- added: 2026-10-15 17:57
- measured: rule (e) ledger/lane successor: agent-successor selftest 29/29, agent-guard 56/56; same-lane only for lane operators (Shay caveat); baseline 3+ false Stop blocks/h + manual abandons
- retired: 2026-10-15 built
- log: 2026-10-15 17:57 review 'coordinator #6 handoff 2026-10-15': added
- log: 2026-10-15 18:06 asked Shay
- log: 2026-10-15 18:06 Shay answered yes

### PI-06 | done
- idea: Enforce the one-debug-attempt-per-row budget mechanically: go-row.sh / go-batch.sh count attempts per row per lane and, on the second attempt of a failed row, record the cause and stop with ROW-NEEDS-FIXER instead of letting the operator keep debugging.
- evidence: 2026-10-15 operator imm26-5090-ctxop3 reached the 200k-token limit debugging row 07-a (one operator, one row, a whole 200k budget, then a respawn as ctxop32/ctxop322). The DEBUG BUDGET rule exists since 2026-10-15 only as text in briefs/COMMON.md; nothing counts attempts.
- saving: up to one operator context (~200k tokens, ~1 h of a lane) per stuck row; rows after the stuck one start sooner.
- risk: none to monitoring; a wrongly counted attempt could stop a legitimate retry (log every attempt so the coordinator can reset the counter).
- hooks: no
- weakens: no
- added: 2026-10-15 17:40
- moment: 17:15, imm26-5090-ctxop3 STOPPED-CONTEXT while debugging 07-a: a mechanical attempt counter would have forced the move to the next row after the first failure.
- last_review: coordinator #6 handoff 2026-10-15
- measured: go-row/go-batch attempt guard: 2nd attempt after FAIL blocked with ROW-NEEDS-FIXER, override --allow-retry reason (logged); offline selftest 38/38 then 39/39; baseline one row (07-a) consumed a 200k operator context
- retired: 2026-10-15 built
- log: 2026-10-15 17:57 review 'coordinator #6 handoff 2026-10-15': open -> confirmed (applies: 2026-10-15 ~17:15 operator imm26-5090-ctxop3 hit its context limit after 5 rows, mostly debugging row 07-a (stobeNativeAiSnapshot EMPTY); the new one-attempt rule was only a text rule in briefs.)
- log: 2026-10-15 18:04 Shay answered yes

### PI-09 | done
- idea: Measure the first live use of go-row.sh / go-batch.sh / preflight.sh (rowtools3) against the hand-run baseline and record per-row time and tokens, then fix or keep the tools on that evidence.
- evidence: HANDOFF #6 (2026-10-15): rowtools3 selftest is 23/23 but "NOT yet run on a live lane"; the baseline is the hand-run row 07-a that took ctxop3 a whole 200k-token context. Until a live row is timed the saving is a claim, and the first live row may need rowcheck/ini fixes.
- saving: unknown until measured; target: one RESULT line per row at < 5k tokens per row instead of the ~200k spent on 07-a.
- risk: none to monitoring (measurement only); rows must keep running on isolated lanes only.
- hooks: no
- weakens: no
- added: 2026-10-15 17:40
- measured: row-timing-report 2026-10-15 18:37-19:53: 15 executed rows, avg 119 s/row (24 s PASS 24-b .. 254 s FAIL 19-a), 3 PASS 11 FAIL 1 GATED, attempt guard blocked 1 repeat. Baseline hand-run 07-a = one 200k-token operator context, wall unrecorded; 07-a not ported so no like-for-like. Tokens/row are NOT recorded (known gap); most FAILs are 19-a/12-d (402 outage + real trip bug), not tool faults.
- retired: 2026-10-15 built
- log: 2026-10-15 18:04 asked Shay
- log: 2026-10-15 18:04 Shay answered yes

### PI-17 | done
- idea: Orphan check should use evidence/log freshness for in-session agents, not agent-host sessions.
- evidence: 19:20 AGENT ORPHANED imm26-4080-op2i (silent 31.9 min) while its poll log was written a minute earlier; I had to check the log by hand.
- saving: ~2 min and a false alarm per busy poller
- risk: could mask a truly dead agent if the evidence dir is touched by another process
- hooks: yes
- weakens: no
- added: 2026-10-15 19:43
- measured: agent-guard-selftest 75/75 (13 new PI-17 cases: silent 31 min + fresh own log/dir/lane dir => not orphaned and in-flight; only foreign file / old own log / .status / session.json agent / no evidence => still orphaned), agent-host-monitor-selftest 26/26 (3 new INPROC cases), agent-successor-selftest 29/29, event-wait-filter-selftest 13/13; live roll call run OK
- retired: 2026-10-15 built
- log: 2026-10-15 19:43 review 'coordinator8-19:50': added
- log: 2026-10-15 19:54 Shay answered yes

### PI-16 | done
- idea: Stop hook IDLE-GAME check should read lane locks (game-N.lock) not only instance 1.
- evidence: 19:19 Stop hook blocked the turn: default slot idle 19 min while 3 lane games (game-3/4/5.lock) ran under operators; I had to record kenshi-ctl idle with a reason.
- saving: 1 blocked turn + manual idle record per outage
- risk: touches hooks: could hide a real idle lane if wrong
- hooks: yes
- weakens: no
- added: 2026-10-15 19:43
- measured: waker-lanes-selftest 15/15 (3 lane games+game.lock free not blocked; idle/operator-less live lane and stale dead-process lock still block); tail-hooks, hook-command, agent-guard, agent-successor, tail-close selftests PASS; agent-session-hooks has 1 unrelated FAIL (meter-coordinator-text, context-meter hook)
- retired: 2026-10-15 built
- log: 2026-10-15 19:43 review 'coordinator8-19:50': added
- log: 2026-10-15 19:54 Shay answered yes

### PI-14 | done
- idea: Allow-list the status/report helpers for subagents (agent-status.ps1, save-report.ps1) in the project permission settings so the auto-mode classifier never blocks an agent from marking itself DONE.
- evidence: 2026-10-15 imm26-pi11 finished its work but the classifier denied agent-status.ps1 and a save-report.ps1 read as Self-Modification, so its status stayed RUNNING until the coordinator fixed it by hand (and the report only arrived as a chat hand-back); imm26-5090-i4op32 also reported save-report.ps1 rejected its arguments.
- saving: no stale RUNNING agents and no hand-fix turn (~3k tokens each time)
- risk: low, but it edits permission settings: Shay decides
- hooks: yes
- weakens: no
- added: 2026-10-15 18:51
- measured: 11 narrow allow rules applied to .claude/settings.json (hooks untouched, JSON parses); effect to be seen when no agent is blocked from marking itself DONE
- retired: 2026-10-15 built
- log: 2026-10-15 18:51 review 'coordinator #7 handoff 2026-10-15': added
- log: 2026-10-15 18:52 asked Shay
- log: 2026-10-15 19:54 Shay answered yes

### PI-15 | done
- idea: Preflight/health check for the chat LLM provider balance (1-token completion, print the 402 body): run in lane-idle/preflight and block row marking while it fails.
- evidence: 19:33-19:40: DeepInfra HTTP 402 hit all lanes; 4 operators ran 19-a/12-d/03-b into empty "..." replies, one FAIL (12-d) was marked and had to be reset; 3 operators + me spent ~40 min before the cause was named.
- saving: ~30-40 min and 1 false FAIL per outage
- risk: low: read-only health call, tiny token cost
- hooks: no
- weakens: no
- added: 2026-10-15 19:43
- measured: llm-health.sh live OK ~300-460 ms (real DeepInfra, key never printed); selftest 10/10 offline (fake 200/402/401/timeout/local-skip/no-key-leak, WSL+Git Bash); preflight selftest preflight-llm-down PASS; lane-brief selftest OK (rule added). Pre-existing unrelated rowtools selftest FAILs: 19-d, heartbeat-agent-status-ps1, trip-family (WSL env)
- retired: 2026-10-15 built
- log: 2026-10-15 19:43 review 'coordinator8-19:50': added
- log: 2026-10-15 19:54 Shay answered yes

### PI-19 | done
- idea: lane-brief.ps1 -Predecessor prints the exact status TASK text to use and registers the successor in lane-owners.json itself.
- evidence: 2026-10-15: successor names hard2 -> hard2b with a different task text caused 2 false NO SUCCESSOR Stop-hook blocks, and every respawn needed a hand-run operator-warn.ps1 -Register (4 times at 19:50).
- saving: 2 false Stop blocks and 4 manual commands per respawn round
- risk: low: registration is only a map write; the successor still must be RUNNING
- hooks: no
- weakens: no
- added: 2026-10-15 19:57
- measured: lane-brief selftest 8 PI-19 cases ok (task text printed exactly, paste cmd, registration first+idempotent, -NoRemote skipped); operator-warn selftest ok incl -InLane; real brief 18575 B < 25600
- retired: 2026-10-15 built
- log: 2026-10-15 19:58 Shay answered yes

### PI-20 | done
- idea: lane-brief standing rule: game speed above 5 only with tools/stobe-goal-watch.sh; never run speed 10 for minutes.
- evidence: 2026-10-15 imm26-5090-i5-op6 ran speed 10 and Shay (the test character) starved and died, resetting the lane (its handoff lesson).
- saving: avoids a lane reset (~10 min) per occurrence
- risk: none
- hooks: no
- weakens: no
- added: 2026-10-15 19:57
- measured: rule 'Game speed (PI-20)' present in every generated brief (selftest ok), brief 18575 B < 25600 cap
- retired: 2026-10-15 built
- log: 2026-10-15 19:58 Shay answered yes
