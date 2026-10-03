# Handoff: how fights should change relationships (STOBE) — context for a deep analysis

Written 2026-10-02 (end of run 12) for a separate session. Read `CLAUDE.md` first (workspace rules: server patches as anchor scripts in `pending-fixes/`, both server trees, one fix per commit, Shay also edits the server, check `git status`/`git log` in the live tree before patching).

## The question

Run 12 added a first, simple rule: **an attack lowers relationships**. Shay wants a deep analysis of whether that rule is right and what the real rule set should be. The rule as built:

> Every game event `A: Initiated attack (talking to: B)` lowers **B's feeling for A by 10** ("attacked me") and **A's feeling for B by 4** ("fought them"), **once per pair per 15 minutes**, for **named** characters only.

It was a quick fix for this case: Malzin fought the raider Vren; afterwards Vren said something friendly and the relationship evaluator gave **+6 "No hard feelings after the fight"**, so they became Acquaintances. The fight itself had never counted.

## How relationships work today (facts, verified 2026-10-02)

- **Storage:** per NPC, `core_npc.extended_data->'relationships'` (`core_npc_master` is a view over `core_npc`), plus a second copy in the text column `relationships`. Entry: `{target: {aff -100..100, tier, type, note, updated_at, custom_info?}}`. **One-directional**: Malzin→Shay and Shay→Malzin are separate entries. The player character has a row too (Shay), but no stance block is generated for her.
- **Tier** from aff (fixed): Hostile ≤−91, Hateful ≤−76, Resentful ≤−56, Cold ≤−31, Wary ≤−6, Neutral −5..+5, Acquaintance ≥+6, Friendly ≥+31, Fond ≥+56, Devoted ≥+76, Bonded ≥+91 (`stobeRelationshipTierLabel`, `stobeRelationshipStanceTier`).
- **Evaluator (the main source of changes):** `stobeEvaluateRelationshipsForTurn` in `lib/chat_helper_functions.php`. Runs after an NPC **speaks** (chat turns, bored/NPC↔NPC chatter), sees the incoming line + her reply + her current map, may return up to 3 updates (`aff_delta`, `type`, `note`), told "normal chat −8..+8". Gate: `stobeRelationshipTurnNeedsConnectorEvaluation` (salient event types `trade, healing, death, recruit, join, leave, combat_end, major_damage, limb_loss, knockout, slavery, …` or keywords; else a 1-in-4 of `RELATIONSHIP_UPDATE_CHANCE`). Model: OpenRouter `deepseek-v4-flash` (relationship connector). **It never sees "they were just fighting each other" unless the line says so.**
- **R4 (the rule under review):** `stobeRelationshipOnAttack()` in `lib/chat_helper_functions.php` (StobeServer `9839389`), called from `stobeNegTickThrottled()` in `lib/negotiation_engine.php` for event type `combat`. Throttle key `conf_opts` `STOBE_REL_FIGHT_<md5(attacker|victim)>`. Generic names skipped via `stobeIsGenericNpcName()` (R3: a plain name that named NPCs carry in brackets, e.g. "Hungry Bandit"). Writes via `stobeApplyRelationshipUpdatesMap` + `stobePersistNpcRelationshipMap` (which stamps a `relationship` history snapshot). Switch: `RELATIONSHIP_FIGHTS_COUNT` (default on). Patch script: `pending-fixes/patch_r25_rel_fights_count.py`. Unit tests: `tests/relationship_stance_regression.php` (R4 checks).
- **Stance (how she talks):** `stobeBuildRelationshipStanceBlock()` (StobeServer `f83a3fb`) puts `<how_you_feel_about_them>` in every chat prompt: tier → tone, type → flavour; outsiders at Hateful/Hostile may attack, squadmates never attack. So R4's numbers directly change how she talks.
- **Rollback:** relationships now follow the loaded save (StobeServer `78243b0`, `28dff99`; `NEVER_CLEAR_RELATIONSHIP_DATA=false`; baseline snapshots at game time 0 for 61 NPCs). Any rule here must write through `stobePersistNpcRelationshipMap` so a snapshot is stamped with the game time.

## Combat events available (eventlog `type` / `data`)

- `combat`: `A: Initiated attack (talking to: B)` and `A: Defending against (talking to: B)` — very frequent, also for wild fights anywhere in the loaded area (e.g. `Krevanix [Outlaw Watch Salome]: Initiated attack (talking to: Dust Bandit)`).
- `combat_start`: `Shay: entered active combat`.
- `combat_end`: `Shay: combat with Malzin ended after 60 seconds (outcome: disengaged; participants: 7; friendly side standing: 1; opponents standing: 6; knocked out: 0; dead: 0; fled: 0)`.
- `major_damage`: `Shay: took a major hit from Cind [Hungry Bandit] using Iron Stick` (and `took a major hit (health N%)`).
- `knockout`: `<X> -> None (Knocked out by an Iron Club from <Y>)`; `death`: `Sorth [Dust Bandit]: has died`; also `limb_loss`, `healing` (`Shay: is using (Basic First Aid Kit) to heal Senlin`).
- Game-side source: Stobe.dll `[EVENT]` lines in `RE_Kenshi\mods\Stobe\stobe.log`; server: `log/stobeserver.log` "Game event received".

## Systems that interact (each needs a decision)

- **Deals / truces** (`lib/negotiation_engine.php`, `negotiation_phase1.php`): surrender, ransom, pay-for-ceasefire, betrayal (BREACHED_NPC/PLAYER), reputation. A fight that ends in a kept deal, or a betrayal, may matter more than the fight itself.
- **Personal fights / test fights:** `stobe-force-attack <npc> [help]` (breach_react directive), Stobe.dll personal-fight guard, `PERSONAL_FIGHT: stood down joiner=…`. Sparring or a staged duel probably shouldn't make Malzin hate Shay.
- **Squad:** Malzin is in Shay's squad (faction Nameless). Friendly fire, an accidental hit, or Shay attacking her own squadmate.
- **Defending vs initiating:** R4 only reacts to `Initiated attack`. A defender is not penalised; but "B defended against A" also means A attacked B.
- **Bodyguard / helping:** Malzin defending Shay against a raider should *raise* Shay→… and Malzin's bond with Shay (saved my life), not only lower Malzin↔raider.
- **Severity:** knockout, limb loss, near death, killing a friend/companion, enslaving, imprisonment vs. a single swing. Healing / rescuing after a fight.
- **Faction and witnesses:** attacking someone's faction-mates, people who watched.
- **Generic names:** unnamed NPCs are skipped (R3). Many fights are against unnamed raiders until they get named.
- **Throttle / volume:** wild fights generate many events; each R4 call does a conf lookup and up to two NPC reads/writes.

## Known open points about R4 as built

1. Fixed numbers (−10/−4) regardless of what happened; no recovery over time; no positive effects (defended me, healed me after).
2. Fires for **any** named pair, including fights the player never saw (wild Outlaws vs bandits).
3. No distinction between enemies at war (raider vs samurai) and friends/squadmates.
4. Repeated fights are throttled to one hit per 15 min per direction, so a long brawl counts once.
5. Runs before/independently of the evaluator; the evaluator can still add +6 on a friendly line right after.
6. No unit test for the hook path (only for the function); no in-game test yet (plan B 55).

## Real data to look at

- Malzin's map today (`SELECT jsonb_pretty(extended_data->'relationships') FROM core_npc_master WHERE name='Malzin'`): 14 entries, all from run 11/12 test fights, e.g. Boss Madoc −6 Wary (rival) "threatens Boss Madoc after a hit", Ulan [Dust Bandit] −11 Wary (rival) "taunted about crew's defeat", Vren [Dust Bandit] +6 Acquaintance "No hard feelings after the fight"; Malzin → Shay 96 Bonded (restored).
- Prompts sent to the LLM: `log/context_sent_to_llm.log` (relationship evaluator calls have `'event_type' => 'relationship_eval'`), archives in `log/archive/*/` (only the last 3 kept).
- Run logs: `archive/test-run-2026-10-02-r12.md`; plan: `STOBE_full_test_plan.md` section E ("How are relationships created…") and B 54–58.
- Relationship system docs/code: `ext/relationship_system/README.md`, `relationship_llm.php` (analysis/evaluation prompts; DB copies in table `prompts`, keys `rel_llm_*`), `lib/relationship_manager.php`.

## What the analysis should produce

A proposed rule set (which events, for which pairs, how much, positive and negative, decay/forgiveness, exceptions for deals, sparring and squadmates), the data/hooks each rule needs, risks (volume, false positives, rollback interplay), and a test plan (unit + in-game rows for `STOBE_full_test_plan.md`). Changing R4 itself is out of scope until Shay picks a design.
