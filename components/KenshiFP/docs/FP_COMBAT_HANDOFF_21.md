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
- No continuous FP/third-person wheel zoom yet. No manual ranged dispatch, ADS lifecycle, timed reload or manual melee yet. Native projectile collision/body-part attribution and old target argument behavior remain unresolved.
- P01 native lifecycle evidence pending; no C/R/M/S gameplay PASS claimed. This candidate is telemetry prerequisite, not the requested final combat system.

## Next
1 DONE: native probe+tests/docs committed and pushed as 538851a6f8f605ffd7a2f80b124a03b5f36f35e3. Candidate C:\KenshiTestRuns\fp-combat\candidates\538851a; SHA256 9357105baaa1236cd89df0ecf1d606d9d58accf208b9017e214c73ca28325cf8. Immutable request C:\KenshiTestRuns\fp-combat\requests\20261005-2043-native-ranged-probe.txt. No game results present yet. Runtime logs/DLLs kept outside git.
2 Check coordination context and fp-combat/results during further work; use returned raw native state/animation/shoot evidence for safe readiness/reload ownership design.
3 Build continuous camera zoom while retaining direct controls and fallback toggle; account for collision, head/body visibility, UI/focus and rebasing.
4 Implement phase 1 ranged using native lifecycle, skill spread, ammo/XP/damage and actual first hit; no instant reload/state forcing. Get coordinator's STOBE truce accessor before initiating attacks.
5 Complete native/manual parity tests before phase 2 melee ready-action/animation-commitment/recovery investigation. Tests must fail on missing actual state evidence; no blanket bug-free claim.
