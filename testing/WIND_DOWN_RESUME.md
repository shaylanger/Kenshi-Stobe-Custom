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
| 23-a | fix23agate2 DONE (367387fa): cause = recipe asked for Squin (14.5 km, Shay attacked there); now 3 nearby asks + a2_gate_local guard, selftest 71/71, no swap needed | rerun: `bash rowtools/unblockrun_23a2.sh 23-a 5090-i3 --save kah-imm26-5090 --allow-retry "fix23agate2: nearby ask, local gate"`; expect RESULT 23-a PASS; a rare SETUP-FAIL "FAR destination" = LLM variance, rerun once; if the LLM never offers a local place, deploy the inject-travel seam on 5090-i3. Notes: inbox\operatorsix23agate2.txt |
| 15-bx | ordering fix works; real native defect: KO'd NPC still gets `[combat]` lines (Utils.cpp `CollectEventPeopleFromAnchor` has no sleep/KO filter); X2 hedge check may be too strict; 15-bx SETUP-FAIL (P not placed within 15 u) | native fixer for S1; Shay decision on X2 (relax or reword) |
| 13-c-neg | recipe defect patched (9b180623, `unblockdefs_f3.sh`), live proof parked | live proof on 5090-i5 (free); setupfail ticket owner imm26-5090-i3op36, needs=native |
| 26-a | root cause: DLL `owned_target` on fresh goats; fix proposed, NOT applied | apply fix, build + install DLL, rerun |
| 26-f | rerun parked (fix26fcamp deployed to compose, 5090-i5, 5090-i3, sfo-manual; NOT 5090-i4 / 4080 / live) | deploy to the rest, rerun |
| 02-bx / 02-dx | reruns parked | apply `pending-fixes/imm26-fix02bxregex` (d009980c) to `/tmp/stobe-standalone4080/site` and the 4080-i4 site (`apply.py <site>`, `--check` first; needs fix02bxsrv) |
| 01-cx | setup-fail ticket, unowned, needs=fixture | runs on 4080-i4 (no fixture on 5090-i5); 4080-i4op25 was running 01-cx x3 then 02-dx x3 when wound down - check `drive.sh` results |
| 4080-i4 | needs fix16bxbrevity and fix02bxsrv | install before the next batch there |
| 14-d, 16-bx, others | at the row-rework cap (see `rowgate.ps1 status <row>`) | next agent needs ESCALATE + METHOD-QUESTION lines |

## 2. Cost-cut work (Shay: "do 1, 3, 4; hold 2")
New files are committed; wiring status:
- Cut 1 row rework gate: WIRED in `.claude/settings.json` (rowgate-guard PreToolUse + rowgate-post PostToolUse on the Agent matcher); selftest 47/47; reader bug fixed. Still TODO: the lane-brief line (SETUP-FAIL reason must end with `evidence <dir>`, `lane-brief.ps1` ~l.394, apply at a boundary). Decision for Shay: restart failing rows at attempt 1 (`rowgate.ps1 close <row>`)?
- Cut 3 status turns out of the model (imm26-cut3, agent adf2d3affe6516029): hand-back pending when this was written; swap note `inbox\operators\cut3.txt`.
- Cut 4 keep-alive guard (222ee8a5): WIRED 2026-10-16 (PreToolUse Bash|PowerShell keepalive-guard.ps1; selftest 105/0). Denies subagent foreground waits/timeouts > 240 s. Check `C:\KenshiTestRuns\keepalive-denies.log` after ~10 min; rollback = create `C:\KenshiTestRuns\keepalive.off`. Open idea: rewrite timeout to 240000 instead of denying (untested updatedInput).
- Waker chores script (imm26-choresbot, DONE 472d9cb1, not switched on): to switch on stop the Monitor on `waker-persist.sh watch` and start `waker-persist-chores.sh watch`; selftest 86/0. Decision: keep hourly liveness line (default yes).
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
