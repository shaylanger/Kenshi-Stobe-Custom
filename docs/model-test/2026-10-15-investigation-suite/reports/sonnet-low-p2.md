Summary
Both symptoms trace to server data and server rules, not game-side bugs.
1. Tengu believed she was Emperor Tengu because the database holds the emperor's biography under the plain name "Tengu".
2. "I haven't agreed to that job" is a hard-coded refusal. It fired when the model proposed a move-to-player action after the player said "you are not emperor tango".

Root cause
1. The `bio_unique` table has rows for `name='Tengu'` (personality, backstory, speechstyle, occupation, goals). Their text describes the United Cities emperor. All five rows were written at 2026-09-25 05:19:30. The NPC row `core_npc_master` id 85663 (name Tengu, faction Anti-Slavers, race Shek) therefore carries the emperor backstory ("United Cities emperor raised in luxury while nobles enforce his rule.") and the occupation "Emperor of the United Cities." The import files only use the name "Emperor Tengu", so what created the plain "Tengu" rows is unknown.
2. After "you are not emperor tango", the model returned `MOVE_TO_TARGET@Shay`. `stobePlayerOrderGate()` in `lib/chat_helper_functions.php` treats `MOVE_TO_TARGET` as a minor order for non-faction NPCs. Tengu is not in the player's faction and her affinity was below the trust minimum (default 56). The function falls through to its final default refusal, "I haven't agreed to that job." The text is generic and does not mean any job was started.

Evidence
- `stobeserver.log`, 2026-10-15 01:52:47: `Order rejected before speech | {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}`. It follows the 01:52:38 event `Shay: you are not emperor tango`. The log line comes from `lib/travel_companionship.php:562`.
- `lib/chat_helper_functions.php`: line 15884 lists `MOVE_TO_TARGET` among the non-faction minor order commands; line 15925 is the final `return "I haven't agreed to that job.";`.
- `context_sent_to_llm.log`, around lines 1920889-1920900 and 1921119: the prompt says "Tengu is a Shek aligned with Anti-Slavers" followed by "United Cities emperor raised in luxury…", and it injects "Emperor Tengu" world-knowledge lines. Around line 1921249 the earlier reply reads "Emperor Tengu, if you want to keep that tongue."
- Database: `bio_unique` has the five `name='Tengu'` rows listed above. `core_npc_master` id 85663 has the emperor backstory and occupation.

What I ruled out
- No job, deal or goal was started. The log shows the action rejected before speech.
- The import files do not use the plain name "Tengu", only "Emperor Tengu". The Anti-Slavers faction is correct for this NPC.

Proposed fix
1. Data: SELECT to confirm, then DELETE the five `bio_unique` rows with `name='Tengu'`. Clear or regenerate the personality, backstory and occupation fields of `core_npc_master` id 85663 so they fit a low-level Shek Anti-Slavers member. Apply this on the live tree and on ss-merge.
2. Code (optional hardening): make the unique-bio lookup skip a bio when the NPC's faction or race does not match the emperor entry. Alternatively, keep the emperor under "Emperor Tengu" only.
3. Order gate: in `stobePlayerOrderGate()`, stop a movement action firing on a purely conversational line such as a correction, for example by dropping `MOVE_TO_TARGET` when the player's message does not ask for movement. Or change the final default refusal text to something clearer, for example "I won't follow you around."

How to confirm the fix worked
- Run `select * from bio_unique where name='Tengu'`. It should return no rows, and row 85663 should no longer mention the emperor.
- Talk to Tengu again. Check that the prompt in `context_sent_to_llm.log` no longer describes her as an emperor. Say "you are not Emperor Tengu" and check that no `Order rejected before speech` line appears for her.

What is not settled
- Which process wrote the plain "Tengu" bio rows on 2026-09-25 is unknown. If it is a generator that renames bosses, it could recreate them.
- Whether other generic NPCs share boss names and have the same problem is not checked.
- Why the model chose a move action is unclear. It was probably a roleplay side effect ("I am walking. Walk with me").
