# Pilot 2 (ab2): Haiku High vs Sonnet High, controlled A/B on the SAME rows and SAME lane

Question: can Haiku High run the lane-operator job (run a row via its one-call script, read the checker line, record it, escalate on anything odd) as well as Sonnet High, and at what time/token/cost?
Control: ONE lane (5090-i4), one Stobe.dll, one server bundle, one base save, 10 fixed rows, EVERY row run once by each model (A/B/B/A order, order effects cancel), scene reset between runs, one identical brief, shadow ledger only (no claims, no TESTS marks, no commits). Arms never run at the same time.

Code (repo): `C:\KenshiModding\tools\automation\pilot-ab2\` (ab2-plan.py, ab2-rebaseline.py, EXECUTOR_PROMPT.md, ab2-state.py, ab2-run.sh, ab2-mark.sh, ab2-next.py, pilot-ab2-compare.py, ab2_lib.py, brief.md, ab2-selftest.sh).
Data (this dir): `queue.txt` (10 rows), `plan.json` (frozen: seed, order, baseline, script hashes), `state.json` (appears at the first run), `captures.jsonl` (one line per run), `brief.md` (the spawn prompt template), `<arm>/verdicts.csv|events.log|state.json|out/<ROW>.out|evidence/<ROW>|bundles/`, `ACTIVE`, `RUNNING` (lock).

## The 10 rows (queue.txt; each verified with --dry) and the plan
`python -I C:\KenshiModding\tools\automation\pilot-ab2\ab2-state.py status` prints the 20 runs (seq, arm, order, row, state). Seed 20261016; the plan is frozen once state.json exists.
Excluded on purpose: 08-d 20-d 22-b 20-a 23-e (trip family / GATED build), 26-*, 24-b/24-c, 15-bx (SETUP-FAIL), 12-d (LLM gated), 13-ax (25 min), 02-bx/02-dx (two fresh saves), 08-e/11-b (unblockdefs_a.sh is being edited).

## What the guards enforce (so the comparison stays clean)
- `ab2-run.sh <arm> <ROW>` is the only thing an arm runs for the row. It refuses unless (arm,row) is the CURRENT seq, no RUNNING lock exists, the lane baseline (Stobe.dll sha8 of both copies, server bundle id, fingerprints of kah-imm26-i4 and kah-imm26-i4-hx0) equals plan.json, and, for the SECOND arm of a row, every script the row command reaches is byte-identical to what the first arm ran (someone editing hxdefs.sh etc. mid-pilot makes it refuse with the file list; `AB2_ALLOW_DRIFT=1` lets it through and records `drift`).
- Identical scene reset before every run, outside the timed window: `lane-setup.sh 5090 4 kah-imm26-i4 --with Cind` (env KAH_INSTANCE=4 KAH_OWNER=rig5090-imm26-i4 KAH_GFX=low KAH_VIDEO_MODE='1024 x 768' KENSHI_MONITOR='\.\DISPLAY2'); a failed reset aborts the run (nothing ran, not advanced).
- `pilot/ab2/ACTIVE` (created by ab2-next.py / ab2-run.sh) switches on: the bare-`stobe-auto` PreToolUse ban (kenshi-waker-guard.ps1) and "no real setupfail tickets for lane 5090-i4" (attempts.py).
- `ab2-mark.sh` = pilot-mark.sh shadow ledger: PASS/FAIL accepted only if equal to the checker's last `RESULT <ROW>` line in the run's .out file and not stale; SETUP-FAIL/GATED/ESCALATE close the row and drop `inbox\coordinator\<ts>-pilot-escalate-<row>.msg`.
- ab2-next.py refuses to issue the next spawn while the previous agent is not DONE/FAILED, a run is in progress, or a finished agent produced no captured run.

## Before the first spawn (coordinator, ~6 min incl. 2.5 min of --dry checks; no game command needed)
Order matters; stop at the first failure. Nothing here starts the game, touches the lane or edits a row.
1. Lane operator done and lane parked: no operator (i4opNN) RUNNING on 5090-i4, then `5090-i4` listed in `C:\KenshiTestRuns\lanes.held` (lane-hold-lib.ps1 Add-LaneHold, or a plain line `5090-i4`), `inflight\5090-imm26-i4` present, `game-4.lock` held by rig5090-imm26-i4. The new DLL is installed (`lane-install.ps1 -Lane i4 -FromLane i3`, both copies) and the lane relaunched per `pilot\haiku-i4\SETUP.md` (game up, `lane-backend.sh status i4` healthy).
2. REBASELINE (mandatory after ANY lane change since plan.json was written: DLL, relaunch, bundle, base save; harmless if nothing changed):
   `python -I C:\KenshiModding\tools\automation\pilot-ab2\ab2-rebaseline.py --check --expect-dll <sha8 of the new DLL, e.g. 3FE805BF>` reads only; then the same without `--check` and with `--tag nc20` (the old build's name) to write. It REFUSES (exit 5, nothing written) unless: state.json has no runs/voids, no RUNNING lock, captures.jsonl empty; a kenshi_x64 runs from D:\KenshiInst\4 (pid recorded), game-4.lock owner is rig5090-imm26-i4, the inflight marker exists, `5090-i4` is validly held, backend healthy (php+bridge listening, pg up, health 200); both Stobe.dll copies are equal (and start with --expect-dll), bundle id and both base-save fingerprints readable; every queue.txt row passes its own command + `--dry` (offline fake lane, rows base redirected to a temp dir: it never touches the lane's rows/). It then archives plan.json as `plan.json.<tag>-<timestamp>`, writes a new plan.json from the CURRENT lane (same seed as the archived plan, same 10 rows, same A/B/B/A order as long as queue.txt is unchanged; pid and lane facts under `plan["rebaseline"]`) and appends `rebaseline.log`. Check the printed line `run order IDENTICAL to the archived plan`.
3. `bash C:/KenshiModding/tools/automation/pilot-ab2/ab2-selftest.sh` prints `SELFTEST OK (54 checks)`; `python -I C:\KenshiModding\tools\automation\pilot-ab2\ab2-state.py status` lists 20 runs, seq 1 CURRENT.
4. No other process may use lane 5090-i4 or edit the row scripts (hxrun*.sh, hxdefs.sh, hxlib, sfrrun.sh, reload-run.sh and what they source; the second arm of a row is refused if they changed); keep `event-wait.sh` running as waker (an agent is in flight). Then spawn the executor (`C:\KenshiModding\tools\automation\pilot-ab2\EXECUTOR_PROMPT.md`).
`ab2-plan.py --force-new` is NOT the rebaseline path any more (no lane/dry checks, no archive): use ab2-rebaseline.py.

Row check after the NC28 install (2026-10-16): all 10 rows kept. TESTS/KNOWN_BLOCKERS show no GATED/fixture/two-fresh-save blocker for them: the `SETUP-FAIL` words in the 16-bx/01-cx/05-cx rows are the old Windows-python `bundle_dir.txt /c/...` false alarm (the queue passes `--out C:/...`, so the path is readable) and `two fresh saves` is satisfied by the lane's single base save (`HX_SAVE2` defaults to `--save`, kah-imm26-i4-hx0). None sets KAH_PF_ISOLATION=0 (it only appears in 4080 header examples and selftests). 23-b and 27-a never ran live on i4 (only dry; PASS/FAIL on other lanes): a SETUP-FAIL there is recorded as ESCALATE and is data for the compare, not a reason to edit the queue mid-pilot.

## The loop (one agent at a time; the coordinator interleaves the arms exactly as plan.json says)
1. `python -I C:\KenshiModding\tools\automation\pilot-ab2\ab2-next.py` prints the next run: seq, arm, row, agent name, the exact Agent description and the filled prompt. Refuses (exit 3) if the previous agent is not DONE/FAILED.
2. Spawn ONE agent with that description and prompt (`subagent_type: general-purpose`, `run_in_background: true`). Exact descriptions:
   - Haiku arm: `[case:bench] [model:haiku] [effort:high] ab2-haiku-<ROW>`
   - Sonnet arm: `[case:bench] [model:sonnet] [effort:high] ab2-sonnet-<ROW>`
   The agent name `ab2-<arm>-<ROW>` MUST be in the description (pilot-ab2-compare.py finds the transcript by it). Do not add anything to the prompt; do not send messages to the agent.
3. Wait for `agents\ab2-<arm>-<ROW>.status` = DONE or FAILED (the waker wakes you). Then `ab2-state.py status` (the seq must show done). Go to 1.
4. Trouble: agent silent > 20 min with a `RUNNING` lock and no game progress -> check `ab2/<arm>/out/<ROW>.out`; if the run crashed: `ab2-state.py unlock "<why>"` then `ab2-state.py void <seq> "<why>"` (voids only that run; its partner shows as unpaired in the compare). A stopped agent is never steered or helped. An escalation inbox message (`pilot-escalate`) is data for the compare, not an order to fix mid-pilot.

## The spawn prompt (brief.md; ab2-next.py fills {AGENT} {ARM} {ROW}); identical for both arms except the name/arm
```
You are `{AGENT}`, an operator for ONE test row of the Kenshi immersion-26 program: row {ROW} on lane 5090-i4. The game is already running and ready. Your whole job is 4 steps.

RESTRICTION (read twice): run the row via its one-call script, read the checker RESULT line, record it, and escalate (stop and hand back) on ANYTHING odd. No debugging, no editing scripts, no second run of the row, no extra game or server queries, no reading other files "to understand". If anything differs from the steps below, stop and hand back.

STOBE-AUTO BAN (PI-48): NEVER run bare `stobe-auto` (no KAH_DIR) or any command on the live install / default port / Steam Kenshi dir: it answers from Shay's LIVE game, not this lane. You do not need it at all. Do not run kenshi-ctl, lane-setup, preflight, go-row or any row script yourself; the only commands you run are the ones written here.

Steps (all from Git Bash, use the Bash tool):
1. Status: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\agent-status.ps1 {AGENT} RUNNING "ab2 {ROW}" "starting" "" "run the row"`
2. Run the row with ONE command, exactly:
   `bash C:/KenshiModding/tools/automation/pilot-ab2/ab2-run.sh {ARM} {ROW}`
   It takes 3 to 15 minutes. Use the Bash tool's maximum timeout (600000); if the tool says the command moved to the background, wait for its completion notice (do not poll, do not sleep, do not start anything else), then read the last 8 lines of the output file it names. The script prints only the last 4 lines of the row plus a final `ab2-run: exit=... Next: ...` line. If it prints REFUSED or "nothing ran" or "scene reset FAILED": that is ODD, go to step 4 with ESCALATE-without-mark (do not run anything else).
3. Find the checker line `RESULT {ROW} <WORD> ...` (WORD is PASS, FAIL, SETUP-FAIL or GATED). Record it with ONE command:
   `bash C:/KenshiModding/tools/automation/pilot-ab2/ab2-mark.sh {ARM} {ROW} <WORD> "<the full RESULT line>"`
   Use WORD exactly as the checker printed it for PASS and FAIL. For SETUP-FAIL, GATED, a missing RESULT line, a non-zero exit with no RESULT line, or anything else odd, use `ESCALATE` as WORD (the full text of what you saw as the note). If ab2-mark.sh says refused, mark exactly what the checker line says, once; do not rerun the row.
4. Finish: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\agent-status.ps1 {AGENT} DONE "ab2 {ROW}" "<WORD> recorded" "C:/KenshiTestRuns/pilot/ab2/{ARM}/out/{ROW}.out" "coordinator: next ab2 seq"` (use FAILED instead of DONE if you had to stop on something odd). Then hand back at most 4 lines: row, the checker verdict word as printed, whether ab2-mark.sh accepted it, and one line describing anything odd (or "nothing odd"). Do not write reports or other files.

Never contact Shay or other agents. Never touch any file except through the commands above. Do not retry anything.
```
(Print it with `type C:\KenshiTestRuns\pilot\ab2\brief.md`; the router prepends one `Routing: case=bench tier=kenshi-bench ticket=` line to every prompt, the same for both arms.)
Core text of the restriction: "run the row via its one-call script, read the checker RESULT line, record it, escalate (stop and hand back) on ANYTHING odd; no debugging, no editing scripts", plus the STOBE-AUTO BAN (PI-48) paragraph.

## After the 20th run
1. `python -I C:\KenshiModding\tools\automation\pilot-ab2\pilot-ab2-compare.py --out C:\KenshiTestRuns\pilot\ab2\COMPARISON.md` (per row: checker verdict of each arm, operator verdict + agree flag, escalations, refusals, script wall, operator wall, tokens, API-price USD, status-count check of each agent's status file, drift notes; totals per arm).
2. Cleanup: delete `C:\KenshiTestRuns\pilot\ab2\ACTIVE` (re-enables real setupfail tickets and the normal stobe-auto rules); for each row touched `powershell -File C:\KenshiModding\tools\automation\row-attempts.ps1 reset 5090-i4 <ROW> "ab2 done"`; stop the lane (`kenshi-ctl.ps1 stop` with KAH_INSTANCE=4, `lane-backend.sh stop i4`) or keep it held; `testruns-sweep.ps1`. The evidence under `pilot\ab2\<arm>\` stays until the compare is read.
3. Tell Shay: verdict agreement per row, escalations, wall, tokens/USD per arm, any drift/refusal events, status-count mismatches.
