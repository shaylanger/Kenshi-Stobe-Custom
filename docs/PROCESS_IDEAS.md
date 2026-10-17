# Process ideas (Shay 2026-10-15): the review kept at every coordinator handoff

Purpose: the coordination process keeps getting cheaper and faster. At every handoff the OLD coordinator spends ~5 minutes on this file; the NEW coordinator asks Shay about the open entries ONCE, together, in its first summary (session-start.ps1 prints them under "PROCESS IDEAS FOR SHAY"). Ideas are recorded, never applied by the review.

Tool: `tools/automation/process-ideas.ps1` (`list`, `add`, `review <decisions.json>`, `answer <id> no|yes|approve`, `done <id> -Measured ".."`); selftest `process-ideas-selftest.ps1`. Do not hand-edit the status lines: use the tool.

Entry fields: id, status (open | confirmed | rejected x1 | rejected x2 | done), idea, evidence (what happened and what it cost, measured where possible), saving (expected speed or tokens), risk (to monitoring and the stall / idle / dead-agent catches), hooks (yes = touches hooks/settings), weakens (yes = would weaken a timeout/stall/idle/dead-agent catch; only allowed with hooks=yes and then FOR SHAY ONLY), log.

Rules:
- At most 23 active entries (open | confirmed). Entries being built (or built and waiting for their measured result) move to the `## In progress` section with `process-ideas.ps1 progress <id>` (status in-progress): they do NOT count toward the cap, so new ideas can keep being added while others are built (Shay 2026-10-16). Above that `add` and `review` refuse a new one until one is retired; a warning shows from 12.
- Handoff review, at most 3 new entries (the biggest of the session, each with a concrete example) and one step per existing entry, judged against what happened THIS session, never against silence: open + does not apply -> rejected x1; rejected x1 + does not apply -> rejected x2; rejected x2 + does not apply -> removed (moved to Retired with a log line); rejected x1 + applies -> open; rejected x2 + applies -> rejected x1; no decision -> unchanged. `confirmed` only when the decision names a specific moment where the idea would have helped.
- Shay answers: `answer <id> no` removes the entry (logged in Retired); `yes`/`approve` marks it confirmed. If he has not answered by the next handoff the review runs again and asks again.
- When an idea is built, record measured before/after numbers (`done <id> -Measured ...`).
- Nothing in this process may weaken a timeout, stall catch, idle catch or dead-agent catch.

## Active

### PI-37 | Oepn
- idea: session-start / agent-status should auto-abandon the inflight marker of a dead predecessor as soon as a successor registered in lane-owners or with the same task text is RUNNING.
- evidence: 2026-10-16 10:00-10:40: after the freeze 3 predecessor markers (op12, op9k, inv-14d) plus sfC/sfE2 caused false RIG STALL / work-in-flight wakes and 5 manual agent-abandon calls.
- saving: ~5 manual calls and 4 spurious waker wakes per resume
- risk: must not hide a truly unowned stopped agent: only when the successor task text matches
- hooks: yes
- weakens: no
- added: 2026-10-16 10:49
- log: 2026-10-16 10:49 review 'coordinator-14': added

### PI-41 | Open
- idea: The tail hard limit (400k) forces a TaskStop of live lane operators mid-row. Prevent it: autoCompactWindow=330000 now set in the user settings so a tail compacts itself soon after the handoff (new sessions), and keep the tail lean (PI-38/39/40). Longer term run lane operators as independent sessions so a coordinator's context never limits a lane.
- evidence: 2026-10-16 11:15-11:20: the tail reached 409k+ after about 40 post-handoff turns and had to order three lane operators to checkpoint; 5090-i3 left a 20-minute 19-ax job unowned, 4080-i4 stopped with 08-d/11-b open, 4080-i3 had to be stopped mid 08-e; three lanes lose about an hour of operator time each until respawned.
- saving: about 1 lane-hour x 3 lanes per handoff, plus the tail turns
- risk: autoCompactWindow also applies to coordinators/subagents; coordinators hand off at 300k, subagents at 200k, so 330k only affects tails
- hooks: no
- weakens: no
- added: 2026-10-16 11:18
- log: 2026-10-16 11:18 review 'coordinator-14-tail-closing': added

### PI-44 | Open
- idea: Never move inbox/coordinator/*.msg by hand (my blanket 'mv *.msg done/' habit hid a Haiku-pilot operator's 00-ask question for about 10 minutes); the waker already moves files to delivered/ and prints them. Add a rule line to AGENT_PROMPTS and make the waker print the full text of any PILOT-ESCALATE / 00-ask message (not the 300-char cut).
- evidence: 2026-10-16 12:48: imm26-5090-i4-hk1 sent a 00-ask (window placement refused); I had archived the file with mv before reading it and only noticed via hk1's status line ~10 min later, so the pilot lane waited.
- saving: avoids a lane waiting for an unseen question (about 10 min of rig time per occurrence)
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 12:52
- log: 2026-10-16 12:52 review 'coordinator-16': added

### PI-46 | Open
- idea: A tail session should need zero model turns: tail-autorelay must relay every finished agent (it relayed sfV/sfT early, then stopped relaying; I relayed sfP, sfR, ctxfix, fxC2, sfU, sfS, op13, op21, op9n by hand) and Get-TailRelayState must also search coordinator/done/.
- evidence: 12:00-13:05: 9 hand relays at ~300k context each, plus ~8 tail-wait restarts.
- saving: ~17 full-price turns at 300k per handoff (large share of the tail's cost)
- risk: low: tooling bug fix with a selftest
- hooks: no
- weakens: no
- added: 2026-10-16 13:05
- log: 2026-10-16 13:05 review 'coordinator-15-tail': added

### PI-48 | Open
- idea: Lane operators must never run bare `stobe-auto` (it talks to the LIVE install): put one line in lane-brief and the lane-operator block saying 'use go-row / lane-setup, or first export RIG, KAH_INSTANCE and source rig-env.sh', and make bare stobe-auto refuse (exit 2) when a lane-lock is held and KAH_INSTANCE is unset.
- evidence: 2026-10-16 12:55-13:05: Haiku pilot hk1 ran bare `stobe-auto wait-world` twice (120 s and 300 s), got 'no answer (loading?)', escalated three times and stopped; the lane sat idle ~15 min, and it took 2 peer messages + 2 tail resumes (about 6 model turns) to find the cause.
- saving: about 15 min lane time and 6 coordinator/tail turns per occurrence, more with cheaper models that follow the brief literally
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 13:35
- log: 2026-10-16 13:35 review 'coordinator-16-tail-closing': added

### PI-49 | Open
- idea: Tooling snags hit by two or more operators become a fixer ticket automatically: operators append `SNAG <script:line> <symptom> <workaround>` to one file and the waker counts repeats; at the second distinct operator it wakes the coordinator once with the proposed root fix.
- evidence: 2026-10-16 12:30-13:35: hxdefs.sh:30 writing /c/... (false SETUP-FAIL, hit op9o, op22 and op14's hx runs, each diagnosed alone at about 10-20k tokens); lane-deploy.sh deleting the sfO inject seam (op14 and op9o each rediscovered it); the root fix is still not applied.
- saving: about 2 x 15k operator tokens per rediscovery and false FAILs on rows; fewer wrong verdict lines
- risk: low (read-only counting; a wake only for repeats)
- hooks: no
- weakens: no
- added: 2026-10-16 13:35
- log: 2026-10-16 13:35 review 'coordinator-16-tail-closing': added

### PI-51 | confirmed
- idea: Replace the 'wake, read output file, restart waker' loop by one persistent waker that appends actionable events to a file watched by the Monitor tool (or the background task notification), so the coordinator does not spend 2 tool calls per wake restarting it and never creates duplicate wakers.
- evidence: 13:00-13:55: about 30 waker restarts, each 2 tool calls; twice a second waker was started while one was still running (exit code 15 kills, duplicate EVENT lines) and the Stop hook blocked once because no waker was running in the gap.
- saving: about 60 tool calls and 3 hook-block turns per hour
- risk: medium: waker semantics and the Stop-hook liveness check must move together
- hooks: yes
- weakens: no
- added: 2026-10-16 13:56
- moment: tail turn after fix26f2 hand-back, 16:1x
- last_review: efc58758-86f8-4786-a138-4e53f075016d-tail
- log: 2026-10-16 13:56 review 'coordinator-17': added
- log: 2026-10-16 16:14 review 'efc58758-86f8-4786-a138-4e53f075016d-tail': Open -> confirmed (applies: tail-wait.ps1 had to be re-armed after each early exit; the tail spent several turns only restarting the waker while 3 agents ran (fix26f2, 3 op25s).)

### PI-52 | Open
- idea: Put known tooling snags (e.g. hxdefs.sh:30 /c/ path in bundle_dir.txt giving a false 'bundle dirs missing' SETUP-FAIL, use HX_OUT=C:/KenshiTestRuns/imm26-4080-hx) in the generated lane brief from testing/KNOWN_BLOCKERS.md, and make mark-row.py refuse SETUP-FAIL 'bundle dirs missing' when run.log is empty and the dirs exist.
- evidence: 11:58-13:34: the same path bug produced false SETUP-FAILs on 01-cx, 16-bx (4080-i3, 5090-i5) and cost two investigator agents (inv01cx 190k tokens) plus two operator rediscoveries before it was named.
- saving: about 200k tokens and 3 false tickets per occurrence
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 13:56
- log: 2026-10-16 13:56 review 'coordinator-17': added

### PI-56 | Open
- idea: tail-autorelay should relay a RESUMED agent's second DONE (agent re-finishes after a SendMessage) as a new result, keyed on the status-file mtime/agentId run counter, instead of treating the name as already relayed.
- evidence: 2026-10-16 15:08: huntA2 was resumed by SendMessage for the expiresAt 43200 order and finished again, but autorelay.log showed no second relay for imm26-huntA2 (state already marked it relayed at 14:56), so the tail had to send the result to coordinator 19 by hand.
- saving: one hand relay (about 2 tool calls) per resumed agent and no risk of a lost result
- risk: low: relays only, no monitoring catch is changed
- hooks: no
- weakens: no
- added: 2026-10-16 15:40
- log: 2026-10-16 15:40 review 'coordinator-18-tail': added

### PI-58 | open
- idea: Let tail-relay.ps1 accept the hand-back text and auto-send it to coordinator.current in one call (and mark the agent relayed in the ledger), so the tail does not need a model turn to re-summarise and SendMessage each result.
- evidence: This tail period: 5 results were each re-typed into a SendMessage of 1.5-3k tokens by a model at 100k+ context, although the content was already in the agent's out file.
- saving: about 5 turns and 15k output tokens per tail period
- risk: low: relays are results not orders; the coordinator still acks
- hooks: no
- weakens: no
- added: 2026-10-16 16:14
- log: 2026-10-16 16:14 review 'efc58758-86f8-4786-a138-4e53f075016d-tail': added

### PI-59 | confirmed
- idea: tail-ack.ps1 must accept agents that are in no program ledger (in-session operators/fixers named imm26-*), e.g. by acking via the inbox/relay file instead of the ledger record, so the new coordinator can ack and the tail closes by ack instead of by timeout.
- evidence: 2026-10-16 17:12: coordinator 21 reported 'tail-ack could not ack them (agents not in the program ledger)' for nc28, 5090-i5-op14 and 4080-i3op26; the tail cannot close via ack, so the tail keeps burning turns until the 5 min relay timeout.
- saving: about 3-5 tail turns and a faster tail close per handoff
- risk: low: ack only closes the tail's wait, it changes no agent state
- hooks: no
- weakens: no
- added: 2026-10-16 17:12
- moment: 18:25 inv26froute tail relay
- last_review: coordinator-22
- log: 2026-10-16 17:12 review '05c6207d-b5b1-49c2-904b-6c32d15536f1-tail': added
- log: 2026-10-16 18:45 review 'coordinator-22': open -> confirmed (applies: 2026-10-16 18:25: tail-ack.ps1 and program-ledger.ps1 ack both refused imm26-inv26froute ('in no program ledger'); the 21 coordinator had to be told to close its tail with tail-close.ps1 instead.)

### PI-60 | confirmed
- idea: Row cards (row-card.sh, e.g. 26-f) still print RUN lines with KAH_PF_ISOLATION=0; the classifier denies that bypass, so every operator that copies the card wastes a step or stops (op27 20-d and op18 26-f both did). Print the safe form: run from the lane's CONFIGURED save (--save <lane save>) and state that rw-* start saves fail the npc-world isolation check.
- evidence: 2026-10-16 17:15 (op27 20-d, blocked for a false 'isolation' reason) and 17:50 (op18 26-f, preflight fail on stale game/marker); 20-d and 22-b PASSED at 17:55/18:00 as soon as they ran from the configured save with no bypass.
- saving: every operator that copies a row card with the bypass loses 1 spawn (about 60k tokens) before the safe form is tried
- risk: none (no timeout/stall/idle/dead-agent catch is weakened; text/format change only)
- hooks: no
- weakens: no
- added: 2026-10-16 18:02
- moment: 18:35 sfFixC hand-back
- last_review: coordinator-22
- log: 2026-10-16 18:02 review 'coordinator-21': added
- log: 2026-10-16 18:45 review 'coordinator-22': open -> confirmed (applies: 2026-10-16 18:35: the sfFixC and sff (03-b) recipe hand-backs each told operators to run with KAH_PF_ISOLATION=0, which the project forbids; I had to rewrite the commands by hand in three operator ...)

### PI-61 | open
- idea: Size setup-fail fixer work to ONE ticket per fixer: three-ticket briefs hit the 200k context at ticket 1-2 every time, so each needed a successor with full re-reading.
- evidence: 2026-10-16 18:00-18:50: imm26-sfFixA (3 tickets) stopped after 03-b, sfFixB (3 tickets) after 13-c/13-c-neg, sfFixA2 stopped before verifying 23-e; three respawns of about 200k tokens each, about 600k tokens of re-reading and a 30+ min delay on 23-e and 11-b.
- saving: about 400k tokens and 30 min per three-ticket batch
- risk: low: more agents, but each with a smaller scope; costs nothing extra in coordination if spawned in parallel at once
- hooks: no
- weakens: no
- added: 2026-10-16 18:45
- log: 2026-10-16 18:45 review 'coordinator-22': added

### PI-62 | open
- idea: The Stop-hook sweep block should not fire for items whose owning agent is DONE and whose commit is pushed (pi11-stage, b3-report, 4080 launch log dumps, old NC trees): auto-keep them 7 days with a standard reason, or auto-delete after a safety check, instead of costing a coordinator turn each.
- evidence: 2026-10-16 18:05-18:30: five separate Stop-hook blocks (imm26-nc6, b3-report.txt, two 4080 launch logs, pi11-stage), each a full-context turn of about 5-8k tokens for a delete or -Keep whose answer was obvious from git log.
- saving: about 5 turns and 30k tokens per session
- risk: medium: auto-delete must verify the work is committed and no inflight marker names the path; never touch corpus, fixtures or inflight
- hooks: yes
- weakens: no
- added: 2026-10-16 18:45
- log: 2026-10-16 18:45 review 'coordinator-22': added

## In progress

### PI-54 | in-progress
- idea: pilot-audit.py/cost-audit.py must be run with Windows python and resolve agent names to ids by default, and the audit must FAIL LOUDLY (not print an empty COST section) when the cost tool finds no transcripts.
- evidence: 2026-10-16 15:10-15:50: the Haiku pilot audit had an empty COST section ('NO MATCH', files to scan 0) and I told Shay no cost data existed; Shay: 'that was a required part of this'. The data existed in the transcripts (Haiku $0.15 vs Sonnet $0.23-0.53 per row marked) and needed agent ids and Windows python.
- saving: about 30 minutes and one wrong claim to Shay per pilot report
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 14:57
- moment: 15:55 Shay: why does SUMMARY-final.md not have any data for the Sonnet run
- last_review: coordinator-18-tail
- log: 2026-10-16 14:57 review 'coordinator-18': added
- log: 2026-10-16 15:40 review 'coordinator-18-tail': open -> confirmed (applies: 2026-10-16 16:00 Shay saw SUMMARY-final.md with every Sonnet column 'no RESULT found'; cause was pilot-audit.py line 607 default sonnet_roots missing the imm26-4080 lanes, found only after Shay com...)
- log: 2026-10-16 16:12 confirmed -> in-progress (Shay: keep adding new ideas while these are built)

### PI-38 | in-progress
- idea: tail-wait / Get-TailAgentSet must not count a still-working in-session agent as 'needs the tail' just because its status file is older than 45 min: use a liveness signal (the agent's tool-output file or its work dir changed in the last 10 min, or ListAgents says running) before it exits the wait and lets the Stop hook block.
- evidence: 2026-10-16 10:57-11:08 (tail ded82aa7): imm26-hxA kept working (script files changed 10:54) but its status said 'designing' since 10:18, so tail-wait exited at once 5 times and the Stop hook blocked 13 times; every block was a full model turn re-reading a 300k+ context.
- saving: about 13 turns x a 300k-token re-read per stalled-status agent (several hundred thousand tokens)
- risk: must still catch a really dead agent: keep the 20-minute no-activity TaskStop rule
- hooks: yes
- weakens: no
- added: 2026-10-16 11:11
- moment: 12:20 tail wait exited immediately in a loop after I archived relays into done/
- last_review: coordinator-16
- log: 2026-10-16 11:11 review 'coordinator-14-tail': added
- log: 2026-10-16 12:52 review 'coordinator-16': open -> confirmed (applies: 2026-10-16 12:00-12:50: the previous tail's tail-wait kept exiting in a loop (relays moved to inbox/coordinator/done/ were not seen by Get-TailRelayState); tail #15 copied relays into delivered/ by...)
- log: 2026-10-16 14:57 confirmed -> in-progress (Shay: keep adding new ideas while these are built)

### PI-39 | in-progress
- idea: The tail session should not be the 300k+ coordinator context: at handoff either /compact the old window (script it into handoff: tail-mode enter prints 'run /compact now') or let tail-autorelay be the ONLY relay path and tell the tail to do nothing on hand-back messages, because every event re-reads the whole context.
- evidence: 2026-10-16 10:50-11:10: after the overlap handoff this tail handled about 25 turns (hand-backs from sfC, sfC2, op9l, hxA, hook blocks, a user question) at 300-330k tokens each, and manually re-relayed 4 agents that tail-autorelay had already relayed (duplicate relay files for sfC, sfC2, op9l, hxA).
- saving: roughly 25 x 300k tokens per handoff plus 4 duplicate relays; the tail hard limit (400k) is reached sooner
- risk: low if /compact keeps the tail routing notes (they are in the ledger)
- hooks: no
- weakens: no
- added: 2026-10-16 11:11
- moment: 12:30 tail #15 asked me to respawn op14/op22 from relays it had to read itself
- last_review: coordinator-16
- log: 2026-10-16 11:11 review 'coordinator-14-tail': added
- log: 2026-10-16 12:52 review 'coordinator-16': open -> confirmed (applies: 2026-10-16 12:00-12:50: the old tail at about 300k context relayed 9 finished agents (sfP, sfR, sfU, sfS, ctxfix, fxC2, op13, op21, op9n) by hand because tail-autorelay did not fire; imm26-wk2 now ...)
- log: 2026-10-16 14:57 confirmed -> in-progress (Shay: keep adding new ideas while these are built)

### PI-42 | in-progress
- idea: Cap read-only investigator/classifier agents at 3 rows (or ~120k tokens) in the brief and give them a hard 'checkpoint the table row-by-row into the report file' rule; four of four classifiers this session (fxB 4/5 rows, fxC 2/5, sfK, sfK2) hit the 200k limit before delivering the final table and needed a respawn.
- evidence: 2026-10-16 11:48 fxB and 11:49 fxC STOPPED-CONTEXT with 4/5 and 2/5 rows done, 11:10 sfK and 11:27 sfK2 stopped; each respawn re-reads its predecessor handoff (~15-25k tokens).
- saving: ~4 respawns per session, ~80k tokens plus ~10 min each
- risk: low: only splits briefs; more agents run in parallel
- hooks: no
- weakens: no
- added: 2026-10-16 11:52
- moment: 12:46 pilotA stopped before pilot-audit.py; 11:59 sfR stopped with nothing committed
- last_review: coordinator-16
- log: 2026-10-16 11:52 review 'coordinator-15': added
- log: 2026-10-16 12:52 review 'coordinator-16': open -> confirmed (applies: 2026-10-16 11:59-12:46: sfP, sfR, sfU, ctxfix and pilotA all stopped at about 205k with unfinished work packages; each needed a respawn that re-read the predecessor handoff (5 respawns, about 5 x 4...)
- log: 2026-10-16 14:57 confirmed -> in-progress (Shay: keep adding new ideas while these are built)

### PI-43 | in-progress
- idea: setupfail.ps1 mark should print the newest recipe/ready note for that row (state ready, owner, runner command) and warn when the marking lane still runs the OLD runner; a stale SETUP-FAIL for 20-d arrived at 11:47 although sfJ had published reload-run-sfj.sh at 11:22.
- evidence: 11:47 setupfail-20-d.msg from 5090-i3 (old recipe text) re-woke the coordinator after the sfJ recipe was already routed; same shape for 26-e at 11:43.
- saving: ~3 wakes per session, avoids re-spawning an investigator for a solved row
- risk: low: output-only change
- hooks: no
- weakens: no
- added: 2026-10-16 11:52
- moment: 12:10 setupfail-08-d.msg for a row whose recipe sfS had just delivered
- last_review: coordinator-16
- log: 2026-10-16 11:52 review 'coordinator-15': added
- log: 2026-10-16 12:52 review 'coordinator-16': open -> confirmed (applies: 2026-10-16 12:10 and 12:14: SETUP-FAIL 08-d and 15-bx notices woke me while the 08-d v2 recipe (sfS+sfT) and the 15-bx v2 scene (sfU2) were already built; each wake cost one model turn plus a ticke...)
- log: 2026-10-16 14:57 confirmed -> in-progress (Shay: keep adding new ideas while these are built)

### PI-45 | in-progress
- idea: lane-brief.ps1 should not refuse to write the brief when it is a few bytes over the 14500 limit (4080-i3/i4 briefs came out 14548 B and 15996 B): shrink the optional blocks further or write the file and only warn, instead of exit 1/2 with no file, which forced -MaxBytes 16000 retries and a PowerShell-vs-Git-Bash path detour.
- evidence: 2026-10-16 12:25-12:45: lane-brief.ps1 4080-i4 and 4080-i3 printed OVER LIMIT and wrote nothing at the default limit; each needed 2-3 extra tool calls (about 15k tokens of coordinator context each).
- saving: about 15k tokens per operator respawn, fewer failed spawns
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 12:52
- moment: 13:02 hk2 spawn, 13:16 4080-i4op15, 13:22 5090-i3op22
- last_review: coordinator-17
- log: 2026-10-16 12:52 review 'coordinator-16': added
- log: 2026-10-16 13:56 review 'coordinator-17': open -> confirmed (applies: 2026-10-16 13:00-13:50: lane-brief.ps1 printed OVER LIMIT and wrote nothing at the default 14500 limit for 5090-i4, 5090-i3, 5090-i5, 4080-i4 and 4080-i3; every spawn needed a second call with -Max...)
- log: 2026-10-16 14:57 confirmed -> in-progress (Shay: keep adding new ideas while these are built)

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

### PI-18 | done
- idea: Tail Stop hook: let a tail end once every owned agent is DONE and its relay file was delivered (or after a 5 min ack grace), without requiring the explicit tail-ack.
- evidence: 2026-10-15 19:52-20:10: coordinator #8 tail waited for the ack of imm26-5090-i5-op6; its Stop hook re-prompted ~50 times, each replaying ~400k context, until the tail hit its 400k limit and left with tail-mode leave -Force.
- saving: ~50 wasted turns (tens of millions of cache-read tokens) per overlap handoff
- risk: a result could be dropped if delivery is marked without the new coordinator reading it; keep the ack for the ledger but do not hold the tail on it
- hooks: yes
- weakens: no
- added: 2026-10-15 19:57
- measured: tail-hooks selftest 16 new PI-18 cases PASS (A: relay delivered / 5 min grace / not-relayed / RUNNING / pre-DONE relay / FAILED / ledger ack; C: blocks 1-3 plain, 4-6 'ONE long background wait', 7th let through + cap-ends.log, change restarts count); tail-ledger 33/33, tail-close 73/73, waker-lanes 15/15, hook-command, agent-guard 75/75 all pass; settings.json Stop+PreToolUse guard entries intact
- retired: 2026-10-15 built
- log: 2026-10-15 19:58 Shay answered yes

### PI-13 | done
- idea: Run every selftest at each handoff (selftest-all.ps1: agent-guard, tail-*, process-ideas, event-wait, rowtools, session-start-budget) and make selftests use fixtures, never live state.
- evidence: 2026-10-15 two selftests drifted silently: process-ideas-selftest 2d/8a failed once the live idea list changed, and agent-guard 'event-sweep.sh LF only' had failed unnoticed since be37f58 because event-sweep.sh line 39 had a mangled rollcall path (backslash-t and backslash-a became control characters) so the waker roll call returned nothing and every stall check failed open for hours.
- saving: catches a broken waker/hook script the same hour instead of hours later; ~5 min per handoff
- risk: low; selftests that start games or take > 2 min must be skipped by a flag
- hooks: no
- weakens: no
- added: 2026-10-15 18:51
- moment: 19:36 hookq ran the full selftest set after its hook edit and discovered the pre-existing failure only because it ran everything.
- last_review: coordinator8-19:50
- measured: 33 tests (32 default ~6 min + rowtools slow 3.5 min), 5 FAIL found at first run (agent-session-hooks, spawn-wp-session, imm26-assert no-assert, rowtools heartbeat leak/WSL path, rowtools-trip CRLF) all fixed, 33/33 pass; also found selftest leaking a fake RUNNING hbagent into live agents dir
- retired: 2026-10-15 built
- log: 2026-10-15 18:51 review 'coordinator #7 handoff 2026-10-15': added
- log: 2026-10-15 18:52 asked Shay
- log: 2026-10-15 19:43 review 'coordinator8-19:50': asked -> confirmed (applies: imm26-hookq found agent-session-hooks-selftest meter-coordinator-text failing the same way on the untouched original hook: a drifted selftest nobody ran.)

### PI-21 | done
- idea: Open-alert ledger: every urgent waker event (LANE IDLE, LANE NO-OPERATOR, AGENT STALL/ORPHANED, DEAD, KILLED, FAILED, 402) is written to C:\KenshiTestRuns\alerts\open\<id>.json and stays open until alert-ack.ps1 <id> '<action taken>' is run or the condition clears by itself (lane-idle OK, agent DONE); a PostToolUse reminder prints 'OPEN ALERTS n: oldest <min>' after tool calls while any alert is older than 3 min; the Stop hook blocks the coordinator from ending a turn with an unacked alert older than 5 min; operators get their own lane alerts in their inbox with the same ack.
- evidence: 2026-10-15 20:0x: waker event 'LANE IDLE 4080-i4 7m' arrived while I was mid-edit and I did not act on it; I only found the 5090-i4 lane idle 16.7 min after Shay asked 'are we running tests on all lanes'. The waker alerts once and nothing tracks whether anyone acted.
- saving: removes silent ignored alerts; catches a blocked lane within one alert cycle instead of when Shay asks (the 5090-i4 lane lost ~17 min)
- risk: adds a Stop block, so a stale or false alert must clear itself or be ackable with a reason, otherwise it loops turns (see the PI-18 tail loop); it must never be able to hide an alert, ack only closes it
- hooks: yes
- weakens: no
- added: 2026-10-15 20:04
- measured: alert-ledger-selftest 40 cases PASS (open, rate limit, ack, auto-clear, stop block 5 min, loop cap, tail/subagent exempt, one-line reminder); selftest-all 32 pass/1 pre-existing fail (session-start-budget live size); live scan opened real alerts lane-idle-5090-i4 and lane-no-operator-5090-i5; hook command verified through Git Bash
- retired: 2026-10-15 built
- log: 2026-10-15 20:05 Shay answered yes

### PI-22 | done
- idea: An operator may not mark itself DONE while its lane still has non-PASS rows: only STOPPED-CONTEXT (with a successor started first) or DONE with an explicit 'lane complete' note; lane-idle/agent-status refuse otherwise.
- evidence: 2026-10-15 20:28 imm26-4080-i4op7b set DONE with 19-ax, 10-a, 10-b, 08-d still open and marked nothing; the 4080-i4 lane had no operator until I noticed the DONE event and respawned imm26-4080-i4op7c (about 10 min of lane time).
- saving: ~10 idle lane-minutes per early DONE
- risk: a legitimately finished lane needs a way to say so (the lane complete note)
- hooks: no
- weakens: no
- added: 2026-10-15 20:31
- measured: rule added to lane-brief.ps1 standing rules (commit this session); detection already by PI-21 lane-no-operator alert; lane-brief selftest OK
- retired: 2026-10-15 built

### PI-23 | done
- idea: A GATED / 'needs a native build' claim must cite a search for the NATIVE names (event types, fields in the DLL sources), not the server's words; the setupfail ticket for it carries the search command.
- evidence: 2026-10-15 row 10-d sat GATED as 'no native exact-transfer event' because earlier agents grepped the DLL for the server words restitution/exact_transfer; imm26-inv-10d found SocialExactTransferEvidence already shipped in NC6/9/10 (main.cpp:7048) and the real blocker was an unstaged caught theft. It cost three operators' attempts and a planned native build (NC11, ~150k tokens).
- saving: avoids an unneeded native build plan (~150k tokens) and several operator attempts
- risk: none
- hooks: no
- weakens: no
- added: 2026-10-15 20:31
- measured: rule added to lane-brief.ps1 (grep native names before GATED); lane-brief selftest OK
- retired: 2026-10-15 built

### PI-24 | done
- idea: Rerun rows get a row script (go-row.sh row definition) before the SECOND manual run; the first operator to hand-run a row writes the rd_<row> from its steps.
- evidence: 2026-10-15 imm26-5090-i4-hard2b ran 17-bx 18-cx 16-bx 15-bx 13-ax 02-ax by hand (no row scripts) and hit its context limit before starting any rerun; its report names this as the next speed-up. 19-d took 6 attempts across scripts.
- saving: ~60k tokens per hand-run row and fewer lost reruns
- risk: row scripts must keep the exact assertions (never weaken)
- hooks: no
- weakens: no
- added: 2026-10-15 20:31
- measured: rule added to lane-brief.ps1; rowtools4 agent building one-call row scripts for 17-bx 18-cx 16-bx 15-bx 13-ax 02-ax
- retired: 2026-10-15 built

### PI-26 | done
- idea: Every Agent-tool spawn gets a RUNNING status file immediately (the agent-router hook writes agents/<name>.status with the task text from the prompt) so a young agent is never 'no status'.
- evidence: 2026-10-15 imm26-fix19 had no status file for ~45 min; the new coordinator took it for never-started and spawned a duplicate imm26-fix19b (two agents on rowcheck.py/rowdefs.sh) until the tail answered; imm26-pi13 was flagged ORPHANED at 30 min because its status still said 'start'.
- saving: avoids duplicate agents and false orphans (~1 duplicate and 1 false alarm this session)
- risk: the router must use the same task text a successor will copy (agent-guard rule b)
- hooks: yes
- weakens: no
- added: 2026-10-15 20:51
- measured: hook version NOT built (a pre-written RUNNING status could mask a never-started agent); replaced by the coordinator rule in AGENT_PROMPTS block C: check ListAgents/ledger owner before duplicating
- retired: 2026-10-15 built

### PI-25 | done
- idea: Automatic tail relay: a script (tail-autorelay) waits on the tail's owned agents and, when one reaches DONE/FAILED/STOPPED-CONTEXT, writes the TAIL-RELAY inbox file from the agent's agents/out/<name>/latest.md or handoff itself (no LLM turn); the tail then has nothing to do and its Stop hook passes 5 min after the relay file (PI-18).
- evidence: 2026-10-15 20:00-21:00 (tail phase): the tail needed ~7 wait cycles and ~40 Stop-hook blocks (each a model turn replaying the tail context) plus 8 hand-written relays of ~2.5k tokens each (wpR3, pi13, wpR2, wpR1, i5-op7, pi21, i3-hard2b, fix19) to move results the coordinator's waker could already see as inbox files.
- saving: ~40 wasted turns and ~20k tokens of manual relays per overlap handoff; the tail context stops growing
- risk: a relay without a model summary may miss a decision for Shay: keep the first 30 lines of latest.md plus any line starting DECISION/QUESTION
- hooks: no
- weakens: no
- added: 2026-10-15 20:51
- measured: tail-autorelay-selftest 24/24 PASS; tail-close/hooks/ledger selftests green (selftest-all -Only tail-*: 4 pass / 0 fail)
- retired: 2026-10-15 built

### PI-28 | done
- idea: Tail Stop hook: while a tail's own background wait / waker process is alive and armed, let the turn END (the session idles and wakes on the background task's completion notification) instead of blocking; block only when the tail has NO armed wait. No per-block replies at all.
- evidence: 2026-10-15 20:00-21:00 tail phase: with agents running the Stop hook blocked the tail every turn end even though an until-loop wait was armed; PI-18 only capped it at 6 unchanged blocks per cycle, so each of ~7 wait cycles still produced ~6 near-identical 'Stop hook feedback' messages (about 40 turns, each a model reply replaying the ~400k tail context); a restart of the wait re-armed the counter.
- saving: ~40 spam turns per overlap handoff (the largest remaining tail cost) and no tail context growth while idle
- risk: a tail with no armed wait or a dead waker must still be blocked; verify the wait process is alive (pid/heartbeat) rather than trusting a flag
- hooks: yes
- weakens: no
- added: 2026-10-15 20:55
- moment: each of ~7 wait cycles produced ~6 near-identical block turns
- last_review: coordinator-10 handoff
- measured: tail-hooks selftest 69 PASS (19 new PI-28 cases: armed->end, no wait/dead pid/stale hb/corrupt file/foreign wait/armed-before-flag/agent needs relay->block, coordinator unaffected); tail-ledger, tail-close, waker-lanes, agent-guard, agent-session-hooks, alert-ledger, hook-command, agent-router, tail-autorelay all PASS; settings.json untouched
- retired: 2026-10-15 built
- log: 2026-10-15 21:10 review 'coordinator-10 handoff': open -> confirmed (applies: 2026-10-15 20:00-21:00 tail phase: ~40 Stop-hook spam turns while a wait was armed; Shay told the coordinator to do the sensible PIs; imm26-pi28 building with fail-closed selftests)

### PI-27 | done
- idea: A tail runs only a FILTERED waker (its own agents' status changes), not the full event stream; or none if tail-autorelay exists.
- evidence: 2026-10-15 the tail received LANE IDLE, wpR3-deploy, inv19d and other events it cannot act on (spawn/decide nothing) and each one cost a turn; both Monitor wakers also died with exit 1 at ~20:36 and had to be replaced by hand.
- saving: a few turns per hour and no waker re-arming
- risk: none
- hooks: no
- weakens: no
- added: 2026-10-15 20:51
- moment: 21:00 the tail's two wakers died while 5 agents ran
- last_review: coordinator-10 handoff
- measured: docs part in AGENT_PROMPTS block B: tail arms ONE tail-wait.ps1 over its owned agents (exit on DONE|FAILED|STOPPED-CONTEXT/needs relay), block message says never reply per block; selftest PI-27/28 case PASS
- retired: 2026-10-15 built
- log: 2026-10-15 21:10 review 'coordinator-10 handoff': open -> confirmed (applies: 2026-10-15 the old tail received LANE IDLE/deploy events it could not act on and both its Monitor wakers died with exit 1; folded into imm26-pi28 (tail-wait.ps1 over own agents' status files))

### PI-30 | done
- idea: Row-builder / tooling work packages must be sized to <= 4 rows (or one phase) per agent: split a 9-row build into 2-3 agents (defs+checker | selftest+fakes | TESTS rows+operator note) and commit after each phase, not at the end.
- evidence: 2026-10-15 imm26-reloadrows-A (9 rows) and -B (6 rows) each ran to ~215k tokens (target 120k) and stopped with NOTHING committed and the selftest never run; two successors had to re-read ~40k of handoff each.
- saving: ~80k tokens and one respawn per oversized builder
- risk: more agents touching the same rowtools dir: keep new files per agent
- hooks: no
- weakens: no
- added: 2026-10-15 21:10
- moment: 21:39 when rowtools43 stopped: splitting item 4 into 2-3 rows per agent would have finished the selftest in the same agent and avoided the extra rowtools44 spawn
- last_review: coordinator-11
- measured: rule added to docs/WP_SIZING.md section 2 (<=4 rows/agent); before: 9-row builders ran ~215k tokens with nothing committed; effect measured at the next row-tool package
- retired: 2026-10-16 built
- log: 2026-10-15 21:10 review 'coordinator-10 handoff': added
- log: 2026-10-15 23:16 review 'coordinator-11': open -> confirmed (applies: 2026-10-15: imm26-rowtools4 (7 items) stopped at ~203k with items 4-7 undone; its successor imm26-rowtools43 (item 4 alone, six rows) also hit ~204k in 10 minutes and finished only the code, not se...)

### PI-32 | done
- idea: lane-brief.ps1 (or the operator spawn) records the kenshi-ctl idle reason 'operator spawned, lane launching' automatically for 15 min so the Stop hook does not demand one by hand
- evidence: 2026-10-15 22:40, 22:41 and 22:45: the Stop hook blocked three times right after spawning a 5090 operator because the 5090 was momentarily idle; each needed a manual kenshi-ctl idle
- saving: 3 turns
- risk: low if the reason expires in 15 min and is cleared when a game starts
- hooks: yes
- weakens: no
- added: 2026-10-15 23:16
- moment: 00:31 when op9f stopped: the lane had no operator for ~10 min while imm26-26a-recipe investigated; an automatic idle reason from lane-brief/agent status would have saved the manual step each time
- last_review: coordinator-12
- measured: lane-brief.ps1 -Name now records a 15-min 'lane launching' rig idle reason (beebc6d); tested 2026-10-16 10:03 on 5090-i5: file written, mtime backdated 45 min so it lapses after 15 min; before: 3 manual idle reasons per session (00:30, 01:00, 01:45), after: 0
- retired: 2026-10-16 built
- log: 2026-10-15 23:16 review 'coordinator-11': added
- log: 2026-10-16 02:55 review 'coordinator-12': open -> confirmed (applies: 2026-10-16 00:30, 01:00, 01:45: after each 5090 operator stopped I had to record kenshi-ctl.ps1 idle by hand to keep the Stop hook quiet while a fixer was building (op9f, op9g, op9h gaps).)

### PI-33 | done
- idea: The Stop hook's successor check must accept ANY successor registered via lane-brief.ps1 -Name/-Predecessor (lane-owners.json), not only <name>2/<name>b suffix names; or lane-brief should register the successor so the hook stops asking for 'imm26-4080-i4op10b' when 'imm26-4080-i4op11' already runs.
- evidence: 2026-10-16 00:21 (op9e->op9f), 01:28 (i4op10->op11), 00:50 (op9f->op9g): the Stop hook blocked three times asking to respawn a fresh <name>b although the real successor (different number) was already RUNNING; each cost a model turn and an agent-abandon.ps1 call.
- saving: ~3 blocked stops + 3 abandon calls per coordinator session (~6k tokens)
- risk: must not hide a truly unowned stopped agent: only accept successors whose status task text equals the predecessor's
- hooks: yes
- weakens: no
- added: 2026-10-16 02:55
- moment: 10:38 when sfE2 stopped and sfE3 was already running (hook demanded sfE2b)
- last_review: coordinator-14
- measured: agent-guard-lib rule (f) + 5 selftest cases, agent-guard-selftest 80/80; live effect not yet measured
- retired: 2026-10-16 built
- log: 2026-10-16 02:55 review 'coordinator-12': added
- log: 2026-10-16 10:49 review 'coordinator-14': open -> confirmed (applies: 2026-10-16 10:3x: the Stop hook asked to respawn imm26-sfE2b / imm26-sfB2 style names although the real successor imm26-sfE3 (different suffix) already ran with the same task text; cost one agent-a...)

### PI-34 | done
- idea: Provide one wrapper `rearm-waker.ps1` (or fold into event-wait.sh) that kills any stale event-wait for this coordinator, then prints the exact run_in_background command; and make event-wait.sh refuse to start under a bare & / disown.
- evidence: 2026-10-16: I started the waker with a trailing `&`/disown by mistake 5 times (01:13, 01:29, 02:09, 03:25, 04:35), each needed a pkill and a relaunch; the runbook says never.
- saving: ~5 wasted tool calls and a wrongly-running waker the Stop hook does not recognise
- risk: low: wrapper only starts/kills event-wait processes owned by this coordinator
- hooks: no
- weakens: no
- added: 2026-10-16 02:55
- moment: 10:27 when I ran event-wait.sh with & disown right after registering the i3 operators
- last_review: coordinator-14
- measured: tools/automation/rearm-waker.ps1 kills stale event-wait and prints the exact command; bare-& refusal in event-wait.sh not built (not detectable); live effect not yet measured
- retired: 2026-10-16 built
- log: 2026-10-16 02:55 review 'coordinator-12': added
- log: 2026-10-16 10:49 review 'coordinator-14': open -> confirmed (applies: 2026-10-16 10:27 I started the waker with a trailing & disown by mistake (the exact failure PI-34 describes) and had to pkill it and restart; also the waker had to be restarted ~25 times after each...)

### PI-36 | done
- idea: Give in-session lane operators a routable address (or have the coordinator tool write a per-lane inbox file AND a bump the operator sees): SendMessage to a live operator by name returns 'not reachable', so operator notes in inbox/operators only reach an operator if it happens to poll.
- evidence: 2026-10-16 10:2x: SendMessage to imm26-5090-i5-op9l and imm26-4080-i4op12b failed with 'No agent named ... is reachable'; 6 inbox notes (nc17/nc18/nc20, 14d, lane plan, deploys) relied on the operators polling.
- saving: avoids a lane running a stale plan for up to a row (~15 min) each time a fix lands
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 10:49
- moment: 10:25 trying to send the lane plan to imm26-5090-i5-op9l and imm26-4080-i4op12b
- last_review: coordinator-14-tail-closing
- measured: agent-ids.ps1 registry built and tried (add/get/list); live effect not yet measured
- retired: 2026-10-16 built
- log: 2026-10-16 10:49 review 'coordinator-14': added
- log: 2026-10-16 10:56 asked Shay
- log: 2026-10-16 11:18 review 'coordinator-14-tail-closing': asked -> confirmed (applies: 2026-10-16 tail period: SendMessage by NAME to live operators failed, but by agent id it worked (hxA, three operators at the hard limit); the tail/coordinator only knows ids from the spawn result.)

### PI-40 | done
- idea: Waker/event-wait should not wake the coordinator for 'EVENT STATUS <agent> DONE' of an in-session subagent: those agents always deliver a hand-back message plus a task notification, so the waker event is a third, duplicate wake. Wake only for what has no other channel (inbox, lane/rig alerts, stalls, orphaned or dead agents).
- evidence: 2026-10-16 10:00-10:50 (coordinator 14, 250-300k context): about 35 waker restarts; for sfA, sfB2, sfD2, sfE3, sfF, sfG, sfG2, sfH, hxB, inv-14e each completion arrived three times (waker EVENT STATUS DONE, SubagentHandback message, task-notification) and each wake was a model turn.
- saving: about 10 duplicate turns per 10 agent completions (about 10 x 280k tokens), and fewer waker restarts
- risk: must keep waking for FAILED/STOPPED-CONTEXT, and for background-job (non-subagent) agents
- hooks: no
- weakens: no
- added: 2026-10-16 11:11
- moment: 11:38 sfK2 DONE and 12:05 bundle DONE wakes right after I had committed/routed their results
- last_review: coordinator-15
- measured: event-wait.sh EW_QUIET_DONE default 1, batch selftest 26/26 (7 new cases), filter selftest 13/13; live effect not yet measured
- retired: 2026-10-16 built
- log: 2026-10-16 11:11 review 'coordinator-14-tail': added
- log: 2026-10-16 11:52 review 'coordinator-15': open -> confirmed (applies: 2026-10-16 10:51-12:20: the waker ended ~25 times; at least 12 of those wakes were only 'EVENT STATUS <agent> DONE' or a duplicate TAIL-RELAY for an agent I had already handled (op9m DONE after I s...)

### PI-29 | rejected x2
- idea: At the tail hard limit the context meter should call tail-close.ps1 (sends 'tail done', then closes the session and window ~20 s later) once all owned agents are checkpointed/relayed, instead of telling the tail to run tail-mode.ps1 leave -Force (which only removes the flag, leaving the session and window open). tail-close's window-kill must first be tested on a real throwaway window.
- evidence: 2026-10-15 ~21:07 old tail session 6d1f3011 followed the meter message, ran tail-mode.ps1 leave -Force at its hard limit: the flag went away but the session process and window stayed open (tail-close.ps1 then refuses with 'no tail flag'); the window-closing path of tail-close was never exercised on a real window.
- saving: no orphan idle tail windows per overlap handoff; the tail context stops being resumable by accident
- risk: kills a session: only after every owned agent is DONE and acked; the meter is a global hook (~/.claude/hooks/context-meter.ps1), so Shay decides
- hooks: yes
- weakens: no
- added: 2026-10-15 21:07
- last_review: coordinator-12
- log: 2026-10-16 02:55 review 'coordinator-12': open -> rejected x1 (does not apply: 2026-10-16: tail 2a0cfe9b closed itself via tail-ack.ps1 (all agents done+acked -> tail-close in 20 s) without any hard-limit case; no tail reached its limit this session.)

### PI-31 | rejected x2
- idea: AGENT ORPHANED must not fire for in-session (Agent-tool) subagents of a live coordinator or live tail: check the agent against the session's own agent list / ledger owner before alerting
- evidence: 2026-10-15 21:24 and 21:40: AGENT ORPHANED imm26-fix10a and imm26-fix03b were false alarms (both alive, only blocked on a test lock); each cost 2-3 turns of investigation, one almost led to a wrong respawn
- saving: about 3 turns per false alarm, avoids a duplicate respawn
- risk: must not hide a real dead agent: keep the alert when the owning session is gone
- hooks: yes
- weakens: no
- added: 2026-10-15 23:16
- last_review: coordinator-12
- log: 2026-10-15 23:16 review 'coordinator-11': added
- log: 2026-10-16 02:55 review 'coordinator-12': open -> rejected x1 (does not apply: 2026-10-16 00:00-05:00: no AGENT ORPHANED alert fired this session; only legitimate STOPPED-CONTEXT events.)

### PI-35 | rejected x2
- idea: mark-row.py needs a note-only mode (append a note to the evidence column without changing status), so row-tooling agents can annotate rows without overwriting results.
- evidence: 2026-10-16 imm26-u-rowsA2 report: mark-row.py has no note-only mode, it always overwrites status and evidence, and a SETUP-FAIL re-mark needs a needs: clause and updates the unblock ticket, so none of the three tooling agents (rowsA/B/C) could add the one-call command to the row.
- saving: one operator lookup per row (inbox note instead of the row)
- risk: low: new flag only
- hooks: no
- weakens: no
- added: 2026-10-16 02:55
- last_review: coordinator-14
- log: 2026-10-16 02:55 review 'coordinator-12': added
- log: 2026-10-16 10:49 review 'coordinator-14': open -> rejected x1 (does not apply: not seen this session)

### PI-55 | rejected x2
- idea: Row runners must refuse to start under WSL bash (check for the /mnt/c mount or uname) and the lane operators' briefs must say 'row scripts run in Git Bash, only wsl.exe tools get MSYS_NO_PATHCONV', because a row script run under WSL silently creates a stray /c/KenshiTestRuns tree inside WSL that then shadows the real path for tools that probe /c first.
- evidence: 2026-10-16 15:26: stray empty /c/KenshiTestRuns/imm26-4080/rows appeared in WSL during 4080-i3op24's 22-b RELOAD-FAIL; it made pilot-audit.py pick /c/... over /mnt/c/... (pilot rows=0) until I passed --pilot-dir.
- saving: about 20 minutes of misdiagnosis per occurrence, plus a false RELOAD-FAIL
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 14:57
- last_review: coordinator-21
- log: 2026-10-16 14:57 review 'coordinator-18': added
- log: 2026-10-16 18:01 review 'coordinator-21': Open -> rejected x1 (does not apply: no stray WSL rows dir this session)

### PI-47 | done
- idea: Lane operators should auto-spawn their own successor ticket: when an operator writes STOPPED-CONTEXT, the lane sits idle until the coordinator turn notices; add an 'idle-lane' fast path that prints the exact lane-brief + Agent spawn text for the new coordinator in the wake event.
- evidence: 4080-i4 and 4080-i3 lanes sat idle 5-10 min at 12:30-12:40 until I messaged the new coordinator; 5090-i3 ended with no rows left.
- saving: ~5-10 lane-minutes per operator turnover (about 8 turnovers per session)
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 13:05
- moment: 17:50: after op18 26-f SETUP-FAIL I generated brief op19 and spawned it by hand, a 3-call routine.
- last_review: coordinator-21
- measured: built 5af59550 (swept into PI-53 commit): LANE NO-OPERATOR line now carries lane-brief command + Agent spawn prompt (selftest lane-successor-selftest 13/13); measured saving pending next turnovers (was 3 calls / 5-10 lane-min)
- retired: 2026-10-16 built
- log: 2026-10-16 13:05 review 'coordinator-15-tail': added
- log: 2026-10-16 18:02 review 'coordinator-21': Open -> confirmed (applies: 2026-10-16 16:55-17:55: 8 lane briefs generated and 8 successor operators spawned by hand (5090-i3 op28-op31, 5090-i5 op15-op17, 4080-i3 op27-op29, 4080-i4 op18-op19), each after reading a hand-back.)

### PI-50 | done
- idea: Deliberately parked lanes (operator finished, nothing claimable until fixer candidates land) should auto-enter lanes.held when the operator is abandoned with a 'parked' reason, and leave it when a new operator status appears; today the digest waker still wakes on LANE IDLE/NO-OPERATOR every ~6 min per parked lane.
- evidence: 13:30-13:50: LANE IDLE 5090-i3 (twice), LANE NO-OPERATOR 4080-i3 (twice), LANE IDLE 4080-i4: five coordinator turns of about 270k tokens each, plus three manual alert-ack calls, until I hand-edited lanes.held.
- saving: about 5 turns x 270k tokens per hour while lanes are parked
- risk: a lane parked by mistake hides a real stall: the hold must carry the abandon reason and expire after 2 h
- hooks: no
- weakens: no
- added: 2026-10-16 13:56
- moment: 17:12: lane-idle-5090-i5 re-fired 7 min after I had acked it and woke the waker again.
- last_review: coordinator-21
- measured: built 6750c86a: agent-abandon 'parked:' -> lanes.held 2 h hold with reason, released by new RUNNING operator / lane-brief -Name (selftest lane-hold-selftest 16/16); measured saving pending (was ~5 coordinator turns/h while parked)
- retired: 2026-10-16 built
- log: 2026-10-16 13:56 review 'coordinator-17': added
- log: 2026-10-16 18:02 review 'coordinator-21': Open -> confirmed (applies: 2026-10-16 17:00-18:00: seven LANE IDLE / NO-OPERATOR alerts for lanes parked on purpose (5090-i3, 5090-i5, 4080-i3, 4080-i4) each needing a manual alert-ack, and each re-woke the waker.)

### PI-53 | done
- idea: Guard path arguments against Git Bash backslash stripping: lane-brief.ps1 (and other -Out/-Path scripts) should reject or auto-fix an -Out value without a drive-letter colon+separator, and print the resolved absolute path it wrote.
- evidence: 2026-10-16 14:00-14:35: three lane briefs (4080-i4op16, 5090-i3op23, 4080-i3op24) were written to C:\KenshiModding\KenshiTestRunsagents...brief.md because bash dropped the backslashes in -Out C:\\...; the operators started without their briefs and the same stray file name was already untracked in git status for op14.
- saving: about 3 operators x 1 missing-brief start, plus a hunt through 3 tool calls
- risk: low
- hooks: no
- weakens: no
- added: 2026-10-16 14:57
- moment: 17:58: the ssh delete loop with unquoted read removed nothing for 3 attempts.
- last_review: coordinator-21
- measured: Before: 3 lane briefs written to stray C:\KenshiModding\KenshiTestRunsagents*.brief.md by Git Bash backslash stripping (operators started without brief). After: lane-brief/cost-audit -Out guard (path-guard-lib.ps1) refuses relative/separator-less paths (exit 2), auto-fixes the known stripped form, prints the resolved absolute path; 5 selftest cases PASS (commit 5af59550).
- retired: 2026-10-16 built
- log: 2026-10-16 14:57 review 'coordinator-18': added
- log: 2026-10-16 18:02 review 'coordinator-21': Open -> confirmed (applies: 2026-10-16 17:45-18:05: tail-ack.ps1 and Git Bash ssh/read loops lost backslashes: 'read p' without -r produced C:KenshiTestRunslogs... paths (ssh deletes failed), `ssh` in a while-read loop swallo...)

### PI-57 | done
- idea: A subagent that waits on its own background job (selftest) must not re-send its full final report each time it wakes: dedupe hand-backs by content hash in the harness/tail relay, or have the agent hand back once and stay silent until its job finishes.
- evidence: 15:09-15:25: imm26-regionR4 sent the same 'WP-R4 DONE' report 7 times (each waking this coordinator, 6 full-context turns of about 5-8k tokens) while its two slow selftests ran.
- saving: about 40k tokens and 6 turns per such agent
- risk: none for monitoring: only identical repeated reports are dropped
- hooks: no
- weakens: no
- added: 2026-10-16 15:42
- moment: tail turns after the 4080-i3op25 and 5090-i3op25 hand-backs
- last_review: efc58758-86f8-4786-a138-4e53f075016d-tail
- measured: Before: one agent re-sent the same DONE report 7 times (~6 turns, ~40k tokens). After: tail-relay.ps1 drops an identical DONE/FAILED/QUESTION/PEER relay (content hash, same agent, 2 h) and logs it; AGENT_PROMPTS says hand back once; tail-relay-dedupe-selftest 10/10 PASS plus tail-ledger 33/33, tail-cheap 28/28, tail-autorelay 24/24 PASS.
- retired: 2026-10-16 built
- log: 2026-10-16 15:42 review 'coordinator-19': added
- log: 2026-10-16 16:14 review 'efc58758-86f8-4786-a138-4e53f075016d-tail': Open -> confirmed (applies: 2026-10-16 tail period: each of the 5 owned agents (i5-op10, fix26f2, 4080-i3op25, 5090-i3op25, replayexec) woke the tail twice, once by the hand-back message and once by the task-notification, eac...)
