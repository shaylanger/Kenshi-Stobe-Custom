# 4080 isolated lane (instance 3) runbook, 2026-10-15

Lane: `C:\KenshiInst\3` (KAH_INSTANCE=3), private backend `127.0.0.1:18084` inside the 4080's WSL `DwemerAI4Skyrim3` (root `/tmp/stobe-standalone4080/site`, DB `stobe_standalone4080_test`, socket `/tmp/stobe-standalone4080/socket`, port 15434), private model Qwen3-4B on `127.0.0.1:18095` (llama-server, task `StobeStandalone4080Model18095`, replies take 35-60 s). Never touch the 5090, instances 1/2 or `/var/www/html/StobeServer`.

## Readiness receipt (2026-10-15 11:04-11:14 local, 4080 clock)
- Kenshi PID 16156, `C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe`, started 11:04:06, save `kah-imm26-4080` (fresh copy of `kah-stobe-4080-standalone-active`), `paused=0 speed=1.0`.
- Loaded: Stobe `E60752C828AB096C7856F79490EC4FB16E015F40887338199471B0E53A0938C6` (the reviewed eight-fix release, same as Shay's 5090 Main Steam), Harness `974DBA03...3025D`, KenshiFP `0E4C44E3...C355`, PG `BAFB8C31...5549`.
- Backend health ok, schema ready, session `ready`, manager_ready_matches=true. Lock `game-3.lock` owner rig4080.
- Round trip: `stobe_ping` -> `mode=chat speaker=Shay nearest=Cind [Hungry Bandit]`; `stobe_say` to Cind -> `ACTION_EXEC: SAY [Cind ...] (NPC)` about 40-57 s later; DB `eventlog` rows type=chat delivery_state=spoken.

## Fixture roster
- `kah-imm26-4080` (current): Shay #971557632/1 (Nameless), Malzin #2740478464/2 (Nameless, 2.6 km away at -51011,1580,3646), NPC Cind [Hungry Bandit] #2529907200/2 (Traders Guild Hive Soldier Drone, about 100 m from Shay). Good for: one-to-one NPC chat, proposals, travel with Cind. Shay starts hungry (295); heal/feed as needed.
- Other i3 saves: `kah-eight-item-4080-squin` (Beak/Kint squad, Squin; eight-item rows), `kah-stobe-4080-standalone-active` (original, keep clean), `kah-stobe-travel-validation-20261013`, `kah-stobe-a0f8`, `kah-stobe-slim-*`, `kah-fresh-start-4080-copy-20261013` (fresh start), `kah-fp*` (FP only). Make a new `kah-` copy per test (folder copy in `C:\KenshiInst\3\save`).

## Helper (5090 Git Bash)
`source /c/KenshiModding/testing/live-stobe-queue/4080-imm26-lib.sh` gives `i3` (stdin body on the i3 route, preflight first), `i3w` (stdin body as WSL root on the 4080), `i3_ready`, `i3_say <target> <text> [wait_s]`, `i3_sql "<select>"`, `i3_selftest`.

## (a) Check readiness
`i3_ready` (status, stobe_ping, game time, PID + module hashes, backend health). Session: `i3w <<<'php /mnt/c/KenshiTestRuns/standalone4080/standalone4080-session-read.php'` (needs `source /tmp/stobe-standalone4080/env.sh` first) must show `status:ready`, `manager_ready_matches:true`.

## (b) Send an utterance, read the reply
`i3_say "#2529907200/2" "Got any news from the road?"` (target by `#serial/index`; plain "Cind" fails with `target not found`). The speaker must be a conscious squad member: if `resolved_speaker` is not the one you want, check `stobe-auto stobe_state Shay` for `unconscious` and run `stobe-auto wake Shay`, then `stobe-auto select Shay`.

## (c) Evidence
- Game: `/c/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log` (CHAT_SEND_STAGE, ACTION_EXEC: SAY, TEST_INBOX).
- Server: `i3w <<<'tail -n 5 /tmp/stobe-standalone4080/site/log/chat_llm_full_capture.log'`; also `context_sent_to_llm.log`, `output_from_llm.log`, `php_error.log` in the same dir.
- DB: `i3_sql "select rowid,type,left(data,150),delivery_state from eventlog order by rowid desc limit 10"` (tables: eventlog, speech, memory, social_*, stobe_*).

## (d) Hot-swap
- Stobe.dll (game closed): stage the DLL in `C:\KenshiTestRuns\staged\` on the 4080, then `C:\KenshiModding\pending-fixes\4080-eight-item-i3-install-20261014\install-stobe-4080-i3.ps1` (`-Action Plan`, then `Apply`; pinned to the E607 candidate, so for a new build copy it and change the pins; rollback via `-Action Rollback`). Do not write through junctions.
- Server PHP (private backend only): `python3 /mnt/c/KenshiTestRuns/standalone4080/standalone4080-install-overlay.py <source_dir> <manifest.json> <label> [--verify-only]` in WSL root (verifies hashes, backs up to `/tmp/stobe-standalone4080/<label>-preinstall-backup`, writes only under `site/`). PHP serves it after about 1 min opcache.

## (e) Stop / restart
Stop: `ssh 4080 powershell -NoProfile -ExecutionPolicy Bypass -File C:\KAH\ctl.ps1 stop -Owner rig4080 -Instance 3`. Launch: same with `launch -Save kah-<copy> -Owner rig4080 -Instance 3` (takes about 2 min, run it detached, log to a file). Keep `C:\KenshiTestRuns\inflight\4080-imm26` while the game runs, delete it after stop. Backend start after a 4080 WSL stop: `Start-ScheduledTask StobeStandalone4080Backend` (runs pg + php + bridge + manager; `sleep infinity` keeps WSL alive).

## (f) Gotchas hit
1. The 4080 WSL distro was Stopped (backend down, no listener on 18084) at the start; start task `StobeStandalone4080Backend`, health ok after about 12 s.
2. `stobe-auto` has no `ping`/`state`/`actors`; use `status`, `stobe_ping`, `stobe_state <target>`, `chars <radius>`.
3. The saved Shay was KO'd (recovery coma): Stobe skips unconscious speakers, so replies came as if from Malzin 2.6 km away. `stobe-auto wake Shay` fixed it.
4. Gluing a body onto the preflight line without a newline breaks its first command (the lib adds the newline).
5. `@nearest` resolves relative to the chosen speaker, not Shay.
6. `C:\StobeBuild\out\Stobe.dll` (E64C6593) is an older build and `Stobe.fixes-candidate.dll` is unreviewed; NOT installed. The installed E607 is the reviewed release.
7. `NETWORK_ERROR 12002` and `CHAT_THREAD: Empty stream response` lines in stobe.log are benign after a reply.

## Lane i4 (second isolated lane, built 2026-10-15 by imm26-lanes-4080)
Lane definitions (single source): `tools/automation/lane-defs.4080.json` (copy on the 4080: `C:\KenshiTestRuns\lane-i4\`). i4: `C:\KenshiInst\4` (KAH_INSTANCE=4, harness `C:\KenshiInst\4\mods\AutomationHarness`), save `kah-imm26-4080-i4` (fresh copy of `kah-stobe-4080-standalone-active`), backend `127.0.0.1:18085` (WSL root `/tmp/stobe-standalone4080-i4`: own site copy, own Postgres cluster port 15435 / db `stobe_standalone4080_i4_test`, own bridge 18097, own manager, own activity key), marker `C:\KenshiTestRuns\inflight\4080-imm26-i4`, lock `game-4.lock`, window parked at 3840,0 (1280x720, windowed, gfx low, 60 fps cap). Same Stobe.dll as i3 (E60752C8). Chat target: Cind `#2529907200/2` (same fixture roster as i3).
- Backend: `wsl ... bash /mnt/c/KenshiTestRuns/lane-i4/stobe-lane-backend.sh i4 status|start|stop|provision`; Windows task `StobeStandalone4080I4Backend` (`stobe-lane-task.ps1 -Lane i4 -Action register|start|status`) runs `supervise` (keeps WSL children alive).
- Game prep (closed game): `lane-prepare.ps1 -Lane i4` on the 4080 (Stobe.dll, ini ports, own transport key, fixture save, window pos, kcfg test low). Launch/stop: `ssh 4080 powershell -File C:\KAH\ctl.ps1 launch -Save kah-imm26-4080-i4 -Owner rig4080 -Instance 4` (stop: same with `stop`). Drive with `export RIG=4080 KAH_INSTANCE=4; . rig-env.sh; stobe-auto ...`.
- LLM: ONE file `C:\KAH\lane-llm.json` (+ `lane-llm.key`), applied to every lane DB by `tools\automation\lane-llm-apply.ps1 -Rig 4080 [-Lane i3|i4|all] [-Check]` (no restart). Now DeepInfra DeepSeek V4.1 Flash; local config kept in `C:\KAH\lane-llm.local.json`. Chat reply ~7-8 s.
- Independence proof: `tools\automation\lane-isolation-check.ps1 4080` (from the 5090) prints `RESULT lane-isolation <item> PASS|FAIL`. Known FAILs until lane i3 is restarted: `windows` (i3 kenshi.cfg Full Screen=Yes) and `graphics` (i3 gfx not low, no 60 fps cap): run `kcfg.ps1 test -Instance 3 -Gfx low` with i3 stopped, then relaunch.

## Lane i4 additions (imm26-lanes-4080b, 2026-10-15)
- Helpers in `4080-imm26-lib.sh`: `i4`, `i4w`, `i4_say <target> <text> [wait_s]`, `i4_sql "<select>"`, `i4_ready`, `i4_selftest` (same behaviour as the i3 ones; i4 route preflight checks KDIR=/c/KenshiInst/4 and an empty inbox). Verified live: i4_ready, i4_sql, i4_say to Cind.
- `lane-isolation-check.ps1` now finds the lane game pids through the CIM process table (Get-Process .Path is null over ssh) and no longer miscounts a single process (a lone object has no .Count). With both games up: install-dirs/npc-world PASS with real pids/saves; only `windows` and `graphics` FAIL until i3 is restarted windowed+low (note sent to the i3 operator's inbox).
- Provider-fixture route for i4: `pending-fixes/4080-lane-i4-fixture-profile/patch-i4-fixture-profile.py` adds profile `4080-i4` (php 18085, db stobe_standalone4080_i4_test, pg 15435, socket /tmp/stobe-standalone4080-i4/socket, STOBE_TEST_INSTANCE_ID=4) to the PRIVATE i4 site copy only (applied; backup `.pre-i4profile`; i3/live untouched). The same two-part change (profile + per-profile `instance_id` in the instance gate) is needed in the source file before it is released; reprovisioning i4 from i3 loses it, re-run the patch. The fixture env (STOBE_TEST_REPLY_MODE=private-i3, STOBE_TEST_INSTANCE_ID=4, STOBE_TEST_PRIVATE_ROUTE=4080-i4, STOBE_TEST_REPLY_ENABLE=1, PRIVATE_SITE_ROOT, REPLY_DB_NAME/SOCKET_DIR, FIXTURE_FILE, CLAIM_DIR) must be set on the i4 php/manager by whoever runs fixture rows (not set by the lane).
- Lane-count measurement (4080: Ryzen 5 3600X 6C/12T, 32.7 GB, 16 GB VRAM), i3 running 06/13 rows + i4 doing 4 chats (one per ~10 s) over 90 s, sampled every 5 s: RAM 13.0-13.2 GB (40%), VRAM flat 6.5 GB (40%), GPU 19-43%, CPU 43-73% (avg ~60%). Chat traffic (DeepInfra) adds no visible load; CPU is the game render loops (i3 is still full gfx and uncapped; i4 low + 60 fps cap). A 3rd lane adds about +5-6 GB RAM (~19 GB, 58%) and +3 GB VRAM (~9.5 GB), CPU would reach ~85-95% and slow all games. Recommendation: 2 lanes; a 3rd only after i3 is windowed low + 60 fps cap, and only if CPU stays < 75% with 3 up.
