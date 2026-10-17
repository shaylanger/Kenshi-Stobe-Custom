# START HERE (Shay's one file for a new session) - state 2026-10-17 00:15, coordinator #24
Read this file first, then run `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\session-start.ps1 -Brief`. Where this top section and the older text below disagree, THIS top section wins.

## Mode
- WIND-DOWN is in force (`C:\KenshiTestRuns\WIND_DOWN.flag`): no lane work, no relaunch, no new 5090 sessions. Offline tooling work is allowed when Shay orders it.
- When Shay says "start working again": step 0 below (ab2 pilot first), delete the flag, `kenshi-ctl.ps1 idle clear`, release lanes.held lines (5090-i4, 5090-i5).
- Context: autoCompactWindow is 183000 for all models (set 2026-10-16). Never ask Shay for /cost around compacts. Ask him only in final text; never block.
- Push is blocked for agents/the coordinator by the permission checker: 9 commits are local only (993ca1e7 .. 1bd48da3). Shay runs `git -C C:\KenshiModding push origin HEAD` himself. Commit 4323750b (docs/model-test, 1117 files, unreviewed agent-session text) may already be on origin/main (github.com/shaylanger/Kenshi-Stobe-Custom); repo visibility unchecked; do not rewrite history without Shay.

## Done this session (all committed locally, live)
- PI-48 bare `stobe-auto` guard (ac3be002; opt-out STOBE_AUTO_LIVE=1; 4080 copy NOT changed; stale game-N.lock files trigger it).
- PI-52 known-snags block in lane brief + mark-row.py refusal (42739691). PI-49 snag helper/counter (d7a133a3). PI-68 duplicate hand-back guard (22643053). PI-68+PI-49 merged into the live chores waker (77201850; backup coord-chores.ps1.pre-swap68-49).
- agent-status-hook: empty final message + a saved report in agents/out = DONE not FAILED (162ef5e6).
- Cost cuts 1, 3, 4, 5 applied (see section 2 below); cut 2 (Haiku operators) HELD for the ab2 result; cuts 6/7/8 not approved.
- PROCESS_IDEAS pruned to 10 (active: PI-48, 49, 52, 65, 68, 70, 71; in progress 42, 54, 66). PI queue removed from AGENT_BACKLOG.

## Not done / open (act on these)
1. Waker flood: identical `RIG STALL`/event lines repeat every 2 s with no dedupe (coord-chores.ps1 / event-wait.sh). Candidate fix: throttle identical event lines to 1 per 10 min. Cause of the 00:03 flood = stale inflight markers (moved to C:\KenshiTestRuns\backup\inflight-removed-0017).
2. KAH_FPS conflict: lane-brief launch line says 60, the KNOWN_BLOCKERS snag block says 30. Find which is right and make both agree.
3. lane-brief-selftest.ps1 has 5 pre-existing FAILs (rules block, status commands, PI-19 x2, PILOT): not caused by recent edits; look when convenient.
4. `ctxfix-selftest.sh` fails 1/53 (xargs quote error), unchecked.
5. HANDOFF.md "Right now" not updated (file holds other agents' uncommitted edits); this file + COORDINATOR_LIVE.md are the record.
6. PI-71 demand-driven lanes (est. $15-30/day, unmeasured): wait for "start working again", design pass + trial on one lane first. Shay's overnight idea: ONE lane per rig (2 total) with a skip-ahead queue (READY rows only; rows waiting for a fix are skipped, rework-capped rows are NOT ready; a lane with no READY row ends cleanly with an alert). Design not started; Shay said "just asking".
7. Shay's PI-70 (-WaitUntil) weakens the stall catch: Shay's call only.
8. Reminders at the next real work: STOBE server on only for a STOBE batch (`stobe-server.sh off` after); `gfx-mods.sh on` before Shay plays (was on); `testruns-sweep.ps1` after each batch (5090 run folders imm26-nc* ~260 MB each go stale after 24 h: delete them, they are judged); the chores waker Monitor dies with the session: start `MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/waker-persist-chores.sh watch` as a Monitor (30 min cap, re-arm) whenever anything is in flight.
9. Shay should check `/hooks` once: the context-meter hook was removed from his global settings by him (2026-10-16); the scripts remain on disk, uncalled.

# WIND-DOWN RESUME LIST (coordinator #24, 2026-10-16 ~22:30)

Shay ordered a wind-down (no new lane work). This is the ONE list of everything stopped, parked or not started, so a new
session can resume cold. Read with `COORDINATOR_LIVE.md` (last 40 lines), `SHAY_DECISIONS.md`, `AGENT_BACKLOG.md`,
`session-start.ps1 -Brief`. When Shay says "start working again": step 0 first, then the rest in order.

## 0. FIRST: resume the ab2 Haiku-vs-Sonnet operator pilot (Shay's standing order)
- Read `C:\KenshiTestRuns\pilot\ab2\README.md` + `COMPARISON.md`. Relaunch lane 5090-i4, re-hold it (`lanes.held`), rebaseline.
- Spawn a FRESH executor `imm26-ab2exec4` for seq 13-20 (01-cx, 18-cx, 23-b, 16-bx) plus the voided runs (05-cx both arms, 17-bx Sonnet).
- Report time / tokens / cost per arm afterwards (no cost pre-approval). Never steer an arm.
- Delete `C:\KenshiTestRuns\WIND_DOWN.flag`. Remove the `kenshi-ctl.ps1 idle` reason (`idle clear`).
- Cut 2 (lane operators on Haiku) stays HELD until the full pilot result.

## 1. Rows stopped mid-way (need a rerun / live proof)
| Row | State | What is needed |
|---|---|---|
| 23-a | fix23agate2 DONE (367387fa): cause = recipe asked for Squin (14.5 km, Shay attacked there); now 3 nearby asks + a2_gate_local guard, selftest 71/71, no swap needed | rerun: `bash rowtools/unblockrun_23a2.sh 23-a 5090-i3 --save kah-imm26-5090 --allow-retry "fix23agate2: nearby ask, local gate"`; expect RESULT 23-a PASS; a rare SETUP-FAIL "FAR destination" = LLM variance, rerun once; if the LLM never offers a local place, deploy the inject-travel seam on 5090-i3. Notes: inbox\operators\fix23agate2.txt |
| 15-bx | ordering fix works; real native defect: KO'd NPC still gets `[combat]` lines (Utils.cpp `CollectEventPeopleFromAnchor` has no sleep/KO filter); X2 hedge check may be too strict; 15-bx SETUP-FAIL (P not placed within 15 u) | native fixer for S1; Shay decision on X2 (relax or reword) |
| 13-c-neg | recipe defect patched (9b180623, `unblockdefs_f3.sh`), live proof parked | live proof on 5090-i5 (free); setupfail ticket owner imm26-5090-i3op36, needs=native |
| 26-a | root cause: DLL `owned_target` on fresh goats; fix proposed, NOT applied | apply fix, build + install DLL, rerun |
| 26-f | rerun parked (fix26fcamp deployed to compose, 5090-i5, 5090-i3, sfo-manual; NOT 5090-i4 / 4080 / live) | deploy to the rest, rerun |
| 02-bx / 02-dx | reruns parked | apply `pending-fixes/imm26-fix02bxregex` (d009980c) to `/tmp/stobe-standalone4080/site` and the 4080-i4 site (`apply.py <site>`, `--check` first; needs fix02bxsrv) |
| 01-cx | op25 DONE: 02-dx PASS 3/3 on 4080-i4 (6f625284); 01-cx SETUP-FAIL 3/3 (9b4e87a9): row-tool defect, the spawned Dust Bandit is renamed at first chat ("Bex [Dust Bandit]") but hxdefs.sh waits for `SAY [Dust`, and the scene teleports a different Dust Bandit serial (dist 3860); rep 3 "no stranger pair within 3000 u" | fixer: give 01-cx an id-based A pick and resolve its post-rename name, as hxdefs_02bd_id.sh does for 02-bx; then rerun on 4080-i4. 4080-i4 site now has fix16bxbrevity, fix14dserver, fix02bxsrv (NOT fix02bxregex). 4080-i4 game stopped, lock released |
| 4080-i4 | needs fix16bxbrevity and fix02bxsrv | install before the next batch there |
| 14-d, 16-bx, others | at the row-rework cap (see `rowgate.ps1 status <row>`) | next agent needs ESCALATE + METHOD-QUESTION lines |

## 2. Cost-cut work (Shay: "do 1, 3, 4; hold 2")
New files are committed; wiring status:
- Cut 1 row rework gate: WIRED in `.claude/settings.json` (rowgate-guard PreToolUse + rowgate-post PostToolUse on the Agent matcher); selftest 47/47; reader bug fixed. DONE 2026-10-16 (lane-brief line applied): was TODO: the lane-brief line (SETUP-FAIL reason must end with `evidence <dir>`, `lane-brief.ps1` ~l.394, apply at a boundary). Decision for Shay: restart failing rows at attempt 1 (`rowgate.ps1 close <row>`)?
- Cut 3 status housekeeping out of the model (a69c8aef, selftest 39/0): settings.json hooks WIRED 2026-10-16 (SubagentStart/SubagentStop/PostToolUse agent-status-hook.py; backup `C:\KenshiTestRuns\backup\settings.json.pre-cut3`). VERIFIED on imm26-modeltestpack 2026-10-16; step (1) lane-brief/AGENT_PROMPTS swap DONE; remaining (2) 200k text (only reaches non-Sonnet-5.5 agents, low value) and (3) waker digest (choresbot now covers DONE events). Original list (status RUNNING within ~2 s, `agents\auto\<id>.json`, check `agents\auto\hook.log`): (1) swap `lane-brief.ps1.cut3.candidate` and `testing/AGENT_PROMPTS.md.cut3.candidate` over the live files (only when no brief is being generated), commit, delete candidates; (2) switch the context-meter 200k text to `agent-note.ps1 <name> "<step>" -State STOPPED-CONTEXT`; (3) waker digest: append `status-digest.ps1 -Consumer waker` in event-wait.sh (option A). Rollback: restore the backup settings.json.
- Cut 4 keep-alive guard (222ee8a5): WIRED 2026-10-16 (PreToolUse Bash|PowerShell keepalive-guard.ps1; selftest 105/0). Denies subagent foreground waits/timeouts > 240 s. Check `C:\KenshiTestRuns\keepalive-denies.log` after ~10 min; rollback = create `C:\KenshiTestRuns\keepalive.off`. Open idea: rewrite timeout to 240000 instead of denying (untested updatedInput).
- Waker chores script (imm26-choresbot, DONE 472d9cb1, SWITCHED ON 2026-10-16): to switch on stop the Monitor on `waker-persist.sh watch` and start `waker-persist-chores.sh watch`; selftest 86/0. Decision: keep hourly liveness line (default yes).
- Cut 2 (Haiku operators): HELD for the full ab2 pilot. Cut 5: edits a-f from `agents\out\imm26-subctx\out-20261016-215944.md` NOT applied (reword CLAUDE.md:15,56,61,66, AGENT_PROMPTS.md, WP_SIZING.md, lane-brief.ps1:318,402, context-meter project.ps1: subagents compact at ~150k, never hand off for size) - waits for Shay's go. Cuts 6, 7, 8 not approved.
- `ctxfix-selftest.sh` fails 1/53 ("status file updated with the SAME task text", xargs quote error): not checked whether pre-existing.

## 3. Small pending items
- Swap `testing/live-stobe-queue/imm26-assert/rowtools/hxdefs.sh.candidate` over `hxdefs.sh` when no run sources it.
- `HANDOFF.md` "Right now" line for choresbot not written (file holds other agents' uncommitted edits).
- PI queue (PROCESS_IDEAS.md is full 15/15): retire tail-moot PI-46/56/58/63/71 first; queued ideas are in AGENT_BACKLOG "PI queue" (a-e).
- Ledger imm26: ~20 of 57 work packages unfinished (`program-ledger.ps1`; many old `stopped` entries from before today: live-rows, tripresume-b, *-hard, *-hard2b, 4080-op2jb/jc, rowtools4, fix10a, regionA1 (24-b, blocked)). Respawn each fresh from its checkpoint only if Shay wants that row; otherwise `agent-abandon.ps1`.

## 4. Decisions owed to Shay (also in SHAY_DECISIONS.md)
Hunt route a/b/c (default a); Mine rebind (default no); own-presence prompt rule (default off); 15-bx split (default yes); 01-cx judging whole reply; bored-turn activity resume (default a); 14-d odds refusal (default a); 15-bx X2 hedge; restart failing rows at attempt 1; apply the cut-5 wording edits.

## 5. Housekeeping when work restarts
- STOBE server on only for a STOBE batch, off after; `gfx-mods.sh on` before Shay plays.
- `testruns-sweep.ps1` after every batch; 4080 deletes need `testruns-sweep.ps1 refresh4080`.
- Stop a 4080 game with `ssh 4080 C:\KAH\ctl.ps1 stop -Instance N`; a 5090 lane game under the rig lock needs a direct process kill (path `D:\KenshiInst\<n>`).
- `/autocompact 183000` and the `/hooks` check; waker Monitor: `waker-persist.sh watch` (re-arm every 30 min while work is in flight).
- Compact audit results are in `docs/COMPACT_AUDIT.md` (#5 = +$0.70 upper bound).
