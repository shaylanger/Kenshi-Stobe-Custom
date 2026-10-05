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
| Stobe.dll | `80E8816A` (REL seed race d8cb37f + squad-member world-event sweep 06e032d) | `5B148D87` (carry events for the player actor 26b6133, REL SR18) |
| KenshiFP.dll | `0349AA2A` (missing-input log ring 9e9a9e0) | - |
| ProfessionGearProgression.dll | `D7A60E49` (paused: Normal config + Normal rules) | `266C68F5` (PG 250, 4080) |
| AutomationHarness.dll | `9DB0D416` (`cage` free cage + KO first 4b53da0, `stat` mod= fd9a84e, `@any` cd21aa8; installed m29) | 4080: same build, operator m29 installs |
| Server (live) | `stobe` dcabbfd (A8 station destination 90a92e8, background-processor live-DB guard 27d411e, p7-05 lockpickable slave 619d7eb, Terrorism not theft dcabbfd) | stray test-DB processor (WSL 1632/1641) must be killed or WSL restarted (Shay) |

## 1. Open automated rows

m22 resumed (m29, 2026-10-04): batches D-N reconciled (passes deleted, evidence in `archive/test-run-2026-10-03-m22.md`). Running: batch O (`m22\list-o.txt`, out `m22\out-o`: Enslaved, A8 grow, SR18/19 Full-Base) with the builds above. Automated runs use graphics mods off (`gfx-mods.sh off --hdtex`).

Memory baseline (Shay 2026-10-04): first-commit DLLs vs current, Kenshi +171 MB at load 0 and less growth per load (118 vs 134 MB/load); no bug. Graphics A/B: Dust/ReShade off -0.6 GB, HD detail textures off another -2.6 GB (9.3 GB private at load 0). Report `MEMORY_BASELINE_2026-10-04.md`.

Status: `todo` / `rerun <batch>` / `FAIL <run> -> item` / `PASS` (then delete the row).

| ID | What | Save | Status |
|---|---|---|---|
| PG rows | open PG rows: balance = Shay decisions (206 farming gear too strong, medic saturation by Medic 50, 199 perception flat 1.4-1.9 s, 191, athletics +38% max / +6% 30 m runs, crossbow lab50 1.60); 132 BLOCKED-vanilla (import into a new game crashes Kenshi +0x94d6db even with PG not loaded); 135-141/155/238/277 Shay-only (section 2) | 5090, Full-Base | m39: everything else PASS-live/offline in PG INGAME_STATUS.md (Z2: 250; Y3: 254, 199; I2: 133, 240; 256 by roll census). Run log archive/test-run-2026-10-03-m22.md |

## 2. Requires Shay

| ID | What |
|---|---|
| Voice / feel | voice quality, overall play feel, relationship balance feel (REL §9) |
| PG 135–141, 277 | tooltip section on armour, backpack, weapon/tool, plain item, two-affix item, shop/loot views |
| PG 155, 238 | feel: repeated tooltip opening; no stall when a shop opens |
| PG balance decision | after all professions are measured (Labouring: +25 % gear = whole skill range). Open decisions D1-D8 below |

### Open Shay decisions (m39, 2026-10-05; everything else is tested, Kenshi closed, nothing running)
Data: 4080 matrix `C:\KenshiTestRuns\pgbal-4080\m35-analysis.txt` ("Cross-profession" block), 5090 batches in `archive/test-run-2026-10-03-m22.md`, rows in PG `INGAME_STATUS.md`.

| # | PG row | Finding | Question for Shay |
|---|---|---|---|
| D1 | 206 farming | +25% gear = +40.9% output, +50% gear = +108.7% (per gear point 2.17, the highest of all; others 0.44-0.73 except crossbow). Skill 25 + 50% gear (0.888) out-produces skill 75 with no gear (0.675) = row FAIL | Lower the farming gear multiplier (e.g. to ~0.5 per point like the other trades), or accept? |
| D2 | 191 medic | Healing time s10 6.37 / s90 18.3 rate, but +50% gear = +0.1%: the Standard kit already saturates by Medic 50 (12.4 s at 10, 4.5 s at 50 and 90), so gear has nothing left to improve | Change how medic gear applies (e.g. scale kit quality/heal amount instead of speed), cap lower, or accept that medic gear does nothing past 50? |
| D3 | 199 perception | 16 observers, perception 10-90 x gear 0-50: detection always 1.4-1.9 s. Game 1.0.65 detection doesn't seem to use perception at this setup (stealth 195 also flat ~1.5 s at 20 m) | Accept perception gear as cosmetic for detection, give it another effect, or have us test other distances/angles? |
| D4 | 254 athletics | +50% Athletics gear: top run speed 81.8 -> 113.1 u/s (+38%), but ~30 m runs only 75.8 -> 80.6 u/s (+6%, acceleration dominates short runs) | Fine as is, or also boost acceleration so short runs feel it? |
| D5 | 190 crossbow | +50% gear = +99.6% output (per point 1.99, 2x the other smithing trades); lab-level-50 control 1.60 (should be ~1.0; science 0.75, robotics 0.84 also off) | Lower crossbow gear multiplier? Rerun the lab50 controls to rule out noise first (our default unless you say otherwise) |
| D6 | 192 turrets | Turrets never fire at a pinned training dummy unless it is designated (harness `turret ... aim`); with designation the mechanic PASSes, per-shot damage noisy (n=1) | Accept (vanilla targeting behaviour) and close balance, or want a longer turret run for damage balance? |
| D7 | 132 import | Importing a character into a NEW game crashes Kenshi every time (kenshi_x64+0x94d6db read 0x270), with import all/squad/unpaused/game's own dialog, and with PG not loaded (dump `C:\KenshiTestRuns\crash-m37-i4-nopg\`); the 4080 crashes too without Stobe/KenshiFP = vanilla/mod stack, not PG | Close as "not ours" (row stays BLOCKED-vanilla), or bisect the other mods to find the culprit? |
| D8 | 191 medic files | `full-base/pg-84-balance-medic.txt` scenario files drifted from `tools/balance_driver.py` (kit refill fix PG b1cde2f: `give 1` with 16 kits held) | No decision needed: TO-DO for us = regenerate pg-84 from balance_driver.py and diff before any medic rerun |

**Shay answers (2026-10-05, m41):** D1 lower farming gear to ~0.5/pt (like the other trades), rerun 206. D2 medic gear scales heal amount/kit quality instead of speed, rerun 191. D3 drop Perception from gear (no Perception affixes; goggles/scout gear roll other stats), row 199 closes as "removed". D4 try acceleration: find + hook run acceleration (with deceleration), test doorways/short runs, Shay judges the feel. D5 rerun lab50 controls first (default), then decide the crossbow multiplier. D6 accept, close 192 balance. D7 close 132 as a game bug, not ours. D8 our to-do as before.

**After reboot (resume):** read `testing/HANDOFF.md` + newest `coordinator-handoff-m40.md` (temp folder, copy in `handoff/`). Kenshi graphics mods are still OFF: `bash C:/KenshiModding/tools/automation/gfx-mods.sh on` before playing. PG config already Normal/Normal, game lock released. Once Shay answers D1-D7: apply the balance changes in PG config, rebuild/install PG, rerun only the affected rows' matrix points (gate first, RUN_ORDER.md).

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
