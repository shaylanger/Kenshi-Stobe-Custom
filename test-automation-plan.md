# Testing without Shay: what's possible and the plan

Goal: Claude sets up and checks most test cases alone; Shay only loads the game once and does the few "eyes/ears" checks.

> **Update 2026-10-02:** the test inbox and the automation commands now live in the standalone
> Kenshi Automation Harness mod (`Kenshi-Automation-Harness/`, see its `AGENTS.md` and
> `docs/COMMANDS.md`); Stobe adds its commands (`stobe_say`, `stobe_state`, ...) through
> `StobeHarnessBridge.cpp`. `stobe-say`/`stobe-auto` keep working as before. The text below is the
> original plan.

## What exists already
- **Test inbox in Stobe.dll** (`stobe-say`), processed on the game thread: `say`, `speed`, `give_cats`, `give_item` (creates items with the game's own factory; proven), `ping`, `state`.
- `stobe-force-attack` (start a fight), goal status files, `KenshiFP.log`, `stobe.log`, server logs and the full LLM prompt logs.

## What the game lets us do (KenshiLib exports, all checked in the headers)
| Need | Game function |
|---|---|
| Load a known starting save | `SaveManager::load(name)` |
| Spawn an NPC / a whole squad (e.g. 4 Hungry Bandits) | `GameDataManager::getDataByName` + `RootObjectFactory::createRandomCharacter` / `createRandomSquad` |
| Move anyone anywhere | `Character::teleport` |
| Knock out / hurt / kill | `MedicalSystem::knockout`, `knockoutForceTimer`, `applyDamage` |
| Give or take items, fill a chest | `createItem` + `Inventory::addItem` (already used by `give_item`) |
| Make factions fight or stop | `getFactionByName` + `Faction::setRelation` |
| Hunger for meal tests | `MedicalSystem` hunger field (KenshiFP already reads it) |

## The plan, in 4 layers

### Layer 1: offline server replay (no game at all)
Most of tonight's dialogue bugs are server-side (95, 96, 97, 98, 99, 104, 105, 107). Recorded event streams (run 8 is now saved) are replayed into the **staging server** (`ss-merge`, separate test DB) and checked automatically:
- who each line is addressed to (bug 95); "we're done here" doesn't accept a deal (96);
- prompts contain gender (97), no `#HERIKA_NAME#` (107), knockout facts and no repeated "Initiated attack" spam (105);
- a 0-item loot report doesn't say "done" (104); surrender offers fire when a bandit is low (98).
Runs in seconds, after every fix, and never touches the live game or DB.

### Layer 2: in-game scenario commands (new inbox commands)
Add to the inbox: `load <save>`, `spawn <template> [n] [near <npc> | x y z] [faction]`, `teleport`, `ko`, `damage`, `kill`, `relation`, `hunger`, `fill_chest`. Then scripts that build each test case from a known save:
| Scenario | Built by Claude | Covers |
|---|---|---|
| `home-clean` | `load` Shay's clean Home save | work goals, meals, labels, patrol |
| `fight-surrender` | spawn 3 Hungry Bandits 30 m away, hostile; damage one to 30 % | surrender, offer caps, paid stand-down (54–56, 22–26) |
| `bodies` | spawn 2 bandits with weapons, kill them next to Malzin | loot (44, 45), dead roster |
| `no-food` / `food` | empty / fill the chests, set Malzin's hunger low | meals (50, 51) |
| `stranger` | spawn a non-faction NPC near Shay | order refusal (57–60) |
| `trader` | spawn a trader | buying (40, 41), seller name (bug 103) |
Each scenario ends with automatic checks (goal status, inventories, deal ledger, logs) and a pass/fail line. Safety stays: auto-pause on any attack on Shay/Malzin, and the game stays paused after an alert.

### Layer 3: screenshots for "Shay looks" rows
A screenshot of the Kenshi window (PowerShell, no extra install) lets Claude check the job list, goal label and FP info panel itself (tests 47, 48, 67–69).

### Layer 4: what still needs Shay
- Launching Kenshi and loading the first save (and the "go").
- Sound quality and "does it feel right" (voice volume/fade, overall play feel).
- Approving DLL installs (Kenshi closed).

## Cost and order
1. Layer 1 replay harness: about one session. Biggest win: catches the bugs that ruined tonight's fight, without the game.
2. Layer 2 commands `load`, `spawn`, `ko`/`damage`/`kill`, `teleport`: about one session in Stobe.dll; scenarios after.
3. Layer 3 screenshots: small.

## Risks
- Game calls must run on the game thread with the crash guard (the inbox already does this); new commands are tried first on a throwaway save.
- Spawn templates need exact game names (looked up once and kept in a table).
- Test commands only work while the inbox is switched on (`stobe-say on`), so normal play can't trigger them.
