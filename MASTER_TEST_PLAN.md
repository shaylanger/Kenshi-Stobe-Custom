# Master test plan (all features, one game)

Index of every open test, one coordinator session runs Kenshi (roles, loop, scenario format: `testing/README.md`; goal,
run rules and to-do list: `testing/HANDOFF.md`). **Open rows only:** a row that passed is deleted (line in the run log
`archive/test-run-<date>-m<n>.md`); rows passed before 2026-10-03 m19 are listed in `archive/test-run-2026-10-03-m19.md`
("master plan pruned"). IDs: `<feature> <row>` (STOBE 41, PG 306, REL SR02, KAH 3).

| Feature | Detail plan (source of truth) | Scenarios |
|---|---|---|
| STOBE + KenshiFP | `STOBE_full_test_plan.md` | `tests/ingame/stobe/` |
| Profession Gear (PG) | `Kenshi-Profession-Gear-Progression/TEST_PLAN.md`, status `INGAME_STATUS.md` | PG repo `tests/ingame/` (`RUN_ORDER.md`) |
| Relationship system (REL) | `STOBE_relationship_system_audit_and_implementation_plan.md` section 8 (open SR rows) | `/var/www/html/StobeServer/tests/social_relationship/ingame/` |
| KenshiFP FP combat | `components/KenshiFP/docs/COMBAT_TEST_PLAN.md` (context `FP_COMBAT_COORDINATION_CONTEXT.md`) | `components/KenshiFP/tests/ingame/` |
| Harness (KAH) | this file, section 5 | `C:\KenshiTestRuns\scenarios\` |

Machines: the 5090 (STOBE, KenshiFP, REL, server, perf rows) and the 4080 rig (PG, harness and KenshiFP combat rows,
results labelled "-4080"). Never compare performance across machines.

## 0. Builds

| Component | Installed (5090) | Install at the next restart |
|---|---|---|
| Stobe.dll | `DAF1390F` (NPC info panel; verified 2026-10-05) | - |
| KenshiFP.dll | `4FD22DEF` both rigs (main ac56752: manual ranged/melee adapter, spatial wounds, wound pick diagnostics; 2026-10-06) | - |
| ProfessionGearProgression.dll | `BAFB8C31` (Normal; verified 2026-10-05) | - |
| AutomationHarness.dll | `2995EE5E` (both rigs, 2026-10-06) | - |
| Server (live) | `stobe` dcabbfd (A8 station destination 90a92e8, background-processor live-DB guard 27d411e, p7-05 lockpickable slave 619d7eb, Terrorism not theft dcabbfd) | - |

## 1. Open automated rows


Memory baseline (Shay 2026-10-04): first-commit DLLs vs current, Kenshi +171 MB at load 0 and less growth per load (118 vs 134 MB/load); no bug. Graphics A/B: Dust/ReShade off -0.6 GB, HD detail textures off another -2.6 GB (9.3 GB private at load 0). Report `MEMORY_BASELINE_2026-10-04.md`.

Status: `todo` / `rerun <batch>` / `FAIL <run> -> item` / `PASS` (then delete the row).

| ID | What | Save | Status |
|---|---|---|---|
| FP combat | open: R10, 5090 R11 rerun pending (b10 invalid: raid; Dust Bandit raid hit the shooter = setup failure, raid guard 16dc0b3; rerun `C:\KenshiTestRuns\fp-5090-11`), R12 remainder (UI focus, KO, save/load, weapon swap, speed/FPS), M08, M09, Gate 3 (R14-R16), S01, S03, S05; manual combat still OFF by default; Full-Base hand-over/fetch regression waits on Shay deleting the Avarek/Beaks Stobe DB rows | kah-fpxbow (fixture FP-crossbow), kah-fpcam | todo; PASS: P01, P02, C00, R01-R09, R13, S04, M00-M07 (4080), R11 (4080), R12 subset (run log m41) |
| PG rows | open: D4 athletics feel (Shay, section 2); 135-141/155/238/277 Shay-only (section 2); 256 deferred | 5090, 4080 | all automated PG rows PASS-live/offline (PG INGAME_STATUS.md); D1-D3, D5-D8 done (run log m41) |

## 2. Requires Shay

| ID | What |
|---|---|
| Voice / feel | voice quality, overall play feel, relationship balance feel (REL §9) |
| PG 135–141, 277 | tooltip section on armour, backpack, weapon/tool, plain item, two-affix item, shop/loot views |
| PG 155, 238 | feel: repeated tooltip opening; no stall when a shop opens |
| PG balance decision | after all professions are measured (Labouring: +25 % gear = whole skill range); D4 feel open |

### Shay decision D4 (D1-D3, D5-D8 done m41-m47; run log `archive/test-run-2026-10-05-m41.md`)

| # | PG row | Outcome |
|---|---|---|
| D4 | 254 athletics | **feel row for Shay**: +50% gear reaches half run speed ~25% faster (t50 0.30 vs 0.40 s, 3 batches), top speed +38% unchanged; the 50->90% ramp and stopping don't change: in 1.0.65 they come from the path slow-down / move-order delay / halt routine, not the acceleration value (both acceleration reads hooked, PG f212cbc; on-screen verified). Play and judge whether short runs feel right |


Graphics mods may still be OFF on the 5090: `bash C:/KenshiModding/tools/automation/gfx-mods.sh on` before playing.

Deferred by Shay: PG 256 (no Swimming roll in this load order), F 62, F 63.

## 3. Bugs fixed, waiting for in-game confirmation

| Bug | What | Confirm in |
|---|---|---|
| STOBE 70, 108 | template-name relationship keys | any older-save load: no template keys |
| STOBE 86 | older-save load turned later deals into BREACHED_PLAYER | a deal, then an older-save load |
| STOBE 87 | Dust King: no initiative check (covered by 88 + 61 PASS m18) | close at the next surrender run |
| STOBE 94 | reset-npc `--restore` key case | round trip at the end |
| STOBE 101 | `[]` extended_data | rel-enslaved set-relation |
| STOBE 105 | KenshiFP log spam | A8 log |

## 4. Harness (KAH) limits and open items

| # | Item | Status |
|---|---|---|
| KAH 1 | `damage` wounds don't bleed (use `blood`) | limit |
| KAH 4 | `faction` gives the NPC a new #serial | limit |
| KAH 12 | never build a Biofuel Distillery (crash); `build` refuses it | limit |
