# Master test plan (all features, one game)

Started 2026-10-02 (late). One coordinator session runs Kenshi and tests every feature in the same
launch; feature agents write scenarios and fix their own bugs. Roles, loop and scenario format:
`testing/README.md`. This file is the index: details stay in each feature's own plan.

**Goal (Shay, 2026-10-03, firm):** the coordinator builds, tests, validates and fixes EVERYTHING and only stops for
Shay's decisions or when nothing testable is left. Any handler, harness command, test switch, hook, driver or code a
test needs gets built, then the test runs: "needs setup"/"missing code" is never a final status (section 2 rows are a
build to-do list, not a parking place). Full to-do list: `testing/HANDOFF.md`.

| Feature | Owner | Detail plan (source of truth for rows) | Scenarios |
|---|---|---|---|
| STOBE (Stobe.dll + server) | coordinator | `STOBE_full_test_plan.md` (items numbered from 1, next 107) | `tests/ingame/stobe/` |
| KenshiFP (KFP) | coordinator | rows live in the STOBE plan (goal panel, FP mode) | `tests/ingame/stobe/` |
| Profession Gear (PG) | PG agent | `Kenshi-Profession-Gear-Progression/TEST_PLAN.md` (rows 1–320), status `INGAME_STATUS.md` | PG repo `tests/ingame/` |
| Relationship system (REL) | REL builder | `STOBE_relationship_system_audit_and_implementation_plan.md` (SR01–SR44), deliveries `isolated/relationships-phase1/DELIVERY.md` | `/root/stobe-work/social-phase1/server/tests/social_relationship/ingame/` |
| Automation harness (KAH) | coordinator (+ helper agents) | this file, section 5 | `C:\KenshiTestRuns\scenarios\` |

IDs: `<feature> <row>` (e.g. STOBE 41, PG 306, REL SR02, KAH 3). Run logs: `archive/test-run-<date>-m<n>.md`.

**Two test machines (2026-10-03):** the 5090 (this PC: STOBE, KenshiFP, REL, server, perf/frame-time/soak rows) and the **4080 rig** (`ssh 4080`, `C:\KAH\ctl.ps1`, harness + PG only: PG rows, new harness commands). Never compare performance across machines; 4080 results are labelled "-4080" (`C:\KenshiTestRuns\m<n>-4080\` on the 4080).

## 0. Builds under test

| Component | Installed (5090, m19) | Pending install |
|---|---|---|
| Stobe.dll | `CA758842` (shop-window relationship pricing hook 103/104 with sell-side -90 %, REL theft_caught SR09/13/14) | - |
| KenshiFP.dll | `6E0A031E` (items to 112) | - |
| ProfessionGearProgression.dll | `D7A60E49` (Forced + InGameTest during tests) | `266C68F5` (only for PG 250, 4080) |
| AutomationHarness.dll | `33087EDE` (main 8116c46: KAH 2/3, 22b `drop owned`, 24 balance commands) | to-do 19 fixes (harness helper) |
| Server (live) | `cef19fe` (branch `stobe`: item 104 -90 %, item 100 b, 110, REL theft/SR09) | B 55 fight rules (REL builder) |

## 1. Automated: runnable now

Status: `todo` / `PASS <run>` / `FAIL <run> -> bug` / `blocked: <why>`.

### 1a. Fixture `auto-home` (Shay + Malzin at Home)

| ID | What | How (short) | Status |
|---|---|---|---|
| STOBE 41 | No false "you have my katana" claim | re-equip katana, gear exchange, "What have I taken from you?" | PASS m1 |
| STOBE 43 | Two-part hand-over gives both items | give bread + dried meat, "give me all your bread and all your dried meat" | PASS m1 (after fix 67) |
| STOBE 54 | Relationship talk by tier | `scenarios.sh trust` -80 / 60 / 96, prompt `<how_you_feel_about_them>` + words | PASS m3 (after 77) |
| STOBE 55 | B 55 fight rules (R4 retired; REL fights mode, STOBE plan section E items 1-8) | `rel-b55.sh` blocks mode/squad/wild/spar/close/treat/fade/chat/bleed/deal | built live (server 1392155), 63 unit checks; in game: m19c after the Stobe rebuild |
| STOBE 56 | Relationship types from the list only | chats, check entries | PASS m16 (all types on the list, new entry for Tovin Brask) |
| STOBE 57 | No entries for generic names | talk/fight an unnamed Hungry Bandit | PASS m16 (after 70: no generic-name keys in the DB after the m16 bandit fights) |
| STOBE 58 | `stobe-reset-npc` save + `--restore` | WSL only, no game action needed | PASS m16 (saved once, restore works; key case -> 94) |
| STOBE 59 | Relationships follow the save | real insult/fight at T, reload fixture, `PLAYTHROUGH: restored` | PASS m3 (stamped trust -80 -> reload -> back to the save's state) |
| STOBE 48 | KO/death during a deal | `scenarios.sh surrender` + `ko` / `kill` | PASS m1 (a + b) |
| STOBE 53 | Cap without a lie | surrender, "Make it 350" | PASS m1 |
| STOBE 60 | Cap tiers 0–2 | surrender with Dust Bandit and Hungry Bandit | PASS (tier 1 m2, tier 0 m8) |
| STOBE 61 | Cap tiers 3–5 (top-up) | spawn Samurai Sergeant / Dust King, beat, accept, 2nd deal | partial m12: surrender trigger fixed (88: health event + ratio 0.25 check); the Dust King flees before speaking, so the tier 3+ top-up needs a setup (section 2) |
| STOBE 20 | Refuse to pay after hand-over | fight setup | -> section 2 (m16: by design, he won't hand over first) |
| STOBE 21 | Pay-later breach | Fond trust, stop for pay-later, don't pay 1+ game min | PASS m16, confirming rerun queued (stale-deal lookup) (`STOBE-21-paylater-breach.sh` with harness `protect`: BREACHED_PLAYER) |
| STOBE 22 | Gang stands down on paid deal | `gang 3` + pay | PASS m16, confirming rerun queued (stale-deal lookup) (`STOBE-22-gang-stands-down.sh` with `protect`: paid deal COMPLETE, gang quiet 120 s) |
| STOBE 17 | Reputation voiced | set counts broken > kept, talk to a new NPC | PASS m8 (after 85) |
| STOBE A4 | Fetch from a far chest walks there | goal status step "Walking to" | PASS m3 (fetch + return); hand-over on return -> 76, retest |
| STOBE A5 | Job list switches by itself (Malzin selected) | log `GOAL_JOB ui refresh replayed selection`, harness `screenshot` | PASS m8 |
| STOBE A6 / KFP | Goal panel above the job list | log `GOAL_PANEL created … (jobs widget)` + harness `screenshot` + `ui` | PASS m2 (after 65: panel 2086,1030, above TimeMoneyPanel 1096) |
| STOBE A7 | "No room in pack" on-screen message | fill pack, ask for bread, harness `messages` | PASS m1 |
| STOBE A8 | Bread chain: well -> farm -> silo -> oven | `power` the silo, water, "make 2 bread" at 50x | needs setup m15: chain works up to power (90 fixed: uses the well's stock), Grain Silo has no power supply in auto-home |
| STOBE A10 | Mid-fight heal is known without saying | `order Shay FIRST_AID_ORDER target <npc>`, then talk | PASS m1 |
| STOBE A11 / A12 | Heal-for-item deal kept / broken | `tests/ingame/stobe/STOBE-A11-A12-heal-deal.sh` | A11 PASS m16; A12 -> section 2 |
| STOBE A13 | Remembers earlier fight events | long fight, then ask (`tests/ingame/stobe/STOBE-A13-fight-memory.txt`) | PASS m16 (A13 v4, after 91/92) |
| PG auto-home group | 95 PENDING rows (see PG `INGAME_STATUS.md`) | PG `tests/ingame/auto-home/pg-01…pg-09` (Forced + InGameTest), then config launches 2–4 (`RUN_ORDER.md`) | PASS m4 (pg-01…08 all green on FAA5B471) |
| STOBE A1 / A2 | FP mode: look-at click keeps control; put down with G | `fp_mode`, `fp_click`, `fp_putdown`, `fp_state` + KenshiFP.log | PASS m1 |

### 1b. Fixture `Crafting base` (benches, Malzin, apothecaries in town)

| ID | What | How | Status |
|---|---|---|---|
| STOBE 14 | Buy from a trader | spawn Skeleton Traders near Home, "buy 3 bread from the trader" | PASS m6 (bought from Abia's carried goods; seller named) |
| STOBE 15 | Goal needing trader stock -> approval | same traders | partial m12: direct BUY works; WAITING_APPROVAL (production chain needing a bought ingredient) needs a setup |
| STOBE A3 | Purchase event names the trader | talk to Malzin, then `trade Shay <trader> <food>` | PASS m4 (event names Apothecary Abia as seller) |
| STOBE 16 | Goal with a crafted ingredient: bench queue grows only by what's missing | goal at a bench | PASS m16 (v5, after 93/95: queue grows only by the missing count; completion needs bench power, see section 2) |
| PG crafting group | PG 85–92, 306 (+ weapons) | PG `tests/ingame/crafting-base/pg-10`, `pg-11` (Forced + InGameTest) | PASS (pg-10 m3, pg-11 m8) |

### 1c. Fixture `Trader` (Shay alone next to 5 real traders)

| ID | What | How | Status |
|---|---|---|---|
| REL p6-01a/b, p7-01, p7-02 | witnesses, recruitment gate, slave escape | SR24 PASS (m8–m13); SR25 PASS m16 (asleep in a bed: no effect); SR30 inconclusive (LLM never tried to join); SR32 PASS m16 (chains_freed +14 after m16/m16b/m16c) |
| PG status | `INGAME_STATUS.md`: 161 PASS-live, 71 PASS-offline, 8 PENDING (pg-21 rerun, pg-09 soak), 65 NEEDS-SETUP, 10 NEEDS-SHAY, 26 DEFERRED | 342 rows: 169 PASS-live, 71 PASS-offline, 1 PENDING (pg-09 optional soak), 65 NEEDS-SETUP, 10 NEEDS-SHAY, 26 DEFERRED (`INGAME_STATUS.md`, PG ab3ec89, DLL 59EFB4B1) |
| PG config launches | pg-30 (AutoClassify off) | pg-30 PASS m5, pg-31 PASS m6, pg-40 PASS m6, pg-41 65/1 m6 (chest full, scenario) |
| PG trader group | PG 211–237 shop rows | PG `tests/ingame/trader/pg-20` (launch 1); `pg-40` (launch 4, NormalVerbose) | PASS m13 (pg-20 diag m3, pg-21 39/0) |

### 1d. Relationship system

| ID | What | How | Status |
|---|---|---|---|
| REL p1-01…04 | Phase 1 smoke: Capture=0 legacy unchanged; Capture=1 server off / shadow (raw events, identity, no affinity change); reload rejects stale events | REL `ingame/RUN_ORDER.md` | PASS (m3/m4/m5) |
| REL p2-01…05 | Phase 2 combat: SR02–05 (+ probes 1, 2, 4); p2-05 enabled mode | same | PASS in game: SR02 (m8, m13), SR03/04 (m4), SR05 (m11), SR41; SR06 inconclusive (victim turns hostile) |
| REL p3-01…04 | Phase 3 unconscious perception: SR08, 10–12 (+ probes 5–9) | same | PASS: SR08 loot via harness transfer + SR10 (m8) + SR11 enslavement (m13) + SR38 (m9); p3-01 39/0 m15 |

### 1e. REL phases 4–8

| ID | What | Status |
|---|---|---|
| REL p4-01…04 | first aid, carry to bed / cage, food | PASS: SR15 lifesaving +29 (m8), SR18 bed rescue +8/+9 and SR19 cage -31/-33 (m11, m13; harness `build`), SR21 food transfer (m13/m15 48/0) |
| REL p8 soak + perf gate | 1 h Hub soak A (Capture=0) / B (Capture=1, shadow) | PASS (m13 soak: functional 30/0, fps 99.5 %, worst 107.7 %; m15 B-A-B-A windows within the same fps regime 99.6-100.2 %, memory B-A -45/+4 MB: gate pass, idle capture) |
| REL p5-01, p5-02 | trade, gift (+ deal kept/broken procedures) | PASS: SR22 fair trade 0 (m8), SR23 m16 (carried-stock seller named), gift +2/+3 (m11, m13); SR29 deal procedures not run; SR13/14 blocked (no theft-caught signal); SR28 + SR29 PASS m16 (rel-surrender.sh kept-hate / breach) |

### 1f. New fixtures from the 4080 (2026-10-03): smoke load first, then the rows they unlock

Details: `handoff/new-test-saves-context.md` (local) and `C:\KenshiTestFixtures\FIXTURES.md` ("Saves made on the 4080").
Copies: `relaunch.ps1 -Fixture "Testing-Save-Full-Base" -Copy kah-fullbase` (also `kah-squin`, `kah-enslaved`).
**The squads are not Shay + Malzin**: pass names explicitly (`select <name>` before `stobe-say say`); a Shay/Malzin literal
required by mod code (not test tools) is a bug. Made without our plugins: first load = PG affix roll for all items (load test);
no Stobe history/relationships. **Never build a Biofuel Distillery** (crash, see KAH 12).

| ID | What | Fixture | Status |
|---|---|---|---|
| SMOKE fullbase / squin / enslaved | loads, 2+ min at 1x without crash, `status` shows the save, `chars` lists the squad, `[EVENT]` lines flow, PG first-load roll ok | each new save | PASS m16 (no crash, squads listed, events flow, PG rolled 241/350/297 items, no exceptions) |
| STOBE A8 | Bread chain well -> farm -> Grain Silo -> oven with real power ("make 2 bread", 50x + goal watch; `building "Grain Silo"` power first) | Full-Base (Beaks/Avarek) | PASS m17 (COMPLETE 2/2 bread, silo drew real power; wrapper oven check fixed) |
| STOBE 16 (full chain) | crafted-ingredient goal completes with powered benches (queue property already PASS m16) | Full-Base | m17 46/10: queues ok, Avarek killed by Kral's Chosen raiders mid-goal -> rerun with `fullbase-guard.sh` (queued) |
| KAH 5 | `power <battery> charge` on a real Battery Bank | Full-Base | todo |
| STOBE generic regression | green STOBE goal scenarios with Beaks/Avarek (no Shay/Malzin hard-coding) | Full-Base | m17: hand-over PASS (item 100 confirmed: only GIVE_ITEM@Beaks); fetch/work cut off by a world raid -> rerun with `fullbase-guard.sh` (queued `m17/rerun.sh`) |
| PG 145, 229 | mod tool weapons (ArkWeaponPack Sickle etc.): research Basic Weapon Smithing/Grades/Utility Weapons, `craft <npc> Sickle at <weapon smith>` with Iron Plates | Full-Base | todo (PG agent scenario) |
| PG 161–199 | balance/benchmark rows: research bench (184), robotics (186), turret + target dummy; needs the balance measurement driver | Full-Base | todo (PG agent driver) |
| REL SR18/19, p4 | bed/cage rescue, first aid, carry on a second base | Full-Base | todo (optional, already PASS on auto-home) |
| PG 220–227 | shop stock by trader type (`traders 300`, `shopstock`/`pg_shop`/`pg_census`); missing types -> "needs setup (no <type> shop in Squin)" | Squin (Beak/Kint) | todo |
| PG 217 | restock: note stock, `wait-game` past restock, compare; instance keys don't reroll | Squin | todo |
| PG 108 | a unique named NPC with gear, if Squin has one | Squin | todo |
| STOBE 15 | WAITING_APPROVAL: missing ingredient only a Squin trader sells (Crafting base version running m16) | Squin | todo |
| STOBE 14 / A3 | buy from a trader, purchase event names the seller, with new characters | Squin | todo |
| REL SR12 (real) | an enslavement the game itself reports: server capture right after load and after the labour shift | Enslaved (Izumi/Daphnilis) | todo |
| REL SR32 (real) | the free squad member frees the enslaved one by `order` (real lockpick); server names the freer | Enslaved | todo |
| REL p7 | free a non-squad slave, then the recruitment gate (low/high trust) | Enslaved | todo |

Guards in the slave camp: keep them off with `ko <guard> <s>` or `relation <guard> <value>`, never `kill`; log any guard handling.

### 1g. Relationship-shaped trading, willingness lines, weapon-stow guard (Shay: "build it", 2026-10-03; being built m16)

Spec: memory `stobe-negotiation-rules`. r = NPC's relationship toward the trading squad member (no data = 0 = vanilla).

| ID | What | How | Status |
|---|---|---|---|
| TRADE prices | Shop + deal prices at r = -80, -50, -10, 0, +10, +56, +100 vs vanilla, buy and sell; formula exact (buy: -30%·(r/100)^1.1 / +1000%·(|r|/100)^2.32; sell: up to +10% / down to -90% (Shay, 2026-10-03)) | trust setup + `shopstock` + real `trade`; STOBE deal (`STOBE-102-104-relationship-trading.sh prices`) | server cef19fe (-90 %) + shop-window hook Stobe CA758842: m19 `prices`, `shop-prices` (+ REAL_TRADER) |
| TRADE floor | Buy/sell or sell/buy-back loop never profits | trade loop | server floor live + shop hook CA758842: m19 `shop-floor` |
| GUARD weapon | Outsider won't stow/drop/hand over her weapon below r +70 (+69 refused, +70 allowed); squadmate + surrendering NPC exempt | ask for her weapon (`… weapon69/weapon70/weapon-squad/weapon-surrender`) | PASS m18 (69 setup fail: rerun) |
| WILL lines | Pay-later -1 refused / 0 allowed; free favour +29 refused / +30 allowed; any trade at -80 refused (STOBE deal + shop window) | deals at set trust (`… paylater/favour/gift/notrade`) | STOBE 103 live; m19 `paylater/favour/gift/notrade` + `shop-block` |

## 2. Rows that needed setup: build status (refreshed 2026-10-03, m19)

Not a parking place (Shay's goal): every row here has its code built or being built, then runs.

| ID | Built / being built | Runs in |
|---|---|---|
| STOBE 61 | `protect` (KAH 11) | PASS m18 (tier 3+ top-up) |
| STOBE 18 | switch `NEG_TEST_FORCE_BETRAYAL` + `STOBE-18-forced-betrayal.sh` | m19 (home + Full-Base) |
| STOBE 20, A12 | switches `NEG_TEST_INJECT` / `NEG_TEST_FORCE_INITIATIVE` (2b2b52d) + wrappers | m19 section C block |
| STOBE 25-37, 44, 45, 47, 49, 51 (section C) | one wrapper each (`tests/ingame/stobe/STOBE-C*.sh`) | m19 section C block |
| STOBE A8 | `power <b> supply` (KAH 10) | PASS m17 Full-Base; home rerun m19 |
| REL SR09, SR13, SR14 | harness `drop … owned` (KAH 22b) + native theft_caught (Stobe CA758842) + server cb3bc44 | m19 `rel-m18.sh` |
| REL SR06, SR30 | switches SOCIAL_TEST_FORCE_FIRST_STRIKE / SOCIAL_TEST_FORCE_JOIN_ATTEMPT | m19 `rel-m18.sh` |
| REL SR07 | harness `sever` (KAH 20) | to run (p3-05 + sever) |
| PG 50, 84, 106, 108, 120, 184 | KAH 13-18 | PASS / run by the PG agent (4080) |
| PG 132, 133, 240, 254, 120 nested | KAH 19/21 + to-do 19 harness fixes (`newgame` hang, `walktime` short stop, nested `packput`) | harness helper, then 4080 |
| PG 89 | `pg_force_critical` + `pg-56-critical-craft` | m19 pg block + 4080 |
| PG 151, 152 | pg-15 launch 1 vs launch 3 (PG off), same machine | PG agent (4080) |
| PG 161-210 | balance driver + KAH 24 measurement commands | PG agent (4080) |
| PG 250 | ruin/loot fixture via harness spawn/stash (PG 266C68F5) | PG agent (4080) |
| PG 274 | colliding-ID case on an edited fixture copy | PG agent |
| PG 256 | deferred by Shay (no Swimming roll in this load order) | - |

## 3. Requires Shay

| ID | What |
|---|---|
| STOBE A9 | TTS volume/fade: PASS (Shay tested, 2026-10-03) |
| Voice / feel | Voice quality, overall play feel, relationship balance feel (REL §9) |
| PG 135–141, 277 | Profession Gear tooltip section on armour, backpack, weapon/tool, plain item, two-affix item, shop/loot views: shown once, readable, no layout break |
| PG 155, 238 | feel: repeated tooltip opening; no stall when a shop opens |

## 4. Bugs found (open)

Owner fixes; the coordinator reruns. Fixed + confirmed bugs leave this table (line in the run log). Pruned 2026-10-03
(m19): 64-85, 88, 89, REL capture confirmed; CRASH m3 = NVIDIA TDR, not our mods. Details: `STOBE_full_test_plan.md`.

| Bug | Owner | Found | What | Status |
|---|---|---|---|---|
| STOBE 70, 108 | STOBE | m16/m18 | template-name relationship keys (Dust Bandit Bowman, Berserker) | fixed live, confirm in game (to-do 8) |
| STOBE 86 | STOBE | m8 | older-save load turned later deals into BREACHED_PLAYER | fixed live, confirm in game |
| STOBE 87 | STOBE | m8 | Dust King: no initiative check | covered by 88 + 61 PASS m18; confirm |
| STOBE 94 | STOBE | m16 | reset-npc `--restore` key case | fixed (tool), round trip at the end |
| STOBE 96, 97 | STOBE | m16 | surrender payment check window; PERSONAL_TRUCE cancels Shay's attack order | fixed, confirm in game |
| STOBE 99, 112, 113 | STOBE+KFP | m16/m18 | WAITING_APPROVAL for a trader-only ingredient; approved buy sub-goal deadlock | fixed (KenshiFP 6E0A031E + server), m19 Squin 15 |
| STOBE 100 (b) | STOBE | m16 | reputation/relationship history follow the speaking character | live 0c6ed3e, m19 18/21 Full-Base + home 21; reputation migration skipped (Shay: test data) |
| STOBE 101 | STOBE | m16 | `[]` extended_data | fixed live, rerun rel-enslaved set-relation |
| STOBE 104 | STOBE | m18 | sell-side max -90 % (Shay) | server cef19fe + Stobe CA758842, m19 trading block |
| STOBE 105 | KFP | m16 | 30k `WORK_GOAL input ratio` lines | fixed (KenshiFP 5719BEA5+), confirm in A8 log |
| STOBE 106, 107, 18 FB | STOBE | m16-m18 | SPARE term wrong_performer; Full-Base pay-later never breached; forced-betrayal wrapper | fixed live, m19 18/21 Full-Base |
| STOBE 109, 111 | STOBE | m18 | old COMPLETE fetch in prompt; generic "the shop here" buy -> MOVE_TO only | fixed live, m19 generic Full-Base + Squin 14 |
| STOBE 110 + lock race | STOBE | m18 | rollback write failed; concurrent rollbacks run unlocked ("rollback lock busy") | 110 fixed live (e605768); lock race: STOBE fixer (to-do 20) |
| STOBE 118 | STOBE | m19 | "One cat, take it or leave it" at r=-80 paid GIVE_CATS@Vel Harrow@1 before any agreement | fixed live (fda6a7f), rerun trading `prices` (m19b) |
| KAH to-do 19 | KAH | m18-4080 | `walktime` short stop, `newgame` hang, `pickup` No Faction as owned, kah.py `@log` path with spaces, nested `packput` | harness helper |
| B 55 | REL | design | R4 retired -> REL combat rules + STOBE plan section E items 1-8 | built live 1392155; in-game m19c; harness `hit` for the accident row |

## 5. Harness (KAH) known limits / open items

| # | Item | Status |
|---|---|---|
| KAH 1 | `damage` wounds don't bleed (use `blood`) | limit, documented |
| KAH 2 | `messages`: no vanilla game message seen yet (Stobe's are captured) | open, watch |
| KAH 3 | `shopstock`/`trade` from a shop barrel: the game's trade event names "Old Wooden Barrel" as seller and the trader's cats don't change (affects STOBE A3) | open, check in STOBE A3 |
| KAH 4 | `faction` gives the NPC a new #serial | limit, documented |
| KAH 5 | `power charge` untested (no battery in fixtures) | `build`/`unbuild` added (D8ECA273, PASS m10); power charge still untested |
| KAH 9 | `kah.py` client: concurrent callers share `inbox.txt.tmp` and lose commands (FileNotFoundError) | fixed (kah.py lock + unique temp, harness 55192E94) |
| KAH 10 | No way to power a bench in fixtures: built + charged Battery Bank leaves out_of_power=1.0 (blocks STOBE A8, 15/16/89 completion) | fixed + confirmed m16 (`power <b> supply`, harness 12F5CE0B) |
| KAH 11 | `protect <npc>`: keep a character conscious through a fight (Shay KO blocks deal tests 20/21/22/61) | fixed + confirmed m16 (harness 08AB6BF0) |
| KAH 12 | **Never build a Biofuel Distillery** (`43875-Newwworld.mod`): StorageBuilding without inventory, crash ~10 s after load (`kenshi_x64.exe+0x2988b5`, null `UseableStuff::inventory` +0x430); harness `build` must refuse it | known limit (2026-10-03), harness helper: add a refusal |
