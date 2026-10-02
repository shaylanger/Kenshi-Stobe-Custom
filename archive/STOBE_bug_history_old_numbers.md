# STOBE bug history (bugs 1–70, 2026-09-30)

One line per bug found in the automated Malzin runs: what went wrong → fix round → status. Open work lives in `STOBE_full_test_plan.md`. The full run logs (exact lines, timestamps, deal ids) are in `archive/test-run-2026-09-30*.md`.

Rounds: server patches `pending-fixes/patch_roundN*.py` (live + ss-merge); DLL `patch_dll_roundN.py`; KenshiFP `patch_kfp_round8.py`.

| # | Bug | Fix | Status |
|---|---|---|---|
| 1 | Deal with an IMPOSSIBLE NPC term stayed open ~24 h; a later refusal "breached" it | r7 | ✅ |
| 2 | Paid hand-over of a worn hat blocked by the worn-gear gift rule | r8 | ✅ (K13) |
| 3 | Overpayment clamped to the whole purse (server had no player Cats; DLL clamped) | r7, DLL r7 | ✅ (D6) |
| 4 | An offer phrased as a question ("…and you take the hat off. Deal?") paid at once | r7 | ✅ (E1) |
| 5 | NPC money/inventory never reached the server (zero deltas) | DLL r8 | ✅ (K12) |
| 6 | Ceasefire speech guard rewrote social counter-offers | r7 | ✅ |
| 7 | Duplicate deal after completion re-counted the payment → refund exploit (`resolved_at` in UTC vs DB clock) | r7 | ✅ |
| 8 | Counter + acceptance not recorded (knock-on of 7) | r7 | ✅ |
| 9 | "Here's your food" handed over any food | r7 | ✅ (E3) |
| 10 | `invalid_recipient` (model wrote names) threw away the deal | r7 | ✅ (E4) |
| 11 | Refund directives consumed but never executed | r7/r8 (late actions emitted) | ✅ (refund seen in run 2) |
| 12 | "Let me put the sandals on" with no equip action | r8 (inferred from speech) | ✅ (K7) |
| 13 | Full pack: NPC couldn't take clothes off | KenshiFP r8 (drop at feet) | ✅ (K6) |
| 14 | Junk bytes on player chat lines (raw QUERY_STRING decode) | r8 | ✅ (K8) |
| 15 | One-slot mailboxes overwritten by back-to-back actions | r7e | ✅ |
| 16 | Any unequip verified every UNEQUIP term | r7e | ✅ (I4) |
| 17 | deal_terms written as text/prose | r7c/7f | ✅ |
| 18 | One payment counted for two deals (lookback slack) | r7g | ✅ |
| 19 | "…I pay you 300 cats. Deal?" paid at once | r7h | ✅ |
| 20 | Breach started a fight; the stop didn't hold (Shay knocked out) | DLL r8 personal truce | ✅ (K9/K10) |
| 21 | Worn item handed over + separate unequip term → false IMPOSSIBLE + refund | r9b | ✅ |
| 22 | One-sided social deals (no NPC side) completed with nothing done | r9c | ✅ |
| 23 | "Take this bread" gave nothing for "Poppyseed Bread" | r9d | ✅ PASSED run 9 (test 33) |
| 24 | GIVE_ITEM to a full pack dropped the item but logged `transferred=1` | DLL r9 | ✅ (L1) |
| 25 | ACCEPT with `{"accepted": true}` left the deal COUNTERED | r9e | ✅ |
| 26 | Spoken amounts differed from recorded terms | r10/10b | ✅ (L2); misquote rewrite not seen (plan L3) |
| 27 | Faction-mates joined a one-on-one fight | DLL r9 + r10; `@help` broken until r14 | ✅ with help (L5); uninvited-joiner path not seen (plan L4a) |
| 28 | "Name your price" didn't start negotiation | r12 | ✅ |
| 29 | Accept + pay in one line: her side waited for the next line | r12, completed by r15 (34) | ✅ |
| 30 | Agreed in words, `deal_decision` NONE | r12 | ⏳ not triggered (plan L9) |
| 31 | "Take off X" recorded as GIVE_ITEM | r12 | ⏳ not triggered (plan L10) |
| 32 | She disarmed for money with no trust | r11 (weapon rule, trust ≥ 56) | ✅ behaviour; server backstop not seen |
| 33 | Stop deal right after an attack recorded as social (stale combat flag) | r10c | ✅ |
| 34 | Payment verified after the reply: settle waited for her next line | r15 | ✅ |
| 35 | Amount check replaced her whole reply | r15 | ⏳ not seen in game |
| 36 | "Four hundred then… Deal?" not seen as an offer | r15 | ✅ |
| 37 | COUNTER with empty deal_terms dropped silently | r15 (next-turn reminder) | ⏳ not seen in game |
| 38 | "Shay \| squadmate" in a non-member's prompt | r15 | ⏳ not seen in game |
| 39 | `ATTACK@shay@help` stripped to `shayhelp` by the action sanitizer | r14 | ✅ |
| 40 | Faction-mates joining after her STOP_ATTACK weren't stood down | DLL r15 | ✅ (3 fights) |
| 41 | Combat pay window ran during a game pause → false breach + revenge attack | r15 (game-time deadline) | ✅ |
| 42 | Breach instruction never reached the LLM ("Cats received" while attacking) | r15 | ⏳ not seen in game (plan F2) |
| 43 | "The rest of them aren't mine to call off" | r16 | ⏳ not seen in game |
| 44 | Work goal BLOCKED "stalled" while still mining raw stone (stall timer only counted the final item) | KFP r17 | ✅ run 4 |
| 45 | Goal refused `actor_serial_unavailable` when the NPC was away at a far machine | r17 | ✅ run 4 |
| 46 | NPC didn't know the base ("no stove, no mine in this shack"): `<player_base>` never reached the prompt | r17b | ✅ run 4 |
| 47 | Planner never filled machine inputs (farm water, processor stone, silo wheat) | KFP r17c | ✅ water→farm, stone→processor |
| 48 | Kept mining after there was enough stone; never switched to the processor | KFP r17d | ✅ run 4 |
| 49 | Test inbox spoke as the selected target ("Malzin to Malzin") | DLL r17b | ✅ |
| 50 | No walk back to the player after a goal (old orders won) | KFP r17b/17e | ✅ run 4 |
| 51 | Fetch/store/loot moved items instantly from any chest/body in range | KFP r17e/17g | built; needs Shay's eyes |
| 52 | "Put those back in storage" became GiveItem to the player | r17d | ✅ run 4 |
| 53 | "Resume/try again" queued a duplicate goal instead of RESUME | r17e | ✅ run 4 |
| 54 | (note) Goals for the same item count the stockpile, so a resumed goal can complete from another goal's output | — | by design |
| 55 | "Keep N stocked" became a one-off WORK_GOAL | r17f | ✅ run 4 |
| 56 | Direct actions (BODYGUARD) skipped `actor serial unavailable` when away | r17g | ✅ (order reached her) |
| 57 | Base block lost when the selected character stood at outer base buildings | r17h | ✅ standalone |
| 58 | Unpowered well: dead "operate" order, NPC idle | KFP r17e | superseded by 61 |
| 59 | NPC never reported a finished/blocked goal (`lifelike_initiative.flag` unread in 1.3.1) | DLL r17d + KFP r17f + r17i | PASSED run 9/10 (goal reports spoken) |
| 60 | "Fetch the vodka and the mead" only fetched one item | r17j + r17k | PASSED run 5–7 (F1) |
| 61 | Power gate blocked an idle machine (silo) before it was used | KFP r17g | PASSED run 10 (power wait only after loading the silo) |
| 62 | PATROL wandered the whole region (no waypoints) | KFP r17g + r17j | PASSED run 4 (managed patrol) |
| 63 | "Wait here"/"come here" left the patrol running | KFP r17g | PASSED run 4 (P1b) |
| 64 | "Loot the food off the dead bonedog": corpse not targetable, silent | r17j (+KFP r17g walking) | PASSED run 4 (C1/C2 conversion) |
| 65 | Goal-report initiative turn skipped "no eligible NPC listener" (only Malzin + player) | DLL r17e + KFP r17h (report within 70) | PASSED run 9 (tests 72, 74) |
| 66 | goal_report directive forced director mode → "No eligible Director cast", report lost | r17k | PASSED run 9 (tests 72, 74) |
| 67 | Patrol waypoints at building centres → path_failed, patrol never advanced | KFP r17h | PASSED run 10 (patrol 4/12 waypoints, no path_failed) |
| 68 | LOOT found no dead body (Sorth died at Home) | KFP r17h (scan merge + diag log) | PASSED run 9 (test 71) |
| 69 | Hauling took water out of the Bread Oven's input to water the farm | KFP r17h | not seen (needs a powered bread run, test 34) |
| 70 | Farm wait hidden by "Obtaining …"; dry farm waited forever | KFP r17h | partly seen run 10 ("Waiting for Wheat Farm XL to grow"); dry farm not seen |
| 71 | LOOT_AREA rejected Sorth's corpse (scan dead=1 valid=0) | KFP r19: native bool returns read as 1 byte (isPlayerCharacter garbage) + per-body scan log | PASSED run 9 (test 71) |
| 72 | Goal reports queued but never spoken ("Director scene failed: No eligible Director cast") | server r19: goal_report never uses director mode; failed director falls back to a normal turn | passed run 6 |
| 73 | Malzin talked about dead Sorth as alive | Stobe r19: roster marks "(dead)/(unconscious)", corpses merged into nearby; server r19: prompt says DEAD | passed run 8 |
| 74 | Job list panel only refreshed after reselecting her | KFP r19: replay updatePlayerSelection after GOAL_JOB add/remove; **failed run 8** → KFP r19h: replay her → nothing → her, log `GOAL_JOB ui refresh replayed/skipped` | installed 0193CD57, not retested |
| 75 | No walk-back after work goals (silent 180 s, gave up); report fired at once | KFP r19: return/report target = other squad member when the worker is selected; skip reasons logged; report fallback 200 s; started on accept | passed run 6 |
| 76 | "Make 3 steel bars" became a question, no goal | server r19: infer WORK_GOAL from a plain make-order to a faction member | passed run 6 |
| 77 | "Put them back" stored only the Mead | server r19: them/those/both → every item of the last FETCH batch | passed run 6 |
| 78 | Long idles between goal steps at high game speed | KFP r19: goal clock = real time x game speed; ticks/waits/stalls in game time | partly passed run 6 (patrol at 50x) |
| 79 | FP look-at click on a squad member takes control of them | KFP r19h+r20: click keeps control; r20 opens the clicked member's stats window | built 111289C5, not installed (test 85) |
| 80 | Work goals blocked "production stalled" after ~3 game min (budgets 10x short on the goal clock) | KFP r19b: game-time budgets x10 | PASSED run 9 (test 70) |
| 81 | Meals never started; prompts said "Well fed" while starving (hunger read as hungriness) | KFP r19b + Stobe r19b: level = hunger + fed; eat <150, stop 250; eating detected by a rise | PASSED run 9 (tests 50, 51) |
| 82 | Game crash on loading Home (14:18): meal step called a NULL inventory function (Malzin starving, patrol goal still active) | KFP r19c: resolve getinv in stg_exports; meals skip anyone down/dead/not loaded; whole meal step under the crash guard | no crash in ~15 loads of Home (runs 9, 10) |
| 83 | Goals given after a save came back when that save was loaded (goals live in our own files, not the save) | KFP r19d: goals stamped with in-game time (getTimeStamp_inGameHours); goals newer than the loaded world dropped silently | passed run 8 |
| 84 | STOBE hotkeys (chat box, push-to-talk, settings menu) fired while typing in other apps | Stobe r19e: hotkeys need the Kenshi window focused (foreground window in our process) | passed run 8 (Shay) |
| 85 | Hunger read 100x too low: raw MedicalSystem::hunger is 0..3, the UI shows x100 (Malzin raw 2.16 = UI 216); meals thought she starved, prompt said Starving | KFP + Stobe r19f: level = (hunger + fed) x 100; eating detection on raw rises >= 0.01 | PASSED run 9 (tests 50, 51) |
| 86 | "Guard me": BODYGUARD on Shay logged ok but Malzin stood aimless | KFP r19g: squad->squad guard/follow uses FOLLOW_PLAYER_ORDER (44) | PASSED run 10 (BODYGUARD → FOLLOW_PLAYER_ORDER) |
| 87 | "Follow me" → "Following you" with no action | server r19g: infer BODYGUARD@player for a plain follow/guard request to a faction member | PASSED run 10 ("Right behind you", follow executed) |
| 88 | Accepted surrender: STOP_ATTACK filtered out (NPC not flagged in combat), he attacked again | server r19g: a deal-sanctioned STOP_ATTACK is never filtered | PASSED run 9 (test 54: surrender accepted, STOP_ATTACK + 300 cats, deal COMPLETE) |
| 89 | Shay on block + passive logged as "Initiated attack", could break the ceasefire | Stobe r19g: player hitting someone already targeting him = "Defending against", no ceasefire break | PASSED run 9 (test 55: Shay's hits logged "Defending against") |
| 90 | Paid ceasefire ended after ~30 s (deal complete, 20 s DLL guard); gang re-engaged; NPC forgot the deal | Stobe r19g: guard 2 min; server r19g: watch 120 s, 4 re-issues, completed ceasefire honoured for 10 min | run 9: truce held for 2.5 min after the bug 116 fix |
| 91 | Surrender offers 1000 then 9000 cats, twice in one fight | server r19g: caps (common 50-300, leader ~1000, wealthy scaled, max 35 % carried), per-NPC cooldown 30 min | PASSED run 9 (test 56: offer 300 of 10000 carried) |
| 92 | No food anywhere: `GOAL_MEAL hungry` logged every tick (~60 ms), storage rescanned each tick | KFP r19h: after "no food anywhere" wait 10 game min before looking again | PASSED run 9 (test 51: one hunger report, re-check per 10 game min) |
| 93 | "Make 1 building material" BLOCKED at the Manual Stone Processor ("made no progress") while she worked it | KFP r19h: only finished units counted as progress, one manual unit > 30 game min; standing at the machine now counts, max 4 game h/unit | PASSED run 9 (test 70) |
| 94 | Old goal report re-delivered on a later initiative turn (mead STORE reported again at a knockout; "…the Hub") | KFP r20: goals loaded as finished count as reported | PASSED run 9 (test 73) |
| 95 | Lines meant for the player get a nearby NPC as speech target; that NPC answers as if addressed (goal report → Maelis, Skovrek's 300-cat offer → Maelis) | Stobe r20: server-swapped speaker addresses the player; server r20: chat/idle replies stored with the real listener | PASSED run 9 (tests 74, 75: TALKTARGET Shay) |
| 96 | "We're done here." recorded as ACCEPT of the NPC's assist deal + StopAttack | server r20: stobeNegLooksLikeAcceptance (no 'we're done') | FAILED run 9 (model ACCEPT on its own); fixed r21 server 072c3c5, PASSED test 76 |
| 97 | Other NPCs call Malzin "him" | server r20: people lines say '(female)/(male)' | PASSED run 9 (test 82) |
| 98 | No surrender offer to the player though several bandits were badly hurt (Pax pleaded in words, no deal) | server r20: no health data -> major hits (-35 % each); separate surrender/assist cooldowns | FAILED run 9; fixed r21 (Stobe live health events + server checks), PASSED test 77 |
| 99 | Fight chatter flood: ~35 NPC-to-NPC lines in 10 min, all spoken | server r20: initiative cooldown kept in its own marker (DLL deleted the flag); heals only when they involve the player | PASSED run 9 (test 78) |
| 100 | KenshiFP FP mode: an NPC you pick up can't be put down | KFP r20: G in first person calls dropCarriedObject | built 111289C5, not installed (test 84) |
| 101 | Loot orders looted nothing: target "Pax Hungry Bandit" vs body "Pax [Hungry Bandit]", and "bandits" vs "Bandit" | KFP r19i: names compared without punctuation; plural retried as singular | PASSED run 9 (test 71, with bugs 108/111/112/114) |
| 102 | Eating/drinking from your own pack logged as giving the item to the nearest NPC ("feeding Skovrek like a pet") | Stobe r20: unmatched losses only logged, never a hand-over | PASSED run 9 (test 79) |
| 103 | Purchases from a trader logged as bought from Malzin (cats really spent; seller name wrong) | Stobe r20: real trader first; squad members never the seller | built 040A3B1C, not installed (test 80) |
| 104 | A loot goal that took 0 items is reported as success ("picked clean", "weapons are stripped") | KFP r20: 0 looted -> BLOCKED with reason; server r20: COMPLETE with nothing done -> 'found nothing' | PASSED run 9 (test 72) |
| 105 | Fight narration invents facts: wrong person credited for knockouts, knockouts stated too early, Skovr/Skovrek mixed up, enemy gangs treated as allies | server r20: max one 'Initiated attack' in recent situation; rules: only state seen outcomes, fight sides over faction labels, look-alike names | PASSED run 9 (test 81, small sample) |
| 106 | Work goals: she works ~1 s, stops, waits, repeats; goals crawl even at 50x. The planner re-sends the operate order + rethink every 2 game s | KFP r19i: order only on a machine change or after 30 game s idle | PASSED run 9 (test 70) |
| 107 | 55 of 135 prompts start with an unfilled "#HERIKA_NAME#" placeholder | server r20: placeholders filled in stobeResolveNpcPromptOverrides | PASSED run 9 (test 83) |
| 108 | Looting ignored what a body wears (weapons, clothes): "found no items to take" | KFP r21 86cb3e6: dead/downed bodies' equipment sections searched | PASSED run 9 |
| 109 | A fight never ended when the enemy walked off into another fight 300 away; Malzin refused orders ("bandit breathing down our necks") | Stobe r21 3c7709d: local radius 150, far targets aren't evidence | PASSED run 9 (combat_end 12 s after) |
| 110 | Malzin refused a loot order on fresh bodies: "Already picked that one clean" (old chat history) | server f3a45df: loot order to a squad member gets a prompt note; no loot action in her reply → LOOT_TARGET (→ LOOT_AREA goal) | PASSED run 10 (goal ran; BLOCKED pack full) |
| 111 | Full pack/slots reported as "found no weapons to take" | KFP r21 c15dec1: "no room" / "took what fit" | PASSED run 9 |
| 112 | Weapons that go straight into her weapon slots counted as 0 looted | KFP r21 2b62a1a: count what moved | PASSED run 9 |
| 113 | The player's own knockout/recovery/death never became events | Stobe r21 4ca2d63 | PASSED run 9 (`[EVENT] knockout: Shay` when Lornic KO'd her) |
| 114 | A big worn weapon (Staff) dropped next to the body instead of looted | KFP r21 81f6b90: worn items taken straight from bodies | PASSED run 9 |
| 115 | Goal meals used food up without feeding her (eatItem: +1 per Dried Meat) | KFP r21 7c3d3e3: food into her pack, the game eats | PASSED run 9 (test 50) |
| 116 | A paid ceasefire broken by a gang-mate's idle chat (Attack action) | server r21 5d75ff2 + c0599a4: ATTACK on the player dropped for the deal's gang for 10 min | PASSED run 9 (test 55) |
| 117 | After a reload the same serial carries another session's name (Garven = Smeck); the voice payment went to "Smeck" and the deal with "Garven" stayed unpaid | server 88f1080 (getNpcData takes the live serial) + fd5975c (snapshot never claims a profile with another serial) | PASSED run 10 (new raiders got their own rows; fallback refused logged) |
| 118 | Bridged actions (EQUIP/UNEQUIP...) failed for a squad member >750 units from Shay ("ACTION_BRIDGE actor not found") | KFP r21 fd1c317: squad list searched first | PASSED run 9 |
| 119 | Asked to put on something she already wears, she tries to equip it ("let me get it back on") | server c331522: prompt note "already wearing"; EQUIP of a worn item dropped | PASSED run 10 (test 16: "It's already on") |
| 120 | A squadmate's gift to the player blocked as an outsider's ("Blocked unpaid gift ... affinity 0") | server r21 7eeeefb: speaker's own action config | PASSED run 9 (test 28) |
| 121 | Full pack: work goal retried "could not take Raw Stone" every second, never blocked | KFP r21 814e72e: BLOCKED "her pack is full" after 5 tries | PASSED run 9 |
| 122 | Cats paid up front for a refused request were kept | server ecdf4fc: unearned prepayment refunded | PASSED run 9 (test 11) |
| 123 | Action target "Grenn Hungry Bandit" (brackets stripped) didn't match; item went to Shay | Stobe 8a08078: punctuation-insensitive match | PASSED run 10 (test 39: 3 kits to Drask [Hungry Bandit]) |
| 124 | "Wait here for <name>" → plain HoldPosition | server 3ffad07: prompt → WaitForGoal | PASSED run 9 (test 42) |
| 125 | WAIT_FOR target with stripped brackets never matched the squad member | KFP cf0d2fa | PASSED run 9 (test 42) |
| 126 | Payment skipped while the NPC was KO'd → deal IMPOSSIBLE | server a652d74: re-sent up to 2x on her next line (10 min) | PASSED run 10 (test 86: Skelden paid 300 after waking) |
| 127 | SPARE broken by the squad's swing 3–10 s after a truce | server fd36e05: 10 s grace | PASSED run 9 (test 19) |
| 128 | Surrender directive lost when the NPC was named mid-fight | server 9203c6f: "<title>" matches "<Name> [<title>]" | unit-tested, not seen in game |
| 129 | NPC accepting the player's counter dropped by the bug 96 guard | server 5cfc41f | PASSED run 9 (test 18) |
| 130 | Offer cap (bug 91) lowers an accepted 400 to 300 after she said "Four hundred" | server 52468b7: capped ACCEPT recorded as COUNTER at the cap; her line rewritten; bare amounts count as spoken | PASSED run 10 (test 89: Tarvek "I can't go above 300") |
| 131 | Re-queued payment marked IMPOSSIBLE ("never delivered") while the bored path was still generating his line | server 0f839c8: a directive claimed <60 s ago with no outcome counts as pending | unit-tested (seen in run 10: overwritten by the dispatch 0 s later) |

## Lessons from the runs (process)
- Claude is too slow for live fights (checks plus 5–10 s replies): Shay was knocked out twice. Fights need Shay on pause and a pre-armed watcher.
- Voice alone can't start a fight (she refuses "attack me" and dares threats); use `stobe-force-attack`.
- STOBE defers speech and actions while the game is paused (`ACTION_QUEUE: paused`); lines sent while paused run on unpause, in order.
- Reloading a save drops the DLL's queued actions (a queued payment and a revenge attack were discarded in run 3).
- The server's deal clocks only tick when something reaches the server (a chat line or game event).
- At high game speed, watch for knockouts too (hunger), not just fights: Malzin starved at 50x in run 5.
- Low-trust NPCs (Resentful) refuse credit ("cats first"); Fond NPCs accept pay-later. Set trust by hand for tests that need it (see the plan).
