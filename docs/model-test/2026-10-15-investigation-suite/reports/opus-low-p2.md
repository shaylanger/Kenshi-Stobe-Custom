## Summary
These are two separate server bugs, and both are confirmed from the logs and the database. I changed no files.
1. **"Emperor Tengu":** the server has a list of unique NPC bios, and it is matched by name only. That list contains a bio for the bare name "Tengu" (the Emperor). So the first time any NPC named Tengu speaks, she gets the Emperor's bio. Here that was a female Shek Anti-Slaver in Spring.
2. **"I haven't agreed to that job":** the model answered "You are not Emperor Tango" with its own action, `MOVE_TO_TARGET@Shay` (walk up to Shay). The check for orders from the player treated that as a request from you that she had refused. It then replaced her whole spoken line with a stock refusal. You never asked her to do anything.

## Root cause
1. `selectBioTraitsForNpc()` → `loadBioUniqueTraitSelections($name)` in `lib/data_functions.php` (lines 5413–5455, 5677–5695) looks up `combined_bio_unique WHERE LOWER(name) = <npc name>`. It does not check race, faction or gender. A unique bio, when one is found, overrides every random trait. `bio_unique` has a set of rows under the bare name `Tengu` with the Emperor's bio, separate from the `Emperor Tengu` rows. The result was saved once into `core_npc_master` and is reused on every chat.
2. In `stobeTravelValidateOrders()` (`lib/travel_companionship.php` 537–565), every action the model emits is run through `stobePlayerOrderGate()` (`lib/chat_helper_functions.php` ~15897–15926).
   - `MOVE_TO_TARGET` is in `stobeNonFactionMinorOrderCommands()`. Tengu's trust in you was below the threshold (she is at -13 now), so the gate falls through to `return "I haven't agreed to that job.";`.
   - The caller then runs `$text=$why;`, which throws away her real line and speaks the refusal instead.
   - The gate never checks whether the player actually asked for the action, so a move she chose herself gets refused as if it were your order.

## Evidence
- **Database**, `public.core_npc_master` id 85663, created 2026-10-15 03:49:19: name `Tengu`, faction `Anti-Slavers [58229-Dialogue.mod]`, race Shek, female, occupation `Emperor of the United Cities.`, backstory `United Cities emperor raised in luxury while nobles enforce his rule.`
- **Database**, `public.bio_unique`: rows `Tengu|personality|Entitled, theatrical...`, `Tengu|backstory|United Cities emperor...`, `Tengu|occupation|Emperor of the United Cities.`, plus speechstyle and goals. There is also a separate full set under `Emperor Tengu`.
- **Seed file:** `data/schema.sql:3407`, `('Tengu', 'occupation', 'Emperor of the United Cities.')`, inside the `INSERT INTO bio_unique` block at line 3390.
- **Prompt log:** `log/context_sent_to_llm.log` ~line 1916810, in the prompt for "What's up, Tango?". It contains "Tengu is a Shek aligned with Anti-Slavers" next to "## Basic Summary United Cities emperor..." and "## Occupation Emperor of the United Cities." Her first reply was: "'Tango'? You address an emperor, peasant."
- **Server log** `log/stobeserver.log`:
  - 01:52:38: `Shay: You are not Emperor Tango. (talking to: Tengu)`.
  - 01:52:47: `LLM stream response generated ... "actions":["MOVE_TO_TARGET@Shay"]`.
  - 01:52:47: `Order rejected before speech {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}`.
  - 01:52:47: the stored infoaction line `Tengu: REJECTED MOVE_TO_TARGET@Shay; not dispatched. I haven't agreed to that job.`.
  - 01:52:48: the spoken line `Tengu: I haven't agreed to that job.`.
  - 01:52:58: her next reply builds on the refusal ("Stop inventing work for me"), and a relationship note was written to match.

## What you ruled out
- **Not a mix-up between two NPCs.** The live NPC is a separate handle (`hand_130004880`) and her profile is her own row.
- **Not the world-lore text.** The Longen entry mentions "Emperor Tengu", but her identity came from her own profile.
- **The rejection came from no existing deal or job.** No travel or deal state was involved, and the gate's fallthrough line is fixed text.
- **Not the model inventing the job by itself.** The line is the server's constant, not model text.

## Proposed fix
**A. Unique bios must also match race/faction (`lib/data_functions.php`, `selectBioTraitsForNpc`).** Pass race, faction and gender into a check, and drop the unique bio when it clearly belongs to someone else. The simplest sound rule: when the unique bio has an `appearance` or `backstory` row, use it only if the NPC's race is named in it, or the faction matches.

The better long-term fix is to key unique bios to the game's string ID instead of the display name, if the native side sends one.

Minimal guard:
```diff
 function selectBioTraitsForNpc(string $name='', string $race='', string $gender='', string $faction='', string $originalName=''): array {
     $requiredTypes = getRequiredBioTraitTypes();
     $uniqueSelections = loadBioUniqueTraitSelections($name);
+    if (!stobeBioUniqueMatchesNpc($uniqueSelections, $race, $gender, $faction)) {
+        $uniqueSelections = createEmptyBioTraitSelections();
+    }
```
Here `stobeBioUniqueMatchesNpc` is a new function:
- It returns true when a `bio_unique_identity` setting (race/faction per unique name) matches the NPC, or when no identity is recorded.
- Otherwise it returns false if the unique text names a race different from the NPC's race (Scorchlander vs Shek), or a gender that does not fit.

**Data:**
- In `data/schema.sql` (~3402–3407), and in the database (`DELETE FROM bio_unique WHERE name='Tengu'`, done by you), remove the bare `Tengu` rows, or rename them to `Emperor Tengu`. The real Emperor already has a full set under that name. Check whether the in-game Emperor's display name is just "Tengu"; if it is, keep the rows but rely on the guard.
- Then reset Tengu's saved profile so it is built again: `core_npc_master` id 85663 (occupation, backstory, personality, speechstyle, goals), or delete the row and let it be recreated.
- Also clear the relationship note "Tengu accuses Shay of inventing work..." in `extended_data`.

**B. Don't treat the NPC's own actions as refused orders (`lib/travel_companionship.php`, `stobeTravelValidateOrders`).** Gate minor moves only when the player actually asked for one. When the gate rejects an action the NPC chose herself, drop it quietly and keep her line:
```diff
         $why=stobePlayerOrderGate($actor,$npc,strval($action));
         if ($why === '') { $kept[]=$action; continue; }
+        $cmd=strtoupper(explode('@',$action,2)[0]);
+        $selfInitiated = in_array($cmd, stobeNonFactionMinorOrderCommands(), true)
+            && !stobePlayerRequestedMovement(strval($GLOBALS['STOBE_LAST_PLAYER_TEXT'] ?? ''));
+        if ($selfInitiated) {
+            stobeLogInfo('Self-initiated minor action dropped (not a player order)',['actor'=>$actor,'action'=>$action]);
+            continue;   // keep $text; NPC just doesn't move
+        }
         storeEvent('infoaction',...);
         $text=$why;
```
- `stobePlayerRequestedMovement()` is a keyword check on the player's last line: follow / come / go to / move / guard / wait / travel / escort.
- Use whatever variable already holds the player's input in this request path.
- A smaller alternative: in `stobePlayerOrderGate`, return `''` for `MOVE_TO_TARGET@<speaker>` and `FACE_TARGET@<speaker>`. Stepping up to the person you are talking to is never a job.

## How to confirm the fix worked
- **A:** run `selectBioTraitsForNpc('Tengu','Shek','female','Anti-Slavers')` in a small PHP check. It should return random traits; today it returns the Emperor's. Add that case to the regression tests. In game, start a fresh chat with Spring's Tengu: the prompt in `context_sent_to_llm.log` must not contain "Emperor".
- **B:** use NEG_TEST_INJECT to inject a model reply of `{"text":"...","actions":["MOVE_TO_TARGET@Shay"]}` for a low-trust non-faction NPC after "You are not Emperor Tengu".
  - Expected: her line is kept, the log shows "Self-initiated ... dropped", and there is no "Order rejected before speech".
  - "Follow me" must still be refused with the travel line.
  - Then run `stobe-tests` (offline).

## What is not settled
- Whether the real Emperor's in-game name is plain "Tengu". If it is, the race/faction guard is required and deleting the bare rows is not enough.
- Whether the native side sends a stable string ID that bios could be keyed to instead of names.
- How many other bare-name unique rows can collide with common NPCs, for example "Beep" or "Agnu". A check of `bio_unique` names against generic NPC names would show this.
- Where the player's last line is held in the chat path for the proposed `stobePlayerRequestedMovement` check (I did not trace it).
- The live tree has uncommitted changes to `lib/chat_helper_functions.php` and `lib/data_functions.php` (git status). Line numbers above are from the working copy.
