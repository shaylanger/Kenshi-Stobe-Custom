# STOBE: open issues and tests left

Last updated 2026-10-06 (doc cleanup: 96/97 and the built + confirmed B 55 spec removed, trace in `archive/test-run-2026-10-05-m41.md`; older run logs are in git history). Installed builds and run status: `MASTER_TEST_PLAN.md` section 0 and `testing/HANDOFF.md`. `NEG_CATS_PURSE_MODES` is on.
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **135**.

**How to report:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## D. Bugs fixed or open, not yet confirmed in game

Fixed and confirmed items are deleted (run log line). Full history of each row below: `git log -p STOBE_full_test_plan.md`. Where each is confirmed: `MASTER_TEST_PLAN.md` section 3.

| # | Bug | Fix / state |
|---|---|---|
| 87 | Dust King: no initiative check (his attack was stood down by another personal-fight guard) | test procedure fixed; covered by 88 + 61 PASS m18 |

## E. Design questions and features

- **B 55 fight rules: built (StobeServer 1392155) and confirmed in game (m22, all blocks PASS).** The full spec (Shay,
  2026-10-03) is in git (`git show 6391c32 -- STOBE_full_test_plan.md`). Summary of the rules in force: severity by the
  victim's state when the fight ends/she wakes (not hurt -10..-15, wounded -23..-30, KO moderate -40..-50, KO severe/bleeding
  -55..-65, limb -68..-78) x closeness before the fight (Friendly 1.3, Fond 2.0, Devoted 2.5, Bonded 3.0; floor -100);
  grudges up to "wounded" fade over ~14 game days, KO or worse never fades by itself; kept deal wins back 0..1/3; consensual
  sparring free; no chat gains for 1 game day; only fights with the squad or a conscious named NPC count; the first fight
  leaves a permanent memory fact, gains at half rate while a grudge is open; broken deal/truce -20..-40, accident 0.25x,
  self-defence 0; treating her wounds afterwards takes off 15-30 % (never positive).

## F. Next big things

| # | What | Notes |
|---|---|---|
| 63 | Pick the next big feature | Go through the big features list (`KENSHI_BIG_MOD_IDEAS_CONTEXT.md`, `PROFESSION_GEAR_PROGRESSION_MOD_CONTEXT.md`) and start on the next big item |

---

## Switches
Relationships: `RELATIONSHIP_STANCE` (how she talks by relationship, on), `RELATIONSHIP_FIGHTS_COUNT` (R4, retired by B 55: off while `SOCIAL_FIGHTS_LIVE` is on), `SOCIAL_FIGHTS_LIVE` (B 55 fights mode, on), `SOCIAL_FIGHT_RULES` (b55|rel), `SOCIAL_GRUDGE_FADE_DAYS` (14), `SOCIAL_GRUDGE_FADE_THRESHOLD` (30), `NEVER_CLEAR_RELATIONSHIP_DATA` (false = relationships follow the loaded save).
Deals: `NEG_CATS_PURSE_MODES` (cap tiers: send GIVE_CATS `@topup`/`@exact` to Stobe.dll; needs Stobe `FF633947`+; on since 2026-10-02).
If a phase misbehaves: `… phase <2-8> off`. Voice payment: `NEGOTIATION_VOICE_PAYMENT`. Trust for free gifts: `GIFT_TRUST_THRESHOLD` (56 = Fond). Trust to give up her own weapon: `NEG_WEAPON_TRUST_MIN` (56). Trust for minor orders from non-faction NPCs: `MINOR_ORDER_TRUST_MIN`. STOBE ini: `Speed Dialogue` (0 = TTS at 1x), `TTSVolume` (0–200), `TTSFadePercent` (25–400).
