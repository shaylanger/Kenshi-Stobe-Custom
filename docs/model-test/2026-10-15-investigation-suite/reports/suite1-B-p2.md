**Summary**

Both problems have one source each, and they are separate bugs.

1. **"Emperor Tengu":** the server gives an NPC a unique biography by matching on name only. The character is just named "Tengu", and the server's seed data has a bio entry called "Tengu" that describes the Emperor. She was handed the Emperor's personality, backstory, occupation and goals, even though her faction is Anti-Slavers.
2. **"I haven't agreed to that job":** you never gave her a job. The model chose a movement action on its own, and a server gate meant for player orders refused it. The gate then replaced her whole spoken reply with its canned refusal line.

**Root cause**

1. `loadBioUniqueTraitSelections()` and `selectBioTraitsForNpc()` in `lib/data_functions.php` (lines about 5413 and 5685) look up `combined_bio_unique` by lower-cased name only. They ignore faction, race, gender and `lock_profile`.
2. `data/schema.sql` lines 3404-3408 seed `bio_unique` rows named plainly `'Tengu'`:
   - personality "Entitled, theatrical, and insulated from consequences."
   - occupation "Emperor of the United Cities."
   - backstory "United Cities emperor raised in luxury while nobles enforce his rule."
   - goals "Maintain noble control, tribute flow, and personal comfort."
   - speechstyle "Imperious tone with abrupt demands and mockery."
3. `data/import/kenshi_boss_bio_unique_upsert.sql` (lines 75-80) separately seeds the real `'Emperor Tengu'`. So the plain `'Tengu'` seed is the one that catches your low-level NPC.
4. Every NPC called Tengu is therefore given the Emperor's bio. The chat prompt reinforces this by also injecting the world-knowledge entries "Emperor Tengu" and "Beautiful Tengu: A Tribute".
5. For the second problem, `stobePlayerOrderGate()` (`lib/chat_helper_functions.php` line 15898) is applied to every action an NPC emits that sits in `stobeNonFactionMinorOrderCommands()`. That list includes `MOVE_TO_TARGET`. If trust is below the threshold, it returns "I haven't agreed to that job." (line 15925).
6. `stobeTravelValidateOrders()` (`lib/travel_companionship.php` lines 538-566) runs this gate and overwrites `$text = $why`. It never checks that the player actually asked for anything.

**Evidence**

- Database, `core_npc_master` id 85663:
  - name "Tengu", female Shek, faction "Anti-Slavers [58229-Dialogue.mod]", profile_id 1, `lock_profile` false.
  - occupation "Emperor of the United Cities.", backstory "United Cities emperor raised in luxury…". These are the seed strings.
  - extended_data has `relationships.Shay`: aff -13, note "Tengu accuses Shay of inventing work and insults her worth."
- Database, `bio_unique` has both a `Tengu` and an `Emperor Tengu` set of rows.
- `context_sent_to_llm.log` lines 1921247-1921260 and 1922161-1922179, in the prompt for the earlier reply (the "Tango" line):
  - The character data reads `occupation: "Emperor of the United Cities."` with `current_native_faction: "Anti-Slavers"`.
  - Her earlier lines were "'Tango'? You address an emperor, peasant…" and "It is Tengu. Emperor Tengu, if you want to keep that tongue."
- The "Tango" in your line was already in the conversation. You said "You are not Emperor Tango." (shown in `stobeserver.log` as `data_preview`).
- `stobeserver.log` 01:52:38 to 01:52:48, request `req_6ad031e617a02`. The record in `chat_llm_full_capture.log` line 151 shows the model's real reply:
  - message: `"Tango" again. You are either deaf or you enjoy bleeding. I am walking, peasant, and you are in my way. Step aside.`
  - action: `MoveToTarget`, target `Shay`
- Right after it, the server logged:
  - `Order rejected before speech {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}`
  - `Tengu: REJECTED MOVE_TO_TARGET@Shay; not dispatched. I haven't agreed to that job.`
  - TTS then spoke the refusal text.
- Her next prompt shows the stored line "Tengu, speaking to Shay: I haven't agreed to that job." and your reply "I didn't give you a job." The model's own message was lost.

**What you ruled out**

- Speech-to-text. "Tango" came from the model, and your typed line "You are not Emperor Tango" is logged as you entered it.
- A real job or deal. No `WORK_GOAL` or travel state existed, and the action was only a requested move.
- A client-side (game DLL) fault. The server received `profile=Tengu` and built the bio itself.
- A problem in the Anti-Slavers faction data. The prompt correctly carried `current_native_faction: "Anti-Slavers"`, but nothing uses it to veto the unique bio.

**Proposed fix**

Part A, the identity mix-up:

1. Delete the plain `'Tengu'` rows from `bio_unique`, and from the seed in `data/schema.sql` lines 3404-3408. The `Emperor Tengu` rows already cover the real Emperor.
2. Make unique-bio lookup safer in `selectBioTraitsForNpc()`. For names that are also ordinary Kenshi first names, require that the NPC's faction or race matches before using a unique bio. Treat `lock_profile` or an explicit "boss" flag as the only override. A simple form is a `required_faction` / `required_race` column on `bio_unique` that `loadBioUniqueTraitSelections` checks against the NPC.
3. Clear the stale values on the existing record. Reset NPC id 85663 so it falls back to random Anti-Slaver bio traits. Use the profile editor or regenerate the profile. I did not touch the database.
4. Check other short-name seeds such as "Beep" for the same pattern.

Part B, the "job" refusal:

1. In `stobeTravelValidateOrders()` (`lib/travel_companionship.php` around line 557), only gate and override the text when the player actually asked for the order. For example, check that the player's message contains an order or request and the action is a response to it. Otherwise drop the action silently and keep `$text`.
2. Roughly:

```php
$why = stobePlayerOrderGate(...);
if ($why === '') { $kept[] = $action; continue; }
// unrequested NPC-initiated move: drop the action, keep the NPC's own words
if (!stobePlayerRequestedOrder($speakerMessage, $action)) { continue; }
$text = $why;
```

3. The same overwrite appears in the other call site in `chat_helper_functions.php` (`$message = $orderRefusal;` near line 16138), so apply the same condition there.
4. Also make the refusal wording pick a neutral phrase rather than "job" when no order was given, if you want to keep refusing the move.

**How to confirm the fix worked**

1. Query: `SELECT name,type FROM bio_unique WHERE name='Tengu'` should return no rows.
2. Reload a save with a non-Emperor NPC named Tengu and check that her `occupation` and `personality` are no longer the Emperor strings.
3. In-game, say "You are not Emperor Tengu" to that NPC. She should no longer claim to be the Emperor.
4. A grep of the log for `Order rejected before speech` should not appear for an NPC-initiated `MOVE_TO_TARGET` when you did not ask for a move.
5. Add a regression check beside `tests/negotiation_engine_regression.php`. It should confirm that an NPC move that the player never requested keeps the model's spoken text.

**What is not settled**

- I did not find which seed file created the plain "Tengu" rows. `data/schema.sql` carries them, but the database may also hold them through an import, so check for it.
- I did not see which prompt line first made her answer to "Emperor" at the very start of the chat. The cause is almost certainly the Emperor bio, but I did not read that first turn.
- Whether you want Part B to drop the action silently or let the model reply normally is a design decision.
- I do not know whether any real Emperor NPC in your save uses a different name, such as "Tengu" alone. If one does, Part A step 2 has to protect it.
