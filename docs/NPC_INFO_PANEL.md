# NPC info panel (Stobe)

Compact, read-only "NPC Info" window for the character you are talking to. Shows what YOUR speaking squad
character knows about that NPC, never the NPC's hidden profile.

## Entry points
- Hotkey `\` toggles the panel for the current chat target (ini `NpcInfoHotkey` in `mod/Stobe.ini`, parsed by
  `SetNpcInfoHotkeyFromString`). Ignored while a text box has keyboard focus (so typing `\` in chat is safe).
- "Info" button in the Stobe chat window (next to Rename, `Stobe_ChatNpcInfoBtn`).
- The panel follows the chat target (switching NPC re-requests), refreshes every 10 s, has Refresh/Close buttons.
- Harness: `stobe-auto stobe_npcinfo open <target> [speaker] | chat | read | refresh | close` (`read` returns the
  text with newlines as ` | `, plus `key=<serial>|<speaker>`, `gen`, `loaded`).

## Sections
1. Identity: name, faction (live faction preferred), occupation only if they told you (`occupation` fact) or
   they are a trader ("seen trading"), else "unknown".
2. Deals with the speaking character: `stobe_social_contract` by npc_serial (name fallback) + player_name; active
   terms with progress, deadline (game hours left / overdue), outstanding payment, real status (in progress,
   breached, fulfilled ...), earlier deals listed separately.
3. Activity: agreed goal from `stobe_task_goal_runtime` / `stobe_work_goal` (status, n/m done, step, blocker
   reason) vs "Doing now" (live activity from the DLL, `DescribeCharacterLiveActivity`; "not visible" if none).
4. Relationship with the SPEAKING character: existing relationship map on `core_npc` (tier label + type),
   "No opinion ... yet (neutral)" if none. Not hard-coded to Shay.
5. What you know: facts the NPC disclosed to that speaker ("They told you (not verified)"), plus observed deals.

## Told vs hidden rules
- Never shown: backstory/bio, goals, hidden thoughts, model/profile/voice, prompts, raw metadata.
- Facts are only recorded when the NPC states them about themselves to the listener: the relationship evaluator
  (`stobeEvaluateRelationshipsForTurn`, one existing LLM call per chat turn) now also returns `disclosed`
  (max 2, category background|interest|occupation|history, no inference). Stored in `stobe_npc_learned_fact`
  keyed by storage_id (`hand_<serial>`) + learner, deduped. Old conversations are NOT back-filled.
- Opening/refreshing makes no LLM call (`/ai_npcs/player_view` is DB-only). HTTP runs off the game thread;
  late replies for another target/speaker (generation + key) are dropped.

## Files
- Server (StobeServer `2596ef2`, branch `stobe`): `lib/npc_player_view.php` (new), `ai_npcs.php` action
  `player_view`, evaluator prompt/parse/record + first-person background gate regex in
  `chat_helper_functions.php`, rollback prune `npc_facts`, regression `tests/npc_player_view_regression.php`.
  (The one-off patch scripts were removed 2026-10-06; git history.)
- DLL (`components/STOBE`): Globals.cpp/.h, Utils.h/.cpp,
  mod/Stobe.ini, AutonomySafetyProbe.h/.cpp, AiNpcInfoWindow.h/.cpp (new window), ChatBox.cpp, Comm.cpp (route),
  StobeHarnessBridge.cpp, main.cpp.
- Test: `tests/ingame/stobe/STOBE-NPCPANEL.sh [NP1..NP8]` (Crafting base copy `kah-npcpanel`).

## Status
Built into Stobe since DAF1390F (2026-10-05), all rows NP1-NP8 verified in game (run log `archive/test-run-2026-10-05-m41.md`).

## Limitations
- Goals are matched by actor_serial, or by name when the goal row has no serial.
- Occupation shows only if told or seen trading.
- Facts come only from chat turns after the deploy, and only when the relationship evaluator connector runs
  for that turn (gate regex + chance).
