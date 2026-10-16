# README_RELOAD_SFJ: recipes for the SETUP-FAIL tickets 23-e and 20-d (imm26-sfJ, 2026-10-16)

Evidence: `C:\KenshiTestRuns\imm26-5090-i3\rows\23-e`, `...\20-d`, `...\20-a` (5090-i3, op20). Test tooling only: no game, DLL, server or lane change.

## Run (one call, from the repo root; same options/exit codes/one RESULT line as reload-run.sh)
    bash testing/live-stobe-queue/imm26-assert/rowtools/reload-run-sfj.sh <23-e|20-d> <lane> [--save S] [--no-reload] [--dry] [--allow-retry "why"] [--alt "<place>"]
Offline proof: `bash testing/live-stobe-queue/imm26-assert/rowtools/reload-sfj-selftest.sh` (WSL; prints `SELFTEST SFJ ALL PASS n/n`).

## 23-e legacy FOLLOW across a reload
Old verdict: SETUP-FAIL "follow did not work BEFORE the save (57.1 -> 43.5)". The follow itself works (FOLLOW assigned, FOLLOW_TICK every 2 s); the follower simply keeps a stand-off of about
40-60 u (79.7 u teleport -> 57.1 u two seconds later -> 43.5 u after 30 s at speed 3), so the set-A threshold `end <= 35` can never pass. Same class as 27-a (`pending-fixes/27a-recipe`).
- `rd_23e` (reloaddefs_sfj.sh): NEGATIVE CONTROL chase BEFORE "Follow me." (no order, Shay `RW_AWAY_F` (120) u away, 45 s at speed 3, `chase_ctrl.txt`), NPC teleported back, "Follow me.", pre chase,
  save+load, post chase. Every chase samples the distance every 5 s (`chase_<tag>.series`); the FOLLOW log of the pre chase window is kept (`follow_log_chase_pre.txt`).
- Checker (reloadcheck_sfj.py): ctrl start >= 90 and end >= 0.8 x start (else SETUP-FAIL "NPC approaches Shay without a FOLLOW order" / "control chase: Shay only n u"); pre start >= 90, end <= `RW_FOLLOW_NEAR` (70)
  and < start; post: FOLLOW_TICK after the load, no FOLLOW_EXPIRED / setDestination failed, start >= 90, end <= 70 and < start.
- Knobs: `RW_AWAY_F` (120), `RW_AWAY_DIR` (x | -x | z | -z; use another direction if the teleport lands in rock: the ctrl line then says start < 90), `RW_CHASE_S` (45), `RW_FOLLOW_NEAR` (70), `RW_FOLLOW_MIN_START` (90).
- If the real series shows the follower parking at a stand-off above 70 u, raise RW_FOLLOW_NEAR (the series file has the numbers) or read `follow_log_chase_pre.txt`; do not weaken the control.

## 20-d pending plan change across a reload
Root cause (proved from the evidence): `travel_alternatives.pending_change` is written by `lib/travel_companionship.php` `if ($isReplace)` -> `stobeImm26PendingChangeWrite`, i.e. only when the NPC answers a
change request with `travel_decision=REPLACE`. The first request "Actually, go to the Stumble Inn instead." never got REPLACE, in 20-d AND in 20-a: 20-a/s3 NPC "Which is it: you still want Squin, or ..." (no
travel_alternatives row), 20-d/s3 NPC "If you're set on the Inn, say so and we'll call the Squin trip off." (alt_pre.txt empty). The 20-a pending_change (rowid 22446) was written one turn LATER, on the
insistence turn "Yes, I mean it. I am sure, change it to the Stumble Inn." (20-a/s4/events.txt; NPC: "Confirm that and I'll lead."). So the ticket premise "20-a recorded it on its first leg" was wrong: the
first-leg wording is identical in both rows; 20-d just lacked the second turn. No server defect: the prompt block, the write and the 6 h freshness window are all present (compose lib/imm26_plans.php l.66-95, 260).
- `rd_20d` (reloaddefs_sfj.sh): trip setup, NPC teleported next to Shay + Shay sheathed/protected before EVERY turn (in 20-a the NPC walked to 326 u away and `destination_candidate_counts places=0` made the later
  confirm fail), s3 change request, then up to 3 insistence wordings (`s3c1..s3c3`, stop at the first travel_alternatives row with pending_change; `insist_turns.txt`), then the unchanged remainder: save+load,
  bare "Yes." (`s4`), `alt_after_yes.txt`, checker `c_20d` (unchanged). No pending_change after 3 turns = SETUP-FAIL as before (no save/load is spent).
- Knobs: `RW_20D_CONFIRM1/2/3` (wordings), `--alt` / `RW_ALT`, `RW_20D_RESUME_FIRST=1`.
- Not covered (separate): the 20-a confirm turn s4b failed because the LLM did not answer ACCEPT while the NPC was 326 u away with no place candidates; the calm/near-NPC steps above should also help 20-a, but
  that row's script (unblockdefs_c.sh) is not changed here.
