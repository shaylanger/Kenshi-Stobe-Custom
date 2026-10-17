## Summary
These are two separate server bugs. Neither was the model hallucinating on its own.
1. **"Emperor Tengu":** the server gave this ordinary Anti-Slaver Shek woman the Emperor's biography. A legacy seed row in `bio_unique` is keyed on the bare name `Tengu`, and the lookup matches on name alone, with no check of race, gender or faction. That biography was then saved to her NPC row, so every turn used it.
2. **"I haven't agreed to that job":** that line is a canned server string, not her reply. On that turn the model had her answer *"'Tango' again... I am walking, peasant, and you are in my way. Step aside."* and attached its own action `MoveToTarget@Shay` (stepping toward you). The player-order gate counts any `MOVE_TO_TARGET` from a non-squad NPC with affinity below 56 as a job you gave her. It rejected the action and **replaced her whole spoken line** with the refusal text.

## Root cause
1. `selectBioTraitsForNpc()` (`lib/data_functions.php:5677-5704`) lets unique-biography traits from `loadBioUniqueTraitSelections($name)` (`:5413`) win outright. That function only checks `LOWER(name) = $1` against `combined_bio_unique` (`:5431-5439`). The legacy seed `data/schema.sql:3404-3408` inserts bare `Tengu` rows (bio_unique ids 11-15) describing the Emperor. The proper record is the separate `Emperor Tengu` entry (ids 113-118, from `data/import/kenshi_unique_bio_unique_upsert.sql:225-230`). So any NPC whose name is exactly "Tengu" becomes the Emperor.
2. `stobeTravelValidateOrders()` (`lib/travel_companionship.php:538-564`) runs every emitted action through `stobePlayerOrderGate()` (`lib/chat_helper_functions.php:15898-15926`). `MOVE_TO_TARGET` is in `stobeNonFactionMinorOrderCommands()` (`:15885-15887`). With trust 0 < 56 and no travel decision, the gate returns `"I haven't agreed to that job."` (`:15925`). The caller then does `$text=$why;` (`travel_companionship.php:561`), which overwrites the NPC's own line. Nothing checks whether you actually asked for the action.

## Evidence
- **eventlog conversation** (rowids 1032154-1032198, localts 1792028989-1792029178 = 2026-10-15 01:49-01:52 UTC):
  - 1032160, before you mentioned any emperor: `Tengu: "Tango"? You address an emperor, peasant...`
  - 1032194: `Tengu: I haven't agreed to that job.`
  - 1032195: `Shay: I didn't give you a job.`
- **Prompt for her first reply** (`log/chat_llm_full_capture.log` line 147, req_6ad0313d4e3da, 01:50:00) contains:
  - `Tengu is a Shek aligned with Anti-Slavers` (live faction)
  - `## Basic Summary United Cities emperor raised in luxury...`
  - `## Occupation Emperor of the United Cities.`
  - The prompt also says `current_native_faction: Anti-Slavers` and tells the model the faction overrides the profile. The model kept the emperor occupation and backstory anyway.
- **Database:**
  - `bio_unique` ids 11-15, name `Tengu`: personality/backstory/speechstyle/occupation/goals = the Emperor. There is no appearance row.
  - `core_npc_master` id 85663: `Tengu | Shek | female | Anti-Slavers [58229-Dialogue.mod] | lock_profile=f | backstory "United Cities emperor raised in luxury..." | occupation "Emperor of the United Cities."`, so the bad biography is saved on her row.
  - `stobe_npc_learned_fact` id 325 (Shay learned about hand_130004880): `is named Tengu and claims title Emperor Tengu`. Polluted memory.
- **Game data:** the Kenshi `Dialogue.mod` string table has both "Tengu" and "Emperor Tengu". The name alone cannot tell the two characters apart.
- **The rejected turn** (`log/stobeserver.log`, req_6ad031e617a02, 01:52:38-01:52:48):
  - Line 2157685: input `You are not Emperor Tango.`
  - Line 2157754: `LLM stream response generated ... "actions":["MOVE_TO_TARGET@Shay"]`
  - Line 2157757: stored infoaction `Tengu: REJECTED MOVE_TO_TARGET@Shay; not dispatched. I haven't agreed to that job.`
  - Line 2157758: `Order rejected before speech | {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}`
- **Original model reply** (`log/output_from_llm.log` ~327305-327311): `"message": "\"Tango\" again. You are either deaf or you enjoy bleeding. I am walking, peasant, and you are in my way. Step aside.", "action": "MoveToTarget", "target": "Shay"`. The text you heard does not appear anywhere in it.
- **Prompt state:** `Current player affinity: 0/100` and `Minor outsider movement/guard orders ... require affinity 56+`. The threshold is `MINOR_ORDER_TRUST_MIN`, default `GIFT_TRUST_THRESHOLD` 56 (`chat_helper_functions.php:15889-15892`).
- **Side effect:** the relationship eval for the next turn gave `aff_delta -8, type rival`, "Tengu accuses Shay of inventing work". Bug 2 cost you affinity (`output_from_llm.log` ~327437).

## What you ruled out
- **Your "Tango" spelling** did not cause the emperor idea. Her very first reply already claimed to be an emperor, and the biography is in the system prompt.
- **A real job or travel deal:** none existed. There is no travel or contract decision on that turn, and the refusal comes from the generic minor-order fallback at `:15925`, not from a travel branch.
- **The newer `Emperor Tengu` entries:** they are not involved. The lookup keys are only `tengu` and its bracket-stripped form (`getBioUniqueLookupKeys`, `data_functions.php:5397-5410`). The bad match is the bare legacy row.
- **TTS or the plugin:** neither changed the text. The swap happens before TTS (the log says "rejected before speech").

## Proposed fix
**Fix 1: emperor biography**
- **(a) Remove the bad seed (main fix).**
  - In `data/schema.sql`, delete lines 3404-3408 (the five `('Tengu', ...)` rows) so fresh databases don't get them.
  - In `debug/db_updates.php`, add a migration next to the existing `bio_unique` patches (around `:1265-1271`):
    ```php
    $applyPatch('bio_unique', 202610150001, static function () use ($db): void {
        // Legacy bare-name alias of Emperor Tengu: ordinary NPCs named "Tengu" inherited the Emperor bio.
        $db->exec("DELETE FROM bio_unique WHERE name = 'Tengu' AND type IN ('personality','backstory','speechstyle','occupation','goals')");
    });
    ```
  - Use DELETE rather than `is_enabled=false`. `loadServerProtectedUniqueNames()` (`data_functions.php:6100-6124`) still treats disabled names as protected unique names.
- **(b) Repair her saved profile** (one-off, after (a)). Blank the copied fields so `npcNeedsBootstrap()` (`:9330`) rebuilds them from the random race/faction pool on the next chat, and drop the polluted fact:
  ```sql
  UPDATE core_npc_master SET personality='', backstory='', speechstyle='', occupation='', goals=''
   WHERE id = 85663 AND name = 'Tengu' AND occupation = 'Emperor of the United Cities.';
  DELETE FROM stobe_npc_learned_fact WHERE id = 325;
  ```
  Optionally also reset the -8 affinity change that Bug 2 caused.
- **(c) Hardening (recommended), in `selectBioTraitsForNpc()`.** After `$uniqueSelections = loadBioUniqueTraitSelections($name);`, throw the unique set away when the live identity contradicts it. If the unique entry (or its titled form, e.g. `"<Title> $name"`) has an appearance row naming a race or gender the live NPC doesn't have, fall back to the random pool:
  ```php
  $uniqueSelections = loadBioUniqueTraitSelections($name);
  if (stobeUniqueBioContradictsIdentity($name, $uniqueSelections, $race, $gender)) {
      stobeLogInfo('Unique bio skipped: identity mismatch', ['name'=>$name,'race'=>$race,'gender'=>$gender]);
      $uniqueSelections = createEmptyBioTraitSelections();
  }
  ```
  The new helper reads the `appearance` description (here "Scorchlander male...") and returns true when it names a different race token or gender than the live `$race`/`$gender` (here Shek/female). This catches the same class for other shared names.

**Fix 2: canned refusal replacing her line**

In `lib/travel_companionship.php`, `stobeTravelValidateOrders()`:
- Always drop a gated action.
- Replace the spoken text only when the player's message actually asked for an order.
- For the NPC's own movement (`MOVE_TO_TARGET` toward the person she's talking to, or anything you didn't ask for), keep her model-written line and log the drop.

Pass the player's message in from `processor/chat.php:1970`:
```diff
-    stobeTravelValidateOrders($targetNpc, $npcData, strval($speaker), intval($gamets), $responseText, $responseActions);
+    stobeTravelValidateOrders($targetNpc, $npcData, strval($speaker), intval($gamets), $responseText, $responseActions, strval($message));
```
```diff
-function stobeTravelValidateOrders(string $actor, array|false $npc, string $speaker, int $gamets, string &$text, array &$actions): void {
+function stobeTravelValidateOrders(string $actor, array|false $npc, string $speaker, int $gamets, string &$text, array &$actions, string $playerMessage = ''): void {
+    // Only an order the player actually gave earns a spoken refusal; the NPC's own movement is just dropped.
+    $playerAsked = preg_match('/\b(follow|come( with| here)?|go to|travel|escort|guard|protect|wait|stay|hold|move|walk|lead|take me|bodyguard)\b/i', $playerMessage) === 1;
     $kept=[];
     ...
         $why=stobePlayerOrderGate($actor,$npc,strval($action));
         if ($why === '') { $kept[]=$action; continue; }
-        // A rejection must never enter memory as an executed action.
-        storeEvent('infoaction',time(),$gamets,$actor.': REJECTED '.$action.'; not dispatched. '.$why.' (talking to: '.$speaker.')');
-        $text=$why;
-        stobeLogInfo('Order rejected before speech',['actor'=>$actor,'action'=>$action,'reason'=>$why]);
+        $cmd = strtoupper(explode('@',$action,2)[0]);
+        $selfMove = $cmd === 'MOVE_TO_TARGET' && strcasecmp(trim(explode('@',$action,2)[1] ?? ''), $speaker) === 0;
+        if (!$playerAsked || $selfMove) {
+            // NPC-initiated movement: drop it, keep the NPC's own words, record nothing as a refused job.
+            stobeLogInfo('Unrequested order dropped, speech kept',['actor'=>$actor,'action'=>$action,'reason'=>$why]);
+            continue;
+        }
+        // A rejection must never enter memory as an executed action.
+        storeEvent('infoaction',time(),$gamets,$actor.': REJECTED '.$action.'; not dispatched. '.$why.' (talking to: '.$speaker.')');
+        $text=$why;
+        stobeLogInfo('Order rejected before speech',['actor'=>$actor,'action'=>$action,'reason'=>$why]);
     }
```
An alternative with no keyword heuristic: if you'd rather not guess intent from words, just never overwrite `$text` for `MOVE_TO_TARGET@<speaker>` and `HOLD_POSITION`. Those are the NPC's own positioning, not work. Keep the overwrite for FOLLOW, BODYGUARD, GUARD_TARGET and travel, which are only ever asked for.

Apply each change to both trees (live `/var/www/html/StobeServer` and `/root/stobe-work/ss-merge`), then `php -l`.

## How to confirm the fix worked
- **Bio:**
  - Add a case to `tests/bio_unique_regression.php` that inserts a bare `Tengu` unique row (and, for (c), an `Emperor Tengu` appearance "Scorchlander male"). Call `selectBioTraitsForNpc('Tengu','Shek','female','Anti-Slavers')`. Assert `sources['occupation'] !== 'unique'` and that the occupation does not contain "Emperor".
  - It fails on the current code and passes after.
  - Live check: `SELECT occupation FROM core_npc_master WHERE id=85663` is no longer the emperor text after one chat, and the next system prompt in `chat_llm_full_capture.log` has no "Emperor".
- **Refusal:**
  - Add a regression check that calls `stobeTravelValidateOrders('Tengu', <npc with affinity 0, not faction>, 'Shay', 1, $text='"Tango" again... Step aside.', $actions=['MOVE_TO_TARGET@Shay'], 'You are not Emperor Tango.')`.
  - Assert that `$actions` is empty and `$text` is unchanged. Today the text becomes "I haven't agreed to that job.".
  - Second case: message `follow me`, action `FOLLOW@Shay` must still give a refusal line.
  - In game: talking to Tengu should log `Unrequested order dropped, speech kept` instead of `Order rejected before speech`, and no `REJECTED` infoaction should appear for unrequested moves.

## What is not settled
- **Other shared names:** I haven't checked other bare-name unique rows that also have titled versions (Cat-Lon, Crab, Goat, Gorillo, King, Megaraptor). Some of those may be correct animal entries. `Horse` (core_npc_master 85975, a Midland Hive drone with a treasure-hunter bio) may be the same class of mismatch. Only Tengu is confirmed.
- **Keyword list:** the order-keyword list in Fix 2 is a heuristic. A command phrased indirectly could slip past it; the result would be a silently dropped action, not a wrong line.
- **Uncommitted edits:** the live tree has uncommitted changes in `lib/chat_helper_functions.php` and others (`git status`). Line numbers above are from the current working files, so re-check the anchors before patching.
- **Original model line:** the model's own line was itself just an emperor-flavoured insult (caused by Bug 1). Once Bug 1 is fixed, she should also stop making imperious "step aside" movement choices.
