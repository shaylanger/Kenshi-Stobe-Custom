## Summary
Mouse never knew any locations because the server received an empty list of travel destinations for her. Every request in the loop (01:59:28, 01:59:43, 02:00:24, 02:00:38 and 02:00:48 on 2026-10-15) had `Observed local choices: []`, `Grounded named-place choices: []` and `Ranked reachable source choices: []`. The model then either proposed no destination, or proposed "Spring", which is the town she was standing in. `stobeTravelCapture` found no resolvable point and replaced her reply with the hard-coded line "I need to find a practical place before promising to lead us there." That reply is a server-side rejection, not something the model chose to say. It repeats because each retry hits the same empty list.

There are two gaps:
1. No candidate list reaches the prompt. The only destination source is the native `travel_destinations` metadata, and no NPC in the database has it. I could not establish why (see "What is not settled").
2. The server has no fallback. The `location_zones` table holds 7 visited towns, but the resolver rejects the NPC's current town and the model is never shown the others.

This is a design gap rather than a one-line bug.

## Root cause
The server only lets an NPC propose a destination from native path-confirmed candidates (`metadata.travel_destinations`). It also accepts a visited-town name from `location_zones`, but the model is never told those names exist. The name it did guess, "Spring", is explicitly rejected by the resolver because it is the current town. With no candidates, `stobeTravelResolvePlan` returns false and the canned refusal is sent.

## Evidence
- `/var/www/html/StobeServer/log/stobeserver.log` line 2159049 (2026-10-15 01:59:28): `Travel agreement rejected before speech {"npc":"Mouse","speaker":"Shay","reason":"I need to find a practical place before promising to lead us there.","request_id":"req_6ad0337b904b8"}`. The same line repeats at 01:59:43, 02:00:24, 02:00:38 and 02:00:48 (lines 2159164, 2159477, 2159585, 2159697).
- The string comes from `lib/travel_companionship.php:454`, inside `stobeTravelCapture`. The path is: `$point = stobeTravelResolvePlan(...)`, then `if (!$point) $reason = "I need to find a practical place..."`, then `$text = $reason` and the actions are stripped.
- `lib/travel_companionship.php:134-152`, `stobeTravelResolvePlan`, only accepts a destination in three ways:
  - Reuse of a stored offer.
  - A match against `stobeTravelLocalCandidates()`.
  - `stobeResolveTravelLocationFromVisitedZones($requested)`, which is rejected when `strcasecmp(trim($GLOBALS['CACHE_CITY']), $place['label']) === 0`, i.e. the destination is the town she is in.
- Prompt sent for request `req_6ad0337b904b8` (`log/context_sent_to_llm.log` around line 1925828): `Observed local choices ...: []`, `Grounded named-place choices ...: []`, `Ranked reachable source choices: []`, and `Recorded agreement ...: null`.
- Model output for the same request (`log/output_from_llm.log`, near line 327690) has `"travel_decision": "PROPOSE", "travel_destination": "Spring"`, with the reason "heading back to Spring anyway".
  - Mouse was in Spring at the time (`GEO_DEBUG_RESOLVE_RESULT` city Spring), so "Spring" is rejected as the current town.
  - The next response (01:59:43) has `travel_destination: ""` and the reason "No confirmed local destination", and it is rejected the same way.
- Database (SELECT only):
  - `core_npc_master.metadata ? 'travel_destinations'` is false for all 136 NPCs; Mouse's value is null.
  - `location_zones` has 7 rows: Stumble Inn, Spring, The Hub, Ogdam, Clownsteady, Hummock, Bantam Knoll. None is flagged `knowledge_only`, so the visited-zone lookup could resolve any of them except the current town.
  - `lib/travel_companionship.php:8-26`, `stobeTravelLocalCandidates`, reads only `metadata['travel_destinations']`, and only rows with `observed === true`, `reachability === 'path_confirmed'` and `observed_unix` within the last 300 s.
- The native producer exists in source: `components/STOBE/src/Context.cpp:3620` writes `"travel_destinations": LocalTravel::CandidatesJson(world, npc)`, and `components/STOBE/src/LocalTravel.cpp:223` builds the list. It only returns candidates inside `kLocalRange` (1800 units), outside 40 units of her position, and path-checked. Its candidate kinds are buildings, gates, guards, creatures, resources and town boundary. Towns far away are never candidates.
- `LocalTravel.cpp` and `Context.cpp` differ from the commit that introduced them (commit d541519, 2026-10-14). I could not tell whether the DLL installed in the game contains this code.

## What I ruled out
- The LLM refusing on its own: the refusal text is the server's own hard-coded string, and the server discards the model's reply when this happens.
- Affinity or policy: Mouse's affinity toward Shay is 0, and `same_route` needs ≥0. The log shows the "practical place" reason, not "I don't trust you" or "not changing my plans".
- A stale stored agreement: `Recorded agreement` is null, so the `ACCEPT` and "changed plans" branches did not run.
- An empty `location_zones` table: it has 7 rows, so the data is there. It just isn't surfaced or usable for the NPC's current town.
- The server dropping candidates it was sent: no NPC has the metadata in the database, and `grep -c travel_destinations` in `log/audit_request.log` gives 0. It never arrived, or arrived without being stored.
- A request-side failure such as a cache or format error: the other travel rejections ("Let's agree on the changed travel plans first", "We already have a journey agreed") are different branches and not the cause here.

## Proposed fix
Do these two steps in order, since step 1 is small and step 2 is larger.

**Step 1: give the server a fallback, so NPCs can always pick a known town from `location_zones` (server only, no game rebuild).**

File: `/var/www/html/StobeServer/lib/travel_companionship.php`.

1a. Add a helper that lists visited towns other than the current one:

```php
function stobeTravelVisitedTownChoices(): array {
    $db = $GLOBALS['db'] ?? null;
    if (!$db) return [];
    $cur = trim(strval($GLOBALS['CACHE_CITY'] ?? ''));
    try {
        $rows = $db->fetchAll(
            "SELECT zone_name, city_name FROM location_zones
             WHERE metadata->>'knowledge_only' IS DISTINCT FROM 'true'
             ORDER BY last_seen_ts DESC LIMIT 20");
    } catch (Throwable $e) { return []; }
    $out = [];
    foreach (is_array($rows) ? $rows : [] as $r) {
        $n = trim(strval($r['city_name'] ?: $r['zone_name']));
        if ($n === '' || strcasecmp($n, $cur) === 0 || in_array($n, $out, true)) continue;
        $out[] = $n;
    }
    return $out;
}
```

1b. In `stobeTravelPrompt()`, after the `Observed local choices` line (about line 355), add a line such as:
`'Known visited towns (usable as travel_destination by exact name, no ID needed): ' . json_encode(stobeTravelVisitedTownChoices())`.

1c. Reword the sentence that tells the model to use candidate IDs only, so it also says an exact visited-town name from that list is acceptable. The existing text already mentions "an exact known visited location", so the model has the permission once the list exists.

1d. No change is needed in `stobeTravelResolvePlan`, because it already falls through to `stobeResolveTravelLocationFromVisitedZones($requested)` and returns the town. Leave the check that blocks the NPC's current town alone: it is correct, since you cannot lead someone to where they already are.

1e. `stobeTravelCapture`'s `PROPOSE` and `ACCEPT` handling then works unchanged for visited towns (`source: visited_location`). Check that the dispatch step (`stobeTravelPlanPointForDispatch`) turns it into `TravelLocation@<town>`. I read it and it accepts both sources, but I did not run it.

Caveat: the model prompt currently says "same_route means your actual intended route, not a destination the player assigned." When the player asks to be led, it may need `detour` (affinity ≥ 20). Mouse's affinity is 0, so she would be refused with "I'm not changing my plans for you". If you want her to lead you at affinity 0, decide whether `stobeTravelMinimum('detour')` (line ~203, currently 20) should be lowered, or whether the prompt should tell the model to use `same_route` when the NPC genuinely wants to go there anyway.

**Step 2: fix the native side so towns and landmarks appear as candidates (game DLL rebuild).**

File: `components/STOBE/src/LocalTravel.cpp`, function `CandidatesJson`.

- The 1800-unit range (`kLocalRange`) means towns a few thousand units away never become candidates. Spring is 52758.5, 61799.7 and The Hub is -50978.8, 2932.48 (all map coordinates from `location_zones`), so a town-level destination will never come out of this producer.
- Add a second producer that emits `kind: "known_place"` rows from the server's `location_zones` data (or from the game's own town list), with `reachability: path_confirmed` set only after a navmesh path check. That is why those towns need the native side: the server cannot verify reachability.
- Then fix the retention gate (`lib/data_functions.php` ~11102-11180) if needed. When a `inventory_live_sync` arrives without the field, prior metadata is kept only with a matching playthrough receipt. If this drops the data, the prompt would still show `[]` even when the DLL emits it. Check this first with the debug steps below.

## How to confirm the fix worked
1. Before changing anything, confirm the empty list: run `SELECT name, metadata ? 'travel_destinations' FROM core_npc_master WHERE name='Mouse';`. It should be false. After talking to an NPC with the fixed DLL it should be true (Step 2).
2. For Step 1: reload Mouse in Spring, say "lead me to The Hub". Expected:
   - The `context_sent_to_llm.log` entry for that request includes the new `Known visited towns ...` line.
   - `stobeserver.log` shows no `Travel agreement rejected before speech` with the "practical place" text.
   - A `travel_agreement` row appears in `eventlog` with `status PROPOSED`, then `ACCEPTED` after you say yes.
   - Mouse then issues `TravelLocation@The Hub` (check `output_to_plugin.log`).
3. Control: ask her to lead you to "Spring" while she is in Spring. She should still say she needs a practical place (expected).
4. Regression: `stobe-tests` (offline) must pass.

## What is not settled
- Why no NPC has `travel_destinations` metadata. Three possibilities: the installed `Stobe.dll` was built before d541519 and has no producer; the producer ran but returned `[]` (no path-confirmed point within 1800 units, or `world->navmesh` was null); or the data was sent but dropped by the receipt retention in `data_functions.php`. I could not check the installed DLL's build or the game log (`stobe.log`), because the game folder path was not reachable from my shell. Look at `stobe.log` and a raw `infonpc`/`inventory_live_sync` request for a `travel_destinations` key to settle this.
- Whether the rejected replies were `PROPOSE` or `ACCEPT`: the log line does not say; the model output for the first request is `PROPOSE`.
- Whether Mouse should lead to a non-town place such as a hunting ground. The request mentions "a herd", and that needs the native candidates (Step 2), not just towns.
- Whether lowering the `detour` affinity gate is desirable. That is a design call for you.

Files: `/var/www/html/StobeServer/lib/travel_companionship.php` (lines 8, 134, 328-356, 454), `/var/www/html/StobeServer/lib/destination_discovery.php` (line 135), `/var/www/html/StobeServer/lib/chat_helper_functions.php` (line 2117), `C:\KenshiModding\components\STOBE\src\LocalTravel.cpp` (line 223), `C:\KenshiModding\components\STOBE\src\Context.cpp` (line 3620).
