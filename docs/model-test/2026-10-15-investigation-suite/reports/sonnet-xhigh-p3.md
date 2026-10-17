## Summary

Mouse never had any destination to offer. Every prompt in the chat said `Observed local choices: []`. The Stobe.dll installed in the game cannot send the "travel_destinations" list the server's travel code depends on. The model then named places in free text ("Spring", "West of Spring", ""), the server could not resolve them, and it replaced Mouse's reply with the same canned sentence each time. Nothing was saved between turns, so the loop restarted every turn.

Two things made it worse:
- The prompt tells her to use "an exact known visited location" but never lists any.
- Even with a working DLL, the native producer only offers points within about 180 m of her.

The proposed fix has two layers. Layer 0 is a correct DLL, which is what the server code was designed around. Layer 1 is a small server change so she can also name towns the party has visited.

Times: server and eventlog times are UTC. The plugin log is local time (UTC-6), so 19:58 local is 01:58 UTC.

## Root cause

1. **The running DLL has no local-travel producer.**
   - `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` was built 2026-10-14 19:37:42 local, about 10 minutes before the game launched at 19:47:51. It is 3,182,080 bytes, SHA256 E64C6593…C1A9A, and identical to `C:\StobeBuild\out\Stobe.dll`.
   - It contains none of the strings `travel_destinations`, `path_confirmed`, `LOCAL_TRAVEL`, `travel_lifecycle`, `native_ai` or `referral_people`.
   - Both backups next to it contain all of them: `Stobe.dll.pre-mainsteam-769859-20261014T192218Z.bak` (3,850,240 bytes) and `Stobe.dll.pre-eight-fix-de16b244…` (3,865,088 bytes).
   - That build compiled only 43 sources. `C:\StobeBuild\obj` has no LocalTravel, NativeAiAwareness, NativeTravelLifecycle, NpcReferralPeople, ProfilePortrait or Activity* objects.
   - The repo has 56 `.cpp` files under `components\STOBE\src`.
   - `tools\automation\build-stobe.ps1` syncs from `\\wsl.localhost\DwemerAI4Skyrim3\root\STOBE-src\src`. That tree is the upstream 1.3.1 release: 43 files, `Context.cpp` from 2026-10-01, no `travel_destinations`.
   - `C:\StobeBuild\build_portable.bat` line 21 `SOURCES=` is the same 43-name list.
2. **So the server gets no candidates.** The repo's `components\STOBE\src\Context.cpp:3620` is the only place that emits `travel_destinations` (via `LocalTravel::CandidatesJson`), and it is not in the running binary. The server's `stobeTravelLocalCandidates()` (`lib/travel_companionship.php:8-47`) returns `[]`.
3. **The model cannot satisfy the prompt.** The rules at `travel_companionship.php:345-349` demand a candidate ID or an exact known visited location. It has neither, so it proposes `PROPOSE` with free text.
4. **The server rejects the free text and overwrites her reply.**
   - `stobeTravelCapture()` calls `stobeTravelResolvePlan()` (`travel_companionship.php:451`). With no candidates it falls to `stobeResolveTravelLocationFromVisitedZones()`.
   - That requires an exact label match, and line 150 refuses the town the NPC is standing in.
   - Mouse is in Spring, so "Spring" is refused. "Spring, Stobe's Gamble" and "West of Spring" are not exact labels, and a blank destination returns false at line 147.
   - Line 453-454 sets `$reason = "I need to find a practical place before promising to lead us there."`, and line 504 sets `$text = $reason`. Nothing is written to travel state, so the next turn starts fresh.
5. **Design gap.** Even with a good DLL, nothing tells the model which named places exist. See "What is not settled" for the 180 m limit.

## Evidence

Chat from eventlog (SELECT), UTC:

| Time | Shay says | What the player saw |
|---|---|---|
| 01:58:42 | "…know any places to hunt nearby" | normal reply, `travel_decision` NONE |
| 01:59:23 | "…leading me around and I'll watch your back…" | canned line (row 1032259) |
| 01:59:36 | "Why don't you pick a practical place then?" | canned line |
| 01:59:50 | "Do you know any nearby locations…" | normal reply: "Spring's the only place I've got a read on" |
| 02:00:20 | "…pick a location, a landmark or a direction and lead me?" | canned line |
| 02:00:33 | "…find a practical place to lead me?" | canned line |
| 02:00:43 | "Do you know any place that you could lead me to?" | canned line |

- `stobeserver.log` has "Travel agreement rejected before speech" for Mouse at 01:59:28, 01:59:43, 02:00:24, 02:00:38 and 02:00:48, always with that reason.
- What Mouse actually generated (`log/output_from_llm.log`) was a different, sensible reply each time, all `PROPOSE`:
  - Line 327707: `travel_destination` "Spring".
  - Line 327740: `travel_destination` blank.
  - Line 327863: "West of Spring".
  - Line 327916: "Spring".
  - Line 328072: "Spring, Stobe's Gamble".
  - These were discarded and replaced by the canned line.
- In `log/context_sent_to_llm.log`, every prompt from 2026-10-15T01:49:50 to 02:00:44 has `Observed local choices (…): []`. The last such prompt is at line 1930134. The destination section also shows `Grounded named-place choices: []`, `Ranked reachable source choices: []`, `This NPC historical observations: []` and `Conditional regional search suggestions: []`. `Recorded agreement … : null`.
- DB, `core_npc_master` row for Mouse (SELECT):
  - `metadata` keys are type, money, orders, game_ts, …, sync_reason(=dialogue_npc), …, inventory_items. There is no `travel_destinations`, `native_ai`, `travel_lifecycle` or `referral_people`. Zero NPCs in the table have `travel_destinations`.
  - `extended_data->relationships` for Mouse: Shay aff 2, tier Neutral.
- The same server code worked when the plugin did send candidates:
  - `context_sent_to_llm.log` line 1771860 (2026-10-13T04:22:32) has a non-empty list ("higher ground to the east", "ground beyond Defensive Gate IV to the south").
  - `stobeserver.log` 2097462 and 2097936 (10-13 04:21:12 and 04:22:08) store a `PROPOSED` travel_agreement for Laru with destination "higher ground to the east".
  - Every list after 10-13T04:23:01 is `[]`.
- `location_zones` has 7 rows: Spring, The Hub, Bantam Knoll, Stumble Inn, Hummock, Clownsteady and Ogdam. The fallback has data, but no code puts those names in the prompt. Only the unconditional phrase at `travel_companionship.php:345` mentions them.
- `components/STOBE/src/LocalTravel.cpp` emits only the kinds observed_source, guard_relative, gate_relative, town_boundary, terrain, landmark and remembered_source. The server also consumes `known_place` (`lib/destination_discovery.php:142,190`, `lib/area_goal.php:20`, `lib/activity/ActivityAgreementAdapter.php:292`), but nothing produces it.

## What you ruled out

- **Affinity or policy refusal.** Mouse's aff toward Shay is 2. `stobeTravelPolicyRefusal` allows `same_route` at 0 or above. Its refusal texts ("I don't trust you enough…", "I'm not changing my plans for you") never appeared.
- **Stale agreement or cleanup state.** Recorded agreement is null, and "Our previous journey has ended…" never appeared.
- **Accept, quote or leader problems.** All five failing turns were `PROPOSE`, not `ACCEPT`. The failure is in destination resolution (line 453).
- **Model misbehaviour.** The JSON was valid, and she correctly would not invent an ID. She told you the truth, "Spring's the only place I've got a read on".
- **Server regression.** The same code stored proposals on 10-13 with candidates present.
- **Empty `location_zones`.** It has 7 rows. The problem is that none of them reach the model.

## Proposed fix

### Layer 0: get a Stobe.dll that includes the travel producer (needed for any local "pick a spot and lead me")

1. Close Kenshi.
2. Build from the repo tree `C:\KenshiModding\components\STOBE`, not from `/root/STOBE-src`. The canonical build guide is `mod/docs/Stobe/building.md` (referenced from `components/STOBE/BUILD.md`). The project and CMake lists contain `LocalTravel.cpp` (`Stobe.vcxproj:120`, `CMakeLists.txt:94`).
3. If you keep using `build_portable.bat`, two edits are needed:
   - Make `tools/automation/build-stobe.ps1` copy from `C:\KenshiModding\components\STOBE\src` (or sync that into `/root/STOBE-src/src` first).
   - Extend line 21 `SOURCES=` with the 13 files missing from it: ActivityController, ActivityGoals, ActivityNativeExecutor, ActivityPolicySupport, ActivityRuntime, ActivityRuntimeBindings, ActivityTransport, BodyguardContractProbe, LocalTravel, NativeAiAwareness, NativeTravelLifecycle, NpcReferralPeople, ProfilePortrait.
   - I did not run this. Activity* may need flags or libraries the portable script lacks, so the canonical guide is safer.
4. Before installing, check the DLL (read-only):
   ```powershell
   $t=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes('C:\StobeBuild\out\Stobe.dll'))
   'travel_destinations','path_confirmed','travel_lifecycle','native_ai' | % { "$_ = $($t.Contains($_))" }
   ```
   All four must say True.
5. Quick stopgap: copy `Stobe.dll.pre-eight-fix-de16b244a5f04bcd8780b2c6216262c7` (the newer backup) over `Stobe.dll` with Kenshi closed. I only verified that it contains the strings, not that it works with today's server.

With Layer 0 alone, her list returns entries like "outside Spring on its west side", "higher ground to the east", "ground beyond Defensive Gate IV to the south", "outside <building> to the <dir>", and "near <animal> to the <dir>" for visible animals (useful for hunting). The model proposes by candidate ID, you say yes, and the existing `TRAVEL_LOCATION@x;y;z;label;local:…` dispatch plus the native `Validate()` handle the walk.

### Layer 1: server fix so she can name towns and the dead end becomes useful (`/var/www/html/StobeServer/lib/travel_companionship.php`, patch the live tree and `ss-merge`)

a) Add this helper (for example after `stobeTravelPlanHash`). It lists names only; coordinates stay server-side and resolve through the existing fallback at lines 148-152:
```php
/** Visited places an NPC may name as a destination; never the town it is standing in. */
function stobeTravelKnownPlaceNames(int $limit = 12): array {
    $db = $GLOBALS['db'] ?? null;
    if (!$db) return [];
    $here = trim(strval($GLOBALS['CACHE_CITY'] ?? ''));
    try {
        $rows = $db->fetchAll(
            "SELECT zone_name FROM location_zones
             WHERE x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL
               AND COALESCE(zone_name,'') <> ''
               AND metadata->>'knowledge_only' IS DISTINCT FROM 'true'
             ORDER BY last_seen_ts DESC, id DESC LIMIT 32");
    } catch (Throwable $e) { return []; }
    $out = [];
    foreach (is_array($rows) ? $rows : [] as $row) {
        $name = stobeSanitizeTravelLocationToken(strval($row['zone_name'] ?? ''));
        if ($name === '' || strcasecmp($name, $here) === 0 || in_array($name, $out, true)) continue;
        $out[] = $name;
        if (count($out) >= $limit) break;
    }
    return $out;
}
```
Using `zone_name` guarantees the label the resolver returns equals the requested text, which line 149 requires.

b) In `stobeTravelPrompt()`, change the instruction at line 345 and add the list just before the "Observed local choices" line (349):
```diff
-... choose a practical real destination from the observed local candidates below or an exact known visited location. Record it with PROPOSE ...
+... choose a practical real destination from the observed local candidates below (use the candidate ID) or one of the Known places below (use its exact name, only for a trip to another town). If the speaker asks you to pick a place, pick one from these two lists in this same response; do not answer with only a promise to find one. Record it with PROPOSE ...
@@ near line 349
+        . 'Known places you can name as travel_destination (exact text; never your current town): ' . json_encode(stobeTravelKnownPlaceNames(), JSON_UNESCAPED_UNICODE) . "\n"
         . 'Observed local choices (ID selection; ...): ' . json_encode($candidates, ...) . "\n"
```

c) Make the refusal informative (lines 453-454):
```diff
         if (!$point) {
-            $reason = "I need to find a practical place before promising to lead us there.";
+            $known = stobeTravelKnownPlaceNames(4);
+            $reason = $known
+                ? "I can't name a spot I can reach from here. Out of town I only know " . implode(', ', $known) . "."
+                : "I need to find a practical place before promising to lead us there.";
```

d) Add a regression check beside `tests/goal_destination_regression.php`: PROPOSE with destination "The Hub" while `CACHE_CITY='Spring'` must resolve to source `visited_location`, and PROPOSE with "Spring" must still be rejected. Run `php -l`, deploy to both trees, then `stobe-rotate-logs`.

### Optional, larger changes (design decisions)

- **Native range.** Add the other-town `known_place` producer natively. The API pattern exists at `PlayerBaseState.cpp:138,185` (`shou->townList->getAllTowns()`). The catch is that `LocalTravel.cpp` `add()` rejects anything beyond `kLocalRange` (1800 units, line 36), the server requires `reachability=='path_confirmed'` (travel_companionship.php:17), and `Validate()` needs `PathConfirmed`. I expect a multi-kilometre path query to fail on streamed navmesh, but I have not tested that. Layer 1 deliberately avoids this by using the server-side visited-place fallback.
- **Detour threshold.** `stobeTravelMinimum()` (line 301) requires affinity 20 for a `detour`. Mouse is at 2. Once she can name a place, a "lead me to a hunting spot" proposal classed as `detour` will be refused with "I'm not changing my plans for you". Lower the 20 if you want neutral NPCs to guide you.

## How to confirm the fix worked

1. Before install, the DLL string check above prints True for all four.
2. After launching and opening a chat with Mouse, `select metadata->'travel_destinations' from core_npc_master where lower(name)='mouse'` returns a non-empty JSON array. The newest "Observed local choices" line in `log/context_sent_to_llm.log` starts with `[{"id":"local:`.
3. Replay "Do you know any place that you could lead me to?" and "pick a location, a landmark or a direction and lead me".
   - The log must not show "Travel agreement rejected before speech … practical place".
   - `select data from eventlog where type='travel_agreement' order by rowid desc limit 1` shows `"status":"PROPOSED"` with a destination label.
   - Then say "yes, lead the way". The status becomes ACCEPTED, `output_to_plugin.log` shows a `TRAVEL_LOCATION@…` line, and the plugin log shows an ACTION_EXEC for it.
4. For Layer 1, the prompt shows `Known places you can name…: ["The Hub", …]` without "Spring" while she is in Spring. Asking for "The Hub" yields a PROPOSED row whose `destination_point.source` is `visited_location`.
5. Negative check: if the prompt lists no candidates and no known places, her reply should still be the canned line.

## What is not settled

- **Who built the 19:37 DLL, and why from the old tree.** The evidence is only the files above. Explaining it needs the candidate or pending folders, which I was told not to read. I also did not test either backup DLL against the current server.
- **Empty lists with the feature DLL.** Prompts on 10-13T04:23 (Icthy) and 10-14T00:12-01:00 (Heads or Tails Dealer, speaker Beak) were also empty and also hit the "practical place" rejection. The feature DLL was probably installed then. I could not tell whether that DLL was loaded on those instances or whether the producer returns `[]` in some situations. Possible causes I did not test: NPC indoors, no path-confirmed points, a `travel_destinations` entry older than the 300 s server filter, or a partial `inventory_live_sync` dropping the field (the 10-13 `CONTEXT_RETENTION_DIAG` lines said `current_receipt_usable:false`, and that diag is no longer logged). So Layer 0 may not remove every loop, and the Layer 1 fallback matters.
- **Far trips.** I did not verify that the plugin carries out a `visited_location` `TRAVEL_LOCATION` for a distant town. The nearest visited towns are about 100,000 units (x) from Spring. Offering far towns for a hunt would be unrealistic, so consider sorting by distance.
- **How far local candidates reach.** Native candidates cover only about 180 m (`kLocalRange`), compass samples at 400 and 1100 units, and at most 32 candidates and 40 path queries. If you want longer walks, those constants in `LocalTravel.cpp` need raising, and `Validate` uses `kLocalRange+400`.

Read-only run: I wrote no files and made no state-changing requests.
