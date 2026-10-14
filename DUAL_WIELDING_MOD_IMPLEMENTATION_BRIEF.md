# Kenshi dual wielding: investigation and implementation brief

Research checkpoint: **2026-10-09**. Requested by Shay. This is a research/design brief, not an implemented mod or a live compatibility certification.

**Follow-up completed:** see “Follow-up static investigation” below for the pinned animation exporter/templates, body-harness audit, exact inventory distinctions, KEP source/hook findings and conservative scope defaults. No building or testing was performed.

## Outcome and recommended next action

True dual wielding is technically plausible through a native RE_Kenshi plugin plus animation/attachment work. Two downloadable implementations already ship native combat code. This moves the question beyond whether a second blade can be displayed. It does **not** prove either implementation works correctly with this workspace's current KenshiFP, KEP, animation packs, or save lifecycle.

**Evaluate Nitoryu alone first on a disposable fixture, then DualWieldCore alone, using the gates below.** Nitoryu has the strongest inspectable documentation, settings, and animation payload. DualWieldCore has promising per-blade combat instrumentation and could be closer to an alternating-attack design. Do not select a foundation until the strict slot rule and FP ownership tests pass. Never run the two candidates together.

Prefer a configuration/FCS overlay if an existing implementation can genuinely meet the requirements. Otherwise obtain upstream source/permission for a narrow integration, or create an independent implementation from the engine interfaces described here. Do not plan on patching an opaque DLL as the maintained solution.

No custom dual wield mod, game installation, load-order edit, candidate launch, or balance patch was made during this investigation. Candidate files were downloaded into an inactive research directory. A live evaluation was not run: the shared game lock belonged to **fixer-pt30** at inspection, and another session was modifying KenshiFP. Do not steal that lock or treat this brief as authorization to overwrite their work.

An agent can start with the evaluation procedure and implementation work packages here without repeating the broad research. Dynamic compatibility, visual quality, damage correctness, and balance remain **explicit validation gates**; no document can honestly certify those without executing the game.

## User requirements and boundaries

| Requirement | Meaning |
|---|---|
| Two swords in the main weapon section | Both actual equipped item instances must be in the main/back section. Never infer this from primary-plus-secondary getters. |
| Automatic pairing | When exactly two eligible swords occupy that section, pair them. No third phantom item, inventory resize, or required click on a new dual wield button. |
| Secondary section excluded | One main sword plus one hip/secondary sword must remain ordinary single wielding. |
| Both swords matter | Render each actual blade, use its own quality, damage, category skill, weight, and reach when it strikes. |
| Situational tradeoffs | Better in some matchups, worse in others; not a universal damage, speed, defence, and initiative upgrade. |
| KenshiFP support | Manual attacks and RMB block must retain their current input ownership and native recovery rules. |
| Research before implementation | This task creates evidence and an actionable specification; it does not build the new mod. |
| Agent ownership | Coding, tooling, animation authoring, testing, and packaging can be agent tasks. Human aesthetic preferences and any author consent/account access remain separate. |

Unresolved choices are defaults for a future prototype, not approved user decisions: exact eligible weapon IDs, tuning curve, NPC rollout, new skill versus existing skills, and whether every click alternates hands or explicitly triggers a bounded combo.

The earlier conversation also identified FP input issues: RMB can initiate move-to-point while blocking; LMB attacks can fail against already-engaged targets; initiating “Attack Unprovoked” immediately alerts the NPC. These are related integration concerns, **not resolved dual wield requirements**. Do not silently add hostility/detection changes to this mod. Keep one input/combat owner and track those behaviours in the existing FP combat plan.

## Evidence discipline

Labels used below:
- **Observed:** file contents, binary payload, SDK declarations, or current source directly inspected.
- **Author documented:** behaviour/formula described by the candidate author; not reproduced here.
- **Inferred:** engineering implication of those observations.
- **Proposed:** our design recommendation, subject to runtime measurement and user tuning.
- **Unverified:** requires a live test or exporter proof.

Static DLL strings demonstrate included symbols/logging vocabulary, not that a feature always executes correctly. A Workshop description or changelog compatibility claim is not a passed test. No candidate source was found in the downloaded distributions. Public Nitoryu page says source will be published later; this is not an available source dependency.

## Workspace and version checkpoint

| Item | Inspected location/state |
|---|---|
| Windows machine | DESKTOP-JFLPK99; Remote Desktop Commander device 39a13270-d7ef-4497-a1b1-feb6780cf90b; RTX 5090 |
| Main workspace | C:\KenshiModding |
| Main repo snapshot | HEAD 1f63a936af22282dc0a850878c6cdb1d50d781ca at initial inspection; repository was already dirty |
| Game | D:\Steam\steamapps\common\Kenshi; Kenshi 1.0.65 x64 context |
| Loader, last installed log | RE_Kenshi 0.3.5; KenshiLib 0.5.0 |
| Live FP source | WSL distribution DwemerAI4Skyrim3, /root/KenshiFP |
| Live FP source snapshot | HEAD ad419c03908616f35cb0c57fc194a1e41f715464; dirty client/kenshifp_client.c, kfp_view.inc, kfp_viewmodel.inc at inspection |
| FP source copy | C:\KenshiModding\components\KenshiFP; a snapshot, not automatically the live source of truth |
| SDK | C:\StobeBuildTools\KenshiSDK\Include\kenshi |
| Other native source | /root/STOBE-src; Windows build tree C:\StobeBuild |
| Harness | C:\KenshiModding\Kenshi-Automation-Harness; read AGENTS.md and docs/COMMANDS.md before operating |
| Game lock | C:\KenshiTestRuns\game.lock; observed owner fixer-pt30; no candidate run attempted |
| Fixture policy | C:\KenshiTestFixtures; test only kah-* copies, never Shay's own save |

First read C:\KenshiModding\CLAUDE.md and testing\HANDOFF.md for current state. Recheck live git HEAD, dirty files, lock, installed DLL hashes, and load order before editing/launching. These are freshness checks, not a reason to repeat this investigation.

Relevant installed stack includes KenshiFP, Stobe, AutomationHarness, ProfessionGearProgression, KenshiExtensionPlugin (KEP), More Combat Animation, Great Anims Mod, Yet More Idle Animations, Immersive Non-Combat Animations, DodgeStrafe, Faster Stand-Up Animation, UWE, Kaizo, and the UWE animation/Kaizo patches. Test against the recorded actual order rather than assuming vanilla animations.

Observed KEP version: kep-core 1.2.0. Relevant enabled settings: fix_melee_combat_xp, fix_animation_override, fix_the_injury_calculation, change_armor_damage_reduction_order, fix_global_damage_multiplier, weapon_extension. combat_ex and combat_techniques_ex were disabled; fix_damage_calculation was 0 and fix_unarmed_block_chance false. Save the exact config in each future evaluation run. XP and damage hook cooperation matter even when “extended combat” is disabled.

## Downloaded, pinned candidate evidence

Local reference root: **C:\KenshiModding\tools\research\dual-wield-reference**.

Subfolders 3807103555 and 3812165089 contain the actual Workshop payloads. Files are not under the game's mods directory and are not enabled. A local .gitignore excludes all third-party payloads and logs; only the exclusion file is eligible for normal source control. Do not redistribute binaries or animation assets through our repo.

Also retained locally:
- manifest.json: relative paths, bytes and SHA256 values for downloaded files.
- dualwieldcore-static-strings.txt: filtered printable strings; inspection evidence, not decompiled source.
- nitoryu-male-skeleton-inspection.txt and nitoryu-female-skeleton-inspection.txt: serializer/bone/animation summaries.

Download method: official SteamCMD installer, anonymous login, workshop_download_item 233860 3807103555 and 233860 3812165089. Both reported successful downloads; directory contents and hashes were subsequently checked. SteamCMD's updater/shutdown returned an overall nonzero status, so download success was determined per item and by payload verification, not process status alone.

| Payload | Bytes | SHA256 |
|---|---:|---|
| 3807103555/DualWieldCore.dll | 3803648 | 945885C2EB885EB2724E552703973E93028EEDCCDD21D1191507874689F64A4E |
| 3807103555/DualWieldProbe.mod | 7163 | 15B3B69E5ED20C206806B0AFEE2339660736D5FB29049D7F84D4C66B2D5FA8D2 |
| 3812165089/Nitoryu.dll | 802816 | C26946DB6BB87A3C49AD61EAABAEECFC98A11ACF72AEBECAA1DCCE5C8DBFFEBF |
| 3812165089/Nitoryu.mod | 36679 | A160838CA25533E2EDA4B30CF3DFCE87A2C7430D4520DFDD3F5FB58FB3E020C5 |
| Nitoryu female skeleton | 1436539 | 5827BD14F844F30A5CD791FD428CB0FF7BE04C37706D70CAB1C8799C233FE32F |
| Nitoryu male skeleton | 1436206 | B90D4F2855437BAF526F5A82F8157DD0F53B8B78792AAC78EA266ABADDB58DC2 |

Future Workshop downloads may differ. Compare against these pins before relying on this assessment.

### Candidate A: DualWieldCore / DualWieldProbe

Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3807103555

**Observed:** loader manifest registers DualWieldCore.dll. Update metadata and embedded session string identify **0.21.0-coexistence1**. DualWield.ini contains only [Logging] Detailed=1; no documented slot restriction or balance controls are exposed there. Distribution contains no external .skeleton files or editable native source. Absence of external skeleton files does not mean absence of animation data: the DLL identifies a blender_baked_clips feature internally.

Filtered DLL evidence includes chooseAttack and _chooseAttacks, InventorySection::getItems, Inventory::getAllSections, Weapon::is2HandedOnly, getTotalAttackDamageFor, hitByMeleeAttack, _iHitYouAreYouHit, MedicalSystem::applyDamage, xpMelee, and Ogre::Skeleton::_updateTransforms symbols.

Included log event names cover offhand_damage, offhand_wound, offhand_range, offhand_technique_selection, paired_weapon_xp, weapon_tempo, blade_strike and blade_strike_result. Gating/error strings include need_two_weapons, hands_occupied, native_weapon_outside_pair, damage_pair_changed, damage_phase_or_pose_stale, and damage_pose_not_presented.

**Inference:** this is a substantial runtime implementation with per-blade timing/damage/XP machinery, not merely a visual second sword. Its native medical and hit interfaces deserve an explicit duplicate-damage test. Binary strings do not prove which slot combinations are selected or that every declared gate works.

**Open gates:** exact main-only selection, ordering of equal blades, mixed qualities/categories, single-click attack ownership, missing limbs, pause/time-scale stability, FP bone ownership, KEP XP cooperation, saved state and uninstall. Limited settings/source make a tailored integration harder unless upstream source becomes available. Do not assume “coexistence” in the version name means KenshiFP support.

### Candidate B: Nitoryu

Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3812165089
Public changelog at inspection: **1.0.5**, updated October 6, 2026.
Actual docs: README.md, FCS.md, FCS-settings.md, Nitoryu.ini, Nitoryu.ini.shipped, fcs.def and translations in the pinned folder.

**Observed:** RE_Kenshi.json registers Nitoryu.dll. Both male and female Ogre skeletons parse as [Serializer_v1.80], with 30 bones and 48 animations each. Male: 1200 tracks/37454 keys; female: 1200 tracks/37463 keys. Parse succeeded without an unknown-chunk stop. This proves clip presence/structure, not visually polished or correct game playback.

Clip coverage includes main/off-hand cuts, backhand/rising/leg cuts, twin sweeps, one-two, three cuts, x cut, dash slash, spin, left/right/overhead/back/scissor blocks, reactions, five stances, draw/sheath variants and running. Main/off-hand cut clips are about 1.07 s; one-two/three-cuts about 1.73 s; dash/spin about 2.67 s. Do not use these durations as final impact times or as timing at all game speeds.

**Author documented:** supports main+main **and main+hip**, normally katana/sabre categories; per-character optional blunt/hacker pairing; heavy/polearm/bow exclusions. Requires a usable bare-sword mesh. Therefore its default eligibility fails our strict main-only requirement. No documented main-only setting was found in the inspected config/settings tables. Per-weapon “nitoryu dual wield” permits/refuses items, but does not itself establish a slot rule.

Author-documented progression uses a saved dual skill, weighted proficiency, ranked moves, extra guard/counter/initiative mechanics and NPC pairing. Those are optional candidate features, not user requirements. Its overall late-game power design is broader than the requested situational tradeoff.

Settings precedence: defaults < GLOBAL CONSTANTS FCS overrides < explicitly present Nitoryu.ini keys; plugin reads settings after game load. Avoid judging an FCS patch while a local INI silently overrides it.

Representative inspected defaults, useful when configuring a future comparison:
| Field/control | Default and implication |
|---|---|
| Proficiency weights | dual skill 0.60; lower weapon skill, dexterity, attack, defence each 0.10 |
| Tier thresholds | proficiency 20/40/60/75/90; upper tiers additionally require dual skill |
| nitoryu pair weight mult | 1.25 times the sum of both combat weights; two equal blades mean 2.5 times one blade's weight input, not a universal 2.5x strength-stat requirement |
| Clumsiness | attack/defence penalty 10 at proficiency 0, fading by slope 0.25 to zero at 40 |
| Beginner speed | 0.85, rising to full at proficiency 30 |
| Master speed bonus | 0.30; documented attack cap 1.5, block cap 4.0 |
| [Balance] off_hand_share | curve rises from 0.03 at 20 to 0.55 at 100; author defines share of attacks using second blade, not a free independent +55% DPS |
| [Balance] off_hand_damage | second blade's own damage multiplied 1.04 at 20, 1.14 at 40, 1.30 at 70 |
| nitoryu off weapon bonus share | 0.5 of off-weapon attack/defence/indoor bonuses |
| Armour proficiency cuts | heavy 0.07 per piece, medium 0.04 per piece, with floor |
| [Guard] guard / counter | additional parry/riposte systems; inspect and disable for a minimal comparison |
| Other systems | pressure, flow, Mugen, pair effects, scissor/split attacks and training; isolate rather than bundle into our baseline |

The full schema remains in FCS-settings.md; use its exact fields/ranges instead of inventing keys.

**FP compatibility configuration:** [Compat] foreign_control defaults to auto; plugin list defaults to ShoulderCombat.dll. KenshiFP.dll is **not explicitly included**. Candidate documentation says add the external controller DLL to the foreign control list and verify foreign_config/foreign_action logs. Proposed evaluation override:
~~~ini
[Compat]
foreign_control=auto
plugins=ShoulderCombat.dll,KenshiFP.dll
~~~
Use the actual loaded DLL name if it differs. Verified modes are off, auto, and on; on always yields, auto yields when a listed DLL is loaded. Default hold_ms=6000 and run_ms=300 use game time. Effective settings can be checked through setting/source lines and settings total=130 record_found=1 from_fcs=N from_ini=N. Pose-yield is not proof that damage, follow-up scheduling, XP, input, and recovery cooperate.

Author documents hooks in chooseAttack, setWeapon, attack/block speed, weapon skills, XP, save/load/stats, hit/wound, combat initiative, block and weapon choice; pose work uses Skeleton::_updateTransforms. The author says some KEP XP paths replace native handling without forwarding. Test the enabled fix_melee_combat_xp path; do not certify compatibility from generic hook chaining.

**Animation extension limitation:** FCS.md describes its pose engine as consuming selected/mirrored tracks; arbitrary authored two-arm clips are not necessarily played unchanged. Importing a new skeleton and listing a COMBAT_TECHNIQUE is not enough to extend every move. Confirm the actual pose-engine route or change the plugin if independently authored two-arm choreography is required.

Permissions: public page permits inclusion in packs/collections with attribution; other uses require contacting the author. Downloading for local evaluation is not source/asset reuse permission. No author message was sent.

## Native engine constraints and implementation surfaces

### Inventory and item identity

SDK Inventory.h exposes sections, section names, equipment flags, limited slots and SectionItem coordinates/dimensions. InventorySection::getItems gives actual item instances. getPrimaryWeapon/getSecondaryWeapon/getEquippedWeapons exist, but “secondary” is not an off-hand contract.

Proposed selector:
1. Find the real main/back equipped section by inspected section metadata, never localized UI text or a guessed name.
2. Enumerate exactly two eligible weapon item instances there. Reject ambiguous counts or unsupported grip/mesh/race cases.
3. Exclude hip/secondary inventory completely. Two physical swords must fit the native grid; do not resize it.
4. Determine main versus off hand deterministically: retain valid native active weapon as main; otherwise stable grid ordering, with stable item identity as tie-break.
5. Store handles/validated item identity, not long-lived raw pointers.
6. Reconcile on equip/remove, slot move, weapon selection, load, actor unload, death, limb state changes and pair changes during a swing.
7. Atomically cancel stale off-hand impacts if either item leaves the valid pair. Remove only our own visual attachment; never delete the actual item.

Get section names/coordinates from harness sections and native inspection at runtime. Need a single concrete mapping in the future implementation; this investigation deliberately does not hardcode an unverified section name.

Gear.h exposes category, is2HandedOnly, combatWeight and Sword damage/bonus data. SDK class “Sword” is broader than a player-facing sword whitelist. Start with explicitly allowed katana/sabre item definitions plus a one-hand/mesh capability check; do not accidentally pair every weapon because of its C++ class. Two-handed-only rejection wins over an item allow flag.

### One native weapon context is the main limitation

CharStats has one weapon handle around offset 0x208, currentWeaponType/skill and cached damage, weight and reach. Existing setWeapon, getTotalAttackDamageFor, weapon-weight speed calculation, attack/block speed and chooseAttack make a native integration possible, but a second equipment item does not create a second engine combat context automatically.

Each impact needs a hand-specific context: actor/target handles, pair identity, sequence ID, native technique/impact index, acting blade identity, current animation phase, range and damage snapshot. Use the off blade's actual skill, quality and relevant bonuses. Scope any temporary native context substitution and restore it on every exit, including exceptions; never leak off-hand caches to later main-hand damage or another actor.

Prefer the native combat hit pipeline over naked health subtraction. It owns defence, armour, injury, faction aggro, sounds, XP, reactions and death. Hooking low-level wound application to add extra damage without preserving that path risks duplicates and bypasses. One (actor, sequence, impact, target) key may apply damage once only, including retries or multiple update passes.

### Techniques and impact timing

CombatTechniqueData.h exposes multiple impact points with direction, power, impact frame, motion-stop frame and limb. Installed fcs.def exposes two impact frames/directions/limbs/power, animation speed, min skill, encumbrance and simultaneous-hit limits. Native multi-impact support is useful; it is not a generic dual-inventory system.

The FCS tooltip warns that fast double-hit techniques need reduced power because a second hit may be too quick to block. Treat the warning as a design constraint, not a chosen multiplier. Nitoryu's limb field conventions are candidate-specific; confirm 0/1 hand interpretation before copying records.

Create normal records/assets with FCS where useful, and use native runtime logic for strict pair eligibility, per-hand item context, additional attachment, input ownership and lifecycle. FCS-only work cannot satisfy all those conditions.

Do not patch by unchecked addresses. Existing components/KenshiFP/docs/MELEE_ADAPTER_RE.md maps Kenshi 1.0.65 and warns header RVAs can differ from the executable. Examples already mapped there: AttackState::initialise 0x2B4AB0; initialiseAttack 0x2B4530; CombatClass::attackState 0x609B00; initialiseBlock 0x608800; need-block path 0x607940; attackImpactCheck 0x609860. These are reference anchors, not instructions to write memory blindly. chooseAttack/setWeapon header addresses were not independently verified in this investigation.

Use unique signature checks, verified calling conventions/ABI, build/version gating, and fail-closed disable behaviour. Reuse the workspace's KenshiLib hook mechanism. Current live KenshiFP RE build uses KenshiLib::AddHook, **not MinHook**.

## KenshiFP integration contract

Read live client/kfp_combat_melee.inc and client/kfp_viewmodel.inc alongside the existing combat coordination docs.

Observed melee flow:
- Owned FP actor's automatic AttackState initialisation is suppressed unless there is a manual pending attack; it parks in WAIT.
- Manual melee_click_swing calls native initialiseAttack directly.
- At most one swing per click, with native recovery/deadtime and a short pending buffer.
- RMB controls manual block. Native automatic block is restricted; no unintended chase should be introduced.
- Hook surfaces include attack initialise, block initialise, approach state, attackState and need-block checks.

Inference: a candidate can hook chooseAttack and still miss portions of the original automatic attack path. Conversely its extra follow-ups/counters can violate FP ownership even while animations appear normal. Load order alone will not resolve semantic conflicts.

**Proposed v1 FP rule:** one accepted click schedules one strike, alternating valid hands across successful swing starts; a failed start does not consume the hand turn. Native recovery remains authoritative. No autonomous ripostes, off-hand follow-ups, Mugen chain or special-move input until separately designed. Third-person AI may use the same alternating sequence automatically through native AI scheduling.

Observed viewmodel path: Skeleton::setAnimationState interception modifies arms after native pose and before matrix work; right sword has a VmPose/swing path, left hand ordinarily rests. Prop1 is left and Prop2 right on inspected human skeletons. Nitoryu and DualWieldCore both reference later _updateTransforms, which can overwrite FP arm IK even when detours technically chain.

Proposed ownership:
- Dual wield core owns pair identity, world attachments and authoritative strike metadata.
- Existing FP controller owns input/recovery requests and camera-specific arm presentation.
- One explicit bridge supplies hand, sequence ID, blade/grip, phase and impact event.
- One defined final bone-transform owner per actor/camera pass; restore world bones after FP rendering.
- Third-person spectator renders must never inherit camera arm edits.
- If interoperability cannot be established, disable candidate pairing for the owned FP actor; do not silently show two blades with single-blade or duplicate damage.

Shared visual/damage rules: visible blade corresponds to the acting item; impact occurs during its visible strike; reach is blade-specific; blocked/missed strikes do not become forced wounds. No hit from a pose that was cancelled or whose pair changed.

Current FP visual work is moving quickly: viewmodel flip/wrist/recovery/render-resolution issues were active at inspection. Recheck fixes before judging candidate regressions. World units are decimetres; do not confuse 3 dm near clip or ~1.9 m eye height with game metres.

## Animation production: what an agent can and cannot promise

An agent can author procedural transforms, create Blender Python rigs/keyframes, generate/export assets when a working exporter exists, tune animation impact timing, build contact sheets, and iterate using native readbacks and captures. There is no inherent need for Shay to hand-key every frame.

However “I can do all animations” is a capability statement, not proof of a finished Kenshi animation pipeline. Blender was not found in the inspected installation/PATH. An Ogre/Kenshi exporter round trip was not performed. The existing bake_locomotion.py and retarget_locomotion.py refer to external Destreza inputs and private KFA formats; **KFA1/KFA2 are not native Ogre .skeleton exports**, and those external inputs cannot be presumed available/licensed.

Existing dump_ogre_skeleton.py is a read-only inspector; it successfully parsed both Nitoryu skeletons. Kenshi's Ogre serializer chunk lengths can exclude bone name strings, so parse by known structure. Disk quaternions are xyzw; helper calculations use wxyz. Prop offsets differ by side: mirroring quaternion components without a bind-space/grip conversion is unsafe.

Minimal independent animation scope: dual idle, right strike, left strike, right/left block, draw/sheath and hit reaction compatibility. Start without spins/dashes/twin combos. Provide male/female and each supported race/scale capability checks; test missing arms/prosthetics and existing animation packs. Unsupported skeletons must fall back.

For native assets, future agent should:
1. Install a supported Blender/exporter toolchain from the official Lo-Fi route.
2. Import an existing lawful template, export unchanged, load in a disposable fixture and prove bone/clip fidelity.
3. Author a two-blade grip/stance; verify neutral bind, props and sheathed attachments.
4. Author strikes with explicit windup/impact/recovery; preserve native motion/defence timing.
5. Compare world and FP captures on open ground, native resolution; require no clipping, hand-at-head poses or folded wrists.
6. Independently verify each blade's impact phase and range against recorded native damage.
7. Keep editable authoring files/scripts alongside generated assets and document tool versions.

For runtime FP animation, extend two independent arm/weapon poses rather than simply attaching another mesh. Respect existing wrist limits and per-camera restoration. If upstream animations are reused, obtain the necessary permission first.

What only Shay may need to supply: choices about feel/art direction, consent if a permission/account step is unavailable to the agent, and acceptance of tradeoff tuning. Human playtesting is valuable for feel, but ordinary install/build/fixture tests are agent work. Author permission and polished motion are not guaranteed by automation.

## Balance research and proposed baseline

Use examples as design principles, not imported current numeric truth:
- Path of Exile's developer Harvest patch removed a dual wield physical-damage bonus while retaining attack-speed/block incentives. Principle: avoid stacking universal damage and speed benefits.
- Blizzard's classic Diablo II Frenzy builds speed from successful attacks and has a mana/action cost. Principle: earned momentum and opportunity cost. Kenshi has no equivalent general stamina/mana budget to reuse by assumption.
- D&D 2014 two-weapon fighting spends a bonus action and limits off-hand ability damage. Principle: the second strike consumes an action resource and need not duplicate full main-hand damage.

These are historical/version-specific primary rules. Do not cite them as current PoE or D2R balance. The earlier BG3 comparison was illustrative; use the primary D&D rule here instead of relying on forum claims.

**Proposed prototype, not user-approved:** trained alternating dual wielding, main blade 100% own power, off blade 75% own power, up to 30% greater accepted strike frequency if native timing permits; defence -5 trained, -10 novice; combined combat weight limits speed; normal reach/block/armour pipeline. No passive block bonus, back parry, initiative boost, free counters or bonus XP. Novice speed penalty can precede trained gains.

Arithmetic for equal blades and alternating strikes:
- Average strike power = (1.00 + 0.75)/2 = 0.875.
- At 1.30 times strike frequency, ideal pre-armour damage rate = 1.1375, about +14%.
- This is not guaranteed in-game DPS: block rate, armour, recovery, reach and skill materially change outcomes.
- A 30% chance of an extra 75%-power follow-up instead gives 1 + 0.30*0.75 = 1.225 per base swing. That is a different model.
- Do not apply both frequency bonus and extra follow-up bonus accidentally. Specify which scheduler is used.

Intended niche: lightly armoured opponents and close sustained pressure. Intended costs: worse defence, weight/strength demand, weaker individual off-hand hits, vulnerable windup/recovery, shorter blade contact opportunities. Armour should be measured through the actual injury/armour pipeline; do not assume “two small hits always worse” for every armour formula.

An additional off-hand armour-penetration penalty is optional only after baseline measurement. Define percentage points versus multipliers explicitly and handle negative/positive weapon AP correctly; do not invent a native stat field. Avoid artificial accuracy, stamina or durability systems unless deliberately added later.

Prototype progression can use existing dexterity and the lower of both category skills; a dedicated saved dual skill is optional and introduces save/UI/XP work. This proposal does not silently endorse Nitoryu's much broader ranked power system.

Balance measurement: same actor stats, exact item instances/quality, target armour, hunger, injuries, game time and attack-slot settings; compare single blade A, single blade B, and pair. Record attempted/accepted swings, contacts, blocks, armour-adjusted wounds, damage/game-second, XP and incoming damage. Minimum independent runs with reset fixtures and sample counts; report variance and exclusions. Measure duels, groups, indoors and heavy armour separately. Mechanical correctness and accepted tuning are distinct gates.

## Existing-implementation evaluation: executable sequence

This sequence is future work; **no rows below passed live during this research**.

1. Read current workspace/harness rules, confirm rig owner, obtain a free normal game lock and create a fixture copy. Capture hashes/config/load order. Preserve exact reversible config backups outside source control.
2. Run baseline without either dual mod: main-only one sword, two main swords, and main+hip; in TP and FP. Confirm native weapon identity, damage and input behaviours.
3. Stage one pinned candidate into an isolated test mod folder and enable its loader manifest using the normal RE_Kenshi procedure. Preserve the current live stack; do not delete required fixture mods.
4. Nitoryu first: run defaults, then documented foreign-control override, then isolate optional guard/counter/special systems. Change one controlled factor at a time; record effective settings after load.
5. Run the gates below. Save relevant logs immediately before restart; RE_Kenshi logs are overwritten on launch.
6. Fully unload/remove candidate and restore original order/config; verify native baseline again.
7. Repeat with DualWieldCore alone. Detailed=1 provides useful native event vocabulary; detect actual log output path rather than guessing.
8. Compare using pass/fail evidence. Pick existing overlay, source integration, independent core, or explicit unsupported FP mode based on results.
9. Do not deploy a chosen foundation until strict main-only behaviour and FP ownership pass together.

Useful existing harness probes: sections <npc>, inv <npc>, stat <npc>, iteminfo, equip/unequip and native state/damage readbacks. Use exact syntax from docs/COMMANDS.md; these names are pointers, not invented ready-to-run scripts.

**Setup trap:** inspected equip handler replaces the existing item in the same slot. Calling equip twice does not establish two swords in one main section. Use native placement/UI inventory drag or an existing section-placement command if available, with sections and item IDs read back. If none exists, adding a narrow fixture helper is a future implementation/test task. Never mark an incorrectly prepared pair test as product failure.

Use explicit named characters or resolved handles, not @player assumptions. Verify passive/block flags, hostility, draw state and target eligibility before timing attacks. Current input issues against engaged targets can otherwise contaminate results.

| Gate | Required evidence / acceptance |
|---|---|
| E01 Main-only eligibility | Two eligible main-section instances pair; single main + hip does not; two in backpack do not. Read back positions/IDs and pair status. |
| E02 Item/mesh identity | Unequal sword models/qualities visibly and mechanically distinct; no duplicates, inventory mutation or extra item. |
| E03 Hand damage | Alternating isolated strikes use acting blade's own damage/skill/quality; exactly one wound application per impact-target. |
| E04 Range and block | Short off blade cannot hit outside its range; misses/blocks cause no phantom wound; native defence and reactions remain. |
| E05 Speed and recovery | One accepted FP click -> one strike; spam respects native recovery; no background attack/follow-up/counter from idle. |
| E06 RMB input | Holding/releasing block never moves actor to a ground point, attacks, opens unintended context or switches targets. Separate pre-existing failure from regression. |
| E07 FP pose coexistence | Both blades readable; world/FP camera passes isolated; no overwriting IK, folded wrist, head strikes or stuck swing. |
| E08 Inventory mutation during attack | Remove/swap/drop either blade during windup and between impacts: stale off damage cancelled; no crash/dangling pointer. |
| E09 Limb/race fallback | Missing/incapacitated arm, prosthetic arms, male/female/race/scale variants: documented supported mode or safe single wield fallback. |
| E10 Save/uninstall | Save/load, import, actor unload/death, disable/re-enable: no item loss, saved pointer, permanent stat modifier or missing actor. |
| E11 KEP compatibility | XP/injury/armour/damage/weapon extension settings enabled: correct XP once, unchanged baseline outside pairs; no double hook application. |
| E12 Animation/load-order matrix | Current MCA/GAM/UWE patches and idle/run/reaction mods; both hook order and final bone owner verified. |
| E13 Time and interruption | Pause, 1x/2x/5x, accelerated test speed, stagger, knockdown, target death/switch, FP entry/exit: no stale phase/repeated hit. |
| E14 AI and ownership | TP NPC pairs work only if enabled; FP actor controlled manually; switching selected actor clears pending state. |
| E15 Balance | Pair advantage measured in intended niche and meaningful disadvantage measured elsewhere; no universal improvement. |
| E16 Performance | Compare same rig/population/render settings; bounded work and memory; no increasing per-skeleton attachment count. |
| E17 Restoration | Candidate removed, original configs restored, baseline passes; test leaves no live mod enabled. |

Start E01/E03/E05/E07/E11 before broad combinations. A failed first gate should stop expensive balance sweeps. Visual review requires full 1600x900 captures at FP distance 0 and world zoom 25 on open ground; use existing VMQUICK procedure if integrating a new viewmodel build. Do not accept cramped-wall or cropped sheets.

Log record schema to add only if a candidate does not expose equivalent data: actor/target handles, pair IDs/section coordinates, sequence/impact/hand, technique, blade quality/category/reach, requested and accepted click times, visual phase, raw and post-armour damage, native hit result, XP before/after and cancellation reason. Names of proposed events are not existing harness commands.

## Implementation packages after evaluation

| Package | Deliverable | Completion gate |
|---|---|---|
| P1 Select foundation | Comparative evidence and source/permission availability; narrow overlay if possible | E01/E05/E07/E11 pass or documented replacement strategy |
| P2 Pair state | Strict selector, deterministic identity and lifecycle invalidation | E01/E02/E08/E09/E10 |
| P3 Combat context | Acting-blade damage/skill/range, native hit path, one-time impact ledger, scoped restore | E03/E04/E11/E13 |
| P4 Scheduler and FP bridge | Single input owner, alternation/recovery, authoritative hand/phase metadata | E05/E06/E14 |
| P5 Attachments/animation | Independent grips/poses and per-camera restoration; editable pipeline | E07/E09/E12 |
| P6 Tunable balance | One clearly defined model, progression/config, bounded speed and weight effects | E15 plus outside-pair baseline |
| P7 Release | Version gating, diagnostics, install/uninstall, migration notes, source and tests | E10/E16/E17 |

Do not prematurely create a second input subsystem in Stobe. Keep generic dual wield core separate from FP presentation where practical, using a small versioned bridge. An integration inside the existing FP plugin is acceptable for a first FP-only prototype, but must explicitly state NPC/TP limitations.

Current toolchain options: existing live FP RE build at /root/KenshiFP/re_plugin/build.sh uses x86_64-w64-mingw32-gcc, windres and plugin.def. Windows VS2010 amd64 compiler exists under C:\StobeBuildTools\v100\Program Files (64)\Microsoft Visual Studio 10.0\VC\bin\amd64\cl.exe. Choose the supported SDK/ABI route; do not assume GCC C++ objects can freely cross MSVC engine boundaries. Current FP uses C bindings for its hook surface.

Effort assessment: configuring an existing candidate is the lowest effort only if eligibility and FP gates pass. A native inventory/damage/animation integration is a substantial multi-stage project; engine ABI, ownership and animation polish dominate uncertainty. No responsible calendar estimate or promise of a finished full mod is possible before live gates. No conceptual blocker was found, but no compatibility guarantee was established.

## Sources and research audit

Primary/local evidence:
- Inventory.h, Gear.h, CharStats.h, CombatTechniqueData.h in the inspected SDK.
- Installed fcs.def and KEP configuration.
- Live /root/KenshiFP/client/kfp_combat_melee.inc, kfp_viewmodel.inc, re_plugin/build.sh.
- components/KenshiFP/docs/MELEE_ADAPTER_RE.md and FP combat/viewmodel plans.
- Harness docs/COMMANDS.md, equip handler, AGENTS.md; workspace CLAUDE.md and testing/HANDOFF.md.
- Downloaded, pinned candidate README/FCS/settings/INI/manifests and actual binary/skeleton payloads.

Public primary references:
- Nitoryu: https://steamcommunity.com/sharedfiles/filedetails/?id=3812165089
- Nitoryu changelog: https://steamcommunity.com/sharedfiles/filedetails/changelog/3812165089
- Nitoryu FAQ: https://steamcommunity.com/workshop/filedetails/discussion/3812165089/589565404421068660/
- Nitoryu feedback: https://steamcommunity.com/workshop/filedetails/discussion/3812165089/589565135028538468/
- Nitoryu bug reports: https://steamcommunity.com/workshop/filedetails/discussion/3812165089/589565135028538310/
- DualWieldCore: https://steamcommunity.com/sharedfiles/filedetails/?id=3807103555
- RE_Kenshi upstream: https://github.com/BFrizzleFoShizzle/RE_Kenshi (licensing must be checked for reused source; GPLv3 repository)
- Official SteamCMD installer: https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip
- Lo-Fi Blender/exporter thread: https://www.lofigames.com/phpBB3/viewtopic.php?f=11&t=10732
- PoE developer Harvest notes: https://www.pathofexile.com/forum/view-thread/2873739
- Blizzard classic Barbarian combat skills: https://classic.battle.net/diablo2exp/skills/barbarian-combatskills.shtml
- D&D 2014 combat rules: https://www.dndbeyond.com/sources/dnd/basic-rules-2014/combat

Research completed: workspace/toolchain/source inspection; current combat/input and FP bone hook analysis; candidate public docs/changelog/feedback review; successful actual Workshop payload download; payload hashes; candidate settings and loader inspection; DLL static string/symbol inspection; male/female skeleton parsing; primary cross-game rules review; design alternatives, risk mapping and test protocol.

Not completed and not claimed: native candidate runtime evaluation; decompilation/full source review; authored exporter round trip; animation quality certification; measured balance/DPS; permissions for reuse; new mod implementation.

Successor first action: **check current lock/build state, run the candidate gate sequence on a fixture copy, and attach measured evidence to this brief.** Do not skip straight to coding a full custom system, and do not repeat broad web research unless the pinned candidates changed.


## Follow-up static investigation — 2026-10-09

This section supplements the initial checkpoint and takes precedence where it is more specific. Scope explicitly ends before building, installing, exporting trial assets, running tests or driving the game. Shay reports an existing harness for body-position/impossible-pose checks; the matching inspected implementation is described below. No requirement is satisfied merely because the harness exists.

### Research completion and remaining boundaries

| Topic | Static work completed | What still requires execution or outside input |
|---|---|---|
| Candidate source/reuse | Reopened both author pages, searched public source links, checked downloaded payloads for source/license/Blender files | Neither candidate's native source was located; permission for adapting private code/assets is not established |
| Animation tooling | Located version-specific modern exporter, downloaded/hash-checked it and official editable rig templates, inspected exporter source/manifest | Install Blender and prove import/export/playback fidelity during the later testing phase |
| Main section | Inspected SDK, live draw path, harness section/item code and archived fixture evidence | Confirm back-section metadata and grid placement in the actual future fixture |
| Hook ownership | Inspected live FP input/melee/pose/wound paths and pinned public KEP source | Actual detour order, candidate callbacks and cooperation need live tracing |
| Harness preparation | Audited existing recorder/checker, inventory readback and input injection | Two-blade telemetry and guaranteed placement helper are future code tasks |
| Design scope | Wrote conservative defaults and decision boundaries below | User may steer defaults; measured tuning remains future work |

No additional broad feasibility research is needed to start the planned evaluation. Lack of candidate source and runtime behaviour cannot be cured by more speculative prose. An agent should not call this a completed compatibility certification.

### Candidate source access and reuse decision

Nitoryu's current author page still says source will be released after polishing/feedback. It allows packs/collections with attribution and asks for direct contact for other uses. No native source or editable .blend files were located in either downloaded candidate distribution. Targeted public searches did not locate a source repository for either candidate. This is a bounded search result, not proof no repository exists anywhere.

DualWieldCore's author explicitly welcomed a UWE compatibility effort in the inspected comments. Treat that as support for a compatibility patch, not a blanket code/animation redistribution license. Its public claims still include KEP compatibility and specific animation conflicts. The pages' scraped header banners include removal/incompatibility text alongside otherwise accessible descriptions; do not infer actual download availability or a technical failure solely from those template banners. The prior successful pinned downloads remain the local evidence.

Practical paths:
1. Evaluate original pinned candidates as dependencies, retaining their files intact.
2. Use documented settings/FCS overrides if they meet strict slot/FP requirements.
3. For a maintained native integration, obtain actual source and suitable reuse terms, or implement independently.
4. Independently authored animations can use the official Kenshi rig template; they need not depend on unpublished upstream .blend files.

No author was contacted. A future permission request, if needed, should ask specifically for native source access, local modifications, redistribution of modified DLLs, animation asset reuse/editable rigs, attribution and the intended release model. An agent may implement independently without waiting for an author reply.

### Pinned animation authoring inputs

Research directory: C:\KenshiModding\tools\research\dual-wield-reference\animation-toolchain

| File | Provenance and pin | Static contents |
|---|---|---|
| Lucius_Kenshi_IO_Tool_4.2-1.3.1-windows_x64.zip | https://lucius64.github.io/kenshi_io_blender/extensions/Lucius_Kenshi_IO_Tool_4.2-1.3.1-windows_x64.zip ; SHA256 942D332FFD9571BDE54A6DEC582714B0EAAF1BED29C3786D9305985BEC6784ED | Manifest, import/export Python, Windows CPython 3.11 wheel, LICENSE/NOTICE |
| LoFi_Blender_Templates.zip | Official Lo-Fi page download: https://www.lofigames.com/phpBB3/download/file.php?id=5037 ; SHA256 188A8C60E05E1EE5F4D2760400DADF35036277FD071DDE57A8804A12E8720855 | kenshi_template.blend (2,120,340 bytes) and readme.txt |

Exporter archive hash matches its maintainer's public extension index. Manifest requires Windows x64 and Blender >=4.2.0, <4.4.0. Recommended initial authoring environment: a pinned Windows Blender 4.2 release with this exact extension 1.3.1. This is a researched pairing, not a locally proven toolchain. Do not install this Windows wheel into WSL Blender. No Blender executable was found in PATH or the conventional Windows Blender Foundation installation directory; this is not a full-disk inventory.

Maintainer documentation supplies a distinct 4.4+ package (1.3.2); never mix it with the pinned 4.2 package. The older Kindrad exporter is a fallback, but its GitHub README redirects to Codeberg. Codeberg could not be retrieved through the research browser, so its present code/version was not certified.

The downloaded exporter has native skeleton serialization and separate keyed/baked animation collection. It can gather the active action and NLA actions; visual-keying selects a baked path. Exporter source offers skeleton version choices; do not assume its "latest" output matches Kenshi's expected serializer. Inspect the exported header before later playback testing. Do not preserve only unconstrained F-curves when an IK/constraint rig needs baked evaluated motion.

Official template README identifies male/female rigged models plus an example weapon. Its assets are limited to Kenshi use; it prohibits profit distribution, asset packs and other-game development. Keep the original archive/README as provenance and do not package the template as a general asset library. This establishes a legitimate editable starting rig, not an existing dual-wield animation set.

Production recipe, to execute only after the user starts building/testing:
- Install the pinned Blender/extension combination from disk.
- Preserve bone names, hierarchy, IDs, bind transforms and prop grip frames. Author controllers separately from export bones.
- First export an unchanged lawful rig/clip; compare rest hierarchy, transforms, clip names/durations and sampled local/world poses against the input.
- Create separate right/left strikes with explicit windup, impact and recovery; use asymmetric grips fitted to each actual blade.
- Bake constraints/IK to the exported skeleton and inspect all interpolated frames, not just keyframes.
- Load through an additive ANIMATION_FILE with unique clip names; avoid replacing the entire vanilla skeleton unless required.
- Maintain editable .blend and procedural scripts, export presets, exact versions and an asset manifest with each generated .skeleton.

Do not reinterpret the original template's clothing-oriented advice to omit skeleton export as a rule for animation production.

### Main-slot mapping and item eligibility precision

Live kfp_controls.inc, draw path around lines 488–515, reads Item::inventorySection at +0xE8 and passes it to native drawWeapon. Its documented equipment-section names are back and hip. The harness uses getSection("main") to put UNEQUIPPED items into general storage: **main is the general inventory section, not the user's main weapon slot.**

Archived C:\KenshiTestRuns\vmq-final2\log.txt line 200 shows a Chisa Katana equipped in section=hip, slotType=0. Item ID: 5022626-Universal Wasteland Expansion.mod. This is useful negative-case fixture gear, not proof that this weapon fits twice in back.

SDK AttachSlot enum defines ATTACH_WEAPON=0 and ATTACH_BACK=1. Do not assume ATTACH_BACK identifies the two-sword main weapon grid: slot enum and inventory section identity are different concepts. Both weapon sections must be classified by actual section metadata/item ownership, not merely weapon slotType=0.

Proposed selector contract:
- Locate the equipped, enabled back weapon section for the supported game/layout; reject hip, main storage and backpack contents.
- Confirm every selected item's inventorySection/owner agrees with that section.
- Require exactly two distinct one-handed sword instances occupying the native grid, with valid meshes. Count instances, not quantity.
- Prefer the native active blade as primary while valid; otherwise grid y/x and validated identity provide deterministic ordering.
- Unknown layouts fail safely to single wield; never broaden eligibility to hip as a fallback.
- Katana/sabre is the initial category filter; explicit two-handed prohibition and actual fit/mesh checks win. Custom sword IDs can be opted in later.
- The Chisa Katana above is a known fixture item, not an approved whitelist. Final data IDs/dimensions should come from effective loaded records, especially with UWE overrides.

The exact back section dimensions, limit flags and per-item coordinates for a prepared TWO-BACK fixture were not found in inspected static evidence. Reading them in the future fixture is an unavoidable runtime acceptance step.

### Hook map and required ownership contract

Public KEP source was downloaded read-only to:
C:\KenshiModding\tools\research\dual-wield-reference\kep-source
Repository: https://github.com/Lucius64/KenshiExtensionPlugin
Pinned HEAD: 08bb145c9b360bbfd2117c57b9104c5d2c18624e
No submodules were initialized and nothing was built. This is an upstream snapshot; a source/binary correspondence to the currently installed DLL has NOT been established.

| Surface | Observed FP / KEP behaviour | Dual-wield integration requirement |
|---|---|---|
| playerControl / mouse flags | Live kfp_controls.inc consumes drawn LMB and RMB; MMB selects; R draws/holsters | Keep FP as the only input owner |
| initialise / initialiseAttack | kfp_combat_melee.inc manual gate suppresses autonomous attack starts; click starts native technique | Commit hand alternation only after successful native start |
| checkForNeedBlock / initialiseBlock | FP controls reactive block and refuses unwanted auto-block/cancel | Candidate passive counters/follow-ups must not bypass this |
| chooseAttack / _chooseAttacks | FP binds chooseAttack, including free swings; KEP AnimationExtension.cpp wraps _chooseAttacks | Candidate must cover target attacks and free swings; preserve KEP filtering |
| setWeapon | KEP ItemExtension.cpp calls original then adds per-weapon material/race bonuses | Do not write only CharStats::weapon and leave caches/bonuses stale; restore all affected context |
| xpMelee | KEP bugfix/StatsFix.cpp replaces processing when fix is enabled; original is called only with fix disabled | Do not assume hook forwarding; award correct hand/category XP exactly once |
| MedicalSystem::addWound | FP kfp_combat_wound.inc records melee evidence, then forwards non-bolt calls unchanged | Existing counters observe wound calls, not authoritative strike IDs |
| addArmour / injury summaries | KEP ItemFix.cpp orders armour; MedicalFix.cpp recomputes injury-derived fields | Use native pipeline and check arm usability from actual state |
| setAnimationState / _updateTransforms | FP applies arms after native animation; both candidates reference later bone-transform work | Define one final pose owner and prevent candidate overwrites |
| animation refresh / linked skeletons | KEP AnimationFix.cpp replaces refresh handling and walks linked skeleton sources | Unique clip names and actual linked-asset/load-order checks are required |

Concrete KEP findings:
- StatsFix.cpp lines 181–235: enabled melee XP fix handles hit, blocked attack, successful block, incoming hit, miss and slot-open cases internally. Original native XP is not forwarded in those enabled branches. A callback placed only inside the native original may never execute.
- ItemExtension.cpp lines 273–320: setWeapon recomputes extra material/species bonuses after the native call. A simplistic pointer swap is inadequate for a different off-hand weapon.
- AnimationExtension.cpp lines 284–310: extended-technique special handling is conditional; with combat_techniques_ex=false this wrapper forwards. Disabled feature does not mean the DLL has no hooks.
- ItemFix.cpp lines 69–79: fix_global_damage_multiplier here concerns crossbow construction. It is not evidence of a generic sword-damage multiplier hook.
- MedicalFix.cpp line 313 onward affects injury-derived summary calculation, rather than proving every damage event is rewritten.

Installed configuration rechecked in mods\KenshiExtensionPlugin\plugin\kep_settings.json: melee XP fix, animation override, injury calculation, armour order, global damage fix and weapon extension enabled; combat_ex/combat_techniques_ex disabled; fix_damage_calculation=0. RE_Kenshi.json loads kep-core-preload-x64 as a preloader and plugin/KenshiExtensionPlugin.dll as the normal plugin. Preloading plus runtime detours means FCS mods.cfg order alone cannot establish native hook order.

Suggested bridge specification (design only, not an existing API):
- Versioned C ABI POD data: actor and target handles, pair generation, sequence ID, hand, blade identity, technique/impact index, phase and cancel reason.
- FP requests a strike; core returns accepted/rejected and acting blade. No automatic extra input or independent follow-up scheduler.
- Pair generation invalidates outstanding events on equip/remove, actor switch, unload, injury fallback and load.
- Pose is read-only presentation of core strike state; cosmetic replay never applies damage or XP.
- Native context changes are bounded to the relevant call chain and restored; outside-pair actors retain original behaviour.
- Damage de-duplication applies to strike-impact-target events; account for native area/multi-part effects without mistaking every addWound call for a separate valid sword strike.

### Existing animation/body harness: exact capabilities and gaps

Inspected authoritative test wrapper for this audit:
C:\KenshiModding\components\KenshiFP\tests\ingame\fp-viewmodel.sh
It embeds vmcheck.py and generates it into each run folder; it is not a separately maintained global checker. C:\KenshiTestRuns\vmq-final2\vmcheck.py is an archived generated instance.

Live recording/replay implementation:
 /root/KenshiFP/client/kfp_viewmodel.inc, VmRec and kah_fp_vm.
Existing commands (future use, not executed here):
- fp_vm probe ; fp_vm bones <name-filter>
- fp_vm rec on ; fp_vm rec off ; fp_vm rec dump <absolute-file>
- fp_vm replay <frame-index> ; fp_vm replay <frame-index> t ; fp_vm replay off

Recorder captures both shoulder/elbow/wrist chains plus one measured weapon basis, one weapon-hand basis/wrist-bend value, head/neck/spine, camera basis, state, phase, time/dt and zoom. Capacity is 6000 frames and recording stops when full; segment long captures or add a truncation diagnostic. At 60 FPS that is about 100 seconds.

Crucial timing rule: measured bones in record n+1 correspond to what frame n rendered. The current checker remaps these into frame n's camera. Preserve that lag correction when joining pose data to strike/impact telemetry.

Existing gates:
- PT30: per-frame motion spikes (dt-aware), commanded-pose error, draw/sheath visibility, arm-tube near-plane cuts and on-screen sword wrist bend <=30 degrees.
- PT29: zoomed-out viewmodel fade, hand/weapon distance from head, both wrists outside torso axis, weapon visibility, sword wrist and right-elbow placement; most geometry flags tolerate <=3% bad frames.
- VMQUICK: each current weapon at zoom 0/25, motion/state capture and labelled full-resolution sheets; run first for any future viewmodel build.
- Both arms are present in records and clipping checks, but weapon path/visibility and wrist-angle checks largely concern the active/main blade. Some test geometry uses a hardcoded 8 dm sword length, unsuitable for mixed dual swords.

This is a strong foundation for catching the reported impossible-looking poses. It is not a complete human biomechanics validator: inspected checks do not establish left/right joint-local swing/twist limits, shoulder/clavicle coupling, full-body self-collision, planted-foot balance or two-blade clearance. Treat the 30-degree wrist threshold as the project's grip-quality rule, not a universal medical limit.

Required future extensions, before accepting dual animations:
1. Record BOTH actual blade transforms, grip frames, dimensions, hand bases, wrist angles and item IDs. Add elbow flexion/signed bend and shoulder/forearm local rotations on both sides.
2. Include world transforms/rest limb lengths and actor scale; reject stretch beyond the documented rig tolerance. Missing/NaN/zero-length measurements are inconclusive/fail, not "0 degree" passing angles.
3. Check both blades against head/torso/arms with phase-aware geometry; check blade-to-blade and opposite-arm clearance. Intended blade crossing in a designed guard must be explicitly classified rather than hidden by a general exemption.
4. Apply limits to interpolated motion and blend transitions: draw, ready, left/right strike, recovery, block, hit reaction, interruption, sheath, camera entry/exit and pair changes.
5. Derive reach/visibility from each actual blade instead of the existing generic sword length. Cover short/long and unequal swords.
6. Preserve dt correction and separate real/game time. Report excluded hitch intervals and require enough eligible frames; "0 flags" with missing data is not a pass.
7. Hard-fail genuine hyperextension, self-intersection or invalid grip on any evaluated frame; do not inherit PT29's 3% tolerance for impossible-body states.
8. Capture full 1600x900 frames on open ground, FP and side/front world view, with both swords readable. Frozen/replayed inspection is useful but must be supplemented by full continuous transitions.
9. Store joint/clearance maxima and the first/worst frame index per side plus clear captures. Pair body checks with authoritative hit timing; a plausible-looking swing can still apply damage incorrectly.

No harness implementation was changed or run. If Shay meant a separate, more comprehensive body validator than this wrapper, it was not located by the scoped file/content searches; future agents should reuse it if supplied, without assuming these inspected checks certify its capabilities.

### Fixture and instrumentation readiness

Observed Commands.cpp:
- sections (around 2718) prints section names, dimensions, equip/container/enabled state and item names. It does NOT print per-item coordinates, handles or limitedSlot.
- iteminfo via DescribeItem (around 330) prints handle/container identity, invPos, slotType, base String ID, inventorySection, equipped, quantity and quality. Use different sword names for initial candidate comparisons; same-name item lookup can be ambiguous.
- equip tries native equipItem and, on failure, moves other equipped items with the same slot type into main storage, then retries. It does not invariably replace a weapon, but it cannot guarantee two-back placement.
- No documented arbitrary equipment-section placement command was located in the inspected command inventory.
- mouse_inject at <x> <y>, left down/up and UI/screenshot commands offer an existing native drag route on isolated test UI. It must be read back with iteminfo; never infer success from an input acknowledgment.

Future helper specification if native dragging is insufficient: accept actor handle, exact existing item handle, target section and coordinates; verify ownership, section constraints, footprint/fit and callbacks; move without cloning; rollback without item loss/drop on failure; return both item positions and identities. Prefer validated addItem/callback paths; SDK getValidInventoryPosition alone is not sufficient (existing source warns it can return an occupied 0,0). This is a future build task, not performed under the research-only instruction.

Existing fp_melee wounds ring holds 16 addWound records (victim, attacker, damage channels, area); it cannot independently identify the acting sword, technique impact or sequence. For per-blade proof, join candidate logs/bridge events to wounds and HP deltas; do not add wounds as a substitute for instrumentation. Drain/export diagnostics promptly in group tests to avoid ring overwrite.

### Conservative implementation defaults

These keep work actionable without turning uncertain preferences into approved requirements:
- Player squad only initially; NPC rollout disabled until strict pairing/ownership passes.
- Katana/sabre swords only, two distinct valid instances in back; no hip pairing or inventory resize.
- Existing dexterity/lower weapon-category proficiency initially; no new saved skill/UI/training tree.
- One accepted FP click, one alternating strike; right/main first on a new pair, failed requests do not advance alternation. No combos, automatic counters or twin damage in v1.
- Keep native aggro, block, reach and recovery semantics. Delayed awareness/stealth changes remain outside this scope.
- Initial clips: idle, right/left attack, right/left block, draw/sheath, clean native movement/reaction blending.
- Keep the earlier 100%/75% hand-power and speed/defence values as configurable experiment targets, not accepted final tuning.
- Unsupported limbs/skeletons use safe ordinary combat and explain the fallback.

Candidate overlay is selected only if strict back-only pairing, one-click scheduling, final-pose ownership and per-blade/KEP correctness can all be demonstrated. Nitoryu's broader default eligibility and documented custom-two-arm-clip limitations make it an evaluation candidate, not a guaranteed foundation.

### Follow-up evidence pins and stopping point

Live FP HEAD remains ad419c03908616f35cb0c57fc194a1e41f715464; dirty files now include kenshifp_client.c, kfp_controls.inc, kfp_view.inc and kfp_viewmodel.inc. Another session is still doing FP work. The game lock file still reads fixer-pt30. No lock acquisition or game interaction was attempted.

SHA256 at inspection:
- live client/kfp_controls.inc: 9D22F0773F148BA8D0A485A8CC687B5710FB01CE867A677898C122859A3FE264
- live client/kfp_viewmodel.inc: 088CAE8423830ADA60BC02B2732C339E4253A0403003C071CFBDE7FD97882AA3
- live client/kfp_combat_melee.inc: 18155B3B07EC8B8D1AD5F5CB667A54B391B2CC061FFEA3BF1CC3FE61A055CD21
- snapshot tests/ingame/fp-viewmodel.sh: E2C60F643359C4C9F9A723CC74D9A780873DF780D2734211384305AE01C4700B
- harness src/Commands.cpp: AF47A1E88BB1E3C4C8921E046F8CCABCF279612AEC9A93422466AC9057EA76C7

Research downloads remain excluded by the reference directory's existing .gitignore. No source code, game config, load order, DLL, test wrapper or saved game was changed. This follow-up changes documentation and stages inactive reference inputs only.

Additional primary references:
- Exporter repository: https://github.com/Lucius64/kenshi_io_blender
- Version/platform/hash index: https://lucius64.github.io/kenshi_io_blender/index.json
- Installation/version routing: https://github.com/Lucius64/kenshi_io_blender/blob/main/docs/Installation_extension.md
- Export options: https://github.com/Lucius64/kenshi_io_blender/blob/main/docs/Option_description.md
- Official templates: https://lofigames.com/updated-modders-pack-now-available/
- Alternative exporter: https://github.com/Kindrad/Kenshi_IO_Continued ; redirected upstream https://codeberg.org/Kindrad/Kenshi_IO_Continued
- KEP source: https://github.com/Lucius64/KenshiExtensionPlugin (local pin above)

Remaining uncertainties are now explicitly categorized as source/permission availability, user preference or executable proof. Next phase is the controlled candidate evaluation plus authoring-toolchain round trip. Those are intentionally outside this research-only checkpoint.
