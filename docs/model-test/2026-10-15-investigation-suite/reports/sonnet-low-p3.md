## Summary
Mouse says "I need to find a practical place before promising to lead us there." because the server rejects her travel offer before she speaks. The model proposed "Spring", which is the town you are standing in, and the resolver refuses a destination equal to the current town. She also has no usable destination list. The model never sees the visited towns as candidates, and native `travel_destinations` candidates are scarce and expire after 300 s. With nothing else to offer, she repeats the fallback line every turn.

## Root cause
`stobeTravelCapture()` calls `stobeTravelResolvePlan()`. It returns false for "Spring" and for any name that is not an exact label match. `stobeTravelCapture()` then sets the fixed refusal text and discards the model's reply. The model's only grounded options were the current town and a few expiring native points.

## Evidence
- `/var/www/html/StobeServer/lib/travel_companionship.php:454` is the only place the string "practical place" exists. It fires when `stobeTravelResolvePlan()` returns false.
- `travel_companionship.php:134-152` (`stobeTravelResolvePlan`) shows how the destination is resolved:
  - Native candidates from `stobeTravelLocalCandidates()` (lines 8-50) must match `observed`, `reachability=path_confirmed`, the actor serial, and be observed within the last 300 s.
  - Otherwise it falls back to `stobeResolveTravelLocationFromVisitedZones($requested)`. That result is rejected unless the label matches the request exactly, and it is also rejected when `strcasecmp($GLOBALS['CACHE_CITY'], $place['label']) === 0`, meaning the request is the NPC's current town.
- `stobeserver.log` 2026-10-15 02:00:33-02:00:38, request `req_6ad033c171a7a` (your line "Okay, can you please find a practical place to lead me?"):
  - Line 2159585: "Travel agreement rejected before speech" with that fallback reason.
  - Line 2159589: the NPC's location is Spring, Spring, Stobe's Gamble.
  - The same rejection repeats at 02:00:48 (`req_6ad033cb930e7`, line 2159697).
- `chat_llm_full_capture.log`, line 159 (`req_6ad033c171a7a`): the model replied `travel_decision":"PROPOSE", "travel_kind":"same_route", "travel_leader":"npc", "travel_destination":"Spring", "travel_reason":"Spring is the only place I have a read on..."`. So the model really did think Spring was the only place it knew.
- Database (SELECT only): `location_zones` has 7 rows, all with `knowledge_only` false: Stumble Inn, Spring, The Hub, Ogdam, Clownsteady, Hummock, Bantam Knoll. Six of them are valid, non-current towns, and `stobeResolveTravelLocationFromVisitedZones` (`lib/chat_helper_functions.php:2117`) could resolve each by exact name. The model just was not given the list.
- The prompt in the capture contains only generic text such as "Use the candidate ID as travel_destination" and "Generic compass ground samples are fallback short walks". I could not find a list of visited towns in it.
- Earlier receipt `testing/live-stobe-queue/KAH-CHAT-005-5090-20261014.receipt.md` line 9 records the same line for Beak. There the model proposed "Squin gate" and was rejected the same way.

## What I ruled out
- The LLM call, network and server health: HTTP 200 with `status=ok`.
- A missing `travel_leader` or `travel_kind`: both were valid. The failure is at the destination step.
- An empty `location_zones` table: it has 6 usable other towns.
- Exact commit or version differences. I only read the live tree and did not check git.

## Proposed fix
All edits are in `lib/travel_companionship.php`. The aim is to give the model a real list of places it may pick, and to make the resolver accept them.

1. Add a function `stobeTravelVisitedCandidates(string $currentCity): array`.
   - It runs `SELECT zone_name, city_name, x, y, z FROM location_zones WHERE metadata->>'knowledge_only' IS DISTINCT FROM 'true' ORDER BY last_seen_ts DESC LIMIT 12`.
   - It drops the row equal to the current city (`$GLOBALS['CACHE_CITY']`).
   - It returns entries shaped like `['id'=>'visited:'.slug($zone_name), 'label'=>$zone_name, 'x'=>..., 'y'=>..., 'z'=>..., 'source'=>'visited_location']`.
2. In `stobeTravelResolvePlan`, after the native-candidate loop, accept `$requested` when it equals a visited candidate id or label (case-insensitive). Return that candidate, which already carries `source=visited_location`. Keep the current-city rejection only for a request that equals the current town.
3. Where the travel prompt block is built (search for "Use the candidate ID as travel_destination"), append these visited candidates to the choices list the model sees, with labels. For example: "Known visited towns you may offer to lead to: Stumble Inn, The Hub, Ogdam, Clownsteady, Hummock, Bantam Knoll." Also tell it not to propose the town it is already in.
4. Soften the dead end at line 454. If the resolver fails and visited candidates exist, replace the fixed refusal text with "I can lead you to X, Y or Z, which would you like?" using real names from the candidate list. This breaks the loop.
5. Check that `stobeTravelPlanHash` (travel_companionship.php:~55-60) still accepts `source=visited_location`. It does today. Native dispatch must also still handle a visited point. `stobeTravelPlanPointForDispatch` does not require a native id for that source, so it should work.

## How to confirm the fix worked
- Offline: write a small PHP check that calls `stobeTravelResolvePlan('Mouse', $npc, 'Ogdam', null)` with the current city set to Spring. Before the fix it returns false. After the fix it returns a point with `source=visited_location`. Also confirm that 'Spring' is still rejected.
- Live: ask Mouse to lead you to Ogdam, then check `stobeserver.log` for no "Travel agreement rejected before speech". Check that `chat_llm_full_capture.log` shows a `travel_destination` other than the current town, and that she walks there.

## What is not settled
- I did not confirm whether the prompt ever lists visited zones. I only searched the captured prompt for a few town names and found none, so it may be listed under another name.
- I did not check whether Mouse had any native `travel_destinations` in `core_npc_master.metadata`. My queries used guessed column names and failed.
- `location_zones` is not scoped per NPC. All 7 rows are global, so an NPC may be offered towns she has never been to.
- I did not verify that native movement can path to a visited-zone point from the current spot.
- One caveat on my own run: I wrote a temp file under `/tmp` in WSL while inspecting the log. A cleanup of it was blocked, so a stray `/tmp/c.txt` may remain.
