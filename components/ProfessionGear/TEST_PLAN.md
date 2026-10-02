# Profession Gear Progression — Full Test Plan

**Status:** pre-install plan. The mod must not be copied into Kenshi until Shay explicitly authorizes installation/testing.

**Current offline automation:** `run_tests.bat` passes 5,135 core checks; `verify_offline.bat` passes 13 required SDK/export symbol checks; `build_portable.bat` and `package.bat` are green. These do not substitute for the in-game rows below.

## Test policy

- Automated tests are run by the agent whenever they can be proven from process output, logs, saved state or deterministic game state.
- Tests marked **SHAY** require visual/UI/game-feel confirmation only.
- Every in-game run archives `ProfessionGear.log`, `profession_gear_affixes.tsv`, `stobe.log` and `KenshiFP.log` before relaunch.
- Use a fixture save/copy. Never overwrite Shay's main save.
- Test vanilla Kenshi first, then coexistence with STOBE/KenshiFP, then third-party compatibility.
- A build pass is not an in-game pass.

## Section A — build/static/core tests

| ID | Automation | Test | Expected |
|---|---|---|---|
| 1 | AUTO | VS2010 portable compile of core | No compile errors |
| 2 | AUTO | VS2010 portable compile of plugin | No compile errors |
| 3 | AUTO | Link DLL with KenshiLib/MyGUI/Ogre | BUILD OK |
| 4 | AUTO | Export table | Undecorated `startPlugin` exists |
| 5 | AUTO | Core regression executable | Exit 0 |
| 6 | AUTO | Quality boundary table | Every boundary maps to intended tier |
| 7 | AUTO | Tier magnitude ranges | Higher tiers never use lower max range |
| 8 | AUTO | Tier affix chances | Non-decreasing from tier 0 through 6 |
| 9 | AUTO | Deterministic RNG | Same key+seed gives identical roll |
| 10 | AUTO | Instance variance | Distinct keys can produce distinct rolls |
| 11 | AUTO | Stackable exclusion | Stackable items receive no affix |
| 12 | AUTO | Serialization round-trip | Record survives serialize/parse identically |
| 13 | AUTO | Malformed sidecar rows | Rejected without crash |
| 14 | AUTO | Unknown stat ID | Rejected |
| 15 | AUTO | Exact exclusion precedence | Excluded ID never classifies |
| 16 | AUTO | Exact override precedence | Explicit tags replace automatic guess |
| 17 | AUTO | Farming classifier | Hoe/farm tools map only to farming pool |
| 18 | AUTO | Mining classifier | Pickaxe/mining tools map to labouring |
| 19 | AUTO | Research classifier | Lab/research items map to science/robotics |
| 20 | AUTO | Engineering classifier | Engineering/construction tools map correctly |
| 21 | AUTO | Robotics classifier | Robotics tools map correctly |
| 22 | AUTO | Medical classifier | Medical tools/clothes/packs map to Medic |
| 23 | AUTO | Weapon smith classifier | Smith item maps to Weapon Smithing |
| 24 | AUTO | Armour smith classifier | Smith item maps to Armour Smithing |
| 25 | AUTO | Crossbow smith classifier | Crossbow smith item maps correctly |
| 26 | AUTO | Cooking classifier | Cooking gear maps to Cooking |
| 27 | AUTO | Travel/scout classifier | Boots/scout gear maps Athletics/Perception |
| 28 | AUTO | Turret classifier | Turret gear maps Turrets/Perception |
| 29 | AUTO | Stealth classifier | Stealth gear maps Stealth/Lockpicking only |
| 30 | AUTO | Ordinary sword negative case | No Farming/Science/etc. affix |

## Section B — plugin startup/hook safety

| ID | Automation | Test | Expected |
|---|---|---|---|
| 31 | AUTO | Load plugin on fixture | Kenshi reaches loaded world |
| 32 | AUTO | Startup log | Version line written once |
| 33 | AUTO | PlayerInterface hook | Hook reports success |
| 34 | AUTO | CharStats getStat hook | Hook reports success |
| 35 | AUTO | Craft completion hook | Hook reports success |
| 36 | AUTO | Inventory weight hook | Hook reports success |
| 37 | AUTO | Tooltip base hook | Hook reports success or documented class-specific fallback |
| 38 | AUTO | Armour tooltip hook | Hook reports success |
| 39 | AUTO | Container tooltip hook | Hook reports success |
| 40 | AUTO | Crossbow tooltip hook | Hook reports success |
| 41 | AUTO | Sword tooltip hook | Hook reports success |
| 42 | AUTO | Idle for 10 minutes game time | No crash, no runaway log growth |
| 43 | AUTO | Pause/unpause/speed 1x/50x | No duplicate generation or instability |
| 44 | AUTO | Save while loaded | No crash/corruption |
| 45 | AUTO | Exit normally | Sidecar fully flushed |

## Section C — per-instance affix generation

| ID | Automation | Test | Expected |
|---|---|---|---|
| 46 | AUTO | First eligible equipped item observed | One record created |
| 47 | AUTO | Same item scanned repeatedly | Record never rerolls |
| 48 | AUTO | Unequipped eligible item in inventory | Record persists but bonus is not active |
| 49 | AUTO | Re-equip same item | Same roll becomes active |
| 50 | AUTO | Drop and pick up same item | Same instance retains same roll |
| 51 | AUTO | Transfer item to squadmate | Same item roll follows item |
| 52 | AUTO | Transfer item to storage then back | Same roll persists |
| 53 | AUTO | Two identical base items | Independent instance records |
| 54 | AUTO | Low quality sample set | Rolls stay in low-tier range |
| 55 | AUTO | High quality sample set | Rolls stay in high-tier range |
| 56 | AUTO | High-tier dual-affix sample | At most MaxAffixes; both contextual |
| 57 | AUTO | Ineligible generic item | No record or empty/no-affix record only |
| 58 | AUTO | Stackable resource | No affix |
| 59 | AUTO | Existing combat sword | No profession garbage affix |
| 60 | AUTO | Explicit rules exclusion | No affix despite matching name |
| 61 | AUTO | Explicit rules override | Correct pool despite misleading name |

## Section D — effective stat behavior

| ID | Automation | Test | Expected |
|---|---|---|---|
| 62 | AUTO | Farming gear equip | Effective Farming increases by rolled percent |
| 63 | AUTO | Farming gear unequip | Effective Farming returns exactly to baseline |
| 64 | AUTO | Labouring gear equip | Effective Labouring increases |
| 65 | AUTO | Science gear equip | Effective Science increases |
| 66 | AUTO | Engineering gear equip | Effective Engineering increases |
| 67 | AUTO | Robotics gear equip | Effective Robotics increases |
| 68 | AUTO | Medic gear equip | Effective Medic increases |
| 69 | AUTO | Weapon Smith gear equip | Effective Weapon Smithing increases |
| 70 | AUTO | Armour Smith gear equip | Effective Armour Smithing increases |
| 71 | AUTO | Crossbow Smith gear equip | Effective Crossbow Smithing increases |
| 72 | AUTO | Cooking gear equip | Effective Cooking increases |
| 73 | AUTO | Turret gear equip | Effective Turrets increases |
| 74 | AUTO | Athletics gear equip | Effective Athletics increases |
| 75 | AUTO | Perception gear equip | Effective Perception increases |
| 76 | AUTO | Stealth gear equip | Effective Stealth increases |
| 77 | AUTO | Lockpick gear equip | Effective Lockpicking increases |
| 78 | AUTO | Multiple same-stat pieces | Percent bonuses aggregate once |
| 79 | AUTO | Mixed profession pieces | Each stat receives only its own affixes |
| 80 | AUTO | `getStat(..., true)` path | Base/unmodified stat remains unchanged |
| 81 | AUTO | Earn XP while geared | Stored base skill rises normally; gear bonus is not baked in |
| 82 | AUTO | Remove all gear after XP | Base skill equals trained value, not boosted value |
| 83 | AUTO | Very high skill + gear | Effective stat clamps safely at configured hard cap |
| 84 | AUTO | Combat unrelated stats | Melee attack/defence/toughness unchanged by profession affixes |

## Section E — player crafting

| ID | Automation | Test | Expected |
|---|---|---|---|
| 85 | AUTO | Craft one eligible item | Roll created at finished-item hook |
| 86 | AUTO | Craft two identical same-tier items | Rolls may differ, both valid for tier |
| 87 | AUTO | Craft different-quality items | Higher-quality item uses stronger range |
| 88 | AUTO | Craft ineligible item | No profession affix |
| 89 | AUTO | Critical-success craft | Actual finished quality drives tier |
| 90 | AUTO | Crafter strong in matching profession | Matching contextual pool/chance applied |
| 91 | AUTO | Crafted item immediately equipped | Bonus active without relaunch |
| 92 | AUTO | Crafted item save/reload | Exact same roll retained |

## Section F — NPC context and loot

| ID | Automation | Test | Expected |
|---|---|---|---|
| 93 | AUTO | Farmer with hoe/work gear | Farming-affix chance elevated |
| 94 | AUTO | Miner/labourer with pickaxe | Labouring-affix chance elevated |
| 95 | AUTO | Researcher with lab gear | Science/Robotics pool only |
| 96 | AUTO | Engineer | Engineering/Labouring pool only |
| 97 | AUTO | Medic | Medic pool only |
| 98 | AUTO | Smith | Relevant smith pool only |
| 99 | AUTO | Cook | Cooking pool only |
| 100 | AUTO | Turret operator | Turrets/Perception pool only |
| 101 | AUTO | Generic combat soldier | Profession affixes rare/absent unless gear itself qualifies |
| 102 | AUTO | Slave sample | Special-affix frequency strongly suppressed |
| 103 | AUTO | Very low-skill poor NPC sample | Frequency suppressed |
| 104 | AUTO | High-skill specialist sample | Matching affix frequency elevated |
| 105 | AUTO | Kill/loot affixed NPC | Loot keeps same roll |
| 106 | AUTO | NPC streams out/in | Item does not reroll |
| 107 | AUTO | NPC save/reload | Item does not reroll |
| 108 | AUTO | Named/unique NPC | Stable behavior and no duplication |

## Section G — specialist backpacks

| ID | Automation | Test | Expected |
|---|---|---|---|
| 109 | AUTO | Ore pack + ore only | Matching contents receive strong effective weight reduction |
| 110 | AUTO | Ore pack + food | Food retains normal weight |
| 111 | AUTO | Ore pack mixed load | Only ore share gets specialist ratio |
| 112 | AUTO | Crop pack + Wheatstraw/Cactus/Greenfruit | Crop share reduced |
| 113 | AUTO | Construction pack + Building Materials/Iron Plates | Construction share reduced |
| 114 | AUTO | Medical pack + first-aid/splints/repair kits | Medical share reduced |
| 115 | AUTO | Tech pack + books/research/AI cores | Tech share reduced |
| 116 | AUTO | Trade pack + trade goods | Trade-good share reduced |
| 117 | AUTO | Generic backpack same contents | Vanilla total unchanged |
| 118 | AUTO | Empty specialist pack | Zero/vanilla weight path; no divide-by-zero |
| 119 | AUTO | Move item into/out of specialist pack | Weight recalculates immediately |
| 120 | AUTO | Nested/invalid ownership edge | Hook falls back to vanilla result |
| 121 | AUTO | Existing vanilla stack bonuses | Specialist calculation does not break stacking |
| 122 | AUTO | Existing backpack weight multiplier | Specialist ratio composes with vanilla multiplier |

## Section H — persistence/save/import

| ID | Automation | Test | Expected |
|---|---|---|---|
| 123 | AUTO | Save/reload same save | Exact rolls persist |
| 124 | AUTO | Restart Kenshi | Sidecar reloads |
| 125 | AUTO | Sidecar missing | Fresh records generate safely |
| 126 | AUTO | Empty sidecar | Safe startup |
| 127 | AUTO | Corrupt row among valid rows | Bad row ignored; valid rows load |
| 128 | AUTO | Duplicate key rows | Deterministic last/defined behavior; no crash |
| 129 | AUTO | Item destroyed | Stale sidecar row causes no runtime error |
| 130 | AUTO | Large sidecar 10k records | Startup remains acceptable |
| 131 | AUTO | Save copied under new name | Existing item handles checked for stability |
| 132 | AUTO | Kenshi import | Define/verify whether handles persist; document reroll policy if not |
| 133 | AUTO | New game | Old save's unreachable records do not affect new items |
| 134 | AUTO | Autosave/manual save cycling | No sidecar corruption |

## Section I — tooltip/UI

| ID | Automation | Test | Expected |
|---|---|---|---|
| 135 | SHAY | Hover affixed armour | Profession section visible and readable |
| 136 | SHAY | Hover affixed backpack | Profession section visible |
| 137 | SHAY | Hover affixed weapon/tool | Profession section visible |
| 138 | SHAY | Hover non-affixed item | No empty/noisy profession section |
| 139 | SHAY | Dual-affix item | Both bonuses shown once |
| 140 | SHAY | Large/decimal roll | Formatting is clean |
| 141 | SHAY | Inventory/shop/loot tooltip contexts | No duplicate rows or layout corruption |

## Section J — compatibility/coexistence

| ID | Automation | Test | Expected |
|---|---|---|---|
| 142 | AUTO | STOBE + ProfessionGear loaded | Both initialize and remain functional |
| 143 | AUTO | KenshiFP + ProfessionGear loaded | Both initialize and remain functional |
| 144 | AUTO | STOBE + KenshiFP + ProfessionGear | No hook-chain crash |
| 145 | AUTO | Existing mod-added hoe | Auto-classifies and rolls |
| 146 | AUTO | Existing mod-added goggles | Contextual classification only |
| 147 | AUTO | Existing mod-added backpack | Exact rule can specialize it |
| 148 | AUTO | Misleading third-party item name | Rules exclusion fixes false positive |
| 149 | AUTO | AutoClassify=false | Only explicit-tag items participate |
| 150 | AUTO | Plugin disabled via Enabled=false | Hooks remain safe and no new affixes/stat effects occur |

## Section K — performance/stability

| ID | Automation | Test | Expected |
|---|---|---|---|
| 151 | AUTO | 100 loaded characters | 1-second scan does not create visible hitch |
| 152 | AUTO | 300+ loaded characters | No runaway CPU/logging |
| 153 | AUTO | Inventory with many items | Stat lookup remains responsive |
| 154 | AUTO | Repeated stat queries | No recursive hook/deadlock |
| 155 | AUTO | Repeated tooltip opening | No memory growth/crash |
| 156 | AUTO | 50x speed work session | Stable for 30 real minutes |
| 157 | AUTO | Combat while profession gear equipped | No unrelated combat regression |
| 158 | AUTO | Rapid equip/unequip | No stale bonus |
| 159 | AUTO | Rapid inventory transfer | No stale weight/bonus |
| 160 | AUTO | Save during active crafting | Finished item rolls once only |

## Release gate

The mod is not release-ready until:
1. all AUTO tests that can run in the fixture environment pass,
2. all hook symbols are confirmed on the installed Kenshi build,
3. stable item identity survives save/reload and normal transfers,
4. job calculations demonstrably use the hooked effective profession stats,
5. specialist backpack totals are verified against vanilla UI weight,
6. coexistence with the current STOBE + KenshiFP setup passes,
7. SHAY tooltip/UI rows 135–141 are accepted.

Any failure gets a bug number and a regression row before the fix is considered complete.
