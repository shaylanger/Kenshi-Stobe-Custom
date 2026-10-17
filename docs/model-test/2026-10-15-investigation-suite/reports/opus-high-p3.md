## Summary
Mouse could not lead you anywhere because the server had no destination it was allowed to use. Every travel prompt she got listed zero local choices. That list is supposed to come from Stobe.dll, but the installed Stobe.dll was built without the code that produces it. So each time she offered a trip, the server rejected it and swapped her reply for its fixed line, "I need to find a practical place before promising to lead us there." That is the loop you saw. The only place the model could name was Spring, the town she was standing in, and the server rejects the current town by design. The fix is mainly a native build problem: the destination code exists in the repo snapshot but never reached the build tree. A smaller server-side change would also stop the loop.

## Root cause
The server only lets an NPC propose or accept a trip to an allowed point: either a native candidate (`metadata.travel_destinations`, which Stobe.dll must send in the NPC snapshot) or a visited town that is not the current town. The installed Stobe.dll (sha256 starting `e64c65930e4a19f5`, built Oct 14 19:37) was compiled from `C:\StobeBuild\src`, which is synced from `/root/STOBE-src/src`. That tree does not have `LocalTravel.cpp` or the 9 lines in `Context.cpp` that add `travel_destinations`. Those only exist in the repo snapshot `components/STOBE/src` (commit d541519, Oct 14).

## Evidence
- **The conversation** (`stobeserver.log`, UTC, 2026-10-15):
  - 01:58:42 "...looking for a place to gather some uh raw meat..."
  - 01:59:23 "...Would you be interested in leading me around..."
  - 01:59:36 "Why don't you pick a practical place then?"
  - 01:59:50 "Do you know any nearby locations that we could go to?"
  - 02:00:20 "...pick a location, a landmark or a direction and lead me?"
  - 02:00:33 "Okay, can you please find a practical place to lead me?"
  - 02:00:43 "Do you know any place that you could lead me to?"
- **Five rejections** in `stobeserver.log` (lines 2159049, 2159164, 2159477, 2159585, 2159697; 01:59:28 to 02:00:48), each `Travel agreement rejected before speech | {"npc":"Mouse","speaker":"Shay","reason":"I need to find a practical place before promising to lead us there."}`.
- **What the model proposed** (`output_from_llm.log`):
  - `travel_decision PROPOSE`, `travel_destination` set to `"Spring"`, `""`, `"West of Spring"`, `"Spring"`, then `"Spring, Stobe's Gamble"`.
  - Its own reasons say it knew of nothing else, e.g. "Spring is the only place I have a read on"; "No confirmed local destination".
- **Empty choice lists in every prompt.** `context_sent_to_llm.log`, last 8 travel prompts (e.g. lines 1923121 to 1930134):
  - `Observed local choices (...): []`
  - `Grounded named-place choices: []`
  - `Ranked reachable source choices: []`
  - `This NPC historical observations: []`
  - `Conditional regional search suggestions: []`
- **Server code:** `/var/www/html/StobeServer/lib/travel_companionship.php`
  - :12-19 builds candidates only from `metadata.travel_destinations` (path_confirmed, observed within 300 s).
  - :134-151 `stobeTravelResolvePlan`: if there is no candidate, it falls back to visited zones, but returns false when the town equals `CACHE_CITY` (:150).
  - :451-454 a false result gives the fixed reason; :504 `$text = $reason;` replaces her whole spoken reply with it.
  - `lib/destination_discovery.php:49-51,139` fills the other prompt lists from the same `travel_destinations` data.
- **Database (SELECT only):**
  - Mouse (`core_npc_master` id 85855) has no `travel_destinations`, `native_ai`, `travel_lifecycle` or `referral_people` key in `metadata`.
  - No NPC in the table has `travel_destinations`.
  - `eventlog` has 0 `destination_sighting` rows and 0 `travel_agreement` rows.
- **The installed DLL:** a byte search of `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` (and the RE_Kenshi copy, same hash) finds 0 hits for `travel_destinations`, `native_ai` and `referral_people`, while ordinary snapshot fields (`storage_id`, `is_carrying`) are present.
- **The source trees:**
  - `diff --strip-trailing-cr C:\StobeBuild\src\Context.cpp components\STOBE\src\Context.cpp` shows exactly 9 lines: 4 includes (`LocalTravel.h`, `NativeAiAwareness.h`, `NpcReferralPeople.h`, `NativeTravelLifecycle.h`) and snapshot lines 3620-3624, which add `travel_destinations`, `native_ai`, `referral_people` and `travel_lifecycle`.
  - `/root/STOBE-src/src/LocalTravel*` does not exist, and `/root/STOBE-src/src/Context.cpp` is dated Oct 1.
  - `C:\StobeBuild\build_portable.bat`, `set SOURCES=` line, has none of: LocalTravel, NativeAiAwareness, NativeTravelLifecycle, NpcReferralPeople, ActivityController, ActivityGoals, ActivityNativeExecutor, ActivityPolicySupport, ActivityRuntime, ActivityRuntimeBindings, ActivityTransport, BodyguardContractProbe, ProfilePortrait. None of these exist in `C:\StobeBuild\src` either.
  - Snapshot `Functions.cpp` differs from the build tree by 58 lines. These include the 5-field `TRAVEL_LOCATION` parse and `LocalTravel::Validate` (snapshot :8024-8036). `main.cpp` differs by 697 lines and calls `LocalTravel::Reset()` (:15289).
- **Visited towns are known but never offered.** `location_zones` (knowledge_only not true) holds Spring, The Hub, Bantam Knoll, Stumble Inn, Hummock, Clownsteady and Ogdam. None of them appear in the travel prompt. Spring is the current town, so it is rejected at :150.

## What you ruled out
- **Affinity or willingness.** The rejection happens after `stobeTravelPolicyRefusal` (:433), so that check passed.
- **An earlier stuck agreement.** "Recorded agreement" was `null` and there are no `travel_agreement` rows.
- **The model refusing.** It did return PROPOSE every time; the server threw the offer away.
- **The staleness filter** (300 s, :19). It is not the cause here: there are no rows at all, not stale ones.
- **Dispatch.** It never got that far; no `TRAVEL_LOCATION` was issued.

## Proposed fix
**A. The root fix (native): build and install a Stobe.dll that contains the destination producer.**
1. Bring the travel and native-awareness sources from `C:\KenshiModding\components\STOBE\src` into `/root/STOBE-src/src`, since `build-stobe.ps1` copies `.cpp`/`.h` from there into `C:\StobeBuild\src`.
   - At minimum: `LocalTravel.cpp/.h`, `NativeAiAwareness.cpp/.h`, `NpcReferralPeople.cpp/.h`, `NativeTravelLifecycle.cpp/.h`, `NativeTravelReceiptPolicy.h`.
   - Plus the changed `Context.cpp`, `Functions.cpp`, `main.cpp`, and whatever else commit d541519 changed: `git show d541519 --stat` lists 43 source files. These depend on each other, so syncing the whole d541519 source set is safer than cherry-picking.
   - Check first with `git status` / `git log` in both trees. `NativeTravelLifecycle.*` and `PlaythroughSession.cpp` currently have uncommitted edits in the repo, so someone is working on them; decide which version you want before copying.
2. The `Context.cpp` change itself (snapshot lines 1-4 and 3620-3624), from the build tree to the snapshot:
   ```diff
   +#include "LocalTravel.h"
   +#include "NativeAiAwareness.h"
   +#include "NpcReferralPeople.h"
   +#include "NativeTravelLifecycle.h"
   ...
   +  json += "\"travel_destinations\":" + Stobe::LocalTravel::CandidatesJson(world, npc) + ",";
   +  json += "\"native_ai\":" + Stobe::NativeAiAwareness::CaptureJson(world, npc) + ",";
   +  json += "\"referral_people\":" + Stobe::NpcReferralPeople::CaptureJson(world, npc) + ",";
   +  Stobe::NativeTravelLifecycle::ObserveIdle(world, npc, CurrentGameTsSeconds());
   +  json += "\"travel_lifecycle\":" + Stobe::NativeTravelLifecycle::SnapshotJson(npc->getHandle().serial) + ",";
   ```
3. Add the new translation units to the `set SOURCES=` line in `C:\StobeBuild\build_portable.bat`: `LocalTravel NativeAiAwareness NpcReferralPeople NativeTravelLifecycle`, plus the Activity*/ProfilePortrait/BodyguardContractProbe units if you sync the full set. They are already listed in `components/STOBE/Stobe.vcxproj:100,120` and `CMakeLists.txt:94,114`, but the portable VS2010 build ignores those files. Without this step the build fails to link (the symbols are missing).
4. Build with `tools\automation\build-stobe.ps1`, then install (Kenshi closed) with `install-dll.ps1 Stobe`.

After this, `LocalTravel::CandidatesJson` sends up to 32 path-confirmed points for each NPC in the snapshot: gate_relative, town_boundary, landmark, compass terrain samples and known places, each with `observed`, `observed_unix`, `reachability:"path_confirmed"` and `actor_serial`. The server (:8-48) turns them into choices. The model can then PROPOSE a candidate ID, "yes, lead the way" ACCEPTs it, and :525 sends `TRAVEL_LOCATION@x;y;z;label;id`, which the new `Functions.cpp` re-checks with `LocalTravel::Validate`.

**B. Optional server-side change (works with the current DLL, needs your decision): offer visited towns by name.** `stobeTravelResolvePlan` already accepts an exact visited-town name that is not the current town (:148-151). The prompt just never lists any. In `lib/travel_companionship.php`:
```php
function stobeTravelKnownTownChoices(int $limit = 10): array {
    if (!isset($GLOBALS['db'])) return [];
    $here = trim(strval($GLOBALS['CACHE_CITY'] ?? ''));
    try {
        $rows = $GLOBALS['db']->fetchAll(
            "SELECT COALESCE(NULLIF(city_name,''),zone_name) AS label, MAX(last_seen_ts) AS seen
             FROM location_zones
             WHERE metadata->>'knowledge_only' IS DISTINCT FROM 'true'
               AND x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL
             GROUP BY 1 ORDER BY seen DESC LIMIT 40");
    } catch (Throwable $e) { return []; }
    $out = [];
    foreach ($rows ?: [] as $r) {
        $l = trim(strval($r['label'] ?? ''));
        if ($l === '' || strcasecmp($l, $here) === 0) continue;
        if (stobeResolveTravelLocationFromVisitedZones($l)['label'] ?? '' !== $l) continue; // same check the resolver uses
        $out[] = $l; if (count($out) >= $limit) break;
    }
    return $out;
}
```
Then in `stobeTravelPrompt`, right after the `Observed local choices` line (:349), add:
```php
. 'Known towns (exact name usable as travel_destination for a longer same_route/detour leg; not the current town; does not prove you know the road or that it is safe): '
. json_encode(stobeTravelKnownTownChoices(), JSON_UNESCAPED_UNICODE) . "\n"
```
Note the precedence bug in the `if` line of the sketch: write it as `$res = stobeResolveTravelLocationFromVisitedZones($l); if (!$res || strcasecmp($res['label'],$l) !== 0) continue;`.

This conflicts with a written design choice: `destination_discovery.php:189-190` says a global named-location coordinate "is knowledge, not actor-owned executable evidence". Also, `location_zones` is not per NPC or per save, and towns are far away (Spring x≈52759, The Hub x≈-50979) compared with the one-game-day leg limit. Treat B as a bridge, or skip it once A ships.

**C. Stop the loop itself (server, small).** When there are no choices at all, tell the model so, instead of letting it PROPOSE and get overwritten every turn. In `stobeTravelPrompt` (:328), when `$candidates === []` and B gives no towns, append: "No executable destination is available this turn. Use travel_decision=NONE, say honestly you don't know a route from here, and do not offer to lead." Also consider keeping the model's own speech on a destination-resolution rejection, instead of replacing it with the fixed string at :504. For example, only strip the movement actions, and add a hint to the next turn's prompt naming the destination that failed to resolve.

## How to confirm the fix worked
1. **Before:** `strings`/byte-grep `mods\Stobe\Stobe.dll` for `travel_destinations` finds 0 hits. **After A:** at least 1.
2. Talk to any NPC, then run `sudo -u postgres psql -d stobe -At -c "select jsonb_array_length(metadata->'travel_destinations') from core_npc_master where name='Mouse'"`. Before: empty. After: a number greater than 0.
3. `grep -n "Observed local choices" log/context_sent_to_llm.log | tail -1` shows a non-empty JSON list. `grep -c "type='destination_sighting'"` style check: `select count(*) from eventlog where type='destination_sighting'` is greater than 0.
4. Replay the conversation ("Can you pick a place and lead me?", then "Yes, lead the way"):
   - `stobeserver.log` has no `Travel agreement rejected ... practical place` line.
   - An `eventlog` row `type='travel_agreement'` with status ACCEPTED appears.
   - `stobe.log` shows `ACTION_EXEC: TRAVEL_LOCATION actor=Mouse` with no `LOCAL_TRAVEL: plan rejected`, and Mouse walks.
5. For B: with the old DLL, ask for "The Hub". The prompt lists "The Hub" and the PROPOSE is accepted. Asking for "Spring" while in Spring is still rejected.

## What is not settled
- Which source tree produced the installed DLL `e64c6593`, and why the d541519 sources were never synced into `/root/STOBE-src`. A "mainsteam" DLL was installed at 19:22 before the 19:37 one. I did not read `pending-fixes/` (that was forbidden), and the travel/activity work may live there.
- Whether the snapshot's `Functions.cpp`/`main.cpp` (697-line diff) build cleanly under VS2010 with the build tree's other files. Not built or tested.
- How often native snapshots are sent. Candidates older than 300 s are dropped (:19), so if NPC snapshots are not refreshed within 5 minutes of chatting, the list could still come up empty after A.
- Earlier "We already have a journey agreed" rejections for Laru (Oct 13) imply stored agreements, yet this database has 0 `travel_agreement` rows. They probably came from another rig or a test DB; not checked.
- Whether B fits your design. It contradicts the "global coordinates are knowledge only" rule in `destination_discovery.php`.
