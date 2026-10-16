# README_RELOAD_SFE (imm26-sfE2/sfE3): corrected setup recipes for 24-c and 26-f

Files (all new; reloaddefs_a.sh, reload-run.sh, reloadcheck_a.py, cleargroup14c-scene.sh untouched):
`reloaddefs_sfe.sh` (rd_24c, rd_26f override the set-A functions in that shell only), `reload-run-sfe.sh` (runner, same options and exit codes as reload-run.sh),
`reload-py-sfe.sh`, `reloadcheck_sfe.py` (checker), `reloadscen_sfe.py` / `reloadfake_sfe.py` (offline fakes), `seed24c.py` (DB seed), `reload-sfe-selftest.sh` (offline, slow: run detached).

Usage: `bash rowtools/reload-run-sfe.sh <24-c|26-f> <lane> --save <S> [--dry]`. Exactly one `RESULT` line.

## 24-c (recipe A, SEEDED, resume leg only)
Natural 24-b path (region SUGGEST -> consent -> stobeAreaGoalResolve) is unreachable: stobeAreaGoalEndpointValid needs spatial.region_name, never forwarded
(server half proposal: pending-fixes/imm26-sfE2-region-name). So: ordinary native trip (OWNED_TRAVEL accepted=1) -> INSERT a cloned travel_agreement row with kind same_route,
recomputed plan_hash and a regional_goal block (seed24c.py) -> save -> load -> "Where were we going?" -> "I'm right behind you.".
Every RESULT line starts with SEEDED. PASS proves ONLY that an area-goal-shaped trip resumes (chain, regional_goal kept, one OWNED_TRAVEL, MOVE_CUS_ORDERED).
The row stays PARTIAL (not full PASS) until recipe B or the native/server region_name fix exists.
Evidence: seed_py.txt, seed_insert.txt, seeded.txt.

## 26-f (ClearGroup offer + accept + save/load)
Uses the 14-c 4-bandit recipe (PASSed), bandits pinned north of the south wall at z -55624 (inv-14e), not the 5-bandit ring (14-d finding: empty ClearGroup set on 5 bandits).
Needs NC17 Stobe.dll on the lane (pending-fixes/npc-immersion-26/NC17), lane in the Hub save. SCENE-OK needed (Cind sees >= 3 of 4). Accept within ~5 min of the offer.
Evidence: scene.txt, bandits.txt, spawn.txt, reseat.txt. Risk: bandits fight/kill before the save -> act_pre not accepted -> SETUP-FAIL.
