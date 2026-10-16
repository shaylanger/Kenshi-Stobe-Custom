# NC25 = NC24 + row 22-b (travel_terminal context push) + row 23-b (FOLLOW expiry for an unloaded follower) (imm26-nat25)

Tree `C:\KenshiTestRuns\imm26-nc25` (NC24 `src/` + `nc25a_edit.py` + `nc25b_edit.py`; base copy `imm26-nc25-base`). Patch `imm26-nat25.patch` (`/root/imm26/imm26-nat25.patch`, diff -ruN a/src b/src, LF; the edit scripts are the canonical way to apply). NOT built into an installed DLL, NOT installed. Source SHA of the scratch build: see the last line of this file.

## FIX A (row 22-b, product gap N1): `travel_terminal` immediate context push
Cause: owned travel reaches `completed`/`failed` in `NativeTravelLifecycle::Emit` (arrival, measured_route_arrival, order ended, ...), but nothing pushed a context snapshot, so the server only saw the receipt at the next ordinary push (receipt stayed ACCEPTED/requested; no situated arrival event).
Change: `Emit` queues the actor (once per `changed && terminal` transition, deduped, max 32) into `terminalActors`; new `NativeTravelLifecycle::TakeTerminalActors()` drains it under the module lock. `main.cpp` main loop, right after `NativeTravelLifecycle::Tick(...)`, calls `PushImmediateContextSnapshot(npc, "travel_terminal", false)` (async) for each. Log line to look for: `CONTEXT_PUSH: sent immediate snapshot reason=travel_terminal`. The legacy `ApplyTravelTargets` path (no receipt) is unchanged.

## FIX B (row 23-b): FOLLOW expiry never fired
Operator hypothesis (main.cpp:9959, squad member skips expiry): REFUTED. 23-b `state_after.txt` shows `"faction":"Traders Guild"` (not the player faction), and `FollowExpiryGameHours` is read via `ReadLayeredIniInt` in `Utils.cpp FollowExpiryLimitGameSeconds()` in NC20 and NC24 sources alike (key present in all trees NC20-NC24).
Cause found in code: in `ApplyFollowTargets` the expiry sat AFTER `if (!follower || ... || !target ...) continue;`, and `FindCharacterBySerial` only scans `world->getCharacterUpdateList()` (loaded/simulated characters). 23-b `state_after.txt`: `distance_to_player` 1551, `has_orders:false`, final result: no FOLLOW_TICK. A follower that is not in the update list takes the `continue` every tick and the 24 h check is never reached. (Not proven live: the new `FOLLOW_DIAG` line settles it on the next run.)
Change (main.cpp only): expiry moved before the loaded guard; squad status cached from the last loaded tick (`s_followSquadCache`, never seen = not squad; loaded squad members still never expire); if the follower is not loaded at expiry the controller is cleared and jobs/speed/goals are restored when it next loads (`s_followRestorePending`, `FOLLOW_EXPIRED_RESTORED`); helper `RestoreAfterFollowExpiry`. New rate-limited (60 s real) `FOLLOW_DIAG: follower= loaded= squad= start= now= limit_s=` per follower. `FOLLOW_EXPIRED` now also prints `loaded=0|1`.
If 23-b still fails on NC25, read `FOLLOW_DIAG` (start=none = SetFollowTarget stored no start; squad=1 = faction; loaded=0 for the whole run = fix applies; the entry vanishing with no FOLLOW_EXPIRED = another ClearFollowTarget caller).

## Tests
`bash offline-tests.sh` (WSL, `MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 bash /mnt/c/KenshiModding/pending-fixes/npc-immersion-26/NC25/offline-tests.sh`) -> `RESULT nc25-offline PASS`. Source tests `components/STOBE/tests/cpp/native_travel_terminal_push_source_tests.py` (10 failures on NC24, 0 on NC25) and `follow_expiry_unloaded_source_tests.py` (5 -> 0); reruns NC24 suite.
Unproven offline: that the pushed snapshot makes the server emit `situated_event kind=arrival`, and the unloaded-follower hypothesis (live rows only).

## Build NC25
`powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc25 -Out <dir> -Guard travel_terminal,FOLLOW_DIAG` (scratch build, nothing installed), or apply `nc25a_edit.py <tree>` then `nc25b_edit.py <tree>` to a fresh NC24 tree. Install later with `install-dll.ps1 Stobe` (Kenshi closed).

## Rows to test on NC25
- **22-b**: complete an owned-travel trip; expect `NATIVE_TRAVEL ... terminal=1`, then `CONTEXT_PUSH ... reason=travel_terminal`, receipt ingested (agreement COMPLETED), `EV(situated_event)` kind=arrival and a single remark, second bored tick within 180 s silent.
- **23-b**: "Follow me." then +1 game day (or ini `FollowExpiryGameHours=2`); expect `FOLLOW_DIAG` lines, then `FOLLOW_EXPIRED ... loaded=0|1`, no FOLLOW_TICK afterwards.

Scratch build status: FIX A alone compiled+linked OK (SHA256 66086B89726339069135EC44C1B5D1B1D8CF3C8058BA8EF92A95112D86DCE47D, objects=69). Full A+B build was still running at hand-back: result in C:\KenshiTestRuns\imm26-nc25-bF\build.out (not yet checked).
