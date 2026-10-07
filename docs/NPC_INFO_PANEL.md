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

## Card layout (biography card, 2026-10-07)
Header: portrait (in-game atlas image, name-initial fallback; portraits off for the session after a fault), name,
Job, Faction, race/looks line, Relationship (tier label + line, for the SPEAKING character), "Talked N times, first
met ..." (conversations split by 1 game hour of silence). No limb HP or stats.
Body (word-wrapped ListBox; Kenshi's read-only multi-line EditBox shows only one line):
1. ABOUT THEM: looks/race, job, faction in one sentence.
2. WHAT YOU'VE LEARNED: a 2-5 sentence bio written by the LLM ('relationship' purpose connector) ONLY from what the
   NPC said to the speaker (chat/inputtext eventlog rows holding both; lines addressed to someone else skipped) and
   their disclosed facts. Never the hidden backstory. Empty bio = "You haven't learned anything ..." text or the
   disclosed facts list.
3. DEALINGS WITH <speaker>: active deals with progress/deadline/status, outstanding payment, earlier deals.
4. RIGHT NOW: agreed goal (status, n/m, step, blocker) + "Doing now" live activity.
Job = bracket title in the name > "Trader" if trading > occupation they told you. The stored `occupation` column is
never shown (often hidden profile text).

## Bio caching (two-phase)
- First request (`bio=0`) never calls the LLM: returns the cached bio (or `pending`) and `bio_stale=1` when new
  dialogue exists; the DLL worker then sends a second POST with `"bio":1`.
- `bio=1` regenerates at most once per 60 s per (NPC, speaker) and only when there is new dialogue; table
  `stobe_npc_bio`. Logs `NPC_BIO: generated|cache hit|throttled|llm returned nothing`.
- Rollback prunes `stobe_npc_bio` rows newer than the cutoff (count key `npc_bio`).

## Told vs hidden rules
- Never shown: hidden backstory, goals, hidden thoughts, model/profile/voice, prompts, raw metadata.
- Facts are only recorded when the NPC states them about themselves to the listener: the relationship evaluator
  (`stobeEvaluateRelationshipsForTurn`, one existing LLM call per chat turn) now also returns `disclosed`
  (max 2, category background|interest|occupation|history, no inference). Stored in `stobe_npc_learned_fact`
  keyed by storage_id (`hand_<serial>`) + learner, deduped. Old conversations are NOT back-filled.
- Opening/refreshing makes no LLM call except the throttled bio regeneration above. HTTP runs off the game thread;
  late replies for another target/speaker (generation + key) are dropped.

## Files
- Server (StobeServer `2596ef2`, bio card `7ea8347`, branch `stobe`): `lib/npc_player_view.php`, `ai_npcs.php` action
  `player_view`, evaluator prompt/parse/record + first-person background gate regex in
  `chat_helper_functions.php`, rollback prune `npc_facts`, regression `tests/npc_player_view_regression.php`.
  (The one-off patch scripts were removed 2026-10-06; git history.)
- DLL (`components/STOBE`): Globals.cpp/.h, Utils.h/.cpp,
  mod/Stobe.ini, AutonomySafetyProbe.h/.cpp, AiNpcInfoWindow.h/.cpp (new window), ChatBox.cpp, Comm.cpp (route),
  StobeHarnessBridge.cpp, main.cpp.
- Test: `tests/ingame/stobe/STOBE-NPCPANEL.sh [NP1..NP12]` (NP9 portrait, NP10 fresh stranger basics + empty bio + no LLM, NP11 bio after 3 chat lines, NP12 cache hit; NP10-12 spawn a "Stranger HHMMSS" Drifter) (Crafting base copy `kah-npcpanel`).

## Status
List panel built into Stobe since DAF1390F (2026-10-05, NP1-NP8 verified, `archive/test-run-2026-10-05-m41.md`).
Biography card: Stobe 3EF4CCEE + server 7ea8347 (2026-10-07), in-game rows NP1-NP12 see the m51 run log.

## Limitations
- Goals are matched by actor_serial, or by name when the goal row has no serial.
- Occupation shows only if told or seen trading.
- Facts come only from chat turns after the deploy, and only when the relationship evaluator connector runs
  for that turn (gate regex + chance).
