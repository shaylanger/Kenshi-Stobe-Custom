# STOBE: open issues and tests left

Last updated 2026-10-03 (m19: pruned 53 fixed + confirmed rows, see `archive/test-run-2026-10-03-m19.md`). Installed builds and run status: `MASTER_TEST_PLAN.md` section 0 and `testing/HANDOFF.md`. `NEG_CATS_PURSE_MODES` is on.
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **121**.

**How to report:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## A. Needs Shay (eyes, hands or first-person mode)

| # | What to do | Expect |
|---|---|---|
| 12 | "Senlin, what if I bandage you up and you give me your rags?"; after she hands over first: "I'm not going to heal you" (automated as `STOBE-A11-A12-heal-deal.sh a12`; by design she counters with a promise instead of handing over first) | You broke the deal; she doesn't say "we're square" |

## B. Needs a specific game state or situation (automatable once it exists)

| # | Situation | Expect |
|---|---|---|
| 15 | A goal needing something only a trader has | WAITING_APPROVAL; approve → buys; decline → cancelled |
| 16 | A goal needing a crafted ingredient at a bench | The bench queue grows only by what's missing |
| 18 | Betrayal: a dishonest NPC who dislikes you, a deal with payment first. Automatable since StobeServer `96b2c91`: test switch `NEG_TEST_FORCE_BETRAYAL` (general_settings, off by default) + `tests/ingame/stobe/STOBE-18-forced-betrayal.sh` (sets it on, and off on exit) | They attack after you pay; BREACHED_NPC, marked intentional (rare by design); plan reason `test_switch`; reputation npc_broken +1; memory "went back on our deal" |
| 20 | Refuse to pay after she's handed something over (fight setup) | She may threaten or attack; paying then stops it and the stop holds. Tried run 12: spawned raiders always want Cats first ("You pay first, then we talk about the bow"), 2 tries; needs Malzin's force-attack setup or a trader |
| 21 (was 42) | Fight setup, Fond trust, she stops for pay-later; don't pay for 1+ game minute | BREACHED_PLAYER, an angry line that matches her attack (no "cats received"), log `breach_react`. Tried run 12: a raider at Fond 60 refused pay-later 3 times ("After is where men die"). The unit check "unpaid -> BREACHED_PLAYER" is stale: hostile deals expire on game time, the test only backdates wall time |
| 22 (was 43) | Fight setup with `help`; she stops for pay | Her words don't say her gang "isn't hers to call off"; the gang stands down. Run 12 (gang of 3 raiders, paid 1000): words fine ("You're paying the whole gang"), deal COMPLETE, no fighting after; but the gang stood down only because gang-mate Yarel's own surrender offer sent a faction STOP_ATTACK. The paid deal itself sends only an individual STOP_FIGHT for the payee |
| 55 | Fights and relationships (B 55, section E items 1-8): BUILT live StobeServer `1392155` (REL "fights" mode replaces R4, switch `SOCIAL_FIGHTS_LIVE`, `lib/social_fights.php`); native "recovered" vitals for the bleeding-out level in Stobe (m19 build) | `rel-b55.sh <outdir> [mode squad wild spar close treat fade chat bleed deal]` (auto-home kah copy, Capture=1): one VERDICT per block; `chat` may be INCONCLUSIVE when the evaluator proposes no gain; accidental squad hit needs harness `hit` (being built). Fade threshold set to 30 (spec said 28; wounded range is now -23..-30): confirm with Shay |

## C. Can't reproduce so far (fixed or built, never triggered in game)

| # | What would show it | Expect | Tried |
|---|---|---|---|
| 25 (was 128) | A surrender offer from a raider who gets **named** mid-fight | Server log `Directive follows the NPC's new name`; offer arrives | Spawned raiders are named before any offer (run 10). Run 12: no `Directive follows` line in ~10 fights |
| 26 (was 30) | She says "Fine…" but the ledger shows nothing | Log `NPC agreed in words but recorded no deal`; the next line records ACCEPT | Every clear offer got a proper decision (run 12 too) |
| 27 (was 37) | A COUNTER with no terms (log `invalid_terms_json`) | Next turn she's reminded and restates it with terms | Never happened (run 12: none in ~40 deal turns) |
| 28 (was 31) | "Take off X" during a deal | Recorded as UNEQUIP, not a hand-over | Tried run 12: Malzin refused both (iron hat for 50, sandals for 200), no terms |
| 29 (was 35) | She misquotes an amount in a longer reply | Only the wrong sentence is rewritten, not the whole reply | Run 12: 8 rewrites, all from the first number on (held-back streaming); 4 were false alarms, now item 51 |
| 30 (was 38) | A non-member's prompt | No "Shay \| squadmate" line | Never seen (run 12: 0 in all of today's prompts) |
| 31 | Counter-offers like "300 now, 200 after?" where she misquotes | Amounts rewritten; log `Negotiation speech amounts differ` | She never misquoted (run 12: "300 now, 200 after" countered with the same numbers) |
| 32 | A REJECT that names her own price ("2000 for the hat") | Recorded as COUNTER (fixed run 11, unit-tested) | The model chose COUNTER by itself in run 11; run 12 "5 cats" got a plain REJECT |
| 33 | Pay for something she can't do, and she agrees | Deal fails and your Cats come back | She always says she can't (refund itself works); run 12: "carry me to the Hub", "build a house now" both refused |
| 34 | One-on-one fight where a faction-mate joins uninvited | `PERSONAL_FIGHT: stood down joiner=…` within ~0.25 s | Nobody joined so far |
| 35 | She agrees to sell/stow her weapon without Fond trust | "Not my Chisa Katana…", log `NPC would give up her weapon` | She refuses on her own (run 12: 3000 and 5000 Cats, refused) |
| 36 | Haggle back and forth more than 6 times | She ends the talks | Run 10: accepted at round 2 (unit-tested). Run 12: 8 rounds with a raider, but every ACCEPT starts a new deal, so rounds never passed 2 |
| 37 | A neutral NPC losing a fight near Shay | They ask for help, maybe with a reward | Run 10: spawned victim wandered off |

| 44 | A Cats term recorded the wrong way round (her words/action say she pays) | Turned round: her GiveCats action, "you give me N", or the deal on the table (log `Negotiation term fixed`) | Run 12: the first two rules fixed it in game; the third ("350 and you go free") unit-tested only; the model keeps finding new wordings |
| 45 | An extra 0-Cats term in her terms | Dropped (log `0 Cats (item 45)`); deal recorded | Unit-tested |
| 47 | An action target by a shared name with a corpse of that name nearby | The living NPC is chosen (Stobe `526D69F1`) | Built; scenarios no longer leave corpses, so not re-seen |
| 49 | Pay an NPC who was named after the deal | Payment VERIFIED, and only for that NPC's deal (serial-pinned) | Part 1 seen in game (1000 Cats verified); part 2 (serial pin) unit-tested |
| 51 | She repeats your offer, then names hers | Her reply is kept, no "My terms:" rewrite | Unit-tested |
## D. Bugs fixed or open, not yet confirmed in game

Fixed and confirmed items are deleted (run log line). Full history of each row below: `git log -p STOBE_full_test_plan.md`. Where each is confirmed: `MASTER_TEST_PLAN.md` section 3.

| # | Bug | Fix / state |
|---|---|---|
| 70, 108 | template-name relationship keys (Dust Bandit Bowman, Berserker) came back via the save-follow restore / new fights | fixed live (197d921, 945dfe1: map reads/writes drop template keys, `data/npc_generic_templates.json`) |
| 86 | game re-reported `Initiated attack` during a truce, so a paid surrender turned BREACHED_PLAYER | fixed live (f98b88e, e9f8598: a breach needs real evidence within 8 s; older-save load cancels later deals) |
| 87 | Dust King: no initiative check (his attack was stood down by another personal-fight guard) | test procedure fixed; covered by 88 + 61 PASS m18 |
| 94 | `stobe-reset-npc --restore` wrote "shay" instead of "Shay" | fixed (tool) |
| 96 | surrender payment on accept missed by the payment check (3 s window) | fixed live (c5a8e25: 30 s window) |
| 97 | personal truce cancelled Shay's explicit attack order | fixed (Stobe: a player attack order ends the truce guard, deal BREACHED_PLAYER) |
| 99 | WAITING_APPROVAL never offered for a trader-only ingredient | fixed (KenshiFP: carried goods + nearest stocking trader) |
| 100 | other squads (Beaks/Avarek) addressed as the persona "Shay" | fixed live (97e0b9f); option (b) live (0c6ed3e): reputation/relationship history follow the speaking character |
| 101 | `[]` extended_data broke relationship writes | fixed live (3e50770), rows repaired |
| 102 | weapon-stow guard: outsider keeps her weapon below r +70 | built live (1c2457f); PASS m18 except `weapon69` |
| 103 | willingness lines (no trade <= -80, pay-later >= 0, favours >= +30, gifts >= +56) | built live; notrade + paylater PASS m19; favour/gift -> 120 |
| 104 | prices by relationship (buy -30 %…+1000 %, sell +10 %…-90 %, floor) | deal side live (cef19fe), shop hook Stobe CA758842 (shop-prices/floor/block PASS m19); deal prices -> 119 |
| 105 | KenshiFP log spam (30k `WORK_GOAL input ratio` lines) | fixed (KenshiFP 5719BEA5+) |
| 106 | wrong-side SPARE term rejected the whole deal | fixed live (terms repaired or dropped) |
| 107 | Full-Base pay-later deal never breached (fight check matched only the persona) | fixed live (6146805) |
| 110 | playthrough rollback "write failed" + unlocked concurrent rollbacks | fixed live (e605768, 538bf00) |
| 111 | "buy from the shop here" -> MOVE_TO only | fixed (server 6fd2406 + KenshiFP unnamed trader search) |
| 118 | spoken "one cat, take it or leave it" paid before any agreement | fixed live (fda6a7f) |
| 119 | higher counters ignored the relationship price | fixed live (3bbbd87) |
| 120 | free favour agreed below +30 without deal terms; no real heal | fixed live (9aadccc) |

## E. Design questions and features

- **BUILT (StobeServer 1392155, m19) -> test row B 55. Fights and relationships, B 55 (Shay's decisions, 2026-10-03):** retire R4 (flat -10/-4 per 15 min) and use the REL combat rules (severity-scaled per incident: aggression -8..-15, injury -15..-28, KO -25..-40, near death -35..-55, maiming -45..-70, accidental friendly fire 0..-3, self-defence 0, enslavement -65..-90; attacker's own feeling unchanged; one escalating budget per fight; witnesses scaled by their bond with the victim). On top:
  1. **Forgiveness over time:** small grudges fade back to 0 (neutral). **Threshold (Shay confirmed 2026-10-03: event-based only, no relationship-value cutoff; a setting with this default):** each fight is its own grudge record; whether it fades is decided by **what happened, not by the number** (Shay 2026-10-03): "not really hurt" and "wounded but standing" fade by themselves, linearly over ~14 game days, whatever the closeness multiplier made the penalty (base band up to -30, so the setting's number is 30, not 28). Knockout or worse (KO, near death, maiming, imprisonment, enslavement, a broken deal) never fades by itself; only positive actions repair it.
  2. **Deals:** a kept surrender/paid deal wins back a variable 0 to 1/3 of that fight's penalty: 1/3 x how fully the deal was kept x the NPC's forgiveness (a forgiving/easygoing personality toward 1, proud/vengeful toward 0). A broken deal adds a betrayal penalty on top.
  3. **Sparring:** a fight both sides agreed to costs nothing unless someone is maimed or killed.
  4. **No instant make-up:** for 1 game day after a real fight, chat can't raise the victim's opinion of the attacker.
  5. **Only fights that matter count:** a squad member is involved, or a named NPC is present and conscious; distant wild fights are ignored.
  6. **The first fight leaves a mark:** a permanent memory fact ("fought me at <place/time>") stays even after the value recovers. While a fight grudge is open, positive gains toward that person count at half rate; once it's back to 0, normal gains apply, so time + effort can turn it into friendship.
  7. **Harsher penalties + closeness scaling (Shay approved 2026-10-03; replaces the REL base ranges for fights):** severity = the victim's state when the fight ends / when she wakes (no hitting someone who is down in Kenshi). Base penalties: not really hurt -10..-15; wounded but standing -23..-30; knocked out with moderate wounds -40..-50; knocked out and wakes up with severe wounds, bleeding out -55..-65; loses a limb -68..-78. Multiplied by the victim's feeling for the attacker **before** the fight: Neutral or worse 1.0x, Friendly 1.3x, Fond 2.0x, Devoted 2.5x, Bonded 3.0x; floor -100. Examples: Fond +60 KO moderate -> -20..-40, bleeding out -> -50..-70, limb -> -76..-96; Bonded +95 limb -> -100; stranger KO -> -40..-50. Broken deal/truce adds -20..-40; accident 0.25x; self-defence 0 (defensive maiming -8..-20).
  8. **Helping afterwards (Shay approved):** if the attacker treats her wounds (bandage/first aid) after the fight, the fight penalty is reduced by a **variable 15-30 %** (not flat: higher the sooner the help came, plus seeded variation per incident so reload can't reroll). She's still angry, but understands it wasn't meant (e.g. light fight, accidental limb loss, bandaged at once). Healing never earns positive trust toward the attacker for that incident (SR17).

## F. Next big things

| # | What | Notes |
|---|---|---|
| 62 | Decouple our logic from KenshiFP | We started by tacking our features onto KenshiFP, and a lot now lives there that shouldn't (e.g. work planner `client/stobe_work_planner.inc`, task goals `client/stobe_task_goals.inc` + goal panel, GIVE_ITEM/BODYGUARD handling). Goal: KenshiFP holds only FP-mode logic; the rest moves into Stobe or a new mod, whichever fits each piece |
| 63 | Pick the next big feature | Go through the big features list (`KENSHI_BIG_MOD_IDEAS_CONTEXT.md`, `PROFESSION_GEAR_PROGRESSION_MOD_CONTEXT.md`) and start on the next big item |

---

## Switches
Relationships: `RELATIONSHIP_STANCE` (how she talks by relationship, on), `RELATIONSHIP_FIGHTS_COUNT` (R4, retired by B 55: off while `SOCIAL_FIGHTS_LIVE` is on), `SOCIAL_FIGHTS_LIVE` (B 55 fights mode, on), `SOCIAL_FIGHT_RULES` (b55|rel), `SOCIAL_GRUDGE_FADE_DAYS` (14), `SOCIAL_GRUDGE_FADE_THRESHOLD` (30), `NEVER_CLEAR_RELATIONSHIP_DATA` (false = relationships follow the loaded save).
Deals: `NEG_CATS_PURSE_MODES` (cap tiers: send GIVE_CATS `@topup`/`@exact` to Stobe.dll; needs Stobe `FF633947`+; on since 2026-10-02).
If a phase misbehaves: `… phase <2-8> off`. Voice payment: `NEGOTIATION_VOICE_PAYMENT`. Trust for free gifts: `GIFT_TRUST_THRESHOLD` (56 = Fond). Trust to give up her own weapon: `NEG_WEAPON_TRUST_MIN` (56). Trust for minor orders from non-faction NPCs: `MINOR_ORDER_TRUST_MIN`. STOBE ini: `Speed Dialogue` (0 = TTS at 1x), `TTSVolume` (0–200), `TTSFadePercent` (25–400).
