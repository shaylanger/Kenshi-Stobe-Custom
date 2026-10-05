# FP combat coordination context (coordinator <-> combat agent)

Written by the coordinator on 2026-10-05 (checkpoint m45). The coordinator keeps this file up to date when interfaces or test arrangements change.
This is not a handoff. The coordinator still owns its current work, every game launch, DLL installs, `/root/KenshiFP` and master testing.
The combat agent builds camera/control improvements first, then ranged combat, then melee combat, all in an isolated branch.

## 1. Baseline source
- **Baseline:** tag `kfp-combat-baseline` in `github.com/shaylanger/Kenshi-Stobe-Custom` (= this folder, `main`). The KenshiFP source is in `components/KenshiFP/`.
  - The coordinator checked it on 2026-10-05: `client/kenshifp_client.c`, `stobe_work_planner.inc`, `stobe_task_goals.inc` and `kfp_locomotion.h` are byte-identical to the live tree.
  - `diff -rq` shows only six `kenshifp_client.c.bak_*` files in live that aren't in the snapshot. They are old backups and don't matter.
  - The live tree's own git (`linguine2552/KenshiFP`, the upstream author, v0.6.1 `200102f`) has `kenshifp_client.c` and `build.sh` modified plus many untracked files. **Its git history is not the baseline. Don't commit or push there.**
  - A copy of the snapshot built cleanly (`re_plugin/build.sh`, MinGW).
    - The build isn't byte-reproducible because of timestamps: the snapshot build hashed `f5fb3623` and the installed build is `0349AA2A`. Compare source revisions, not DLL hashes.
- **Live source (coordinator only, don't edit):** WSL `DwemerAI4Skyrim3` `/root/KenshiFP`. Build with `cd /root/KenshiFP/re_plugin && bash build.sh`.
  - The coordinator installs from there with `tools/automation/install-dll.ps1 KenshiFP`.
- **Combat branch/worktree:** branch `fp-combat` (from the baseline tag), worktree `C:\KenshiModding\kfp-combat-wt`.
  - Edit `components/KenshiFP/` there. Commit and push only `fp-combat`, with one change per commit (what + why).
  - Commit identity: `shaylanger <shaylanger2@gmail.com>`. Check `git config user.email` first.
  - Build in WSL from a private copy: `rsync -a --delete /mnt/c/KenshiModding/kfp-combat-wt/components/KenshiFP/ /root/kfp-combat/ && cd /root/kfp-combat/re_plugin && bash build.sh`.
- **Taking in coordinator changes:** the coordinator syncs live into `components/KenshiFP` on `main` whenever it commits KenshiFP fixes.
  - Merge `main` into `fp-combat`. Don't cherry-pick live files by hand.
  - Before merging back, the coordinator does a three-way merge into `/root/KenshiFP` and runs the master regression rows.
- No decoupling/extraction branch exists yet. The Codex investigation `KENSHIFP_DECOUPLING_REFACTOR_HANDOFF.md` is investigation only. If that extraction starts, its branch gets listed here.

## 2. Ownership and interfaces (`client/kenshifp_client.c`, baseline line numbers)
| Area | Owner | Code | Rule |
|---|---|---|---|
| Actor selection | shared, frozen | `first_player_char(gw)` (1474; v1 = squad leader index 0); `g_player_pc` (1164, per-frame cache for hooks); `stobe_find_character_by_serial` (1949); `stobe_is_player_squad_char` (2823) | STOBE goals, voice and labels use these. Combat may add its own target/actor helpers but must not change the meaning of `first_player_char` or `g_player_pc`. Propose changes here first. |
| Frame update | combat may add calls | `hooked_mainloop` (8075): orig frame -> `poll_input` -> `fp_jump_pause_guard` -> `camera_lock` -> `fp_camera_override` (fallback) -> `fp_movement` -> interiors/floor/head -> `fp_gui_update` -> `stobe_goal_label_update`; `hooked_cam_update` (7235) is the real camera path | Add combat as its own `fp_combat_tick(gw, time)` call **after** `fp_movement`. Keep the existing call order. |
| Camera / controls | **combat agent** | `fp_camera_override` (4567), `hooked_cam_update` (7235), `vanilla_cam_handoff` (3796), `poll_input` (1536), `hooked_keypressed` (7992), `hooked_charmove_update` (8343), `hooked_face_direction` (8207), `hooked_sheathe` (8304), `kfp_locomotion.h` | Owned by combat. Keep the FP toggle and the harness `fp_*` command replies stable. |
| Ranged | **combat agent** | `fp_aim_point` (8147), `hooked_ranged_animupd` (8163), `hooked_gun_shoot` (8190), `kfp_meshray.h` | Owned by combat. |
| Melee | **combat agent** | new code | New file(s) `client/kfp_combat_*.inc` included next to `kfp_locomotion.h` (3332), so merges stay small. |
| STOBE communication | **coordinator**, frozen | Called from `camera_lock` (3150-3161): `stobe_voice_modifier_tick`, `stobe_unequip_request_tick`, `stobe_general_action_request_tick`, `stobe_fight_truce_tick` (2794: NPC truce/disengage after STOBE deals), `stobe_work_goal_tick`, `stobe_task_goal_tick`, `kah_bridge_tick`. Files in `RE_Kenshi\mods\Stobe\`: `stobe_action.req`, `stobe_work_goal.{req,status,control}`, `stobe_task_goal.{req,status,control}`, `stobe_goal_report.req`, `voice_action.flag`, `voice_command.flag`. Code: `stobe_work_planner.inc`, `stobe_task_goals.inc`, lines ~1650-3130 of the client. | Don't change these. Combat must not start fights against NPCs under an active STOBE truce. Check `stobe_fight_truce` state before forcing attack orders and ask the coordinator for an accessor if one is needed. |
| Hook install | shared | `install_hook` (8970), `hook_watchdog` (8113), `rva_sigs.h` | New hooks: add a signature in `rva_sigs.h` (signature scan, no fixed RVAs) and log install success/failure once. |

## 3. Harness and installed builds (5090, 2026-10-05, updated m46)
- Harness repo `C:\KenshiModding\Kenshi-Automation-Harness`, HEAD `93d03e3`; installed `AutomationHarness.dll` `B847ACF6` (built from 93d03e3).
  - m46 additions: `give` searches CROSSBOW + exact names first (71b475c; the game's item factory still refuses to create crossbows),
    `rangedtest` (KAH 26: per-shot acc01/spread/hits, `loaded=n/max`, `reloads=`), `rangedinfo <npc>` (bow, has_ammo, loaded, ammo type,
    ranged mode/state), `attack` gives crossbow users `RANGED_ATTACK_FOCUSED_UNPROVOKED` (93d03e3).
  - Crossbow fight recipe (proven m46, auto-home): spawn + `recruit` a "Mercenary Crossbowman", `select`/`protect` him, `pin` a Hungry
    Bandit target ~30 m off, `order <shooter> RANGED_ATTACK_FOCUSED_UNPROVOKED target <t>` (or `rangedtest <shooter> <t> shots N attack`).
    Pin/protect don't survive a reload. Kenshi doesn't consume the inventory bolt stack: ammo evidence is the gun's loaded count.
  - KenshiFP registers `fp_mode`, `fp_click`, `fp_putdown` and `fp_state` through `KenshiAutomationHarness.h` (3665).
  - Stat names the harness knows: see `kStatNames` in `src/Commands.cpp` (`friendly_fire`/`precision_shooting`, not `precisionfriendlyfire`).
- Installed SHA256 (first 8 hex digits), 5090: KenshiFP `0349AA2A` (main, Vortex folder `...\Vortex\kenshi\mods\KenshiFP RE V0.6.1 ...\KenshiFP\KenshiFP.dll`),
  Stobe `DAF1390F` (NPC-panel session candidate; `2A3FC123` is the last coordinator build), AutomationHarness `B847ACF6`, ProfessionGear `2E533D44`; PG config Normal/Normal.
- Results so far: `results/20261005-2043-native-ranged-probe/` P01 PASS (FP off 10 shots/9 ammo increases, FP on 4/4); the wrapper's
  `precisionfriendlyfire` stat name had to be patched to `friendly_fire` for the run (see its run.txt): fix it in the wrapper.
- **Harness additions:** general test commands (aim, attack, combat state, camera readouts) go into the harness repo as **separate commits** on a branch `fp-combat-harness`, one command per commit with a `docs/COMMANDS.md` row and an offline test (`tests\run_tests.bat`).
  - The coordinator reviews and merges them into the harness `main` and installs them at a batch boundary. Two harness DLLs are never installed at the same time.
  - KenshiFP-only commands go in KenshiFP itself (`kah_bridge_tick`).
- **Fixtures** (`C:\KenshiTestFixtures\FIXTURES.md`; always test on `kah-*` copies via `C:\KenshiTestRuns\scenarios\relaunch.ps1`):
  - `auto-home` (Shay/Malzin; `scenarios.sh fresh|duel|gang|surrender`: the main combat bed)
  - `Testing-Save-Full-Base` (Beaks/Avarek, raids: run `fullbase-guard.sh`)
  - `Testing-Save-Squin` (Beak/Kint)
  - Never use Shay's own saves.

## 4. Candidate builds, test requests and results
Root: `C:\KenshiTestRuns\fp-combat\` (WSL `/mnt/c/KenshiTestRuns/fp-combat/`).
- **Candidate:** `candidates/<fp-combat commit short>/KenshiFP.dll` plus `MANIFEST.txt` containing `commit=`, `sha256=`, `built=<time>`, `base=<main commit merged in>` and `ini=` (any `KenshiFP.ini` keys the test needs).
- **Request:** `requests/<YYYYMMDD-HHMM>-<slug>.txt`. One request per file, written once and never edited (to change one, write a new request). Fields:
  - `candidate=<dir>`
  - `fixture=<name>`
  - `tests=<one per line: harness scenario path under the combat worktree, or a wrapper command>`
  - `pass=<what real game state proves it>`
  - `config=<ini/test switches>`
  - `priority=`
  - Scenario files must end with the one-line `RESULT <row> PASS|FAIL <evidence>` (see `testing/README.md`, `verdict()` in `tests/ingame/stobe/stobe-fight-lib.sh`).
- **Results (written by the coordinator):** `results/<request id>/`:
  - `RESULT.txt`, one line per test
  - `run.txt` with the candidate commit and hash as installed, harness/Stobe/PG hashes, fixture, ini, and start/end time
  - scenario outputs and CSVs
  - logs: KenshiFP.log, harness.log, crash dump if any
  - `restore.txt` showing that main KenshiFP `0349AA2A` (or the current main hash) was reinstalled and the SHA was verified
- **Scheduling:** the coordinator runs candidate requests between master batches, never in the middle of one, and batches several requests into one launch where it can.
  - Sequence: Kenshi closed -> install candidate (SHA check) -> run -> close -> reinstall main KenshiFP -> verify SHA -> resume master tests.
  - A candidate that crashes the game or breaks a STOBE/master row is logged in `results/` and isn't retried until a new commit fixes it.
- **The combat agent must not** launch Kenshi, install DLLs, take `C:\KenshiTestRuns\game.lock`, edit `/root/KenshiFP`, `main`, MASTER_TEST_PLAN.md or the STOBE plans, or use the 4080 rig.
- **Contact:** use cross-session messages to the coordinator for interface changes or urgent requests. Otherwise the request files are the channel.
