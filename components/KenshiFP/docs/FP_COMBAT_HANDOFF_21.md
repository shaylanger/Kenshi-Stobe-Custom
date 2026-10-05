# FP combat handoff 21
Updated 2026-10-05. Dedicated development checkpoint; does not replace the other coordinator's normal handoff.

## Ownership and baseline
- Coordination read: C:\KenshiModding\FP_COMBAT_COORDINATION_CONTEXT.md, m45.
- Baseline kfp-combat-baseline = 39e871bba819a3b00457747ba9e4e8855fd83838.
- Worktree C:\KenshiModding\kfp-combat-wt, branch fp-combat. Private build mirror /root/kfp-combat.
- Game launches, installs, fixtures and master testing remain coordinator-only. No game tests/installations performed by this agent. No shared actor/STOBE/live/harness-repo changes.
- Candidate revision and SHA will be recorded in C:\KenshiTestRuns\fp-combat\candidates\<commit>\MANIFEST.txt; immutable requests/results use the coordination contract.

## Completed
- Passive native lifecycle probe: client/kfp_combat_trace.h and kfp_combat_probe.inc; only minimal integration into existing client hooks/main-loop/KAH registration.
- fp_combat_probe begin|end|state|events [after_sequence]|clear. Recording defaults off; 512 rows, 64-row pages, reset capture IDs, loss reports, raw state/mode/ammo/stat/actor/gun/target data, native animation and shoot before-after observations. No combat dispatch or game-state writes.
- Automated coordinator-only native FP-off/FP-on capture wrapper tests/capture_native_ranged.py; existing kah transport; sustained crossbow combat must be prepared by coordinator. Raw command transcript/CSVs/results, no false PASS for missing callbacks/ammo changes, restore prior FP toggle.
- Full staged COMBAT_TEST_PLAN.md and NATIVE_PROBE.md document camera/ranged/parity/melee/regression coverage, harness command proposals and P01 prerequisite.
- B07 plain GCC and UBSan production-include mock checks PASS.
- B08 eight decoder/assessment unittest cases PASS.
- Isolated RE_Kenshi MinGW DLL build PASS; exported startPlugin verified. Not installed. Runtime/native offsets remain unvalidated.

## Resolved incident; remaining limitation
- Unbounded ASan test produced runaway DEADLYSIGNAL diagnostics and blocked remote commands. Other agent stopped isolated test; exact pgrep on /root/kfp-combat/test_combat_probe afterward found no process. Remote access recovered.
- Root cause is unresolved; ASan was NOT passed. New offline runner uses 20s subprocess timeout, 15s CPU limit, 1MiB output file limit and core=0; uses plain/UBSan. Do not run ASan unbounded.
- Handoff's earlier timed-out write actually succeeded; this version supersedes it.

## Findings / not implemented
- Baseline KFP_MANUAL_AIM=0. Old targetless R raise/LMB fire is tabled due native task lifecycle conflict and includes unsafe forced states/instant reload. Do not enable it wholesale.
- first_player_char source actually returns selected squad member, fallback squad slot 0; coordination table's old leader comment is stale. Helper semantics unchanged.
- Continuous FP/third-person wheel zoom and separate controlled/inspected identities are now implemented (see current implementation below). Manual ranged dispatch, ADS lifecycle, timed reload and manual melee remain in progress. Native projectile collision/body-part attribution and old target argument behavior remain unresolved.
- P01 native lifecycle evidence pending; no C/R/M/S gameplay PASS claimed. This candidate is telemetry prerequisite, not the requested final combat system.

## Next
1 DONE: native probe+tests/docs committed and pushed as 538851a6f8f605ffd7a2f80b124a03b5f36f35e3. Candidate C:\KenshiTestRuns\fp-combat\candidates\538851a; SHA256 9357105baaa1236cd89df0ecf1d606d9d58accf208b9017e214c73ca28325cf8. Immutable request C:\KenshiTestRuns\fp-combat\requests\20261005-2043-native-ranged-probe.txt. No game results present yet. Runtime logs/DLLs kept outside git.
2 Check coordination context and fp-combat/results during further work; use returned raw native state/animation/shoot evidence for safe readiness/reload ownership design.
3 Build continuous camera zoom while retaining direct controls and fallback toggle; account for collision, head/body visibility, UI/focus and rebasing.
4 Implement phase 1 ranged using native lifecycle, skill spread, ammo/XP/damage and actual first hit; no instant reload/state forcing. Get coordinator's STOBE truce accessor before initiating attacks.
5 Complete native/manual parity tests before phase 2 melee ready-action/animation-commitment/recovery investigation. Tests must fail on missing actual state evidence; no blanket bug-free claim.

## Current implementation: camera and control (2026-10-05)
- Work continues until requested implementation is completed. This file is a running record, not an instruction to stop at a checkpoint.
- kfp_control.inc owns a full five-ID squad handle independently of vanilla selection. Inspecting another squad member does not change direct movement/view ownership. F6 (key_take_control) explicitly transfers; fp_control state|take exposes the same operation. Invalid/missing actor releases ownership instead of falling back to a different squad member.
- direct_default=1 enables direct control once a valid squad world appears. Existing FP toggle remains the native-control fallback; explicit fallback stays off until toggled back or another world is loaded.
- Transfer/fallback/unload clears our cached direct-drive intent and stops only our pinned actor's MOVE_DIRECTION vector, preserving native combat movement modes.
- kfp_view.h/inc implement wheel zoom 0..12m, frame-time smoothing, eye/body visibility switching, five-ray terrain/building/static+visual collision with safety margin. Missing/faulting collision stays at the eyes. Floating-origin calibration keeps the pre-offset eye anchor.
- camera_zoom=1 makes wheel affect distance only. camera_zoom=0 retains optional legacy wheel throttle. Existing speed_scale remains 0.6; wheel no longer changes it by default. Physical input is focus-gated; explicit harness wheel injection uses the same zoom math.
- fp_camera state|distance <0..12>|wheel <-2400..2400> reports requested/applied distance and actual Ogre-node distance, collision state and speed scale; acknowledgments do not prove completion.
- tests/test_control_view.c production-control include plus portable view checks pass plain GCC and UBSan. tests/run_offline.py runs both probe/control suites plus eight trace-decoder checks with bounded subprocesses. Private DLL build passes. These do not validate real engine collision, visibility, movement or ownership behavior.
- tests/validate_camera_control.py is a coordinator-only automated numeric subset using existing harness: zoom/speed, inspect inventory/stats without transfer, explicit transfer and fallback. It restores toggle/distance, leaves actor-a selected/controlled on disposable fixture, and requires coordinator fixture restoration. Physical WASD/UI/focus, moving transfer, visual clipping/head/gear and C05 remain game-test requirements.
- Native binary read-only analysis: existing GUN_RELOAD signature uniquely resolves 0x436fb0 on this installed executable. It immediately copies max count to loaded count, without a timer or inventory debit. It MUST NOT be used as native timed reload. Offline SDK offsets are exploratory only; production uses unique signature scanning.
- P01 native combat evidence still absent as of 2026-10-05 21:13 UTC. User has been given the existing immutable request path to remind coordinator. Continue independent implementation; cease evidence polling once needed data arrives.
