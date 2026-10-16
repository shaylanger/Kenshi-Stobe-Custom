# fix26f22b: 26-f Shay KO'd during the row (reloaddefs_sfe.sh.candidate)

Evidence (4080-i4 op16, stobe.log 13:52-13:55): scene SCENE-OK and say 1 worked (resolved_speaker=Shay), but the reply was "Dravos is on me and I'm mid-swing" and the next prep failed. Cause is NOT a KO during the settle:
scene.txt line "WARN no Holy Sentinel id found" = the sentinel-friendly step ran right after the 58 k-unit teleport, before Rebirth had streamed in, so The Holy Nation / Rebirth sentinels stayed hostile to Nameless.
They joined the bandit fight (Druven, Halna, Vesk, Skoval "Initiated attack" on Shay 13:54:22-31), Shay took Kolven's club (health 45%) and was knocked out by Druven's Iron Club at 13:54:39 (before say 1b; protect did not hold).
Fix (function rs_peace + rs_guard): after the ready-wait + settle, retry up to RW_PEACE_TRIES (6 x 5 s) until `chars "Holy Sentinel|!dead"` lists sentinels, `relation <id> 100` for every one found (up to 6, covers both the Rebirth and The Holy Nation factions), then rs_guard
(wake + health 100 + protect on for Shay, protect on for Cind, select Shay). rs_guard also runs before every rl_say of rd_26f (says 1/1b-d, 2, 3). rl_prep_player in rowlib.sh is untouched. Assertions unchanged.
Test: `bash rowtools/fix26f-selftest.sh` (9 checks, all PASS; run against the old file it fails the 3 new ones). reload-sfe/sfi selftests: same 5/46 and 6/58 baseline failures with old and new file (copy-env lane issue), no new failures.
Swap (when no operator uses lane 4080-i4's reloaddefs_sfe.sh): cp reloaddefs_sfe.sh.candidate reloaddefs_sfe.sh   (candidate sha256 prefix ec07f1afc39819c7)
One call (unchanged): bash rowtools/reload-run-sfe.sh 26-f <lane> --save <S>
