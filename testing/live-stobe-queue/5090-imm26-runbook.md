# 5090 isolated imm26 lane (instance 3) runbook, 2026-10-15

Second STOBE test lane next to the 4080 one (`4080-imm26-runbook.md`). Isolated: game `D:\KenshiInst\3` (KAH_INSTANCE=3, lock `C:\KenshiTestRuns\game-3.lock` owner `rig5090-imm26`), private backend `127.0.0.1:18086` in the 5090 WSL `DwemerAI4Skyrim3` (root `/tmp/stobe-imm26-5090`: `site/` = copy of `/root/imm26/base`, PG cluster port 15437 socket `/tmp/stobe-imm26-5090/socket`, DB `stobe_imm26_5090`, env `/tmp/stobe-imm26-5090/env.sh`), private model Qwen3-4B (llama-server, Windows 127.0.0.1:18098, GPU, alias `qwen4b`) reached through a WSL bridge 127.0.0.1:18099 (`bridge.py`, curl.exe hop). Replies take about 4-8 s. No API keys anywhere (`local-test-no-auth`). Never touch Shay's Steam install, instances 1/2, `/var/www/html/StobeServer`, ss-merge, the live DB (5432) or ports 80/443.
Files: `C:\KenshiTestRuns\imm26-5090\` (`provision.sh`, `config.php`, `start.sh`, `bridge.py`, `launch.log`, `in\Stobe-E607.dll`, `model.pid`).

## Installed
- Stobe E607 `E60752C828AB096C7856F79490EC4FB16E015F40887338199471B0E53A0938C6` at **`D:\KenshiInst\3\mods\Stobe\Stobe.dll`** (this, not `RE_Kenshi\mods\Stobe\`, is the loaded plugin path: proven by the process module list; `RE_Kenshi\mods\Stobe` holds ini/logs/goal files and a stray old DLL). OgreMain_x64.dll on i3 is byte-identical to the 4080's (7D3888D2...), so no ABI problem (BC9D2F91 stays out). Backup of the previous files: `D:\KenshiInst\3\imm26-backup-20261015T123904\` (old `Stobe.mods.dll` = BC9D, `StobeCustom.ini`).
- `RE_Kenshi\mods\Stobe\StobeCustom.ini` = the 4080 lane's ini with `ServerPort=18086` (TalkRadius 80, TTS off).
- Harness `974DBA03...`, KenshiFP `0E4C44E3...` (same as 4080); PG DLL differs (7CA14E1F vs 4080 BAFB8C31), irrelevant.
- Save: `kah-imm26-5090` = fresh copy of the 4080's `kah-stobe-4080-standalone-active` (taken over ssh with tar). Clean checkpoint after setup: `kah-imm26-5090-ready`.

## Bring-up (what was done, in order)
1. Preflight: no Kenshi, `game-3.lock` stale (owner `5090c-ui-setup-20261014`, pid gone) -> overwrote with owner `rig5090-imm26`.
2. Model: `Start-Process C:\KenshiTestRuns\standalone5090gpu\llama-server.exe -m qwen4b.gguf --port 18098 --alias qwen4b -ngl 99 ...` (hash-checked against `server.identity.json`; pid in `model.pid`).
3. Backend: `wsl ... bash /mnt/c/KenshiTestRuns/imm26-5090/provision.sh` (refuses to overwrite), then `start.sh` (bridge, php -S 18086 with 4 workers, manager loop). Health: `curl http://127.0.0.1:18086/health.php`.
4. Install DLL + ini + save copy (PowerShell), take lock, `$env:KAH_INSTANCE=3; $env:KAH_OWNER='rig5090-imm26'; kenshi-ctl.ps1 launch -Save kah-imm26-5090 -Monitor DISPLAY2 -Gfx low` (detached, ~90 s). DISPLAY1 is refused for instance 3 by kenshi-ctl; DISPLAY2 is primary 2560x1440. Window is background, input isolation ON.
5. Marker `C:\KenshiTestRuns\inflight\5090-imm26` while the game runs; delete after stop.

## Helper (Git Bash on the 5090)
`source /c/KenshiModding/testing/live-stobe-queue/5090-imm26-lib.sh`: `i3` (stdin body in WSL with RIG=5090 KAH_INSTANCE=3, inbox preflight), `i3w` (+ private backend env), `i3_ready`, `i3_say "#serial/idx" "text" [wait_s]`, `i3_sql "<select>"`, `i3_selftest`. Same names as the 4080 lib. Game log: `/mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log`. Server logs: `/tmp/stobe-imm26-5090/site/log/` and `/tmp/stobe-imm26-5090/{php,manager,bridge-current}.log`.

## Round trip proof (12:41 local)
`i3_say "#2529907200/2" "Hello Cind, how are you holding up?"` -> `ACTION_EXEC: SAY [Cind [Hungry Bandit]] ... (NPC)` 4 s later; DB `eventlog` rows type=chat (PC row, then NPC rows `spoken`).

## Fixture roster (kah-imm26-5090)
Shay #971557632/1 (Nameless), Cind [Hungry Bandit] #2529907200/2 (Traders Guild Hive Soldier Drone, about 20-40 m), Holy Nation Outlaws Felk #3229492224/6, Opajil #3172973568/4, Boralin #2610839808/7, Liplom #3058959872/3, Gills #2681396480/2 nearby at load. Setup applied after load: teleport the 5 outlaws to -51011 1580 3646, `wake Shay`, `health Shay 100`, `hunger Shay 100`, `select Shay`.

## Start / stop
Stop: `KAH_INSTANCE=3 KAH_OWNER=rig5090-imm26 kenshi-ctl.ps1 stop`, then delete the inflight marker (lock stays `rig5090-imm26` or `release`). Model: `Stop-Process -Id (Get-Content ...\model.pid)`. Backend after a WSL restart: `wsl ... bash /mnt/c/KenshiTestRuns/imm26-5090/start.sh` (postgres must be started by it: it does).

## Gotchas
1. The saved world loads with Shay KO'd by blood loss and 5 hostile Holy Nation Outlaws on top of him (same as 4080's KO gotcha, plus the attackers): without the setup block, Stobe replies come while combat events flood.
2. Target by `#serial/index`; `stobe-auto` has no `ping`/`state`: use `stobe_ping`, `stobe_state`.
3. The WSL `stobe-auto` honours `KAH_INSTANCE=3` through `rig-env.sh` (KAH_DIR=D:\KenshiInst\3\mods\AutomationHarness); never run it without the lib preamble or it hits instance 1.
4. Other agents' stale material for this lane (`/tmp/stobe-standalone5090i3`, 5090-i3-* scripts) is a different, older private backend (port 18086 was theirs, PG15436): it was NOT running, port 18086 was free; do not start both.

## Lanes i4 and i5 (added 2026-10-15 by imm26-lanes-5090b; i3 above is unchanged)
Registry (single source of truth): `C:\KenshiTestRuns\lanes\lanes-5090.json` (dirs, ports, DBs, roots, markers, locks, window slots, video mode, frame cap).

| lane | game dir | instance / lock owner | backend | PG / DB | WSL root | save | window |
|---|---|---|---|---|---|---|---|
| i3 | D:\KenshiInst\3 | 3 / rig5090-imm26 | 18086 | 15437 / stobe_imm26_5090 | /tmp/stobe-imm26-5090 | kah-imm26-5090 | DISPLAY2 1296x759 at -2560,0 (1280x720, 60 fps) |
| i4 | D:\KenshiInst\4 | 4 / rig5090-imm26-i4 | 18087 | 15438 / stobe_imm26_5090_i4 | /tmp/stobe-imm26-5090-i4 | kah-imm26-i4 | DISPLAY2 1040x807 at -1260,0 (1024x768, 30 fps) |
| i5 | D:\KenshiInst\5 | 5 / rig5090-imm26-i5 | 18088 | 15439 / stobe_imm26_5090_i5 | /tmp/stobe-imm26-5090-i5 | kah-imm26-i5 | DISPLAY1 1040x807 at -4400,400 (1024x768, 30 fps) |

- Build: `kenshi-instance.ps1 sync -Instance <n>` then `lane-install.ps1 -Lane i4|i5` (copies i3's Stobe E607 / KenshiFP / mods.cfg / ini with its own ServerPort, removes the live activity key, copies the fixture save to the lane's own name), then `bash tools/automation/lane-backend.sh provision|start|stop|status <lane>` (own PG cluster, php -S, manager loop; the old bridge is unused), then `lane-llm-apply.sh <lane>` (LLM = DeepInfra per `C:\KenshiTestRuns\lane-llm.json`; `--check all`).
- Launch (one lane at a time, detached ~90 s): `touch C:\KenshiTestRuns\inflight\5090-imm26-i4`; then in PowerShell `$env:KAH_INSTANCE='4'; $env:KAH_OWNER='rig5090-imm26-i4'; $env:KAH_GFX='low'; $env:KAH_VIDEO_MODE='1024 x 768'; $env:KAH_FPS='30'; $env:KENSHI_MONITOR='DISPLAY2'; kenshi-ctl.ps1 launch -Save kah-imm26-i4 -Monitor DISPLAY2 -Gfx low`; i5 the same with 5 / `rig5090-imm26-i5` / `kah-imm26-i5` / `DISPLAY1`. Then `lane-window.ps1 -Lane i4 -Action place` (SetWindowPos, never focuses) and `-Action show`.
- **Video mode: never 800x600** (Kenshi rewrites it to 4096x2160 and the window fills the screen). Use >= 1024 wide (1024x768 is a listed mode). The lane window outer size is client + 16 x 39.
- Stop (per lane): same env vars + `kenshi-ctl.ps1 stop`, then `release`, delete `inflight\5090-imm26-iN`.
- Helpers (Git Bash): `source /c/KenshiModding/testing/live-stobe-queue/5090-imm26-lanes-lib.sh` -> `i4 i4w i4_ready i4_say "#serial/idx" "text" [wait_s] i4_sql "<select>" i4_mark i4_since` and the same for i5 (generic `lane_run|lane_runw|lane_sql|lane_say <n> ...`); `lanes_selftest`. Fixture roster is the same as i3 (`kah-imm26-5090-ready` copy), Cind is `#2529907200/2`.
- Isolation proof: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\lane-isolation-check.ps1 5090` (dispatches to `lane-isolation-check-5090.ps1 [-Lanes i4,i5]`): 18 `RESULT lane-isolation <item>` lines + SUMMARY, exit 1 on any FAIL, read-only. Items: install-dir logs harness-channel saves backend-port database php-server wsl-tmp-env activity-key stobe-ini-route windows markers-locks shared-mutable log-crosstalk gfx-cap input-isolation llm-config not-live. A lane that is not running is checked on config/files only. Run it before every batch that uses two lanes at once and after any lane rebuild.
- Load with 3 games up (measured 15:23, worlds loaded, all idle apart from the autonomous world): RAM 47.1 GB total, **8.3 GB free** (each Kenshi ~3.9 GB working set / 5.6 GB private, WSL vmmem 4.4 GB; before i4/i5 free was 18.4 GB) -> **3 lanes is the ceiling; a 4th would leave about 3 GB free: do not**. CPU 32% average, GPU 11% and 5.4 of 32.6 GB VRAM (Chrome/other apps included). Frame rates at the caps: i3 58 fps of 60, i4 28.8 of 30, i5 28.5 of 30.
- Gotchas: (1) `lane-window.ps1 place` resizes to the registry w/h: keep the registry slots at the real outer size (1040x807 for a 1024x768 mode). (2) 3 lanes + a Shay session would exceed the RAM headroom: Shay gaming = stop all lanes. (3) The lane has no game-side `activity-transport.key` on purpose (the Steam one is deleted by lane-install); the isolation item accepts absent-or-own only. (4) `kenshi-ctl.ps1 launch` also prints "kenshi.cfg set to windowed 1600x900" before the gfx step applies the lane video mode: the final cfg is what `gfx-cap` checks.
