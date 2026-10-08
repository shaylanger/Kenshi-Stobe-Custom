# STOBE: open issues and tests left

Last updated 2026-10-06 (doc cleanup: 96/97 and the built + confirmed B 55 spec removed, trace in `archive/test-run-2026-10-05-m41.md`; older run logs are in git history). Installed builds and run status: `MASTER_TEST_PLAN.md` section 0 and `testing/HANDOFF.md`. `NEG_CATS_PURSE_MODES` is on.
This list holds **only** open items. Everything fixed and confirmed is gone (history: `archive/STOBE_bug_history_old_numbers.md`, run logs `archive/test-run-*.md`).

**Numbering restarted on 2026-10-02:** items are numbered 1, 2, 3… here. "was N" is the old bug number (still used in commit messages and code comments). The next new item is **146**. Items 135-145 = Shay's play session 2026-10-07 (logs `C:\KenshiTestRuns\logs\20261007-shay-play\`, dialogue export `dialogue.txt` there); the FP half is `components/KenshiFP/docs/COMBAT_TEST_PLAN.md` "Gate 6".

**How to report:** tell me roughly when (your clock) and which NPC, e.g. "Malzin around 11:02, she didn't take the vest off". Send it **before relaunching Kenshi** (logs reset on launch).

## D. Bugs fixed or open, not yet confirmed in game

Fixed and confirmed items are deleted (run log line). Full history of each row below: `git log -p STOBE_full_test_plan.md`. Where each is confirmed: `MASTER_TEST_PLAN.md` section 3.

| # | Bug | Fix / state |
|---|---|---|
| 135 | NPC panel shows the wrong person in the squad: Shay selected himself + `\` -> Malzin's card; selected Malzin -> his own card. Log: panel target = the *other* squad member (`target=Shay speaker=Malzin` while Malzin was selected). Want: card for the selected character, seen by the controlled one. | open (Stobe) |
| 136 | FP mode: chat to a squad mate comes from the *selected* character, not the FP-controlled one (Shay 2026-10-07). Want: speaker = controlled character always in FP. | open (Stobe + KenshiFP export) |
| 137 | Full-Base, Beaks -> Avarek "make me 1 bread": she talked about the campfire, said "input's blocked, no grain" and emitted no action twice (19:55, 19:57); only after Shay spelled out silo -> flour -> oven did she emit `WORK_GOAL@Campfire@Bread@1` (20:01). Wheat farm, silo, oven, well all present. Want: the model knows the real chain/benches for the item; a plain "make N X" gets a goal; bench name corrected server-side. | open (server) |
| 138 | Resume after interrupt: goal wg-7d14 was running; "resume your task" -> `TASK_CONTROL@RESUME@Bread@1@Campfire` -> "I could not find a matching goal to change." (20:08); "get to work" x3 -> new WORK_GOALs accepted (wg-b706/36cd/c9fb) that never ran while she said "I'm moving". Interrupt was a fight (20:11 LMB engage, see FP PT10). Want: interrupted goals resume by themselves after the fight/follow ends; "resume" always matches the live goal. | open (server + Stobe) |
| 139 | "Clear all your tasks, goals and jobs" -> `TASK_CONTROL@PAUSE@Bread@0` (not cancel); native jobs Operate Water Pump / Haul from water pump stayed; explicit cancel (20:17 `TASK_CONTROL@CANCEL@Bread@1`) still left wg-7d14 running (hauled water + re-added a Wheat Farm job at 20:26). Want: clear-all cancels every goal and removes the jobs the goals added (and her jobs if asked); cancel stops the live goal. | open (server + Stobe) |
| 140 | Goal panel tooltip/info sits where the outpost info panel is (`GOAL_PANEL created at 2073,969`): in your own outpost the goals are hidden. | open (Stobe) |
| 141 | Spar truce: after the agreed stop (STOP_FIGHT ok x6, 20:30-20:41) Avarek still showed the red "attacking" icon, so right-click heal was impossible; she swung again at 20:33; she was out of the squad after the spar and didn't rejoin when asked. Want: an agreed stop ends hostility natively (icon, AI target), a squad member who spars stays/returns to the squad. | open (Stobe + server) |
| 142 | Heal deal: kit given to Avarek (not in squad) 20:41, "patch me up" -> `FIRST_AID actor=Avarek target=Beaks result=ok` (20:43:40) but no healing happened. Want: FIRST_AID by a non-squad NPC really treats the target (or a guarded refusal); verify bandaging in game state. | open (Stobe) |
| 143 | LLM too literal: in two good backstory replies Avarek ended with the bread request ("...making bread demands of strangers", "...whether a stranger bakes him bread?"). Want: prompt rule so an old request isn't dragged into unrelated talk. | open (server prompt) |
| 144 | Interrupt/resume robustness (Shay): goal running, then follow me / attack X / defend me / spar / chat, then "resume" -> goal continues with the same id; also auto-resume. Multi-step compound tests, not one action. | test rows to build |
| 145 | Log finding (not reported): 100+ `STT_RESULT: rejected reason=Hold push-to-talk longer` in Shay's session + 3 "Speech transcription failed" (pre-fix build, B056BDF0 not installed). Check the PTT key isn't firing on a normal key. | open (Stobe) |

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
