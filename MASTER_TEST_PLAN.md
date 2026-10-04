# Master test plan (all features, one game)

Index of every open test, one coordinator session runs Kenshi (roles, loop, scenario format: `testing/README.md`; goal,
run rules and to-do list: `testing/HANDOFF.md`). **Open rows only:** a row that passed is deleted (line in the run log
`archive/test-run-<date>-m<n>.md`); rows passed before 2026-10-03 m19 are listed in `archive/test-run-2026-10-03-m19.md`
("master plan pruned"). IDs: `<feature> <row>` (STOBE 41, PG 306, REL SR02, KAH 3).

| Feature | Detail plan (source of truth) | Scenarios |
|---|---|---|
| STOBE + KenshiFP | `STOBE_full_test_plan.md` | `tests/ingame/stobe/` |
| Profession Gear (PG) | `Kenshi-Profession-Gear-Progression/TEST_PLAN.md`, status `INGAME_STATUS.md` | PG repo `tests/ingame/` (`RUN_ORDER.md`) |
| Relationship system (REL) | `STOBE_relationship_system_audit_and_implementation_plan.md` (SR01–SR44) | `/var/www/html/StobeServer/tests/social_relationship/ingame/` |
| Harness (KAH) | this file, section 5 | `C:\KenshiTestRuns\scenarios\` |

Machines: the 5090 (STOBE, KenshiFP, REL, server, perf rows) and the 4080 rig (PG + harness only, results labelled
"-4080"). Never compare performance across machines.

## 0. Builds

| Component | Installed (5090) | Install at the next restart |
|---|---|---|
| Stobe.dll | `80E8816A` (REL seed race d8cb37f + squad-member world-event sweep 06e032d, installed m29 for batch O) | - |
| KenshiFP.dll | `0349AA2A` (missing-input log ring 9e9a9e0) | - |
| ProfessionGearProgression.dll | `D7A60E49` (paused: Normal config + Normal rules) | `266C68F5` (PG 250, 4080) |
| AutomationHarness.dll | `9DB0D416` (`cage` free cage + KO first 4b53da0, `stat` mod= fd9a84e, `@any` cd21aa8; installed m29) | 4080: same build, operator m29 installs |
| Server (live) | `stobe` 90a92e8 (A8 workstation destination; rel-enslaved poll c01292f) | - |

## 1. Open automated rows

m22 resumed (m29, 2026-10-04): batches D-N reconciled (passes deleted, evidence in `archive/test-run-2026-10-03-m22.md`). Running: batch O (`m22\list-o.txt`, out `m22\out-o`: Enslaved, A8 grow, SR18/19 Full-Base) with the builds above. Automated runs use graphics mods off (`gfx-mods.sh off --hdtex`).

Memory baseline (Shay 2026-10-04): first-commit DLLs vs current, Kenshi +171 MB at load 0 and less growth per load (118 vs 134 MB/load); no bug. Graphics A/B: Dust/ReShade off -0.6 GB, HD detail textures off another -2.6 GB (9.3 GB private at load 0). Report `MEMORY_BASELINE_2026-10-04.md`.

Status: `todo` / `rerun <batch>` / `FAIL <run> -> item` / `PASS` (then delete the row).

| ID | What | Save | Status |
|---|---|---|---|
| STOBE A8 | bread chain grow on Full-Base | Full-Base | N: no bread goal ('do not know how to reach Campfire') -> server 90a92e8 (station/base building = here); confirm in batch O |
| REL SR12, SR32, p7 | real enslavement capture; freeing by `order`; free a non-squad slave + recruitment gate | Enslaved | N: p7-03 FAIL = seed race; Stobe d8cb37f (in 80E8816A, installed) + test poll c01292f; confirm in batch O |
| REL SR18/19 | bed/cage rescue on a second base (PASS on auto-home) | Full-Base | N: SR18 35/2 capture missing, SR19 actor=#0 + crash after `cage` -> Stobe 06e032d squad sweep + harness 4b53da0; confirm in batch O |
| PG rows | open PG rows (balance 161-210, 89, 132/133/240, 145/229, 151/152, 184, 188-192, 220-227, 250, 254, 274) | 4080 + Full-Base | PG validation gate first (CLAUDE.md): 4080 operator m29 running gate per profession, then pg-89 full, pg-55 (pinned dummies d6bb99b), pg-51 (Sickle @any 57e0381). Provisional (before gate): crafting/science valid; engineering gear no effect (product?); medic flat (kit-driven); athletics/swimming capped; stealth + lockpicking measurement broken; assassination/swimming gear only with FormulaScaling (Shay decision); thievery works; farming crop-state dominated; perception unrun. See INGAME_STATUS.md |

## 2. Requires Shay

| ID | What |
|---|---|
| Voice / feel | voice quality, overall play feel, relationship balance feel (REL §9) |
| PG 135–141, 277 | tooltip section on armour, backpack, weapon/tool, plain item, two-affix item, shop/loot views |
| PG 155, 238 | feel: repeated tooltip opening; no stall when a shop opens |
| PG balance decision | after all professions are measured (Labouring: +25 % gear = whole skill range) |

Deferred by Shay: PG 256 (no Swimming roll in this load order), F 62, F 63.

## 3. Bugs fixed, waiting for in-game confirmation

| Bug | What | Confirm in |
|---|---|---|
| STOBE 70, 108 | template-name relationship keys | any older-save load: no template keys |
| STOBE 86 | older-save load turned later deals into BREACHED_PLAYER | a deal, then an older-save load |
| STOBE 87 | Dust King: no initiative check (covered by 88 + 61 PASS m18) | close at the next surrender run |
| STOBE 94 | reset-npc `--restore` key case | round trip at the end |
| STOBE 96, 97 | surrender payment window; truce cancelled Shay's attack order | REL surrender / accept + `attack` |
| STOBE 101 | `[]` extended_data | rel-enslaved set-relation |
| STOBE 105 | KenshiFP log spam | A8 log |
| REL SR07, SR30 | scenario baselines and post-recruit handle relookup | rel-m18 |
| STOBE 121 | stale ended-goal block reasons made the NPC refuse a new production order (server e0e8e5c) | home PASS m21; grow Full-Base still pending |
| KAH to-do 19 | `walktime`, `newgame`, `pickup`, kah.py `@log`, nested `packput` (installed harness E83B0826) | PG 254, 132/133/240, 120 (4080) |

## 4. Harness (KAH) limits and open items

| # | Item | Status |
|---|---|---|
| KAH 1 | `damage` wounds don't bleed (use `blood`) | limit |
| KAH 4 | `faction` gives the NPC a new #serial | limit |
| KAH 12 | never build a Biofuel Distillery (crash); `build` refuses it | limit |
