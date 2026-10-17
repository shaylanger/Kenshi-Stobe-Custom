## Summary
Mouse has no travel candidates to choose from, so every "lead me" offer fails at the server's place-resolution step, and the server then speaks its own fixed line in her voice. Three things cause it. (1) The installed Stobe.dll does not contain the native local-travel producer at all: the WSL build source /root/STOBE-src is a stale tree without LocalTravel.cpp, and build-stobe.ps1 builds from it. (2) Even with the producer built, the chat turn never refreshes candidates for a non-trader NPC, and the server drops candidates older than 300 s. (3) On a failed offer the server replaces her whole reply with the rejection text and feeds that text back as her own prior speech, so the model repeats it. No code was changed and no state was written.

## Root cause
Candidate list for the prompt = `normalizeCoreNpcMetadata($npc['metadata'])['travel_destinations']` (travel_companionship.php:8-12). For Mouse that key does not exist, so the prompt gets `Observed local choices: []`. Without a candidate ID or a visited-zone name, `stobeTravelResolvePlan` returns false and the code sets `"I need to find a practical place before promising to lead us there."` (travel_companionship.php:454). The underlying reasons, in order of weight:

1. The running DLL lacks the producer. `Context.cpp:3620` (`"travel_destinations": LocalTravel::CandidatesJson`) and `LocalTravel.cpp` are absent from the build tree. Installed Stobe.dll (D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll, 2026-10-14 19:37:42) has the same size as C:\StobeBuild\out\Stobe.dll and contains no `travel_destinations`, `observed_unix`, `reachability`, `native_ai`, `LOCAL_TRAVEL`, `NATIVE_TRAVEL`, or `ACTIVITY` strings. It does contain `CONTEXT_ROUTE`, `CONTEXT_PUSH`, `INV_SYNC`.
2. Freshness and trigger. Candidates are only carried by a full `BuildNpcContextEnvelope` (Context.cpp:3620). The chat-time push for Mouse is the inventory-only payload (main.cpp:4177, `INV_SYNC: sent name=Mouse ... reason=dialogue_npc`); the full envelope is only sent on debounced selection (main.cpp:14201-14202) or trader captures (main.cpp:13720, 16026). The server keeps a candidate only if `observed_unix` is within 300 s (travel_companionship.php, `$observed < time() - 300`). The inventory merge keeps `travel_destinations` only if it was already stored with a matching receipt (data_functions.php:11145-11170), and it never was for Mouse.
3. Failure feedback loop. On rejection `$text = $reason` replaces her reply (travel_companionship.php, `stobeTravelCapture`, the `if ($reason !== '')` block). That line is then written to the event history as Mouse's speech, and the next prompt contains `- Mouse, speaking to Shay: I need to find a practical place before promising to lead us there.` (output 5 times in the last request block, context_sent_to_llm.log block starting line 1929713). The model imitates it.
4. Visited-zone fallback is nearly empty. `location_zones` has 7 rows: Spring, The Hub, Bantam Knoll, Stumble Inn, Hummock, Clownsteady, Ogdam. None are in Stobe's Gamble except Spring, and Waystation / Anti-slaver Guards are not in it. The prompt tells the model to use "an exact known visited location" but never lists them.

## Evidence
Time mapping: game-local time = server log time minus 6 h (game 20:00:48.979 = server 02:00:48.979; CONTEXT_ROUTE at game 20:00:49.924 matches "Snapshot preserved ... 02:00:49" on the server).

Conversation (server log, decoded `inputtext` payloads, Shay to Mouse; all times server time, 2026-10-15):
- 01:58:42 "...any places to hunt nearby" (talking to Mouse)
- 01:59:23 "Would you be interested in leading me around..." (req_6ad0337b904b8)
- 01:59:36 "Why don't you pick a practical place then?"
- 01:59:50 "Do you know any nearby locations that we could go to"
- 02:00:20 "...pick a location, a landmark or a direction and lead me?"
- 02:00:33 "...find a practical place to lead me?"
- 02:00:43 "Do you know any place that you could lead me to?"

Rejections, server log "Travel agreement rejected before speech": 01:59:28 (req_6ad0337b904b8), 01:59:43, 02:00:24, 02:00:38, 02:00:48, all with the same reason.

LLM output (output_from_llm.log):
- 01:59:28, req_6ad0337b904b8: `travel_decision: PROPOSE`, `travel_destination: "Spring"` (her current town). Refused by the CACHE_CITY guard in chat_helper_functions.php `stobeResolveTravelLocationFromVisitedZones`, and the earlier message text ("headed back toward Spring") was discarded.
- 01:59:43, req_6ad03388720ac: `travel_destination: ""`, `travel_reason: "No confirmed local destination..."`. Refused by `if ($requested === '') return false;` in `stobeTravelResolvePlan`.
- Later replies (e.g. output lines ~327866, "We go west out of Spring...") were also discarded. Her text "Spring's the only ground I've got a read on" shows she only knows Spring.

Prompt (context_sent_to_llm.log): `Observed local choices (...): []` at line 1925828 (req_6ad0337b904b8 block) and in every later block.

Database (SELECT only):
- core_npc_master id 85855 (Mouse): metadata has no `travel_destinations`, `travel_destinations_context_receipt`, `native_ai` or `travel_lifecycle` keys. Keys present: `storage_id`, `sync_reason=dialogue_npc`, `type=npc`, `game_ts=133362`, `money`, `portrait`, `profile_age`, and others. Newest update is `inventory_live_sync`.
- 0 of 136 NPC rows contain `travel_destinations`.
- location_zones: 7 rows (above). `metadata.knowledge_only` false for all.

Code:
- Server: travel_companionship.php:8-44 (`stobeTravelLocalCandidates`, 300 s window, requires `observed` true and `reachability` `path_confirmed`), :134-150 (`stobeTravelResolvePlan`), :345 (prompt paragraph, "choose a practical real destination from the observed local candidates below or an exact known visited location"), :454 (refusal text). `stobeTravelCapture` replaces `$text` with `$reason`.
- Server: data_functions.php:11102-11105 and 11145-11170 (receipt merge rule for inventory syncs).
- Native: LocalTravel.cpp:39-38 (`kMaxCandidates`=32, `kLocalRange`=1800 units = 180 m, `kLifetimeMs`), :223-235 (30 s cache), :343-372 (add: path-confirmed, 40 m to 180 m), :439-446 (outside-town-radius directional candidates).
- Build: build-stobe.ps1 line 7 copies `\\wsl.localhost\DwemerAI4Skyrim3\root\STOBE-src\src` to C:\StobeBuild\src. That WSL tree has 43 .cpp/.h files versus 127 in the repo's components/STOBE/src. It has no LocalTravel.cpp, no NativeTravelLifecycle.*, and its Context.cpp (dated 2026-10-01) has 0 `travel_destinations` matches. C:\StobeBuild\src has 0 matches too.
- Repo: commit d541519 (2026-10-14 13:39 -0600, "STOBE: Activity goals, local/native travel...") added the source. It is not in the build tree.
- Server git: lib/travel_companionship.php and lib/destination_discovery.php are untracked (`??`) in the live tree, so the server half of travel is uncommitted work in the live tree.

Game log (stobe.log, local time): 20:00:48.973 "CHAT_TIMING: pipe queued ... I need to find a practical place"; 20:00:48.979 INV_SYNC reason=dialogue_npc; CONTEXT_ROUTE for the same instant is len 4154 → npc_snapshot.php. No LOCAL_TRAVEL line appears anywhere in stobe.log, and CONTEXT_PUSH has 0 hits this session.

## What you ruled out
- Model not knowing place names: the event history does contain Stobe's Gamble, Spring, Waystation, Anti-slaver Guards. The failure is the candidate list and the resolver.
- Affinity / willingness gate: `stobeTravelPolicyRefusal` runs before place resolution and would return a different reason. The reason here is the place-resolution one, so the policy check passed.
- Stale candidates: the DB has none at all, so freshness is a second problem, not the first.
- Prompt-building bug: the prompt is built correctly from the empty list (line 1925828).
- Database or network failure: queries succeed, npc_snapshot calls arrive, stream events arrive. Only the candidate field is absent.
- Visited-zone fallback works in principle (`Spring` was matched and then refused as the current city); the problem is the list is almost empty.

## Proposed fix
Do these in order. Step 1 is the blocker: until the DLL is rebuilt, steps 2 to 5 change nothing.

Step 1, build from the repo source. Diff the trees first (`diff -rq` between components/STOBE/src and /root/STOBE-src/src). Then either copy the repo's .cpp/.h into /root/STOBE-src/src, or point build-stobe.ps1 line 7 at the repo folder (`C:\KenshiModding\components\STOBE\src`). Run the offline C++ tests in components/STOBE/tests/cpp first (native_travel_receipt_tests.cpp is the relevant one). Rebuild with build-stobe.ps1, install with `install-dll.ps1 Stobe`, and confirm: `grep -a -c travel_destinations Stobe.dll` > 0 and `LOCAL_TRAVEL` > 0.

Step 2, refresh candidates at every chat turn (native). In ChatBox.cpp, in the dispatch that starts the inputtext StreamChatTask (around line 4860-4892, before `PlaythroughSession::StartTask`), resolve the target character the same way SendChatToStobeServer does (ChatBox.cpp:6411-6440, loop over `world->getCharacterUpdateList()`) and call a full-envelope push synchronously:

```cpp
// ChatBox.cpp, before StartTask(StreamChatResponseThread...)
if (Character *chatTarget = FindChatTargetCharacter(world, profileName)) {
    PushImmediateContextSnapshot(chatTarget, "chat_turn", /*synchronous=*/true);
}
```
PushImmediateContextSnapshot is static in main.cpp:4195; expose it through a header. The synchronous post means npc_snapshot stores candidates before the stream event is processed. Verify the order in the log: a CONTEXT_ROUTE line must precede "Chat input received" for the same request.

Step 3, the server accepts candidates from that refresh. The 300 s window in travel_companionship.php (`$observed < time() - 300`) is fine once a push happens each turn; keep it. Do not widen it to hide a missing push.

Step 4, tell the model what places exist. In the travel prompt builder (travel_companionship.php around line 345), add a known-places line built from the DB (fetchAll exists, postgresql.class.php:82):

```php
$visited = $GLOBALS['db']->fetchAll(
    "SELECT zone_name FROM location_zones
     WHERE metadata->>'knowledge_only' IS DISTINCT FROM 'true'
     ORDER BY last_seen_ts DESC LIMIT 12", []);
$visitedNames = array_map(fn($r) => $r['zone_name'], $visited);
// Append to the prompt, e.g.:
// "Known visited places (exact names for TravelLocation): ... . You are currently in $currentTown; you cannot lead the speaker to your current town."
```
Also state in the prompt that the current town is not a valid destination, so the model does not propose "Spring" from Spring.

Step 5, stop the loop. In `stobeTravelCapture`, when `$reason !== ''` and the cause is place resolution, do not overwrite `$text`. Keep her reply, strip the travel fields and the movement actions, and store the refusal as a system note (not as her speech). Next prompt: "Your last travel offer could not be made: <reason>. Name only a place from the known-places list or say you do not know a route. Do not repeat the refusal sentence." This removes the server-written line from the Mouse event history (the "Mouse, speaking to Shay: I need to find a practical place..." lines).

Step 6 (design, optional), so "lead me" works more often. When no candidate exists within 180 m, retry `CandidatesJson` with a 400 m range, or add one candidate per cardinal bearing that the player named, projected with `Project()` and checked with `PathConfirmed()`. Both already exist in LocalTravel.cpp; only the range and the trigger change.

## How to confirm the fix worked
- Build: `grep -a -c travel_destinations Stobe.dll` and `grep -a -c LOCAL_TRAVEL Stobe.dll` both > 0 after install.
- Server log, one chat turn: CONTEXT_ROUTE (npc_snapshot) line precedes "Chat input received" for that request_id.
- DB (SELECT only): `SELECT jsonb_array_length(metadata->'travel_destinations') FROM core_npc_master WHERE name='Mouse';` should be > 0 right after the chat.
- context_sent_to_llm.log for that request: `Observed local choices` is a non-empty JSON array of IDs.
- Replay Shay's exact line "Do you know any place that you could lead me to?" at a spot with observed landmarks: expect travel_decision PROPOSE with a candidate ID, then ACCEPT on "Yes, lead the way" with a quote from the current player line, then a TravelLocation action (stobe.log ACTION_EXEC TRAVEL).
- Where no candidate exists, the reply should name the reason (no route known), not the place-resolution sentence, and the next prompt must not contain the refusal sentence as Mouse speech.

## What is not settled
- Whether the native producer returns any candidate in Spring (180 m range, path confirmation, navmesh anchors) is untested because the DLL never contained it. Step 6 may be needed.
- Why the 2026-10-13 Laru receipts had `travel_destinations` incoming but nothing is stored now: not traced. It may point to a second drop in the merge path.
- Timezone offset of 6 h is inferred from matching timestamps, not from configuration.
- Whether the 4080 or any other rig runs an older DLL: not checked.
- The WSL build tree (/root/STOBE-src) may be intentionally older than the repo; I did not confirm which one is the intended source of truth. CLAUDE.md says the repo is a snapshot of /root/STOBE-src, which is the opposite of what the file dates show, so Shay should decide the direction before Step 1.
- Server-side travel code (travel_companionship.php, destination_discovery.php) is untracked in the live tree; its behaviour may still change.
