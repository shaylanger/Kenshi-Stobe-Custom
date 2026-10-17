## Summary
Mouse never had a single destination she was allowed to use. The Stobe.dll you were playing on (installed 2026-10-14 19:37, about 20 minutes before the chat) was built from the old `/root/STOBE-src` tree. That tree doesn't have the native "local travel candidates" code (`LocalTravel.cpp`), so the game sent the server no `travel_destinations`. The server only accepts a travel offer whose destination it can resolve to a real point. With no native candidates, the only other route is an exact name of a visited place other than the current town, and the prompt never shows the model that list. Each time Mouse proposed a trip ("Spring", "", "West of Spring", "Spring, Stobe's Gamble") the server rejected it. It then replaced her whole reply with one fixed line, "I need to find a practical place before promising to lead us there.", and saved that line as her dialogue. The model never learned why it failed, so it repeated the same mistake every turn.

## Root cause
The installed Stobe.dll has no native travel-candidate producer, so `stobeTravelLocalCandidates()` returns `[]` and `stobeTravelResolvePlan()` returns false for every proposal. `stobeTravelCapture()` then speaks the canned refusal (`lib/travel_companionship.php:453-454`). Two server gaps make it a loop: the visited-place names the resolver would accept are never put in the prompt, and the rejection reason is never fed back to the model.

## Evidence
- **The repeated line is the server's, not the model's.** `/var/www/html/StobeServer/lib/travel_companionship.php:454` sets `$reason = "I need to find a practical place before promising to lead us there.";` when `stobeTravelResolvePlan()` returns false. Lines 503-507 then overwrite `$text` and strip the actions.
- **Five rejections in `log/stobeserver.log` (UTC, 6 h ahead of game time):** lines 2159049, 2159164, 2159477, 2159585 and 2159697, at 01:59:28, 01:59:43, 02:00:24, 02:00:38 and 02:00:48. Each reads `Travel agreement rejected before speech | {"npc":"Mouse","speaker":"Shay","reason":"I need to find a practical place..."}`. The request ids are req_6ad0337b904b8, req_6ad03388720ac, req_6ad033b458190, req_6ad033c171a7a and req_6ad033cb930e7. These match `stobe.log` lines 2017, 2093, 2317, 2394 and 2465 (19:59:28 to 20:00:48 local).
- **What the model actually answered** (`log/chat_llm_full_capture.log` lines 155-160, field `result.response_text`). Every reply was `travel_decision=PROPOSE`, `leader=npc`, with `travel_destination` set to "Spring", then "", "West of Spring", "Spring", and "Spring, Stobe's Gamble". The model's own text was reasonable (for example "I'm headed back toward Spring. You're welcome to walk with me...") but was discarded each time.
- **The prompt gave her nothing to choose from.** The travel system message (message 2) in req_6ad0337b904b8 and req_6ad033b458190 contains:
  - `Observed local choices (...): []`
  - `Grounded named-place choices: []`, `Ranked reachable source choices: []`, `historical observations: []`, `Conditional regional search suggestions: []`
  - `Recorded agreement: null`, affinity 0/100
- **The installed DLL has no producer.** `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll` (and `...\Kenshi\mods\Stobe\Stobe.dll`) is 3,182,080 bytes, dated 10-14 19:37, sha256 starts `e64c65930e4a19f5`. It contains 0 occurrences each of `travel_destinations`, `LOCAL_TRAVEL`, `travel_lifecycle`, `known_place` and `town_boundary`. The previous DLLs in the same folder contain all of them: `Stobe.dll.pre-eight-fix-de16b244...` (10-14 13:22) and `Stobe.dll.pre-mainsteam-769859-...bak`.
- **Where the DLL came from.** `C:\StobeBuild\out\Stobe.dll` has the same hash and time (19:37). `tools/automation/build-stobe.ps1:7` builds from `\\wsl.localhost\...\root\STOBE-src\src`. `C:\StobeBuild\src` has no `LocalTravel.cpp`, and its `Context.cpp` has 0 `travel_destinations`. `C:\StobeBuild\src\main.cpp` (19:35) is byte-identical (md5 c5ef26e0) to `/root/STOBE-src/src/main.cpp`, last changed 10-14 20:35 -0500, which is 19:35 local. `C:\StobeBuild\build_portable.bat` `SOURCES=` doesn't list LocalTravel, NativeTravelLifecycle, NativeAiAwareness, NpcReferralPeople, ProfilePortrait, BodyguardContractProbe or any Activity* file.
- **Where the producer code does exist.** It is only in this repo: `components/STOBE/src/LocalTravel.cpp` (commit d541519, 10-14 13:39). `components/STOBE/src/Context.cpp:3620` adds `"travel_destinations":` from `Stobe::LocalTravel::CandidatesJson(world, npc)` to the chat context (`ChatBox.cpp:6437` sends it with every chat).
- **Database.** `public.core_npc_master` row for Mouse (id 85855): `metadata ? 'travel_destinations'` is false, and the keys `native_ai`, `travel_lifecycle` and `referral_people` are also missing. No NPC row has `travel_destinations`. `eventlog` has 0 `travel_agreement` rows for `travel-v1:2627441408:%`. Mouse's stored chat lines are the canned text (rowids 1032281, 1032286, 1032291).
- **It worked before this DLL.** `log/context_sent_to_llm.log` shows non-empty `Observed local choices` lists on 2026-10-13 03-04 UTC (Ojillo, Ambulin, Laru, Zaro, Icthy), 96 prompts in all. They had candidate kinds terrain, town_boundary, landmark, gate_relative and guard_relative. All of today's Tengu and Mouse prompts are `[]`.
- **Visited places the resolver would accept exist.** `location_zones` has 7 rows, none `knowledge_only`: Spring, The Hub, Bantam Knoll, Stumble Inn, Hummock, Clownsteady, Ogdam. `stobeTravelResolvePlan()` (lines 147-151) rejects an empty name, any name whose resolved label isn't an exact match, and the current town (`CACHE_CITY`, set at `lib/data_functions.php:2420` to the geo zone "Spring"). So "Spring" and "Spring, Stobe's Gamble" fail, and "West of Spring" matches nothing.
- **The loop is visible in the model's input.** The req_6ad033cb930e7 history contains the canned line three times ("Mouse, speaking to Shay: I need to find a practical place...") and nothing about what was proposed or why it was refused.

## What you ruled out
- **The model looping by itself:** the five outputs were all different. Only the server text was identical.
- **Trust or willingness refusal:** affinity was 0, and same_route needs 0 or more (`stobeTravelMinimum`). The logged reason is the "no point" reason, not "I don't trust you".
- **Accept without an offer, or a changed-terms rejection:** all five were PROPOSE with no stored agreement (`null`).
- **Serial sign or identity mismatch:** `stobeParseLiveStorageSerial()` (`chat_helper_functions.php:15336-15359`) turns negative serials into unsigned ones. The people list carries `Mouse|hand_2627441408`.
- **Candidates dropped by freshness or path filters:** there were no rows to filter. The DLL can't produce them and the metadata key is missing.
- **An empty visited-places table:** it has 7 usable rows. The model just never saw them.
- **LLM or connector errors:** every call returned status ok, finish_reason stop, with valid structured JSON.

## Proposed fix
There are three parts: A restores the native candidates (the main cause), B lets NPCs pick known towns and stops the loop (server only, works even on the current DLL), and C feeds rejections back to the model (optional, hardens against loops).

### A. Native: build and install a Stobe.dll that includes LocalTravel
1. **Sync the source.** `/root/STOBE-src/src` is behind `components/STOBE/src`. Only in components: LocalTravel, NativeTravelLifecycle, NativeTravelReceiptPolicy.h, NativeAiAwareness, NpcReferralPeople, ProfilePortrait, BodyguardContractProbe, Activity*, NpcPanelRequestPolicy.h and PortraitFaultInjection.h. Ignoring CR, `/root/STOBE-src` also has some lines the snapshot lacks: main.cpp 213, ChatBox.cpp 29, PlaythroughSession.cpp 18, Functions.cpp 6, Globals.cpp 4, AiNpcInfoWindow.cpp 2. Part of that is the 19:35 edit you rebuilt with.
   - First keep whatever the 19:35 change was for. Look with `diff --strip-trailing-cr /root/STOBE-src/src/main.cpp /mnt/c/KenshiModding/components/STOBE/src/main.cpp`.
   - Then copy `components/STOBE/src/*.cpp *.h` into `/root/STOBE-src/src/`.
   - Re-apply any `/root`-only change you still need.
2. **Add the new units to `C:\StobeBuild\build_portable.bat`:**
   ```diff
   -set SOURCES=AudioPlayback ... ShopPricing ShopPriceHook StobeGoals StobeDrawnWeapon
   +set SOURCES=AudioPlayback ... ShopPricing ShopPriceHook StobeGoals StobeDrawnWeapon LocalTravel NativeTravelLifecycle NativeAiAwareness NpcReferralPeople ProfilePortrait BodyguardContractProbe ActivityController ActivityGoals ActivityNativeExecutor ActivityPolicySupport ActivityRuntime ActivityRuntimeBindings ActivityTransport
   ```
   Otherwise the link fails, because Context.cpp and Functions.cpp call `Stobe::LocalTravel::*` and others.
3. **Stop this happening again.** At the end of `tools/automation/build-stobe.ps1`, before printing the hash, add:
   ```powershell
   $dll = [IO.File]::ReadAllText('C:\StobeBuild\out\Stobe.dll', [Text.Encoding]::ASCII)
   foreach ($m in 'travel_destinations', 'LOCAL_TRAVEL', 'travel_lifecycle') {
     if (-not $dll.Contains($m)) { "BUILD REJECTED: Stobe.dll lacks '$m' (built from a tree without native travel)"; exit 1 }
   }
   ```
4. `components/STOBE/CMakeLists.txt:112` and `Stobe.vcxproj:98,161` refer to `src/NativePlaceKnowledge.cpp/.h`, which aren't in the repo. Nothing in `components/STOBE/src` calls them. Either commit that source (the old DLLs have a `known_place` "Actual native named town" string, so it exists somewhere) or remove the references.
5. **Install** with Kenshi closed: `install-dll.ps1 Stobe`. It writes `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll`; the copy in `RE_Kenshi\mods\Stobe` currently has the same hash. The fastest interim step is to copy `Stobe.dll.pre-eight-fix-de16b244a5f04bcd8780b2c6216262c7` back over Stobe.dll, but you lose whatever the 19:35 build added.

What this gives you: each chat turn carries up to 32 path-checked points within about 180 m (`kLocalRange = 1800`). They include "ground/higher ground to the <dir>", "outside Spring on its <dir> side", gates, guards, nearby buildings, and visible or remembered animals. That is exactly the "a location, a landmark or a direction" you asked for. The model proposes the candidate ID, you say yes, and the server sends `TRAVEL_LOCATION@x;y;z;label;<id>`.

### B. Server: let NPCs pick known towns, and say NONE when there is nothing
Patch `lib/travel_companionship.php` in both trees: live `/var/www/html/StobeServer` and `/root/stobe-work/ss-merge` (they are currently identical, md5 8c581739). The file is untracked in the live tree, so take a backup first.

1. **New function** after `stobeTravelResolvePlan()` (after line 152):
   ```php
   /** Exact visited-place names stobeTravelResolvePlan() will accept; never the current town. */
   function stobeTravelVisitedChoices(int $limit = 10): array {
       $db = $GLOBALS['db'] ?? null;
       if (!$db) return [];
       $here = trim(strval($GLOBALS['CACHE_CITY'] ?? ''));
       try {
           $rows = $db->fetchAll("SELECT zone_name, city_name FROM location_zones
               WHERE metadata->>'knowledge_only' IS DISTINCT FROM 'true'
                 AND x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL
               ORDER BY last_seen_ts DESC NULLS LAST, id DESC LIMIT 64");
       } catch (Throwable $e) { return []; }
       $out = [];
       foreach ($rows as $row) {
           foreach ([strval($row['city_name'] ?? ''), strval($row['zone_name'] ?? '')] as $name) {
               $name = stobeSanitizeTravelLocationToken($name);
               $k = mb_strtolower($name);
               if ($name === '' || isset($out[$k]) || strcasecmp($name, $here) === 0) continue;
               // Same exact-label test stobeTravelResolvePlan() applies, so every listed name resolves.
               $place = stobeResolveTravelLocationFromVisitedZones($name);
               if (!$place || strcasecmp($place['label'], $name) !== 0) continue;
               $out[$k] = $name;
               if (count($out) >= $limit) return array_values($out);
           }
       }
       return array_values($out);
   }
   ```
2. **In `stobeTravelPrompt()`**, after line 330 (`unset($candidate);`):
   ```php
       $visited = stobeTravelVisitedChoices();
       $noDestination = !$candidates && !$visited && !is_array($state['destination_point'] ?? null);
   ```
   On line 345, replace `or an exact known visited location.` with `or an exact name from the known places list below.`

   After line 349 (the `'Observed local choices ...'` line), insert:
   ```php
           . 'Known places (exact names usable as travel_destination; public world knowledge, not proof you walked that road; distant places are long trips): ' . json_encode($visited, JSON_UNESCAPED_UNICODE) . "\n"
           . ($noDestination ? "You have NO executable destination this turn. Use travel_decision=NONE, do not PROPOSE or ACCEPT, and say honestly in your own words that you cannot lead anywhere from here yet.\n" : '')
   ```
   With `travel_decision=NONE`, `stobeTravelCapture()` returns at line 396, so her own words are spoken instead of the canned line.

   Town travel already runs on the current DLL. `stobeBuildTravelLocationAction` (`chat_helper_functions.php:2333-2357`) sends `TRAVEL_LOCATION@x;y;z;label` for a `visited_location`, and the native code skips the local-ID check when there is no ID (`Functions.cpp:8027`).
3. Run `php -l lib/travel_companionship.php` on both trees. Opcache serves the change after about a minute.

### C. Server (optional): tell the model why its offer was refused
In `stobeTravelCapture()`, in the `if ($reason !== '')` block (lines 503-507), call this before `return;`:
`stobeTravelNoteRejection($actor,$speaker,$gamets,$decision,strval($state['destination'] ?? ''),$reason);`

Add these functions:
```php
function stobeTravelRejectKey(string $actor, string $speaker): string {
    $key = stobeTravelKey($actor, $speaker);
    return $key === '' ? '' : 'travel-reject-v1:' . substr($key, strlen('travel-v1:'));
}
function stobeTravelNoteRejection(string $actor, string $speaker, int $gamets, string $decision, string $requested, string $reason): void {
    $key = stobeTravelRejectKey($actor, $speaker);
    if ($key === '' || $gamets <= 0) return;
    try {
        storeEvent('travel_rejection', time(), $gamets, $key . json_encode(['decision'=>$decision,
            'requested'=>mb_substr($requested,0,80), 'reason'=>$reason], JSON_UNESCAPED_UNICODE), 'pending', '', '', false);
    } catch (Throwable $e) { stobeLogWarn('Travel rejection not recorded', ['npc'=>$actor,'error'=>$e->getMessage()]); }
}
function stobeTravelLastRejection(string $actor, string $speaker, int $gamets): ?array {
    $key = stobeTravelRejectKey($actor, $speaker);
    if ($key === '' || $gamets <= 0 || !isset($GLOBALS['db'])) return null;
    try {
        $row = $GLOBALS['db']->fetchOne("SELECT data FROM eventlog WHERE type='travel_rejection'
            AND gamets <= $2 AND gamets >= $2 - 3600 AND LEFT(data, LENGTH($1))=$1
            ORDER BY gamets DESC, rowid DESC LIMIT 1", [$key, $gamets]);
        $d = is_array($row) ? json_decode(substr(strval($row['data']), strlen($key)), true) : null;
        return is_array($d) ? $d : null;
    } catch (Throwable $e) { return null; }
}
```
In `stobeTravelPrompt()`, add `$rejected = stobeTravelLastRejection($actor,$speaker,$gamets);` and append after the known-places line:
```php
. ($rejected ? 'Your last travel ' . $rejected['decision'] . ' to ' . json_encode($rejected['requested']) . ' was refused before you could say it: ' . $rejected['reason'] . " Do not repeat it; choose a listed choice ID or known place name, or use travel_decision=NONE.\n" : '')
```
The existing `REJECTED` infoaction rows can't do this job: the history builder skips `infoaction` (`chat_helper_functions.php:4966`), so the model never sees them.

## How to confirm the fix worked
1. **DLL check.** `grep -a -c travel_destinations "D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll"` gives 0 today and should be 1 or more after A. With step A3 in place, a bad build exits 1.
2. **Replay your exact steps** in game: Spring, talk to Mouse, "Would you be interested in leading me around...", then "Okay, well can you maybe just pick a location, a landmark or a direction and lead me?".
   - In `chat_llm_full_capture.log`, the new request's message 2 should show `Observed local choices ...: [{"id":"local:...` (today `[]`) and `Known places ...: ["The Hub","Bantam Knoll",...]` without "Spring".
   - `stobeserver.log` should have no `Travel agreement rejected before speech ... practical place` line for that turn.
   - Run `sudo -u postgres psql -d stobe -c "SELECT gamets,left(data,220) FROM eventlog WHERE type='travel_agreement' AND data LIKE 'travel-v1:2627441408:3454101504:%' ORDER BY rowid DESC LIMIT 2;"`. It should show a `PROPOSED` row with `destination_point`; today there are 0 rows.
   - Say "Yes, lead the way". There should be an `ACCEPTED` row, and `stobe.log` should log `ACTION_EXEC: TRAVEL_LOCATION actor=Mouse` and she starts walking.
3. **B on its own** (works on the current DLL): ask "Can you lead me to the Hub?". Expect PROPOSE accepted, `destination_point.source = visited_location`, and no rejection line. Also try a case with no evidence: with an empty candidate list and empty known places, her reply should be her own words with `travel_decision` NONE, not the canned line.
4. **Offline regression test** (there is no travel test today; `grep -l stobeTravelCapture tests/` is empty). Stub `$GLOBALS['db']` so `fetchAll`/`fetchOne` return the 7 `location_zones` rows, and set `CACHE_CITY='Spring'`. Assert that `stobeTravelVisitedChoices()` contains "The Hub" and not "Spring", and that `stobeTravelResolvePlan('Mouse', $npc, 'The Hub', null)['source'] === 'visited_location'`. It fails before B (the function doesn't exist) and passes after.

## What is not settled
- I couldn't see who rebuilt and installed the DLL at 19:35-19:37 or what the `/root/STOBE-src` main.cpp edit was for (git diff wasn't allowed). Check it before overwriting that tree.
- I didn't build anything (read-only), so it is unproven that `components/STOBE/src` with the longer SOURCES list compiles under VS2010. The missing `NativePlaceKnowledge.cpp` is probably in a pending-fixes or candidate tree, which I was told not to read.
- Even with a travel-capable DLL, some earlier prompts had empty lists: Laru 4 times and Icthy once on 10-13 around 03-04 UTC, and "Heads or Tails Dealer" in Squin on 10-13 22:xx and 10-14 00:16 UTC. Indoors or navmesh projection failing is likely, but I didn't verify it.
- I don't know whether the backup DLL works with the current server's receipt and lifecycle code.
- `location_zones` holds what the player has visited (global, not per NPC), and those places are kilometres away. Whether NPCs should "know" them is your design call.
- Native local candidates only reach about 180 m. A real hunting trip needs remembered sightings, the regional catalog (`lib/destination_catalog.json`), or towns.
- Process note: to run one read-only query I briefly created and then deleted a scratch file `/tmp/q_mouse.sql` in WSL. No other files, services or database rows were changed.
