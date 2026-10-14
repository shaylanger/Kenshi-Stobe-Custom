# STOBE / NPC logic: how to test changes end to end on the 5090

A context file for an agent that changes Stobe (NPC chat, goals, deals, relationships, actions) and must prove
the change works in the real game, automatically. Covers the server, the DLL, the saves, the harness, the batch
runner and how to read results. (First-person/animation work is out of scope here.)

Read first: `CLAUDE.md` (standing rules), `testing/HANDOFF.md` "Right now" (what is installed/running now),
`STOBE_full_test_plan.md` (open STOBE items), `MASTER_TEST_PLAN.md` (index of open rows), `docs/REFERENCE.md`
(full command list, scenario helpers, gotchas, relationship storage).

## 1. The pieces

| Piece | Where | What it does |
|---|---|---|
| Stobe server (PHP + Postgres) | WSL distro `DwemerAI4Skyrim3`, live tree `/var/www/html/StobeServer` (branch `stobe`), merge copy `/root/stobe-work/ss-merge` | builds the LLM prompt, calls the model, parses action lines (`WORK_GOAL@...`, `TASK_CONTROL@...`, deals), guards, relationships. Logs `log/stobeserver.log` (huge: grep/tail only), prompts `log/context_sent_to_llm.log`. DB `sudo -u postgres psql -d stobe` (`eventlog` = every chat/action line). |
| Stobe.dll | source `/root/STOBE-src` (snapshot `components/STOBE`) | in-game side: chat UI, sends events, runs actions (goals, orders, first aid, equip...), goal panel, NPC info panel. Log `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log` + `stobe_goals.log`; goal status `stobe_work_goal.status` / `stobe_task_goal.status` (cancel leftovers: `<id>\tCANCEL` into the `.control` file). |
| Automation harness (KAH) | repo `Kenshi-Automation-Harness` (own git), DLL in `mods\AutomationHarness` | in-game test commands (`stobe-auto <cmd>`): load saves, select, spawn, give, teleport, ko, relation, fight, inv, jobs, screenshot... `stobe-auto help`, full list `docs/COMMANDS.md` there. Stobe-only commands live in `StobeHarnessBridge.cpp`. |
| `stobe-say` | WSL tool | speaks as the selected character: `stobe-say say <npc> <text>` (exact names), `stobe-say ping`, `stobe-say on` |
| Wrappers | `tests/ingame/stobe/STOBE-*.sh` | one scenario per file, each ends with `RESULT <row> PASS|FAIL <evidence>` lines. Shared lib `stobe-fight-lib.sh` (`verdict()`, setup helpers, `park_malzin`...); `bash -n` it after any edit. |
| Batch runner | `tools/automation/run-batch.sh` | runs a list of wrappers in one game launch, writes `SUMMARY.txt` + `DONE`. |

Chat model: DeepInfra (DeepSeek V4.1 Flash); relationship eval via OpenRouter. Don't change the runtime unless asked.
If NPCs answer "..." grep the server log for `"http_code":402` (out of credit).

## 2. Before you test: bring the stack up

1. WSL stops when idle; after a PC restart or a long idle the server is down. Start it detached:
   `MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s <<'EOF'` +
   `setsid nohup bash /etc/start_env >/tmp/start_env.log 2>&1 </dev/null &` + `EOF`. Check `pgrep -c postgres`, `pgrep -c apache2`.
2. STOBE server may be switched off (it is turned off during non-STOBE work to save LLM credits):
   `bash /mnt/c/KenshiModding/tools/automation/stobe-server.sh on` (WSL root) before a STOBE batch, `off` after.
3. Voice: keep Parakeet STT and PocketTTS stopped unless the batch tests voice/TTS:
   `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/wsl-voice.sh all stop`
   (replies still arrive in ~1 s without TTS; one harmless `[WARN] Local TTS synthesis failed` per line).
4. Graphics mods off for automated runs (Kenshi closed): `bash tools/automation/gfx-mods.sh off --hdtex`.
   Shay restores with `gfx-mods.sh on` before he plays: remind him in your final summary (and to turn STOBE on).
5. Steam must be running (`D:\Steam\steamapps\..`; after a PC restart `D:\Steam\steam.exe -silent`).

## 2b. Which game install (instance) to use — check this before every Stobe run

The 5090 has more than one Kenshi install. Each one has its own Stobe config
(`<install>\RE_Kenshi\mods\Stobe\StobeCustom.ini`, keys `ServerHost` / `ServerPort`) and its own harness.

| Instance | Install | Stobe ServerPort (checked 2026-10-13) | Usable for Stobe/NPC tests? |
|---|---|---|---|
| 1 (default) | `D:\Steam\steamapps\common\Kenshi` | `8083` = the real Stobe server (Apache + PHP + model) | **yes: use this one** |
| 2 (lane "5090b") | `D:\KenshiInst\2` | `18083` = `capture_server.py`, a profile/portrait capture sink with `production_forwarding=false` | **no.** The sink answers `/StobeServer/interaction.php` with `{"ok":true}` (no `enabled`/`generation`), so Stobe goes into sync-error and `stobe-say` is refused with "manual input not allowed right now". Nothing reaches the server or the model. |
| 3 | `D:\KenshiInst\3` | `8083` | in principle yes (same server as instance 1); not used for Stobe so far |

Rules:
- Run Stobe/NPC batches on **instance 1** unless you have a reason not to. Instances >= 2 were set up for
  non-Stobe, gfx-low rows.
- Before any Stobe run, check the port of the install you will launch:
  `grep -iE '^(ServerHost|ServerPort)' "<install>/RE_Kenshi/mods/Stobe/StobeCustom.ini"` must say `127.0.0.1` / `8083`.
  If it says `18083`, that install talks to the capture sink, not to Stobe. To use it for Stobe, set
  `ServerPort=8083` in that file with that Kenshi closed (and put it back afterwards if the capture work still needs
  18083). Patching the sink does not help: it never forwards anything to the real server.
- The real server must be up: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8083/StobeServer/` from WSL
  should answer (Apache), and `stobe-server.sh on` (section 2).
- **Talk to the right harness.** `stobe-auto` and `stobe-say` go to instance 1 by default. For instance n >= 2 export
  the instance variables first, the same way the batch tools do (`batch-health.sh`, `rig-env.sh`):
  on 4080 use `KENSHI_DIR=/c/KenshiInst/<n>` with `KAH_DIR='C:\KenshiInst\<n>\mods\AutomationHarness'`; on 5090 use
  `KENSHI_DIR=/mnt/d/KenshiInst/<n>` with `KAH_DIR='D:\KenshiInst\<n>\mods\AutomationHarness'`.
  In both cases set `KAH_INSTANCE=<n>` explicitly.
  (in Windows-launched commands also pass `WSLENV=KAH_INSTANCE:KAH_OWNER:KAH_GFX`, see `tools/automation/mi-trial.sh`).
  `stobe-say` requires all three variables to agree for an isolated route and refuses incomplete or mismatched routes;
  when no isolated-route variable is set, it retains the instance-1 default. Launches go through `kenshi-ctl.ps1` with `KAH_INSTANCE=<n>`;
  the batch out dir gets a `.instance` file so the health checks look at the right game.
- Logs for instance n are under `D:\KenshiInst\<n>\...` (stobe.log in `RE_Kenshi\mods\Stobe\`), not the Steam folder.

## 2c. Step by step: run one Stobe/NPC test (copy these in order)

Instance 1 (the main install), from Git Bash in `C:\KenshiModding`. `W` = run inside WSL as root:
`W() { MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s; }` (then `W <<'EOF' ... EOF`).

1. Server stack up:
   `W <<'EOF'` / `pgrep -c apache2 || (setsid nohup bash /etc/start_env >/tmp/start_env.log 2>&1 </dev/null &; sleep 40)` /
   `bash /mnt/c/KenshiModding/tools/automation/stobe-server.sh on` / `bash /mnt/c/KenshiModding/tools/automation/wsl-voice.sh all stop` /
   `curl -s -o /dev/null -w 'server=%{http_code}\n' http://127.0.0.1:8083/StobeServer/` / `EOF` (must print an HTTP code, not 000).
2. Port check of the install you will launch (must be 127.0.0.1 / 8083):
   `grep -iE '^(ServerHost|ServerPort)' /d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/StobeCustom.ini`
3. Lock + save copy + launch (game closed first; never Shay's saves):
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/automation/kenshi-ctl.ps1 lock`
   `powershell -NoProfile -File C:/KenshiTestRuns/scenarios/relaunch.ps1 -Fixture "Testing-Save-Full-Base" -Copy kah-fullbase`
   (or `-Fixture auto-home -Copy auto-home` etc., section 4), then `powershell -NoProfile -ExecutionPolicy Bypass -File tools/automation/kenshi-ctl.ps1 window`
   (foreground must not be Kenshi).
4. In the world: `W <<'EOF'` / `stobe-say on; stobe-auto wait-world; stobe-auto select Beaks; stobe-say ping` / `EOF`
   (`ping` must answer; for Full-Base also `bash /mnt/c/KenshiModding/tests/ingame/stobe/fullbase-guard.sh`).
5. Smoke check that chat reaches the model: `stobe-say say Avarek "hello"`, then within ~10 s
   `grep -c 'NPC_SAY: Avarek' /mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log` rises.
   A refusal "manual input not allowed right now" = Stobe is in sync-error: wrong port (step 2) or server down (step 1).
6. One test: `W <<'EOF'` / `cd /mnt/c/KenshiModding/tests/ingame/stobe && PLAYER=Beaks MATE=Avarek bash STOBE-144-interrupt-resume-fullbase.sh` / `EOF`
   -> read its `RESULT` lines. Many tests: a list file + `run-batch.sh` (section 7) instead.
7. Close: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/automation/kenshi-ctl.ps1 stop`, `... kenshi-ctl.ps1 release`,
   delete the `kah-*` save copy, `stobe-server.sh off` if no other Stobe work follows.

Instance 2 or 3 instead (only if its port is 8083, step 2 on `/d/KenshiInst/<n>/...`; instance 2 is 18083 today, so
first set `ServerPort=8083` in `D:\KenshiInst\2\RE_Kenshi\mods\Stobe\StobeCustom.ini` with that game closed):
prefix every launch with the instance variables (`KAH_INSTANCE=<n>` + `WSLENV=KAH_INSTANCE`, see `tools/automation/mi-trial.sh` `ctl2`),
and in every WSL block first
`export KAH_INSTANCE=<n> KENSHI_DIR=/mnt/d/KenshiInst/<n> KAH_DIR='D:\KenshiInst\<n>\mods\AutomationHarness'`;
read logs from `/mnt/d/KenshiInst/<n>/RE_Kenshi/mods/Stobe/stobe.log`.

## 3. Making a change

**Server change** (most NPC-behaviour fixes: prompt text, guards, action parsing, deals):
1. `git log`/`git status` in the live tree first (Shay edits it too). Back up the files you touch.
2. Patch with an anchor script in `pending-fixes/` (asserts its anchors, takes a tree root), applied to BOTH trees
   (live + ss-merge). Never copy whole files; never `git checkout` a file in ss-merge. Don't chown; don't leave
   root-owned files the web server must write.
3. `php -l` every changed file. Add a regression check under `tests/` (e.g. `tests/negotiation_engine_regression.php`,
   `tests/goal_control_m51_regression.php`): it must FAIL without the fix and PASS with it.
4. Deploy (both trees), `stobe-rotate-logs`, wait ~1 min (PHP opcache), commit in the live tree with identity
   `shaylanger <shaylanger2@gmail.com>`, `git push origin HEAD:stobe`.
5. Run the offline suite `stobe-tests` + the regression checks: they must pass BEFORE any game batch, so a server
   bug never costs a game run.

**Stobe.dll change:** edit `/root/STOBE-src`, build with `tools/automation/build-stobe.ps1`
(-> `C:\StobeBuild\out\Stobe.dll`), install with Kenshi closed:
`& C:\KenshiModding\tools\automation\install-dll.ps1 Stobe` (checks SHA256). Copy changed files into
`components/STOBE` (`diff -rq`) and commit in this repo (one fix per commit, push right away). Stobe must keep
working with KenshiFP absent.

**Harness change** (a test needs a command that doesn't exist): build it, don't report "blocked". General
commands in the harness repo (`build.bat`, offline `tests\run_tests.bat`), Stobe-only ones in `StobeHarnessBridge.cpp`;
install with `install-dll.ps1 Harness`.

## 4. Which save to use

Masters live in `C:\KenshiTestFixtures\` (description: `FIXTURES.md` there). Never load a master, never use Shay's
own saves: test on a `kah-*` copy in `%LOCALAPPDATA%\kenshi\save\`
(`powershell -File C:\KenshiTestRuns\scenarios\relaunch.ps1 -Fixture "<name>" -Copy kah-<name>` = stop, copy, launch).
The harness turns autosave off, so a copy stays clean unless a test calls `save`. Delete copies afterwards.

| Fixture | Squad (player / mate) | Use it for |
|---|---|---|
| `auto-home` (batch save name `home`) | Shay / Malzin | default STOBE save: goals at Home buildings (stone mine, stone processor, wheat farm, grain silo w/o power, well, oven, chests), deals, fights (`scenarios.sh fresh|duel|gang|surrender|trust|raid|bodies`), relationship rows. Malzin is a test character: her relationship values don't matter. |
| `Testing-Save-Full-Base` (`kah-fullbase`) | **Beaks / Avarek** | full production chains with power (bread: wheat farm -> grain silo -> oven, water), goals at many bench types, interrupt/resume, spar/heal deals, bed/cage rescue. World raids: run `tests/ingame/stobe/fullbase-guard.sh` after every load (run-batch does it for `kah-fullbase`). |
| `Testing-Save-Squin` | **Beak / Kint** | many trader types: buy/sell, buy approval, goals needing a trader-only ingredient. |
| `Testing-Save-Enslaved` | **Izumi / Daphnilis** | slavery, escape, recruiting non-squad slaves (KO or set relation on guards first). |
| `Trader` | Shay alone | buying from real traders, shop stock. |
| `Crafting base` | Shay / Malzin | crafting at benches (no research done: `research "<name>"` first; no materials: `give` / `fill`), first aid / cage / trade setups, Apothecary Abia/Kalena (real traders; Abia also used for NPC panel trust rows via `scenarios.sh trust`). |

How to pick: the scenario needs (a) which buildings/NPCs exist, (b) whose squad. Non-Shay squads are good for
catching hard-coded names: pass `PLAYER=... MATE=...` and `stobe-auto select <player>`. Wrapper names with
`-fullbase`/`-squin` already pick their save. Never `build` a Biofuel Distillery (crashes the game).

## 5. Launch and pre-flight

- Lock: `C:\KenshiTestRuns\game.lock` (`kenshi-ctl.ps1 lock|release`); one runner per machine.
- Launch: `tools/automation/kenshi-ctl.ps1 launch -Save <save>` (windowed 1600x900 on DISPLAY2, background, input
  isolation; never focus the game or send real keys: input goes through the harness `key_inject`/`mouse_inject`).
  Check `kenshi-ctl.ps1 window` (foreground must not be Kenshi). `launch` archives the previous stobe.log/KenshiFP.log
  to `C:\KenshiTestRuns\logs\` (logs reset on every launch: copy what you need before relaunching).
- `stobe-say on`, `stobe-auto wait-world`, then pre-flight: installed DLL hashes, `stobe-say ping`,
  `stobe-auto state <player>` / `state <mate>`, goal status files terminal, no combat toward the squad,
  `stobe-auto hunger <mate> 250` before long runs. At game speed >10x run `tools/stobe-goal-watch.sh` (pauses on
  combat/KO toward the squad).
- Goals run on game time (nothing advances while paused), live outside the save and are dropped when an older save loads.

## 6. Writing a test (wrapper)

- One `tests/ingame/stobe/STOBE-<item>-<what>.sh`, sourcing `stobe-fight-lib.sh`; ends with exactly one
  `RESULT <row> PASS|FAIL <key evidence>` per row (status-file value, event line, inventory delta) + a log path on FAIL.
- A PASS means real game/server state changed (status files, stobe.log/stobe_goals.log lines, inventories, DB
  `eventlog` rows), never just what the NPC said.
- **Setup checks first** (shared helpers): fixture loaded, selected chars, live NPC names/handles, inventory space and
  items, worker awake at the bench with materials/power/job, game time advancing, raid protection. Bounded polls,
  not fixed sleeps. A failed setup ends that row with `FAIL setup: <reason>`; fix and rerun, never unchanged retries.
- **Mechanical vs live-model rows:** for logic (guards, thresholds, deal terms, pay-later, goal control) inject the
  model reply with the switches (`NEG_TEST_INJECT` etc., see existing wrappers) BEFORE the logic under test, prove
  the injection fired, check real state, restore switches on exit. A small separate live-model set checks that the
  prompt makes the model produce the intended reply (e.g. item 143: two backstory answers must not mention bread).
- **Compound tests (Shay's rule):** reproduce how a player actually hits a bug: several actions in a row (order a
  goal, interrupt with follow/attack/spar/chat, then "resume"; change your mind; clear all; toggle things between
  steps), and replay Shay's exact words/selection/order for a reported bug. Example:
  `STOBE-144-interrupt-resume-fullbase.sh`. Single isolated actions miss most of his bugs.
- Never weaken an assertion to get a PASS. Don't use Malzin's relationship as evidence of anything she "feels".

Useful existing wrappers to copy from: `STOBE-A8-bread-chain-fullbase.sh` (production chain goal),
`STOBE-generic-goals-fullbase.sh`, `STOBE-144-interrupt-resume-fullbase.sh` (interrupt/resume/clear),
`STOBE-A11-A12-heal-deal.sh`, `STOBE-21-paylater-breach.sh`, `STOBE-C31-C32-C45-C51-deal-guards.sh`,
`STOBE-NPCPANEL.sh`, `STOBE-DRAWN.sh`, `REL-SR18-SR19-fullbase.sh`. Scenario `.txt` files run via `stobe-auto run`.

## 7. Running a batch (one launch, many rows)

List file, one row per line: `name | save | player | mate | timeout-s | command`
(`save` = save name, `home` = auto-home + `scenarios.sh fresh` + select Shay, `-` = keep the current world):
```
144-fb   | kah-fullbase | Beaks | Avarek | 3000 | STOBE-144-interrupt-resume-fullbase.sh
21-fb    | kah-fullbase | Beaks | Avarek | 1500 | STOBE-21-paylater-breach.sh
C25      | home         | Shay  | Malzin | 1800 | STOBE-C25-renamed-surrender.sh
A8-grow  | kah-fullbase | Beaks | Avarek | 3000 | GROW=1 STOBE-A8-bread-chain-fullbase.sh
```
Group rows by save, pack as many as possible into one launch. The list must pass the dry run
(`tools/automation/dryrun.sh`, fake game, seconds; run-batch refuses otherwise). Start detached inside WSL
(the `bash -c '... &'` form dies silently; use a heredoc):
```
MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s <<'EOF'
setsid nohup bash /mnt/c/KenshiModding/tools/automation/run-batch.sh --launch kah-fullbase --stop \
  /mnt/c/KenshiTestRuns/<run>/list.txt /mnt/c/KenshiTestRuns/<run> >/mnt/c/KenshiTestRuns/<run>/start.log 2>&1 </dev/null &
sleep 5; pgrep -f run-batch.sh
EOF
```
Mark it in flight (`echo <out> > C:\KenshiTestRuns\inflight\<name>`) and check every <= 2 min with a background
`sleep 120; bash tools/automation/batch-health.sh <out>` (WSL /mnt paths): `HEALTH OK` = wait again, read
nothing; `HEALTH STALL` = act now (Kenshi gone, stuck on menu, no output 20 min: kill the step, log the bug,
recover, rerun the rest); `HEALTH DONE` = read `<out>/SUMMARY.txt`. run-batch relaunches a dead game up to 2 times
and restarts Kenshi when Windows commit headroom is low. Never edit a script a running batch uses.

## 8. Reading results and closing the loop

- Read only `SUMMARY.txt` (RESULT lines). For a FAIL open only its `excerpt=` file (the row's verdict lines + the
  error/goal/deal lines every log wrote during it); grep full logs only if the excerpt doesn't explain it.
- Useful evidence sources: `stobe_goals.log` (`WORK_GOAL accepted/switch`, `GOAL_JOB added/removed`,
  `ACTION_BRIDGE command=... result=`), stobe.log (`CHAT:`, `NPC_PANEL:`, `INV_TRANSFER:`, `DRAWN_WEAPON:`,
  `PERSONAL_FIGHT`/`PERSONAL_TRUCE`, `STT_RESULT`), DB dialogue + action lines:
  `select to_char(to_timestamp(localts),'HH24:MI:SS'),type,left(data,400) from eventlog where localts > extract(epoch from now())-3600 and type in ('inputtext','chat','action') order by rowid`.
  `result=ok` on an action only means it was dispatched: check the game state it should have changed.
- Classify each non-pass: product bug / setup failure / inconclusive / fix awaiting confirmation / Shay decision.
  Batch all fixes, rebuild once, restart once, rerun only what the changes invalidate. Loop until nothing testable is left.
- Log results in a run log `archive/test-run-<date>-m<n>.md`; delete passed items from `STOBE_full_test_plan.md`
  (next item number is in its header) and rows from `MASTER_TEST_PLAN.md`; update `testing/HANDOFF.md` "Right now".
- After the batch: `kenshi-ctl.ps1 stop`, release the lock, delete the `kah-*` copies and run dirs you no longer
  need (keep only cited evidence), `stobe-server.sh off` if nothing else needs it, `gfx-mods.sh on` reminder for Shay.

## 9. Gotchas
- Git Bash mangles `/mnt/...` paths and nested quotes: WSL heredocs + `MSYS_NO_PATHCONV=1`; don't run Windows
  `python3` from Git Bash (use WSL python3). Git Bash `/tmp` is not WSL `/tmp`.
- Logs reset on launch: when Shay reports a bug, save `stobe.log`, `stobe_goals.log` and the DB eventlog before relaunching.
- The LLM often picks a different action than intended (e.g. PAUSE for "clear everything", a wrong bench name):
  treat it as a bug and add a server guard + regression check, not a retry.
- Never `unload` a character that is still someone's fight/order target (crash). Never test on Shay's saves.
- If Shay says he is gaming on the 5090, stop all testing there; otherwise run batches in the background.
