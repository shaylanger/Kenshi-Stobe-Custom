# Master test plan (all features, one game)

Started 2026-10-02 (late). One coordinator session runs Kenshi and tests every feature in the same
launch; feature agents write scenarios and fix their own bugs. Roles, loop and scenario format:
`testing/README.md`. This file is the index: details stay in each feature's own plan.

| Feature | Owner | Detail plan (source of truth for rows) | Scenarios |
|---|---|---|---|
| STOBE (Stobe.dll + server) | coordinator | `STOBE_full_test_plan.md` (items numbered from 1, next 64) | `tests/ingame/stobe/` |
| KenshiFP (KFP) | coordinator | rows live in the STOBE plan (goal panel, FP mode) | `tests/ingame/stobe/` |
| Profession Gear (PG) | PG agent | `Kenshi-Profession-Gear-Progression/TEST_PLAN.md` (rows 1–320), status `INGAME_STATUS.md` | PG repo `tests/ingame/` |
| Relationship system (REL) | REL builder | `STOBE_relationship_system_audit_and_implementation_plan.md` (SR01–SR44), deliveries `isolated/relationships-phase1/DELIVERY.md` | `/root/stobe-work/social-phase1/server/tests/social_relationship/ingame/` |
| Automation harness (KAH) | coordinator (+ helper agents) | this file, section 5 | `C:\KenshiTestRuns\scenarios\` |

IDs: `<feature> <row>` (e.g. STOBE 41, PG 306, REL SR02, KAH 3). Run logs: `archive/test-run-<date>-m<n>.md`.

## 0. Builds under test

| Component | Installed | Pending install |
|---|---|---|
| Stobe.dll | `162DB1E3` (REL 1–7 + m8) | - |
| KenshiFP.dll | `8A7BC8A8` (…, 84) | - |
| ProfessionGearProgression.dll | `FAA5B471` (craft-output roll, shop radius 60) | - |
| AutomationHarness.dll | `D8ECA273` (trade places items incl. shop storage, build/unbuild) | - |
| Server (live) | `2b3593c`+ (branch `stobe`, m1 fixes 64–72) | REL phase 1 (`feature/social-phase1`, inert by default) once delivered |

## 1. Automated: runnable now

Status: `todo` / `PASS <run>` / `FAIL <run> -> bug` / `blocked: <why>`.

### 1a. Fixture `auto-home` (Shay + Malzin at Home)

| ID | What | How (short) | Status |
|---|---|---|---|
| STOBE 41 | No false "you have my katana" claim | re-equip katana, gear exchange, "What have I taken from you?" | PASS m1 |
| STOBE 43 | Two-part hand-over gives both items | give bread + dried meat, "give me all your bread and all your dried meat" | PASS m1 (after fix 67) |
| STOBE 54 | Relationship talk by tier | `scenarios.sh trust` -80 / 60 / 96, prompt `<how_you_feel_about_them>` + words | PASS m3 (after 77) |
| STOBE 55 | R4 fights count (superseded once REL is enabled) | `scenarios.sh duel`, server log `a fight counts (R4)` | PASS m1 (fires once per pair; direction = event attacker) |
| STOBE 56 | Relationship types from the list only | chats, check entries | PASS m16 (all types on the list, new entry for Tovin Brask) |
| STOBE 57 | No entries for generic names | talk/fight an unnamed Hungry Bandit | PASS m16 (after 70: no generic-name keys in the DB after the m16 bandit fights) |
| STOBE 58 | `stobe-reset-npc` save + `--restore` | WSL only, no game action needed | PASS m16 (saved once, restore works; key case -> 94) |
| STOBE 59 | Relationships follow the save | real insult/fight at T, reload fixture, `PLAYTHROUGH: restored` | PASS m3 (stamped trust -80 -> reload -> back to the save's state) |
| STOBE 48 | KO/death during a deal | `scenarios.sh surrender` + `ko` / `kill` | PASS m1 (a + b) |
| STOBE 53 | Cap without a lie | surrender, "Make it 350" | PASS m1 |
| STOBE 60 | Cap tiers 0–2 | surrender with Dust Bandit and Hungry Bandit | PASS (tier 1 m2, tier 0 m8) |
| STOBE 61 | Cap tiers 3–5 (top-up) | spawn Samurai Sergeant / Dust King, beat, accept, 2nd deal | partial m12: surrender trigger fixed (88: health event + ratio 0.25 check); the Dust King flees before speaking, so the tier 3+ top-up needs a setup (section 2) |
| STOBE 20 | Refuse to pay after hand-over | fight setup | needs setup (m8: a gang of 3 KOs Shay before any offer; see section 2) |
| STOBE 21 | Pay-later breach | Fond trust, stop for pay-later, don't pay 1+ game min | needs setup (m8: a gang of 3 KOs Shay before any offer; see section 2) |
| STOBE 22 | Gang stands down on paid deal | `gang 3` + pay | needs setup (m8: a gang of 3 KOs Shay before any offer; see section 2) |
| STOBE 17 | Reputation voiced | set counts broken > kept, talk to a new NPC | PASS m8 (after 85) |
| STOBE A4 | Fetch from a far chest walks there | goal status step "Walking to" | PASS m3 (fetch + return); hand-over on return -> 76, retest |
| STOBE A5 | Job list switches by itself (Malzin selected) | log `GOAL_JOB ui refresh replayed selection`, harness `screenshot` | PASS m8 |
| STOBE A6 / KFP | Goal panel above the job list | log `GOAL_PANEL created … (jobs widget)` + harness `screenshot` + `ui` | PASS m2 (after 65: panel 2086,1030, above TimeMoneyPanel 1096) |
| STOBE A7 | "No room in pack" on-screen message | fill pack, ask for bread, harness `messages` | PASS m1 |
| STOBE A8 | Bread chain: well -> farm -> silo -> oven | `power` the silo, water, "make 2 bread" at 50x | needs setup m15: chain works up to power (90 fixed: uses the well's stock), Grain Silo has no power supply in auto-home |
| STOBE A10 | Mid-fight heal is known without saying | `order Shay FIRST_AID_ORDER target <npc>`, then talk | PASS m1 |
| STOBE A11 / A12 | Heal-for-item deal kept / broken | first aid via `order`, deal state | needs setup: harness wounds don't bleed, NPCs self-bandage (see section 2) |
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
| REL p5-01, p5-02 | trade, gift (+ deal kept/broken procedures) | PASS: SR22 fair trade 0 (m8), gift +2/+3 (m11, m13); SR29 deal procedures not run; SR13/14 blocked (no theft-caught signal) |

## 2. Requires specific game setup (no fixture/command for it yet)

| ID | What it needs |
|---|---|
| STOBE 61 | a tier 3+ NPC (Samurai/Dust King) who stays to negotiate after losing (the Dust King flees ~240 m before the offer is spoken) |
| STOBE 15 | a production goal whose missing ingredient only a trader sells (to see WAITING_APPROVAL) |
| STOBE A8 | power at Home (the Grain Silo/Well have no supply: no working generator/battery in auto-home; harness `build` could place a generator + battery, untested) |
| STOBE 20, 21, 22 | A fight Shay survives long enough for an offer: 3 raiders KO her (m8); needs a stronger test character (`setstat`/health regen) or the raid squad `size` scaled down per member |
| REL SR07, SR09, SR13, SR14 | forced limb loss in a fight; a source of better evidence; a theft-caught signal + steal driver |
| REL SR11 (old) | An enslavement the game reports (spawned bandits may already count as slaves: probe 21); SR12 + SR32 PASS m16 |
| STOBE A11 / A12 | A wounded NPC who can't bandage herself (harness `damage` wounds don't bleed; NPCs self-treat) and stays put for a heal-for-item deal |
| STOBE 18 | A dishonest NPC who dislikes Shay betraying a paid deal: rare by design; needs many tries or a forced-betrayal test switch |
| STOBE 25–37, 44, 45, 47, 49, 51 (section C) | LLM behaviours that haven't happened in game; checked passively: after every run grep the server/stobe logs for their log lines |
| KAH power charge | A battery building in a fixture (none has one) |
| PG 50, 84, 89, 106, 108, 120, 132, 133, 240 | ground drop/pick-up; melee stat names in `stat`; forcing a critical craft; NPC unload trigger; a unique NPC fixture; nested/unowned pack weight; import / new-game commands |
| PG 145, 229 | an equippable mod tool weapon (harness can't create weapons; `craft` may cover it) |
| PG 151, 152, 161–199 (not 177) | frame-time metric; balance measurement driver + benchmark fixtures (job-path proof done: PG 177/331 PASS m16) |
| PG 217, 220–227, 250, 256, 274 | restock trigger; fixtures next to several shop types; ruin loot; swim gear + water; colliding item ID save |
| REL SR07, SR09 | forcing a limb loss in a fight; an in-game source of better evidence (phase 6) |

## 3. Requires Shay

| ID | What |
|---|---|
| STOBE A9 | TTS volume/fade: the setting and ini are checked automatically; how it sounds is Shay's |
| Voice / feel | Voice quality, overall play feel, relationship balance feel (REL §9) |
| PG 135–141, 277 | Profession Gear tooltip section on armour, backpack, weapon/tool, plain item, two-affix item, shop/loot views: shown once, readable, no layout break |
| PG 155, 238 | feel: repeated tooltip opening; no stall when a shop opens |

## 4. Bugs found (open)

Owner fixes; the coordinator reruns. Fixed + confirmed bugs leave this table (line in the run log).

| Bug | Owner | Found | What | Status |
|---|---|---|---|---|
| STOBE 64 | STOBE | stobe-tests | `negotiation_engine` regression: "unpaid -> BREACHED_PLAYER" backdates wall time but hostile deals expire on game time (stale test); "breach reaction queued" depends on it | fixed, confirmed (stobe-tests 55/0/7) |
| STOBE 65 | KFP | m1 | Goal panel overlaps the Money/Day/speed box | fixed, PASS m2 |
| STOBE 66 | STOBE | m1 | Work goal to "Home": destination_not_known (base registry pruned by cross-fixture loads, not re-detected) | closed: no player-owned town in auto-home; server fallback is the fix (PASS m2) |
| STOBE 67 | STOBE | m1 | Squad member agrees to hand over items, no GIVE_ITEM sent | fixed, PASS m1 |
| STOBE 69 | STOBE | m1 | Denies carrying an item her prompt lists ("nothing left") | fixed (semantic guard), PASS m4 |
| STOBE 71 | STOBE | m1 | Surrender offers never fired: raider's combat rows under his generic pre-naming name | fixed live (722d53d), PASS m1 |
| STOBE 72 | STOBE | m1 | Accepting after a rejected counter flipped the payer (Shay pays) | fixed, PASS m2 |
| STOBE 73 | STOBE | m2 | Squad member agrees to a fetch ("I'll go dig it out") but sends no TASK_GOAL | fixed, PASS m3 |
| STOBE 74 | STOBE | m2 | Agreed purchase, no action | fixed live (1a8fc3f), PASS m2 (goal added) |
| STOBE 76 | KFP | m3 | "bring it to me" fetch keeps the item on return | fixed, PASS m4 |
| STOBE 77 | STOBE | m3 | Relationship stance block doesn't shape tone (same reply at -80/60/96) | fixed live (0a22a77), PASS m3 |
| STOBE 78 | STOBE | m3 | Errand to a named trader out of nearby range: she doubts/asks back, no action | fixed, PASS m4 (prompt block; model returns BUY) |
| STOBE 79 | STOBE | m4 | BUY goal with destination = trader name rejected (destination_not_known) | fixed live (21fdbed), PASS m4 |
| STOBE 80 | KFP | m4 | Silent crash (no dump) right after a BUY goal: character search buffer overflow | fixed, PASS m5 (no crash, trader found and reached) |
| STOBE 81 | KFP | m5 | BUY goal: "merchant does not have" an item the trader carries (stock view misses carried goods) | fixed (KenshiFP 846E6119), PASS m6 |
| STOBE 82 | KFP | m6 | "buy … and bring it to me": no hand-over on return (76 covers FETCH only) | fixed, PASS m9 |
| STOBE 83 | KFP | m7 | Carried-goods BUY: money paid, item missing ("Kenshi rejected the purchase") | -> 84 |
| STOBE 84 | KFP+KAH | m8 | `Inventory::buyItem` returns the bought item unplaced: KenshiFP BUY and harness `trade` lose the item (money paid) | fixed, PASS m9 (KenshiFP); harness trade from shop storage fixed D8ECA273 |
| STOBE 85 | STOBE | m8 | Bad reputation (broken > kept) in the prompt is ignored by new NPCs | fixed live (795b0f1), PASS m8 |
| STOBE 86 | STOBE | m8 | Reloading an older save turns deals made after it into BREACHED_PLAYER | fixed live (f98b88e + e9f8598): false breach from repeated 'Initiated attack'; older-save load cancels later deals; deal repaired |
| STOBE 87 | STOBE | m8 | Unique NPC named like its template (Dust King) gets no initiative check / surrender | see rows 87/88 |
| STOBE 88 | STOBE | m10 | Fleeing/out-of-scan fighters never sent a health event (no surrender check below 35%) | fixed (Stobe 99092DDD+), PASS m12 |
| STOBE 89 | KFP | m12 | Silent crash on a work goal at the Crafting base: object-search buffers sized to the request | fixed (KenshiFP B67AEAD3), PASS m12 |
| STOBE 94 | STOBE | m16 | `stobe-reset-npc --restore` writes the entry under PLAYER_NAME `shay` while the server writes `Shay`: possible duplicate relationship keys | fixed (tool), round trip at the end |
| STOBE 96 | STOBE | m16 | Deal payment verified only from dispatched_unix-3: an NPC paying on accept is missed; REISSUE waits for speech, deal hangs | fixed live (c5a8e25), rerun surrender |
| STOBE 97 | STOBE | m16 | Personal-truce guard (20 s) clears an explicit player attack order: player betrayal impossible | fixed (Stobe EF62563B), rerun SR29 breach |
| REL capture | REL | m4 | No campaign id with Playthrough Saves off: all social events skipped | fixed (server 5cd104e, Stobe 44793036), PASS m4 |
| CRASH m3 | ? | m3 | 02:05:45 crash dump, game frozen on kah-crafting while idle | NVIDIA TDR (GPU driver hang, nvlddmkm 153/4101, DXGI DEVICE_HUNG) in vanilla render: not our mods; Shay: driver/TdrDelay |

## 5. Harness (KAH) known limits / open items

| # | Item | Status |
|---|---|---|
| KAH 1 | `damage` wounds don't bleed (use `blood`) | limit, documented |
| KAH 2 | `messages`: no vanilla game message seen yet (Stobe's are captured) | open, watch |
| KAH 3 | `shopstock`/`trade` from a shop barrel: the game's trade event names "Old Wooden Barrel" as seller and the trader's cats don't change (affects STOBE A3) | open, check in STOBE A3 |
| KAH 4 | `faction` gives the NPC a new #serial | limit, documented |
| KAH 5 | `power charge` untested (no battery in fixtures) | `build`/`unbuild` added (D8ECA273, PASS m10); power charge still untested |
| KAH 6 | Hover tooltips can't be read (PG 135–141) | open: try `ui` while hovering |
| KAH 7 | `camera` command (fixed view for perf windows) | deferred m16: not needed (REL gate passed); feasible via `ou->player->camera` (teleport, manuallySetOrientationAndZoom, lock per frame), needs in-game checks |
| KAH 9 | `kah.py` client: concurrent callers share `inbox.txt.tmp` and lose commands (FileNotFoundError) | fixed (kah.py lock + unique temp, harness 55192E94) |
