# Master test plan (all features, one game)

Index of every open test, one coordinator session runs Kenshi (roles, loop, scenario format: `testing/README.md`; goal,
run rules and to-do list: `testing/HANDOFF.md`). **Open rows only:** a row that passed is deleted (line in the run log
`archive/test-run-<date>-m<n>.md`); rows passed before 2026-10-03 m19 are in the m19 run log (git history).
IDs: `<feature> <row>` (STOBE 41, PG 306, REL SR02, KAH 3).

| Feature | Detail plan (source of truth) | Scenarios |
|---|---|---|
| STOBE + KenshiFP | `STOBE_full_test_plan.md` | `tests/ingame/stobe/` |
| Profession Gear (PG) | `Kenshi-Profession-Gear-Progression/TEST_PLAN.md`, status `INGAME_STATUS.md` | PG repo `tests/ingame/` (`RUN_ORDER.md`) |
| Relationship system (REL) | `docs/RELATIONSHIP_SYSTEM_DESIGN.md` section 8 (open SR rows) | `/var/www/html/StobeServer/tests/social_relationship/ingame/` |
| KenshiFP FP combat | `components/KenshiFP/docs/COMBAT_TEST_PLAN.md` (context `FP_COMBAT_COORDINATION_CONTEXT.md`) | `components/KenshiFP/tests/ingame/` |
| Harness (KAH) | this file, section 5 | `C:\KenshiTestRuns\scenarios\` |

Machines: the 5090 (STOBE, KenshiFP, REL, server, perf rows) and the 4080 rig (PG, harness and KenshiFP combat rows,
results labelled "-4080"). Never compare performance across machines.

## 0. Builds

| Component | Installed (5090) | Install at the next restart |
|---|---|---|
| Stobe.dll | `7A8997FD` (goal/action logic moved in from KenshiFP + NPC info panel; 2026-10-06 m49) | - |
| KenshiFP.dll | `FE26573F` both rigs (FP-only after the decoupling + eye-drift fix; 2026-10-06 m49) | - |
| ProfessionGearProgression.dll | `BAFB8C31` (Normal; verified 2026-10-05) | - |
| AutomationHarness.dll | `2995EE5E` (both rigs, 2026-10-06) | - |
| Server (live) | `stobe` 0295a3a (14-A3 "no promises" hedge fix; earlier: NPC panel player_view 2596ef2) | - |

## 1. Open automated rows


Memory baseline (Shay 2026-10-04): first-commit DLLs vs current, Kenshi +171 MB at load 0 and less growth per load (118 vs 134 MB/load); no bug. Graphics A/B: Dust/ReShade off -0.6 GB, HD detail textures off another -2.6 GB (9.3 GB private at load 0). Report `archive/MEMORY_BASELINE_2026-10-04.md`.

Status: `todo` / `rerun <batch>` / `FAIL <run> -> item` / `PASS` (then delete the row).

| ID | What | Save | Status |
|---|---|---|---|
| FP combat | open: M09, S05, C01-C05 beyond C00, Gate 3 balance acceptance; reconfirm on FE26573F (passed on older builds): R10, R12 (UI/KO/SWAP/SPEED/LOAD), R14-R16, M08 (all 7), S03; manual combat still OFF by default | kah-fpxbow (fixture FP-crossbow), kah-fpcam | todo; PASS on FE26573F (m49): R07-R09, R11, R13, FP-EYE both rigs, S01 (= DC1-DC5); earlier builds: P01, P02, C00, R01-R06, S04, M00-M07 (4080) |
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

## 4. Harness (KAH) limits and open items

| # | Item | Status |
|---|---|---|
| KAH 1 | `damage` wounds don't bleed (use `blood`) | limit |
| KAH 4 | `faction` gives the NPC a new #serial | limit |
| KAH 12 | never build a Biofuel Distillery (crash); `build` refuses it | limit |
