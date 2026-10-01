# Kenshi modding workspace (Shay)

STOBE / KenshiFP work: notes, test plan, patch scripts, tools, source snapshots.

## Current state (2026-10-01, after run 5 + round 19) — start here
- **Installed:** Stobe.dll `8B231133…`, KenshiFP.dll `639DAD65…`; server through round 19 (live + ss-merge, pushed). stobe-tests baseline 52 pass / 7 known (negotiation_engine flakes; rerun).
- **Next job:** test plan "Round 19 retest" (R1, R2, C1, C2, F1b, D1, H1, M1, M2, S1) plus the untested round 18 rows (N1–N3, N5, V1–V2, S1). Log in a new `test-run-<date>.md`; next bug is **80** (79 is logged in the test plan, section 4, to fix next round). Run 5 log: `test-run-2026-10-01.md`.
- **No manual validation:** run only rows Claude can verify from logs/state/goal status; list the "Shay" rows at the end. Test everything and log bugs, then fix all, then retest. DLL fixes: build during the run, install only when Shay says Kenshi is closed.
- **Test location:** Shay's outpost "Home" (layout in the test plan). Malzin is in Shay's squad (faction "Nameless"), Fond (+60). Keep food in a chest for long goals.
- History: `STOBE_bug_history.md` (bugs 1–78), `PATCH_HISTORY.md`, run logs in `archive/`.

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
