# FP combat context (merged, worked directly on main)

Updated 2026-10-06 (m48). fp-combat was merged into main (938d2e2); the branch/candidate/request workflow below the
merge is retired. One session does FP combat as coordinator + developer: it edits `/root/KenshiFP` and
`components/KenshiFP` directly, builds, installs, launches Kenshi (lock owner `fpcombat` while it holds the game) and
commits/pushes one fix per commit. The old "coordinator owns X / combat agent must not" rules are obsolete.
Order of work: camera/control (done), ranged and melee adapters in main, manual combat OFF by default; open rows in
`components/KenshiFP/docs/COMBAT_TEST_PLAN.md` (R10, 5090 R11 rerun pending (b10 invalid: raid; raid guard 16dc0b3, rerun fp-5090-11), R12 remainder, M08/M09, Gate 3, S01/S03/S05).


## 1. Source and build
- Source of truth: `components/KenshiFP/` on `main` (github.com/shaylanger/Kenshi-Stobe-Custom); live build tree WSL
  `/root/KenshiFP` (client dir kept identical: copy changed files, `diff -rq`; the six `kenshifp_client.c.bak_*` there don't matter).
- Build `cd /root/KenshiFP/re_plugin && bash build.sh`, offline tests `python3 tests/run_offline.py`, install
  `tools/automation/install-dll.ps1 KenshiFP` (Kenshi closed). Builds aren't byte-reproducible: compare source, not hashes.
- The live tree's own git (upstream `linguine2552/KenshiFP` v0.6.1) is not the history. Baseline tag `kfp-combat-baseline`;
  the old `fp-combat` branch/worktree `kfp-combat-wt` is merged (938d2e2) and no longer used.
- `KENSHIFP_DECOUPLING_REFACTOR_HANDOFF.md` is investigation only.

## 2. Shared interfaces (`client/kenshifp_client.c`, baseline line numbers; still binding)
| Area | Owner | Code | Rule |
|---|---|---|---|
| Actor selection | shared, frozen | `first_player_char(gw)` (1474; v1 = squad leader index 0); `g_player_pc` (1164, per-frame cache for hooks); `stobe_find_character_by_serial` (1949); `stobe_is_player_squad_char` (2823) | STOBE goals, voice and labels use these. Combat may add its own target/actor helpers but must not change the meaning of `first_player_char` or `g_player_pc`. Propose changes here first. |
| Frame update | combat may add calls | `hooked_mainloop` (8075): orig frame -> `poll_input` -> `fp_jump_pause_guard` -> `camera_lock` -> `fp_camera_override` (fallback) -> `fp_movement` -> interiors/floor/head -> `fp_gui_update` -> `stobe_goal_label_update`; `hooked_cam_update` (7235) is the real camera path | Add combat as its own `fp_combat_tick(gw, time)` call **after** `fp_movement`. Keep the existing call order. |
| Camera / controls | **combat agent** | `fp_camera_override` (4567), `hooked_cam_update` (7235), `vanilla_cam_handoff` (3796), `poll_input` (1536), `hooked_keypressed` (7992), `hooked_charmove_update` (8343), `hooked_face_direction` (8207), `hooked_sheathe` (8304), `kfp_locomotion.h` | Owned by combat. Keep the FP toggle and the harness `fp_*` command replies stable. |
| Ranged | **combat agent** | `fp_aim_point` (8147), `hooked_ranged_animupd` (8163), `hooked_gun_shoot` (8190), `kfp_meshray.h` | Owned by combat. |
| Melee | **combat agent** | new code | New file(s) `client/kfp_combat_*.inc` included next to `kfp_locomotion.h` (3332), so merges stay small. |
| STOBE communication | **coordinator**, frozen | Called from `camera_lock` (3150-3161): `stobe_voice_modifier_tick`, `stobe_unequip_request_tick`, `stobe_general_action_request_tick`, `stobe_fight_truce_tick` (2794: NPC truce/disengage after STOBE deals), `stobe_work_goal_tick`, `stobe_task_goal_tick`, `kah_bridge_tick`. Files in `RE_Kenshi\mods\Stobe\`: `stobe_action.req`, `stobe_work_goal.{req,status,control}`, `stobe_task_goal.{req,status,control}`, `stobe_goal_report.req`, `voice_action.flag`, `voice_command.flag`. Code: `stobe_work_planner.inc`, `stobe_task_goals.inc`, lines ~1650-3130 of the client. | Don't change these. Combat must not start fights against NPCs under an active STOBE truce. Check `stobe_fight_truce` state before forcing attack orders and ask the coordinator for an accessor if one is needed. |
| Hook install | shared | `install_hook` (8970), `hook_watchdog` (8113), `rva_sigs.h` | New hooks: add a signature in `rva_sigs.h` (signature scan, no fixed RVAs) and log install success/failure once. |

## 3. Installed builds (2026-10-06)
- KenshiFP `4FD22DEF` on both rigs (main ac56752: wound pick diagnostics on top of 39F58D2D manual melee adapter, spatial
  wounds), harness `2995EE5E`; 5090 also Stobe `DAF1390F`, ProfessionGear `BAFB8C31`.
- Harness notes: `rangedtest`/`rangedinfo` (KAH 26), `attack` gives crossbow users `RANGED_ATTACK_FOCUSED_UNPROVOKED`,
  `combatmode <npc> [block|ranged|taunt|hold|passive on|off]` (orders-panel stance; auto-home Shay has BLOCK=1 PASSIVE=1,
  which never swings). `drop <npc> <item> all` leaves one ground item per unit: `pickup` takes one per call (loop it).
- Fixtures: `kah-fpxbow` (Axima crossbow + hostile Skaera; preserved as fixture `C:\KenshiTestFixtures\FP-crossbow`), `kah-fpcam` (fresh auto-home copy), `kah-fullbase`
  (regression; `fullbase-guard.sh`). Never Shay's own saves.

## 4. Tests and results
- Plan: `components/KenshiFP/docs/COMBAT_TEST_PLAN.md`; master rows in `MASTER_TEST_PLAN.md`.
- Wrappers: `components/KenshiFP/tests/ingame/fp-manual-*.sh` (ranged, anatomy, limbs, melee skill/life, transitions,
  soak with native-AI control; RESULT lines). Offline: `python3 /root/KenshiFP/tests/run_offline.py`.
- Results: `C:\KenshiTestRuns\fp-combat\results\merged-1\RESULT.txt` (2026-10-05), 2026-10-06 batches 4080 b18-b21 and
  5090 `C:\KenshiTestRuns\fp-5090-*` (run log `archive/test-run-2026-10-05-m41.md`).
- Open admin: 4080 save copies `kah-fp-*` await deletion by Shay (permission checker); Full-Base hand-over/fetch regression
  row waits on Shay deleting the Avarek/Beaks Stobe DB rows (approved, permission checker blocked).
- Findings: CombatClass+0x290 pointer is always 0; use `target_h` (+0x298) / `focused_h` (+0x2C8). Spatial aim frame
  (B14-frame PASS on re-read; game units are decimetres): eye anchor = `where` y + 19 dm (1.9 m eye); the traced 17 dm
  column is the body capsule. Aim rays hit the target's handle (hits-2), so R08/R10 aren't blocked by the frame.
