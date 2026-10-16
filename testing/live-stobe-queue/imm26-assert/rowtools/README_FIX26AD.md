# README_FIX26AD (imm26-fix26ad): SETUP-FAIL tickets 26-d and 26-a (hunt26a-scene, lane 5090-i5)

Offline work only (no game, lane, server or DB touched). Everything is NEW files (candidates); no queued or running script is edited. The checker `reloadcheck_a.py` and every assertion are unchanged.

## Swap (one command; nothing is overwritten, `mv -n`)
```
cd C:/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools && for f in reloaddefs_sf26ad.sh reload-run-sf26ad.sh hunt26a-run.sh; do mv -n $f.candidate $f; done
```
(none of the three names exists yet, so no queued list can be using them; the selftest also runs before the swap by staging the candidates in a temp copy.)

## 26-d: `reload-run-sf26ad.sh` (= `reload-run-sf26bd.sh` + `reloaddefs_sf26ad.sh`)
Cause (ticket): after the save+load the s3 turn ("Are we still on that job?") only leaves the old record `accepted` with `resume.state=pending` ("restarts as soon as the target is observed again");
the continuation (`resume.continuedAs`, new accepted record, NATIVE_TRAVEL_START) appears ~100 s later, but the dump the checker reads was taken right after the say.
Fix (recipe only): `si_job` run-mode polls `rw_act_dump act_post.txt` every `RW_RESUME_POLL_STEP` (10 s) for at most `RW_RESUME_POLL` (150 s) until the old accepted record is `superseded` AND a record with
`resume.of = old id` is `accepted|completed` with `resume.state=resumed`; only then `out_post`/`act_log_post`/`state_post` are dumped and the unchanged checker runs. Nothing is relaxed: a continuation that
never appears inside the window is still a **FAIL** (selftest `26d-never-resumes-still-fails`), and every checker clause (same agreement terms, new world epoch, exactly one active record, grant re-emitted,
no `start rejected`) runs on the final dump. Evidence `resume_poll.txt` (one line per poll). Also (from the scratch run `defs-sf26bd-tp.sh`, people guard OK at dist 32.7): Shay is teleported next to the
NPC inside the s3 say body, because the people= guard needs her within TalkRadius at that moment (`RW_RESUME_TELEPORT=0` disables). 26-dx (a cancelled Hunt is not resumed) keeps its single immediate dump;
26-e is unchanged.

Run: `bash testing/live-stobe-queue/imm26-assert/rowtools/reload-run-sf26ad.sh 26-d 5090-i5 --inject Hunt [--save kah-imm26-i5] [--complete]` (same options and exit codes as `reload-run-sf26bd.sh`;
Malzin + Nameless defaults). Real wall time grows by up to 150 s only when the continuation is late.

## 26-a: `hunt26a-run.sh` (one command, lane 5090-i5; `hunt26a-scene.sh` itself unchanged)
Cause (ticket): the Hunt is a JOINT trip. After the Yes Malzin walks to the target (~1000 u away) while Shay stands at the scene: `NATIVE_TRAVEL brk_sep:132 participation_qualified=0` then
`ACTIVITY_END_DIAG activity_no_verified_progress` (record failed/timeout, participation not_completed). Also seen in earlier runs: KO by goats, leftover goats, the outlaw fight near The Hub.
What it does: (1) clean: kill every `[Herbivore]` within 150, `give` + `equip` a Katana (give only when none is carried), blood 100, hunger, wake, health 100;
(2) arm the sfO inject (Hunt, Malzin), run `hunt26a-scene.sh` (COUNT=3, REFACTION=0, APOLOGY=0), require `SCENE-OK`; when the offer reply is "...in the middle of a fight" it waits 45 s, kills the goats and
retries (max 4; still refused = SETUP-FAIL); (3) FOLLOW: right after the Yes `teleport Shay <Malzin>` every 4 s while polling the newest NEW Hunt record (ids that existed before the run are excluded) until
`completed|failed|cancelled|expired` or 300 s; (4) verdict from real state: PASS only when the record went proposed -> accepted -> completed, `participationOutcome.status` is set (not `not_completed`),
the agreement's outbox rows are acknowledged and Malzin's inventory gained >= 1 item (Katana excluded). A failed/timeout record is FAIL; no scene / no offer / Yes not landing is SETUP-FAIL.
Prints ONE line `HUNT26A-RUN 5090-i5 PASS|FAIL|SETUP-FAIL <detail> [evidence=<dir>]` (exit 0/1/2); evidence `try<N>/`, `follow.log`, `rec_final.txt`, `rec_summary.txt`, `inv_before/after.txt`, `verdict.txt`.

Run: `bash testing/live-stobe-queue/imm26-assert/rowtools/hunt26a-run.sh [outdir]` (default `C:/KenshiTestRuns/imm26-5090-i5/rows/26-a/run-<ts>`; lane `5090-i5`, game at speed 0.5, Shay + Malzin in squad).

**Deviation to know:** the ticket lists "hunger 0". `hunger` is the game UI value (300 = full) and an earlier lesson (i4op5 handoff) says hunger <= 20 KOs Malzin, so the runner sets `RW_HUNGER` (default **250**).
If you really want 0: `RW_HUNGER=0 bash hunt26a-run.sh`. Optional `RW_HUNT_SPEED=3` runs the follow at game speed 3 (restored to 0.5). **Unverified in game:** that following with Shay (distance <= a few units)
is enough for `participation_qualified=1`, and the exact `inv` JSON shape (the delta uses `"name"` lines plus count-like fields); the first live run decides, evidence is in the dir above.

## Selftest (offline, slow: run detached, about 6 min)
`bash testing/live-stobe-queue/imm26-assert/rowtools/reload-sf26ad-selftest.sh` -> `SELFTEST SF26AD ALL PASS 29/29` (26-d: immediate and delayed continuation pass, never-resumes is a FAIL, poll knob,
s3 teleport before the say and its off switch, 26-dx/26-e unchanged; 26-a: pass, Katana give/no-give, equip/blood/hunger, goat kill, Shay follow teleports, old-record exclusion, failed record = FAIL,
no inventory / no participation = not PASS, fight retry then pass, fight forever / bad scene / accept not landed = SETUP-FAIL; originals unmodified; bash -n). Support files: `reloadscen_sf26ad.py`, `hunt26ascen.py`,
`hunt26afake.py`, `hunt26a-scene-stub.sh`, `hunt26a-inject-stub.sh`.
