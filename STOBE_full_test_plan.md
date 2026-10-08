# STOBE: open issues and tests left

Last updated 2026-10-06 (doc cleanup: 96/97 and the built + confirmed B 55 spec removed, trace in `archive/test-run-2026-10-05-m41.md`; older run logs are in git history). Installed builds and run status: `MASTER_TEST_PLAN.md` section 0 and `testing/HANDOFF.md`. `NEG_CATS_PURSE_MODES` is on.
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **146**. Items 135-145 = Shay's play session 2026-10-07 (logs `C:\KenshiTestRuns\logs\20261007-shay-play\`, dialogue export `dialogue.txt` there); the FP half is `components/KenshiFP/docs/COMBAT_TEST_PLAN.md` "Gate 6".

**How to report:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## D. Bugs fixed or open, not yet confirmed in game

Fixed and confirmed items are deleted (run log line). Full history of each row below: `git log -p STOBE_full_test_plan.md`. Where each is confirmed: `MASTER_TEST_PLAN.md` section 3.

| # | Bug | Fix / state |
|---|---|---|
| 141 | Spar truce: after the agreed stop (STOP_FIGHT ok x6, 20:30-20:41) Avarek still showed the red "attacking" icon, so right-click heal was impossible; she swung again at 20:33; she was out of the squad after the spar and didn't rejoin when asked. Want: an agreed stop ends hostility natively (icon, AI target), a squad member who spars stays/returns to the squad. | fixed in c0ed0d9 (Stobe 8AF6F9B5 (KenshiModding c0ed0d9/9d19bfc)), awaiting in-game confirmation: a member who left the squad for ATTACK@<mate> rejoins on STOP_ATTACK/STOP_FIGHT (`spar rejoin` log); STOBE-144 row 141 |
| 143 | LLM too literal: in two good backstory replies Avarek ended with the bread request ("...making bread demands of strangers", "...whether a stranger bakes him bread?"). Want: prompt rule so an old request isn't dragged into unrelated talk. | fixed in StobeServer 331f845 (ended-goal prompt rule), awaiting in-game confirmation (live-model check, no wrapper row) |
| 145 | Log finding (not reported): 100+ `STT_RESULT: rejected reason=Hold push-to-talk longer` in Shay's session + 3 "Speech transcription failed" (pre-fix build, B056BDF0 not installed). Check the PTT key isn't firing on a normal key. | fixed in 9d19bfc (Stobe 8AF6F9B5 (KenshiModding c0ed0d9/9d19bfc)), awaiting in-game confirmation: PTT key ignored while a text field has focus (cause: V typed in the chat box, ~70 ms taps) |

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
