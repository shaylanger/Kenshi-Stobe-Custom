# Native ranged lifecycle probe (prerequisite; not manual combat)
This candidate adds passive telemetry to the existing main-loop, ranged animation and gun-shot hooks. Recording is OFF until the harness command starts it. No game state, AI task, ammo, draw/reload or targeting mutation is added. Existing FP command replies are unchanged; no shared harness rebuild is needed.

## Command
`fp_combat_probe begin|end|state|events [after_sequence]|clear`
- begin resets the bounded trace and assigns a new capture ID.
- end stops recording and retains rows.
- clear resets rows and assigns a new capture ID, preserving recording on/off.
- state reports capture, recording, frame count and whether an actual actor was observed.
- events returns up to 64 rows after a sequence, header capture/next/oldest/lost/count and footer through/more. Follow through while more=1. Reject lost>0, capture changes, missing footer or sequence gaps. The ring holds 512 events; poll frequently.
- Raw CSV columns: seq, monotonic_ms, observed_frame, event_kind, actor_ptr_hex, ranged_ptr_hex, gun_ptr_hex, target_ptr_hex, raw_state, raw_combat_mode, observed_ammo, raw_stat_or_shoot_argument, frame_dt.
- kinds: 1 observed frame state transition, 2 native animation callback, 3 before native shoot callback, 4 after native shoot callback. Pointer values identify observed objects within a capture; they are not persistent character handles. Unknown integer fields are -1.
- Event time is monotonic wall time; frame_dt is the existing game-loop argument, not a verified combat/simulation clock. State numbers and stat argument are not inferred readiness or reconstructed effective skills.
- Hook events before the first observed frame are intentionally excluded. begin/clear warm up one frame.

## Validation and use
`tests/run_offline.py` compiles the production include against a mocked engine using plain GCC and UBSan, then runs eight trace decoder tests. Every subprocess is bounded in time, CPU and output size. Native offsets, hook cooperation and game behavior still require coordinator-owned P01.

`tests/capture_native_ranged.py` uses the existing kah.py transport. Coordinator must first prepare a selected crossbow actor in sustained native combat on a disposable fixture. The wrapper switches FP off/on, captures both native baselines and restores the prior FP toggle. It verifies paired actual shot calls and one observed ammo decrement per call, animation callbacks and several ammo increases. It never asserts projectile impact/damage or manual control. See COMBAT_TEST_PLAN.md.

Current baseline KFP_MANUAL_AIM=0 is intentionally retained. The old targetless manual prototype is tabled because forced combat fields conflict with native tasks, and its instant reload violates the intended design. Readiness mapping, safe native ownership, spatial collision/body parts, timed reload, spread parity and manual melee remain implementation/evidence tasks.
