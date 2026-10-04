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
| Stobe.dll | `6EBC6403` (aid e1d8eed + thread handle c02f95f) | - |
| KenshiFP.dll | `6E0A031E` (items to 112) | - |
| ProfessionGearProgression.dll | `D7A60E49` (paused: Normal config + Normal rules) | `266C68F5` (PG 250, 4080) |
| AutomationHarness.dll | `70953474` (client fc53dba `@log-wait`) | 4080: kah-pg-wt c5a5c88 (artifact give, `research start any`) + B1EBCA95 power supply |
| Server (live) | `stobe` 2e84508 (C49 4181499; rel-m18 fixes 3f341bc..2e84508) | - |

## 1. Open automated rows

Resumed m22 (Shay 2026-10-03). Batch D results: `C:\KenshiTestRuns\m22\out-d\SUMMARY.txt` (37/16, reconciled m23: passes deleted, evidence in `archive/test-run-2026-10-03-m22.md`). Next: batch E (`m22\list-e.txt`).

Status: `todo` / `rerun <batch>` / `FAIL <run> -> item` / `PASS` (then delete the row).

| ID | What | Save | Status |
|---|---|---|---|
| STOBE 55 (B 55) | fight rules (STOBE plan section E items 1-8): `rel-b55.sh` blocks mode/squad/wild/spar/close/treat/fade/chat/bleed/deal/accident | auto-home | built live; remaining m21 batch stopped before this row; resume B55 after Capture=1 |
| STOBE section C (26, 27, 30-32, 49) | forced test switches / injection | auto-home | D: C49 FAIL verified=0 (server 4181499 fix), C30/C26 INCONCLUSIVE (wrappers 12fac38/0d2b742); rerun E |
| STOBE 16 | crafted-ingredient goal completes with powered benches | Full-Base | D setup fail (OUT dir, fixed); rerun E |
| STOBE A8 | bread chain at home (PASS m17 on Full-Base) | Full-Base | home PASS m21; D Full-Base ALERT (Kral's Chosen raid, RAID_CALM added); rerun E |
| TRADE prices | deal prices at r = -80…+100 (buy -30 %…+1000 %, sell +10 %…-90 %) | auto-home | D 27/28 PASS (ledger = formula -50..+100, -80 no deal); sell -80/1 wrapper bug fixed 58d943f; rerun E |
| TRADE shop real | shop window with a real spawned trader (`REAL_TRADER=1`) | kah-trader | in batch E (shop-prices/floor/block-rt) |
| WILL paylater | no pay-later below 0 | auto-home | D INCONCLUSIVE (model refused at r=0 too); wrapper injects the same ACCEPT both sides (2fa6371); rerun E |
| KAH 5 | `power <battery> charge` on a real Battery Bank | Full-Base | D 4/3 (battery search radius, fixed r=3000); rerun E |
| REL SR12, SR32, p7 | real enslavement capture; freeing by `order`; free a non-squad slave + recruitment gate | Enslaved | m18 p7-04 15/2, p7-05 21/1: analyse, fix, rerun |
| REL SR09, SR13, SR14 | theft seen/unseen + theft_caught (`drop … owned`, native theft_caught) | auto-home | D FAIL SR09/13 seen/14; SR13 unseen PASS = invalid evidence; fixer 7 (Nomads owner, stobe_ready, witness); rerun E rel-m18-r |
| REL SR07 | limb loss (`sever`) | auto-home | D FAIL (attribution window); re-attack fix 1e15790; rerun E |
| REL SR06, SR30 | forced first strike / join attempt (`SOCIAL_TEST_FORCE_*`) | auto-home | D: SR30 low trust PASS; SR06 + SR30 trusted FAIL (fixes a83011e, ac5ff4b); rerun E |
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
| STOBE C49 | renamed partner/current roster payment routing (server 4181499) | C49 auto-home |
| REL SR07, SR30 | scenario baselines and post-recruit handle relookup | rel-m18 |
| STOBE 118 | spoken offer paid before agreement | TRADE prices |
| STOBE 121 | stale ended-goal block reasons made the NPC refuse a new production order (server e0e8e5c) | home PASS m21; grow Full-Base still pending |
| KAH to-do 19 | `walktime`, `newgame`, `pickup`, kah.py `@log`, nested `packput` (installed harness E83B0826) | PG 254, 132/133/240, 120 (4080) |

## 4. Harness (KAH) limits and open items

| # | Item | Status |
|---|---|---|
| KAH 1 | `damage` wounds don't bleed (use `blood`) | limit |
| KAH 2 | `messages` didn't see vanilla game messages | fixed (8341146), confirm |
| KAH 3 | shop-barrel `trade` named the barrel as seller | fixed (7778508), confirm |
| KAH 4 | `faction` gives the NPC a new #serial | limit |
| KAH 12 | never build a Biofuel Distillery (crash); `build` refuses it | limit |
