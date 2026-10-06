# REL (stateful relationships): architecture, settings, operations

How the relationship system is built and run (live since m18, 2026-10-03). Design and open SR rows:
`RELATIONSHIP_SYSTEM_DESIGN.md`; per-row results: `REL_FINAL_REPORT.md`. No rollback recipe (Shay's decision).

## Server (StobeServer)

- **History on `stobe`:** phase commits `59e8efa` (1), `9214617` (2 combat), `aa40554` (3 unconscious),
  `7154f5a`/`4724817` (4 care), `3cd48b5` (5 property/economy/agreements), `307b011` (6-7 witnesses/dialogue/
  recruitment/escape), `8da1a73` (8 retention/perf). The old `feature/social-phase1` branch only added test files.
- **Code:**
  - `lib/social_{agreements,care,dialogue,event_contract,identity,interpreter,perception,property,recruitment,rules,runtime,store}.php`;
  - endpoint `social_event.php`;
  - tool `tools/social_relationship_inspect.php`;
  - data `data/social_relationship_rules.json` (version `phase8-v1`) and `data/social_relationship_schema.sql`.
- **Hooks in shared files:**
  - `lib/chat_helper_functions.php`: recruitment gate on JoinParty, dialogue guard;
  - `lib/negotiation_engine.php`: deal outcomes go to `social_agreements` (`stobeNegApplyConsequences`);
  - `lib/relationship_manager.php`: one locked writer, R4 exclusion while enabled;
  - playthrough policy 5 / API 9: the social tables follow the loaded save.
- **Tests:**
  - `tests/run_social_phase1.py` (runner) and `tests/social_*` (suites);
  - `tests/social_relationship/` (scenarios.json, mutation proof, in-game scenarios + RUN_ORDER.md,
    rel-surrender.sh, rel-enslaved.sh);
  - the 8 social suites are also in `stobe-tests` (own DB `stobe_social_phase1_test`).

## Database (live DB `stobe`)

- **Tables:**
  - `social_event_inbox`: raw facts, idempotent by event id;
  - `social_incident`: encounters, KOs, carries, deals, escapes;
  - `social_belief`: what each observer believes;
  - `social_effect`: the ledger, shadow and applied;
  - `social_evidence`;
  - `social_checkpoint`: rollback per game time.
- **Migration:**
  - `debug/db_updates.php` runs `data/social_relationship_schema.sql` (`CREATE TABLE IF NOT EXISTS`).
  - It registers the six tables in `database_versioning` at version **202610020001**.
  - Playthrough API 9 reinstalls its SQL functions on first use.
- **Retention:** raw facts, checkpoints and finished incidents older than 3 game days are pruned automatically every
  2000 facts (also `inspect --retention`). The ledger, beliefs and latent incidents are never pruned.
- **Relationship values themselves:** in the existing `core_npc_master.extended_data.relationships`. Only `enabled`
  mode writes there. Relationships follow the loaded save (`NEVER_CLEAR_RELATIONSHIP_DATA=false`).

## Native (Stobe.dll)

- **Source:** `/root/STOBE-src`, snapshot in `Kenshi-Stobe-Custom/components/STOBE`.
  - REL files: `src/SocialEventProtocol.{h,cpp}` (in `Stobe.vcxproj` and `CMakeLists.txt`).
  - REL code in `src/main.cpp` (`SocialEntityFor`, emitters, world sweep, witnesses, slavery/freed, carry/placed,
    aid, meals, trade) and `src/Utils.cpp` (Capture flag, sequence, `SocialPostStructured`).
- Every REL native patch is in `/root/STOBE-src` (the patch scripts were removed 2026-10-06; `git log` in this repo).
- **Native tests:** `tests/cpp/social_protocol_tests.cpp` (portable build, includes the storage_alias check).

## Settings

| Setting | Where | Values | Default (code) | Release recommendation | Now on this PC |
|---|---|---|---|---|---|
| Native capture | `RE_Kenshi\mods\Stobe\StobeCustom.ini` `[SocialRelationships] Capture` (read at game start) | 0 / 1 | 0 | **1** | 1 |
| Mode | `general_settings.SOCIAL_RELATIONSHIP_MODE` | off / shadow / enabled | off | **shadow** until Shay's balance review, then enabled | shadow |
| Categories | `general_settings.SOCIAL_CATEGORY_{COMBAT,AID,CARRY,SLAVERY,PROPERTY,ECONOMY,AGREEMENTS,DIALOGUE,WITNESS,RECRUITMENT}` | `false` turns one off | on | all on | unset (on) |
| Recruitment override | `general_settings.SOCIAL_RECRUITMENT_OVERRIDE` | true lifts the gate | unset | unset | unset |
| R4 fights count (item 55) | `RELATIONSHIP_FIGHTS_COUNT` | used while REL is not `enabled` | unchanged | unchanged | unset |
| Rules | `data/social_relationship_rules.json` | ranges, thresholds, retention | `phase8-v1` | `phase8-v1` | `phase8-v1` |

Mode switch: `php tools/social_relationship_inspect.php --set-mode off|shadow|enabled` (prints the previous value).

## Verify an install

1. `php tools/social_relationship_inspect.php`: shows `mode` and `session` (Playthrough Saves off: campaign
   `legacy`), and the counts grow during play.
2. `stobe.log` at game start: `SOCIAL_CAPTURE: enabled (StobeCustom.ini [SocialRelationships] Capture=1)`.
3. In shadow: `--check-shadow` exits 0.

## Where the logic lives
- Server: `lib/social_event_contract.php` (validation), `social_store.php` (ingest/apply/pending/checkpoint/rollback),
  `social_interpreter.php` (combat, KO/theft/enslavement), `social_identity.php` (storage_id + name binding, storage_alias
  for re-squadded characters), `social_rules.php` + `data/social_relationship_rules.json`, `social_care.php`
  (aid/carry/food), `social_property.php` (theft/gift/trade), `social_agreements.php` (deal outcomes, hooked from
  `stobeNegApplyConsequences`).
- Native: `SocialEventProtocol.{h,cpp}` (envelopes), `Utils.cpp` (capture flag, shared sequence, `SocialPostStructured`),
  `main.cpp` (`SocialEntityFor`, `SocialEmitHarm`, emitters in attackingYou, major damage, KO, recovered, limb, death,
  slavery, transfer aggregation).
- Offline runner: `tests/run_social_phase1.py` (needs `/tmp/negtest`, created by the runner). Regression events must be
  in game-time order (later ts) or they count as "late".

## Operating rules
- Never purge the live social tables during a test batch (an m9 purge broke a running m10 batch).
- Judge in-game runs from `C:\KenshiTestRuns\<run>\rel\*.inspect.txt` and the archived stobe.log, not the live tables
  (fixture reloads prune them).
- The offline runner and `stobe-tests` must not run at the same time (they share the test DB `stobe_social_phase1_test`).
  If inserts hit duplicate keys there, reset `core_npc_id_seq` with `setval` (test DB only).
