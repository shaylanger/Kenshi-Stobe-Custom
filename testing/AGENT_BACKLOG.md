# AGENT BACKLOG: work the coordinator can start without Shay (Shay 2026-10-16)

RULE: every time an agent slot is free, start the TOP READY item below. Slot test (check at every waker event and after every agent result):
`ListAgents` live subagents + replay runs in flight <= 17 (the session cap is 20 concurrent). The ordered Haiku pair test (replay2, `imm26-hpairexec11`) has priority over everything: never take its slots; if the replay runs show cap refusals, start nothing.
Keep this file current: set state to STARTED (agent name + id) when spawned, DONE when its result is handled, add new items the moment they appear. Items marked WAIT need a result or a Shay answer first (not startable). Agent type per item: investigate -> kenshi-debugger `[case:investigate]`; fixer -> `[case:generate]`; operator -> `[case:generate]` + lane-brief.ps1; one fixer per ticket (PI-61); size per docs/WP_SIZING.md.

| # | item | type | state | spawn spec / notes |
|---|---|---|---|---|
| 1 | 26-f post-load ClearGroup resume (a clear-group order must resume after save/load; Shay rule "everything resumes after save/load") | investigate `imm26-inv26f` | STARTED 21:00 `imm26-inv26f` (a4f1d1ac05b34af9f) | Evidence: testing/NPC_IMMERSION_26_TESTS.md row 26-f, KNOWN_BLOCKERS; ask for root cause + patch diff, no edits |
| 2 | 23-a native arrival tolerance fix | fixer `imm26-fix23anative` | WAIT inv23a (a80058b9dd5461884) result | also folds in the recipe nit: skip stage-landing check when Cind x/z moved > 1000; then op for 5090-i3 reruns 23-a (`unblockrun_23a2.sh`) |
| 3 | 14-d SCENE-BAD (3 extra serials not near; far bandit lands in the near platoon) | fixer `imm26-fix14dtool3` | WAIT op21 report | fallback `--far-spawnt "<squad template>"`; evidence C:\KenshiTestRuns\inbox\setupfail*14-d* and set_probe.txt in the i5 rows dir |
| 4 | 13-c-neg (native, SETUP-FAIL ticket, setupfail.ps1 list) | investigate `imm26-inv13cneg` | READY | owner imm26-5090-i3op36 is gone; ticket age 17h+ |
| 5 | 15-bx / 17-bx variance | investigate `imm26-inv15bx17bx` | READY | note 15-bx split is a Shay decision (default yes in SHAY_DECISIONS); investigate why the rows vary run to run |
| 6 | operator for lane 5090-i3 | operator `imm26-5090-i3op38` | WAIT items 2 or 4 | spawn when a fixer lands a claimable row (alert lane-idle-5090-i3 acked until then) |
| 7 | 16-bx brevity (prompt trait line, option a) | fixer `imm26-fix16bxbrevity` | STARTED 21:12 (Shay decided a) | anchor patch in pending-fixes/imm26-fix16bxbrevity; note inbox\operatorsix16bxbrevity.txt; then an operator reruns 16-bx n=3 |
| 8 | PI-67 auto-close stale STOPPED-CONTEXT/FAILED markers when the row is PASS/reassigned | fixer `imm26-fixpi67` | READY (low priority) | agent-status/session-start/alert-scan; add selftest; hooks untouched |
| 9 | PI-68 stop a duplicate hand-back loop (agent waiting on own background work re-delivers its report) | investigate then fixer | READY (low) | evidence: imm26-replay2-interim loop ~190k tokens |
| 10 | PI-69 swap.ps1 template with every pending hook swap README | coordinator does it | READY (small) | pending-fixes/living-handoff-compact/swap.ps1 is the model |
| 11 | preflight.sh: treat isolation cache stale when lane-isolation-check*.ps1 is newer | coordinator, between lane runs | WAIT no running lane script | never edit a script a running list/batch uses |
| 12 | selftest-all-h24 (C:\KenshiTestRuns\selftest-all-h24.txt): 40 pass / 8 FAIL / 1 skip. FAILs: waker-persist (we rely on it!), imm26-assert, session-start-budget, event-stream, ctxfix, agent-successor, lane-successor, tail-close (25 known). Logs in C:\KenshiTestRuns\selftest\<name>.txt | triage then fixers (one per cause) | READY (medium: waker-persist and imm26-assert first) | a [case:read] reader summarises each FAIL line (cause vs live-state flake because lanes were running) -> one fixer per real cause; rerun individually with selftest-all.ps1 -Only if supported |
| 13 | headless `claude -p --model haiku` replay runner (Shay said YES 2026-10-16 ~21:10) | generate `imm26-fixrunner` | STARTED 21:10 (a3e57542bd04cc8ef) | new files only (toolsutomation\shadow-replay
eplay2-headless.py); must coexist with hpairexec11 (claim files); when verified: run the r2 remainder + r3 (+ graders if headless-capable) with it, tell hpairexec11 to stop issuing r2 |
| 14 | tail-close-selftest 25 pre-existing failures | fixer | PARKED | only matters if tail handoffs continue (auto-compact replaces them) |
| 15 | ab2 pilot cleanup + COMPARISON.md explanation | coordinator | WAIT imm26-ab2exec3 finishing (seq ~8/20) | README cleanup list in COORDINATOR_LIVE section 5 |
| 16 | replay2 FINAL FULL REPORT to Shay | coordinator | WAIT r2, r3, graders | section 3 of COORDINATOR_LIVE |

## PI queue (ideas waiting for a free slot in the 15-entry cap of docs/PROCESS_IDEAS.md; add them with process-ideas.ps1 add when a slot frees)
- Slot-test script: one command printing live subagent count + replay runs in flight (agent-rollcall counts) so the backlog slot rule is mechanical. Evidence: 2026-10-16 21:00 Shay asked 'how many subagents do you have' and I needed ListAgents + rollcall + reasoning; the 4080-i4 lane sat idle 27 min because nobody checked the slots.
- Executor agents for mass tiny model calls should be headless processes, not Task subagents (covered by PI-66's alternative; evidence: hpairexec2..10, nine executors for ~700 calls; headless runner now built).
