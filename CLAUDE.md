# Kenshi modding workspace (Shay)

STOBE / KenshiFP work: notes, test plan, patch scripts, tools, source snapshots.

## Current state (2026-10-02, after run 11) — start here
- **Installed:** Stobe.dll `D7DA294A` (hand-overs inventory-first), KenshiFP.dll `F7935763`. Server through round 23 (live + ss-merge, pushed). Kenshi is closed.
- **Open items live only in `STOBE_full_test_plan.md`**, numbered from 1 (restarted 2026-10-02; "was N" = old bug number used in commits/code). Sections: A needs Shay, B needs a game state, C can't reproduce, D open bugs (38–40), E design/features. **Next item is 41.**
- **Next job:** D bugs 38–40 (planner input ratio, false "done" claims, inventory lag), then B rows that can be staged; then Shay's A rows. Run `stobe-tests` once at the end.
- Shay works on the server too (e.g. `61658b2` dialogue contract split): check `git log`/`git status` in the live tree before patching, and patch with anchor scripts, never by copying whole files.
- Untracked `tools/*.py` inspection scripts (extract-meaningful-responses, inspect-*, list-session-core, summarize-gameplay-shadow) came from another session: not mine, left uncommitted.
- **Automated test bed works** (see "Test bed" below); run 9 (`archive/test-run-2026-10-02-r9.md`) is the first fully automated run. Other sessions: coordinate (SendMessage) before installing DLLs or launching Kenshi so two sessions don't fight over the game.
- stobe-tests: 51 pass / 7 known / `negotiation_engine` fails 2 checks ("unpaid -> BREACHED_PLAYER" pre-existing; "breach reaction queued" depends on it). The runner deletes the leftover "Inactive game probe" event (it failed 3 deal checks at random).
- **Naming:** plan items are plain numbers ("item 7"/"bug 7"), numbered from 1 since 2026-10-02; old numbers ("was 79") only for tracing. No letter codes. Fixed and confirmed items get deleted from the plan (add a line to the run log in `archive/`).
- **No manual validation:** run only rows Claude can verify from logs/state/goal status; list "Shay" rows at the end. Test everything and log bugs, then fix all, then retest. **Claude runs the whole loop alone** (Shay's decision 2026-10-02): launch Kenshi, load a test save, test, log bugs, close Kenshi, fix, build, install, relaunch, retest until every testable bug is fixed, then close Kenshi. No "go" needed. Use `tools/automation/kenshi-ctl.ps1` (launch/stop/restart/status/health) and `install-dll.ps1`.
- **Test location:** Shay's outpost "Home" (game calls the area "The Hub, Border Zone"). Malzin is in Shay's squad (faction "Nameless"), Fond. Keep food in a chest for long goals. The test inbox speaker is the **selected** character: keep Shay selected.
- History (all in `archive/`): `STOBE_bug_history_old_numbers.md` (closed bugs, old numbering), `PATCH_HISTORY.md`, `run8-deep-dive.md`, run logs `test-run-*.md`; run 8 raw logs + all LLM prompts in `archive/logs-run8-2026-10-01/` (local only, gitignored).

## Process rules from run 8 (Shay's feedback)
- Say the full plan up front and run exactly that; never add steps mid-test.
- After a watch-script ALERT the game **stays paused** until Shay unpauses; never send a speed command after an alert. (Exception: automated runs on a fixture copy, see "Test bed".)
- Watch fights live (NPC lines + events), and fact-check NPC claims against `[EVENT]` lines; wrong statements are bugs.
- Save `stobe.log`/`KenshiFP.log` (and server/prompt slices) before any relaunch: both game logs reset on launch.
- Prompts sent to the LLM: `log/context_sent_to_llm.log`, outputs `log/output_from_llm.log` (server). `stobe-rotate-logs` archives them.

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
- **Stobe.dll:** source `/root/STOBE-src` → copy changed files to `C:\StobeBuild\src`, build `C:\StobeBuild\build_portable.bat` (VS2010, `/GL`+`/LTCG` required) → `C:\StobeBuild\out\Stobe.dll`; install to `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` (plain file). A Vortex redeploy could restore the old 1.2.3 link.
- **KenshiFP:** source `/root/KenshiFP` (compiles `client/stobe_work_planner.inc`, `client/stobe_task_goals.inc`; `stobe_task_goals_stage.inc` is unused). Build `cd /root/KenshiFP/re_plugin && bash build.sh` → `re_plugin/KenshiFP.dll`. Install over the Vortex link target `C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\KenshiFP\KenshiFP.dll`.
- Install with `& "C:\KenshiModding\tools\automation\install-dll.ps1" Stobe|KenshiFP` (Shay allows installs without asking; Kenshi must be closed; it checks SHA256). Replace DLLs only with Kenshi closed; verify loaded modules (`(Get-Process kenshi_x64).Modules`).
- **No DLL backup copies** (`.prev_<hash>`, dated copies): git is the history; rebuild an old version from its commit if needed.
- **Logs:** `D:\…\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`, `D:\…\Kenshi\KenshiFP.log` (both reset on launch, so review before relaunch), server `log/stobeserver.log` (huge: grep/tail only). Goal status: `RE_Kenshi\mods\Stobe\stobe_work_goal.status` / `stobe_task_goal.status` (tab-separated; step = field 8 work, field 10 task); control `stobe_work_goal.control` (`<id>\tCANCEL|PAUSE|RESUME`).
- **Machines:** this PC (RTX 5090) runs Kenshi + WSL stack + PocketTTS; the 4080 (`ssh 4080`) is reserved for a future background LLM. Chat: DeepInfra (DeepSeek V4.1 Flash); relationship eval still via OpenRouter. Don't change the runtime unless asked. Slow replies → rerun `tools/stobe-provider-bench.php` before blaming the server.

## Tools (WSL `/usr/local/bin`; sources in `tools/`)
- `stobe-say on|off|ping|state <npc> [--json]|speed <0|0.5..50>|give_cats <n>|say <npc> <text…> [--wait S]` (drives the game via the DLL test inbox). `stobe-auto` (scenario commands, see "Test bed").
- `stobe-reset-npc <npc>`, `stobe-session HH:MM HH:MM|now [npc]` (for Shay's time + NPC reports), `stobe-tests [tree] [pattern]` (once at the end), `stobe-rotate-logs` (after every server deploy), `negotiation_admin.php deals N`.
- `tools/stobe-goal-watch.sh <goal_id> <max_s>` (Git Bash): goal status + auto-pause on combat/knockout toward Shay/Malzin.
- Fights: Shay on pause duty; arm `stobe-fight-offer`/`stobe-fight-watch` before `stobe-force-attack`.

## Test bed (automated, Claude runs it alone)
- **Loop:** `kenshi-ctl.ps1 launch -Save auto-home` → `stobe-auto wait-world` → pre-flight → build the situation with `stobe-auto` → `stobe-say say …` → check real game state → log in `archive/test-run-<date>.md` → after a batch: `kenshi-ctl.ps1 stop` → fix → build → `install-dll.ps1 Stobe|KenshiFP` → relaunch → retest. Close Kenshi when done.
- **Launch** (`tools/automation/kenshi-ctl.ps1`, PowerShell; allowed without asking): `launch [-Save x]` starts `kenshi_x64.exe` directly (Steam running, no Steam prompt), RE_Kenshi restarts it as `RE_Kenshi\kenshi_x64.exe --norestart`, the script presses the launcher dialog's OK (button 1003), archives logs to `C:\KenshiTestRuns\logs\` and deletes the old `stobe.log`, then waits for `TEST_AUTO: frame listener running` and the autoload. Also `stop`, `restart`, `status`, `health` (ok/crashed/hung), `screenshot [-Save n]` (`C:\KenshiTestRuns\shots\`; Kenshi's HUD doesn't show in it yet).
- **Saves:** fixtures (master copies) in `C:\KenshiTestFixtures\` (`auto-home` = run 8 autosave at Home, Malzin in squad); a copy lives in `%LOCALAPPDATA%\kenshi\save\`. Restore a fixture by copying it over the save folder. Never test on Shay's own saves.
- **In-game commands** (`stobe-auto`, WSL; Stobe `src/TestAutomation.cpp`, needs `stobe-say on`, works at the main menu): `status`, `wait-world`, `load`, `save`, `chars [r]`, `find <character|squad|item|weapon|armour> <text>`, `spawn <template> <faction> [near <npc>|at x y z] [count n] [dist m]`, `where`, `teleport`, `ko`, `health <pct>`, `kill`, `hunger <0..300>`, `attack <a> <b>` (player → NPC works; same-faction NPCs ignore it), `select`, `recruit`, `give <npc> <item> [n]`, `relation <npc> <v>`. Names: exact match nearest the player, `#serial` for one of several same-named NPCs, `@player`, `@selected`; corpses near the player are found too. Spawned "Hungry Bandit" + faction `Drifters` = neutral test dummy.
- **Pre-flight:** DLL hashes, `stobe-say ping`, `state Malzin`/`state Shay`, goal status files all terminal, no `[EVENT] combat…-> Shay|Malzin`; `stobe-reset-npc Malzin` unless trust matters; `stobe-auto hunger Malzin 250` before long 50x runs.
- A pass means real game state changed (status files, KenshiFP.log, inventories, events), never just the words.
- **Safety:** at speed >10x use `tools/stobe-goal-watch.sh` (pauses on combat/knockout toward Shay/Malzin). On a fixture copy an alert ends that test: pause, save logs, log the bug, reload the fixture (`stobe-auto load auto-home`).
- The LLM often picks a different action than intended: log it as a bug and add a server guard.
- **Scenarios** (`tools/automation/scenarios.sh`, WSL): `fresh` (reload auto-home, feed, reset Malzin), `bodies <n>`, `duel`, `gang <n>`, `surrender` (prints `serial|name|deal`; sends Malzin 300 away, waits for `combat_start` before dropping his health, refuses if Shay is KO; retry if the deal is empty), `trust "<npc>" 60 Fond`. Accept with the **full** name (`stobe-say say "Vorl [Dust Bandit Bowman]" "Vorl, deal."`): the test inbox needs an exact name.
- `@player` = first squad member (can be Malzin): name Shay explicitly. `attack` gives a real order (breaks truces like a player click). Never kill members of a spawned neutral squad near the squad (survivors turn hostile): teleport them away. Check `stobe-auto where Shay` for ` KO` between fights. A second squad member with a bracketed name: spawn `"Bandit Raiders (weakened) 1" Drifters`, recruit one, talk to him once (he gets named "X [Dust Bandit]").
- Server fixes: stage in a copy (`rsync` the live tree minus log/.git), add a check to `tests/negotiation_engine_regression.php`, run it there with the `stobe-tests` env vars, confirm it fails without the fix, then deploy both trees. Raiders must be teleported inside the outpost walls (else `path_failed`); Shay attacking first is what reliably starts a fight. `buy`, `money`, `stash`, `inv`, `hp` in `stobe-auto`; `give` can't create weapons.
- **Builds:** `tools/automation/build-stobe.ps1` (syncs changed WSL sources, builds); KenshiFP `build.sh` in WSL; then `kenshi-ctl.ps1 stop` + `install-dll.ps1`.
- **Gotchas:** after a reload spawned NPCs get the same serials (and the server's old names: bug 117); PHP opcache serves a changed server file only after ~1 min; WSL clock is 1 h ahead of stobe.log (use `stobe-guard.sh`, line numbers). Never `git checkout` a file in ss-merge (it holds uncommitted round work).

## Working rules
- Shay: concise answers, one step at a time, no unrelated changes.
- Only touch Kenshi-modding paths; keep reads small (grep/tail), batch commands; if the permission checker fails twice, stop and tell Shay.
- Server changes: back up → stage → `php -l` → standalone test → deploy live + ss-merge → rotate logs → commit/push → `stobe-tests` once at the end.
- Patch scripts go in `pending-fixes/` (assert anchors, take a tree root, reproducible).
- Python one-offs: write to the scratchpad, run with WSL `python3`.
- Negotiation design rules: memory `stobe-negotiation-rules`.
- Open for later: "relationship should shape everything she does" (pricing/willingness by tier); pick the 4080 background LLM.
