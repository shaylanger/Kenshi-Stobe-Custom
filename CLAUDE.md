# Kenshi modding workspace (Shay)

STOBE / KenshiFP work: notes, test plan, patch scripts, tools, source snapshots.

## Current state (2026-10-01 night, after run 8 + round 19h) — start here
- **Run 8** (`test-run-2026-10-01-r8.md`): bugs 92, 93 found, 74 reopened, 84 passed; fixes installed. Its "Retest next run" list comes first. **Next bug is 102.** The test inbox speaker is the *selected* character: keep Shay selected.
- **Installed:** Stobe.dll `261C7AF3…`, KenshiFP.dll `0193CD57…` (all fixes through bug 93; prev `BC284585`); server through round 19g (live + ss-merge, pushed). stobe-tests baseline: 51 pass / 7 known / 1 pre-existing fail (`negotiation_engine` "unpaid -> BREACHED_PLAYER", fails on pre-r19 code too: not ours, investigate some day).
- **Next job:** test plan section "Round 19 retest" (tests 43–56; Shay: 47, 48), then round 18 (tests 57–69), then the rest. Log in a new `test-run-<date>.md`.
- **Naming:** test rows are plain numbers (test 43); bugs are always "bug N". No letter codes (Shay finds them confusing). Passed rows are deleted from the test plan.
- **Bug 79** (FP look-at click takes control): r19h keeps control on Shay; details panel on click not done yet.
- **No manual validation:** run only rows Claude can verify from logs/state/goal status; list the "Shay" rows at the end. Test everything and log bugs, then fix all, then retest. DLL fixes: build during the run, install only when Shay says Kenshi is closed.
- **Test location:** Shay's outpost "Home" (layout in the test plan). Malzin is in Shay's squad (faction "Nameless"), Fond (+60). Keep food in a chest for long goals.
- History: `STOBE_bug_history.md` (bugs 1–91), `PATCH_HISTORY.md`, run logs in `archive/` (runs 5–7: `archive/test-run-2026-10-01-r5-r7.md`).

## Gotchas learned (runs 5–7)
- **Goals live outside the Kenshi save** (`RE_Kenshi\mods\Stobe\stobe_work_goals.tsv`, `stobe_task_goals.tsv` + server DB). Since bug 83 new goals carry the in-game time and are dropped when an older save is loaded; older unstamped goals are not. Clear leftovers before testing: write `<id>\tCANCEL` lines to `stobe_work_goal.control` / `stobe_task_goal.control`.
- **Goals run on game time** (bug 78): nothing advances while paused (requests aren't even picked up); at 50x everything is 50x faster, incl. stall/give-up timers.
- **Hunger:** `MedicalSystem::hunger` is fullness on a 0–3 scale; the game UI shows ×100 (216 = 2.16, max 300, KO ~76–87). Long 50x runs starve NPCs: keep food in a chest; the watch script must pause on `[EVENT] knockout: Shay|Malzin` as well as combat.
- **Walk-back/report target** is the selected squad member unless that's the worker herself, then the nearest other squad member (bug 75).
- **`stobe-say give_cats <n>` gives Shay cats** (test helper); it's not a payment. Shay pays by voice ("Here are your cats").
- **Squad members can't use Stobe's FOLLOW** (blocked for player faction); follow/guard go through KenshiFP BODYGUARD → FOLLOW_PLAYER_ORDER.
- **Crash dumps:** `D:\…\Kenshi\crashDump1.0.65_x64.zip`; parse the .dmp exception + stack (scratch script `md.py` approach) and map KenshiFP RVAs with `x86_64-w64-mingw32-nm -n` (ImageBase from `objdump -p`).
- Git Bash mangles `/mnt/...` paths and nested quotes: use `wsl.exe … bash -s <<'EOF'` heredocs, `MSYS_NO_PATHCONV=1`, or write patch scripts with the Write tool. Edits to WSL files via `//wsl.localhost/DwemerAI4Skyrim3/...` with Read/Edit work.

## Git: the repos are the source of truth
- **Server** `github.com/shaylanger/StobeServer`, committed in the live tree `/var/www/html/StobeServer` (on `integrate-custom` = `origin/stobe`; `git push origin HEAD:stobe`; don't switch branches there without asking). `upstream` = Dwemer-Dynamics, keep separate.
- **Native** `github.com/shaylanger/Kenshi-Stobe-Custom` = this folder (`main`). `components/STOBE`, `components/KenshiFP` are snapshots of `/root/STOBE-src`, `/root/KenshiFP`: copy changed files over (`diff -rq`) before committing.
- One fix/feature per commit (what + why + bug/feature number); **push right after every commit**. Never commit logs, DLLs, backups, runtime state.

## Where things are
- **Server:** WSL `DwemerAI4Skyrim3`, `/var/www/html/StobeServer` (live) + merge copy `/root/stobe-work/ss-merge` (patch **both**). Run via `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s` + heredoc. Don't chown, and never leave root-owned files the web server must write. DB: `sudo -u postgres psql -d stobe`.
- **Stobe.dll:** source `/root/STOBE-src` → copy changed files to `C:\StobeBuild\src`, build `C:\StobeBuild\build_portable.bat` (VS2010, `/GL`+`/LTCG` required) → `C:\StobeBuild\out\Stobe.dll`; install to `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` (plain file; keep old as `C:\StobeBuild\out\Stobe.dll.prev_<hash8>`). A Vortex redeploy could restore the old 1.2.3 link.
- **KenshiFP:** source `/root/KenshiFP` (compiles `client/stobe_work_planner.inc`, `client/stobe_task_goals.inc`; `stobe_task_goals_stage.inc` is unused). Build `cd /root/KenshiFP/re_plugin && bash build.sh` → `re_plugin/KenshiFP.dll`. Install over the Vortex link target `C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\KenshiFP\KenshiFP.dll` (keep `.prev_<hash8>`).
- Replace DLLs only with Kenshi closed; verify SHA256 and loaded modules (`(Get-Process kenshi_x64).Modules`).
- **Logs:** `D:\…\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`, `D:\…\Kenshi\KenshiFP.log` (both reset on launch, so review before relaunch), server `log/stobeserver.log` (huge: grep/tail only). Goal status: `RE_Kenshi\mods\Stobe\stobe_work_goal.status` / `stobe_task_goal.status` (tab-separated; step = field 8 work, field 10 task); control `stobe_work_goal.control` (`<id>\tCANCEL|PAUSE|RESUME`).
- **Machines:** this PC (RTX 5090) runs Kenshi + WSL stack + PocketTTS; the 4080 (`ssh 4080`) is reserved for a future background LLM. Chat: DeepInfra (DeepSeek V4.1 Flash); relationship eval still via OpenRouter. Don't change the runtime unless asked. Slow replies → rerun `tools/stobe-provider-bench.php` before blaming the server.

## Tools (WSL `/usr/local/bin`; sources in `tools/`)
- `stobe-say on|off|ping|state <npc> [--json]|speed <0|0.5..50>|give_cats <n>|say <npc> <text…> [--wait S]` (drives the game via the DLL test inbox).
- `stobe-reset-npc <npc>`, `stobe-session HH:MM HH:MM|now [npc]` (for Shay's time + NPC reports), `stobe-tests [tree] [pattern]` (once at the end), `stobe-rotate-logs` (after every server deploy), `negotiation_admin.php deals N`.
- `tools/stobe-goal-watch.sh <goal_id> <max_s>` (Git Bash): goal status + auto-pause on combat/knockout toward Shay/Malzin.
- Fights: Shay on pause duty; arm `stobe-fight-offer`/`stobe-fight-watch` before `stobe-force-attack`.

## Automated testing
- **Wait for Shay's "go"** (Kenshi running ≠ save loaded). Read-only checks are fine before that.
- Then: both DLL hashes, `stobe-say on`, `ping`, `state Malzin`/`state Shay`, combat check. One line at a time; a pass means real game state changed (status files, KenshiFP.log, inventories), never just the words.
- **Safety:** after risky lines grep stobe.log for `[EVENT] combat…-> Shay|Malzin` before the next line; at speed >10x poll every 10 s and `stobe-say speed 0` on any combat toward them; if Shay is attacked or knocked out, stop and tell him. Back to 1x when done.
- The LLM often picks a different action than intended: log it as a bug and add a server guard.

## Working rules
- Shay: concise answers, one step at a time, no unrelated changes.
- Only touch Kenshi-modding paths; keep reads small (grep/tail), batch commands; if the permission checker fails twice, stop and tell Shay.
- Server changes: back up → stage → `php -l` → standalone test → deploy live + ss-merge → rotate logs → commit/push → `stobe-tests` once at the end.
- Patch scripts go in `pending-fixes/` (assert anchors, take a tree root, reproducible).
- Python one-offs: write to the scratchpad, run with WSL `python3`.
- Negotiation design rules: memory `stobe-negotiation-rules`.
- Open for later: "relationship should shape everything she does" (pricing/willingness by tier); pick the 4080 background LLM.
