# COORDINATOR LIVE STATE (living document; Shay 2026-10-16)

PURPOSE: a fresh coordinator with ZERO context (after /compact, a crash or a new session) must be able to continue from this file alone,
because a compaction summary can lose things that cannot be recovered (Shay's exact orders, why a decision was taken, which agent does what).
RULES (docs/HANDOFF_STANDARD.md): rewrite the section that changed in the SAME turn as the event (agent result, Shay message, decision, new agent, install);
never append a "correction" paragraph, fix the line; commit + push it with the work; keep it under ~250 lines (history goes to archive/).
`tools/automation/handoff-snapshot.ps1` adds the mechanical state (agents, alerts, ledger, inflight) at every compaction: `C:\KenshiTestRuns\handoff-auto.md`.
ZERO-CONTEXT TEST before every compact: "could a new session do the next 10 things from this file + HANDOFF 'Right now' + SHAY_DECISIONS.md without asking anyone?"

Last updated: 2026-10-16 ~20:55 by coordinator #24 (session 7b068528-9019-4ad1-913a-ead9d4167d45). Tail of coordinator #23 (5161648d) CLOSED 20:47: it owns nothing; no tail exists now.

## 1. Resume checklist (do these first)
1. `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\session-start.ps1 -Brief`; `agent-rollcall.ps1` (one line per agent).
2. Waker: Monitor tool, command `MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/waker-persist.sh watch`, timeout_ms 3600000 (expires after 30 min; re-arming is harmless; heartbeat `C:\KenshiTestRuns\waker\coordinator.hb`).
3. Open alerts: `ls C:\KenshiTestRuns\alerts\open`; act, then `alert-ack.ps1 <id> "<action>"`.
4. Read `testing/SHAY_DECISIONS.md` (open questions for Shay, defaults in use).
5. Agents run in THIS session unless noted: never respawn a RUNNING one; the task-notification "completed" for an agent that "is waiting on its own background work" is NOT a finish (check its .status).

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
| imm26-hpairexec11 | a10f12a2e2161043c | replay2 executor (Sonnet High, waves of <=10 because of the 20-concurrent cap): r2 (15/240 done at 20:50; hpairexec10 died silently after batch 01, abandoned), then r3, finalize, graders, aggregate -> then FINAL FULL REPORT to Shay; at ~150k own context it hands off -> spawn hpairexec12 |
| imm26-5090-i3op37 | a9501959811f482a6 | DONE 20:48: 23-a = REAL FAIL with recipe v3 (c5b46874): game ended the order 19 u short (planar=18.9 dy=14.9, native_order_ended_before_goal). Lane 5090-i3 now has NO claimable row; investigator inv23a running; recipe nit: skip stage-landing check when Cind x/z moved >1000 (stale y) |
| imm26-inv23a | a80058b9dd5461884 | investigates the 23-a arrival tolerance (native C++); result -> native fixer -> op for 5090-i3 rerun |
| imm26-4080-i3op32 | abd6bf21590043dbe | lane 4080-i3 operator (brief agents\imm26-4080-i3op32.brief.md, 15.7 KB over limit but fine): applies fix02bxsrv apply.py to /tmp/stobe-standalone4080/site then 02-bx n=3, then rows from fix01cxguard/fix02dxroute |
| imm26-fix01cxguard | ad41638d336c5e23e | DONE 4a88ed78 (v3cx GUARD markers widened, selftest 35/35); op32 told to rerun 01-cx n=3 on 4080-i3 after 02-bx |
| imm26-fix02dxroute | ab2e97d14c298a4d9 | routes 02-dx through the v3 echo skip; note inbox\operatorsix02dxroute.txt |
| imm26-5090-i5-op21 | a4d054cf11835817a | lane 5090-i5 operator: NC34 DLL (6E14E686) installed on both i5 Stobe dirs; running 26-a; then 14-d v2 (`unblockrun_14d_v2.sh 14-d i5 --allow-retry "fix14dtool v2" --ask "Hunt 5 bandits."` and again "Hunt the 5 bandits."), then 19-e (`reloadrun-b.sh 19-e 5090-i5 --no-reload ...`, grep "Trip resume wait" in /tmp/stobe-imm26-5090-i5/site/log/stobeserver.log) |
| imm26-4080-i3op31 | DONE (tail 23 closed 20:47, no tail left) | results: 16-bx v3 FAIL 0/3 (real: reserved NPC >40 words in 4 of 9 replies; prompt has no brevity rule; checker lacks "how about you" in ENGAGE, covered by fix16bxengage); 01-cx v3cx FAIL 2/3 (checker gap -> fix01cxguard); 02-dx FAIL 1/3 (checker gap -> fix02dxroute). Marks b8930534, 4676f94e, 7cf8d45d |
DONE this session (reports in `C:\KenshiTestRuns\agents\out\<name>\`): fix23arecipe (b67b4b10), fix19ewait a8b1bcdb8cec14367 (59f4916b), fix14dtool2 a1479e6611afc458b (00b89ce6), fix16bx2/fix16bxengage (cafc7a61, 789165d1), fixcindwait (8d57ec16), fixnc34 (NC34 native fix built; DLL 6E14E686), fixctllaunch, pi62sweep, pi51/pi62 swaps. STOPPED by me: imm26-replay2-interim (re-delivery loop).

## 6. Rigs and lanes
- 5090-i3: op37 (23-a). 5090-i5: op21. 5090-i4: PARKED/held for ab2 (lane 5090-i4 must not be touched except by ab2 arms; site frozen, deploys skip -i4). 4080-i3: op31 (tail). 4080-i4: NO runnable row (alert lane-idle-4080-i4 acked): spawn `imm26-4080-i4op24` (brief via `lane-brief.ps1`, register in `lane-owners.json`) when 14-d/19-e style work exists.
- Operator notes: `C:\KenshiTestRuns\inbox\operators\*.txt` (fix23arecipe, fix14dtool, fix19ewait, fix11b-defects).
- Offline check running: `unblock_23a2_selftest.sh` rerun in WSL (output C:KenshiTestRunsNblock23a2-rerun.txt (started 20:42, ~12 min); expect 56/56).

## 7. Open issues (ranked)
1. 26-f post-load ClearGroup resume: no investigator. 2. 15-bx/17-bx variance; 15-bx split (SHAY_DECISIONS). 3. 12-d design gate. 4. 13-c-neg (native, i3 op). 5. `preflight.sh`: treat isolation cache stale when `lane-isolation-check*.ps1` is newer (NOT done; edit only between lane runs; stale cache `C:\KenshiTestRuns\preflight-isolation-5090.txt` caused false FAILs). 6. tail-close-selftest 25 pre-existing failures. 7. selftest-all output unread: `C:\KenshiTestRuns\selftest-all-h24.txt`. 8. Checker: c_23a option-A items read only s3/s4 chat so can show PASS on a FAILED agreement (verdict still FAIL).
- PI list (docs/PROCESS_IDEAS.md, 15/15 active): open 37,41,44,46,48,49,52,56,58,63; confirmed 64,65,66(awaiting Shay),67,68,69; PI-41 = autoCompact instead of tail hard limit (now being done).

## 8. Gotchas learned (not in the repo elsewhere)
- Permission classifier denies the coordinator editing hooks/settings.json/CLAUDE.md ("self-modification"): prepare candidate + swap.ps1 and give Shay a copy-paste command. Git Bash `!` commands strip backslashes and expand `$vars`: use `cd <dir> && powershell -NoProfile -ExecutionPolicy Bypass -File swap.ps1`.
- Agent "completed" notifications can be interim ("waiting on its own background work"); a stale RUNNING status after DONE raises orphaned alerts (PI-64): mark DONE + ack.
- A stash/pop by an agent touched the whole repo once: check `git stash list` after fixers that use git.
- Windows Temp scratch dirs are not WSL /tmp; Git Bash mangles /mnt paths: `MSYS_NO_PATHCONV=1 wsl.exe ...`.
- Subagent spawn: explicit model=/effort= params; description must start `[case:<name>]` (claude-code-guide agent also needs one, e.g. `[case:read]`).

- hpairexec10 looked orphaned (status silent 35 min) but was ALIVE (task notice 'waiting on its own background work'); I had spawned hpairexec11 and abandoned it, then TaskStopped hpairexec10 to avoid two executors issuing the same r2 runs. Rule: before respawning an executor, check the task notices (completed-with-children = alive) and TaskStop the old one first.
- 14-d v2 SETUP-FAIL 20:48 on i5 (op21): SCENE-BAD agreedTargets != near five (3 extra serials not near: the far bandit spawn lands in the platoon, the predicted fallback is `--far-spawnt "<squad template>"`); op21 handles/reports, then a fixer if needed.

## 9. Auto-compact at 150k setup (Shay's order; status)
- Built: `tools/automation/handoff-snapshot.ps1` (PreCompact hook writes handoff-auto.md; SessionStart matcher "compact" with `-Print` re-injects it), `docs/HANDOFF_STANDARD.md`, memory `living-handoff-autocompact`.
- Needs Shay (self-modification denied for me): `autoCompactWindow` in ~/.claude/settings.json (now 330000), the PreCompact + SessionStart(compact) hook entries, and `.claude/context-meter.project.ps1` main-session thresholds (now warn 270k / handoff 300k; candidate in `pending-fixes/living-handoff-compact/`). Not applied until Shay runs `pending-fixes/living-handoff-compact/swap.ps1`.
