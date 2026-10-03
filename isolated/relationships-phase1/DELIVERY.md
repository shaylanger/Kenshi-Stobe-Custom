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

## 2026-10-03 Delivery 4: Phase 4 aid, carry, food (supersedes Delivery 3; merge this one)

### Server
- Merge **`feature/social-phase1` at `9847985`** (based on live `stobe` `43c15d9`, fast-forward). No new
  migration. Rules `phase4-v1` (new `care` thresholds).
- Aid: one native fact per first-aid session with measured vitals before/after (worst body part
  flesh/max, blood/max, bleed rate). Credit to the person who treats: routine +1..+3 / meaningful
  +5..+12 / lifesaving +20..+35, one growing budget per injury episode (repeat treatment free), counts
  while the patient is unconscious; nothing when the helper or the helper's side caused the injury;
  nothing when unmeasured.
- Carry: outsider pickup of a conscious person -5..-12; unconscious pickup judged only by the outcome:
  bed (placed within 15 s by the carrier) +8..+18, lifesaving class if near death at pickup; prison
  -20..-40 (learned on waking when unconscious); drop alone or placement without a known carrier =
  nothing. Squad: no penalties, routine bedding 0, critical rescue positive.
- Food: food handed over by a conscious donor and eaten within a game day: +2..+5 (hunger < 2.0
  native = UI 200) or +6..+12 (< 1.0); full, own food, routine squad supply, food taken from an
  unconscious body = nothing; one class per donor/recipient/day.

### Native
- Patch `C:\KenshiModding\pending-fixes\rel-native-phase4.patch` (cumulative; SHA256
  `499e20463b893af2fa03c24d475b5ac4c31e3187ef03fee376a7a18f8f2e17f0`), applies clean to the current
  `/root/STOBE-src` (incl. the newer PlayerBaseState.cpp). No new source file.
- Adds `aid` (first-aid sessions closed 4 s after the last treatment frame), `carry_start`, `carry_end`
  (target state at drop), `placed` (bed/prison with the carrier remembered for 15 s), `eat` (with
  fullness before/after), `food_items` + `recipient_hunger` on `item_transfer`.
- Private proof build: SHA256 `24f5ac83e0c33deb5931a562b3e95e25fa9ce2bf3628de684b58b1bcf6deee64`.

### Scenarios
`REL-p4-01-first-aid`, `REL-p4-02-carry-to-bed`, `REL-p4-03-carry-to-cage` (Crafting base fixture: bed and
cages), `REL-p4-04-food` (auto-home). Checks in `RUN_ORDER.md` "Phase 4".

### Offline evidence
Runner 20/20 steps, incl. `social_care` (27 checks) and `mutation_proof` (11 mutations over the combat,
KO and care suites each fail their suite; now part of the runner).

### Needs a game probe
10. Vitals scale: the `kind=aid` stobe.log lines (before/after health, blood, bleed) calibrate the aid classes.
11. `order Malzin FIND_BED_AND_PUT_IN target <npc>` carries and beds a KO'd NPC.
12. `LIFT_PERSON` + `PUT_IN_CAGE building <cage>` cages him; `placed` "prison" names Malzin.
13. `transfer` + `eat` produce `item_transfer` with `food_items`/`recipient_hunger` and `eat` lines.
Known gap: carry by the player actor (Shay) is not captured (the world poller skips the player actor).

## 2026-10-03 Delivery 5: Phase 5 property, economy, agreements (supersedes Delivery 4; merge this one)

### Server
- Merge **`feature/social-phase1` at `3cd48b5`** (based on live `stobe` `1a8fc3f`, item 74; fast-forward).
  No new migration. Rules `phase5-v1`.
- **Touches a live file outside REL:** `lib/negotiation_engine.php` `stobeNegApplyConsequences` gets a
  4-line hook: when REL is enabled it scores the deal outcome (kept_promise +1..+3, kept_coercive_deal
  0..+2, broken_promise -5..-15, + betrayal -20..-40 if the player broke the truce) and the legacy
  +4/-15 is skipped. Off/shadow keep the legacy delta (shadow records the would-be effect).
  `tests/negotiation_engine_regression.php`: 190 pass with and without the hook.
- Theft: scores only stolen-flagged items the owner CAUGHT; native sends `caught: null` (no proven
  detection signal) so **no theft scores in game yet** (by design, plan section 3). Severity by share of
  belongings, starving owner's food = major, returned items = small compensation once, squad exempt.
- Gifts (+1..+4) and trade (buyItem path; price vs the game value) share the economic budget (decreasing
  weights, +6/day, never past +30); shop storage seller, faction purse, missing value = nobody credited;
  deal payments are not gifts.

### Native
- Patch `C:\KenshiModding\pending-fixes\rel-native-phase5.patch` (cumulative; SHA256
  `830ec34258e98f63a4421d44a71adc5b6fc1ff5d104363bf391f3372e9861790`), applies clean to the current
  `/root/STOBE-src`. Adds `trade` from the buyItem hook (buyer, seller only if a character, buyer_spent,
  seller_gained, reference_value) and on `item_transfer`: stolen_items, caught=null, owner inventory size, owner fullness.
- Private proof build: SHA256 `0fb7e3cae0a8f7569834a04f28d53fa8368c666f6d5bd49a8818fba1c80fcb52`.

### Scenarios
`REL-p5-01-trade` (Trader), `REL-p5-02-gift` (auto-home), plus two deal procedures in `RUN_ORDER.md`
"Phase 5" (scenarios.sh surrender: kept deal; attack after acceptance: broken + betrayal).

### Offline evidence
Runner 22/22 steps incl. `social_property` (31 checks), `legacy_negotiation` (190) and `mutation_proof`
(15 mutations, each fails its suite).

### Needs a game probe
14. A real purchase (`trade Shay <trader> <item>`): is the seller a character or shop storage, and what is
    buyer_spent / reference_value for a normal purchase (calibrates the economy thresholds)?
15. `transfer` of a non-food item to an NPC gives an `item_transfer` with a conscious giver and no stolen items.
16. Blocker for SR13/SR14 in game: an engine signal that a theft was caught (and a steal action driver).

## 2026-10-03 Fix for run m4: no social events without Playthrough Saves

**Cause:** live runs with Playthrough Saves (automatic switching) off. The handshake then answers `off`, so
`PlaythroughSession::Character()` stays empty. The native code needed a campaign id for every envelope, and
the server scope needed a `ready` handshake. Every event was therefore skipped
(`SOCIAL_CAPTURE: skipped ... (no playthrough campaign id)`), and all counts stayed 0. The autoload path
was not the cause. You can confirm with `SELECT value FROM stobe_meta.settings WHERE key='PLAYTHROUGH_AUTO_SWITCH'`,
which should not be `true`.

**Fix**
- Native: `C:\KenshiModding\pending-fixes\rel-native-m4-fix.patch` (SHA256 `6f89051603ea900aa23f646d14d7fd540e2089e26687f4040e8591dbae3fd30e`).
  - It is incremental: it applies to the current `/root/STOBE-src`, which already contains phase 5. Only `src/Utils.cpp` changes.
  - Without a campaign id the game now sends campaign `legacy` and logs once: `SOCIAL_CAPTURE: no playthrough campaign id (Playthrough Saves off): using campaign 'legacy'`.
  - Private proof build: `7f8a738c…`.
- Server: merge `feature/social-phase1` at **`5cd104e`** (one commit on top of live `dcf71ac`).
  - `stobeSocialScope` accepts `legacy` only while switching is off. It takes the load id and client from the event, and refuses an older load after a newer one (stale queue after a reload). Behaviour with switching on is unchanged.
  - The inspect tool's `session` field and its checks follow the same scope: `"status": "playthrough_saves_off"`, `"campaign_id": "legacy"`.
  - New `tests/social_scope_regression.php` (9 checks) fails without the fix. The runner passes 23/23 steps.
- Scenarios:
  - `REL-p1-02`: removed the `@log` of the startup "enabled" line; it moved to the verify header as a grep, since `@log` only sees new lines.
  - `REL-p1-02` step 19 and `REL-p1-03` (`queued`) failed because nothing was sent. They should pass with the fix.
  - `RUN_ORDER.md` has a new "Playthrough Saves off" section.

## 2026-10-03 Run m4 results, fixes and reruns

**The DB rows were already gone when I looked.** Each fixture reload runs the playthrough rollback,
which prunes social rows later than the fixture's game time. That is by design: relationships follow
the loaded save. So for each scenario I judged from the `*.inspect.txt` snapshots taken right after
it, plus stobe.log. I purged the six tables afterwards: they were already empty. Mode is off.

### Verdict per SR row (m4)
| Row | Verdict | Evidence / reason |
|---|---|---|
| SR41 | pass | p1-01 inert; p1-02 server off stored nothing; every shadow run passed `--check-shadow`; p2-05 enabled applied effects. Not checked: the R4 `--relation` check. |
| SR02 | pass | p2-01 Rel Vorn->Shay -14; p2-02 Malzin->Rel Kesh -14; p2-03 Rel Bek->Rel Arn -15; p2-05 Rel Dov->Malzin -31 (applied) |
| SR03 | pass | no row for the side that hit back (p2-02: Kesh->Malzin, Kesh->Shay; p2-03: Arn->Bek) |
| SR04 | pass | Shay defending Malzin not charged (p2-02) |
| SR05 | pass | p2-05: aggression -15, injury -1, KO -15, one budget (-31 inside the KO band) |
| SR34 (binding) | pass | renamed NPCs, Malzin and Shay all resolved (probe 3) |
| SR38/SR40 | pass (stale check) | p1-04 `--check-stale` passed. Step #27 failed only because of a log format bug (fixed, below). |
| SR06 | scenario issue | p2-04: the fight went on during the wait, so it stayed one encounter |
| SR08, SR11, SR12, SR38 (p3-04) | scenario issue | the bandits fled and were never knocked out; in p3-03 he also left event range before the shackle |
| SR10 | scenario issue | p3-02: no blame, as expected, but the transfer itself was not captured (food eaten on arrival) |
| SR15/SR16 | **real bug** + scenario issue | first aid bandages wounds; flesh barely changes (-41% stayed, bandaging 0->96), so aid was graded by the wrong measure. The aid session was also never closed before the game paused. |
| SR21 | scenario issue | the hungry NPC ate the meat on arrival. Native facts were correct for the full NPC (Fenn: food_items, hunger 2.8, eat 2.8->2.8). |
| SR18/SR19 | blocked (probes 11/12 negative) | `FIND_BED_AND_PUT_IN` and `LIFT_PERSON` produced no carry: no `[EVENT] carry` line at all |
| SR22/SR23 | scenario issue | p5-01's regex captured "5 traders within 300.0: Erisila" as the trader name |
| gift | open (probe 15) | the Iron Plates transfer Shay->Rel Gav left no inventory line at all (Shay's inventory was full: 3/6 arrived) |
| SR29 | not run | deal procedures |
| noise (**real bug**) | fixed | town medics' +0.5% flesh top-ups were earning routine-healing credit |
| SR43 | noted | in the Hub: ~1500 inbox rows and ~850 checkpoints per load in a few minutes |

### Probe answers
- 1: `order … UNPROVOKED_FOCUSED_MELEE_ATTACK` works.
- 2: the attack hook fires for NPC vs NPC fights.
- 3: binding works for renamed NPCs, Malzin and Shay.
- 4: `game_ts` is game seconds (gamets/3600 = the harness's game_hours).
- 10: first aid raises bandaging, not flesh; harness `damage` wounds have bleed 0.
- 13: the item_transfer and eat facts are correct.
- 11/12: negative (see above).
- 5, 6, 7, 9, 14, 15, 16: still open.

### Fixes
- **Server: merge `feature/social-phase1` at `1ca847c`** (one commit on live `stobe` `21fdbed`).
  - Aid is now graded by wound points newly bandaged; near death = worst part <= -30% or blood <= 35%; routine credit needs >= 2% flesh or >= 5 bandaged points.
  - An open encounter is refreshed and checkpointed at most once per game minute.
  - inspect: the `loads.events` count is fixed.
  - Rules are now `phase5-v2`. The runner passes 23/23 steps; new care checks fail without the fix.
- **Native: `C:\KenshiModding\pending-fixes\rel-native-m4b.patch`** (SHA256 `3af774a4e51bee0097f13b8980182326698910cbe9480e2f4d80e573ba3e6349`).
  - Incremental against the current `/root/STOBE-src`; changes `Utils.cpp` and `main.cpp`. Private build `3940adb7…`.
  - Unsigned serials in the `queued` log lines: serials >= 2^31 printed negative, which broke `@log` matches like p1-04 step #27.
  - Aid facts now include `wound`/`untreated` (bandaging).
  - A capture-only probe line `INV_TRANSFER: gain without loss this sweep to=… item=…` for the unseen transfers.
- **Scenarios:**
  - p2-01, p3-01, p3-03, p3-04 cripple the bandit's legs so the knockout happens.
  - p3-03 brings him back into range before the shackle.
  - p3-01, p3-02, p3-04 use Iron Plates instead of food for transfers.
  - p2-04 sends the bandit 300 m away during the wait.
  - p4-01 waits for full bandaging, then lets the game run 8 s so the session closes.
  - p4-02/03 log `where` plus a screenshot; p4-03 spawns near Shay.
  - p4-04 uses hunger 170 and an `inv` check.
  - p5-01 has fixed regexes; p5-02 gives 1 plate and checks `inv`.

### What to rerun (after installing m4b, Capture=1, mode shadow; inspect after each, before the next reload)
p1-04 (log format only), p2-01, p2-04, p3-01, p3-02, p3-03, p3-04, p4-01, p4-04, p5-01, p5-02.
Then p4-02 and p4-03 once, for the where/screenshot diagnostics. Optionally the two deal procedures (SR29).
Also please check `grep "INV_TRANSFER: gain without loss" stobe.log` during p3-02/p5-02.

## 2026-10-03 Run m5 results, fixes and reruns

Judged from the `m5/rel/*.inspect.txt` snapshots, the gain/loss files and the archived stobe.log
(`C:\KenshiTestRuns\logs\20261003-040157-stop\stobe.log`).

### Root causes found
1. **Crowd limit (native, real bug):** Stobe's world sweep covers the player plus at most 16 characters
   around her (`getCharactersWithinSphere(..., 16, ...)`). In the Hub (raids, many townsfolk) the test NPCs
   dropped out. As a result their KO, shackle, transfer and recovery facts were never seen (p3-02 KO, p3-03
   enslaved, p3-04 recovered, p5-02 gain).
   **Fix:** characters that appeared in a social fact or event in the last 5 min (newest 16) are always
   added to the sweep.
2. **KO without attribution (native):** a KO in a fight can come with no attacker from the game (p2-01:
   `unattributed`). **Fix:** the KO/harm fact then names the last attacker the attack hook saw for that
   victim within 10 s (`attribution: recent_attacker`). The server still scores harm only inside an
   observed encounter.
3. **Trade sides lost (native):** `getDataType()` did not identify Shay or Keys as characters, so the
   fact had actor and target null (`incomplete_roles`). **Fix:** sides are resolved by serial in the
   character list; shop storage still resolves to nobody.
4. Scenario issues:
   - Crippling at 95 still let them flee. Now legs go to -10%, and the KO is forced 6 s after the attack.
   - Hub guards haul KO'd outsiders away. p4-01 now runs on auto-home; p4-02/03 are blocked.
   - Hungry NPCs eat food on arrival. Food is now handed over while the recipient is full, then he is
     made hungry and eats it.
   - Shay's full inventory hides items from the scan. The gift now comes from an NPC donor.
   - p2-04 must run chained after p2-01 (keep).
5. Not noise: the meaningful-aid rows between townsfolk are real. Hub medics bandage raid wounded
   (e.g. worst -0.22, 230 untreated points bandaged).

### Verdicts (m5)
- **Pass:**
  - SR41 (every shadow run passed `--check-shadow`).
  - SR38/SR40 (p1-04 25/0, including the log-format fix).
  - SR02 (Rel Vorn->Shay -12).
  - SR15 (Malzin->Rel Ona meaningful_aid +11 while she was unconscious and near death).
- **Rerun needed after the m5 build:** SR05 (KO attribution), SR06 (chained), SR08, SR10, SR11, SR12,
  SR16, SR21, SR22/SR23 (trade sides), gift.
- **Blocked:** SR18/SR19. Needs a fixture with a bed and a cage and no town guards. Also, Malzin did not
  act on `FIND_BED_AND_PUT_IN`.
- **Probe answers:**
  - 14: a normal purchase from Keys paid 146 = value 146, ratio 1.0, so the trade is fair and earns nothing.
  - 15: the gift transfer from Shay's full inventory is not seen by the inventory scan (Stobe's own scan,
    not REL; probably backpack contents).
  - The `gain without loss` lines (Liplom water) are townsfolk getting water: harmless.

### Delivery
- **Native:** `C:\KenshiModding\pending-fixes\rel-native-m5.patch` (SHA256 `97f7296d0fa7395e889233c9492c037e94cce86b92b196db03a9ed0cf7778ab0`).
  Incremental against the current `/root/STOBE-src` (which has m4b). Changes `Utils.cpp`, `main.cpp`,
  `SocialEventProtocol.h`. Private build `b47f8fc1…`.
- **Server:** `feature/social-phase1` at `de3b29c` on live `4a1cfe3`. Only scenarios and scenarios.json
  changed; no lib change since `1ca847c`.

### Rerun (m5 build, Capture=1, shadow; fresh fixture before each unless noted; inspect before the next reload)
1. p2-01, then **p2-04 with keep** (no reload)
2. p3-01, p3-02, p3-03, p3-04
3. p4-01 (now auto-home)
4. p4-04
5. p5-01 (Trader)
6. p5-02

Do not rerun p4-02/p4-03 until there is a suitable fixture.

## 2026-10-03 Delivery 6/7: witnesses, dialogue guard, recruitment gate, slave escape

### Server
- Merge **`feature/social-phase1` at `307b011`** (one commit on live `stobe` `de3b29c`; fast-forward).
  No migration. Rules are now `phase7-v1`.
- **Touches `lib/chat_helper_functions.php`** in 3 small hooks, all inert unless mode is `enabled`:
  1. The relationship evaluator filters its updates (`social_dialogue.php`).
  2. `stobeBuildActionConfigForNpc` asks the recruitment gate (`social_recruitment.php`).
  3. `normalizeActionTagToken` drops `JOIN_PARTY` when the gate blocks it.
- **Witnesses:** the native envelope now lists characters within 40 m, each with the game's own
  sensing (`SensoryData::canISeeThisGuy` / `canIHearThisGuy`) and consciousness.
  - Only conscious witnesses who perceived the act get a share of the victim's effect toward the culprit.
  - The share depends on how the witness felt about the victim before the event: affinity 11/31/56/76/91 → 5–10 / 15–25 / 25–40 / 40–55 / 55–70%. Positive acts (aid) count at half that rate.
  - Each witness counts once per incident, the share grows with the harm budget, and it is one hop only (echoes never echo).
  - Switch: `SOCIAL_CATEGORY_WITNESS`.
- **Dialogue guard (enabled only):** LLM evaluator deltas are clamped to -8..+3. For a pair that REL
  already scored mechanically in the last game hour, the dialogue delta is dropped (no double count).
- **Recruitment gate (enabled only):** JoinParty needs affinity >= 76 plus trust evidence (lifesaving,
  a completed escape, or 2+ major aid/rescue) and no severe grievance. Economic evidence never counts.
  `SOCIAL_RECRUITMENT_OVERRIDE=true` lifts the gate (documented override); `SOCIAL_CATEGORY_RECRUITMENT` switches it.
- **Slave escape:**
  - A known liberator gets chains_freed (+8..+18) right away.
  - If the freed slave is seen alive and free one game day later (`escape.sustain_seconds`), the escape completes: one budget of +15..+65, chains included.
  - Recaptured or dead before that: no completion. Unknown liberator: nobody credited.

### Native
- Patch `C:\KenshiModding\pending-fixes\rel-native-p67.patch` (SHA256 `f2b686189d05a1505b9a9f7e13b4e80b66d3ce0572599868700d05f6c88d5334`).
  - Incremental against the current `/root/STOBE-src`, which already has m5. Private build `e8f430d1…`.
  - Witnesses on attack, harm and aid facts. The log line now shows `witnesses=N`.
  - Theft `caught` = the conscious owner's senses register the taker (was always null).
  - `freed` carries the liberator: the character whose current task targets the slave, e.g. `PICK_LOCK_ON_SHACKLES`.
  - `#include <kenshi/SensoryData.h>` added; no new source file.

### Scenarios (order in `RUN_ORDER.md` "Phase 6/7")
1. `REL-p6-01a-witness-setup` (fresh).
2. Two `--set-relation` commands (new test-setup option of the inspect tool).
3. `REL-p6-01b-witness-attack` (keep).
4. `REL-p7-02-slave-escape` (fresh).
5. `REL-p7-01-recruit-gate` (fresh, enabled mode, LLM-dependent).

### Fixture for SR18/SR19
Build one Bed and one Prisoner Cage at Home in a copy of auto-home, using the game UI (the harness has no
build command), and save it as fixture "Home beds". The Hub doesn't work: town guards haul knocked-out
outsiders away. p4-02 and p4-03 then run there unchanged.

### Offline evidence
- The runner passes 24/24 steps; new suites `social_witness` (19 checks) and `social_recruitment` (21 checks).
- `mutation_proof`: 20 mutations, each fails its suite. New ones cover: nearby counted as witnessed, every
  witness treated as a close friend, the dialogue re-scoring a fight, the gate only in the prompt, and an
  escape completing without the wait.

### Needs a game probe
- **17:** `caught` reported by the owner's senses on a real conscious transfer (look for `"caught":true|false` on `item_transfer` lines).
- **18:** witness sensing returns sensible values (the attack line has `witnesses>=1`; the friend is perceived).
- **5:** `isUnconcious()` while sleeping (the sleeping friend in p6-01b).
- **20:** `PICK_LOCK_ON_SHACKLES` gives the freed fact a liberator.

### Not done (blocked or partial)
- An insult heard by a friend: dialogue listeners are not witnesses yet.
- Prompt-side belief injection: notes only.
- Native `ACT_JOIN_PARTY` fallback paths: not audited in game.

## 2026-10-03 Run m8 results, fixes and reruns

### Verdicts (m8)
- **Pass:**
  - SR02 and SR05 (p2-01: Rel Vorn->Shay aggression -15 + KO -21, KO attributed to Shay, remembered attacker Shay).
  - SR10 (p3-02: KO with no attacker, transfer latent, on waking `no_known_culprit`).
  - SR15 (p4-01: Rel Ona->Malzin **lifesaving +29** while unconscious).
  - SR22 normal purchase (p5-01: Shay buys from Keys = `fair_trade`).
  - SR24 (p6-01b: Rel Wren, bonded 91, -> Shay witness -7 of the victim's -10).
  - SR41 (all shadow runs). p7-01 in enabled mode: the NPC was not recruited.
- **Real bugs, fixed:**
  - SR25: a floor-sleeping friend (Rel Sorn) counted as a witness (-6). `isUnconcious()` is false while sleeping (probe 5).
    **Fix (native):** a character in a bed or whose current task is sleeping is not a witness.
  - SR08: looting a knocked-out body showed only the looter's gain (Malzin: rag shirt, fabrics); the body's loss never appeared.
    **Fix:** the native side sends unmatched gains as `item_gain`. The server ties a gain to the one knocked-out owner whose
    baseline holds those items (ambiguous = no attribution), so waking with them missing blames the remembered attacker.
- **Scenario issues:**
  - My m7 log format added `witnesses=N` before `facts=`, so the `@log` regexes did not match (p2-01 #34, p3-01 #37,
    p4-04 #38, p4-02/03). Fixed in the scenario files.
  - A fled bandit (230 m away) cannot be teleported once KO'd. He is now brought next to Shay before the forced KO.
  - The gift donor was never talked to, so the world sweep never looked at her inventory. She is now talked to first.
- **Inconclusive:**
  - SR06 (p2-04): after the first beating the bandit turned hostile and struck first on return, so Shay's blows were
    correctly retaliation (no new row). A clean repeat needs a victim who stays non-hostile.
  - SR30 (p7-01): the LLM never tried JoinParty, so the gate was not exercised.
- **Blocked / probe:** SR11, SR12, SR32. No `enslaved`/`freed` fact at all, although `shackle` reported
  `chained=1 slave_state=1`, and no legacy `[EVENT] slavery` line either.
  New probe 21: a capture-only line `EVENT_SCAN: first seen already enslaved serial=… name=…` shows whether these
  bandits are already slaves when first seen; if so, no transition can be reported.

### Delivery
- **Server:** `feature/social-phase1` at **`7f57911`** (one commit on live `795b0f1`). Adds `item_gain`;
  the runner passes all steps; unconscious suite now 36 checks.
- **Native:** `C:\KenshiModding\pending-fixes\rel-native-m8.patch` (SHA256 `d8404870dd92d97dc7acd1f597c17c1bf67ef32b151e4d06b4f6221f808778d4`).
  Incremental against the current `/root/STOBE-src` (which has REL 1-7). Private build `349e787e…`.

### Rerun (m8 build, Capture=1, shadow, fresh fixture unless noted)
1. p2-01, p3-01, p3-03, p3-04
2. p4-04
3. p5-02
4. p6-01a, set-relation, p6-01b (keep)
5. p7-02

p2-04 is optional (see SR06). Afterwards, grep stobe.log for `first seen already enslaved` (probe 21) and for
`kind=freed ... liberator` (probe 20).

### Harness build command (answer for SR18/SR19)
Feasible. KenshiLib exposes `RootObjectFactory::createBuilding(GameData* data, Ogre::Vector3 position, TownBase* t,
Faction* owner, Ogre::Quaternion rotation, FactoryCallbackInterface*, Layout*, Building* isDoorOf, GameSaveState*,
Building* isIndoorsOf, bool invisible, bool completed, bool isFoliage, int floorNumber, bool isOutsideFurniture)`
(RVA 0x57C4F0, `RootObjectFactory.h`), and `GameWorld::theFactory` is a member.

Suggested command: `build <building name> [near <npc> dist m | at x y z] [faction <name>]`.
1. Look up the GameData of type BUILDING by name (as `find` does).
2. Call `world->theFactory->createBuilding(data, pos, nullptr, faction ? faction : player faction, Ogre::Quaternion::IDENTITY,
   nullptr, nullptr, nullptr, nullptr, nullptr, false, /*completed*/ true, false, 0, false)`.
3. Report the building name and position (`buildings` then lists it).

Unverified: whether a town pointer (nullptr) and an identity rotation are accepted for furniture like "Bed" and
"Prisoner Cage", and whether the building needs a terrain/height snap. Test by building one bed at Home and checking
`buildings 50 Bed`. With it, p4-02/p4-03 run on auto-home: `build Bed near Shay dist 10`,
`build "Prisoner Cage" near Shay dist 15`.

## 2026-10-03 Run m9 results, fixes, phase 8 (offline)

### Verdicts (m9)
- **Pass:**
  - SR38 (p3-04 39/0: knocked out, loot latent, reload).
  - SR24 (Rel Wren -6 of the victim's -10).
  - SR02 again (Rel Vorn->Shay, Rel Tam->Shay -31 = aggression + KO).
  - The m8 `item_gain` path works: Rel Gav's unmatched gain was reported, `no_ko_owner` as expected.
  - SR11 progress: p3-03 44/0, the enslaved fact for Rel Vash is now captured (he was brought close).
- **Real bugs:**
  - p2-01: Malzin's KO of the bandit had no encounter (`no_encounter`) because the hook never reported her own
    attack. **Fixed (server):** an ally who harms someone already being assaulted by their side joined that assault.
  - SR25: the floor-sleeping witness (Rel Sorn) still counted (-7) despite the m8 sleep check. Witness entries now
    carry the character's `task` and `prone` state (probe 22), and prone KO / playing dead never witnesses.
- **Scenario issues:**
  - p3-01: the KO'd bandit was killed because the fight went on over the body. Everyone now steps back right after the KO.
  - p4-04 / p5-02: the recipient wandered off and was never scanned. Recipients are now brought next to Shay first.
  - p7-02: probe 21 answer: "first seen already enslaved: Rel Xan". He was never scanned before the shackle.
    He now spawns next to Shay, and a sweep sees him free before the shackle.
  - The `@log` harm lines in p2-01 / p3-01 depended on the KO attacker; they are now covered by the inspect checks.
  - p4-02 / p4-03 must be rerun after harness D8ECA273 (the `build` height bug).
- **New diagnostic:** stobe.log `SOCIAL_FOCUS: focus=N resolved=M unresolved=#…` every 20 s. If unresolved serials
  show up, the character list Stobe searches doesn't contain them (out of the active area).

### Phase 8: offline parts done
- **Retention (SR43):** raw facts, checkpoints and finished incidents older than 3 game days are pruned every 2000
  facts (also `inspect --retention`). Never pruned: the ledger, beliefs, latent incidents.
- **Perf/soak bench** `tests/social_perf_bench.php`, part of the runner: 6000 facts over 4.2 game days in shadow mode.
  p50 5.9 ms, p95 12.2 ms, max 18 ms per fact; tables bounded; no latent incident lost.
- **Release notes:** `docs/social_relationship_release.md` (switches, install manifest, rollback recipe, validation summary, open gates).
- Runner: all steps pass, including 20 mutations and the perf bench.

### Delivery
- **Server:** `feature/social-phase1` at **`8da1a73`** (one commit on live `e9f8598`); rules `phase8-v1`.
- **Native:** `C:\KenshiModding\pending-fixes\rel-native-m9.patch` (SHA256 `5738976b3cdff7ed82e70f245c09c33a2b9c78a95f434a7b355c314a288b92da`),
  incremental against the current `/root/STOBE-src` (which has m8). Private build `24a71b5c…`.

### Rerun (m9 build, Capture=1, shadow, fresh unless noted)
1. p2-01
2. p3-01, p3-03
3. p4-02, p4-03 (auto-home with the fixed harness `build`)
4. p4-04, p5-02
5. p6-01a, set-relation, p6-01b (keep): report the witness `task`/`prone` values of Rel Sorn (`--events 60` or stobe.log)
6. p7-02

Afterwards, grep stobe.log for `SOCIAL_FOCUS` and `first seen already enslaved`.

### Phase 8: in-game parts (the coordinator's)
1. **Soak + performance gate:** `REL-p8-01-soak.txt` (Crafting base = the Hub, 3 × 2 game hours at speed 5, about an
   hour of real time). Run once with Capture=0 and once with Capture=1 (shadow).
   Pass: no crash or hang; no `SERIAL_HTTP: queue overflow`; inbox growth flattens once retention runs;
   `--check-shadow` exit 0; frame time / fps within 5% of the Capture=0 run.
2. **Full matrix rerun on one build:** p1-01..04, p2-01..05, p3-01..04, p4-01..04, p5-01..02, p6-01a/b, p7-01..02.
   Record the DLL hash and server commit.
3. **Enabled-mode session** on a kah-* copy (p2-05 style): Shay's short balance and feel review.
4. Install manifest and rollback check: follow the release notes once (`--set-mode off`, purge, Capture=0) and
   confirm legacy behaviour (p1-01).

### Is REL ready for phase 8?
For the offline part, yes (done above). For the final in-game sign-off, not yet. These gates are still open:
- Carry (SR18/19): needs the harness `build`.
- Slavery capture (SR11/12/32): needs the probe 21 rerun.
- Sleeping witnesses (SR25): needs probe 22.
- Recruitment gate exercised (SR30): LLM-dependent.
- Repeat assault (SR06): needs a non-hostile victim.

The soak can run now, in parallel with those reruns.

## 2026-10-03 Run m10 (p4-02 / p4-03 with the fixed `build`), judged from the snapshots

Rule from the coordinator: **REL purges only when the coordinator says so.** My m9 purge hit this run.

- **p4-03:**
  - `LIFT_PERSON` works: Malzin and Rel Kade ended up at the same position, i.e. she was carrying him.
    `carry_start` and `placed` facts were captured (probe 12 answered: yes for LIFT).
  - `PUT_IN_CAGE` failed because of my regex: it captured " Prisoner Cage dist". Fixed.
- **p4-02:** `FIND_BED_AND_PUT_IN` did nothing for Malzin (probe 11 negative). Rel Cobb was hauled 218 m by someone
  outside the sweep. The scenario now uses `LIFT_PERSON`, then `PUT_SOMEONE_IN_BED building "Bed"`, with `where` checks.
- **Server:** `feature/social-phase1` at `7a0a000` (scenarios only, on live `8da1a73`). No native change.
- **Rerun in m11:** p4-02, p4-03 (auto-home, `build` Bed and Prisoner Cage first).

## 2026-10-03 Run m11 results, fixes, frame-time gate, final report draft

### Verdicts (m11)
- **Pass in game (new):**
  - SR18: Rel Cobb -> Malzin safe_rescue +9 (`LIFT_PERSON` + `PUT_SOMEONE_IN_BED` on the built bed).
  - SR19: Rel Kade -> Malzin imprisonment -31 (`LIFT_PERSON` + `PUT_IN_CAGE`).
  - SR05: Malzin's knockout of Rel Vorn is now charged as a joined assault (-40).
  - Gift: Rel Gav -> Rel Dona +3.
  - SR24 again.
- **Probe 7 answered:** the enslaved fact names the shackle owner (Rel Grell -> Rel Vash).
- **Real bugs, fixed:**
  - SR11: Rel Vash's own knockout was never seen, so his enslavement was lost on waking. **Server:** a KO holder
    now keeps the enslavement until he wakes.
  - SR32 / focus: raid attack facts flooded the 16-character focus list, so Rel Xan was again "first seen already
    chained" (`SOCIAL_FOCUS` showed many unresolved serials). **Native:** focus now comes only from chats, facts
    involving the player's side, and KO / enslave / carry / transfer facts; the list holds 24.
  - SR25: the floor-sleeping witness still counted (-5). The stobe.log line now includes the witness entries
    (`w=[...]` with `task` / `prone`) so the next run shows whether he was asleep or woken by the fight.
- **Scenario issues:**
  - Regex `witnesses=d+` lost its backslash, which broke the harm `@log` steps in p2-01 / p3-01. Fixed.
  - Malzin attacked the spawned Drifters (p4-04, p5-02, p7-02). Their faction is now set to friendly with `relation 60`.
  - The m11 soak was healthy but quiet (68 facts in 6 game hours). It now spawns three raids.
- **Still open:** p3-01's loot by Malzin (`LOOT_TARGET`, probe 6) was not captured.

### Delivery
- **Server:** `feature/social-phase1` at **`796019b`** (2 commits on live `7a0a000`).
- **Native:** `C:\KenshiModding\pending-fixes\rel-native-m11.patch` (SHA256 `ce715bbbde8ca2048fa3f7abbefb8ab84539adea63f8027293e6feace7377daa`).
  Incremental against the current `/root/STOBE-src` (REL m9 + item 88). Private build `67bf37a0…`.
- **Note:** the live `main.cpp` "Item 88b" fighter loop sits right after the REL focus block. A rebase conflict
  there was resolved by keeping both; the patch only touches the focus cap line.

### Frame-time gate: what to record
The harness has no fps today. Please have the helper add **`fps`**:
- `Ogre::Root::getSingleton().getAutoCreatedWindow()` -> `getAverageFPS()`, `getWorstFPS()`, `getWorstFrameTime()`;
  then `resetStatistics()`.
- It answers `avg=… worst=… worst_ms=…`.

Until then, the soak screenshots capture RE_Kenshi's on-screen FPS counter.

At each soak checkpoint, for A (Capture=0) and B (Capture=1, shadow), record:
1. `fps`
2. `(Get-Process kenshi_x64).WorkingSet64/1MB`
3. B only: the inspect counts, `grep -c "SERIAL_HTTP: queue overflow"`, the last `SOCIAL_FOCUS` line, and the stobe.log size

**Pass:** B avg fps >= 95% of A; worst frame time <= 110% of A; memory growth B-A < 100 MB; no overflow;
`--check-shadow` exit 0.

### Rerun (m11 build)
1. p2-01, p3-01, p3-03
2. p4-04, p5-02
3. p6-01a/b: report `w=` for Rel Sorn
4. p7-02
5. p8-01 twice (A Capture=0, B Capture=1)

Optionally p4-02/p4-03 once more to confirm.

### Final report draft
In `docs/social_relationship_release.md` ("Final report (draft)"), generated from scenarios.json:
- 12 rows pass in game
- 9 offline only / by construction
- 18 partial / rerun pending
- 5 blocked / open

Recommendation: keep `shadow` for normal play until the soak gate and the open rows close. `enabled` is fine for a
supervised balance session on a fixture copy. Turn off `SOCIAL_CATEGORY_SLAVERY` / `_WITNESS` if they are still
open when enabling for real play.
