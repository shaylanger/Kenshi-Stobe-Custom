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
   their disclosed facts. The hidden backstory only at a high tier: when the SPEAKING character's tier with the NPC is
   `NPC_BIO_BACKSTORY_MIN_TIER` or higher (general_settings; default Devoted, so Devoted/Bonded; a tier name
   Acquaintance..Bonded or `off`), the prompt also gets the stored backstory in `<confided>` and the LLM retells it
   as what the NPC has confided to them, in its own words (never copied, never called a backstory/profile).
   Empty bio = "You haven't learned anything ..." text or the disclosed facts list.
3. DEALINGS WITH <speaker>: active deals with progress/deadline/status, outstanding payment, earlier deals.
4. RIGHT NOW: agreed goal (status, n/m, step, blocker) + "Doing now" live activity.
Job = bracket title in the name > "Trader" if trading > occupation they told you. The stored `occupation` column is
never shown (often hidden profile text).

## Bio caching (two-phase)
- First request (`bio=0`) never calls the LLM: returns the cached bio (or `pending`) and `bio_stale=1` when new
  dialogue exists; the DLL worker then sends a second POST with `"bio":1`.
- `bio=1` regenerates at most once per 60 s per (NPC, speaker) and only when there is new dialogue; table
  `stobe_npc_bio`. Logs `NPC_BIO: generated|cache hit|throttled backstory=0|1` and `NPC_BIO: llm returned nothing`.
- Each cached bio is marked `backstory_included`. A tier crossing either way (e.g. a grudge drops her below
  Devoted) makes the bio stale and regenerates it at once (skips the 60 s throttle unless the last attempt
  failed); a confided bio is hidden immediately from a speaker below the tier. Card field `bio_backstory=1|0`
  (1 = the shown bio used the backstory); the DLL ignores it, tests read it from the server (`srv_view`).
- Rollback prunes `stobe_npc_bio` rows newer than the cutoff (count key `npc_bio`).

## Told vs hidden rules
- Never shown: goals, hidden thoughts, personality, relationship notes, model/profile/voice, prompts, raw metadata
  (at every tier; they never reach the bio prompt). Hidden backstory: never shown verbatim; below
  `NPC_BIO_BACKSTORY_MIN_TIER` never used; at/above it only through the bio, as what the NPC confided.
- Facts are only recorded when the NPC states them about themselves to the listener: the relationship evaluator
  (`stobeEvaluateRelationshipsForTurn`, one existing LLM call per chat turn) now also returns `disclosed`
  (max 2, category background|interest|occupation|history, no inference). Stored in `stobe_npc_learned_fact`
  keyed by storage_id (`hand_<serial>`) + learner, deduped. Old conversations are NOT back-filled.
- Opening/refreshing makes no LLM call except the throttled bio regeneration above. HTTP runs off the game thread;
  late replies for another target/speaker (generation + key) are dropped.

## Files
- Server (StobeServer `2596ef2`, bio card `7ea8347`, confided backstory `bf31d12`, branch `stobe`): `lib/npc_player_view.php`, `ai_npcs.php` action
  `player_view`, evaluator prompt/parse/record + first-person background gate regex in
  `chat_helper_functions.php`, rollback prune `npc_facts`, regression `tests/npc_player_view_regression.php`.
  (The one-off patch scripts were removed 2026-10-06; git history.)
- DLL (`components/STOBE`): Globals.cpp/.h, Utils.h/.cpp,
  mod/Stobe.ini, AutonomySafetyProbe.h/.cpp, AiNpcInfoWindow.h/.cpp (new window), ChatBox.cpp, Comm.cpp (route),
  StobeHarnessBridge.cpp, main.cpp.
- Test: `tests/ingame/stobe/STOBE-NPCPANEL.sh [NP1..NP12]` (NP9 portrait, NP10 fresh stranger basics + empty bio + no LLM, NP11 bio after 3 chat lines, NP12 cache hit; NP10-12 spawn a "Stranger HHMMSS" Drifter; NP13 trader set to Devoted (85) -> bio_backstory=1, `backstory_included`=1, `NPC_BIO ... backstory=1`; NP14 set to Acquaintance (20) -> all 0; both via `scenarios.sh trust`, a test backstory is written if the trader has none, the trader is put back to Fond 60) (Crafting base copy `kah-npcpanel`).

## Status
List panel built into Stobe since DAF1390F (2026-10-05, NP1-NP8 verified, `archive/test-run-2026-10-05-m41.md`).
Biography card: Stobe 3EF4CCEE + server 7ea8347 (2026-10-07), in-game rows NP1-NP12 see the m51 run log.
Confided backstory at Devoted+: server bf31d12 (2026-10-07, server-only, no DLL change), offline
`npc_player_view_regression` section 3c; in-game NP13/NP14 open (MASTER section 1).

## Limitations
- Goals are matched by actor_serial, or by name when the goal row has no serial.
- Occupation shows only if told or seen trading.
- Facts come only from chat turns after the deploy, and only when the relationship evaluator connector runs
  for that turn (gate regex + chance).
