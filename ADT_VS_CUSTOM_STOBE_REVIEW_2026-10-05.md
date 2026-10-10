# ADT 1.1.0 vs Shay's custom STOBE: source review
Date: 2026-10-05. Package: C:\Users\Shay\Downloads\3798433371.
Scope: static review of readable Lua/Python, settings and representative content, compared with current custom STOBE native/server source and CUSTOM_CHANGES.md. No ADT installation, execution or gameplay benchmarking. Native engine DLL source is not included in the inspected package, so engine binding correctness is not fully auditable. This is a substantial targeted review, not a claim to have audited every file.

## Finding
ADT is broader as a player-facing narrative/content-authoring toolkit. Custom STOBE has substantial overlapping dialogue/memory/lore/UI capabilities and more developed persistent work/task execution, negotiated deals and event-driven social consequences. More visible NPC dialogue in screenshots does not prove a superior underlying NPC-life simulation.

## Confirmed additions or materially different systems

### 1. Multi-stage player quests and in-game quest authoring
ADT supplies definition storage, editor mutations, validation/publication, frozen accepted revisions, per-character journal/tracker, objective evidence, schedules, optional activities, required handoffs and reward settlement.
Capabilities include talking to exact people or N distinct people, visiting/leaving/returning to cities, regions, possession, exact item/Cats transfers, buying/selling, waiting game days, participating in distinct combat sessions, exact Written document interactions and target/giver survival guards.
The package contains 20 quest definition files; representative inspected definitions are enabled and published. This count is content files, not 20 gameplay-validated scenarios.
Examples:
- Trader Spread the Word: talk to eight distinct people in the trader's city, then report for 750 Cats.
- Military Field Experience: visit Border Zone, participate in three battles, report for 3,000 Cats. Its battle condition is not restricted to Border Zone: prose and mechanical conditions differ in scope.
- Caravan Guard Contract: wait three game days with giver alive, report for payment, optional daily provisions. This does NOT prove escort proximity, route completion or a fully simulated travelling caravan.
STOBE has real contracts, production/task goals and deadline/term verification, but no equivalent general-purpose authored multi-stage player quest editor/catalog was found. An NPC making items for you and the player completing a staged employer quest are different directions of gameplay.
Evidence: runtime/engine/plugins/quests/{capability_registry,objective_engine,definition_store,editor_service,stage_settlement}.py; scripts/init/18d* and 18g*/18h* quest UI; QUEST_CREATOR_GUIDE.txt.

### 2. More explicit radiant scene composition and scheduling
ADT chooses a focal character from non-player candidates when available, then builds weighted scene tickets for general, same-faction, animal and player-squad scenes. Weights are multiplied by eligible population; weights are not simple percentages and are clamped to 1-100, so setting zero does not disable a category.
Default settings: single_prompt, 6 conversation lines, maximum 6 speakers/candidates, range 100, scan delay 2,000 seconds. Scheduling uses accumulated active real seconds while the loaded game is unpaused, not Kenshi game hours. Defaults therefore do NOT demonstrate more frequent chatter than our one-game-hour timer.
One model request normally authors the exchange; optional per-turn generation and an optional Director route can add requests. Deferred triggers remain pending with bounded scheduling rather than all opportunities being discarded when busy.
STOBE already has bored/rechat NPC exchanges and one-request Director scenes. Its periodic candidate selection lacks ADT's explicit scene-category policy. The opportunity is weighted selection, scheduling, concise scene budgets and integration of continuity, not rebuilding group dialogue.
Evidence: scripts/init/11c_radiant_scene_director.lua, 15x_radiant_queue.lua, 15z_automation.lua; runtime/engine/{radiant,feature_automation}.py; settings/settings.txt. STOBE: src/main.cpp and ChatBox.cpp; processor/{bored,rechat}.php; lib/director_scene.php.

### 3. Dedicated battle-start/ongoing group dialogue
ADT observes player-squad combat sessions and sends a compact one-request scene with at most three speaking combatants plus bounded overhearers. Ongoing repeats default to 16 seconds, subject to queue/player priority and session validity. Battle dialogue disables actions/trade and does not perform the ordinary heavy history/biography path.
STOBE captures combat facts and uses them in dialogue, urgency, negotiation and social consequences. No equivalent dedicated three-speaker combat-session scheduler with repeating compact exchanges was found in inspected current native sources. Combat-aware normal chat is not the same feature.
Evidence: scripts/init/06e_game_combat_monitor.lua, 12c_flow_battle_radiant.lua, 15x_radiant_queue_battle.lua; runtime/engine/radiant.py _run_battle_start. STOBE: processor/combat.php, lib/lifelike_npc.php, structured combat dialogue contracts.

### 4. Private temporary thoughts
ADT can accept an NPC's unspoken thought alongside ordinary sapient chat, store it by exact NPC/player pair, and feed it back into later relevant prompts. Thoughts expire by interaction/game-time policy, can link to a quest stage, and are excluded from public dialogue and ordinary memory extraction.
STOBE has memories, motives, goals and relationship context, but no equivalent dedicated expiring pair-specific hidden-thought store was found. This may preserve unresolved suspicion, hesitation or intention without turning private speculation into shared fact. It is model-authored fictional state, not evidence of deeper reasoning.
Evidence: runtime/engine/thoughts.py; feature_chat.py thought context/storage; response_protocol.py.
Potential implementation: bounded structured field in the existing response, no separate LLM call just to obtain a thought.

### 5. Written documents as owned transferable narrative objects
ADT offers writing/continuation/editing, ownership, exact IDs, Show, Give, Remember, multiple remembered papers, revision/provenance and document quest objectives/rewards.
Important: its Written inventory is separate from physical Kenshi item inventory. Do not describe these as automatically lootable/equippable physical books.
STOBE diary/adventure/history features overlap with writing a record, but an equivalent owned document exchange and quest system was not found. Value beyond a deals UI: delivering letters, showing evidence, collecting statements, introducing people via a specific document.
Evidence: runtime/engine/{character_inventory,feature_written,written_context}.py; scripts/init/18a2_written_workshop.lua; quest documents.py.

### 6. Context-sensitive music
SentientSongs includes a local audio library, folder/track inheritance, AND/OR scene rules, priorities, fades, activation delays, minimum holds and random silence. Conditions include battle, stealth, day/night, city, region and weather. No model call is required for rule selection.
No corresponding custom STOBE music controller found.
Evidence: runtime/engine/sentient_songs/{context_policy,service,library}.py; SentientSongs/README.txt.

### 7. Campaign content packages and authoring workflow
ADT has editable campaign content, shared faction-lore pages, ordered military/civil rank hierarchies and authority filters, profile modules, quest import/export, add-on preview/apply/update/repair/remove with file ownership records, and translation authoring tools.
STOBE already has playthrough isolation/transfer, world knowledge, faction biography guidance, random/unique biographies, portraits, model profiles and web editors. Those are NOT all missing. The additions are the integrated content-pack lifecycle, quest/rank authoring and in-game access.
Faction/rank narrative context alone does not mean native membership, promotion, command authority or a dynamic faction simulation. ADT documentation explicitly separates narrative faction from native diplomacy/recruitment.
Evidence: runtime/engine/{campaign_addons,faction_lore,faction_hierarchy,provisional_learning,temporary_profiles}.py; Workshop Tools; README.txt. STOBE: playthrough services, ui/world_knowledge.php, ui/stobenpcs.php and biography data.

## Things that are not established advantages
- TTS: inspected ADT speech paths call native Character say and append chat text. No NPC synthesis/provider pipeline was found in readable scripts/runtime/settings. This does not exclude an undocumented compiled feature, but voices are not a demonstrated ADT advantage. STOBE has explicit STT/TTS and voice delivery.
- General NPC approaches: NPC Initiative Enabled defaults to no. The inspected quest scheduler binds current-stage participants and exact player receivers; it is not a general every-stranger-approaches-you system.
- Raids: character.raid returns unavailable; /raid and /raid_town are disabled.
- Full native faction careers, continent simulation, generated cities and autonomous economy were not established.
- Physical written-item gameplay is not established by the roleplay inventory.
- Portraits, ordinary NPC conversations, memories, lore, diaries, per-feature model routing, real item trade and recruitment already overlap substantially.

## Where custom STOBE is more developed in inspected scope
- Recursive real production/resource planning and ongoing stock/fetch/build/medical/prisoner/guard goals.
- Negotiated terms, counters, payment timing, handover verification, deadlines, betrayal and reminders.
- Rich relationship types and custom combat/grudge/care/theft/recruitment consequences. ADT's current NPC/player personal relation store is a single -100..100 scalar; legacy trust/respect/grievance fields in other catalogs are not proof of three independent active values.
- Explicit voice input/output and streamed delivery.
- Existing mechanical injection/harness and extensive live-game regression workflow. No comparative reliability claim is possible without running ADT under equivalent fixtures.

## Recommended order for Shay
1. Improve radiant category selection, deferred scheduling and bounded battle exchanges. Highest direct benefit for feeling that NPCs talk to one another.
2. Add compact private temporary thoughts using existing responses and strict knowledge separation.
3. Build a small authored player-quest layer using existing receipts/actions/contracts before contemplating a full creator UI.
4. Expand shared faction/job/rank context where it adds distinct behavior. Reuse our lore/profile infrastructure.
Written objects and music are optional later systems. Do not duplicate the read-only NPC panel already being implemented by another session; latest inspected server commit is 2596ef2 for its player_view.

## Follow-up / evidence limits
No game changes or ADT runtime execution occurred. Dialogue quality, actual bubbles, native action success, latency, cost and compatibility with UWE/Kaizo require isolated gameplay validation. Some APIs are present but runtime-guarded/experimental; source presence is not successful game execution.
If implementing similar capabilities, create our own code/content. The downloaded LICENSE.txt is proprietary/source-visible and does not provide general permission to copy its implementation or assets into STOBE.
