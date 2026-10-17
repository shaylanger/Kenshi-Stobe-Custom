## Summary
These are two separate server bugs, and the logs show both clearly.

1. **Tengu thought she was the Emperor.** Her profile was built from the seeded unique biography for the name "Tengu", which describes Emperor Tengu. That lookup matches on name only. It never checks race, sex or faction. The row was also created before her race was known, so nothing could have caught the mismatch. She is a female Shek with the Anti-Slavers.
2. **"I haven't agreed to that job."** You said "You are not Emperor Tango." The model answered with an in-character line and also chose a `MoveToTarget@Shay` action on its own. The server's order gate for non-squad NPCs treated that move as an order from you. It rejected it, replaced her whole spoken line with the stock refusal "I haven't agreed to that job.", and wrote a REJECTED entry to history. On the next turn she read that back as you "inventing work" for her.

## Root cause
1. `selectBioTraitsForNpc()` takes the `combined_bio_unique` rows whose name matches, even when the NPC's live identity contradicts them. The seed `data/schema.sql` has a bare-name entry `'Tengu'`, and `Tengu` is also a normal random Shek name.
2. `stobeTravelValidateOrders()` runs on every chat turn with an NPC outside your squad. It sends every "minor order" action the model emits through `stobePlayerOrderGate()`, without checking whether you asked for anything. When the gate rejects, it does `$text=$why`, which throws away the NPC's real reply.

## Evidence
**Issue 1 (identity)**
- Database: `core_npc_master` id 85663, name `Tengu`. Race is Shek, gender female, faction `Anti-Slavers [58229-Dialogue.mod]`.
  - occupation = "Emperor of the United Cities."
  - backstory = "United Cities emperor raised in luxury while nobles enforce his rule."
- Database: `core_npc_master_history` for npc_id 85663. The first row, `snapshot_reason=create` at 03:49:19 DB time (01:49:19 UTC), already has the Emperor occupation, with race `Unknown` and an empty faction. So the profile was created from the name alone, and the unique bio was set before any race or faction was known. Later `snapshot_sync` rows kept it.
- `data/schema.sql:3404-3408` seeds `bio_unique ('Tengu', personality|backstory|speechstyle|occupation|goals ...)`. It has no appearance row, which is why the live appearance ("Female Shek ... small horns") was kept and the prompt contradicts itself.
- `combined_bio_unique` holds both a `Tengu` set (from schema.sql) and an `Emperor Tengu` set (from `data/import/kenshi_unique_bio_unique_upsert.sql:225-230`, "Scorchlander male ...").
- `lib/data_functions.php`:
  - `getBioUniqueLookupKeys()` (~5397) builds the lookup keys from the name only.
  - `loadBioUniqueTraitSelections()` (5413) queries `WHERE LOWER(name) = $1`, with no race, gender or faction filter.
  - `selectBioTraitsForNpc()` (5677-5700) receives `$race`, `$gender` and `$faction` but uses them only for the random pool. For each trait type it picks the unique text first if one exists.
  - Callers: `storeNpcProfile` at 9049 and `storeNpcSnapshot` at 11026.
- `log/context_sent_to_llm.log`, prompt for `req_6ad031f48276d`: "Tengu is a Shek aligned with Anti-Slavers ... ## Occupation Emperor of the United Cities." World-knowledge lore lines for "Emperor Tengu" and "Beautiful Tengu: A Tribute" were also pulled in by the name.
- `log/output_to_plugin.log`, 2026-10-15 01:50-01:52 UTC: "You got it wrong. It is Tengu. Emperor Tengu, if you want to keep that tongue."

**Issue 2 ("job")**
- `log/stobeserver.log` 01:52:38: the player line for `req_6ad031e617a02` was `Shay: You are not Emperor Tango. (talking to: Tengu)`.
- `log/output_from_llm.log:327280+`, raw model output for `req_6ad031e617a02`:
  - message = "\"Tango\" again. You are either deaf or you enjoy bleeding. I am walking, peasant, and you are in my way. Step aside."
  - action = "MoveToTarget", target = "Shay".
- `log/stobeserver.log:2157758` 01:52:47: `Order rejected before speech | {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}`
- `log/output_to_plugin.log:10041` 01:52:48: the message actually sent was "I haven't agreed to that job." Her real line was discarded.
- Code path:
  - `processor/chat.php:1448-1449`: `$travelConsentTurn` is true for every NPC outside your squad.
  - `processor/chat.php:1966-1970`: calls `stobeTravelValidateOrders($targetNpc, $npcData, $speaker, $gamets, $responseText, $responseActions)` and does not pass your line.
  - `lib/travel_companionship.php:538-565`: for each action it calls `stobePlayerOrderGate()` (line 557). On a rejection it writes `storeEvent('infoaction', ... 'REJECTED '.$action.'; not dispatched. '.$why ...)`, then `$text=$why;`, then logs (lines 559-562).
  - `lib/chat_helper_functions.php:15885-15887`: `stobeNonFactionMinorOrderCommands()` includes `MOVE_TO_TARGET`.
  - `lib/chat_helper_functions.php:15898-15926`, `stobePlayerOrderGate()`: trust is below `MINOR_ORDER_TRUST_MIN` (default = `GIFT_TRUST_THRESHOLD` 56). `stobeTravelOrderGate()` returns null because no travel deal is accepted. The command is not FOLLOW, MOVE_TO or TRAVEL_LOCATION, so it falls through to `return "I haven't agreed to that job.";` (15925).
- Next turn, `req_6ad031f48276d`: the prompt history shows "Tengu, speaking to Shay: I haven't agreed to that job." She replied "Then we agree on something. Stop inventing work for me ...".
- Database: `core_npc_master.extended_data` relationship note = "Tengu accuses Shay of inventing work and insults her worth." (aff -13). The made-up refusal also cost relationship points.
- The same overwrite exists in the dispatch path at `lib/chat_helper_functions.php:16133-16140` (`$message = $orderRefusal;`). A similar earlier case is in the log: 2026-10-10 09:43:51, "Hungry Bandit" `MOVE_TO@Axima` refused.

## What you ruled out
- **Speech-to-text or the name "Tango".** The player text arrived as typed ("Tango"), and the profile was already the Emperor's before the first line (01:49:49).
- **An auto-rename collision.** "Batch identity rename skipped (not eligible)" for serial 130004880 is normal; Tengu was never renamed.
- **The relationship worker, memory recall, or a real job or travel deal.** Memory recall found 0 rows. `stobeTravelOrderGate` returns null because no travel deal was accepted. No work or task goal was involved. The "job" text is the gate's fallback string only.
- **The LLM inventing the "job" line itself.** Its raw output contained no such line. The server substituted it.

## Proposed fix
Patch both server trees, the live tree and `/root/stobe-work/ss-merge`. The live tree has uncommitted edits in these files, so the line numbers are approximate. Run `php -l` afterwards.

**Fix 2: don't let the gate overwrite an NPC's own line**

`lib/chat_helper_functions.php`: add this next to `stobeNonFactionMinorOrderCommands()`:
```php
/** True when the player's line actually asks the NPC to move/escort/guard/wait. */
function stobePlayerLineAsksForMovement(string $line): bool {
    $line = strtolower(trim(str_replace("\u{2019}", "'", $line)));
    if ($line === '') return false;
    return preg_match("/\b(follow|come\s+(?:here|with|over|along|to)|go\s+(?:to|with)|walk\s+(?:to|with)|move|lead|take\s+me|escort|guard|protect|watch\s+(?:over|my\s+back)|wait|stay|hold\s+(?:here|position)|meet\s+me|travel|bring\s+me)\b/", $line) === 1;
}
```

`lib/travel_companionship.php`, `stobeTravelValidateOrders()`:
```diff
-function stobeTravelValidateOrders(string $actor, array|false $npc, string $speaker, int $gamets, string &$text, array &$actions): void {
+function stobeTravelValidateOrders(string $actor, array|false $npc, string $speaker, int $gamets, string &$text, array &$actions, string $playerLine = ''): void {
+    $playerAsked = stobePlayerLineAsksForMovement($playerLine);
     $kept=[];
 ...
         $why=stobePlayerOrderGate($actor,$npc,strval($action));
         if ($why === '') { $kept[]=$action; continue; }
-        // A rejection must never enter memory as an executed action.
-        storeEvent('infoaction',time(),$gamets,$actor.': REJECTED '.$action.'; not dispatched. '.$why.' (talking to: '.$speaker.')');
-        $text=$why;
-        stobeLogInfo('Order rejected before speech',['actor'=>$actor,'action'=>$action,'reason'=>$why]);
+        if ($playerAsked) {
+            // A rejection must never enter memory as an executed action.
+            storeEvent('infoaction',time(),$gamets,$actor.': REJECTED '.$action.'; not dispatched. '.$why.' (talking to: '.$speaker.')');
+            $text=$why;
+            stobeLogInfo('Order rejected before speech',['actor'=>$actor,'action'=>$action,'reason'=>$why]);
+        } else {
+            // Her own move, not an order from the player: drop it, keep her line, no "job" in history.
+            stobeLogInfo('Unrequested outsider move dropped',['actor'=>$actor,'action'=>$action]);
+        }
     }
```

`processor/chat.php:1970`:
```diff
-    stobeTravelValidateOrders($targetNpc, $npcData, strval($speaker), intval($gamets), $responseText, $responseActions);
+    stobeTravelValidateOrders($targetNpc, $npcData, strval($speaker), intval($gamets), $responseText, $responseActions, strval($message));
```

`lib/chat_helper_functions.php:16136-16140` has the same rule. Only set `$message = $orderRefusal;` when `stobePlayerLineAsksForMovement(<player line>)` is true; otherwise just `continue;` (the action is dropped, her reply is kept). Optionally do the same around 13995-13999 so the history row for an unrequested move has no refusal reason.

Result: the move is still never dispatched, so outsiders still don't obey you, but her real reply is spoken and nothing about a "job" goes into history.

**Fix 1: unique bios must match the live identity**

1. Database, one-time migration (also add it to `data/schema.sql` / the `db_updates` list):
```sql
ALTER TABLE bio_unique        ADD COLUMN IF NOT EXISTS race varchar(64) NOT NULL DEFAULT '', ADD COLUMN IF NOT EXISTS gender varchar(16) NOT NULL DEFAULT '';
ALTER TABLE bio_unique_custom ADD COLUMN IF NOT EXISTS race varchar(64) NOT NULL DEFAULT '', ADD COLUMN IF NOT EXISTS gender varchar(16) NOT NULL DEFAULT '';
-- recreate combined_bio_unique with race, gender appended to both SELECT lists (append at the end so CREATE OR REPLACE VIEW works)
UPDATE bio_unique SET race='Scorchlander', gender='male' WHERE lower(name) IN ('tengu','emperor tengu');
```
   Fill the same columns for other unique NPCs whose names also appear in the random name pools. An empty value means "any", so all other rows keep their current behaviour.

2. `lib/data_functions.php`:
   - Change the signature to `loadBioUniqueTraitSelections(string $name, string $race = '', string $gender = '')`.
   - Select `race, gender` too, and add `$race|$gender` to the cache key.
   - In the row loop, skip a row when its `race`/`gender` is set and either the NPC's value is empty or `Unknown` (defer until the snapshot knows it), or it differs, compared case-insensitively.
   - In `selectBioTraitsForNpc()`, change the call to `loadBioUniqueTraitSelections($name, $race, $gender)`.

3. In the `storeNpcSnapshot()` update path for an existing, unlocked row (`lock_profile=false`): when a stored trait equals a unique-bio text that now fails the identity check, overwrite it with the random selection. Without this, NPCs created by name only, like this Tengu, never get repaired.

4. Repair this NPC now. Either edit her in the NPC UI, or set new values on row 85663 for personality, backstory, occupation, speechstyle and goals, for example from a random Shek/Anti-Slaver bio. Leave `lock_profile` false.

5. Optional: when a unique bio is skipped for a name collision, add one prompt line: "You share the name Tengu with Emperor Tengu of the United Cities; you are not him." This keeps the lore lines from confusing the model.

Quick stop-gap if you only want the data fix: disable the bare `Tengu` rows (`is_enabled=false`). The `Emperor Tengu` set stays. But see "not settled" about the Emperor's in-game name.

## How to confirm the fix worked
- **Fix 2, offline:** add a regression test in `tests/` that calls `stobeTravelValidateOrders('Tengu', <outsider npc, aff -13>, 'Shay', g, $text, $actions, $line)` with `$actions=['MOVE_TO_TARGET@Shay']`.
  - `$line="You are not Emperor Tango."` should leave `$text` unchanged and `$actions` empty.
  - `$line="come here"` should give `$text === "I haven't agreed to that job."`.
  - The first assertion should fail on the current code.
- **Fix 2, in game:** use the injection switch (`NEG_TEST_INJECT`) to inject a reply with `MoveToTarget@Shay` to an outsider after a non-request line. `stobeserver.log` should show `Unrequested outsider move dropped`, and `output_to_plugin.log` should carry the injected line, not the refusal.
- **Fix 1, offline:** extend `tests/bio_unique_regression.php` (rollback transaction).
  - `selectBioTraitsForNpc('Tengu','Shek','female',...)` should report `sources.occupation != 'unique'`.
  - `('Tengu','Scorchlander','male')` should report `'unique'`.
  - `('Tengu','Unknown','')` should not report `'unique'`.
- **Fix 1, in game:** talk to the Anti-Slaver Tengu again (or a fresh copy of the fixture).
  - `SELECT occupation, backstory FROM core_npc_master WHERE name='Tengu'` should no longer say Emperor.
  - The next prompt in `context_sent_to_llm.log` should have no "Emperor of the United Cities" under `## Occupation`.

## What is not settled
- Whether the real Emperor's in-game character name is "Tengu" or "Emperor Tengu". If it is "Emperor Tengu", the bare `Tengu` rows in `schema.sql` are simply wrong and can be deleted. If it is "Tengu", they are needed, and the race/gender identity columns are the only safe fix. The game data was not checked.
- The exact place in `storeNpcSnapshot()` where an existing row keeps its old traits (step 3 of Fix 1) was not read line by line.
- How often the model emits movement actions with no request (only two cases in the current log: this one and Hungry Bandit on 2026-10-10). The regex in `stobePlayerLineAsksForMovement` is a heuristic: a missed request falls back to today's refusal, and a false match changes nothing for real requests.
- The live server tree has uncommitted changes to `chat_helper_functions.php`, `travel_companionship.php` and other files. The line numbers above are from that working copy.
