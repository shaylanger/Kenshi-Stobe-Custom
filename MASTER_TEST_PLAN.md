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
| Stobe.dll | `CA758842` (shop pricing hook 103/104, -90 % sell side; REL theft_caught) | `66620F55` (B 55 vitals on waking) |
| KenshiFP.dll | `6E0A031E` (items to 112) | - |
| ProfessionGearProgression.dll | `D7A60E49` (Forced + InGameTest during tests) | `266C68F5` (PG 250, 4080) |
| AutomationHarness.dll | `33087EDE` | `609C459C` (to-do 19 fixes + `hit`) |
| Server (live) | B 55 `1392155`, items 104, 100 (b), 110 + lock, 118-121 | - |

## 1. Open automated rows

Status: `todo` / `rerun <batch>` / `FAIL <run> -> item` / `PASS` (then delete the row).

| ID | What | Save | Status |
|---|---|---|---|
| STOBE 55 (B 55) | fight rules (STOBE plan section E items 1-8): `rel-b55.sh` blocks mode/squad/wild/spar/close/treat/fade/chat/bleed/deal/accident | auto-home | built live, 63 unit checks; m19c |
| STOBE 21 | pay-later breach (`STOBE-21-paylater-breach.sh`, `protect`) | home + Full-Base | PASS m16 home; confirming reruns m19b (Full-Base: items 107, 100 b) |
| STOBE 22 | gang stands down on a paid deal | home | PASS m16; confirming rerun |
| STOBE 18 | forced betrayal (`NEG_TEST_FORCE_BETRAYAL`, `STOBE-18-forced-betrayal.sh`) | home + Full-Base | m19 Full-Base inconclusive (raider KO'd); rerun m19b |
| STOBE 20, A12, section C (25-37, 44, 45, 47, 49, 51) | forced via `NEG_TEST_INJECT` / `NEG_TEST_FORCE_INITIATIVE`, one `STOBE-C*.sh` wrapper each | auto-home | m19 section C block |
| STOBE 16 | crafted-ingredient goal completes with powered benches | Full-Base | m19 54/4 (backpack setup); rerun m19b |
| STOBE generic | goal scenarios with Beaks/Avarek: work part (hand-over + fetch PASS m19) | Full-Base | rerun m19b with `fb()` |
| STOBE 14 / A3 | buy from "the shop here", purchase event names the seller | Squin | FAIL m18 -> 111 (fixed); rerun |
| STOBE 15 | WAITING_APPROVAL approve/decline for a trader-only ingredient | Squin | FAIL m18 -> 112/113 (fixed); rerun |
| STOBE A8 | bread chain at home (PASS m17 on Full-Base) | auto-home | rerun (+ GROW=1 optional) |
| TRADE prices | deal prices at r = -80…+100 (buy -30 %…+1000 %, sell +10 %…-90 %) | auto-home | FAIL m19 -> 119 (fixed); rerun m19b `prices` |
| TRADE shop real | shop window with a real spawned trader (`REAL_TRADER=1`) | auto-home | setup fixed (cc4d14e); rerun m19b |
| GUARD weapon | +69 refused / +70 allowed; squadmate + surrendering NPC exempt | auto-home | PASS m18 except `weapon69` (setup); rerun |
| WILL favour / gift | free favour only at r >= +30, free items at +56 | auto-home | m19 -> 120 (fixed); rerun m19b |
| KAH 5 | `power <battery> charge` on a real Battery Bank | Full-Base | todo |
| REL SR12, SR32, p7 | real enslavement capture; freeing by `order`; free a non-squad slave + recruitment gate | Enslaved | m18 p7-04 15/2, p7-05 21/1: analyse, fix, rerun |
| REL SR09, SR13, SR14 | theft seen/unseen + theft_caught (`drop … owned`, native theft_caught) | auto-home | `rel-m18.sh`; m18 probe-theft-seen 19/3: analyse |
| REL SR07 | limb loss (`sever`) | auto-home | m18 p3-05b 31/2: analyse, rerun |
| REL SR06, SR30 | forced first strike / join attempt (`SOCIAL_TEST_FORCE_*`) | auto-home | `rel-m18.sh` |
| REL SR18/19 | bed/cage rescue on a second base (PASS on auto-home) | Full-Base | todo |
| PG rows | open PG rows (balance 161-210, 89, 132/133/240, 145/229, 151/152, 184, 188-192, 220-227, 250, 254, 274) | 4080 + Full-Base | PG agent; status in `INGAME_STATUS.md` |

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
| STOBE 99, 112, 113 | WAITING_APPROVAL + approved buy deadlock | STOBE 15 |
| STOBE 100 (b) | reputation/relationship history follow the speaking character | STOBE 18/21 Full-Base |
| STOBE 101 | `[]` extended_data | rel-enslaved set-relation |
| STOBE 104, 119 | -90 % sell side; higher counters ignored the relationship price | TRADE prices |
| STOBE 105 | KenshiFP log spam | A8 log |
| STOBE 106, 107, 18 FB | wrong-side SPARE; Full-Base pay-later; betrayal wrapper | STOBE 18/21 Full-Base |
| STOBE 110 + lock race | rollback write failed; unlocked concurrent rollbacks | php_error.log after older-save loads |
| STOBE 111 | "the shop here" buy | STOBE 14 Squin |
| STOBE 118, 120 | spoken offer paid before agreement; willingness lines outside deal terms | TRADE prices, WILL favour/gift |
| STOBE 121 | stale ended-goal block reasons made the NPC refuse a new production order (server e0e8e5c) | A8 home + grow Full-Base (m19c) |
| KAH 122 | protect never fed: squad starved at 50x in pg-09-soak, game fell to menu; kah run now aborts on menu (harness bf43c27 + 7e9dff1, DLL E83B0826) | pg-09-soak (m19c) |
| KAH to-do 19 | `walktime`, `newgame`, `pickup`, kah.py `@log`, nested `packput` (harness 609C459C) | PG 254, 132/133/240, 120 (4080) |

## 4. Harness (KAH) limits and open items

| # | Item | Status |
|---|---|---|
| KAH 1 | `damage` wounds don't bleed (use `blood`) | limit |
| KAH 2 | `messages` didn't see vanilla game messages | fixed (8341146), confirm |
| KAH 3 | shop-barrel `trade` named the barrel as seller | fixed (7778508), confirm |
| KAH 4 | `faction` gives the NPC a new #serial | limit |
| KAH 12 | never build a Biofuel Distillery (crash); `build` refuses it | limit |
