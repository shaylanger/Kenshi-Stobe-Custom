## Summary

Both problems come from the server, not from the game or the model.

1. **She thought she was Emperor Tengu.** The Shek Anti-Slaver named "Tengu" was given the real Emperor's personality because her name matches a stray short-name seed row, `Tengu`, in the `bio_unique` table. Her stored profile says "Occupation: Emperor of the United Cities". The bio lookup uses the name only and never checks race, gender or faction.
2. **"I haven't agreed to that job."** You gave her no job. When you said "You are not Emperor Tango", the LLM replied with a normal in-character line and also added an action it chose itself, `MoveToTarget` on Shay. The server's player-order gate treated that action as an order from you, rejected it because her affinity (-5) is below the minimum (56), and replaced her whole reply with the canned refusal text. That text was then spoken and saved to the conversation history. No job was ever started.

## Root cause

**Issue 1.** `data/schema.sql` lines 3404-3408 seed `bio_unique` rows named `Tengu` ("United Cities emperor raised in luxury…", "Emperor of the United Cities."). The real Emperor already has proper rows under the name `Emperor Tengu`, so the short-name seed is redundant. `selectBioTraitsForNpc()` calls `loadBioUniqueTraitSelections($name)`, which does an exact lowercase name match on `combined_bio_unique` (`lib/data_functions.php` 5413-5480, called at 5685). Both profile-creation paths (`storeNpcProfile` ~9049 and `storeNpcSnapshot` 11026) pass race, gender and faction but only the name is used. Existing non-empty trait columns are never overwritten (`storeNpcProfile` upsert, lines 9177-9179), so the wrong traits persist.

**Issue 2.** `stobeTravelValidateOrders()` (`lib/travel_companionship.php` 538-565, called from `processor/chat.php:1970`) runs `stobePlayerOrderGate()` on every action a non-faction NPC emits, whether or not the player asked for anything. `MOVE_TO_TARGET` is in `stobeNonFactionMinorOrderCommands()` (`lib/chat_helper_functions.php:15885`). Trust -5 is below `stobeNonFactionOrderTrustMin()` (56). There is no accepted travel agreement, and `MOVE_TO_TARGET` is not one of the travel commands with a specific refusal line. So the gate falls through to its generic fallback, `return "I haven't agreed to that job."` (line 15925). Then line 561, `$text=$why;`, overwrites the NPC's real reply with that string. Line 560 also stores an `infoaction` "REJECTED …" event.

## Evidence

**Issue 1**
- DB `core_npc_master` row id 85663: name "Tengu", race Shek, gender female, faction "Anti-Slavers [58229-Dialogue.mod]".
  - Its personality is "Entitled, theatrical, and insulated from consequences."
  - Its occupation is "Emperor of the United Cities."
  - Its backstory is "United Cities emperor raised in luxury while nobles enforce his rule."
- `bio_unique` has 5 rows named `Tengu` (created 2026-09-25 05:19:30, same text as schema.sql). It also has 6 separate rows named `Emperor Tengu`, which come from `data/import/kenshi_*_bio_unique_upsert.sql`.
- The first history snapshot of that NPC (`core_npc_master_history`, history_id 115968) already holds the Emperor traits.
- `log/context_sent_to_llm.log`, first Tengu chat prompt (req_6ad0313d4e3da, 01:49:50 UTC, block starts at line 1916786): the character section reads "Tengu is a Shek aligned with Anti-Slavers", "United Cities emperor…" and "Occupation: Emperor of the United Cities".
  - The `# Knowledge` block of that prompt has no Emperor Tengu entry, so the profile alone caused the mix-up.
- Her first reply (logged at 01:50:00): "'Tango'? You address an emperor, peasant…". Later she said "Emperor Tengu, if you want to keep that tongue."
- Only in later turns did the world-knowledge entries "Emperor Tengu" and "Beautiful Tengu: A Tribute" appear. They were retrieved because the conversation now contained the word "Emperor", which reinforced the confusion.
- `combined_bio_unique` joined to `core_npc_master` on name gives 5 matches: Grey, Horse, Jaegar, Tengu, Tinfist.
  - Horse is a "Midland Hive Worker Drone" in the DB, but the unique bio says "A Shek treasure hunter…". That looks like the same name-only collision. I did not check which side is right.

**Issue 2**
- Server log (`log/stobeserver.log`, UTC), request req_6ad031e617a02, Shay: "you are not emperor tango":
  - 01:52:47 `LLM stream response generated … "actions":["MOVE_TO_TARGET@Shay"]`
  - 01:52:47 `Order rejected before speech | {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}`
- The raw model output (`log/output_from_llm.log`, line ~327280) was: message "\"Tango\" again. You are either deaf or you enjoy bleeding. I am walking, peasant, and you are in my way. Step aside.", with `"action": "MoveToTarget", "target": "Shay"`.
- `log/output_to_plugin.log` line 10041 shows what was sent to the game and voiced: `Tengu|ScriptQueue|I haven't agreed to that job.`
- The `eventlog` row stored: "Tengu: REJECTED MOVE_TO_TARGET@Shay; not dispatched. I haven't agreed to that job."
- The prompt's Dialogue Contract State said "Current player affinity: -5/100" and that minor outsider orders need 56+.
- Knock-on effect:
  - Next turn, the history showed "Tengu: I haven't agreed to that job." and you answered "I didn't give you a job."
  - She replied "Stop inventing work for me and I will stop pretending you are worth the breath."
  - The relationship worker (`output_from_llm.log`, 01:53:20) then applied aff_delta -8 with the note "Tengu accuses Shay of inventing work".
- It happened once. `Order rejected before speech` appears only this one time in the current `stobeserver.log`, and `I haven't agreed to that job` appears nowhere else.

## What I ruled out

- **Wrong name or race from the game.** The DB row shows Shek, female, Anti-Slavers, and the roster sends plain "Tengu".
- **Auto-rename.** The log says "Batch identity rename skipped (not eligible)", and no rename token is contained in "tengu".
- **A job actually started.** No WorkGoal, task or action row exists for Tengu. The only action was the model's `MoveToTarget`, which was "not dispatched". The only Tengu rows in `eventlog` with type infoaction or action in that window are the REJECTED line.
- **The model inventing the refusal.** The model's own text contained no mention of a job. The phrase exists only in server code (`chat_helper_functions.php:15925`).
- **World knowledge as the original cause.** It was not in the prompt before the word "Emperor" came up in the conversation.
- **`bio_unique_custom` override.** It has no Tengu rows.

## Proposed fix

**Fix 1: remove the bogus short-name bio, then clear her cached traits.**

a) `data/schema.sql`, delete lines 3404-3409 (in both `/var/www/html/StobeServer` and `/root/stobe-work/ss-merge`). This keeps a fresh install from re-seeding it. The real unique is `Emperor Tengu`, which stays.
```diff
-('Tengu', 'personality', 'Entitled, theatrical, and insulated from consequences.'),
-('Tengu', 'backstory', 'United Cities emperor raised in luxury while nobles enforce his rule.'),
-('Tengu', 'speechstyle', 'Imperious tone with abrupt demands and mockery.'),
-('Tengu', 'occupation', 'Emperor of the United Cities.'),
-('Tengu', 'goals', 'Maintain noble control, tribute flow, and personal comfort.'),
-
```

b) Live database. I did not run these, because I was read-only:
```sql
BEGIN;
DELETE FROM bio_unique WHERE name = 'Tengu';          -- exact name only; 'Emperor Tengu' stays
UPDATE core_npc_master
   SET personality='', backstory='', occupation='', speechstyle='', goals=''
 WHERE id = 85663 AND name='Tengu' AND race='Shek';
COMMIT;
```
- The reset is needed because the upsert keeps any non-empty existing value. Blank columns are refilled on the next snapshot sync from the random-bio pool, plus the faction-based occupation. Alternatively, edit the five fields in the NPC editor UI.
- Deleting the `Tengu` unique rows does not make her eligible for auto-rename, because no rename token is contained in "tengu".

c) Optional class fix. Name-only matching also hits other NPCs (see Horse). In `selectBioTraitsForNpc()` you could ignore the unique set when its `appearance` or `backstory` text names a race that conflicts with the live NPC's race. I did not test this, and `bio_unique` has no race column, so it is a heuristic.

**Fix 2: don't reject, and don't replace speech for, an order the player never gave.**

In `lib/travel_companionship.php`, add a helper above `stobeTravelValidateOrders` and pass the player's line in:
```diff
+/** True when the speaker's current line plausibly asks the NPC to move, follow, wait, guard or work. */
+function stobePlayerLineAsksForOrder(string $line): bool {
+    return preg_match('/\b(?:follow|come|go|walk|run|move|lead|escort|guide|take\s+me|meet|wait|stay|stop|hold|guard|protect|defend|watch|patrol|bring|fetch|carry|join|help|work|build|craft|mine|harvest|gather|travel|head|leave|let\'s)\b/i', $line) === 1;
+}
+
-function stobeTravelValidateOrders(string $actor, array|false $npc, string $speaker, int $gamets, string &$text, array &$actions): void {
+function stobeTravelValidateOrders(string $actor, array|false $npc, string $speaker, int $gamets, string &$text, array &$actions, string $playerLine = ''): void {
 ...
         $why=stobePlayerOrderGate($actor,$npc,strval($action));
         if ($why === '') { $kept[]=$action; continue; }
+        if ($playerLine !== '' && !stobePlayerLineAsksForOrder($playerLine)) {
+            // The model volunteered this movement/guard action; nobody asked. Drop it quietly:
+            // keep the NPC's own words and write no REJECTED event for an order never given.
+            stobeLogInfo('Unrequested order dropped',['actor'=>$actor,'action'=>$action]);
+            continue;
+        }
         // A rejection must never enter memory as an executed action.
```
`processor/chat.php:1970`:
```diff
-    stobeTravelValidateOrders($targetNpc, $npcData, strval($speaker), intval($gamets), $responseText, $responseActions);
+    stobeTravelValidateOrders($targetNpc, $npcData, strval($speaker), intval($gamets), $responseText, $responseActions, strval($message));
```
- None of Shay's lines in this conversation ("What's up, Tango?", "I was just using your name, sorry, did I get it wrong?", "You're not Emperor Tango.", "I said tengu.") match the regex. The action is therefore dropped and the model's real sentence is spoken.
- Real orders such as "follow me", "guard me" or "walk with me" still get the same refusals as before.
- Apply the same change to both live and ss-merge, and run `php -l` on the changed files.

## How to confirm the fix worked

- **Issue 1.** Run `select count(*) from bio_unique where name='Tengu'` and expect 0. Check that row 85663 has a non-Emperor occupation after the next snapshot sync. Then talk to her again. The next `Tengu` block in `log/context_sent_to_llm.log` should show an occupation that is not "Emperor of the United Cities", and she should say she is just Tengu. A control: any NPC literally named "Emperor Tengu" must still get the Emperor bio.
- **Issue 2.**
  - Repeat the same sequence with an outsider NPC at affinity below 56: "What's up, Tango?" then "You're not Emperor Tango."
  - Expect `Unrequested order dropped` (if the model emits MoveToTarget) and no `Order rejected before speech` line in `log/stobeserver.log`.
  - Expect no `infoaction … REJECTED` row, and the `output_to_plugin.log` message should be the model's own text.
  - Control: say "follow me" or "guard me" to the same NPC. You should still get a refusal, and the "Order rejected before speech" line should appear.
- A regression test could be added next to `tests/bio_unique_regression.php` using its rollback-transaction pattern. It would cover two things: an NPC named "Tengu" gets no Emperor traits, and an unrequested MOVE_TO_TARGET keeps its text.

## What is not settled

- Why the model chose `MoveToTarget`. Likely factors: she was "Current Action: moving", her earlier line was "Walk with me or step aside", the action is listed as available, and the model ran at temperature 0.6. The proposed fix does not stop the model emitting such actions. It only stops the server from turning them into a fake refusal.
- Whether the five-column reset actually refills. I read the upsert at `data_functions.php` 9177-9179, but I did not run it. The NPC-editor edit is the fallback.
- The older path at `lib/chat_helper_functions.php` 16133-16138 does the same overwrite (`$message = $orderRefusal`). It was not used in this event, but it needs the same guard, using `$GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE']`.
- The relationship drop of -8 for Shay with Tengu was caused by the canned line. It will not undo itself.
- `lib/travel_companionship.php` is untracked in git, and `chat_helper_functions.php` and `processor/chat.php` have uncommitted changes. The line numbers above are from the live working tree, and I did not look at the ss-merge copy.
- Whether other name collisions matter, such as Horse (race mismatch). That is a design decision about adding a race check.
- Timestamps: server logs are UTC, and DB `created_at` values appear to be UTC+2.
