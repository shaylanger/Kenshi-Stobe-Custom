# README_RELOAD_SFI (imm26-sfI): 26-d / 26-dx / 26-e on the hunt26a-scene ground

SETUP-FAIL tickets 26-d, 26-dx, 26-e (5090-i3 op20, 2026-10-16): the set-A recipe spawns "wild goats" `near <npc> dist 7` at the ready-save spot (Copper Mine V). There the NPC has
canISee=0 for the goats (ACTIVITY_SIGHT_DIAG), the candidate is `suitable:false` and no Hunt proposal comes. These rows now build the scene that passes 25-a / 26-a
(`hunt26a-scene.sh`, recipe `agents/out/imm26-26a-recipe/latest.md`) with the generic lane helpers, so any lane works.

Files (all new; reloaddefs_a.sh, reload-run.sh, reloadcheck_a.py, reload-py.sh untouched): `reloaddefs_sfi.sh` (rd_26d, rd_26dx, rd_26e override the set-A functions in that shell only),
`reload-run-sfi.sh` (runner), `reloadfake_sfi.py` / `reloadscen_sfi.py` (offline fakes), `reload-sfi-selftest.sh` (offline, slow: run detached, ~10 min). The checker is the unchanged `reloadcheck_a.py`.

## Use
`bash testing/live-stobe-queue/imm26-assert/rowtools/reload-run-sfi.sh <26-d|26-dx|26-e> <lane> [--save S] [--no-reload] [--dry] [--allow-retry "why"] [--complete]`
`  [--faction "<name>"] [--no-refaction] [--no-apology] [--goats N] [--offer T] [--accept T]` -> `RECORDS` lines + exactly ONE `RESULT <row> PASS|FAIL|SETUP-FAIL|GATED ...` (exit 0/1/2/3/4 as go-row.sh).
i3 reloads `kah-imm26-5090-ready`, i4 `kah-imm26-i4-trip2`; any other lane needs `--save <ready save>` (one where Shay + Cind exist; the scene teleports both to the Hub's E ground).

## What the scene does (reloaddefs_sfi.sh)
1. `rw_prep` with TRIP_QUIET=0 (the quiet scene would send non-squad characters, goats included, away): activity tables + trip rows cleaned, H-AFF 60.
2. Ground: wake/heal NPC, unpin, teleport Shay `-49400 1660 3625` and the NPC `-49422 1661 3643`, select Shay, relation 50, weapons sheathed, 10 s for the navmesh, travel rows deleted, H-AFF friend 60, ctxpush,
   apology "It was a mistake, I'm sorry." (clears the quarrel memory), ctxpush. (`scene.txt`, `plain_say.txt`)
3. Goats: `spawn "wild goats" Herbivore at -49405 1664 3645 count 8 size 0.2` (NOT `near ... dist 7`: goats within ~12 u flee), `chars 80 "[Herbivore]|!dead"`, the first 5 pinned, the NPC re-serialled into
   a non-hostile faction (default Traders Guild; clears baked personal enmity so the accept does not die on `requester_now_hostile`), ctxpush, `face` the first goat, `senses` must give sees=1 for >= 1 goat
   (3 tries, then one respawn). No goat in sight = `SETUP-FAIL SCENE-BAD ...` (never a FAIL). (`scene_pre.txt`, `spawn_pre.txt`, `goats_pre.txt`)
4. Offer (`s1`; one fallback wording `s1b` only when no proposal), then WAIT for the offer speech to be delivered (stobe.log `RECHAT_TIMING: follow-up`, <= 40 s; saying Yes while it is delivered cancels the offer and
   the accept fails with "Explicit scoped consent was not verified"), then the accept (`s2`), 26-dx "Cancel that." (`s2c`). (`delivery_<step>.txt`)
5. Save + load (`rw_save_load`, pins are dropped by the load), then Shay + NPC back on the ground, the goats re-spawned at the same place, pinned and checked again (`scene_post.txt`), then the row's post-load say(s).
Same say numbering and evidence files as set A, so `reloadcheck_a.py` verdicts are unchanged.

## Faction and the 26-a decision
Default: the NPC is re-serialled into **Traders Guild** (the proven 25-a / 26-a scene). Then the Hunt partner is not a player-faction member and the NC17 "player-faction partner allowed when the player requests" decision is not
needed for the Start gate. `--faction Nameless` (the player faction) exercises the NC17 path and needs NC17/NC20 Stobe.dll on the lane. 26-a itself is still FAIL on the native Hunt executor
(`activity_no_verified_progress`, `owned_order_cleanup_pending`): 26-d / 26-dx / 26-e need only the offer, the accept (record `accepted`) and the save+load, not a completed hunt (26-d `--complete` additionally needs the executor fix).

## Env knobs
`RW_FACTION RW_REFACTION=0 RW_APOLOGY=0 RW_APOLOGY_WAIT(8) RW_GOATS(8) RW_PIN_GOATS=0 RW_EG_SHAY RW_EG_NPC RW_EG_GOAT RW_SENSE_TRIES(3) RW_DELIVERY_WAIT(40) RW_ACCEPT_DELAY(1) RW_OFFER2` plus the set-A knobs (README_RELOAD_A.md).
The runner exports `ROW_SETTLE=1` (default 3) so the accept follows the delivered offer quickly.

## Known risks (live)
- Cind's id changes with the faction re-serial; the runner takes the id from the `faction` answer and logs it (`npc id now ...` in scene.txt). A namesake sharing the handle (Cade) would make `stobe_say` hit the wrong NPC: check `resolved_speaker`/reply names in s1.
- The saved game keeps the old goats; the post-load goats are fresh spawns (as in set A). Cind must see one of them for the resume to fire (resume fires on a chat turn while the target is observed).
