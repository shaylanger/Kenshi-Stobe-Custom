# Where things are: repos, builds, installs, logs, machines

Read before: building/installing a DLL, finding logs, using server/harness/4080.
Moved verbatim from CLAUDE.md (original line numbers in the comment before each block). Nothing here is paraphrased.

<!-- original CLAUDE.md line 45 -->
- **Server** `github.com/shaylanger/StobeServer`, committed in the live tree `/var/www/html/StobeServer` (on `integrate-custom` = `origin/stobe`; `git push origin HEAD:stobe`; don't switch branches there without asking). `upstream` = Dwemer-Dynamics, keep separate.
- **Native** `github.com/shaylanger/Kenshi-Stobe-Custom` = this folder (`main`). `components/STOBE`, `components/KenshiFP` are snapshots of `/root/STOBE-src`, `/root/KenshiFP`: copy changed files over (`diff -rq`) before committing.
<!-- original CLAUDE.md line 51 -->
- **Server:** WSL `DwemerAI4Skyrim3`, `/var/www/html/StobeServer` (live) + merge copy `/root/stobe-work/ss-merge` (patch **both**; never `git checkout` a file in ss-merge). Run via `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s` + heredoc. Don't chown; never leave root-owned files the web server must write. DB: `sudo -u postgres psql -d stobe`. PHP opcache serves a changed file only after ~1 min.
- **Stobe.dll:** source `/root/STOBE-src`; build `tools/automation/build-stobe.ps1` (syncs to `C:\StobeBuild\src`, VS2010 `/GL`+`/LTCG`) → `C:\StobeBuild\out\Stobe.dll`.
- **KenshiFP:** source `/root/KenshiFP` (`client/stobe_work_planner.inc`, `client/stobe_task_goals.inc`); build `cd /root/KenshiFP/re_plugin && bash build.sh`. **One command per build:** `tools/automation/kfp-pipeline.sh [--patches a,b|--all-pending] [--revert p]` (WSL root, detached; usage in its header): scratch copy of /root/KenshiFP + pending patches (per-patch/pair conflict report) → DLL → full animlab gate in private mount namespaces (base, all, each patch alone / set minus it) → per-patch delta table (BREAK = verdict flip or pool take drop >= 0.05) → on PASS stages `C:\KenshiTestRuns\staged\KenshiFP-<sha8>.dll` on both rigs + a queue line; install at the rig's next restart with `install-dll.ps1 KenshiFP -Staged [-Rig 4080]`.
- **Harness:** repo `C:\KenshiModding\Kenshi-Automation-Harness` (own git, public; read its `AGENTS.md`, commands `docs/COMMANDS.md`). Build `build.bat`, offline tests `tests\run_tests.bat`. New general test commands go there; Stobe-only ones into `StobeHarnessBridge.cpp`.
<!-- original CLAUDE.md line 56 -->
- **Install:** `& "C:\KenshiModding\tools\automation\install-dll.ps1" Stobe|KenshiFP|Harness|ProfessionGear` (allowed without asking; Kenshi must be closed; checks SHA256). No DLL backup copies: git is the history.
- **Logs:** `D:\…\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`, `D:\…\Kenshi\KenshiFP.log` (both reset on launch: `kenshi-ctl.ps1 launch` archives them to `C:\KenshiTestRuns\logs\`), harness `mods\AutomationHarness\harness.log`, server `log/stobeserver.log` (huge: grep/tail only), LLM prompts `log/context_sent_to_llm.log`. Goal status `RE_Kenshi\mods\Stobe\stobe_work_goal.status` / `stobe_task_goal.status`; cancel leftovers with `<id>\tCANCEL` in the `.control` files.
