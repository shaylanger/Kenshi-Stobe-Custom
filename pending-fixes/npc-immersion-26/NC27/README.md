# NC27 = NC25 + nc27a (Hunt progress-by-damage) + nc27b (give-up line) - Shay's Hunt orders 2026-10-16 (imm26-huntA1/huntA2)

Orders: Hunt no-progress timeout = 5 min REAL (10000 game-s); actively damaging the hunted animal resets the timer; when the NPC gives up it says why right away.
Tree `C:\KenshiTestRuns\imm26-nc27` (NC25 `src/` + `nc27a_edit.py` + `nc27b_edit.py`; base `imm26-nc27-base`). Offline only, NOT installed. Scratch build `C:\KenshiTestRuns\imm26-nc27-b\out\Stobe.dll`, SHA256 `19A3E132B8FE49C47639A46E68469DFAC087C7066F47D2D91093739B759489ED` (gitignored copy next to this file). `offline-tests.sh` proves the edit scripts reproduce the tree exactly (diff -rq of src clean).

## Where the timeout is (answers)
- Server `lib/activity/ActivityAgreementAdapter.php`: `'noProgressTimeout' => 1800` (~55 s real) -> 10000 (server patch `pending-fixes/imm26-huntA/apply.py`). The DLL has no constant of its own (default 86400 only when the field is missing).
- Route walk is already exempt: `Goal::Tick` returns from the `Travelling && RouteTravel` branch before the timeout check, arrival resets the timer. Only the walk to the animal, the search and the fight after arrival count (unit-tested).
- Agreement `expiresAt` = now+21600 game-s (~11 min real at speed 1) is a SEPARATE hard end (Cancelled, agreement_expired). DECISION for Shay: raise to 43200 so a long walk plus the 5 min window fits? Not changed.

## nc27a (DLL): damage resets the timer
Hunt only. `ConcreteRuntimeBindings::Refresh` reads the target's summed flesh (6 body parts, `TargetFleshTotal` in ActivityDanger.cpp) into `Target.health/healthValid`; `Goal::Tick` resets `lastProgress_` when health drops by > 0.5 versus the previous observation of the same target while phase Performing with our owned Attack pending. Unreadable health = no reset. Log: `ACTIVITY_PROGRESS_DIAG reset=target_damage ...` (max 1 per 30 game-s).

## nc27b (DLL + server): give-up line
Terminal `report` (status failed, reason token already mapped, e.g. activity_no_verified_progress -> "timeout") -> server stores a situated event (plan_changed + outcome text with the reason) -> NEW DLL: after the server ACCEPTED a failed report `ActivityTransport` queues an `EndingSpeechRequest`; `ServiceEndingSpeech` (game thread) calls the existing `Stobe::UI::TriggerOptionalBoredTurn(world,npc,requester,"")` (settle 1.5 s, retry 3 s, give up 90 s; policy `ActivityEndingSpeech.h`). NEW server (`apply.py`): the failed report's event carries `ending=failed`, is stored with the marker, ranks priority 6 with urgent spacing (20 s global / 40 s per NPC) and ttl 300 s, and the remark instruction tells the NPC to say it is giving up and why. Applies to every activity that FAILS (Hunt/Mine/ClearGroup). Known gap: a failed report is only sent once cleanupComplete (stuck-melee case, 26-a never reports).

## Offline proof
- `bash offline-tests.sh` (WSL): base fails (goal test does not compile, source test fails), edits apply, goal test + policy test + source test (`components/STOBE/tests/cpp/hunt_progress_source_tests.py`) pass, mutation (no `lastProgress_ = now;` in the damage block) fails the goal test, second runs refuse (exit 3).
- Server (huntA tree `/root/imm26/huntA-tree` = compose + apply.py): `tests/imm26_huntA_timeout_regression.php` 4/4 (2 fail unpatched), `tests/imm26_huntA_giveup_regression.php` 16/16 (6 fail unpatched), `imm26_wpE_situated_events_regression.php` 35/35, `imm26_wpE_activity_kinds_regression.php` 51/51. Run: `flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 php tests/<file>`.
- Stale, not ours: `activity_goal_tests.cpp` (Mine terms without route fields; Start() rejects).

## Compose
NC27 (nc27a, nc27b) + durableA1's NC26 edit on the same tree: apply nc27a, nc27b, then durableA1's edit. Files are disjoint (NC26 touches main.cpp + new StobeDurableItem files; nc27b's header is header-only, no CMake change). Server: apply `pending-fixes/imm26-huntA/apply.py <compose tree>` last (idempotent). A composed build and the deploy are later work packages.

## Live-test recipe (needs a lane with NC27 DLL + the patched server; not run)
1. Speed 1. Accept a Hunt from a town that is > 5 min of walking from the animals. Expect NO failure during the walk (no `ACTIVITY_END_DIAG` for the agreement) and a start of the 5 min window only on arrival. Watch the agreement's expiresAt (21600 game-s from accept) if the walk is long: this is the DECISION above.
2. Armed NPC fighting the animal for > 5 min real: expect `ACTIVITY_PROGRESS_DIAG reset=target_damage` roughly every 30 game-s while hits land and no timeout.
3. Unarmed NPC (or one that never hurts the animal) that reached the area: after ~10000 game-s (~5 min real at speed 1) expect `ACTIVITY_END_DIAG ... reason=activity_no_verified_progress`, the failed report, then `ACTIVITY_GIVEUP_SPEECH: dispatched id=<agreement>` within ~2 s, and an in-character line (one or two short sentences) saying it gives up and why (no progress / cannot find anything to hunt). Server eventlog: situated_event row with `"ending":"failed"`, a situated_remark_claim row for it.
4. Negative: kill the animal normally -> no give-up line (completed ending, no `ending` marker).
