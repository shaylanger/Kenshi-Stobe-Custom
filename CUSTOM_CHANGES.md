# Custom Changes vs Baseline Native Mods

This file is the high-level map of the native/game-side customizations. It is intentionally broad. Git history, test plans, and source diffs are the detailed record. Updated 2026-10-06 (after the KenshiFP decoupling, m49).

## Source baselines

- Native STOBE DLL source started from Dwemer-Dynamics/STOBE. The current live source tree was based on the 1.3.1-era upstream history (snapshot HEAD dedc49d before local uncommitted changes).
- KenshiFP started from linguine2552/KenshiFP (snapshot HEAD 200102f before local uncommitted changes).
- The PHP/server half of the project is tracked separately in shaylanger/StobeServer.
- Companion mods in their own repos: Kenshi Automation Harness (in-game test commands) and Profession Gear Progression (item affixes and profession gear bonuses).

## Who owns what (since m49)

- **Stobe.dll:** chat/LLM bridge, negotiation and deals, relationships (REL capture), NPC info panel, and all goal/action logic (work planner, task goals, goal panel, native actions). Works with KenshiFP absent.
- **KenshiFP.dll:** first-person mode only: camera/head/eye, mouse and cursor, FP targeting, manual FP combat (ranged + melee adapters, off by default), FP harness commands.

## Major native STOBE DLL changes

### Voice targeting and interaction modes
- Expanded push-to-talk handling with earlier target locking so the intended speaker stays stable through a request.
- Added target-by-name routing and separate normal/action/forced voice behaviors.
- Added additional voice/action plumbing used by the server's structured action system.

### Negotiation, deals and payments
- Real hand-overs for deals (items, Cats with `@topup`/`@exact` purse modes), surrender/truce deals, pay-later and breach detection backed by game evidence.
- Relationship-based shop pricing hook (`ShopPriceHook.h`, `ShopPricing.h`; interface in `pending-fixes/relationship-pricing-interface.md`).

### Combat/truce and event behavior
- Added custom combat/truce handling needed by negotiated ceasefires, including stand-down behavior for relevant faction allies.
- Added event prioritization/debounce and interruption hooks so urgent gameplay events can affect AI conversation/initiative more reliably.

### Stateful relationships (REL)
- Native social event capture (`SocialEventProtocol`, emitters for harm, KO, recovery, limb loss, death, slavery, carry, aid, meals, trade, witnesses) feeding the server's relationship ledger. Details: `docs/REL_ARCHITECTURE.md`.

### Goals and real-game actions (moved in from KenshiFP at m49, `src/StobeGoals.cpp`)
- Structured dialogue actions become real native game actions: equipment, weapon state, facing, medical/rescue, patrol/bodyguard, imprisonment/release, movement, repair/build, combat.
- Persistent single-NPC work planner: real production, inventories, buildings, jobs and recursive recipe chains, travel, quantity-based completion, stalls/blockers, persisted state.
- Persistent task goals: looting, storage/fetch/delivery, medical/battle cleanup, prisoners, stock maintenance, construction/repair, guard/wait/patrol, buying with quantity/Cats tracking and approval-aware fallback.
- Goal status/control files and the goal panel UI; log `stobe_goals.log`.

### UI
- NPC info panel (`\` hotkey / chat "Info" button): what the speaking character knows about the chat target, no LLM call. Details: `docs/NPC_INFO_PANEL.md`.

### Test bridge
- `StobeHarnessBridge.cpp` registers Stobe-only commands with the Automation Harness (`stobe_*`). The old built-in test inbox (TestAutomation.cpp) is gone.

## Major KenshiFP changes
- First-person camera, head/eye tracking (eye-drift fix), free cursor, FP targeting.
- Manual FP combat: ranged and melee adapters (off by default). Plan and evidence: `components/KenshiFP/docs/COMBAT_TEST_PLAN.md`.

## Equipment and UNEQUIP_ITEM safety
- Fixed server/native identity routing issues that prevented the correct actor from receiving an equipment action.
- Rejected unsafe Character-level/vtable unequip approaches after they caused NPC deaths during testing.
- Section-aware inventory transfer using the real equipped inventory section and a carried-inventory destination, with explicit verification/rollback.
- Dialogue/history must not claim an equipment action succeeded until live state supports it.

## Important design boundaries

- Real Kenshi state is the source of truth for physical actions; an NPC's words never prove a test passed.
- Do not reintroduce the old unsafe Character-level UNEQUIP_ITEM implementations.
- Persistent work/task goals are primarily single-NPC; multi-NPC delegation and broad world scouting were intentionally deferred.
- Native and server changes are tightly coupled. A feature may require both this repo and the shaylanger/StobeServer fork.
- Keep Stobe independent of KenshiFP (and the reverse): new gameplay/goal logic goes into Stobe, KenshiFP stays first-person only.

## Versioning workflow

This repository is the permanent history for the custom native/game-side setup. The active WSL source trees are still used for builds today, so refresh components/STOBE and components/KenshiFP from those live trees before committing a native change.
