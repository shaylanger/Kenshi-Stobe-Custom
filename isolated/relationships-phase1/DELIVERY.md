# REL (stateful relationships) deliveries to the coordinator

Owner: REL builder. Newest section last. Each section is self-contained: what to merge, what to
apply/build, settings, scenario files, expected results. Nothing here is installed or deployed by REL.

## 2026-10-03 Delivery 1: Phase 1 framework + in-game smoke gate

### Server
- Merge **`feature/social-phase1` at `03b188e`** (github shaylanger/StobeServer, branch `feature/social-phase1`)
  into the live tree (`/var/www/html/StobeServer`, branch `stobe`) and ss-merge. It is based on
  live HEAD `5f71138` (fast-forward; no conflicts).
- After the merge: run the DB updates as for any deploy (`php debug/run_db_updates.php`): adds the six
  `social_*` tables (version 202610020001), playthrough table policy 5 (social tables are per save;
  older snapshots load them empty) and playthrough API version 9 (functions reinstall themselves).
  Then `stobe-rotate-logs`.
- Inert by default: `SOCIAL_RELATIONSHIP_MODE` unset = `off`: `social_event.php` answers
  `{"status":"disabled"}` and writes nothing; R4 (`RELATIONSHIP_FIGHTS_COUNT`, item 55) unchanged;
  the playthrough rollback skips the social step while the social tables are empty.
- Behaviour change also in `off` (writer consolidation, low risk): `RelationshipManager::setRelationship`
  now writes through `stobePersistNpcRelationshipMap` (both the `relationships` column and
  `extended_data.relationships`, normalised). No caller in the server uses it today.
  With mode `shadow`/`enabled` every relationship map write takes a row lock and merges deltas
  against the stored row (protects parallel dialogue/worker writers).

### Native
- Patch: `C:\KenshiModding\pending-fixes\rel-native-phase1.patch` (git diff relative to the
  STOBE source root). Verified: `rsync -a /root/STOBE-src/ /tmp/rel-verify/ && cd /tmp/rel-verify &&
  git apply --check <patch> && git apply <patch>` applies cleanly to the current working tree.
- Adds `src/SocialEventProtocol.{h,cpp}` (portable envelope serializer), `PlaythroughSession::ClientId()`,
  the opt-in capture in `LogGameEvent` (posts a JSON envelope to `/StobeServer/social_event.php`),
  `[SocialRelationships] Capture=0` in `mod/Stobe.ini`, a portable test, and log lines
  `SOCIAL_CAPTURE: enabled ...` / `SOCIAL_CAPTURE: queued kind=<k> seq=<n> load=<id> actor=#<s> target=#<s>`.
- **Build step:** add `SocialEventProtocol` to `SOURCES` in `C:\StobeBuild\build_portable.bat`
  (the patch updates `CMakeLists.txt`/`Stobe.vcxproj`, not that bat file).
- Private proof build (from the patched copy, not installed):
  `C:\KenshiModding\isolated\relationships-phase1\build\out\Stobe.dll`
  SHA256 `c2ae4c70a0c33df57783327ab07497acbdc3d1788ef4128541dde007a2426897`. Your own build will hash
  differently (timestamps); build it with `build-stobe.ps1` after applying the patch.
- Inert by default: Capture=0 means no extra posts or log lines.

### Settings
| Switch | Where | On | Off/restore |
|---|---|---|---|
| Native capture | `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\StobeCustom.ini` `[SocialRelationships]` `Capture` | `Capture=1` before launch (read at game start) | `Capture=0`, relaunch |
| Server mode | `general_settings` id `SOCIAL_RELATIONSHIP_MODE` | `php tools/social_relationship_inspect.php --set-mode shadow` | `--set-mode off` |
Social capture needs the playthrough handshake (session `ready` with a campaign id); without it the
native side logs `SOCIAL_CAPTURE: skipped ... (no playthrough campaign id)`.

### Test data isolation
Shadow mode writes no affinity (`--check-shadow`). Social rows live only in the six new tables and are
keyed by the loaded save's campaign + load id; a fixture reload prunes later rows via the playthrough
rollback. After the batch: `--set-mode off`, then `--purge-all --yes` (the tables hold only test data
while REL is not enabled for normal play), and Capture=0.

### Scenarios (WSL `/root/stobe-work/social-phase1/server/tests/social_relationship/ingame/`, also in the branch)
Order and checks: `RUN_ORDER.md` there. `REL-p1-01-capture-off` (any normal launch),
`REL-p1-02-capture-on-server-off`, `REL-p1-03-shadow-capture`, `REL-p1-04-reload-stale`
(one launch with Capture=1). Expected: all steps PASS; inspect checks exit 0 (details in each header).

### Offline evidence
`STOBE_DB_NAME=stobe_social_phase1_test python3 tests/run_social_phase1.py`: 14/14 steps pass
(unit/property 600+ checks, integration 666 checks, save migration, concurrency, HTTP, inspect tool,
legacy relationship/stance/rollback, native portable + cross-language contract).

### Game probes this gate answers
1. Does the playthrough session reach `ready` with a campaign id on the fixture (else capture is skipped)?
2. Do event posts arrive in order (few `late` rows)? Many `late` rows = queue reordering; report the count.

## 2026-10-03 Delivery 2: Phase 2 combat (supersedes Delivery 1's commit/patch)

The server branch was rebased onto live `stobe` `22272c7` (items 64, 66, 67, 68); Delivery 1's commit
`03b188e` is now `3f5a711`. Merge the newest commit only.

### Server
- Merge **`feature/social-phase1` at `b2429a0`** (based on `22272c7`, fast-forward). DB updates and
  log rotation as in Delivery 1 (no new migration in this delivery).
- New: `lib/social_interpreter.php`, `lib/social_identity.php`; rules `data/social_relationship_rules.json`
  version `phase2-v1` (+`injury` band, `combat.encounter_idle_seconds` = 600 game seconds).
- Inert while `SOCIAL_RELATIONSHIP_MODE` is off (the interpreter runs only for captured structured
  events, i.e. mode shadow/enabled and native Capture=1).
- Combat rules: only victim -> attacker changes; first strike of a pair encounter = initiator;
  hitting back / already engaged / defending an ally (same faction or both player faction) is free;
  harm escalates one budget per incident (aggression -8..-15 -> injury -15..-28 -> KO -25..-40 ->
  maiming -45..-70, charged as the difference); defender maiming = separate grievance -8..-20;
  unknown attacker or no observed encounter = not scored; generic template names never written.

### Native
- Patch: `C:\KenshiModding\pending-fixes\rel-native-phase2.patch` (cumulative, replaces
  `rel-native-phase1.patch`). Verified against the current `/root/STOBE-src` working tree
  (incl. the newer PlayerBaseState.cpp): `git apply --check` + apply clean.
- Adds structured facts: `attack` (attackingYou hook; victim_targeting_actor, player_defending;
  3 s per-pair debounce), `harm` (major damage = injury, knockout, limb loss = maiming, death; with
  attribution source defeated_by/attacker_list/predation), `recovered`; entity storage id, faction,
  player-faction flag, consciousness. All social posts share one sequence and queue lane 1.
  stobe.log: `SOCIAL_CAPTURE: structured kind=<k> seq=<n> load=<id> actor=#<s> target=#<s> facts=...`.
- Build step unchanged: `SocialEventProtocol` must be in `SOURCES` of `C:\StobeBuild\build_portable.bat`.
- Private proof build from the patched copy: SHA256
  `e59bba5e7b4552c5567a76a7837a4477440f17bb9de7f6ba5c43435f9ac4dbca` (not installed).

### Settings
As Delivery 1. Enabled mode (`--set-mode enabled`) only for `REL-p2-05`, on a `kah-*` fixture copy,
then `--set-mode off` and reload the fixture.

### Scenarios
`REL-p2-01-player-first-strike` (fresh), `REL-p2-04-repeat-assault` (keep), `REL-p2-02-npc-attacks-squad`,
`REL-p2-03-npc-vs-npc`, `REL-p2-05-enabled-affinity` (all fresh). Order and exact checks:
`tests/social_relationship/ingame/RUN_ORDER.md` ("Phase 2 combat"). Run the Phase 1 smoke gate first.

### Offline evidence
Runner 16/16 steps pass, incl. `social_combat_regression` (35 checks). Mutation proof: removing
retaliation, ally defence or the escalation budget each makes it fail (SR03, SR04, SR05).

### Needs a game probe (answers come from the Phase 2 scenarios)
1. `order <npc> UNPROVOKED_FOCUSED_MELEE_ATTACK target <npc>` makes a neutral NPC attack (REL-p2-02/03).
2. The attackingYou hook fires for NPC vs NPC fights (REL-p2-03 `@log` lines).
3. Profile binding: a renamed+talked-to NPC and Malzin resolve (`--interpret-log`: no `unresolved_identity`).
   The player (Shay) as culprit resolves by name if her profile has no storage id; as an observer she
   needs a stored profile.
4. Game seconds per real second (two `time` lines in REL-p2-04) to calibrate the 600 s encounter window.
5. `isUnconcious()` while sleeping (sleeping vs KO): not used yet; needed before phase 3 awareness rules
   treat sleep. Probe: `sleep Malzin` then `where Malzin` (KO flag?).

## 2026-10-03 Delivery 3: Phase 3 unconscious perception (supersedes Deliveries 1-2; merge this one)

Server rebased again onto live `stobe` `2b3593c` (items 69, 72). Earlier commits are superseded.

### Server
- Merge **`feature/social-phase1` at `68c0c25`** (based on `2b3593c`, fast-forward; the branch is
  force-pushed on each rebase, so merge by commit id). DB updates + log rotation as in Delivery 1
  (no new migration since Delivery 1).
- Phase 3: knockout opens a per-victim incident (remembered attacker only with an observed
  encounter or the game's "defeated by"; inventory baseline). Items moved while unconscious are
  objective diagnostics only. On waking: missing items that objectively left are blamed on the
  remembered attacker (x0.8, theft/major/all-property by share), or on a known thief if better
  evidence exists (adapter only until phase 6); unknown attacker = nobody; squad handling squad
  inventory = exempt; enslavement learned on waking and charged to the owner (<= -56), the KO
  attacker keeps only the harm; harm while unconscious is charged on waking inside the attacker's
  encounter budget; a KO carried over a reload resolves once.
- Bug fixed on the way (would have hit live rollbacks once REL captured data): checkpoints stored
  jsonb columns as strings, so a rollback restored incident state as a JSON string.

### Native
- Patch: `C:\KenshiModding\pending-fixes\rel-native-phase3.patch` (cumulative; replaces phase1/phase2
  patches; SHA256 `7d670c5091a4589d66669e2d4f5f63fd398ac1e90a12cc4079e5ebee38b62ee1`). Applies clean to
  the current `/root/STOBE-src` working tree (checked again just before this note).
- Adds: KO harm event carries the inventory baseline + cats, `recovered` carries the current inventory,
  `item_transfer` (actor = taker, target = loser, items, to_ground) from the matched transfer deltas,
  `enslaved`/`freed` with the owner (getMySlaveOwner) as actor.
- Build step: `SocialEventProtocol` in `SOURCES` of `C:\StobeBuild\build_portable.bat` (no other new file).
- Private proof build from the patched copy: SHA256
  `b588f9c8d95f5d49c260e521403d62b2ba2fff4a60c3bd92dc8483f3e5e80f97` (not installed).

### Scenarios
Phase 3 (shadow, Capture=1): `REL-p3-01-ko-loot-inferred`, `REL-p3-02-unknown-ko`,
`REL-p3-03-enslaved-while-ko`, `REL-p3-04-reload-mid-ko` (saves `kah-rel-ko`; delete it afterwards).
Full order: Phase 1 smoke gate -> Phase 2 -> Phase 3, see `RUN_ORDER.md`. All need named NPCs
(the scenarios rename and talk to their bandits).

### Offline evidence
Runner 17/17 steps pass (adds `social_unconscious` 33 checks). `tests/social_relationship/mutation_proof.sh`:
blaming the objective taker, charging enslavement while unconscious, dropping the squad exemption, or
counting used-up items each fail the suite.

### Needs a game probe (answers come from the Phase 3 scenarios)
6. `order Malzin LOOT_TARGET target <KO npc>` really moves items (else the `transfer` fallback line).
7. `shackle <npc> owner <npc>` sets the owner the game reports (`getMySlaveOwner`), i.e. the
   `structured kind=enslaved` line has the slaver as actor.
8. The inventory baseline/current maps use the same item keys (theft share depends on it):
   compare the `"inventory"` facts of the knockout and recovered lines in stobe.log.
9. A reload while KO keeps the same serial for the KO'd NPC (REL-p3-04 BANDIT2 vs BANDIT).

### Risks for merging into live
- Mode off + Capture=0 is inert (no new rows, no table locks on rollback, R4 unchanged); verified offline only.
- `setRelationship` now writes through the canonical writer (both relationship columns) even when off.
- With shadow/enabled every relationship map write takes a row lock + delta merge (dialogue path too).
- Playthrough policy 5 / API 9: first deploy reinstalls the playthrough SQL functions; old snapshots load
  the social tables empty.
- Identity: generic names never bind; the player as an observer needs a stored profile (probe 3).
- Encounter idle window (600 game s) is a guess until probe 4.
