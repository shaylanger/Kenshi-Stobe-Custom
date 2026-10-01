# STOBE negotiation: Phase 1 completion plan

**Status:** planned only; no code has changed.
**Date:** 2026-09-28
**Track:** B (negotiation). Apply this after the Track A hat test.

## Why we're still on Phase 1

The agreed rule is that Phase 2 doesn't start until Phase 1 can do two things:
- carry out and verify every supported term of an accepted deal, or
- report a concrete reason why it can't.

Today an accepted deal only queues `STOP_ATTACK`. No payment, item or first-aid term is ever carried out or checked. So this plan finishes Phase 1. Phase 2 (a truce that holds) is outlined at the end.

---

## 1. What the 2026-09-28 hostile test showed

Sources: the `batering_with_hostile+.txt` bundle, the `eventlog` table and `stobe_social_contract`.

| # | Finding | Evidence | Cause |
|---|---|---|---|
| F1 | Julia countered and the counter was recorded | `deal-2fa7…` COUNTERED: 2000 Cats + STOP_ATTACK | Working as designed |
| F2 | The counter's "drop that machete" demand was lost | The terms have no disarm entry | There's no term type for the player disarming |
| F3 | Your next three lines went to **Trella**, not Julia | eventlog: `(talking to: Trella [Slaver Guard Resule])` | The game client (`ChatBox.cpp` `ResolveChatTargetCharacter`) changed the target mid-fight. This isn't a server problem. |
| F4 | The 20,000 Cats offer got the reply "..." | `llm_stream_response_incomplete`, `finish_reason=length` | The model hit its output-token limit; the negotiation fields make responses longer |
| F5 | Nothing checked whether you could afford 5,000 or 20,000 Cats | No check exists | The client sends `money` per character (`Context.cpp:4620`), but the server never stores it. `core_npc_master.metadata` has no `money` key. |
| F6 | A counter goes nowhere | If your reply to the counter doesn't match the keyword filter, negotiation isn't even active on the next turn. And even an ACCEPT would create a new deal instead of accepting the counter. | `$negotiationActive` needs `stobeDealLooksNegotiableMessage()` **and** combat; there's no code for "accept the open counter" |
| F7 | Combat state flips quickly | Julia's metadata showed `running`, `is_in_combat=false` 6 s after her counter | Phase 1 can't depend on one metadata snapshot |
| F8 | The "world verified" check is fake | The caller passes `stobeDealTransition(... ['world_verified'=>…])` itself | A known gap from the previous handoff |

### Findings from the second test (Malzin, 21:40–21:44)

| # | Finding | Cause, and which item fixes it |
|---|---|---|
| F9 | The 40,000 Cats bribe was recorded as a **COUNTER** ("put the cats on the floor right now"), so no STOP_ATTACK was sent | Working as designed, but there's no way to accept the counter. **B1 fixes this.** |
| F10 | "Okay, stop attacking me…" got a cut-off, failed reply | `finish_reason=length`. **B2 fixes this.** |
| F11 | "You gotta stop attacking…" got "Fine. I'll give you room." plus `FACE_TARGET`, with no STOP_ATTACK. **She agreed in words but did nothing.** | That turn wasn't treated as negotiation, probably because the combat flag flipped (F7). **B1** (an open deal keeps negotiation active) fixes it. Also new **B7b**: if the speech agrees to stop fighting but there's no STOP_ATTACK, either add it (only when an ACCEPTED deal exists) or rewrite the line. |
| F12 | **5 cut-off replies in about 3 minutes**, including both "put your clothes back on" requests, which never reached the game | Model `deepseek-v4-flash` spends most of its output budget on hidden reasoning (461 of 573 tokens in a good reply). Current payload: `reasoning: {exclude: true}`, which hides the reasoning but doesn't limit it. **B2 becomes a general dialogue fix and is done first.** |
| F13 | The clothing-for-Cats deal and your refusal to pay worked **only through the model's memory**: no ledger entry, but a real `ATTACK@Shay` | Negotiation only switches on in combat. Deals made outside combat are Phase 6. |

**New item order:** B2 (cut-offs, all dialogue), then B3, then B1 + B7b, then B4 to B9.

---

## 2. Phase 1 completion: work items

This is all server-side PHP, with no DLL changes, **as long as step 0 confirms Cats balances reach the server**.

### Step 0: Confirm the data we need (read-only, done first when applying)
1. Capture one raw request payload during combat. Check that `money` is present for **both** the NPC and the player.
2. Measure how often NPC metadata syncs arrive during combat (from `updated_at` and `sync_reason`).
3. If `money` isn't sent for the player, **stop**. That needs a STOBE DLL change (x64 v100 build), which I'll bring to you as a separate decision.

### B1: Keep the negotiation going on follow-up turns (fixes F6)
- Make `$negotiationActive` true when the NPC has an **open deal** with you (PROPOSED, COUNTERED, ACCEPTED or AWAITING_PERFORMANCE), whether or not the keyword filter or combat check passes.
- Allow at most one open deal per NPC and player. A new offer cancels the old one and records `superseded_by`.
- **Basic counter acceptance:** if the NPC has an open COUNTERED deal and returns ACCEPT, move **that same deal** to ACCEPTED (the transition already exists), using the newly validated terms. Full back-and-forth bargaining stays in Phase 3.
- Files: `processor/chat.php` (~L1109) and `lib/chat_helper_functions.php` (~L12508). Both call one shared helper, `stobeDealShouldNegotiate()`, so the two conditions can't drift apart.

### B2: Stop empty "..." replies (fixes F4)
- For negotiation turns, raise the output-token limit and use smaller reasoning settings if the provider supports that. I'll pick exact values after reading `getLlmConfigForNpc`.
- If a reply still ends with `finish_reason=length`, retry once. If that also fails, give an honest short in-character line. Never record a deal from a cut-off reply.

### B3: Store Cats balances (fixes F5)
- Save the incoming `money` into `metadata.money` along with `money_observed_at` (a timestamp), in the existing metadata normalizer.
- This matters beyond negotiation: it's also the evidence source for B5.

### B4: Check whether each term can actually be performed

**Terms the NPC performs.** The server knows these.

| Term | Rule |
|---|---|
| NPC `GIVE_CATS` | Needs a known `money` ≥ the amount; otherwise the deal is `IMPOSSIBLE (npc_insufficient_cats)` |
| NPC `GIVE_ITEM` / `RETURN_ITEM` | The item must be in the NPC's `inventory_items` in sufficient quantity. Match by name; keep the exact matched name. |
| NPC `FIRST_AID` | Only allowed where the existing FIRST_AID bridge can run |

**Terms you perform.** Realism rule: the NPC can't see your purse.
- Accept the deal even if you can't pay; bluffing is part of bargaining.
- Record `affordable_at_acceptance: true|false|unknown` as internal evidence. Don't show it to the NPC.
- If you then fail to pay, the deal times out as unpaid (B6).

**Kinds nothing can carry out.**
- `LEAVE_AREA` has no action that performs it.
- **Recommendation:** remove it from the allowed list and the prompt until one exists, so an NPC can't promise it.

Validation stays deterministic in `stobeDealValidate` plus a new `stobeDealFeasibility()`. The model's claims about inventory are never trusted.

### B5: Carry out the deal (fixes F8)
A new module, `lib/negotiation_coordinator.php`, runs deals one step at a time.

1. On ACCEPT, build **per-term records**: `{term_id, kind, by, to, amount/item, status, dispatched_at, deadline_at, evidence}`, with statuses PENDING, DISPATCHED, VERIFIED, FAILED or IMPOSSIBLE. Store them in the deal's `terms` data, or in a `term_state` field added with `ALTER TABLE … ADD COLUMN IF NOT EXISTS`.
2. **Order of steps:**
   - (a) The NPC stops attacking (dispatched in the same response, as today).
   - (b) Take a baseline snapshot of both parties' `money` and inventory.
   - (c) Carry out the NPC's own terms **one at a time** through existing actions (`GIVE_CATS@<player>@<n>`, `GIVE_ITEM@<player>@<item>`, the FIRST_AID bridge).
   - (d) Your terms become an **obligation**. The NPC's prompt shows it (e.g. "Shay owes you 1000 Cats, due within 2 min"), and you pay through STOBE's manual "give cats" action or a normal trade.
3. **When the coordinator runs:**
   - on every incoming event or metadata sync that involves either party;
   - on the existing background processor's tick, to catch deadlines. I'll confirm its entry point before applying.
4. **Safeguards:** it's safe to run twice on the same event (keyed by `term_id` plus status). It never re-sends an action that's already out; a failed action becomes FAILED, not a retry loop.

### B6: Verify from observed game state
`world_verified` from the caller is removed. The coordinator marks a deal COMPLETE only when **every** term is VERIFIED.

| Term | Counts as VERIFIED when |
|---|---|
| NPC `STOP_ATTACK` | At least 2 metadata syncs show `is_attacking=false`, spanning ≥ 30 s after dispatch. If the NPC attacks again inside that window, the term is FAILED (`reacquired`), **not** BREACHED_NPC; Phase 2 looks into why. |
| `GIVE_CATS` (either direction) | Payer's `money` drops **and** payee's `money` rises by ≥ the amount against the baseline, with both readings newer than the dispatch or obligation start. For you, a matching manual "give cats" event plus the money change. |
| `GIVE_ITEM` / `RETURN_ITEM` | The payee's `inventory_items` count for the matched item goes up and the payer's goes down |
| `FIRST_AID` | The target's `blood` / `limbs` metadata improves after dispatch |

**Final deal states:**

| Situation | Deal status |
|---|---|
| Every term verified | `COMPLETE` |
| Your term's deadline passes unmet, and the NPC's own terms were verified | `BREACHED_PLAYER` |
| Deadline passes and nothing can be pinned on either side | `EXPIRED` |
| Something couldn't be done | `IMPOSSIBLE` (with the term and reason) |
| The NPC fails a term it agreed to | `BREACHED_NPC` is **not used in Phase 1**. Without deliberate betrayal (Phase 8), an NPC failure counts as a system failure: `FAILED`, then `IMPOSSIBLE`. |

Every transition writes an `evidence` entry: which syncs, the before and after values, and timestamps.

### B7: Truthful dialogue
- **Remove the spoken line "The terms still need to be carried out."** Instead, the NPC's prompt block gets the per-term status, so the NPC talks about the deal truthfully in its own voice.
- **Invalid structured deal:**
  - If the NPC's speech doesn't claim agreement, keep it and store the result as REJECT.
  - If it does claim agreement, swap in a short in-character refusal. That replaces today's single fixed line.
- **When you don't pay:** the NPC sees `BREACHED_PLAYER` or an overdue obligation. It can then react (demand payment, or resume the fight with the existing real `Attack` action), within the existing property and escalation rules.

### B8: Visibility for debugging (no web endpoint)
- Add structured `stobeLogInfo` lines at every stage: `Deal feasibility`, `Deal dispatch`, `Deal term verified/failed`, `Deal status`.
- Add a command-line script, `tests/deal_status.php [npc]`, that prints open deals and per-term evidence.
- The public API endpoint that was rejected **stays rejected**.

### B9: Tests
- Use a **dedicated test database**, and keep the existing safeguard that refuses to run from `tests/` without one. Earlier negotiation tests ran on the live DB; that stops here.
- **Synthetic tests:**
  - feasibility, with known/unknown money and missing items;
  - the order of steps;
  - running twice changes nothing;
  - STOP_ATTACK verification when the NPC attacks again;
  - Cats verification from before/after money;
  - timeout → BREACHED_PLAYER;
  - accepting a counter;
  - one open deal per NPC;
  - a cut-off reply records no deal.
- Run `php -l` on every touched file.

---

## 3. Order of changes when you say "apply"
1. Step 0 read-only checks, and a go/no-go report to you.
2. Back up to `/tmp/stobe-negotiation-p1c-backup_<ts>/`: all touched PHP files and a DB schema dump.
3. B3 (store Cats balances), then B1 (conversation continuity), then B2 (token limit).
4. B4 (feasibility), then B5 (coordinator), then B6 (verification).
5. B7 (dialogue), then B8 (logs), then B9 (tests).
6. Deploy to the live server; run `php -l` again live.
7. Hand over to you for the in-game Phase 1 sign-off tests (section 5).

**Files touched:**
- `lib/negotiation_phase1.php`
- `lib/negotiation_coordinator.php` (new)
- `lib/bootstrap.php` (require the new module)
- `processor/chat.php`
- `lib/chat_helper_functions.php` (trigger, prompt block, money storage)
- tests

**No KenshiFP or STOBE DLL changes**, unless step 0 fails.

---

## 4. Decisions (Shay answered on 2026-09-28)

D1 yes · D2 yes · **D3 = 1 minute** · D4 later · D5 yes. Anywhere below that still says 2 minutes now means 1 minute.

Original questions:

| # | Question | My recommendation |
|---|---|---|
| D1 | Include basic "accept the NPC's counter" in Phase 1? | **Yes.** Without it a counter goes nowhere. Full multi-round haggling stays in Phase 3. |
| D2 | Remove `LEAVE_AREA` until there's a real action that performs it? | **Yes**, so NPCs can't promise something the game can't do. |
| D3 | How long you get to pay | **2 real minutes** from acceptance, with the time left shown in the NPC's context |
| D4 | Add a "player drops weapon" term (Julia's machete demand)? | **Later** (Phase 3 terms). For now the NPC can still ask for it in speech; it just isn't enforced. |
| D5 | Payment methods that count | Both STOBE's manual "give cats" action and normal Kenshi trade, since both are verified by the money change |

---

## 5. In-game Phase 1 sign-off tests (clean save, one attacker, say its name)

Name the NPC in each line ("Julia, …") until the target-switch issue (F3) is fixed.

1. **Refusal.** A lowball offer is rejected. No deal is recorded, and the NPC keeps its own voice.
2. **Accept + ceasefire.** A fair offer is accepted, and STOP_ATTACK is dispatched and **verified**, or FAILED with a reason.
3. **Payment.** You pay via the manual "give cats" action; the term goes VERIFIED from the money change, and the deal goes COMPLETE.
4. **Non-payment.** Don't pay; after 2 min the deal goes BREACHED_PLAYER and the NPC reacts.
5. **Counter → accept.** The NPC counters and you accept; the **same** deal moves to ACCEPTED.
6. **NPC can't pay.** Ask a broke NPC to pay you. You get IMPOSSIBLE with the reason, and the NPC doesn't claim it paid.

For each test, report the exact reply and whether the fight stopped. I'll read the deal row, the evidence and the logs.

---

## 6. Separate items (not Phase 1 server work)

- **F3, target switching mid-combat:** a client-side fix in `ChatBox.cpp` target resolution. Proposal: when the player doesn't name anyone, stay locked on the NPC you have an open negotiation with. That needs a STOBE DLL (v100) build, so it's a separate decision.
- **Track A follow-up:** the work planner, task goals, `EQUIP_ITEM` lookup and `stobe_goal_engine.inc` read item GameData at `+0x78` on real inventory items. The header says `+0x40`. This may quietly break item counting, trading and equipping by name, and Phase 1's inventory evidence depends on correct item data.

## 7. Phase 2 preview (not planned in detail until Phase 1 is signed off)

- A durable truce:
  - watch each hostile NPC for ≥ 30 s after STOP_ATTACK;
  - find out whether vanilla AI picks the target again;
  - prototype a limited hostility exception, which probably needs native work in KenshiFP or STOBE;
  - otherwise use a clearly limited fallback.
- Test each squad member separately.
