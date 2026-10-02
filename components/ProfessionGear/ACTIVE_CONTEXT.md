# Profession Gear Progression — ACTIVE CONTEXT

**Last updated:** 2026-10-02
**Purpose:** Live handoff file. Update this file every implementation turn before finishing so another agent can continue without reconstructing state.
**Hard constraint:** DO NOT install, copy, enable, or otherwise apply this mod to the Kenshi game directory until Shay explicitly authorizes it.

## Project locations

- Design/source context: `C:\KenshiModding\PROFESSION_GEAR_PROGRESSION_MOD_CONTEXT.md`
- Active project: `C:\KenshiModding\components\ProfessionGear`
- Kenshi SDK used for compile: `C:\StobeBuild\sdk`
- VS2010 portable toolchain: `C:\StobeBuildTools`
- Current package output: `C:\KenshiModding\components\ProfessionGear\out\package\ProfessionGearProgression`
- Current game install check used previously: `D:\Steam\steamapps\common\Kenshi\mods\ProfessionGearProgression`
- The game mod directory above was checked and the ProfessionGearProgression folder was NOT present.

## Git state / history

- Repository: `C:\KenshiModding`
- Branch: `main`
- Remote: `origin https://github.com/shaylanger/Kenshi-Stobe-Custom.git`
- ProfessionGear initial implementation commit: `b0c29f1 feat: add profession gear progression mod foundation`
- That commit was pushed to origin/main.
- There are unrelated modified/untracked files in the repo. Do not stage or alter them unless directly required.
- Current unrelated tracked modification observed: `tools/stobe-reset-npc`
- Current unrelated untracked files include root context docs and several tools scripts.

## What is implemented now

### Core
- Standalone SDK-independent `ProfessionGearCore`.
- Contextual item tags for Farming, Mining/Labouring, Research, Engineering, Robotics, Medic, smithing, Cooking, work/travel boots, specialist packs, Turrets, Scout and Stealth.
- Profession stat mapping includes Labouring, Science, Engineering, Robotics, Weapon/Armour/Crossbow Smithing, Medic, Turrets, Farming, Cooking, Athletics, Swimming, Perception, Stealth, Assassination, Lockpicking and Thievery.
- Item quality -> 7 internal tiers.
- Tier-specific affix chance and magnitude range.
- 1 affix normally, optional second coherent affix at higher quality.
- Deterministic per-instance RNG keyed by item handle/base ID.
- Role-aware roll weighting.
- Player-crafted chance multiplier.
- Poor/slave suppression.
- Stackable items excluded.
- TSV serialization/parser for per-instance affix persistence.

### Game plugin
File: `src\ProfessionGearPlugin.cpp`

Hooks:
- `PlayerInterface::update`
- `CharStats::getStat(StatsEnumerated,bool)`
- `CraftingBuilding::addFinishedCraftItem(Item*)`
- `Inventory::getTotalWeight()`
- tooltip `getTooltipData1` for InventoryItemBase, Armour, ContainerItem, Crossbow and Sword.

Behavior:
- Scans loaded characters once per second from `GameWorld::getCharacterUpdateList()`.
- Discovers eligible items and gives each one a persistent roll once.
- Uses character profession stats to infer primary profession context.
- Reads slave state and suppresses special rolls for slaves/very poor NPCs.
- Effective profession stat bonus is applied only when the affixed item is equipped.
- `getStat(..., true)` (unmodified/base stat) is left untouched.
- Effective stat result is capped at 150.
- Crafted eligible item is rolled at craft completion using final item quality.
- Tooltip appends a `Profession Gear` section with stat bonuses.
- Specialist backpack weight path exists for ore, crop, construction, medical, tech and trade packs.
- Backpack specialization preserves Kenshi's original total and applies a category-specific ratio to contents.
- Master `Enabled` switch bypasses scanning/stat/tooltips/backpack changes.
- `AutoClassify` can be disabled.
- Exact rules support:
  - `exclude|base_item_string_id`
  - `tag|base_item_string_id|TAG1,TAG2`
- Rules override automatic classification.
- Persistence file: `profession_gear_affixes.tsv`
- Log file: `ProfessionGear.log`

### Build/package
- `build_portable.bat`: VS2010/Kenshi SDK DLL build.
- `run_tests.bat`: SDK-independent core test build/run.
- `package.bat`: copies built DLL/config/rules/RE_Kenshi manifest/mod.info into project-local package output only.
- Current DLL build previously completed with `BUILD OK`.
- Export check previously confirmed undecorated `startPlugin`.
- Core tests previously printed `ProfessionGearCore tests passed`.
- Package previously completed with `PACKAGE OK`.

### Documentation/tests
- `README.md`
- `TEST_PLAN.md`
- Test plan currently has 160 numbered tests spanning build/core, hook safety, per-instance identity, effective stats, crafting, NPC context, specialist packs, persistence, tooltip/UI, compatibility and stress/performance.
- Existing `tests\test_profession_gear.cpp` covers only a subset of the 160 plan and needs expansion.

## Important gaps found during resume audit

1. **Automated test coverage is incomplete.**
   The 160-case plan exists, but the SDK-independent executable currently tests only basic classification, tiers, deterministic rolls, serialization and aggregation.

2. **Runtime architecture still polls loaded characters every second.**
   Original design prefers event-driven item/equipment/inventory hooks and cached character aggregates. Current stat path scans the character inventory on every hooked stat read to sum equipped affixes. This should be hardened/cached before claiming the full runtime implementation is complete.

3. **General utility progression is incomplete.**
   Athletics/Perception/Stealth are present as stat affixes and specialist pack weight exists, but explicit generalized movement-speed/carry-efficiency/encumbrance affix types are not yet modeled independently.

4. **Specialist backpack stacking is not implemented.**
   Category-specific weight reduction exists. The design also calls for stronger specialist stacking where feasible. Need decide safe implementation without touching installed FCS.

5. **No new FCS content has been authored.**
   This is intentional so far because the user prohibited applying the mod to the game. The runtime system can augment existing/third-party items via classification/rules. A true FCS package with new tool/clothing/backpack records would require either an offline-safe FCS workflow or later authorized work in the Kenshi mod environment. Do not silently touch the game directory.

6. **Game-facing behavior is compile-validated, not live-validated.**
   No Kenshi runtime hook or save/load test has been executed because installation is explicitly prohibited.

7. **Stable item-handle persistence remains an in-game unknown.**
   Sidecar persistence uses `Item::getHandle().toString()`. It must be proven through save/load, transfer, stream-out/in and import once game testing is authorized.

8. **Job code-path coverage remains an in-game unknown.**
   Hooking `CharStats::getStat` compiles, but it must be proven that Farming/Labouring/etc. production calculations use this getter rather than raw fields in all important paths.

## Current task from Shay

Continue building the full mod without installing/applying it to Kenshi. Add/complete a full test plan using the existing testing framework. Maintain this ACTIVE_CONTEXT.md every turn with:
- what was inspected,
- what changed,
- test/build status,
- blockers/unknowns,
- exact next work.

## Work planned next

1. Inspect existing KenshiModding automated testing framework and reuse its conventions where practical.
2. Expand core representation to support utility effects beyond profession stat-percent affixes, especially carry/encumbrance/movement/logistics where they can be tested offline.
3. Replace hot-path inventory rescans with cached equipment aggregates and add event/inventory invalidation hooks where SDK symbols permit.
4. Add specialist pack stacking behavior if a safe runtime mechanism exists.
5. Expand SDK-independent automated tests substantially so the plan is backed by executable coverage.
6. Add static symbol/build validation scripts for required Kenshi hook exports.
7. Re-run all offline tests/build/package.
8. Update this context with exact results.
9. Do NOT install the package into Kenshi.

## Notes for next agent

- Preserve C++14/VS2010 compatibility.
- Follow existing STOBE build/toolchain patterns.
- Do not assume CMake is on PATH; the portable batch build is the known-good route.
- Avoid touching unrelated repo files.
- Build success does not equal in-game success.
- Do not state that live hooks, item handle persistence, job calculations or UI are proven until the mod is actually authorized for installation and tested.


---

## Turn update — 2026-10-02 continuation after timeout

### Resume audit performed
- Confirmed the prior ProfessionGear implementation and package were intact.
- Confirmed initial implementation commit `b0c29f1` exists.
- Reviewed the full original profession-gear design context again.
- Reviewed the existing STOBE automated test framework and its game-thread scenario philosophy.
- Confirmed this mod is still NOT installed/applied to Kenshi.

### Changes made this turn

1. **Created this ACTIVE_CONTEXT.md** as the mandatory live handoff file.
2. **Moved effective-stat math into the testable core** via `EffectiveStatValue(...)`.
3. **Moved specialist-pack item weight classification into the testable core** via `SpecialistPackItemWeightMultiplier(...)`.
4. **Added per-character equipped-bonus caching**:
   - cache key: character handle serial,
   - cached value: profession-stat -> total equipped affix percent,
   - `CharStats::getStat` now reads the cache instead of rescanning the whole inventory each stat query.
5. **Added inventory event refresh hooks**:
   - `Inventory::_sectionAddItemCallback`
   - `Inventory::_sectionRemoveItemCallback`
   - `Inventory::_sectionUpdateItemCallback`
   These rebuild the affected character's cached profession aggregate after the original callback.
6. The existing once-per-second loaded-character scan remains intentionally as a discovery/safety fallback for NPC initialization/stream-in and unknown equipment lifecycle cases.
7. Removed duplicated specialist-pack weight matching logic from the plugin; the core is now the single source for that behavior.
8. **Expanded offline executable coverage from a small smoke suite to 5,135 checks**, including:
   - exact quality boundaries,
   - tier range/chance monotonicity,
   - classification for every currently modeled item family,
   - override/exclusion precedence,
   - allowed-stat pools,
   - effective-stat base/unmodified/cap/floor behavior,
   - every specialist pack weight family and unrelated-item negative cases,
   - deterministic/instance-varying rolls,
   - stackable/disabled/zero-chance handling,
   - high-tier/max-affix behavior,
   - serialization validation,
   - aggregation,
   - RNG bounds/distribution sanity,
   - hash determinism,
   - profession-stat enum recognition.
9. **Added `verify_sdk_symbols.ps1` and `verify_offline.bat`**.
   It checks all current hook symbols against `C:\StobeBuild\sdk\KenshiLib.lib` and checks the built DLL export table for `startPlugin`.
10. Updated README and TEST_PLAN to describe current cache behavior and offline validation commands/results.

### Validation results this turn

- `run_tests.bat`:
  - **PASS**
  - `ProfessionGearCore tests passed: 5135 checks`
- `build_portable.bat`:
  - **PASS**
  - `BUILD OK`
- `verify_offline.bat`:
  - **PASS**
  - 13/13 checks
  - verified:
    - PlayerInterface::update
    - CharStats::getStat
    - CraftingBuilding::addFinishedCraftItem
    - Inventory::getTotalWeight
    - Inventory add/remove/update callbacks
    - base/Armour/Container/Crossbow/Sword tooltip symbols
    - DLL `startPlugin` export
- `package.bat`:
  - **PASS**
  - package remains project-local under `out\package\ProfessionGearProgression`

### Current implementation assessment

The runtime framework is now built far enough for pre-install status:
- generalized contextual classification,
- quality/tier rarity and magnitude,
- role-aware NPC rolls,
- slave/poor suppression,
- crafting integration,
- per-instance sidecar persistence,
- cached equipped profession stat effects,
- specialist category weight backpacks,
- tooltip hooks,
- explicit compatibility rules,
- offline build/symbol/core validation.

### Still intentionally unproven / blocked by "do not apply to game"

These cannot be truthfully completed without loading the plugin in Kenshi:
1. Whether item handles remain stable through real save/load, streaming, transfers and imports.
2. Whether every profession job path actually calls the hooked `CharStats::getStat` rather than reading raw struct fields.
3. Live tooltip dispatch/chaining and visual layout.
4. Live plugin-hook coexistence with STOBE and KenshiFP.
5. Live specialist backpack UI weight behavior.
6. NPC initialization timing across actual stream-in/out.
7. Long-duration performance in a real loaded world.
8. Exact game save/import policy for sidecar identity.

### Deliberate non-implementation: selective stacking
The design wants specialist backpacks to stack their intended cargo better. Kenshi exposes section-wide `setStackingBonus` / `getMaxStack` but those calls do not expose the current item category. Applying them would boost unrelated contents too, violating the specialist-pack design. No unsafe/general stacking override was added. Keep this as an in-game/FCS design item rather than pretending it is solved.

### FCS content status
No new FCS item records have been authored because doing so through Kenshi's mod environment risks crossing the user's explicit "do not apply the mod to the game yet" boundary. The native framework can operate on existing/third-party items through classification and exact rules. A later authorized phase can add new named profession tools/clothing/packs as FCS content.

### Exact next work
1. Run final repository/game-directory safety check.
2. Run `git diff --check`.
3. Stage/commit/push only `components/ProfessionGear` changes from this turn.
4. Keep all unrelated repo changes untouched.
5. Await explicit authorization before any install/live-game testing.
