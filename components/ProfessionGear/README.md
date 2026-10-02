# Profession Gear Progression

Standalone RE_Kenshi plugin that adds contextual profession-equipment progression to Kenshi.

## What it does

- Classifies existing vanilla and mod-added equipment by profession context.
- Rolls per-instance profession affixes using item quality/tier.
- Applies profession bonuses at `CharStats::getStat` without modifying base skills or XP.
- Caches equipped profession aggregates per character; inventory add/remove/update callbacks refresh the cache, with the 1-second loaded-character sweep retained as discovery/safety fallback.
- Gives player-crafted items their roll at `CraftingBuilding::addFinishedCraftItem`.
- Uses the owning NPC's strongest profession skills as role context.
- Heavily suppresses special gear rolls for slaves/very low-tier NPCs.
- Persists item-instance rolls in `profession_gear_affixes.tsv`.
- Adds profession lines to tooltips for supported equipment classes.
- Supports exact item overrides and exclusions in `ProfessionGear.rules`.
- Adds category-specific weight specialization for ore, crop, construction, medical, trade and tech packs.

## Supported profession stats

Labouring, Science, Engineering, Robotics, Weapon Smithing, Armour Smithing,
Crossbow Smithing, Medic, Turrets, Farming, Cooking, Athletics, Swimming,
Perception, Stealth, Assassination, Lockpicking and Thievery.

## Build

Use the same VS2010/Kenshi SDK toolchain as STOBE:

```
build_portable.bat
run_tests.bat
verify_offline.bat
```

Output:
`out\ProfessionGearProgression.dll`

The portable build uses:
- `C:\StobeBuildTools` VS2010/SDK 7.1 toolchain
- `C:\StobeBuild\sdk`
- `C:\StobeBuild\boost`

## Packaging

Run `package.bat` after a successful build. It creates:

`out\package\ProfessionGearProgression\`

Nothing in the build or package scripts copies files into Kenshi.

## Runtime files

- `ProfessionGear.ini`: global tuning.
- `ProfessionGear.rules`: exact compatibility overrides/exclusions.
- `profession_gear_affixes.tsv`: generated per-instance persistence sidecar.
- `ProfessionGear.log`: startup/hook diagnostics.

## Rules syntax

```
exclude|some_mod_item_string_id
tag|some_mod_hoe_string_id|TOOL_FARMING
tag|some_mod_research_outfit|BODY_RESEARCH,HEAD_RESEARCH
tag|some_mod_ore_pack|PACK_ORE
```

Explicit rules beat automatic name/category classification.

## Important implementation rule

The plugin changes effective stat reads only. It does not write equipment bonuses into
the stored base profession skill values. Unequipping the item therefore removes the
bonus without changing earned XP.

## Current validation boundary

The core logic and final DLL are built and tested without installing the mod.
All game-facing hooks require the in-game test plan before release because Kenshi ABI,
item identity persistence, tooltip dispatch and job-stat call paths can only be proven
inside the live game.
