# Test bed: loop, saves, commands, pre-flight, safety

Read before: launching the game for tests or writing scenarios.
Moved verbatim from CLAUDE.md (original line numbers in the comment before each block). Nothing here is paraphrased.

<!-- original CLAUDE.md line 69 -->
- **Loop:** `kenshi-ctl.ps1 launch -Save <save>` (`stobe-say on` first) → `stobe-auto wait-world` → pre-flight → batch of scenarios/wrappers → check real game state → log in the run log → `kenshi-ctl.ps1 stop` → fix all → build → install → relaunch → retest. Game lock `C:\KenshiTestRuns\game.lock` (`kenshi-ctl.ps1 lock|release`).
- **Saves:** fixtures in `C:\KenshiTestFixtures\` (read `FIXTURES.md`), tested on `kah-*` copies (`C:\KenshiTestRuns\scenarios\relaunch.ps1 -Fixture <name> -Copy <kah-name>`). Full-Base (Beaks/Avarek), Squin (Beak/Kint), Enslaved (Izumi/Daphnilis) squads aren't Shay/Malzin: pass names (`PLAYER=… MATE=…`, `stobe-auto select <player>`); run `tests/ingame/stobe/fullbase-guard.sh` after every Full-Base load (world raids). Never `build` a Biofuel Distillery (crash).
- **Commands:** `stobe-auto <cmd>` (harness client; `stobe-auto help`, full list `docs/COMMANDS.md`), `stobe-say say <npc> <text>` (speaks as the selected character; exact names), `scenarios.sh fresh|duel|gang|surrender|trust`, wrappers `tests/ingame/stobe/STOBE-*.sh` (source `stobe-fight-lib.sh`: `bash -n` it after edits), scenario files `stobe-auto run <file> --csv out.csv`.
- **Pre-flight:** DLL hashes, `stobe-say ping`, `state <player>`/`state <mate>`, goal status files terminal, no combat toward the squad; `stobe-auto hunger <mate> 250` before long 50x runs.
- **Safety:** at speed >10x use `tools/stobe-goal-watch.sh` (pauses on combat/knockout toward the squad); on a fixture copy an alert ends that test (save logs, log the bug, reload the fixture). Long WSL batches: start detached (`setsid nohup bash … &` inside WSL).
- Goals run on game time (nothing advances while paused); goals live outside the save (stamped with game time, dropped on loading an older save). The LLM often picks a different action than intended: log it as a bug and add a server guard.
<!-- original CLAUDE.md line 78 -->
- Crash dumps: `D:\…\Kenshi\crashDump1.0.65_x64.zip` (parse exception + stack; map KenshiFP RVAs with `x86_64-w64-mingw32-nm -n`).
- Git Bash mangles `/mnt/...` paths and nested quotes: use `wsl.exe … bash -s <<'EOF'` heredocs or `MSYS_NO_PATHCONV=1`; don't run Windows `python3` in Git Bash (use WSL python3).
