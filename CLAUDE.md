# Kenshi modding workspace (Shay)

Home folder for STOBE / KenshiFP work: notes, test plan, patch scripts, tools and source snapshots.

## Current state (2026-10-01) — start here
- **Installed:** Stobe.dll `3F967C4E…`, KenshiFP.dll `1C768AB1…`. Server: everything through round 18c (live + ss-merge, pushed). stobe-tests baseline 52 pass / 7 known (one suite flakes now and then; rerun).
- **Next job: test the round 17 fixes and round 18 features** from `STOBE_full_test_plan.md` → "Work and task goals" (rows R1, R2, B1, B1c, F1, P1, P1b, C1, C2) and "Round 18 features" (N1–N5 faction-only orders, V1–V3 TTS volume/fade, S1–S2 TTS speed, J1–J3 job list, L1–L3 goal label). Log results in a new run file (`test-run-2026-10-01.md`); next bug number is **71**.
- **Shay wants no manual validation** for automated runs: run only rows Claude can verify from logs/state/goal status; list the Shay-only rows (marked "Shay") at the end.
- **Workflow Shay asked for:** test everything first and log bugs, then fix them all, then retest; DLL fixes need Kenshi closed (build, then install when he says it's closed).
- **Test location now: Shay's outpost "Home"** (wheat farms S + XL, grain silo, well, bread oven, stone mine, manual stone processor, 4 General Camp Storage Chests, generators). Malzin is in Shay's squad (faction "Nameless"), relationship Fond (+60). The farm ran dry in run 4; bread needs the well powered and the farm watered.
- Run 4 log (bugs 44–70, all fixed): `archive/test-run-2026-09-30-r4.md`. Patch history: `PATCH_HISTORY.md`. Bugs 1–70: `STOBE_bug_history.md`.

## Key behaviour added in rounds 17–18 (what the tests check)
- **Work goals** (KenshiFP planner): walk-back to the selected player when a goal ends; hauls missing inputs only from storage/mines/machine outputs; clears old orders when switching machines; power gate (blocks "X has no power" after 30 s, only once she operates a machine with inputs loaded); "Waiting for <farm> to grow"; dry farm blocks after 60 s; goal machines mirrored as real Kenshi jobs (`GOAL_JOB added/removed`; safety switch-off on an unexpected removal); on-screen label "StobeGoalLabel" (top centre) for the selected squad member.
- **Goal reports:** KenshiFP writes `stobe_goal_report.request` + `lifelike_initiative.flag` when she's back within 70; Stobe.dll consumes the flag and may address the player; server `bored.php` queues a `goal_report` directive (no director mode).
- **Server conveniences:** store-not-give for "put back in storage"; "resume/try again" resumes the existing goal; "keep N stocked" → STOCK goal; item lists read from the player's line; PATROL → managed patrol goal; LOOT_TARGET with a category or an unreachable body → LOOT_AREA; stored-serial fallback when the NPC is outside the people list; `<player_base>` for faction members (presence or nearest known base).
- **Faction-only orders (18c):** non-faction NPCs refuse work orders; follow/guard/wait/come/go only at trust ≥ `MINOR_ORDER_TRUST_MIN` (default 56) or an open deal.
- **TTS (18a/18b):** plays at 1x at any game speed (`Speed Dialogue=0`); STOBE Settings TTS row: Volume 0–200 %, Fade 25–400 % (`TTSVolume`, `TTSFadePercent`).

## Git: the repos are the source of truth
- **Server** `github.com/shaylanger/StobeServer`, committed in the live tree `/var/www/html/StobeServer` (checked out on `integrate-custom` = `origin/stobe`; push with `git push origin HEAD:stobe`; don't switch branches there without asking). `upstream` = Dwemer-Dynamics, keep separate.
- **Native** `github.com/shaylanger/Kenshi-Stobe-Custom` = this folder (`main`). `components/STOBE`, `components/KenshiFP` are snapshots of the live WSL sources `/root/STOBE-src`, `/root/KenshiFP`: copy changed files over (check `diff -rq`) before committing.
- One fix/feature per commit, message says what + why + bug/feature number; **push right after every commit**. Never commit logs, DLLs, backups, runtime state.

## Where things are
- **Server:** WSL `DwemerAI4Skyrim3`, `/var/www/html/StobeServer` (live) + merge copy `/root/stobe-work/ss-merge` (patch **both**). Run commands with `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s` + heredoc. Don't chown. DB: `sudo -u postgres psql -d stobe`.
- **Stobe.dll:** source `/root/STOBE-src`; copy changed files to `C:\StobeBuild\src`, build `C:\StobeBuild\build_portable.bat` (VS2010, `/GL`+`/LTCG` required), output `C:\StobeBuild\out\Stobe.dll`; install to `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` (save the old one as `C:\StobeBuild\out\Stobe.dll.prev_<hash8>`).
- **KenshiFP:** source `/root/KenshiFP` (compiles `client/stobe_work_planner.inc` and `client/stobe_task_goals.inc`; `stobe_task_goals_stage.inc` is an unused copy). Build `cd /root/KenshiFP/re_plugin && bash build.sh` → `re_plugin/KenshiFP.dll`. Install by copying over the Vortex link target `C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\KenshiFP\KenshiFP.dll` (keep `.prev_<hash8>`).
- Only replace DLLs while Kenshi is closed; verify SHA256 and the loaded modules (`(Get-Process kenshi_x64).Modules`).
- **Logs:** `D:\…\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`, `D:\…\Kenshi\KenshiFP.log` (reset on launch), server `log/stobeserver.log`. Goal status files: `RE_Kenshi\mods\Stobe\stobe_work_goal.status` / `stobe_task_goal.status` (tab-separated; current step is field 8 for work, field 10 for task goals); control file `stobe_work_goal.control` (`<id>\tCANCEL|PAUSE|RESUME`).
- **Machines:** this PC (RTX 5090) runs Kenshi + the WSL stack; the 4080 (`ssh 4080`) is reserved for a future background LLM. Chat runs on DeepInfra (DeepSeek V4.1 Flash). Don't change the runtime unless asked.

## Tools (WSL `/usr/local/bin`; sources in `tools/`)
- `stobe-say on|off|ping|state <npc> [--json]|speed <0|0.5..50>|give_cats <n>|say <npc> <text…> [--wait S]` — drives the game through the DLL test inbox (speaker falls back to another squad member if the target is selected).
- `stobe-reset-npc <npc>`, `stobe-session HH:MM HH:MM|now [npc]`, `stobe-tests [tree] [pattern]` (once at the end), `stobe-rotate-logs` (after every server deploy), `stobe-force-attack`, `stobe-fight-watch`, `stobe-fight-offer` (fight tests), `negotiation_admin.php deals N` (ledger).

## Automated testing
Shay loads the save at Home, unpauses and says **"go"** (Kenshi running ≠ ready). Then: check both DLL hashes, `stobe-say on`, `ping`, `state Malzin`/`state Shay`, combat check. Send one line at a time; a pass means the game state changed (status files, KenshiFP.log, inventories), not just the words.
- **Safety:** after risky lines grep stobe.log for `[EVENT] combat…-> Shay|Malzin`; at speed >10x poll every 10 s and `stobe-say speed 0` on any combat toward them; if Shay is attacked or unconscious, stop and tell him. Drop speed to 1x when done.
- Watch out: the LLM often picks a different action than intended (log it as a bug and add a server guard); goals for the same item count the stockpile; planner assumes 1 input per output.

## Working rules
- Keep reads small (grep/tail), batch commands; if the permission checker fails twice, stop and tell Shay.
- Server changes: back up → stage → `php -l` → standalone test → deploy live + ss-merge → rotate logs → commit/push → `stobe-tests` once at the end.
- Write patch scripts in `pending-fixes/` (assert anchors, take a tree root) and keep them reproducible.
- Python one-offs: write the script to the scratchpad and run it with WSL `python3` (Git-Bash heredocs mangle paths/quotes).
- Test reports from Shay come with a time + NPC name: use `stobe-session`.
- Open items for later: Shay's design note "relationship should shape everything she does" (pricing/willingness by tier); pick the 4080 background LLM.
