# COORDINATOR LIVE STATE (living document; Shay 2026-10-16)

PURPOSE: a fresh coordinator with ZERO context (after /compact, a crash or a new session) must be able to continue from this file alone,
because a compaction summary can lose things that cannot be recovered (Shay's exact orders, why a decision was taken, which agent does what).
RULES (docs/HANDOFF_STANDARD.md): rewrite the section that changed in the SAME turn as the event (agent result, Shay message, decision, new agent, install);
never append a "correction" paragraph, fix the line; commit + push it with the work; keep it under ~250 lines (history goes to archive/).
`tools/automation/handoff-snapshot.ps1` adds the mechanical state (agents, alerts, ledger, inflight) at every compaction: `C:\KenshiTestRuns\handoff-auto.md`.
ZERO-CONTEXT TEST before every compact: "could a new session do the next 10 things from this file + HANDOFF 'Right now' + SHAY_DECISIONS.md without asking anyone?"

Last updated: 2026-10-16 ~20:55 by coordinator #24 (session 7b068528-9019-4ad1-913a-ead9d4167d45). Tail of coordinator #23 (5161648d) CLOSED 20:47: it owns nothing; no tail exists now.

## 0. (cleared 22:08) LLM balance topped up by Shay; llm-health OK. Operators respawned: imm26-4080-i4op25 (afd2c7df286186938: 01-cx x3, 02-dx x3) and imm26-5090-i5-op22 (a1211dab5b1bd93e3: 14-d v2 rerun now, 19-e after fix19erecipe). fix14dserver DONE def07676. Compact #2 measured ($0.23, in docs/COMPACT_AUDIT.md); tell Shay.

- 22:12 inv26f DONE: camp ClearGroup never resumes (strict campZone equality in ActivityResume.php:115); fixer imm26-fix26fcamp (a4d7e70bf54475471) running; decision on bored-turn activity resume added to SHAY_DECISIONS. Also running: op32, hpairexec12, ab2exec3 (+arms), fix23agate, fix19erecipe, op25(4080-i4), op22(5090-i5).

## 1. Resume checklist (do these first)
1. `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\session-start.ps1 -Brief`; `agent-rollcall.ps1` (one line per agent).
2. Waker: Monitor tool, command `MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/waker-persist.sh watch`, timeout_ms 3600000 (expires after 30 min; re-arming is harmless; heartbeat `C:\KenshiTestRuns\waker\coordinator.hb`).
3. Open alerts: `ls C:\KenshiTestRuns\alerts\open`; act, then `alert-ack.ps1 <id> "<action>"`.
4. Read `testing/SHAY_DECISIONS.md` (open questions for Shay, defaults in use).
5. BACKLOG: `testing/AGENT_BACKLOG.md` is the list of work to start without Shay; at every waker event / agent result check the slot test in it and spawn the top READY item. Replay2 (Shay's ordered test) has priority for slots.
6. Agents run in THIS session unless noted: never respawn a RUNNING one; the task-notification "completed" for an agent that "is waiting on its own background work" is NOT a finish (check its .status).

## 2. Shay's standing orders (verbatim sense, this session)
- No lane idle ever; never `KAH_PF_ISOLATION=0`; both rigs allowed (isolated lanes only); never Shay's live install/server/DB.
- Haiku experiments: no cost pre-approval; report time, tokens, cost per arm afterwards vs the baselines. "do PI 66 and any other PI item that is confirmed".
- Never steer/resume/message an ab2 arm. Ask Shay only in final text, never block (no AskUserQuestion).
- Shay: "record in the handoff the details (options, in-game effects, short description) ... if the other session ended we would have no data"; "the handoff needs to capture everything a fresh session would need given 0 context, so we don't lose important info during a compact".
- NEW DECISION FOR SHAY (now in SHAY_DECISIONS): 16-bx 40-word cap: keep it, or give reserved/terse NPCs a trait brevity line in the prompt. In game: reserved characters either get replies cut to <=40 words by the prompt, or the row allows longer replies. Default: keep the cap, no prompt change.
- Shay wants: auto-compact at ~150k with this file kept current instead of 300k + new-session handoff (see section 9, status of the setup).
- When a game question is asked of Shay: describe the in-game effect on NPC behaviour and the code logic, in plain terms.

## 3. Deliverables owed to Shay
- FINAL FULL REPORT of ALL replay2 arms (Haiku pair R1/R2/R3, draft-review, guard rails, Haiku alone, Sonnet alone) when r2+r3 are done: quality graded, tokens, time, cost vs baselines. Interim read: `C:\KenshiTestRuns\shadow\replay2-interim\INTERIM.md` (dr 69% ~ Sonnet 73%, H 42%, gr 47%; pair R1 agree 15%). Cost anomaly: R1 P026-P038 first attempts ran on Sonnet ($4.25 billed vs ~$1.85 clean); the cost method should count the final attempt's model.
- ab2 pilot (Haiku vs Sonnet lane operator, 10 rows x 2, 20 runs): COMPARISON.md + plain-terms explanation when done. PASS/FAIL = the row checker's RESULT line; the operator's recorded verdict must equal it (mismatch = false claim); SETUP-FAIL/GATED/no line = ESCALATE.
- PI items asked once in the first summary (docs/PROCESS_IDEAS.md): PI-66 (Shay applies `"env": {"CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "40"}` in .claude/settings.json) and open PIs.

- OWED (Shay 2026-10-16): report the REAL cost of the next compact at ~150k. Tool `tools/automation/compact-audit.py compacts --session <id>` (auto-runs 15 min after a compaction via handoff-snapshot.ps1 once the hook is installed; else run it by hand ~15 min after); result in C:\KenshiTestRuns\compact-audit\latest.md + docs/COMPACT_AUDIT.md. Tell Shay when it exists.

- Shay said YES (2026-10-16 21:10) to: build a headless `claude -p --model haiku` runner for the remaining replay2 calls (no 20-subagent cap, no executor context limit; ~1 h to build, est. 20-30 min for 225 R2 + R3 runs). hpairexec11 keeps running meanwhile.

## 4. Decisions taken (why)
- Compact instead of handoff session (Shay): cheaper per turn, keeps reasoning; handoff session costs ~same one-off but adds a tail and relay failure modes (PI-68 loop cost ~190k tokens).
- 23-a checker: default = report SETUP-FAIL (not n/a) when the agreement never reached ACCEPTED + native start; test-tooling choice, not in SHAY_DECISIONS.
- PI-51 (persistent waker Monitor) and PI-62 (`testruns-sweep.ps1 -Auto`) APPLIED by Shay running swap.ps1; PI-61 (one fixer per ticket) practiced.
- No cascade/verifier agents; models per `model-policy.json`; ab2/replay2 spawns use `[case:bench] [model:..] [effort:..]` with explicit model=/effort= params (the router does not fire for subagent spawns).

## 5. Agent roster (SendMessage by agentId; name does not work for subagents)
Registered in `C:\KenshiTestRuns\agents\ids.json` (`agent-ids.ps1 add <name> <id>`).
| agent | id | role / what to do when it finishes |
|---|---|---|
| imm26-ab2exec3 | a8ac64bdf861762a3 | ab2 executor, runs 20 runs serially via ab2-next.py; at ~150k own context it hands off -> spawn ab2exec4 from `ab2-state.py status` (never from memory). At the end: COMPARISON.md, then cleanup (delete C:\KenshiTestRuns\pilot\ab2\ACTIVE; `row-attempts.ps1 reset 5090-i4 <ROW>` per row; unpark lane 5090-i4 (lanes.held); run fix02bxsrv `apply.py` on /tmp/stobe-imm26-5090-i4/site) and explain to Shay |
| ab2-<arm>-<ROW> (e.g. ab4125bb63c428ad2 = sonnet 02-cx seq 7) | per run | arm agent; NEVER message/steer |
| imm26-hpairexec12 | a2df4cf4da781316b | replay2 executor #12 (Sonnet High). 22:10: told to STOP issuing subagent waves; the HEADLESS runner (replay2-headless.py, commit 4c8a1047, Haiku via claude -p, ~$0.006/run, 16 parallel, no cap) was started by me: `python -I toolsutomation\shadow-replay
eplay2-headless.py run --round r2 --parallel 16` (log C:\KenshiTestRuns\shadow
eplay2\headless-r2-run.log). hpairexec12 polls `status` (collect does not see headless runs), then `run --round r3`, `merge-cost`, finalize, aggregate-cost, graders (subagents waves of 8, or `run --round grade` untested). Hands off at ~120k -> hpairexec13 |
| imm26-5090-i3op37 | a9501959811f482a6 | DONE 20:48: 23-a = REAL FAIL with recipe v3 (c5b46874): game ended the order 19 u short (planar=18.9 dy=14.9, native_order_ended_before_goal). Lane 5090-i3 now has NO claimable row; investigator inv23a running; recipe nit: skip stage-landing check when Cind x/z moved >1000 (stale y) |
| imm26-fix23agate | af4922b8959aebd6b | 23-a RECIPE fix from inv23a (root cause: tripdefs_23a2.sh:124 stage teleport 'gate dist 400' puts Cind off-mesh; skip staging when gate < 1500 u; + landing-check nit); selftest scenario a2-local-gate; note inbox\operatorsix23agate.txt; then an operator reruns 23-a on 5090-i3 (no operator yet: backlog) |
| imm26-fix14dserver | a55d7511d72a47aca | 14-d server fix: ActivityAgreementAdapter keys() rejects ClearGroup intent campZoneRef/discoveryRef ('Unexpected activity fields'); anchor patch pending-fixes/imm26-fix14dserver; then i5 operator reruns 14-d |
| imm26-fix19erecipe | aa28c7638749868c1 | 19-e recipe: teleport Cind within ~30 u before s4; note fix19erecipe.txt; then i5 operator reruns 19-e |
| imm26-inv23a | DONE (hand-back 22:12) | root cause = recipe (above), NOT native arrival; optional ORDER_ENDED diag patch in report C:\KenshiTestRunsgents\out\imm26-inv23a\out-20261016-210228.md |
| imm26-fix16bxbrevity | DONE e98e265a | lib/imm26_personality.php brevity line (reserved/terse triggers incl. 'understatement' so Cind matches); deployed to compose + 3 lane sites (md5 caa39a8a); 4080 sites via note fix16bxbrevity.txt; op32 told to apply on 4080-i3 and rerun 16-bx n=3 (4080-i4 site needs it too) |
| imm26-4080-i3op32 | abd6bf21590043dbe | lane 4080-i3 operator (brief agents\imm26-4080-i3op32.brief.md, 15.7 KB over limit but fine): applies fix02bxsrv apply.py to /tmp/stobe-standalone4080/site then 02-bx n=3, then rows from fix01cxguard/fix02dxroute |
| imm26-4080-i4op24 | a7cf3b4960324f5ab | lane 4080-i4 operator (spawned ~21:00): 01-cx n=3 (hxrun_v3cx.sh) and 02-dx n=3 (hxrun_02bd3.sh); op32 keeps 02-bx only |
| imm26-fixrunner | a3e57542bd04cc8ef | DONE 4c8a1047: replay2-headless.py (status / run --round r1|r2|r3|dr|gr|all|grade / merge-cost; measured 19-41 s, 83-87k tokens, $0.005-0.008 per run vs subagent 146k tokens, $0.0091; hooks off via --setting-sources ""). Used for the r2 remainder + r3 |
| imm26-inv26f | a4f1d1ac05b34af9f | investigates 26-f post-load ClearGroup resume (report + patch diff, no edits) |
| imm26-fix01cxguard | ad41638d336c5e23e | DONE 4a88ed78 (v3cx GUARD markers widened, selftest 35/35); op32 told to rerun 01-cx n=3 on 4080-i3 after 02-bx |
| imm26-fix02dxroute | ab2e97d14c298a4d9 | DONE db092857: v3 row_02dx echo skip + new wrapper rowtools/hxrun_02bd3.sh (old hxrun_02bd.sh defaults to v2); op32 told to rerun 02-dx n=3 with hxrun_02bd3.sh after 02-bx and 01-cx |
| imm26-5090-i5-op21 | a4d054cf11835817a | DONE 22:00: 26-a FAIL (native, off-mesh actor), 14-d FAIL (server allowlist), 19-e FAIL (recipe: Cind 107 u away); marks a6d3c470, efd2e511, 754ed21c; lane i5 up, no claimable row -> backlog 17-20 |
| imm26-4080-i3op31 | DONE (tail 23 closed 20:47, no tail left) | results: 16-bx v3 FAIL 0/3 (real: reserved NPC >40 words in 4 of 9 replies; prompt has no brevity rule; checker lacks "how about you" in ENGAGE, covered by fix16bxengage); 01-cx v3cx FAIL 2/3 (checker gap -> fix01cxguard); 02-dx FAIL 1/3 (checker gap -> fix02dxroute). Marks b8930534, 4676f94e, 7cf8d45d |
DONE this session (reports in `C:\KenshiTestRuns\agents\out\<name>\`): fix23arecipe (b67b4b10), fix19ewait a8b1bcdb8cec14367 (59f4916b), fix14dtool2 a1479e6611afc458b (00b89ce6), fix16bx2/fix16bxengage (cafc7a61, 789165d1), fixcindwait (8d57ec16), fixnc34 (NC34 native fix built; DLL 6E14E686), fixctllaunch, pi62sweep, pi51/pi62 swaps. STOPPED by me: imm26-replay2-interim (re-delivery loop).

## 6. Rigs and lanes
- 5090-i3: op37 (23-a). 5090-i5: op21. 5090-i4: PARKED/held for ab2 (lane 5090-i4 must not be touched except by ab2 arms; site frozen, deploys skip -i4). 4080-i3: op31 (tail). 4080-i4: NO runnable row (alert lane-idle-4080-i4 acked): spawn `imm26-4080-i4op24` (brief via `lane-brief.ps1`, register in `lane-owners.json`) when 14-d/19-e style work exists.
- Operator notes: `C:\KenshiTestRuns\inbox\operators\*.txt` (fix23arecipe, fix14dtool, fix19ewait, fix11b-defects).
- Offline check running: `unblock_23a2_selftest.sh` rerun in WSL (output C:KenshiTestRunsNblock23a2-rerun.txt (started 20:42, ~12 min); expect 56/56).

## 7. Open issues (ranked)
1. 26-f post-load ClearGroup resume: no investigator. 2. 15-bx/17-bx variance; 15-bx split (SHAY_DECISIONS). 3. 12-d design gate. 4. 13-c-neg (native, i3 op). 5. `preflight.sh`: treat isolation cache stale when `lane-isolation-check*.ps1` is newer (NOT done; edit only between lane runs; stale cache `C:\KenshiTestRuns\preflight-isolation-5090.txt` caused false FAILs). 6. tail-close-selftest 25 pre-existing failures. 7. selftest-all output unread: `C:\KenshiTestRuns\selftest-all-h24.txt`. 8. Checker: c_23a option-A items read only s3/s4 chat so can show PASS on a FAILED agreement (verdict still FAIL).
- PI list (docs/PROCESS_IDEAS.md, 15/15 active): open 37,41,44,46,48,49,52,56,58,63; confirmed 64,65,66(awaiting Shay),67,68,69; PI-41 = autoCompact instead of tail hard limit (now being done).

## 7b. NOT STARTED / DEFERRED (honest list, 2026-10-16 ~21:00; reason per item; keep current)
| item | state | reason |
|---|---|---|
| imm26-4080-i4op24 | SPAWNED ~21:00 (see roster) | I held it while the 20-agent cap was tight; lane 4080-i4 has been idle ~27 min (alert open). Spawn now; split rows with op32 (op32 keeps 02-bx; tell it to drop 01-cx/02-dx) |
| 5090-i3 operator | none (op37 DONE, no claimable row) | waits for inv23a -> native fixer for the 23-a arrival tolerance |
| native fixer for 23-a arrival (ORDER_ENDED planar/dy) | not spawned | needs inv23a result first |
| 26-f post-load ClearGroup resume | no investigator ever spawned | not capped; never ticketed. Spawn [case:investigate] |
| 15-bx / 17-bx variance | no agent | not ticketed (also needs Shay's 15-bx split decision) |
| 12-d design gate | none | waits for a Shay design decision |
| 13-c-neg (native) | assigned to an i3 operator, none exists | needs a native fixer + operator |
| recipe nit: skip 23-a stage-landing check when Cind x/z moved >1000 | not done | small follow-up for the 23-a fixer |
| 16-bx brevity (prompt trait line) | waits | Shay decision in SHAY_DECISIONS (default a) |
| 14-d scene (SCENE-BAD, 3 extra serials) | op21 reported SETUP-FAIL | needs --far-spawnt fallback / fix14dtool3 |
| headless claude -p replay runner | proposed to Shay, not built | waits for his yes |
| PI-67/68/69/70/71 builds | confirmed/open, not built | not capped; low priority behind lane work |
| preflight.sh stale isolation cache fix | not done | edit only between lane runs |
Reason key: CAP = held because of the 20-concurrent-subagent cap (only the i4 operator and the replay waves were truly capped); the rest were never ticketed or wait on a result/decision.

## 8. Gotchas learned (not in the repo elsewhere)
- Permission classifier denies the coordinator editing hooks/settings.json/CLAUDE.md ("self-modification"): prepare candidate + swap.ps1 and give Shay a copy-paste command. Git Bash `!` commands strip backslashes and expand `$vars`: use `cd <dir> && powershell -NoProfile -ExecutionPolicy Bypass -File swap.ps1`.
- Agent "completed" notifications can be interim ("waiting on its own background work"); a stale RUNNING status after DONE raises orphaned alerts (PI-64): mark DONE + ack.
- A stash/pop by an agent touched the whole repo once: check `git stash list` after fixers that use git.
- Windows Temp scratch dirs are not WSL /tmp; Git Bash mangles /mnt paths: `MSYS_NO_PATHCONV=1 wsl.exe ...`.
- Subagent spawn: explicit model=/effort= params; description must start `[case:<name>]` (claude-code-guide agent also needs one, e.g. `[case:read]`).

- hpairexec10 looked orphaned (status silent 35 min) but was ALIVE (task notice 'waiting on its own background work'); I had spawned hpairexec11 and abandoned it, then TaskStopped hpairexec10 to avoid two executors issuing the same r2 runs. Rule: before respawning an executor, check the task notices (completed-with-children = alive) and TaskStop the old one first.
- 14-d v2 SETUP-FAIL 20:48 on i5 (op21): SCENE-BAD agreedTargets != near five (3 extra serials not near: the far bandit spawn lands in the platoon, the predicted fallback is `--far-spawnt "<squad template>"`); op21 handles/reports, then a fixer if needed.

- Operator tooling snags (op21, 2026-10-16): launch lanes with KAH_FPS=30 (the brief says 60; at 60 the isolation preflight fails on the frame cap); unblockrun_14d_v2.sh wants lane `5090-i5` (not `i5`) and a lane-setup before EVERY run (bandits accumulate); reloadrun-b.sh needs `--save kah-imm26-19a-5090-i5`; never start long jobs with `( ... ) &` in Git Bash (runs detached, overlaps the real run): use run_in_background.
- Agent slots are OVER the cap right now (about 9 live agents + up to 16 replay runs): the backlog items 17-19 wait for slots; the replay test has priority.

## 9. Auto-compact at 150k setup: APPLIED by Shay 2026-10-16 ~21:05
- .claude/settings.json: autoCompactWindow 183000 (150k + fixed 33k buffer; unverified assumption, check with /context that the window shows 183k and watch where the next auto-compact fires), hooks PreCompact (handoff-snapshot.ps1: writes C:\KenshiTestRuns\handoff-auto.md and schedules the compact audit 15 min later) and SessionStart matcher "compact" (-Print: re-injects the snapshot + the OWED-TO-SHAY audit line). Meter: warn at 120k (checkpoint text incl. PROCESS IDEAS), no handoff session, no tail. Backups: C:\KenshiTestRunsackup\*.pre-livehandoff-*.
- Docs: docs/HANDOFF_STANDARD.md, docs/COMPACT_AUDIT.md (measured: compact #1 $0.23 vs handoff $1.84), testing/AGENT_BACKLOG.md.
- OWED to Shay: after the next auto-compact (first at the new threshold) report the REAL cost from C:\KenshiTestRuns\compact-audit\latest.md; record it in docs/COMPACT_AUDIT.md "Compact #2".
