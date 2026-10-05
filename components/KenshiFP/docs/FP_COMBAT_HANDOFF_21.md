# FP combat handoff 21 — full resume context
Updated 2026-10-05 21:36 UTC (15:36 user local). Paused at the user's explicit latest request to write all context and stop. This dedicated FP combat record does not replace the coordinator's normal handoff.

## Objective and latest instruction
The user authorized all implementation in an isolated clone/worktree while another agent extracts STOBE/standalone code and runs master tests. Implement camera/control, ranged phase 1, then melee phase 2 with automated test coverage. Earlier unrelated stop/checkpoint instructions were stale; do not apply them to a resumed implementation. The latest user explicitly requested this pause. A new user instruction to resume authorizes continuing.
Stop polling the coordinator once their requested information has arrived. Coordination/baseline context has arrived; actual P01 native ranged evidence has NOT arrived at the latest results-directory check (~21:31 UTC).

## Accepted design
1. Persistent FP-style WASD controls while wheel zooms continuously between eyes and third person; wheel no longer throttles run speed. Retain old toggle as native-control fallback.
2. Inspect/select another squad member's stats/inventory without transferring camera/movement; explicit control transfer.
3. RMB hold raises/ADS crossbow; LMB one legal shot; R or automatic native-duration visible reload. Preserve native skills/spread, ammo, damage/armour/XP. Actual first collision victim is injured, including an intervening NPC; spatial body part rather than weighted random reroll. Invisible skill-dependent spread calibrated against matched native torso accuracy/fire rate. High-skill limb aim is tactical, not automatic disarm/cripple.
4. Ready melee click initiates a native swing promptly, not a queue waiting for AI initiative. Native animation/state commitment and recovery gate actions. Spam cannot reset/accelerate. RMB legal responsive defence, WASD yields committed root motion. Optional <=0.20s buffer only in the tail of one's own recovery.
5. Automated mechanical and statistical tests using existing harness; keep visual/feel checks separate. Never call mocks native validation or promise a bug-free system.

## Ownership / safety boundaries
- Coordinator context: C:\KenshiModding\FP_COMBAT_COORDINATION_CONTEXT.md, m45. Read it fully on resume.
- Coordinator exclusively owns game launches/stops, installs, game.lock, live /root/KenshiFP, main branch, master/STOBE tests, fixture preparation and 4080. This agent has NOT run game commands, installed DLLs or changed those live resources.
- Edit/build/offline-test private combat worktree and mirror only. Package immutable candidate requests between master batches.
- Do not change shared first_player_char(gw), g_player_pc or STOBE actor resolvers. Source first_player_char actually returns selected squad member, fallback slot 0; old coordinator table leader comment is stale.
- New hooks must use unique executable signatures (rva_sigs/sigscan), never guessed fixed RVAs. Normal/unowned actors must pass through.
- Respect STOBE fight truce before initiating an attack. Draft native adapter currently lacks this gate: MUST fix before enabling/packaging manual combat. Request/read-only accessor integration according to coordinator contract; do not alter frozen STOBE functions.
- No new subagents were spawned during this work. Other existing machine/coordinator agents must not be interrupted to perform this handoff.
- Automatic approval review rejected a combined local-commit + GitHub push because external change-set destination authorization was not established. Local commits are allowed and continue. Do not retry/bypass push without explicit user authorization. Earlier probe commits were already pushed; camera and subsequent checkpoint are local only.

## Machine / repository
Remote Desktop Commander deviceId 39a13270-d7ef-4497-a1b1-feb6780cf90b, DESKTOP-JFLPK99 (5090). Windows shell is PowerShell; WSL distro DwemerAI4Skyrim3, root.
Worktree C:\KenshiModding\kfp-combat-wt, branch fp-combat. Repo shaylanger/Kenshi-Stobe-Custom. Baseline tag kfp-combat-baseline = 39e871bba819a3b00457747ba9e4e8855fd83838.
Source components/KenshiFP/client/kenshifp_client.c (~9800 lines), modular .inc files; build re_plugin/build.sh.
Private WSL mirror /root/kfp-combat. Staging /root/stobe-work/fp-combat-staging (Windows UNC \\wsl.localhost\DwemerAI4Skyrim3\root\stobe-work\fp-combat-staging).
Use Windows git -C C:\KenshiModding\kfp-combat-wt. WSL git cannot use the Windows-created worktree absolute .git pointer; do not rewrite it.
Commit identity shaylanger <shaylanger2@gmail.com>. Keep runtime DLL/logs out of git.
Remote tools are lazily discoverable via ALL_TOOLS filtered for remote_desktop_commander. start_process waits max 3s and reports Windows PID; poll read_process_output with bounded negative tail. read_file supports line ranges; write_file/edit_block for changes.
Windows rg and WSL rg unavailable here; Python/Select-String/Get-Content used. Avoid complex PowerShell/bash nested quoting: write Python scripts and execute their absolute WSL paths.
Scratch on current agent is NOT the Windows project. No Library/browser workflow is needed for these existing Git-backed files.

## Revisions / candidates
- 538851a6f8f605ffd7a2f80b124a03b5f36f35e3: passive native lifecycle probe/tests/docs, pushed.
- e7d71f7: earlier docs checkpoint, pushed.
- 77b9099227f71d1b8ad0ab37821505f7ef421fe3: camera/control and coordinator numeric scenario, LOCAL commit; push blocked by review.
- Final local checkpoint commit containing controller/native draft and this handoff is identifiable by git log -1 after this file was saved; avoid embedding a self-referential commit hash.
P01 candidate C:\KenshiTestRuns\fp-combat\candidates\538851a\KenshiFP.dll, SHA256 9357105baaa1236cd89df0ecf1d606d9d58accf208b9017e214c73ca28325cf8.
P01 immutable request C:\KenshiTestRuns\fp-combat\requests\20261005-2043-native-ranged-probe.txt.
Camera candidate C:\KenshiTestRuns\fp-combat\candidates\77b9099\KenshiFP.dll, SHA256 a57d12e79037f66d22838c696bbeb3c414023bff784bfac3c04384655a164674.
Camera request requests\20261005-2119-camera-control.txt; wrapper copied into candidate folder, so later worktree changes cannot alter it.
Results contract C:\KenshiTestRuns\fp-combat\results\<request-id>\RESULT.txt, run.txt, raw CSV/logs, restore.txt SHA-verified restoration. At latest check results folder still empty. User sent reminder request to coordinator.

## Completed camera/control source
client/kfp_control.inc: pin all five native handle IDs independently from inspection. Explicit F6 key_take_control transfer, fp_control state|take; refuses non-squad selection fallback. Missing actor releases instead of silently transferring. direct_default=1 enables once a valid squad world appears; explicit old toggle fallback stays off until toggled or new world.
fp_control_release_actor in main source clears own direct/facing/cache intent and stops only pinned actor's cached MOVE_DIRECTION vector/mode, preserving native combat modes. Physical WASD foreground-gated.
client/kfp_view.h/inc: 0..12m wheel zoom, frame-rate smoothing, eye threshold 0.65m, head/gear visible in third person. Five native terrain/building/static rays plus visual mesh refinement with 0.25m margin. Missing/faulting collision keeps camera at eyes. Preserve mesh perch cache and floating-origin pre-offset anchor.
camera_zoom=1 default: wheel distance only. camera_zoom=0 retains optional legacy throttle. Existing speed_scale remains 0.6; no default wheel speed changes.
fp_camera state|distance <0..12>|wheel <-2400..2400> reports actual Ogre derived-node distance, requested/applied distance, collision flags/speed. Actual read only while valid direct eye ownership. Explicit harness injection allowed background and uses same zoom math; physical focus handling remains separate test.
Shared selected actor cache/resolvers and STOBE ticks untouched; FP camera/movement/visibility/fall/aim hooks use private g_fp_control_actor.
tests/validate_camera_control.py coordinator-only numeric C00 subset: actual node distance vs applied, wheel/speed/actor, select actor-b while retaining actor-a, inv/stat query, explicit take, toggle fallback. Fixture awake distinct actors, unpaused, closed UI, open space. No installation/launch/movement/attack. Restores original toggle/distance; leaves actor-a selected/controlled, coordinator restores fixture. Physical WASD/UI/visual/moving-transfer/C05 are NOT validated by it.

## Completed probe / offline controller
client/kfp_combat_trace.h and kfp_combat_probe.inc: recording off by default, bounded 512 ring, 64-row pages, sequence/loss/capture-ID checks. fp_combat_probe begin|end|state|events [after_seq]|clear. Raw actor/RC/gun/target/state/mode/ammo/stat; native animation and shoot before/after callbacks. Observational, no grants or combat dispatch.
tests/capture_native_ranged.py is coordinator-only P01 wrapper using existing kah.py. Requires prepared sustained native crossbow fight. FP off/on cycles, setup metadata, frequent page drain, raw JSONL/CSVs; fail on missing animation/shots, real ammo decrement, insufficient reloads, loss/reset/gaps. Restores prior FP toggle. No load/equip/attack/heal/speed/install/launch. Protected target only for disclosed lifecycle capture, never damage/parity evidence.
client/kfp_combat_controller.h: portable native-gated action decisions, fire/reload edges, no deferred AI queue, interruption rearm, native reload requests, own-recovery buffer expiry/no refresh, commitment/block gating. Its shot/swing/block/reload counters count DECISIONS, not actual gameplay.
tests/test_combat_controller.c B10 passed plain GCC and UBSan. test_control_view.c B09 production control include + portable view passed plain/UBSan. test_combat_probe.c B07 passed plain/UBSan. test_native_trace.py eight decoder tests B08 passed.
tests/run_offline.py runs all three C tests + Python decoder, bounded timeout/CPU/output/core settings.

## Draft native ranged adapter — NOT READY FOR GAME ACCEPTANCE
client/kfp_combat_native.inc (235 lines), integrated into main source, PRIVATE BUILD ONLY, g_combat_enabled defaults OFF. Not packaged/installed/game-tested.
fp_combat on|off|state|physical|input <aim 0|1> <fire 0|1> <reload 0|1>. Injection feeds same controller; cannot override readiness. Current adapter RANGED ONLY; melee policy exists but has no native adapter.
KenshiLib exported setup/end/reloadCheck/resetShotTimer bindings, unique scans intercept native RC updateT/updateMT/end for only owned actor. Unowned and partially installed hook state pass through. Gun shoot hook suppresses autonomous owned shots unless explicit dispatch. Guarded main-loop native tick after movement; probes remain independent.
Draft calls native draw, gun createPhysical/setVisible/update, native reloadCheck once per owned game frame, animationUpdate non-null sentinel to aim/reload, measured native gun readiness/closeness and aimTimer, GunClass::shoot, native reset timer. No instant ammo refill or forced async loading counter.
Latest fix: explicit lower/release uses end trampoline directly, avoiding interception swallowing the adapter's own end call. Final private build/check status is recorded below once complete.
IMPORTANT remaining engineering before manual candidate:
- STOBE truce gate absent.
- Review hook/AI lifecycle conflicts, thread ownership/global crash guard, stale pointer/full-handle identity on reuse, missing/changed gun, hook installation order and native exports readiness.
- Existing sheathe suppressor only works if installed; verify install conditional because baseline KFP_MANUAL_AIM=0. Draft sets g_aim_mode but never enables old prototype.
- Verify dt vs game-speed scaling (dt*speed currently for own aim timer), pause/no overspeed/double native ticks.
- Improve LOWER while reload/UI interrupted: g_aim_mode/animation ownership must eventually lower after completion even if controller already cleared aimed.
- Native manual ammo/reload/readiness/XP not game-validated. GunClass::shoot receives NULL target; height/wall/power/hostility modifiers and actual collision attribution may differ from native targeted shooting.
- fp_aim_point is still OLD head + 80m look ray; no actual TPS camera-to-world/muzzle obstruction yet. ADS optics/FOV/alignment not implemented.
- Native mouse button dispatch not filtered; vanilla RMB orders/LMB interactions may conflict. Must integrate scoped mouse input ownership.
- No spatial body-part routing, actual animated-body collision refinement or balance calibrations.
- No native melee action integration or root-motion yield.
Do NOT describe this draft as completed ranged/melee implementation or enable it on user's save.

## Native analysis and exact findings
Read-only binary D:\Steam\steamapps\common\Kenshi\kenshi_x64.exe (36718592 bytes); x86_64-w64-mingw32-objdump available in WSL. capstone/pefile not installed; stdlib PE parsing used.
Analysis scripts and bounded assembly files in staging/native; staging scripts are NOT project artifacts or runtime commands.
Verified unique current exe signatures: native RC updateT=0x438c70, updateMT=0x43aee0, end=0x437470; gun shoot=0x43a730, animationUpdate=0x51e4e0, getGun=0x4345c0, GunClass reloadAmmo=0x436fb0.
GunClass::reloadAmmo immediately copies max loaded count into current ammo and updates meshes. It alone has no timer/inventory debit. Never enable old prototype instant reload.
Native RC reloadCheck at 0x437ce0: derives skill reload time, _isReloading +0x80, max/timer +0x74/+0x78, decrement by engine game-time global; updates reload pose/UI, debits correct inventory ammunition at completion, refill helper and native stat/DEX XP. This is correct adapter path to investigate.
Ranged animationUpdate clears gun readiness, drives reload/aim animation; null target lowers arms, non-null tested for presence, not dereferenced in this function. Existing prototype passed player as sentinel. readiness depends on real anim progress.
Gun shoot applies native skill+Perception spread once via Ogre randomDeviant and records actual projectile. NULL target skips target-height adjustment and intended target notification. Do not assume it proves parity.
Medical iShotYou at 0x439c90 passes CUT_PIERCED to MedicalSystem::addWound and retains native damage/hostility. Native addWound target=0x6508d0 (resolved internal JMP thunk 0x1dddb), weighted body-part selection inside function. Changing aim alone does NOT select spatial limb.
Gun spawn helper internal JMP thunk 0x39676 resolves 0x43a2f0; returns Harpoon*, potential narrowly scoped projectile tracking hook. Harpoon mesh node +0x58; tracer +0x68; native damage +0x4c; fields require further proof before use. No Harpoon definition found in SDK.
physHit definition IS in KenshiLib-src/Include/kenshi/CharMovement.h: size0x60, hit byte+7, position+8, normal+0x14, distance+0x20, shape+0x28, hand+0x30, group+0x50, unsafePtr+0x58; exported constructor/hitObjectUnsafePtr/Utility trace functions available.
KenshiLib.dll root game folder exports native RC lifecycle, getCombatClass, CombatClass changeState/setCombatState/initialiseBlock/setAttackTarget, AttackState initialiseAttack, physHit/trace and iShotYou. Enumerated exports via staging/export_contracts.py. Bindings are version-aware; game interception still unique-scan native target.
SDK located /root/KenshiLib-src/Include/kenshi. Address deltas vary; speculative SDK+offset dumps can land in other functions. Never use those guesses live. Use verified signatures, native thunk targets/callgraph/RTTI.
Last analysis staging/rtti_map.py parsed MSVC RTTI, found CombatClassAI vtable 0x16f67b8 and base0x16f6698. Entries point to JMP thunks, NOT function bodies. Next unwrap their E9 branches and disassemble real bodies:
AI slots 0x28->0xd4a9, 0x40->0xcc34, 0x48->0x2d44d, 0x50->0x2ee0b, 0x58->0x15875, 0x60->0x25ac7.
Base slots 0x28->0x109c9, 0x40->0xcc34, 0x48->0x45732, 0x50->0x2ca02, 0x58->0xd7a6, 0x60->0x16ee1.
AttackState vtable0x16b3bb8: validate thunk0x39202, initialise0xddf5, update0x29393, end0x479bf.
Combat SDK fields: active+0x130, isAttacking+0x140, inDeadTime+0x144, deadTimer+0x148, stateTimer+0x14c, technique+0x150, techniqueFinished+0x158, movement+0x170, me+0x188, combatState+0x1f0, nextMove+0x1f4, target+0x290/hand+0x298. Enum CHOP0/BLOCK1/REACTION_BLOCK2/STARTUP3/DECISION4/CIRCLE5/WAIT6/HESITATE7/STUMBLE8/FINISHED9/PATHSTART10/PATH11. Validate these native observations.

## Test/harness contract and commands
Harness repo C:\KenshiModding\Kenshi-Automation-Harness. Installed folder D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness, enabled.flag previously verified. Wrapper uses that installed folder, not repo root.
Reuse kah.py send(folder,cmd,args,timeout=5), transport flattens newlines into spaces; decoder handles it. Actors name or #serial/index; selected vs controlled must be distinct.
Generic shared harness extensions belong separate fp-combat-harness branch with coordinator review; plugin prefixed telemetry/input commands avoid shared ABI changes.
Fixtures auto-home awake Shay/Malzin disposable kah copy; FullBase/Squin other scenarios; never user save.
Build:
wsl.exe -d DwemerAI4Skyrim3 -u root -- rsync -a --delete /mnt/c/KenshiModding/kfp-combat-wt/components/KenshiFP/ /root/kfp-combat/
wsl.exe -d DwemerAI4Skyrim3 -u root -- bash /root/kfp-combat/re_plugin/build.sh
Offline:
wsl.exe -d DwemerAI4Skyrim3 -u root -- python3 /mnt/c/KenshiModding/kfp-combat-wt/components/KenshiFP/tests/run_offline.py --out /root/stobe-work/fp-combat-staging/<new-validation-dir>
NEVER run capture/validate_camera scripts yourself: coordinator owns runtime execution.
COMBAT_TEST_PLAN.md has B/C/R/M/S IDs, full camera/mechanics/parity/melee/regression matrix and explicit unvalidated gates. NATIVE_PROBE.md describes P01.
ASan earlier runaway DEADLYSIGNAL flooded remote terminal; other agent stopped ONLY isolated /root/kfp-combat/test_combat_probe and process absence confirmed. Root cause unresolved, ASan NOT passed. All offline runner subprocesses timeout20s, CPU15s, output file limit1MiB, core0; plain/UBSan only. Avoid unbounded commands/output.
Unsigned UNC PowerShell script blocked; no policy changed. Python staging packaging used. DLL build timestamps nondeterministic; source/text normalization vs CRLF verified before packaging.

## Resume order
1. Read this file, coordination context, COMBAT_TEST_PLAN.md, NATIVE_PROBE.md and repository CLAUDE/context/AGENTS instructions. Review git log/status/diff without reverting checkpoint work.
2. Check P01 results until actual evidence arrives. Once complete, consume raw state/ammo/reload observations and stop routine checking; no repeated requests for already delivered baseline.
3. Audit/fix native draft blockers above, complete actual-camera/muzzle aim, ADS, input consumption, truce and scoped native lifecycle; build/offline-test then immutable ranged request. Do not enable unsafe old KFP_MANUAL_AIM prototype.
4. Trace native projectile first-hit/spatial body-part routing; preserve native damage/armour/XP and downstream mod effects. Add animated/race/missing-limb/cover/crowd cases.
5. Implement native melee ready-start/commitment/defence/recovery and movement root-motion yield, using real native state calls and scoped AI ownership, not just a click queue.
6. Extend runnable mechanical/statistical test harness scenarios; matched native/manual accuracy/fire-rate/reload/limb-impact protocols, evidence gates and confidence intervals. Coordinator runs live cases; do independent work while waiting.
7. Keep this handoff and tests current, local commits per meaningful change. Push remains blocked until user explicitly authorizes. Final combined implementation cannot be claimed accepted until engine/game/balance/visual evidence supports it.

## Final stop verification
2026-10-05 ~21:37 UTC: bounded validation-stop completed exit0. Production-include/portable B07/B09/B10 plain GCC and UBSan PASS; eight Python native trace decoder tests PASS; isolated MinGW RE_Kenshi DLL build PASS and exported startPlugin verified. git diff --check PASS (CRLF normalization warnings only). No game test/install was performed. No manual-combat candidate packaged. Final source/docs saved as a LOCAL checkpoint commit; publishing remains blocked. No development child agents or test processes remain running; unrelated coordinator agents retain their own work.
