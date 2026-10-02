# Run 8 deep dive (2026-10-01, 22:13–23:01)

Sources (saved in `archive/logs-run8-2026-10-01/`, not committed): `stobe.log`, `KenshiFP.log`, goal files, the server log slice, and all 135 LLM prompts + outputs (`context-slice.log`, `output-slice.log`). Every claim below was checked against these.

## Why it felt worse than recent runs
1. **The fight hit untested paths all at once.** Recent runs were mostly one-on-one with Malzin at Home. This was a 4-faction brawl (Hungry Bandits, Dust Bandits, a Free Trader, then Holy Nation Outlaws), and every weakness in idle chatter, addressee tracking and offers showed at the same time.
2. **Most of the wrong talk comes from 3 plumbing bugs, not the model** (95, 102, 94). They feed NPCs false "memories", and each NPC then builds on them.
3. **My process made it worse:** I didn't watch the fight live, added a step that wasn't in the plan, and unpaused the game after an attack alert.

## Root causes, by what you saw

### "People answered things that weren't said to them" (bug 95): two plumbing bugs
- **DLL keeps the old listener when the server swaps the speaker.** The DLL starts an idle turn for a pair (22:17:41: Pax → Maelis). If an initiative is pending (goal report, NPC offer), the server swaps in a different speaker and tells it to talk to the player (Malzin → "shay"; 22:24:33 Skovrek → "shay"). The server's reply carries no addressee, so the DLL tags every line with the pair's original listener (`TALKTARGET` = Maelis). Result: Malzin's goal report and Skovrek's "Greenlander, I'll pay you 300" were recorded as said **to Maelis**.
- **Server guesses addressees and skips the player.** When storing an NPC line without a target, `stobeInferDialogueTargetForLog()` (`lib/data_functions.php` ~3680) excludes the player on purpose and picks the only other NPC nearby. Malzin's reply to *your* order at 22:48 ("Give me a bit") was stored as "talking to: Dezerka".
- Those wrong records go into every nearby NPC's "Recent Situation", so they reply as if spoken to. Skovrek later pressed *Malzin* about "that three hundred".
- **Fix:** the server returns the addressee with each line and the DLL uses it; the guesser may pick the player, and for a chat reply always uses the player who spoke.

### "Malzin said I was feeding the Dust Bandit" (bug 102)
- The DLL builds `trade` events by diffing inventories. A loss with no matching gain (eating, drinking, a used medkit) is pinned on a "likely counterparty" (`ResolveLikelyInventoryTransferCounterparty`, `main.cpp` ~6490): the nearest/talked-to NPC. Shay and Malzin ate and drank during the fight and it was logged as "transferred 1x Water to Skovrek" (×6). Malzin then mocked you for it, twice.
- **Fix:** an unmatched loss is "used/consumed" (or nothing at all), never a transfer to someone.

### "Bought food from Malzin" (bug 103)
- To name a seller the DLL takes your **last talk target** if the game says they're a trader (`ResolveLikelyTraderForActor`, `main.cpp` 4430). Malzin was the talk target and carries the trader flag, so purchases from the real trader were credited to her (1704 + 2512 + 855 cats). The cats you spent were real.
- **Fix:** never name a squad member as the seller; prefer the character whose inventory gained the cats / lost the items, then the open trade window.

### "She said all done when the bodies still had weapons" (bugs 101 + 104)
- **101:** the loot target never matched: "Pax Hungry Bandit" vs "Pax [Hungry Bandit]", "bandits" vs "Bandit". Fixed, built (`8751BF24`), not installed.
- **104:** the goal then ended COMPLETE with 0 items, and the server's report told her: *"You just finished the job (loot area all; **0/0 done**)… tell Shay **that it's done**."* She did as told.
- **Fix:** a loot that matched nothing → BLOCKED "couldn't find Pax's body"; a COMPLETE with 0 done gets a "found nothing to take" instruction, never "it's done".

### "Mead's in the chest. Done." out of nowhere (bug 94)
- KenshiFP saves task goals to `stobe_task_goals.tsv` but **not the "already reported" flag**. After every game launch, each finished task goal is reported again the first time she's near you. The 22:17 knockout gave her a turn, and the old mead goal was reported a second time (first at 22:01).
- **Fix:** mark loaded COMPLETE/BLOCKED/CANCELLED goals as reported; drop old finished goals from the file.

### "We're done here" became a deal (bug 96)
- `stobeNegPlayerAcceptsOfferNote()` (`lib/negotiation_engine.php` 1213) treats single words like **done**, fine, ok, sure anywhere in your line as accepting the open offer. It then injected "The player has just accepted your offer… That is binding" into Skovrek's prompt. His open offer was the one wrongly aimed at Maelis (bug 95).
- **Fix:** accept only on clear acceptance ("deal", "agreed", "I accept", "yes" as the whole answer); "we're done", "I'm done", "done here" mean ending the talk.

### No surrender offers (bug 98)
- The server's "losing?" check uses stored health. Maelis, Pax and Skovr had **no health data** (`blood 0/0`, no limbs), and with no data the server assumes 100 % (`stobeNegHealthRatio` returns 1.0). Only Vorr had real numbers.
- Skovrek's "help me" offer also started a 120 s **global** cooldown that blocks everyone's surrender offers.
- **Fix:** read health from the live game for combatants (or treat missing as unknown and use knockout/major-damage events); separate cooldowns for surrender and assist.

### Made-up fight facts (bug 105)
- Knockout events do reach the prompts (70 lines), but they're buried under **1,862 "Initiated attack" events** (all in this session).
- The model said things it had no event for: "Vorr's down" at 22:21 (KO'd at 22:24:53); "your Ranger did the work on Pax" two seconds before Skovrek's own club KO'd Pax.
- It mixed up **Skovr** and **Skovrek**: Karric's prompt correctly said "Dezerka took a major hit from Skovr", and he said "Skovrek's club".
- Wrong sides: Maelis (Hungry Bandit)'s prompt listed Skovrek's Dust Bandits as `[Friendly]` while they were fighting each other.
- **Fix:** prompt rule "only state that someone is down, dead or hit if an event or the people list says so"; collapse repeated "Initiated attack" lines; show each combatant's state (fighting / down / dead) and who they're fighting; label near-identical names (Skovr vs Skovrek); take faction attitude from who is actually fighting whom.

### Malzin called "him" (bug 97)
- Her gender is in only 7 of the prompts that mention her ("Malzin (Female Greenlander)"); in 31 she's just "Malzin | player's squad | doing: …".
- **Fix:** add gender to the people-awareness lines.

### Chatter flood (bug 99)
- The idle timer is 1 minute, but every knockout, heavy hit, death and **heal** (18 heals, mostly Holy Nation Outlaws patching each other) arms an extra turn: 4–6 turns a minute, 41 in the fight.
- **Fix:** cap idle turns in combat (1 per 30–60 s), only for events near the player, and never for strangers healing each other.

### Template error (bug 107, new)
- 55 of 135 prompts start with "You are **#HERIKA_NAME#**", an unfilled placeholder. Only the diary code replaces it.

### Work goals stop-start (bug 106) and the stall (bug 93)
- The planner re-sent the operate order + rethink every 2 game seconds, interrupting her each time. Fixed, built (`8751BF24`), not installed. Bug 93 (installed) counts being at the machine as progress.

### Smaller ones from this run
- FP click on a squad member keeps control but shows **your** info, not hers (bug 79, half done).
- In first person, a picked-up NPC can't be put down (bug 100).
- The job list refresh skipped because Malzin wasn't the selected character (expected; bug 74 not yet retested).

## Fix order I'd suggest
1. **Plumbing that poisons memory:** 95 (addressee), 102 (consumption as gift), 94 (re-reports), 103 (seller). These cause most of the false talk.
2. **Deal and goal honesty:** 96 ("done" ≠ accept), 104 (0 looted ≠ done), 98 (health data, cooldowns).
3. **Prompt quality:** 105 (facts, names, sides), 97 (gender), 107 (placeholder), 99 (chatter cap).
4. Install the built fixes (101, 106) and retest the work goals.
