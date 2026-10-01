# STOBE negotiation: in-game test guide (Phases 1–8)

Everything is live on the server. There were **no DLL changes**, so just start the launcher and Kenshi as usual.

## Before you start
- Use a clean save, and address each NPC **by name** in your first line ("Julia, …").
- After each test, you can check what the server recorded. Run this in the WSL terminal, or just tell me and I'll read it:

```
cd /var/www/html/StobeServer && sudo -u www-data php tools/negotiation_admin.php deals 3
```

- To see one deal with all its evidence, use `… deal <contract_id>`. To see queued NPC-initiated actions, use `… directives`.
- To switch a phase off, use `… phase 6 off` (and `on` to switch it back). To list all switches, use `… phases`.

## What each status means
| Status | Meaning |
|---|---|
| `DISPATCHED` | The action was sent to the game and is waiting for proof |
| `VERIFIED` | The game's own execution record, a Cats change or the combat log proved it |
| `AWAITING_PLAYER` | You owe something; the clock is running |
| `UNMET` / `IMPOSSIBLE` | It didn't happen; the evidence says why |

| Deal status | Meaning |
|---|---|
| `COMPLETE` | Every term was verified |
| `BREACHED_PLAYER` | You didn't deliver |
| `BREACHED_NPC` | The NPC betrayed you on purpose |
| `IMPOSSIBLE` | The game couldn't do something that was agreed |
| `EXPIRED` | Bargaining went quiet for 10 minutes |

## Paying by voice (new)
Just say it to the NPC you're talking to. You (the player) really hand it over before they reply:
- "Here are your 200 cats" / "Here are your two hundred cats"
- "I give you two thousand three hundred cats"
- "Take these 50 cats"
- "Here, take this bread" / "Here are 2 bread". The item must be in your carried inventory.
- If you owe them on a deal: **"Two hundred cats."** or **"Here's your money"** pays what you owe.

These **never** pay:
- offers ("I'll give you 200 if…") and anything with *if / I'll / would / later*;
- questions;
- negated lines ("no way I'm paying", "I don't want to pay");
- reported speech ("I offered to pay you 200");
- any sentence longer than about 18 words.

Each sentence is judged on its own, so "Fine. Here are 300 cats." pays 300.

**Bets and "if you win/lose" outcomes** are recorded as promises. The server can't know who won a fight, so nothing is refunded or paid automatically.

**"Here's your cats"** in the same line that closes the deal pays what that deal says you owe.

If you don't have enough Cats, nothing moves, and the NPC is told you came up short.

To switch it off: `… phase` doesn't cover this one. Set `NEGOTIATION_VOICE_PAYMENT` to `false` instead (ask me).

## Bartering items by voice
Example: a drink for her hat, with Grog or Vodka in your carried inventory.
1. "Malzin, I'll buy you a drink if you take off your hat." This starts a deal. Nothing is handed over yet.
2. She agrees, e.g. "Once I've got the drink in hand."
3. Give it with any of:
   - "Here's your drink" (uses the drink you carry)
   - "Here, take this grog"
   - "Here's what I owe you"
4. **Expect:**
   - you hand her the Grog;
   - the game confirms it, and the drink term is `VERIFIED`;
   - she's then told to keep her side, and takes the hat off;
   - the deal ends `COMPLETE`.

"Drink" matches any drink you carry: grog, rum, sake, vodka, whiskey, beer, ale, wine and similar. Name a specific one if you want to choose which.

**Food works the same way:**
- If the deal only says *food* ("I'll give you food to stop"), then "Here's some food" or "Here's your food" hands over **any** food you carry: bread, dried meat, foodcube, ration pack, rice bowl and so on.
- If a specific item was named ("I want bread and I'll stop"), **only bread** counts. "Here's your food" hands over bread if you have it, and nothing otherwise.

**Test F1:** get a hostile NPC to agree to "food to stop", then say "Here's some food" and check that the deal completes. Then try a deal where they demand bread while you carry only dried meat, and say "here's your food". Nothing should be handed over, and the deal stays unpaid.

## Tests

### T0: Voice payment on its own
1. Say to any NPC: "<Name>, here are 20 cats."
2. **Expect:** a game message like "Shay gave <Name> 20 cats", and your Cats go down by 20.
3. If nothing happens, tell me. `stobe.log` will show whether the game received it (`HOOK_MSG_PROC: Processing: NPC_ACTION: Shay`).

### T1: Bribe that is paid (Phases 1 and 2)
1. Get one outsider to attack you. Say: "<Name>, I'll give you 300 cats to stop attacking."
2. If they counter, reply: "<Name>, okay, <their number> it is."
3. **Expect:** they stop attacking. The deal goes to `AWAITING_PERFORMANCE` with STOP_ATTACK `DISPATCHED`, which becomes `VERIFIED` after about 30 s without attacks.
4. **Within 1 minute**, pay them with STOBE's manual **give cats** action (or a normal trade).
5. **Expect:** the GIVE_CATS term is `VERIFIED` and the deal is `COMPLETE`.

### T2: Bribe that is not paid (Phases 1 and 7)
1. As T1, but don't pay.
2. **Expect:** after 1 minute the deal is `BREACHED_PLAYER`, then an angry line from the NPC, and they **attack again**.
3. Their affinity toward you drops by 15, and they remember you broke the deal.

### T3: Truce that doesn't hold (Phase 2)
1. If an NPC who agreed starts fighting again within 30 s, the server re-sends the stop order, up to 2 times.
2. **Expect:** `deal <id>` evidence shows `attack_resumed` and `truce_reissue_queued`. If it keeps failing, the deal becomes `IMPOSSIBLE` (`truce_did_not_hold`).
3. Tell me if this happens. It shows whether vanilla AI keeps re-targeting you.

### T4: Haggling and the Trella problem (Phase 3)
1. During a fight with more than one enemy, bargain with one of them.
2. For your follow-ups, **don't** say a name ("Do we have a deal?").
3. **Expect:** your line goes to the NPC you're negotiating with. `stobeserver.log` shows `Chat addressee routed to negotiation partner`.
4. Keep countering. By the 6th round they end the talks.

### T5: Surrender offer from a losing enemy (Phase 4)
1. Beat an enemy down until they're badly hurt. Don't kill them.
2. **Expect:** within a few seconds they speak up on their own, begging or offering Cats or items. `deals` shows a `PROPOSED` deal by `npc` with kind `surrender`.
3. Say "<Name>, deal." **Expect:** `ACCEPTED`. Their terms execute, and your SPARE term is verified if you don't attack them for 30 s.
4. Limits: once per NPC per fight, and at most one such offer every 2 minutes.

### T6: NPC asks you for help (Phase 5)
1. Stand near a neutral NPC who is losing a fight with someone else.
2. **Expect:** they call to you for help, maybe promising a reward.
3. Accept and help. Their reward (`when: after_player`) is handed over after the fight ends with them alive.

### T7: Deal outside combat (Phase 6)
1. Say: "Malzin, I'll give you 200 cats to take off your hat."
2. **Expect:** a social deal. If she accepts, the hat comes off and the UNEQUIP term is `VERIFIED` from KenshiFP's log. You then have **1 in-game day** to pay.
3. Loans: "<Name>, lend me your <item>, I'll bring it back." Expect a `LOAN_ITEM` term plus your `RETURN_ITEM` obligation.

### T8: Betrayal and wider deals (Phase 8)
1. Rare, and only from dishonest or greedy personalities who already dislike you.
2. **Expect:** occasionally, after you pay, they attack anyway. The deal becomes `BREACHED_NPC` with `betrayal.planned=true` in `deal <id>`, so it can't be mistaken for a bug.
3. Also try a toll ("I'll pay you 100 to let us pass"), which may produce `SAFE_PASSAGE`, and a ransom, which may produce `RELEASE_PRISONER`.

## Known limits
- **Paying by trade** is detected from the NPC's Cats balance, which only refreshes when they speak or sync. If you pay by trade, say something to them afterwards. The manual **give cats** action is detected immediately.
- The **truce** is STOBE's faction-level ceasefire. If vanilla AI still re-targets you after 2 re-issues, the deal records it honestly as `IMPOSSIBLE`. Please report this, because it's the Phase 2 open question.
- **NPC-initiated speech** (surrender, help, settlement, betrayal, angry reactions) uses KenshiFP's initiative trigger, so it only works while KenshiFP is loaded. If an NPC owes a dispatch and you talk to them first, it's attached to their reply instead.
