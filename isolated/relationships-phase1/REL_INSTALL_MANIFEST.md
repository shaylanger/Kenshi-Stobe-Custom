# REL install manifest (2026-10-03, after run m16)

What is merged and installed where. No rollback recipe (Shay's decision).

## Server (StobeServer)

- **Live tree:** `/var/www/html/StobeServer`, branch `integrate-custom` = `origin/stobe`. Merge copy:
  `/root/stobe-work/ss-merge`.
- **REL history on `stobe`:** 29 REL commits, from `dcb066b` (phase 1 framework, 2026-10-02) to `79b368b`
  (Testing-Save-Enslaved scenarios). Phase commits:
  - `59e8efa` phase 1;
  - `9214617` phase 2 combat;
  - `aa40554` phase 3 unconscious;
  - `7154f5a`/`4724817` phase 4 care;
  - `3cd48b5` phase 5 property/economy/agreements;
  - `307b011` phases 6-7 witnesses/dialogue/recruitment/escape;
  - `8da1a73` phase 8 (retention, perf bench, release notes);
  - fixes after the in-game runs: `5cd104e`, `1ca847c`, `7f57911`, `9332e49`/`796019b`, `68fec51` (storage_alias),
    plus scenario and state commits.
- **Not yet merged:** `feature/social-phase1` (pushed) is three commits ahead of `stobe`, all test files and states:
  - `941c7b2` REL-p3-05b SR07 fallback;
  - `ceef2eb` SR28/SR29 states;
  - `8ca2a49` theft probe scenarios.

  The final report and manifest are workspace files, not server commits.
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
- **Patches:** all in `C:\KenshiModding\pending-fixes\` and all applied to `/root/STOBE-src`:
  - rel-native-phase1..5;
  - p67, m4-fix, m4b, m5, m8, m9, m11, m13;
  - **m16, m16b, m16c** (the last three: storage_alias, sweep handle change, freed on chains off).
- **Installed:** `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` **EF62563B**. It contains every REL patch
  plus STOBE items 92, 96 and 97. Any later build from `/root/STOBE-src` keeps them.
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
