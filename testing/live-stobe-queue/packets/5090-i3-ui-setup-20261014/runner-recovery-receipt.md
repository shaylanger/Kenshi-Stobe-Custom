# 5090 instance-3 runner recovery, 2026-10-14

Owner: `/root/5090_runner_guard_recovery`; scoped owner `5090c-ui-setup-20261014`.

At 10:19:49 local, actual runner PID 40364 (parent 67392, PowerShell, created 2026-10-13 14:06:27) matched official `rig-runner.ps1` and lane `5090c`. This was a genuine idle runner, not a regex false positive. Its state reported idle/no work, there were no `.cur`/`.tail` or lane queued/running rows, and its only child was conhost PID 91372. No D3 game was running. Main PID 86884 was protected and untouched.

Executed documented `rig-runner.ps1 -Stop -Rig 5090c`: confirmed runner stopped and marked stopped. This stops only the idle isolated runner; it does not stop an active batch or main game.

Executed original atomic `acquire-lock.ps1 -Apply`: `LOCK_CREATED owner=5090c-ui-setup-20261014 instance=3`.

Executed exact stage script SHA256 `FD5BDCC96B33C69708706605FCB76E9547329D915ED34B68DE464C0D63A6FC13` with copied source fixture `C:\Users\Shay\AppData\Local\kenshi\save\kah-fresh-start-5090-copy-20261013-152239`: `STAGED ONLY instance=3 game_launched=false backend_started=false`. Rollback snapshots retained in D3.

Launch script SHA256 `3AF013D74575AD3E00D7CB1F04D5D9AA0DFEEF9FEC22389E0F207298C66936A3` failed before game start because `tools/automation/kenshi-ctl.ps1` line 113 has an invalid DISPLAY1 regex (`Not enough )'s`). Launch-file snapshots already exist and must be preserved. Minimal tooling repair assigned to `monitor_regex_fix`; independent technical review required before scoped launch retry. UI/gameplay row is not yet executed and has no PASS claim.

Next: technically review monitor regex fix, repeat original launch guards with existing snapshots, launch same isolated instance/copy in background, then exact world/input checks and reviewed KAH-INT-001 row.

Monitor recovery: original regex repaired and pure `monsel` PASS 19; direct constrained retry then correctly refused DISPLAY1 because actual attached hardware is Samsung SAM0B49. `EnumDisplayDevicesW` mapping proves DISPLAY2 is ASUS AUS32B1 (authorized), DISPLAY3 is SNY05D1 and avoided. To avoid accidental fallback, auxiliary instance 2/3 explicit DISPLAY1/DISPLAY2 requests now both require exact selection. Pure `monsel` PASS 24; current ctl SHA256 `FDE7F4A10A46BCDB27A7482F6F495030EB99B37D1C3EF93835466942C573A665`. Independent technical review pending for exact DISPLAY2 retry. Existing launch snapshot is preserved; original launch wrapper still pins the older ctl and must not be rerun unchanged.
