# STOBE: open issues and tests left

Last updated 2026-10-06 (doc cleanup: 96/97 and the built + confirmed B 55 spec removed, trace in `archive/test-run-2026-10-05-m41.md`; older run logs are in git history). Installed builds and run status: `MASTER_TEST_PLAN.md` section 0 and `testing/HANDOFF.md`. `NEG_CATS_PURSE_MODES` is on.
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **135**.

**How to report:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## D. Bugs fixed or open, not yet confirmed in game

Fixed and confirmed items are deleted (run log line). Full history of each row below: `git log -p STOBE_full_test_plan.md`. Where each is confirmed: `MASTER_TEST_PLAN.md` section 3.

| # | Bug | Fix / state |
|---|---|---|
| 70, 108 | template-name relationship keys (Dust Bandit Bowman, Berserker) came back via the save-follow restore / new fights | fixed live (197d921, 945dfe1: map reads/writes drop template keys, `data/npc_generic_templates.json`) |
| 86 | game re-reported `Initiated attack` during a truce, so a paid surrender turned BREACHED_PLAYER | fixed live (f98b88e, e9f8598: a breach needs real evidence within 8 s; older-save load cancels later deals) |
| 87 | Dust King: no initiative check (his attack was stood down by another personal-fight guard) | test procedure fixed; covered by 88 + 61 PASS m18 |
| 94 | `stobe-reset-npc --restore` wrote "shay" instead of "Shay" | fixed (tool) |
| 99 | WAITING_APPROVAL never offered for a trader-only ingredient | fixed (goal code, in Stobe.dll since m49: carried goods + nearest stocking trader) |
| 101 | `[]` extended_data broke relationship writes | fixed live (3e50770), rows repaired |
| 105 | KenshiFP log spam (30k `WORK_GOAL input ratio` lines) | fixed (KenshiFP 5719BEA5+) |

### Drawn-weapon reactions (built: Stobe fc1ead3 / DLL F23B4432 not installed yet, StobeServer 055e0c5; never run in game)

Wrapper `tests/ingame/stobe/STOBE-DRAWN.sh [DW1 .. DW10]` on a Crafting base kah-* copy (Shay + Malzin, Hub). Native state via harness `stobe_drawn status|pair|draw|hold|set|reset`, stobe.log `DRAWN_WEAPON:` lines; replies injected with NEG_TEST_INJECT context `react` (DW1 DW2 DW9).

| # | Row | Pass when |
|---|---|---|
| 125 | DW1 neutral NPC who sees a drawn weapon within 10 m speaks | `speak_friendly ... speech=sent`, `REACTION_TURN: dispatched react=drawn_weapon`, server `Drawn weapon reaction turn`, eventlog infoaction "... with a drawn ...", injected line said |
| 126 | DW2 guard (name/task heuristic) tells him to put it away | `speak_guard kind=guard`, no friendly line, injected line said |
| 127 | DW3 hostile: warn, weapon kept out in range -> native attack after WarnSeconds | `warn` then `attack order=1` >= warn s later, `attack_confirmed` or `pair` attack_target=player |
| 128 | DW4 holstering after the warning cancels | `cancel_holstered`, no attack after the warn time |
| 129 | DW5 closing in inside AttackDistance after the warning attacks at once | `attack order=1` well before the (30 s) warn time |
| 130 | DW6 NPC who can't see the player (faces away) doesn't react | no DRAWN_WEAPON line / sees=0; control: turned back he speaks |
| 131 | DW7 own squad (Malzin) never reacts | no line, `pair` no_pair while a neutral NPC reacts |
| 132 | DW8 no reaction during combat | a warned NPC who starts fighting gets `cancel_combat`, no attack order, no further line |
| 133 | DW9 per-NPC cooldown | redraw inside the cooldown: no second line; short cooldown: second line |
| 134 | DW10 live model (no injection) | the line is about the weapon; speech only (attack_target=none, no deal) |

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
