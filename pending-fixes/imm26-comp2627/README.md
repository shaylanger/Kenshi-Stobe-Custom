# NC2627 = ONE composed native build: NC25 + NC27 (Hunt timeout) + NC26 (10-f option A durable item id) - OFFLINE, NOT installed

## Lineage (verified)
Latest native chain: NC3 ... NC24 (25-b mine fix) -> NC25 (22-b travel_terminal push + 23-b FOLLOW expiry; DLL CD455D58, on the 4080 lanes). NC26 (durableA1, b32e0f9f) and NC27 (huntA1/huntA2, 06dd6723 / 3950a6b4 / e5584c6d) were BOTH built on NC25 in parallel, so neither contains the other. NC2627 contains every earlier patch (NC3..NC25) plus both. No whole-file copies: the compose is the three anchor-asserting edit scripts applied to the NC25 tree.
Overlap check: NC27 edits only Activity*.cpp/.h (ActivityController, ActivityDanger, ActivityGoals, ActivityRuntimeBindings, ActivityTransport, new header-only ActivityEndingSpeech.h); NC26 edits main.cpp + CMakeLists.txt and adds StobeDurableItem.{h,cpp}. Disjoint: composed `src/main.cpp` is byte-identical to the NC26 tree's, and the 9 Activity* files plus ActivityEndingSpeech.h are byte-identical to the NC27 tree's.

## Result
- Source tree: `C:\KenshiTestRuns\imm26-nc2627` (= `bash compose-native.sh`: NC25 tree + nc27a_edit.py + nc27b_edit.py + nc26_edit.py; script diffs its output against this tree: identical).
- Build: `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc2627 -Out C:\KenshiTestRuns\imm26-nc2627-b -Guard DURABLE_ITEM,travel_terminal,FOLLOW_DIAG,ACTIVITY_PROGRESS_DIAG,ACTIVITY_GIVEUP_SPEECH` -> `BUILD OK (objects=70)`.
- **DLL: `C:\KenshiModding\pending-fixes\imm26-comp2627\Stobe.dll` (git-ignored; same bytes as `C:\KenshiTestRuns\imm26-nc2627-b\out\Stobe.dll`), SHA256 `AB082050CD3D83840AFA2824F7739ABAC6018564628ABF76A3F815D4DD8420DA`.**
- Patch list (apply order): nc27a_edit.py (Hunt progress-by-damage), nc27b_edit.py (give-up speech request after an accepted failed report), imm26-durableA/nc26_edit.py (durable item id hooks + transfer evidence field). Underneath: NC25 = NC24 + nc25a + nc25b etc. (full chain in `pending-fixes/npc-immersion-26/NC*/README.md`).

## Offline proof (all run 2026-10-16, WSL)
- `bash pending-fixes/imm26-comp2627/compose-native.sh` -> `RESULT comp2627-native PASS` (edits apply, identical to built tree, hunt_progress / native_travel_terminal_push / follow_expiry source tests pass on the composed src, 3 DurableItem::Reset calls).
- `imm26-durableA/offline-tests.sh` -> `RESULT durableA-offline PASS`; `NC27/offline-tests.sh` -> `RESULT nc27-offline PASS` (+ mutation fails as it should); `NC25/offline-tests.sh` -> `RESULT nc25-offline PASS`.
- `bash pending-fixes/imm26-comp2627/server-compose.sh` -> `RESULT comp2627-server PASS`: durable native 19/19, durable B 18/18, huntA timeout 5/5 (incl. expiresAt 43200), huntA giveup 16/16, wpE situated 35/35, wpE activity kinds 51/51, wpR1 resume 42/42, php -l clean.
- Not provable offline: that the DLL loads and the hooks behave in game (live recipes below).

## Server apply (matching combination)
The DLL's wire contract needs BOTH server patches (the DLL emits `durable_item_id`; failed reports need the `ending=failed` event):
1. base = the imm26 compose tree (scratch default `/root/imm26/huntA-tree` = compose + huntA).
2. `python3 pending-fixes/imm26-durableA/apply.py <tree> --with-b` (NC26 option A on top of option B; refuses without B).
3. `python3 pending-fixes/imm26-huntA/apply.py <tree>` (idempotent; expiresAt now+43200 for ALL activity kinds, noProgressTimeout 10000, ending=failed event).
`bash pending-fixes/imm26-comp2627/server-compose.sh [base] [dest]` does 1-3 on a scratch copy (`/root/imm26/comp2627-server`) and runs the 7 tests. NOT deployed anywhere. Deploy to a lane's private backend = a separate step (copy the three changed lib files + `social_event_contract.php` + `activity.php`; php -l; tests under flock). The DLL is safe without the server patches only in the sense that unknown fields/events are ignored, but then option A and the give-up line do nothing.

## Install per lane (nothing installed by this WP; Kenshi of that lane must be closed)
Never the Steam/live install: `tools\automation\install-dll.ps1 Stobe` copies `C:\StobeBuild\out\Stobe.dll` to Shay's Steam install, so do NOT use it for this candidate unless Shay orders the live install (then first `build-stobe.ps1` default mode on the composed source).
- 4080 lanes i3/i4 (the proven path): stage the DLL at `C:\KenshiTestRuns\staged\Stobe-NC2627-AB082050.dll` on the 4080, then run a copy of `pending-fixes\4080-nc-install-20261015\install-stobe-4080-nc.ps1` with `$NewSha='AB082050CD3D83840AFA2824F7739ABAC6018564628ABF76A3F815D4DD8420DA'`, `$OldSha` = the lane's current SHA (NC25 = `CD455D583F662347B8251424F1B97B03D5110DFDEA83C0320AB8411C49F103F3`), `-CandidatePath` the staged file: `-Action Plan`, `SelfTest`, `Apply -Instance 3|4`, `Rollback` if needed (script is pinned to the NC SHA, so the copy needs those two constants and the receipt name changed).
- 5090 lanes: copy to `D:\KenshiInst\<n>\mods\Stobe\Stobe.dll` of the isolated lane (instance marker, game closed, link count 1; `stage-stobe-candidate.ps1` rules), then `lane-install.ps1 -Lane i4|i5 -FromLane i3` replicates i3's build to the others. 5090 lanes are parked (no new 5090 sessions) until Shay says otherwise.

## Live-proof recipes (not run)
1. NC26 option A (4080, kah-* copy, private backend with step 2 above, two save/load cycles): follow `pending-fixes/imm26-durableA/README.md` section "LIVE PROOF RECIPE" steps 1-8 unchanged (theft stamps `DURABLE_ITEM: stamped`, save, load x2 shows `DURABLE_ITEM: restored` with the same id, return carries the same `durable_item_id`, repair state credits `hand_<serial1>` via `return_item_key hand_<serial3>`, negatives a/b/c, old-save load check). Expected extra: the DLL is NC2627 so Hunt rows are not exercised there.
2. Hunt timeout (NC27 section "Live-test recipe" steps 1-4 in `pending-fixes/npc-immersion-26/NC27/README.md`): (1) walk > 5 min to the area with no failure during the walk; (2) armed NPC fighting > 5 min: `ACTIVITY_PROGRESS_DIAG reset=target_damage` ~ every 30 game-s, no timeout; (3) unarmed NPC in the area: after ~10000 game-s `ACTIVITY_END_DIAG ... reason=activity_no_verified_progress`, `ACTIVITY_GIVEUP_SPEECH: dispatched id=<agreement>` within ~2 s and an in-character give-up-and-why line, eventlog `situated_event` with `"ending":"failed"`; (4) normal kill: no give-up line. Needs the server patch step 3.
3. Regression smoke on the composed DLL before either proof: log shows `DURABLE_ITEM: hooked|install`, rows 22-b (`CONTEXT_PUSH ... reason=travel_terminal`) and 23-b (`FOLLOW_DIAG`) as in NC25 README.

## Known gaps / notes
- Server `expiresAt` 43200 applies to every activity kind (told to the coordinator by huntA2).
- NC27 known gap: a failed report is only sent once cleanupComplete (stuck-melee case never reports).
- NC26 limits (ground items, split stacks, stackables unproven) as in the durableA README.
