[Reading 1229 lines from start (total: 1229 lines, 0 remaining)]

# Kenshi Generalized Equipment & Profession Progression Mod
## Unified Design + Feasibility Context
**Prepared:** 2026-10-02  
**Status:** Research/design only. No implementation has been performed.  
**Intended use:** Handoff/context file for a future implementation agent.

---

# 1. Core idea from Shay

The big-picture goal is to extend Kenshi's existing combat-equipment progression into an **all-around equipment progression system**.

Kenshi already makes combat equipment meaningful:
- weapons have types, manufacturers/qualities, damage, weight, skill modifiers, etc.
- armour has quality and combat/mobility/stealth modifiers
- different equipment supports different combat builds

The proposed mod should make non-combat roles feel similarly deep, **while also broadening equipment progression in general beyond Kenshi's current narrow set of combat modifiers**.

This document now deliberately combines the original profession-tools idea and the later **Generalized Equipment & Profession Progression** idea into one mod. They are not separate projects. The profession system is the main use case, while the generalized equipment system is the underlying framework that lets any sensible item category participate.

A character should be able to have a real **profession gear build**, not merely a high base skill. At the same time, ordinary gear should be able to vary in more meaningful ways when the modifier makes sense for that item. Examples include boots that improve movement, load-bearing equipment that helps with encumbrance, specialist packs that excel at particular cargo, or protective/precision gear that improves an appropriate skill.

The target is therefore broader than "farming tools":
- profession tools and clothing are one branch,
- general utility/mobility/logistics equipment is another,
- combat equipment can remain mostly within Kenshi's existing combat logic but may participate in the same quality/random-roll framework where appropriate,
- all branches share the same contextual classification, quality, rarity, crafting, NPC-generation and per-instance-roll systems.

Examples:
- Labourer/miner: pickaxe + work goggles + work hat/gloves/boots + ore pack
- Farmer: hoe + straw hat + work clothes + crop pack
- Researcher: lab coat + glasses/goggles + precision/science tool
- Engineer: tool belt, protective goggles, engineering clothing/tool
- Medic: medical coat, field pack, gloves
- Smith: apron, protective gear, smithing hammer/tool
- Hauler: boots, harness, specialist backpack
- Cook: apron/headwear/tool
- Robotics specialist: tool/visor/gloves
- Turret operator/ranger/scout, etc.

This is NOT intended to be simply "add ten new items."

It is intended to create a broad progression layer where:
1. gear can improve the job a character is built for,
2. better gear/quality creates further progression,
3. gear found on NPCs makes sense for that NPC,
4. crafted equipment can roll different values,
5. compatible existing/mod-added items can receive contextual modifiers without needing a compatibility patch for every mod,
6. not every eligible item has a modifier,
7. modifiers have contextual randomness rather than nonsense random affixes.

---

# 1.1 Unified scope: profession progression + generalized equipment progression

The complete mod should be thought of as an **equipment progression framework for the whole game**, with profession gear as the largest missing category in vanilla Kenshi.

It should support four broad families:

### A. Profession effectiveness
Equipment that helps a character perform a job:
- Farming
- Labouring / mining
- Science / research
- Engineering / construction
- Robotics
- Medicine
- Cooking
- Weapon / armour / crossbow smithing
- Turrets
- other sensible profession skills

### B. Mobility and physical utility
Equipment whose purpose is not a profession skill but changes how the character operates:
- Athletics / movement speed
- encumbrance handling
- effective carrying / hauling support
- swimming
- stealth / infiltration where contextually appropriate
- perception / scouting where contextually appropriate

Examples:
- running/travel boots may improve movement or Athletics
- a load-bearing harness may reduce the effect of carried weight
- a scout hood or goggles may support Perception
- a specialist climbing/travel item could support movement-oriented play if the underlying Kenshi mechanics can be hooked safely

### C. Logistics and storage specialization
Backpacks and containers should have niches rather than only a generic "bigger is better" progression:
- ore/mining packs
- crop/farming packs
- construction-material packs
- medical packs
- technology/research packs
- caravan/trade packs

A specialist pack should outperform a generic backpack for its intended cargo while being less universally useful.

### D. Contextual item individuality
Two copies of the same base item do not have to be mechanically identical.

The generalized framework should allow:
- no affix at all,
- one coherent affix,
- rare higher-tier items with multiple coherent affixes,
- quality-dependent ranges,
- source-dependent rarity,
- NPC-role-dependent rolls,
- player-crafted rolls,
- support for vanilla and third-party mod items.

This should **not** become unrestricted random loot. The system must know what an item is for before deciding what it can roll.

---

# 1.2 One shared progression loop

The merged concept should create one consistent loop across professions and general equipment:

```
character role / item purpose
        -> eligible item category
        -> quality/tier
        -> chance of modifier
        -> contextual modifier pool
        -> per-instance roll
        -> visible tooltip
        -> real in-game effect
        -> persistence through save/load/trade/equip
```

Examples:
- farmer + hoe + straw hat -> Farming-focused possibilities
- miner + pickaxe + work goggles + ore pack -> Labouring/logistics possibilities
- researcher + lab coat + visor -> Science/Robotics possibilities
- courier + boots + load-bearing pack -> Athletics/encumbrance possibilities
- generic sword -> combat-relevant possibilities only; never Farming or hauling

The same framework should power all of these rather than implementing each profession as an unrelated special case.

---

# 2. Important examples / intended behavior

## 2.1 Labouring

A pickaxe could improve Labouring.

Example concept only:
- crude/shoddy pickaxe: small possible Labouring bonus
- standard: larger range
- high/specialist/masterwork/etc.: progressively better range
- top-end tool quality could be analogous to high weapon/manufacturer progression

A labourer might also wear:
- goggles
- miner's/work hat
- gloves
- boots
- specialist ore backpack

The final "labourer build" could get meaningful benefit from several pieces, balanced by slots/opportunity cost.

## 2.2 Research

Possible role gear:
- lab coat
- research glasses/goggles
- precision gloves
- handheld instrument/tool in weapon/tool slot
- research satchel

Possible effects:
- Science
- Robotics
- Engineering
- research/production speed if implemented as a separate effect

## 2.3 Farming

Kenshi/mods already contain hoes, so existing hoe-like items should be eligible.

Possible role gear:
- hoe
- straw hat
- work gloves
- field boots
- crop backpack

Possible effects:
- Farming
- job/production efficiency where technically appropriate

## 2.4 General equipment variety

The system should not be limited to profession stats.

Context-appropriate equipment could also affect:
- Athletics / movement speed
- encumbrance/carrying
- Stealth
- Dodge
- Perception
- Medic
- Engineering
- Robotics
- Science
- Labouring
- Farming
- Cooking
- Weapon Smith
- Armour Smith
- Crossbow Smith
- Turrets
- Swimming
- Assassination / lockpicking / thievery where appropriate
- possibly job-specific speed/effectiveness if separate from the displayed skill

Example:
- boots may reasonably roll movement/Athletics effects
- a hauler harness/backpack may improve effective carry weight
- a straw hat might improve Farming
- a research visor might improve Science
- a sword should NOT randomly roll Farming, carrying, or movement affixes merely because it is equipment

The rule is **context first, randomness second**.

---

# 3. NPC equipment generation requirement

NPC equipment should reflect the NPC rather than receiving random affixes blindly.

Examples:
- slave / extremely poor NPC:
  - often no profession bonuses at all
  - likely low-quality or ordinary gear
- Holy Nation farmer:
  - could spawn with a hoe that has a Farming modifier
  - could have a straw hat/work clothing with a Farming modifier
- miner/labourer:
  - may receive a labouring tool, goggles, ore pack
- researcher:
  - may receive science/research appropriate clothing or tool
- smith:
  - smithing-related apron/tool/protection
- elite or wealthy profession NPC:
  - better chance at higher-quality profession gear
- generic combat NPC:
  - should mostly retain combat-relevant gear and should not get nonsensical profession affixes

The system should consider some combination of:
- character template/base data
- faction
- NPC stats
- occupation/job/AI packages where readable
- equipment type
- item name/category
- quality/tier
- economic/social tier
- existing equipment
- possibly location/faction flavor

FCS already supports:
- character base stat packages
- randomized stats
- armour quality chances
- weapon lists
- weapon manufacturer/"weapon level" probabilities

This means Kenshi already has useful context for distinguishing a Holy Nation farmer from a slave or soldier.

---

# 4. Specialized backpacks

This part is especially feasible because Kenshi already implements the core mechanics.

The local Kenshi SDK shows that an InventorySection has:
- `weightMultiplier`
- `setWeightMultiplier(float)`
- `stackingBonusMin`
- `stackingBonusMult`
- `setStackingBonus(int, float)`
- limited-slot/item compatibility support

Existing backpacks already use weight reduction and stacking bonuses.

Desired extension:
- Ore Pack
  - better stacking for ore/resource items
  - stronger effective weight reduction for ore than a generic pack
- Crop/Farm Pack
  - better stacking/weight treatment for Wheatstraw, Cactus, Greenfruit, etc.
- Construction Pack
  - specialization for Building Materials / Iron Plates
- Medical Pack
  - specialization for medical supplies
- Trade/Caravan Pack
  - broad trade-good specialization
- Research/Tech Pack
  - books, engineering research, ancient science books, AI cores, components, etc.

Important distinction:
Kenshi's native backpack section has a general weight multiplier and general stack multiplier. **Per-item-category weight reduction inside the same bag is not obviously exposed as an FCS field.**

Therefore:
- generic backpack weight reduction + stacking can be pure/native Kenshi behavior
- "ore weighs 80% less, but food only 40% less in this same bag" likely needs a runtime plugin hook
- selective stack compatibility may also need runtime work depending on how restrictive the desired behavior is

The SDK makes this technically plausible because inventory sections and contained items are directly accessible.

---

# 5. Quality / tier progression

The desired profession gear should mirror the satisfying progression of weapons/armour.

The exact naming system is undecided. It does not have to literally use Edgewalker names for a hoe, but there should be meaningful tiers.

Potential conceptual progression:
- crude / makeshift
- shoddy
- standard
- high
- specialist
- masterwork
- elite / ancient / industrial / master-crafted equivalents

The important part is:
- higher quality raises the possible affix range
- quality should influence price and rarity
- NPC economic/profession tier should influence what they get
- player crafting skill should influence what can be produced

---

# 6. Random values within each tier

This is a core requirement.

The bonus should NOT be one fixed number per quality.

Example only:
- two Shoddy hoes are crafted
- Hoe A: +5% Farming
- Hoe B: +8% Farming

Both are valid Shoddy rolls.

Similarly:
- not every hoe must have a Farming affix at all
- some may have one
- some may have a weaker/stronger roll inside the allowed tier range
- later tiers have better ranges and/or better chance of receiving useful affixes

The system should support:
- tier-specific min/max ranges
- tier-specific affix chance
- potentially affix count limits
- weighted affix selection
- contextual affix pools

Example design:
```
Hoe:
  allowed:
    Farming
    Labouring (small chance, if desired)
    Athletics penalty/bonus (rare/contextual)
  forbidden:
    Heavy Weapons
    Crossbows
    Assassination
    Carry Weight unless tool design specifically warrants it
```

The exact numbers should be tuned later. Current percentages are only examples.

---

# 7. Player crafting requirement

When an eligible item is crafted:
1. Kenshi determines its normal resulting quality/tier using its own crafting system.
2. The profession gear system reads the actual finished quality.
3. It rolls eligible modifiers from the range allowed for that quality.
4. That individual item keeps those rolled values.

Example:
```
Player crafts two nominally Shoddy hoes.

Hoe #1:
Farming +5%

Hoe #2:
Farming +8%
```

The local SDK provides an excellent native hook point:
- `CraftingBuilding::addFinishedCraftItem(Item* what)`
- `CraftingBuilding::whosCrafting`
- `CraftingItem::criticalSuccess`
- final `Item*` exists at that point

This suggests an implementation can wait until Kenshi has produced the real item and its real quality, then assign/initialize the affix.

For weapons specifically, Kenshi already varies crafted quality/model based on skill/manufacturer rules. External FCS research also confirms weapon crafting quality is already variable rather than a single fixed result.

---

# 8. What Kenshi already exposes natively

Local SDK inspection on Shay's machine confirms:

## Item instances
`InventoryItemBase` contains:
- `quality`
- `weight`
- `manufacturerData`
- `materialData`
- quantity
- inventory/equipped state
- save/load/serialization functions

`Gear` contains:
- per-instance level
- `level_0_100`
- crafter
- player-crafted detection
- normal serialization

This is very useful because individual equipment pieces already have instance-specific state and quality.

## Armour
Runtime `Armour` instances already contain:
- athletics multiplier
- attack bonus
- defence bonus
- perception bonus
- combat speed multiplier
- stealth multiplier
- assassination multiplier
- dexterity multiplier
- damage multiplier
- dodge multiplier
- unarmed bonus
- ranged skill multiplier
- weather protection

This confirms Kenshi already treats equipped gear as a source of runtime stat modifiers.

## Backpacks / containers
`ContainerItem` and `InventorySection` expose:
- athletics multiplier
- weight multiplier
- combat speed multiplier
- combat skill bonus
- stealth multiplier
- inventory `weightMultiplier`
- stack bonus minimum/multiplier

## Character stats
`CharStats` exposes the full profession stat set, including:
- STAT_LABOURING
- STAT_SCIENCE
- STAT_ENGINEERING
- STAT_ROBOTICS
- STAT_SMITHING_WEAPON
- STAT_SMITHING_ARMOUR
- STAT_MEDIC
- STAT_TURRETS
- STAT_FARMING
- STAT_COOKING
- STAT_ATHLETICS
- STAT_SWIMMING
- STAT_PERCEPTION
- etc.

Important runtime functions include:
- `CharStats::getStat(StatsEnumerated, bool unmodified)`
- `CharStats::getStatMultiplier(StatsEnumerated)`
- `CharStats::getStatRef(...)`
- GUI bonus/penalty functions
- `setEquipmentStatBonuses(...)`

However, vanilla `setEquipmentStatBonuses` only exposes the normal vanilla armour-related set (Athletics, combat speed, attack/defence, stealth, etc.). It does **not** include Farming/Labouring/Science/etc.

That means arbitrary profession-stat equipment bonuses probably need a runtime extension rather than simply filling an existing vanilla armour field.

## Crafting
SDK exposes:
- `CraftingBuilding::addFinishedCraftItem(Item*)`
- crafter identity
- critical success
- player-crafted weapon level logic
- final item objects

## Item creation / NPC equipment
SDK exposes:
- `RootObjectFactory::createItem(...)`
- `Character::generateWeapon(GameData*, GameData* manufacturer)`
- character inventory
- equipped weapons/armour
- equip/unequip functions
- item handles

This makes spawn-time/post-spawn affix initialization feasible.

---

# 9. Pure FCS feasibility

Decided: standalone RE_Kenshi plugin + optional FCS content (section 10); the pure-FCS analysis was removed 2026-10-06; the
rationale is in section 10.

# 10. Recommended architecture

## Standalone RE_Kenshi plugin + optional FCS content

Recommended mod concept name placeholder:
**Profession Gear Progression** / **Wasteland Professions** / TBD.

Structure:
```
Kenshi mod
|
+-- small FCS layer
|   +-- optional new tools
|   +-- profession backpacks
|   +-- new profession clothing where useful
|   +-- recipes/blueprints/vendors
|
+-- standalone RE_Kenshi plugin DLL
    +-- discover existing/mod-added items
    +-- contextual item classification
    +-- generate affixes
    +-- persist per-instance affixes
    +-- apply equipped bonuses
    +-- modify profession effective stats
    +-- specialized backpack behavior
    +-- NPC spawn/context rules
    +-- crafting-roll integration
    +-- tooltip display
```

It should NOT depend on:
- STOBE
- KenshiFP
- Shay's STOBE server
- any LLM
- any personal runtime state

It may depend on:
- RE_Kenshi / KenshiLib, as a declared framework requirement

This keeps it independently publishable.

---

# 11. Steam Workshop / Nexus feasibility

A native plugin does not prevent Workshop distribution.

Current RE_Kenshi ecosystem examples show DLL plugins distributed as normal Workshop mods. Users enable the mod in the Kenshi launcher and need RE_Kenshi/KenshiLib installed.

A typical plugin package can include:
- empty/minimal `.mod` so Kenshi recognizes the mod
- `RE_Kenshi.json`
- plugin DLL
- config/data files
- optional FCS data/assets

Nexus distribution can use the normal Kenshi `mods` folder structure.

Therefore the likely user-facing requirement would be:
> Requires RE_Kenshi (and whatever minimum KenshiLib version the plugin is built against).

This is still a standalone mod. It simply has RE_Kenshi as a framework dependency.

---

# 12. Compatibility with existing mods

This is one of the main reasons to prefer a runtime plugin.

Desired behavior:
- GenMod adds a hoe -> system sees/classifies the hoe and may affix it
- UWE adds work clothing -> system may classify relevant pieces
- another mod adds goggles -> system can potentially treat them as researcher/miner gear
- another mod adds backpacks -> system can consider them
- vanilla items work too

No direct modification of the third-party mod's source records should be required for common cases.

## Suggested classification system

Each item gets one or more semantic tags at runtime:
- TOOL_FARMING
- TOOL_MINING
- TOOL_RESEARCH
- TOOL_ENGINEERING
- TOOL_SMITHING
- HEAD_FARMING
- HEAD_MINING
- HEAD_RESEARCH
- BODY_RESEARCH
- BODY_SMITHING
- BOOTS_TRAVEL
- PACK_ORE
- PACK_CROP
- etc.

Classification should use strong signals first:
1. explicit config override by base item ID/stringID
2. native type/category/slot
3. weapon category where relevant
4. existing GameData fields/functions
5. known base-game item mappings
6. item name keywords as a fallback only

Never let name-keyword guessing override an explicit exclusion.

Example config:
```json
{
  "items": {
    "some_mod_item_string_id": {
      "tags": ["TOOL_FARMING"]
    }
  },
  "rules": {
    "name_contains": {
      "hoe": ["TOOL_FARMING"],
      "pickaxe": ["TOOL_MINING"],
      "lab coat": ["BODY_RESEARCH"]
    }
  }
}
```

This gives automatic compatibility while still allowing community patches/overrides for unusual mods.

---

# 13. Contextual affix pools

Randomness must operate only inside a valid semantic pool.

Example:

## Farming tool
Eligible:
- Farming
- small Labouring effect if thematically justified
- possibly work speed

Not eligible:
- Heavy Weapons
- Crossbows
- assassination
- random combat damage
- arbitrary run speed

## Research goggles
Eligible:
- Science
- Robotics
- Engineering
- Perception maybe, depending balance

## Travel boots
Eligible:
- Athletics
- movement-speed effect
- encumbrance-related benefit

## Ore pack
Eligible:
- ore/resource stack bonus
- ore-specific weight reduction
- Labouring/carry-related support if desired

## Sword
Keep combat pools:
- existing Kenshi combat properties
- possibly new combat-oriented affixes later

## Boots / travel gear
Eligible examples:
- Athletics / movement
- encumbrance-related support
- swimming or stealth only when the item concept justifies it

Not eligible:
- Farming simply because Farming exists as a stat
- random weapon-category bonuses on ordinary boots

## Load-bearing gear / harnesses
Eligible examples:
- reduced encumbrance effect
- carrying/hauling efficiency
- small Athletics trade-offs or benefits depending on design

## General rule for all existing/mod-added equipment
An item does not need to have been created by this mod to participate. If the runtime classifier can confidently determine its purpose, it may receive an appropriate progression roll. If classification confidence is poor, default to **no added modifier** rather than inventing one.

Do not let the generalized system turn every item into Diablo-style random loot.

Kenshi should still feel like Kenshi.

---

# 14. Affix occurrence / rarity

Not every item should be special.

Suggested model:
- ordinary low-tier NPC equipment: often no affix
- dedicated profession gear: better chance
- high-quality equipment: higher affix chance and/or stronger range
- exceptional/rare items: chance of multiple coherent bonuses
- slaves/poor NPCs: almost always mundane equipment
- specialist NPCs: increased relevant-affix chance

This keeps bonuses interesting and creates loot discovery.

A possible roll sequence:
```
1. Is item eligible?
2. Is this item excluded?
3. Determine semantic class.
4. Determine quality tier.
5. Determine source:
   - NPC spawn
   - vendor
   - loot
   - player craft
6. Roll whether an affix exists.
7. Select only from allowed contextual pool.
8. Roll magnitude within quality range.
9. Store affix on this item instance.
```

---

# 15. NPC-context generation

When an NPC first receives/generated equipment:

1. derive an NPC role profile
2. evaluate each eligible equipped/carried item
3. modify affix probability/pool based on role
4. roll once
5. persist result

Role inference candidates:
- strongest profession skills
- character template
- faction
- AI/jobs
- equipment itself
- economic tier / armour quality
- slave/prisoner status
- named/unique status
- vendor/profession context

Examples:

Holy Nation farmer:
```
role: FARMER
hoe:
  Farming affix chance = high
straw hat:
  Farming affix chance = moderate
boots:
  Farming/Athletics work affix chance = low
```

Slave:
```
role: SLAVE
global affix chance multiplier = very low
high-quality roll disabled
```

Tech Hunter researcher:
```
role: RESEARCHER/TECH
science/robotics gear chance = elevated
quality ceiling = higher
```

This can be implemented without editing every NPC if the plugin processes characters after their normal Kenshi equipment has been generated.

---

# 16. Applying profession stats safely

Recommended principle:
**Do not permanently write the equipment bonus into the character's base skill value.**

Bad approach:
```
equip +10 Farming hat
-> directly add 10 to character.farming
-> unequip subtract 10
```

Risks:
- save contamination
- double application
- incorrect XP behavior
- crashes/desync if item disappears
- interactions with injuries/race multipliers
- difficult compatibility

Preferred approach:
- maintain affixes on the item
- when Kenshi requests an effective stat, layer equipment contribution onto the effective result
- base stat/XP remains unchanged

Candidate hook area:
- `CharStats::getStat(StatsEnumerated, bool unmodified)`
- possibly `getStatMultiplier(...)`
- GUI stat bonus display functions as needed

Proof-of-concept requirement:
verify that the production/job code uses this same effective stat path for Labouring/Farming/Science/etc.

If some systems access the raw member directly, those systems may need individual hooks.

---

# 17. Percent vs flat stat bonuses

This is a design decision to make later.

Possible forms:

## Flat
`+8 Farming`

Advantages:
- easy to understand
- Kenshi already displays many skills numerically

Risk:
- disproportionately strong at low skill

## Multiplicative
`Farming +8%`

Could mean:
- effective skill * 1.08
or
- job speed * 1.08

Advantages:
- scales with trained character

Risk:
- harder to integrate cleanly with all systems/UI

## Mixed
Some items use:
- flat skill
- skill multiplier
- production speed
- carrying specialization

Recommendation for first prototype:
**choose one simple profession stat, probably Farming or Labouring, and prove a flat effective-stat bonus first.**
Then compare balance/behavior against percentage implementation.

The user's examples use percentages, but those were explicitly illustrative, not a locked decision.

---

# 18. Per-item random affix persistence

This is the most important unresolved engineering detail.

The SDK confirms item handles contain:
- type
- container
- containerSerial
- index
- serial
- string conversion
and Kenshi serializes item state.

Potential strategies:

## A. Sidecar registry keyed by stable item handle
Store:
```
item_handle -> affix set
```

Pros:
- no modification to Kenshi save format
- easy config/debug
- standalone

Need to verify:
- handle remains stable across save/load
- moving item between inventories
- dropping/picking up
- trading
- equipping
- stack split/merge
- crafting
- imports/new games

## B. Deterministic generation from stable item identity
Hash:
```
stable item identity + base item ID + mod seed
```

Pros:
- no large database
- reproducible

Cons:
- only works if identity is truly stable
- stack/copy behavior could produce collisions or changed rolls

## C. Hook Kenshi item serialization to embed custom data
Most integrated but highest risk and complexity.

Recommendation:
Start with **A or B**, prove handle stability, and avoid changing Kenshi's native save schema unless absolutely necessary.

A small sidecar save file under the mod's own folder is likely safest.

---

# 19. Item tooltip / user visibility

The player must be able to see what an item rolled.

Otherwise the progression system will feel invisible.

Desired tooltip example:
```
Industrial Pickaxe [High]
Labouring +11%
Carry Efficiency +4%

Profession Gear:
Mining
```

Potential native hook points already exist:
- item `getTooltipData1`
- item `getTooltipData2`

Need to append mod lines without replacing vanilla tooltip content.

For compatibility:
- call original tooltip function first
- append mod-owned lines
- avoid rewriting existing strings

Optional:
- distinct prefix/icon/text color if safely supported

---

# 20. Existing item quality behavior

External FCS research confirms:
- weapon manufacturers contain multiple possible models/quality levels
- NPC weapon quality can be chosen probabilistically through manufacturer/"weapon level"
- player weapon crafting already varies resulting quality
- armour NPC quality can also be probabilistic
- character records support random stat ranges

Useful implication:
profession affix strength can be derived from the **actual instantiated item's quality**, rather than inventing a completely separate quality system.

For non-Gear tools that do not naturally have a meaningful vanilla gear level:
- plugin may need its own internal profession-quality tier
- or the FCS item variants can provide tiers

Avoid forcibly mapping every object to weapon-quality names if it feels unnatural.

---

# 21. New tool slot issue

Kenshi weapon/gear slots are fixed.

A pickaxe/hoe/research instrument could be represented as:
- a weapon/tool held in an existing weapon slot
- an armour/accessory piece using an existing equipment slot
- a carried item whose bonus activates while in inventory
- a new FCS gear item that visually represents the profession

A completely new equipment slot is much more invasive.

For first implementation, use existing slots and/or "equipped/held tool" semantics.

Later possibility:
RE_Kenshi ecosystem has examples of inventory-section extensions, but a new dedicated equipment slot should not be part of the initial proof of concept.

---

# 22. Standalone vs existing Shay mods

This future project should be architecturally independent.

Do NOT put the feature inside:
- Stobe.dll
- KenshiFP.dll
- StobeServer

Instead use a new repo/project, e.g.:
```
C:\KenshiModding\ProfessionGear\
```
or another dedicated source tree.

It can reuse knowledge/patterns from the existing SDK/build setup, but not runtime dependencies on Shay's voice/LLM systems.

Benefits:
- publishable
- testable independently
- easier to disable
- safer compatibility
- cleaner open-source licensing
- no need for users to install STOBE

---

# 23. Compatibility / conflict strategy

Primary goal:
**avoid touching third-party FCS records whenever runtime augmentation is sufficient.**

Plugin should:
- read existing item base data
- attach its own runtime metadata
- hook effective stat calculation
- append tooltip information
- leave original stats/models/records intact

FCS layer should only define genuinely new content.

Potential conflicts:
- another native plugin hooking the same stat/tooltip/equipment functions
- mods that drastically rename/reclassify items
- total-conversion mods with unconventional item semantics
- mods that replace crafting systems

Mitigation:
- hook chaining/call-original correctly
- explicit include/exclude config
- user-editable semantic mappings
- debug command/log showing why an item was classified
- no assumptions based solely on English item names where a stable ID/rule exists

---

# 24. Performance considerations

The runtime system should NOT scan every item in the world every frame.

Event-driven preferred:
- item creation
- character initialization
- equipment change
- crafting completion
- inventory ownership change when relevant
- save/load
- tooltip requested

Cache:
```
item handle -> classification + affixes
character handle -> current equipment bonus aggregate
```

On equip/unequip:
- recompute that character's profession bonus aggregate

Then effective-stat reads are cheap:
```
base result + cached equipment bonus
```

---

# 25-27. Proof of concept, feasibility, risks

Done: the mod is built and every automated row passed in game (2026-10-06; PG repo `INGAME_STATUS.md`). The POC plan,
feasibility assessment and risk list were removed 2026-10-06.

# 28. Recommended design philosophy

- Kenshi first, loot-RPG second.
- Gear must make semantic sense.
- Special items should be uncommon enough to feel meaningful.
- Profession bonuses should create choices, not mandatory max-stat uniforms.
- Quality should matter, but skill training should still matter.
- A master farmer with ordinary tools should remain competent.
- A novice with elite gear should not instantly equal a veteran.
- Specialist packs should beat generic packs in their niche but be worse/less flexible elsewhere.
- NPC equipment should tell a story about the NPC.
- Do not give every object five random stats.
- Prefer one or two coherent modifiers over affix clutter.
- Existing/modded items should be supported without destructive FCS overrides.
- The mod is not only about job skills: sensible mobility, carrying, storage and utility progression are first-class parts of the same system.
- Item purpose should matter more than raw rarity. A rare farming tool should be excellent at farming, not randomly excellent at unrelated combat or travel stats.
- General-purpose gear and specialist gear should coexist. Specialist gear wins in its niche; generic gear remains useful because it is flexible.

---

# 29. Potential profession families for later

Not a commitment, but possible expansion families:

1. Farming
2. Labouring / mining
3. Research / science
4. Engineering / construction
5. Robotics
6. Medicine
7. Weapon smithing
8. Armour smithing
9. Crossbow smithing
10. Cooking
11. Hauling / logistics
12. Trade / caravan
13. Turret operation
14. Scouting / travel
15. Stealth / infiltration
16. Thievery / lockpicking
17. Assassination
18. Survival / exploration
19. Swimming / water travel
20. General workshop / production

Each needs its own sensible item classes and affix pools.

---

# 30-31. Research sources, recommendation for the implementation agent

Done: the mod was built as recommended (standalone plugin, no STOBE/KenshiFP dependency); sections removed 2026-10-06.
