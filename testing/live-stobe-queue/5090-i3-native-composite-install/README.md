# 5090 i3 native composite install packet — preparation only

This is the guarded install/rollback packet and its future-use regression suite. The operator reports that the composite install completed under Windows PowerShell 5.1 (receipt suffix `24bf49`). A prior direct PowerShell 7 attempt (receipt suffix `d847b4`) rejected the timestamp as stale and made no DLL mutation. Do not rerun this installer against the already-installed build; use the current operator receipt/runtime state. The `ReceiptTime.psm1` correction below is for future packet use and does not rewrite either receipt or modify the game.

## Bound install identity

- Instance: `D:\KenshiInst\3` (`KAH_INSTANCE=3`)
- Target: `D:\KenshiInst\3\mods\Stobe\Stobe.dll`
- Expected preinstall SHA-256: `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`
- Owner/lock: `5090c-ui-setup-20261014` / `C:\KenshiTestRuns\game-3.lock`
- Save: `kah-5090c-ui-20261014`
- Display for a later background test launch: `\\.\DISPLAY2` (ASUS)
- Existing D3 game PID 26972, GPU PID 97588, and adapter PID 29152 are protected by the current instruction. The installer refuses while a D3 game process exists; it never stops one. PID 86884 is not an install precondition.
- Preserve private HTTP 18086 and its GPU/adapter services. These scripts do not inspect, edit, stop, or start them.

## Candidate and receipts

The composer has not yet supplied final composite pins. Supply the final immutable candidate DLL and its independently reviewed SHA-256, plus a fresh boundary receipt path and SHA-256, only when those are available. The receipt must be JSON with `status: "CLEAR"`, `instance: 3`, the exact target path, `candidate_sha256` equal to the supplied pin, `owner: "5090c-ui-setup-20261014"`, `game_stopped: true`, a non-empty `review_verdict` identifying the independent review, and ISO-8601 `issued_utc`. The install script rejects a receipt older than ten minutes. It reads the timestamp's original JSON string token through `ReceiptTime.psm1`; do not cast `ConvertFrom-Json`'s timestamp property back to string, because PowerShell versions/local timezones can reinterpret it. The scripts compare all fields; the receipt is not a substitute for current-state guards.

Default operation is plan-only. `install-composite.ps1 -Apply` is the only staging/install entry point. It validates the exact instance marker, owner lock, stopped D3 process, target path and baseline hash before creating a unique backup. It hashes a same-volume temporary candidate and uses atomic `File.Replace`; it rechecks both installed candidate and backup hashes and emits a receipt. Any mismatch refuses without overwriting an unexpected target.

`rollback-composite.ps1` is a compare-and-swap rollback: it requires D3 stopped, the expected lock owner, target still equal to the installed candidate pin, and backup still equal to the original AEF pin. It uses `File.Replace` and retains the displaced candidate in the backup directory. It will not overwrite a target that has drifted.

## Later launch recipe (not executed here)

Only after the install receipt is reviewed and the game-test boundary is authorized, use the current wrapper in a fresh terminal:

```powershell
$env:KAH_INSTANCE = '3'
$env:KAH_OWNER = '5090c-ui-setup-20261014'
$env:KENSHI_MONITOR = '\\.\DISPLAY2'
& 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1' launch -Save 'kah-5090c-ui-20261014' -Monitor '\\.\DISPLAY2'
```

Do not add `-Play`: the wrapper's ordinary test launch uses background mode and input isolation, whereas `-Play` is disallowed for instance copies. `restart` invokes `stop` internally and is not a substitute for the required fresh boundary. The wrapper applies the test mod-order dialog guard. Recheck actual monitor presence and the process/lock state at that later boundary.

## Packet status

Historical packet preparation has been superseded by the operator's completed install receipt. This documentation/test update made no external writes. The install and rollback scripts remain guarded tooling; any later use requires freshly pinned candidate/review/boundary receipts and a separate authorized boundary.

## Timestamp regression

Run the synthetic regression in both Windows PowerShell 5.1 and PowerShell 7. It checks UTC `Z`, a nonzero offset, fractional seconds, and fail-closed handling of missing, offset-free, duplicate, and impossible timestamps:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-receipt-time.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\test-receipt-time.ps1
```
