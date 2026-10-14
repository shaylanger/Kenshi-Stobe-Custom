# 4080 portrait-absent read-only preflight packet

This packet is prepared locally only. It has not been executed and has not contacted the 4080, SSH, KAH, a game process, the queue, or a save. A separate exact review is required before any invocation.

## Pins

| Item | Path | SHA256 |
|---|---|---|
| Preflight body | `testing/live-stobe-queue/packets/4080-portrait-absent-preflight-20261014/body.sh` | `07B1FC69C6521B7B13500AB1478B145B6A5B10A5B626E51C63BFFF1EF4242DDD` |
| Invocation wrapper | `tools/automation/remote-bash-stdin-4080.ps1` | `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354` |
| Standalone i3 route guard | `tools/automation/rig4080/instance-route-preflight.sh` | `408FD0CAC181FEE32EF5DD0D0512CBD10494962CF1E251412EB900AF80E6EF51` |
| Route guard's sourced definitions | `tools/automation/rig-env.sh` | `A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D` |
| Target row | `tests/ingame/stobe/STOBE-PORTRAIT-ABSENT-4080.sh` | `A98D0E7A0D6F821DA647C1B7523983D882FE679B66C574E808AFE49888D5AF50` |
| Row helper | `tests/ingame/stobe/portrait-row-lib.sh` | `64780F2411742D407291CD775FFAE49DB58A6CA500A2BA1070E985A4A6A88784` |

The body verifies the route-guard and `rig-env.sh` hashes before invoking the standalone guard. The guard is run with stdout/stderr suppressed so route paths, inbox metadata, and its status text are not included in the receipt. The body does not source `rig-env.sh` itself.

## Receipt and read scope

On success, stdout is limited to:

- Kenshi PID and exact instance-3 executable path.
- `STOBE_LOADED=1`, established by a `tasklist /m Stobe.dll` query filtered to that PID, plus the SHA256 of the expected instance-3 on-disk `Stobe.dll`.
- The copied-save label and the SHA256 of its `quick.save`.
- The pinned row-script and row-helper hashes.

It does not read process command lines or enumerate the process's loaded-module collection. `stobe-auto status` is used only as a read-only source for the current world/save identity; its response is parsed but never printed. The body does not run the portrait gameplay row or change game, save, inbox, configuration, or queue state.

## Prepared invocation (not run)

After a fresh exact review authorizes it, the wrapper call would be:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-portrait-absent-preflight-20261014\body.sh
```

The wrapper targets SSH alias `4080` (`DESKTOP-NQQPA73`). The body sets `KAH_INSTANCE=3` and calls the standalone i3 route guard. The copied save expected by the read-only identity check is `kah-stobe-travel-validation-20261013`; its `quick.save` is read from the current user's local Kenshi save directory. This packet is only local preparation: it provides no fresh runtime route, process, loaded-Stobe, or save proof.
