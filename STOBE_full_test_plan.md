# STOBE: open issues and tests left

Last updated 2026-10-04 (m23 reconciliation of m22 batch D; m21 reconciliation; m19: pruned 53 fixed + confirmed rows, see `archive/test-run-2026-10-03-m19.md`). Installed builds and run status: `MASTER_TEST_PLAN.md` section 0 and `testing/HANDOFF.md`. `NEG_CATS_PURSE_MODES` is on.
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **125**. Work resumed m22; run log archive/test-run-2026-10-03-m22.md.

**How to report:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## B. Needs a specific game state or situation (automatable once it exists)

| # | Situation | Expect |
|---|---|---|

## C. Open reproduction and regression checks

| # | What would show it | Expect | Tried |
|---|---|---|---|
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
| 101 | `[]` extended_data broke relationship writes | fixed live (3e50770), rows repaired |
| 105 | KenshiFP log spam (30k `WORK_GOAL input ratio` lines) | fixed (KenshiFP 5719BEA5+) |
| 124 | server background processor started by stobe-tests with the test DB (STOBE_DB_NAME=stobe_test) holds the live lock + port 12346: live ticks stale for hours, recovery fails ("already running"); batch O REL rows ran during the stall | fixed 27d411e (live-DB guard in start + start.sh, stobe-tests off switch, owner stamp, listener drops lock fd; regression background_processor_guard_regression.php); confirm: after the stray is gone, live ticks advance during a batch |

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
