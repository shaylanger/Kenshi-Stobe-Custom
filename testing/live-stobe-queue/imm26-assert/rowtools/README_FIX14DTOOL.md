# fix14dtool (imm26, 2026-10-16): row 14-d tooling, from inv14d (agents/out/imm26-inv14d/latest.md)
- F2 (all rows): `rowcheck.first_reply` and the `rowlib.sh` rl_say reply wait pick the NPC reply by speaker NAME (say.txt `target=<full name>`), not by the `(NPC)`/`(PC)` log tag
  (tag = isPlayerCharacter() of the speaker; a Nameless-faction NPC logs `(PC)`). No `target=` line = legacy `(NPC)` match. Selftest: `fix14dtool_selftest.sh` (14/14, fixtures `fix14dtool_fixtures/` = real 14-d evidence).
- F3 (14-d only, v1 files untouched): `unblockrun_14d_v2.sh` + `unblockdefs_14d_v2.sh` + `unblockfake_14d_v2.py` + `unblock_14d_v2_selftest.sh` (47/47). FAR bandit = own `spawn` as another faction
  (`--far-faction`, default "Starving Bandits") or own squad (`--far-spawnt`); the scene gate requires the probe's offered agreedTargets == exactly the 5 NEAR serials, else SETUP-FAIL with the cause.
- Run: `bash unblockrun_14d_v2.sh 14-d <lane> --allow-retry "<why>" --ask "Hunt 5 bandits."` (also `"Hunt the 5 bandits."`).
