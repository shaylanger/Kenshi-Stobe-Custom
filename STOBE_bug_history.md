# STOBE bug history (bugs 1–64, 2026-09-30)

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
| 23 | "Take this bread" gave nothing for "Poppyseed Bread" | r9d | ⏳ not retested (plan D7b) |
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
| 59 | NPC never reported a finished/blocked goal (`lifelike_initiative.flag` unread in 1.3.1) | DLL r17d + KFP r17f + r17i | built, not installed |
| 60 | "Fetch the vodka and the mead" only fetched one item | r17j | live, not retested |
| 61 | Power gate blocked an idle machine (silo) before it was used | KFP r17g | built, not installed |
| 62 | PATROL wandered the whole region (no waypoints) | KFP r17g + r17j | built, not installed |
| 63 | "Wait here"/"come here" left the patrol running | KFP r17g | built, not installed |
| 64 | "Loot the food off the dead bonedog": corpse not targetable, silent | r17j (+KFP r17g walking) | live, not retested |

## Lessons from the runs (process)
- Claude is too slow for live fights (checks plus 5–10 s replies): Shay was knocked out twice. Fights need Shay on pause and a pre-armed watcher.
- Voice alone can't start a fight (she refuses "attack me" and dares threats); use `stobe-force-attack`.
- STOBE defers speech and actions while the game is paused (`ACTION_QUEUE: paused`); lines sent while paused run on unpause, in order.
- Reloading a save drops the DLL's queued actions (a queued payment and a revenge attack were discarded in run 3).
- The server's deal clocks only tick when something reaches the server (a chat line or game event).
- Low-trust NPCs (Resentful) refuse credit ("cats first"); Fond NPCs accept pay-later. Set trust by hand for tests that need it (see the plan).
