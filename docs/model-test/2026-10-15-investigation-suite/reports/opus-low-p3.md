## Summary
Mouse never had a destination she could lead you to. The server only accepts a lead/travel offer when the NPC's metadata holds native travel candidates (`travel_destinations`, sent by Stobe.dll) or when the model names a visited town exactly. Mouse had no candidates. The model asked for "West of Spring", which is not a visited town. So every attempt was rejected with the canned line "I need to find a practical place before promising to lead us there." Nothing changes between turns, so the same thing happens every time, which is the loop you saw.

## Root cause
The source the game is built from no longer sends `travel_destinations`. Without it, the server's only other way to find a place is an exact visited-town name, and that path also refuses the town you are currently in (Spring).

## Evidence
- `/var/www/html/StobeServer/lib/travel_companionship.php:454`: `if (!$point) { $reason = "I need to find a practical place before promising to lead us there."; }`. `$point` comes from `stobeTravelResolvePlan` (lines 134-153).
- `travel_companionship.php:8-38` (`stobeTravelLocalCandidates`): it reads only `metadata['travel_destinations']`. Each row must have `observed=true`, `reachability='path_confirmed'`, a matching `actor_serial`, and must be at most 300 s old.
- `travel_companionship.php:147-152` (the fallback): `stobeResolveTravelLocationFromVisitedZones($requested)`. It needs an exact match on the label and returns false when the place is the current city (`CACHE_CITY`).
- stobeserver.log, 2026-10-15 02:00:24: `"target_npc":"Mouse" ... "actions":["TRAVEL_LOCATION@West of Spring"]`, then `Travel agreement rejected before speech | {"npc":"Mouse","speaker":"Shay","reason":"I need to find a practical place..."}`. The same rejection repeats at 02:00:38 and 02:00:48.
- context_sent_to_llm.log, around line 1930110: "Shay: Okay, can you please find a practical place to lead me?" followed by Mouse's refusal. The travel record sent to the model was `{"travel":null,"activity":[]}`, so the prompt contained no candidate IDs.
- Database: `core_npc_master` row for Mouse (id 85855): `metadata ? 'travel_destinations'` = false.
- Database: `eventlog` has 0 rows with `type='destination_sighting'`, so `stobeDestinationRememberSnapshot` never received anything to store.
- The last `travel_destinations` traffic in stobeserver.log is 2026-10-13 04:22:24 (an NPC named Laru). There has been none since.
- The candidate producer exists only in the repo snapshot:
  - `C:\KenshiModding\components\STOBE\src\Context.cpp:3620`: `json += "\"travel_destinations\":" + Stobe::LocalTravel::CandidatesJson(world, npc) + ",";`
  - `components\STOBE\src\LocalTravel.cpp`: up to 32 candidates (line 39), tagged `path_confirmed` (line 186).
- The build source `/root/STOBE-src` is on branch `local/event-priority-debounce`, with HEAD at the upstream merge `dedc49d` (STOBE 1.3.1). It has no `src/LocalTravel.cpp`. `travel_destinations` appears only in the unrelated `AutonomySafetyProbe.cpp` and `mod/Stobe.ini` (`TravelDestinationSet=0`). The DLL built from this tree therefore sends no candidates.
- `location_zones` has 7 visited towns: Stumble Inn, Spring, The Hub, Ogdam, Clownsteady, Hummock, Bantam Knoll. Spring is excluded because you were standing in it, and "West of Spring" matches none of them.

## What you ruled out
- **The model refusing on its own.** It did emit a travel action. The server's guard replaced its line before speech.
- **The policy/consent checks.** `stobeTravelPolicyRefusal` and the kind/leader checks passed. The logged reason is the `!$point` branch, which only runs after those checks.
- **An old agreement blocking her.** The travel record was null.

## Proposed fix
Do both parts. Part A brings the real feature back. Part B lets NPCs pick known towns even with no native candidates, and stops the loop.

**A. Restore the native candidate producer (Stobe.dll).**
1. Get the LocalTravel code back into `/root/STOBE-src`. Copy `components/STOBE/src/LocalTravel.cpp`, `LocalTravel.h`, and the `Context.cpp` hunk around line 3620 from the snapshot. Use `diff -rq components/STOBE/src /root/STOBE-src/src` to see what else is missing.
2. Add `LocalTravel.cpp` to `CMakeLists.txt` and `Stobe.vcxproj`.
3. Build with `tools/automation/build-stobe.ps1`, then install with `install-dll.ps1 Stobe`.

Be careful: `/root/STOBE-src` has uncommitted changes (`git status` shows modified files), so check them before overwriting anything.

**B. Server fallback in `lib/travel_companionship.php`.**
1. In `stobeTravelResolvePlan`, after the exact match fails and the request is empty or not a known town, fall back to the nearest visited town other than the current city. Replace lines 147-152:

```diff
-    if ($requested === '') return false;
-    $place = stobeResolveTravelLocationFromVisitedZones($requested);
-    if (!$place || strcasecmp($place['label'],$requested) !== 0
-        || strcasecmp(trim(strval($GLOBALS['CACHE_CITY'] ?? '')),$place['label']) === 0) return false;
-    return $place + ['source'=>'visited_location'];
+    $here = trim(strval($GLOBALS['CACHE_CITY'] ?? ''));
+    if ($requested !== '') {
+        $place = stobeResolveTravelLocationFromVisitedZones($requested);
+        if ($place && strcasecmp($place['label'],$requested) === 0
+            && strcasecmp($here,$place['label']) !== 0) return $place + ['source'=>'visited_location'];
+    }
+    return stobeTravelNearestVisitedTown($here);   // new helper, below
```

2. Add the new helper:

```php
function stobeTravelNearestVisitedTown(string $here): array|false {
    $db = $GLOBALS['db'] ?? null; if (!$db) return false;
    $x = floatval($GLOBALS['CACHE_LOC_X'] ?? 0); $z = floatval($GLOBALS['CACHE_LOC_Z'] ?? 0);
    $row = $db->fetchOne("SELECT zone_name,x,y,z FROM location_zones
        WHERE x IS NOT NULL AND lower(zone_name)<>lower($1)
        ORDER BY (x-$2)^2+(z-$3)^2 LIMIT 1", [$here,$x,$z]);
    return $row ? ['label'=>$row['zone_name'],'x'=>floatval($row['x']),
        'y'=>floatval($row['y']),'z'=>floatval($row['z']),'source'=>'visited_location'] : false;
}
```

Use whatever globals hold the request's `loc_x`/`loc_z`; the log shows them in `GEO_DEBUG_RESOLVE_START`. The plan hash at line 60 already accepts `visited_location` points.

3. Put the list of visited towns (minus the current one) into the "Purpose-based destination evidence" prompt section, so the model names a real one, e.g. "Known towns you can lead to: The Hub, Stumble Inn, ...".
4. Make the refusal at line 454 name those options instead of the fixed sentence, so the model has something new to act on and the loop breaks.
5. Apply the change to both the live tree and ss-merge. Add a regression check in which an NPC with no `travel_destinations` and the request "West of Spring" resolves to the nearest visited town.

## How to confirm the fix worked
- **Offline:** the new regression check fails before Part B and passes after it, and `stobe-tests` passes.
- **In game, after Part A:** while talking to Mouse, `grep travel_destinations log/stobeserver.log` shows fresh entries. Mouse's `core_npc_master.metadata` contains `travel_destinations`, and `eventlog` gains `destination_sighting` rows.
- **In game, end to end:** ask "lead me somewhere". The log shows an accepted proposal rather than "Travel agreement rejected before speech". After you accept, a `TRAVEL_LOCATION@<town>` dispatch follows and Mouse moves.

## What is not settled
- Why LocalTravel is missing from `/root/STOBE-src`. It may have been lost when the upstream 1.3.1 merge landed, or it may live only on another branch or in the repo snapshot. Check `git log --all -- src/LocalTravel.cpp` there.
- Which DLL is actually installed. I did not hash it. The last candidate traffic on 10-13 suggests an older build did send candidates.
- Whether visited-town walks are safe enough for long trips. The native path check (`path_confirmed`) does not cover them, so dispatch still has to recheck the path.
