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
| Stobe.dll | `137286B7` (rename guard 9af0971 + game theft-dialog hook a99f498) | - |
| KenshiFP.dll | `2092A07C` (feed carried inputs first da02382, missing-dep need ba0fb83) | - |
| ProfessionGearProgression.dll | `D7A60E49` (paused: Normal config + Normal rules) | `266C68F5` (PG 250, 4080) |
| AutomationHarness.dll | `4B835FCC` (`chars` filter a8005d3, `face` d91fe88, `senses`, `fill optional`) | 4080: D3B372F9 (operator m26) |
| Server (live) | `stobe` 9f6fc55 (rollback keeps squad 04fc777, SR09 face 9f6fc55) | - |

## 1. Open automated rows

Resumed m22 (Shay 2026-10-03). Batch D/E reconciled (E: 57/14, `C:\KenshiTestRuns\m22\out-e\SUMMARY.txt`; passes deleted, evidence in `archive/test-run-2026-10-03-m22.md`). Running: batch F (`m22\list-f.txt`: rel-m18 + rel-b55 retests).

Memory baseline (Shay 2026-10-04): first-commit DLLs vs current, Kenshi +171 MB at load 0 and less growth per load (118 vs 134 MB/load); no bug. Report `MEMORY_BASELINE_2026-10-04.md`.

Status: `todo` / `rerun <batch>` / `FAIL <run> -> item` / `PASS` (then delete the row).

| ID | What | Save | Status |
|---|---|---|---|
| STOBE section C (31, 32) | misquoted counter amounts; REJECT naming a price | auto-home | never reproduced live; candidates for injection rows |
| STOBE 16 | crafted-ingredient goal completes with powered benches | Full-Base | J: goal blocked "pack full" 7 s in (fetched Iron Plates while carrying the Crossbow inputs) -> KenshiFP da02382; rerun L |
| STOBE A8 | bread chain grow on Full-Base | Full-Base | J: raid KO -> whole-row raid guard 7e937ef + `chars` filter; rerun L |
| REL SR12, SR32, p7 | real enslavement capture; freeing by `order`; free a non-squad slave + recruitment gate | Enslaved | m18 p7-04 15/2, p7-05 21/1: analyse, fix, rerun |
| REL SR18/19 | bed/cage rescue on a second base (PASS on auto-home) | Full-Base | todo |
| PG rows | open PG rows (balance 161-210, 89, 132/133/240, 145/229, 151/152, 184, 188-192, 220-227, 250, 254, 274) | 4080 + Full-Base | pg-09 soak 24/0 PASS D (5090); 4080 operator m23 rerunning pg54/84/81/80/52/53/82/87-fs/89 + home list; see INGAME_STATUS.md |

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
