# Custom Changes vs Baseline Native Mods

This file is the high-level map of the native/game-side customizations. It is intentionally broad. Git history, patch scripts, test plans, and source diffs are the detailed record.

## Source baselines

- Native STOBE DLL source started from Dwemer-Dynamics/STOBE. The current live source tree was based on the 1.3.1-era upstream history (snapshot HEAD dedc49d before local uncommitted changes).
- KenshiFP started from linguine2552/KenshiFP (snapshot HEAD 200102f before local uncommitted changes).
- The PHP/server half of the project is tracked separately in shaylanger/StobeServer.

## Major native STOBE DLL changes

### Voice targeting and interaction modes
- Expanded push-to-talk handling with earlier target locking so the intended speaker stays stable through a request.
- Added target-by-name routing and separate normal/action/forced voice behaviors.
- Added additional voice/action plumbing used by the server's structured action system.

### Test and automation bridge
- Added a test-inbox path that can submit text through the same chat path used after speech-to-text.
- Added test helpers for state inspection, Cats updates, and game-speed control used by automated regression runs.
- Added richer event/action logging so server decisions can be correlated with what actually happened in Kenshi.

### Combat/truce and event behavior
- Added custom combat/truce handling needed by negotiated ceasefires, including stand-down behavior for relevant faction allies.
- Added event prioritization/debounce and interruption hooks so urgent gameplay events can affect AI conversation/initiative more reliably.

## Major KenshiFP changes

### Generalized real-game action execution
- Expanded the STOBE-to-KenshiFP bridge so structured dialogue actions can become real native game actions instead of narration only.
- Added support/foundations for equipment, weapon state, facing, medical/rescue, patrol/bodyguard, imprisonment/release, movement, repair/build, combat, and related actions.
- Added native request/status handling used for deterministic server-side follow-up.

### Persistent work planner
- Added a single-NPC persistent production/gathering planner.
- Uses real Kenshi production, inventories, buildings, jobs, and dependency chains.
- Supports recursive resource/recipe resolution, travel to known destinations, quantity-based completion, stalls/blockers, and persisted state.

### Persistent task-goal engine
- Added broader autonomous tasks such as looting, storage/fetch/delivery, medical/battle cleanup, prisoners, stock maintenance, construction/repair, guard/wait/patrol, and goal controls.
- Added real trading/procurement support with quantity/Cats tracking and approval-aware purchase fallback.
- Added fixes for blocked goal resume, stored actor serials, base awareness, and returning to the player after goal completion.

### Equipment and UNEQUIP_ITEM safety
- Fixed server/native identity routing issues that prevented the correct actor from receiving an equipment action.
- Rejected unsafe Character-level/vtable unequip approaches after they caused NPC deaths during testing.
- Moved toward section-aware inventory transfer using the real equipped inventory section and a carried-inventory destination, with explicit verification/rollback.
- Preserved the rule that dialogue/history must not claim an equipment action succeeded until live state supports it.

## Project/test tooling

The C:\KenshiModding workspace contains the development process around these changes:
- CLAUDE.md with live paths, deployment rules, and test workflow.
- bug history and open/full test plans.
- automated stobe-say, session, reset, combat/deal, provider benchmark, and log tooling.
- patch scripts for the successive server, STOBE DLL, and KenshiFP regression rounds.
- archived test runs documenting failures and fixes.

The project has repeatedly used real in-game regression testing rather than treating successful LLM output as proof of gameplay success.

## Important design boundaries

- Real Kenshi state is the source of truth for physical actions.
- Do not reintroduce the old unsafe Character-level UNEQUIP_ITEM implementations.
- Persistent work/task goals are primarily single-NPC; multi-NPC delegation and broad world scouting were intentionally deferred.
- Native and server changes are tightly coupled. A feature may require both this repo and the shaylanger/StobeServer fork.
- Some paths remain actively tested. A source path being present does not guarantee every edge case has been verified in the current save.

## Versioning workflow

This repository is the permanent history for the custom native/game-side setup. The active WSL source trees are still used for builds today, so refresh components/STOBE and components/KenshiFP from those live trees before committing a native change. Long term, these tracked component copies can become the canonical source/build roots if desired.
