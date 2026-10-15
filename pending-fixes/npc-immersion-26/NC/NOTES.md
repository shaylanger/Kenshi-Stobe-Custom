# NC = N1 + N2 composed native Stobe.dll (NOT installed anywhere)

DLL: `NC\Stobe.dll`  SHA256 `E1BB634BB46186CD7A2A904435CE748D029504532D8FFB562D1983AA0492C87B`
(VS2010 x64, 69 objects: 63 src + 6 legacy-v1). Build: `powershell -File NC\build.ps1` -> `RESULT NC-BUILD PASS ... objects=69` (takes `inflight\build-stobe-lock`, source list read from `NC\CMakeLists.txt`, guard strings: travel_destinations LOCAL_TRAVEL travel_lifecycle world_towns known_place abandoned_in_danger N2_PROXIMITY handBackStatus FOLLOW_EXPIRED SpeakWhilePaused outcome=transient).
Patch: `NC\nc.patch` = `diff -ruN a b` against `components/STOBE` (apply with `patch -p1 --binary` from `components/STOBE`; roundtrip verified identical to NC/src, NC/legacy-v1, CMakeLists.txt, Stobe.vcxproj). It adds the `legacy-v1/` dir. Full tree: `NC\src`, `NC\legacy-v1`.

## IMPORTANT: the base is NOT components/STOBE/src alone
`components/STOBE/src` is a half-merged snapshot: its Activity*/LocalTravel*/NativeTravelLifecycle are OLDER than the installed E607 release (no discovery/route refs, camp, activity v2 protocol, `NativePlaceKnowledge.*`, `InspectRequest`, `ValidateForDispatch`; yet its CMakeLists/vcxproj already list NativePlaceKnowledge.cpp). It is NEWER than E607 in: SpeakWhilePaused (ChatBox/Functions/Globals/Utils), world_towns (main.cpp), BodyguardContractProbe (+ `bodyguard_probe` harness command), PlaythroughSession retry (6 attempts, `PLAYTHROUGH: outcome=transient`).
So NC = N1 tree (E607 + camp + NativePlaceKnowledge + N1) + components-only deltas (`_work\comp-delta.patch`, `_work\comp-delta2-playthrough.patch`: files ChatBox, Functions, Globals, Utils, main, StobeHarnessBridge, PlaythroughSession, BodyguardContractProbe) + `n2.patch` (N2c, applied clean with offsets). Not taken from components (older/other line): Activity*, LocalTravel*, NativeTravelLifecycle (N2 hunks still applied), and the components-only `ACTIVITY_PROPOSAL_DIAG`/HUNT4080 ProposalTrace diagnostic in ActivityRuntimeBindings.cpp (isolated diagnostic, dropped).

## Merged feature list (see N1\NOTES.md and N2c\NOTES.md for full JSON shapes; unchanged)
N1: activity `event` op (arrival/progress/threat/injury/phase/handback, signed like poll/report), hand-back of delivered items (grant flag `handback:true`, `handBackStatus` in status row), native_ai `active_job`/`active_package`/`player_orders`/`temporary_companion`, legacy FOLLOW expiry (`[Settings] FollowExpiryGameHours`, default 24, 0 disables, log `FOLLOW_EXPIRED`).
N2: `native_ai.attention` block, `abandoned_in_danger` social event, receipt `participation` object, `facts.transfer_evidence`, proximity bored turn (`N2_PROXIMITY` / `OPTIONAL_TURN`, `stream.php ...optional=1&attn=`), bystander `role/squad_name/squad_id/settlement`, entity export `in_player_squad/squad_id/squad_name/settlement`.
Interaction check: N2 `AppendAttention` inserts before the final `}` of native_ai when `observed:true`; N1's new blocks sit before that brace, so both coexist (attention is appended last).

## Server contract needs
Event op accepted only while the agreement is accepted; server must accept `abandoned_in_danger`, treat `agreement_id` as optional there, whitelist the entity keys above, read native_ai `temporary_companion.present/expires_gamets`, accept `handback:true` grant flag.

## Tests (WSL `bash NC/tests/run.sh`, 18 results, all PASS, failures=0)
n1_logic 83 checks; n2_logic 109; n2_entity 15; social_protocol 22; native_travel_receipt; activity_candidate_policy; chat_interrupt_policy 17; chat_hotkey_policy 27; drawn_weapon_policy 48; npc_panel_request_policy 13; test_inbox_target_ref; portrait_fault_injection 13; shop_pricing; stobe_portable; activity_goal_route_lifecycle; activity_discovery_ref; activity_status_snapshot (the last three from `activity-composed-release\native-aef-candidate\tests`, `_finite` mapped); playthrough_session_retry_source (python source test). `components` `activity_goal_tests` not run (known to abort on the E607 activity base, N1 notes). Native glue (events, hand-back, attention, proximity, participation) is compile-verified only, nothing ran in game.

## Install steps (coordinator, after server patches are composed)
1. Kenshi closed on the lane; copy `NC\Stobe.dll` to the lane's `...\RE_Kenshi\mods\Stobe\Stobe.dll` (active plugin path, not only outer `mods\Stobe`), verify SHA.
2. Activity transport signing key: env `STOBE_ACTIVITY_TRANSPORT_SECRET` or file `activity-transport.key` beside the DLL (>= 32 chars) on each lane; on the private backend `/var/lib/stobe/activity-enabled` containing `1`.
3. Optional settings in stobe.ini `[Settings]`: `FollowExpiryGameHours`, `SpeakWhilePaused`.

## Risks
- Base is a union of two lines (see above); compile + logic tests pass but no game run. The BodyguardContractProbe is included (opt-in via `bodyguard_probe`, but `Observe()` runs each tick); E607 deliberately shipped without it.
- vcxproj entries (legacy-v1 with ObjectFileName/include dir) generated, not built with VS2019; CMake list is the verified one.
- Hand-back, event ordering and threat/injury sampling risks as in N1\NOTES.md; abandon watch agreement_id missing (N2c).

## Open (not done)
`tools\automation\build-stobe.ps1` still reads the stale `build_portable.bat` SOURCES; planned fix: derive SOURCES from CMakeLists.txt into a derived bat (+ legacy-v1 loop, `-Root` param, keep guard strings). Not committed; first attempt aborted before writing (file unchanged).
