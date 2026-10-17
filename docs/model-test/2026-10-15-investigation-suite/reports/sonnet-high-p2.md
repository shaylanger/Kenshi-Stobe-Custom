**Summary**

Both symptoms come from the server, and both have a specific cause.

1. The database has a row set named plain "Tengu" that describes the Emperor of the United Cities. Your anti-slaver Tengu is looked up by name and receives that bio, so the LLM plays the Emperor.
2. "I haven't agreed to that job" was not a reply to anything you asked for. Tengu's model reply included a movement action, `MOVE_TO_TARGET@Shay`, which was not a player order. The server treated it as an order from you, rejected it, and overwrote her spoken line with a generic refusal.

**Root cause**

1. The seed file `data/schema.sql` inserts `('Tengu', 'personality'|'backstory'|'speechstyle'|'occupation'|'goals', ...)` into `bio_unique`. These rows describe the Emperor ("United Cities emperor raised in luxury...", "Emperor of the United Cities."). The proper unique NPC is already seeded as "Emperor Tengu". Bio lookup is an exact lowercase match on the NPC's name, so any NPC called "Tengu" gets the Emperor's persona.
2. `stobePlayerOrderGate()` treats every `MOVE_TO_TARGET` (and `FOLLOW`, `HOLD_POSITION`, `BODYGUARD` and so on) from a non-faction NPC as a player-issued order, whoever started it. When trust is below the threshold, its fall-through return is the generic "I haven't agreed to that job." (`stobeTravelValidateOrders` then writes that line over her real reply.) The prompt also offers `MoveToTarget` to NPCs who can never use it at -5 trust.

**Evidence**

*Issue 1*
- `data/schema.sql:3404-3408` seeds the five `Tengu` rows. They sit in a block with Beep, Esata the Stone Golem, Cat-Lon and others, ending in `ON CONFLICT (name, type) DO NOTHING`.
- Database `bio_unique` has 5 rows for `Tengu` (created 2026-09-25 05:19:30) and 6 rows for `Emperor Tengu` (05:19:31). `bio_unique_custom` has 0 Tengu rows.
- `lib/data_functions.php:5409-5412` (`getBioUniqueLookupKeys`) builds the lookup keys from the NPC name only. Lines 5421-5445 (`loadBioUniqueTraitSelections`) query `WHERE LOWER(name) = $1` or `IN ($1,$2)`.
- `log/context_sent_to_llm.log` at about 01:49:50, `req_6ad0313d4e3da` (line 1916786 onward), npc_name `Tengu`. The system prompt reads "Tengu is a Shek aligned with Anti-Slavers", then "United Cities emperor raised in luxury...", "Entitled, theatrical...", "Occupation: Emperor of the United Cities". The appearance line ("Female Shek... small horns") comes from live game data, not from the bio, because the `Tengu` seed has no appearance row.
- The Emperor persona then carries into her replies: `"Tango"? You address an emperor, peasant.` and `Emperor Tengu, if you want to keep that tongue.`

*Issue 2*
- `stobeserver.log` 01:52:38: you said "You are not Emperor Tango." (`req_6ad031e617a02`). Your relationship was Neutral (wary), -5 (`context_sent_to_llm.log` line 1921140).
- That prompt lists `AVAILABLE ACTION: MoveToTarget` (line 1920983) and `MoveToTarget` in the schema (line 1921472).
- 01:52:47: `LLM stream response generated ... "actions":["MOVE_TO_TARGET@Shay"]`, `response_length` 115.
- 01:52:47: `Tengu: REJECTED MOVE_TO_TARGET@Shay; not dispatched. I haven't agreed to that job.`
- 01:52:47: `Order rejected before speech {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}`
- TTS then spoke that line, and the same text was stored as her chat line at 01:52:48.
- `lib/chat_helper_functions.php:15898-15925` (`stobePlayerOrderGate`):
  - Faction members pass.
  - `MOVE_TO_TARGET` is in `stobeNonFactionMinorOrderCommands()` (line ~15882).
  - Trust must reach `stobeNonFactionOrderTrustMin()`. It defaults to `GIFT_TRUST_THRESHOLD`, 56.
  - Only `FOLLOW`, `MOVE_TO` and `TRAVEL_LOCATION` get a specific message. Everything else, including `MOVE_TO_TARGET`, falls through to line 15925: `return "I haven't agreed to that job.";`
- `lib/travel_companionship.php:557-562` (`stobeTravelValidateOrders`): `$text=$why;`. It replaces the reply unconditionally, and never checks whether you asked for anything. It runs from `processor/chat.php:1970`.
- Her earlier line "I am walking. Walk with me or step aside" is where the model got the idea to emit a move action.

**What I ruled out**
- Faction or game-data mix-up: the game data correctly says Female Shek, Anti-Slavers. Only the bio text is wrong.
- A custom or user-edited bio (`bio_unique_custom` has 0 Tengu rows).
- A started job or deal: the log shows `MOVE_TO_TARGET` rejected and not dispatched, and no work or task goal was created. The word "job" is only the fall-through string.
- A travel agreement: `stobeTravelOrderGate` returned null (no ACCEPTED state), so the generic message was used.
- A fuzzy name match: the lookup is an exact lowercase match, so the plain "Tengu" row is hit directly.

**Proposed fix**

*Fix 1: remove the bogus seed*
- In `data/schema.sql`, delete the five `('Tengu', ...)` lines at 3404-3408, and the blank line before them.
- Add a one-time DB patch in `debug/db_updates.php`, next to the existing cleanup at line 1265 and following its pattern. Use a new id after the latest (`202610020001`), for example `202610150001`:
```php
$applyPatch('bio_unique_tengu_dedupe', 202610150001, static function () use ($db): void {
    $db->exec("DELETE FROM bio_unique WHERE name = 'Tengu'");   // exact, case-sensitive: keeps 'Emperor Tengu'
});
```
- Check the other hand-seeded names (Beep, Bugmaster, Cat-Lon, Esata the Stone Golem, Moll, The Phoenix, Tinfist) the same way. "Cat-Lon" duplicates "Mad Cat-Lon" in the database. Plain names that other NPCs can share are the same risk.
- Leave `Emperor Tengu` alone. It is the real unique NPC.
- Without the patch the existing database keeps the rows, because the seed only does `ON CONFLICT DO NOTHING`.

*Fix 2: keep her speech and use an accurate refusal*
- In `lib/travel_companionship.php`, `stobeTravelValidateOrders`, keep the LLM's text when the move was her own idea. Use the player's line from `$GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE']` (set in `processor/chat.php:349`) to tell the two apart. Replace the text only if the player's line asks for movement or work:
```php
$msg = strtolower(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''));
$playerAsked = preg_match('/\b(follow|come|go|move|walk|stay|hold|guard|protect|patrol|take me|lead)\b/', $msg) === 1;
storeEvent('infoaction', ...);                 // keep logging the rejection
if ($playerAsked) { $text = $why; }            // was: $text = $why; unconditionally
```
  Do the same in the `chat_helper_functions.php:16133-16139` path (`$message = $orderRefusal;`).
- In `stobePlayerOrderGate` (line ~15925), replace the generic "haven't agreed to that job" with a movement-appropriate line for `MOVE_TO_TARGET`, `HOLD_POSITION`, `BODYGUARD` and `GUARD_TARGET`. For example: `"I'm not going to follow your lead."` or `"I don't take orders from you."`
- Optionally, stop offering `MoveToTarget`, `HoldPosition` and `Bodyguard` to non-faction NPCs below the trust minimum, wherever the available-action list is built (`stobeBuildActionConfigForNpc`). The model then cannot choose them, and the refusal line is never needed.

**How to confirm the fix worked**
- Before the fix: `SELECT name,type FROM bio_unique WHERE name='Tengu';` returns 5 rows. After the patch it returns 0, and `Emperor Tengu` still has 6.
- In the game, talk to the anti-slaver Tengu. The next `llm_stream_request` for `npc_name 'Tengu'` in `context_sent_to_llm.log` should show no "Emperor of the United Cities" text and no "United Cities emperor raised in luxury".
- Say "You are not Emperor Tengu" and make sure she does not answer "I haven't agreed to that job." If the model emits `MOVE_TO_TARGET` again, the log should still say `Order rejected` but her spoken line should stay intact.
- Regression check: say "follow me" to a stranger. The refusal line should still replace her reply.
- The existing `tests/bio_unique_regression.php` (rollback-wrapped) is the place to add the Tengu case.

**What is not settled**
- Which line the model originally intended. The log shows only `response_length` 115, not the text the server replaced.
- Whether the five `Tengu` rows were intentional (possibly meant for an NPC literally named "Tengu"). I found no code that depends on them.
- Whether the in-game Emperor is named "Emperor Tengu" or just "Tengu". The wiki says "Emperor Tengu", and the Emperor Tengu rows exist, so deleting the plain rows is correct only if that is how the game names him. Check the name in game or in a real Heft chat log.
- The exact player-request regex above is a first draft. A broader intent check would be better if you want fewer misses.
