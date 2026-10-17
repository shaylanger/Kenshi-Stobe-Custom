## Summary
Mouse never knew any place because the game client that is installed does not send the list of destinations the server expects. Her prompt shows "Observed local choices ...: []" on every turn. The server only accepts a travel offer that points at one of those candidates, or at a place name in the `location_zones` table. With neither available, it rejects the offer with the canned line "I need to find a practical place before promising to lead us there." That line is in the code, not something the model wrote. The model keeps asking for travel, gets the same rejection, and so the loop continues.

The client code that produces destinations exists in git (`components/STOBE/src/LocalTravel.cpp`, committed in d541519 on 2026-10-14 13:39 -0600). It is not in the DLL that is running. The Stobe.dll installed on 2026-10-14 19:37 was built from an old source copy in `C:\StobeBuild\src`, which is missing `LocalTravel.cpp`.

## Root cause
The built and installed Stobe.dll has no local-travel candidate producer. The result is:
1. The client sends no `travel_destinations` in Mouse's metadata.
2. The server's `stobeTravelLocalCandidates()` returns [].
3. The fallback lookup `stobeResolveTravelLocationFromVisitedZones()` has only 7 rows to search, and the only one near Mouse is Spring, her own town. Spring is explicitly excluded because it is the current city.
4. `stobeTravelResolvePlan()` returns false, and `stobeTravelCapture()` sets the canned rejection.

This is a secondary effect of the design. The prompt tells the model to choose only from candidates, and it gives no real known places to pick from. So the model keeps proposing travel with no valid destination, and the server keeps rejecting it.

## Evidence
- Server log `stobeserver.log`, 2026-10-15 02:00:33: you said "Okay, can you please find a practical place to lead me?"
- Same log, 02:00:38, `LLM stream response generated`: Mouse's action was `["MOVE_TO_TARGET@Shay"]`.
- Same log, 02:00:38: `Travel agreement rejected before speech | {"npc":"Mouse",... "reason":"I need to find a practical place before promising to lead us there."}`. The same pair repeats at 02:00:48.
- `lib/travel_companionship.php` line 454 is the only place the canned sentence is produced. It fires when `stobeTravelResolvePlan(...)` returns false (about lines 440-455).
- `stobeTravelLocalCandidates()` (lines 8-52) needs `metadata.travel_destinations` rows that are observed within the last 300 s, `reachability == "path_confirmed"`, and carry the actor serial.
- `context_sent_to_llm.log`, Mouse's latest prompt: "Observed local choices (ID selection; path checked when observed, rechecked before movement): []". "Recorded agreement": null.
- Database: `core_npc_master` row "Mouse" has 0 `travel_destinations`.
- Database: `location_zones` has only 7 rows: Spring, The Hub, Bantam Knoll, Stumble Inn, Hummock, Clownsteady, Ogdam. Spring is excluded by the `CACHE_CITY` check in `stobeTravelResolvePlan()`.
- Client source: `Context.cpp:3620` calls `Stobe::LocalTravel::CandidatesJson(world, npc)`. `LocalTravel.cpp` builds candidates (terrain, gates, buildings, guards, town boundary), and `CMakeLists.txt` (line 94) and `Stobe.vcxproj` (line 120) both list it.
- Installed `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll` (19:37:42), `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` and `C:\StobeBuild\out\Stobe.dll` all lack the strings `travel_destinations`, `path_confirmed` and `LOCAL_TRAVEL`.
- `C:\StobeBuild\src` has no `LocalTravel.cpp`. Its `Context.cpp` is dated Oct 1 and contains no `travel_destinations`.
- Game `stobe.log` for the 20:00 local session has no LOCAL_TRAVEL or travel lines.

## What I ruled out
- The model is not inventing the refusal. It is a server string.
- Affinity is not the cause. Her affinity toward you is 0, which the prompt treats as eligible for shared travel.
- A missing travel schema is not the cause. The schema fields are present in the request.
- `npcIsInPlayerFaction` is not the cause. The travel section is in her prompt.
- The `destination_catalog.json` fallback is not a source of places. It only maps creature and resource templates.

## Proposed fix
There are two parts. Part 1 must come first and is the actual fix. Part 2 is optional but is what gives NPCs real named locations.

**Part 1: ship the client that has the candidate producer.**
1. Re-sync the build source. `tools/automation/build-stobe.ps1` should copy `components/STOBE/src` (or `/root/STOBE-src`) into `C:\StobeBuild\src`. Check that the copy includes `LocalTravel.cpp`, `LocalTravel.h`, and the d541519 versions of `Context.cpp`/`Context.h`. Nothing in `C:\StobeBuild\src` was refreshed after Oct 1.
2. Make sure the build file that `C:\StobeBuild\build.bat` uses lists `src/LocalTravel.cpp`, as `CMakeLists.txt:94` and `Stobe.vcxproj:120` do.
3. Build, then run `install-dll.ps1 Stobe` with Kenshi closed.

**Part 2 (optional): give the server a list of known places.**
`stobeTravelResolvePlan()` falls back to `location_zones` through `stobeResolveTravelLocationFromVisitedZones()` (`chat_helper_functions.php:2117`). You can seed `location_zones` with named towns and their x/y/z, with `knowledge_only` not set, so the model can propose "The Hub" and similar. The model currently has no list of them in its prompt (the Observed-choices line is empty). Add them to the prompt in `stobeTravelPrompt()` after the "Observed local choices" line, for example:
```php
$known = $GLOBALS['db']->fetchAll("SELECT zone_name FROM location_zones WHERE metadata->>'knowledge_only' IS DISTINCT FROM 'true' ORDER BY last_seen_ts DESC LIMIT 12");
// append: 'Known visited places (exact names usable as travel_destination): '.json_encode(array_column($known,'zone_name'))
```
Check the fetch method name against the database wrapper before using this. Without the fix to Part 1, this alone only helps if those towns are not the one you are standing in.

## How to confirm the fix worked
1. After installing, grep the DLL for `travel_destinations` and `path_confirmed`. Both must be present.
2. Stand near Mouse in a loaded area, ask her to lead you somewhere, and look at the `context_sent_to_llm.log` line "Observed local choices". It should list candidates with ids like `local:<session>:<serial>:<n>`.
3. The `core_npc_master.metadata` for Mouse should have `travel_destinations` rows.
4. `stobeserver.log` should show a PROPOSE then an ACCEPT, instead of "Travel agreement rejected before speech".
5. `stobe.log` should show movement toward the candidate (TravelLocation/MOVE_TO) with no LOCAL_TRAVEL "candidate query unavailable" line.

## What is not settled
- I did not find which step of `build-stobe.ps1` leaves `C:\StobeBuild\src` stale. It may sync from `/root/STOBE-src` instead of `components/STOBE`, so check which source it reads.
- I did not verify that the model's `travel_decision`/`travel_destination` were empty in this specific response, because the response body was not readable in the logs. The conclusion rests on the candidate list being empty and the rejection reason.
- I did not run the candidate code in game. Whether `Project()` and `PathConfirmed()` return any candidates for Mouse in Spring is untested, and there may be a second problem there once the DLL is rebuilt.
- Pre-existing uncommitted changes in `NativeTravelLifecycle.*` and `PlaythroughSession.cpp` may also affect this. I did not read them, as instructed.
