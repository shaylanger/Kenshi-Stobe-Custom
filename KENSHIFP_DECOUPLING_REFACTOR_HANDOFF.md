# KenshiFP decoupling: investigation and implementation handoff

Date: 2026-10-03 (user local time). Author: Codex.
Status: DONE (2026-10-06, m49): goal/action logic moved into Stobe (9d99f36), removed from KenshiFP (f94b1d5); Stobe 7A8997FD +
KenshiFP FE26573F installed on the 5090; DC1-DC7 PASS (DC1-DC5 with the KenshiFP DLL absent), evidence `archive/test-run-2026-10-06-m49.md`.
Original status (below kept as history): investigation only; no source/runtime changes, builds, installs, game commands or test-plan edits.
Requested deliverable: move non-FP features out of KenshiFP; leave KenshiFP responsible only for FP-mode behavior.
User clarification: existing goals are disposable test data. No migration of current goal state is required.
Do not infer permission to delete other data, profiles, memories or saves.

## Executive assessment

Feasible, but this is extraction of a native runtime subsystem, not a file move.
Preferred end state: gameplay goals/actions and related UI inside modular Stobe code; KenshiFP retains camera, FP input/cursor behavior, FP targeting and FP harness commands.
A separate native executor DLL is a fallback if preserving the MinGW C implementation materially reduces risk. It is not yet proven necessary.

Initial estimate after deeper inspection: 5-9 focused development days including game validation, with low confidence until the compiler/fault-guard spike passes. Approximately 0.5-1.5 days for the isolated spike/dependency inventory, 2-4 days extraction/integration, 1-2 days callers/build cleanup, 1-2 days gameplay regression. These overlap and are planning estimates, not measured work.
Discarding old goals removes data-migration work, not correctness testing for future goal persistence.

Development can remain separate from the ongoing test setup. Deployment cannot be promised to have zero effect: matching DLLs must be installed at a coordinated restart and affected tests rerun. No installed DLL changes during a batch.

## Environment and source of truth

5090 device: DESKTOP-JFLPK99, Desktop Commander deviceId 39a13270-d7ef-4497-a1b1-feb6780cf90b.
4080: DESKTOP-NQQPA73; not the refactor target.
Workspace: C:\KenshiModding.
WSL distribution: DwemerAI4Skyrim3.
Live native sources: /root/KenshiFP and /root/STOBE-src.
Server: /var/www/html/StobeServer; merge copy /root/stobe-work/ss-merge.
Workspace components/KenshiFP and components/STOBE are snapshots, not authoritative live build sources.
Stobe Windows build: C:\StobeBuild; extracted v100 tools: C:\StobeBuildTools.
Read CLAUDE.md and testing/HANDOFF.md for CURRENT state before acting; the active coordinator owns tests.
Read /root/STOBE-src/AGENTS.md and mod/docs/Stobe/{AGENTS.md,agent-guide.md,building.md}.
Read server instructions before server edits. Read harness AGENTS.md if changing harness code.

Observed revisions (moving targets):
- C:\KenshiModding HEAD 7f5fcb2.
- /root/STOBE-src HEAD dedc49d.
- /root/KenshiFP has modified kenshifp_client.c, build.sh and numerous untracked goal/include files.
Do not reset, checkout over, or copy snapshots onto these trees.

Observed SHA256:
- client/kenshifp_client.c ffdae92d36e320545abf9981a3351e9432e4cb195d485c67490c4350b0d4a1ad
- client/stobe_work_planner.inc ae8964e7b691eddc46b1a603afffe35ba08a3dd9b30cf99b40373a80882c4319
- client/stobe_task_goals.inc be7eac92dd1daa4ea2c1975bd0464571d4ad3cbe0d7b123ff734fc88660f0127
Recheck on pickup. Preserve a complete baseline including untracked files in the isolated development tree.

## Findings grounded in live source

Line numbers below are approximate and will shift.

### 1. Update loop is tied to the camera

KenshiFP client/kenshifp_client.c:
- 3037-3038 directly includes work planner then task goals.
- camera_lock(), about 3150, runs voice modifiers, unequip requests, general action requests, fight truce, work goals, task goals and the harness bridge BEFORE its g_fp_mode branch.
- camera_lock() first validates the camera pointer. Therefore even non-FP runtime processing currently depends on a readable camera.
- about 8084 calls camera_lock every frame; about 8094 updates goal UI.
This logic is already used outside FP mode but depends on the KenshiFP DLL.

Stobe src/main.cpp:
- Hook_PlayerUpdateTick already has a GameWorld/worldFrameStable gate.
- around 14753 updates world state/autonomy; around 14794 runs ProcessMessageQueue, ExecuteQueuedActions, UpdateMoveToActions, ApplyFollowTargets and ApplyTravelTargets.
This is a plausible destination, not a proven insertion point. Establish order and world-load behavior before integrating.

### 2. Work/task planners form one coupled engine

Active work planner: 1,532 lines. Active task goals: 2,236 lines.
Other files exist: stobe_goal_engine.inc 468 lines and stobe_task_goals_stage.inc 1,126 lines. The inspected main client includes only the active work/task files. Determine other references before deleting older files.

Work planner relies on task-goal meal handling, input feeding and purchase fallback:
sgm_meal_tick, wgp_feed_inputs, stg_request_purchase_fallback.
Task goals rely on work-planner structures/helpers, clocks, reporting, inventory/scanning and native order routines.
Do not move only one include and assume independent modules.

Shared requirements include:
- character serial/handle lookup, squad membership and position;
- native strings, GameData lookup and item matching;
- inventory scans and ownership/transfer semantics;
- building scans and production/crafting queues;
- orders, rethink, movement and combat/KO checks;
- native exports and hard-coded offsets;
- game clock/world timestamp;
- mod paths and request/control/status/TSV files;
- completion reports, initiative, hunger/meal pause and return behavior;
- memory readability and fault containment.

Goal clock uses real elapsed time multiplied by GameWorld frameSpeedMult; dt capped at 2 seconds; both goal ticks call the update helper. Preserve speed/pause semantics and measure load-transition accounting rather than silently changing it.
World timestamps use getTimeStamp_inGameHours with a hidden return pointer. Preserve the actual calling convention.

### 3. GUI extraction is substantive

Goal panel lives inside task goals, approximately 1880-2057.
It uses first_player_char, settings_find, native MyGUI strings, widget creation/caption helpers and shared GUI export pointers.
It finds JobsPanel and TimeMoneyPanel, avoids overlap, follows HUD visibility and shows the selected squad character's goals.
Native widget offsets are used to accumulate screen coordinates.
Do not replace selected-character lookup with squad leader lookup.
Suggested destination: StobeGoalPanel.cpp with engine-produced view data, separate from planner decisions.
Unproven: safe reuse of Stobe's existing MyGUI wrappers, widget destruction/load lifecycle, UI scaling behavior. Validate explicitly.

### 4. BODYGUARD has important behavior beyond issuing an order

General action handler around 2915:
BODYGUARD/GUARD_TARGET map to task 45.
Patrol/hold/move/bodyguard cancel standing task goals and clear current orders.
Squad-to-squad BODYGUARD uses FOLLOW_PLAYER_ORDER instead because NPC-style BODYGUARD was ignored by squad AI (bug 86).
Task goals also issue guard orders.
Preserve both paths and their cancellation ordering.

### 5. GIVE_ITEM is not all in KenshiFP

Stobe Functions.cpp around 8646 already executes ACT_GIVE_ITEM; main.cpp around 11357 parses and queues GIVE_ITEM.
Task goals separately contain inventory transfer/handover behavior for fetch/buy/return flows.
No literal GIVE_ITEM match was found in the inspected KenshiFP main client.
Do not blindly replace Stobe's existing executor. Trace immediate dialogue transfer versus goal delivery, and consolidate only when their quantity, ownership, distance and failure semantics are equivalent.
Determine precisely which path the user meant; the architecture goal can be met without rewriting the working immediate executor.

### 6. Protocol boundary is already file based

Server lib/work_goal_functions.php writes stobe_work_goal.request.
lib/task_goal_functions.php writes stobe_task_goal.request and reads stobe_task_goal.status.
lib/chat_helper_functions.php and lib/negotiation_engine.php write stobe_action.request.
chat_helper_functions.php writes unequip_item.request.
Paths are currently rooted in /mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe.
Native planners use the Stobe mod directory for request/control/status and TSV files.
Preserve filenames and field/state meanings during initial extraction to reduce caller changes.
Audit ALL producers/consumers later, including harness, shell tools, test wrappers, documentation and alternate server copy. The search performed here was targeted, not exhaustive.
Do not clear current files while an existing test is using them. A clean refactor fixture can start with disposable goals.

### 7. Additional non-FP bridge must be included

KenshiFP stobe_lifelike_signal_tick (~1724) reads Stobe.dll at fixed RVAs:
InterruptTtsPlayback, BeginChatInterruptGeneration and a bored/initiative global.
It checks a few prologue bytes before internal calls/writes.
stobe_set_voice_range_lock (~1672) similarly accesses Stobe proximity globals by RVA.
A Stobe rebuild can change these addresses, disabling or misdirecting behavior.
This is a CUTOVER BLOCKER even if goals compile cleanly.

Move generic interrupt/initiative processing into Stobe using direct internal APIs. Trace Stobe's existing UpdateLifelikeInitiativeFlag before adding a second consumer.
For FP-specific target locking, retain only the FP trigger in KenshiFP; use a versioned POD/C exported API or explicit file protocol to ask Stobe, not DLL offsets.
Generic U/voice modifier behavior needs ownership review: distinguish FP-only targeting from voice/chat features usable in normal view.
Do not leave non-FP voice/initiative behavior dependent on KenshiFP to claim completion.

### 8. Compiler/fault guard is the largest unproven technical risk

KenshiFP re_plugin/build.sh compiles kenshifp_client.c using x86_64-w64-mingw32-gcc as C, with dynamic KenshiLib export resolution.
Stobe build_portable.bat compiles a fixed list of .cpp files with VS2010 x64, /MD /GL /EHa, and links /LTCG to KenshiLib/MyGUI/Ogre.
The Stobe ABI must stay v100.

KenshiFP guard_arm (~1197) zeros the first qword of jmp_buf to bypass MinGW/MSVCRT unwind behavior. It tracks the arming thread so background-save exceptions do not longjmp to the game thread.
DO NOT port that jmp_buf layout hack to v100.
Use a dedicated v100-compatible fault boundary, preserving thread filtering and avoiding unsafe unwinding across C++ objects/locks. A compile pass alone proves nothing about exception behavior.
If retaining C in a separate MinGW DLL, keep all C++ ownership/containers on the v100 side and cross only a versioned C/POD boundary. Never exchange std::string, MyGUI objects by value, STL containers or allocator-owned memory across CRTs.

### 9. Build plumbing must change

tools/automation/build-stobe.ps1 copies ONLY .cpp and .h from live src to C:\StobeBuild\src.
It does not copy .inc files and does not remove stale destination sources.
build_portable.bat has an explicit SOURCES list.
New modules require build list updates; includes must be copied explicitly or converted to .cpp/.h.
Check CMake/project/other supported build routes and build-support snapshots too.
Never run the existing script as an isolated-build test: it writes the shared build/output directory used by the coordinator.
install-dll.ps1 uses fixed Stobe and Vortex KenshiFP destinations. A new DLL would require deliberate installer/package/loader support.

### 10. FP harness ownership is already clear

KenshiFP kah_bridge_tick registers fp_mode, fp_click, fp_putdown and fp_state.
These belong in KenshiFP. Generic goal/action controls belong in Stobe's bridge or the general harness, not this FP bridge.
Retain FP commands and test selection/click/putdown behavior after cleanup.

## Recommended module boundaries (proposed, not implemented)

- StobeNativeActions: native compatibility, lookup, orders, movement, equip/unequip, safety boundaries.
- StobeGoalRuntime: clocks, lifecycle/reset, file protocol and one owner.
- StobeWorkPlanner: finite production planning.
- StobeTaskGoals: fetch/buy/guard/stock/repair/etc., with explicit shared services.
- StobeGoalPanel: selected-character view/UI.
- Stobe initiative/interrupt/voice services: existing functions where possible.
- KenshiFP: camera/head/mouse/cursor, FP interaction and FP harness; only a stable bridge for unavoidable FP-specific Stobe requests.

Names are suggestions. First preserve behavior; avoid combining extraction with planner redesign.

## Next agent: exact starting sequence

1. Re-read current handoff, git status/logs and live files; determine who owns the active test/build outputs.
2. Work in a distinct source/build location. Include current untracked sources; a plain git worktree is insufficient for /root/KenshiFP.
3. Produce a complete dependency map and protocol producer/consumer inventory. Compare live versus snapshots without overwriting either.
4. Run an isolated v100 spike for a minimal native helper and planner subset. Resolve C-to-C++ conversions, bool widths, function pointer signatures, aggregate structs and fault guard first.
5. Prototype stable Stobe bridge replacing fixed RVAs BEFORE any deployment of a rebuilt Stobe.
6. Extract work/task engine together and create an explicit engine/UI reset on world changes. Keep generic gameplay mutation on game thread.
7. Route through stable-world update loop; establish action/goal/autonomy ordering. Detect competing ownership of actor orders.
8. Build both candidates to separate output folders. Add startup diagnostics identifying executor owner and protocol version.
9. Coordinate one cutover restart. Exactly one executor and one UI owner; do not dual-consume file requests.
10. Validate on fixture copies with KenshiFP absent, then with cleaned KenshiFP enabled.
11. Update callers, scripts, packaging and docs; remove old includes/functions only after replacement passes. Search for remaining fixed Stobe RVAs and non-FP dependencies.
12. Refresh component snapshots and commit focused changes according to current repo instructions. Do not commit DLLs/logs/runtime data.

## Regression gates

Use existing tests and real inventory/order/status changes, not just dialogue text:
- production single/multiple output, dependencies, already-carried inputs, no power, queue growth, purchase fallback and approval;
- fetch from storage/ground, buy from named trader, delivery to a person, partial stack/quantity, full inventory and failure rollback;
- immediate GIVE_ITEM and goal handover separately;
- guard squad member versus NPC, replacement/cancel, patrol/hold/rescue/repair;
- hunger meal pause/resume, combat/KO interruption and delayed completion report/return;
- paused and accelerated game, load/reload and older-save pruning using NEW goals;
- selected-character panel, changing selection, hidden HUD/map/menus, scaling and relaunch;
- initiative and danger preemption, TTS/chat cancellation, FP voice targeting without fixed RVAs;
- no KenshiFP installed: generic goals/actions/UI still work;
- KenshiFP installed: FP camera/cursor/click/putdown and existing harness commands still work;
- no duplicate inventory/money/order side effects;
- frame-time comparison on the same 5090 fixture/scene; do not compare against 4080.
Map current test IDs from the current plan, since IDs/status changed during investigation.

## Remaining unknowns / limits

No implementation, compiler spike, candidate build, DLL load or in-game regression was performed.
No zero-risk claim is justified.
Complete helper graph, all callers and exact load-reset behavior remain unproven.
Fault-boundary correctness and GUI ABI/lifetime are the first technical gates.
Stable bridge exports and RE_Kenshi load order need design/verification.
Existing Stobe autonomy/order conflicts require inspection.
Hard-coded native object offsets remain even after removing inter-DLL RVAs; moving code does not make the game ABI version-independent.
Active test/build state must be checked on pickup; handoffs and source revisions were changing.
This investigation did not take the coordinator lock or interrupt its test batch.
