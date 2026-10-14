# 5090 instance-3 UI discovery receipt

Owner: `/root/5090_i3_discovery_operator`. Read-only setup discovery; no gameplay PASS.

Executed pinned `discover-ui.ps1` SHA256 `E751422A7748E10DC2FE742CEF32A77537D1B6772841336CF3B98D479AAE6C58` through WindowsPowerShell `-NoProfile -ExecutionPolicy Bypass -File`. Default attempt exited 1 at CIM process enumeration (`HRESULT 0x80041003`, Access denied). Same exact script under standard approved sandbox escalation exited 0.

- Host: `DESKTOP-JFLPK99`.
- Only observed Kenshi process: PID `86884`, `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\kenshi_x64.exe`. Instance 3 was not running.
- `D:\KenshiInst\3\instance.txt`: SHA `70ABDF168262E70F179F8A3D5E1FBDC0BFB8A17CAF8A18A2AC2A6B2E0842F6A9`; contents `instance=3 synced=2026-10-11T20:27:44 from=D:\Steam\steamapps\common\Kenshi`.
- `D:\KenshiInst\3\settings.cfg`: SHA `C267C67F89D78E6DB2C1D68E521760CCD86F27AAA87DAF369594330ECE26886B`; `User save location=0`.
- `D:\KenshiInst\3\mods\Stobe\Stobe.dll`: SHA `40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D`.
- `D:\KenshiInst\3\mods\AutomationHarness\AutomationHarness.dll`: SHA `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- `D:\KenshiInst\3\RE_Kenshi\mods\Stobe\StobeCustom.ini`: SHA `B834118D8597A8C738220712B36F01398FAD1F69CE7C728B7B42E2CA4A8AB972`; `ServerHost=127.0.0.1`, `ServerPort=8083`, `ChatHotkey=/`. This is shared-route configuration and must be changed through the separately reviewed isolated staging operation before launch.
- `D:\KenshiInst\3\RE_Kenshi\mods\Stobe\Stobe.ini`: missing.
- Checked instance root, `mods`, `mods\Stobe`, `RE_Kenshi`, `RE_Kenshi\mods`, `RE_Kenshi\mods\Stobe`, `save`: all non-reparse. Checked files were also non-reparse.
- `C:\KenshiTestRuns\game-3.lock`: absent.
- TCP listeners on private port `18086`: zero. No endpoint request was issued.
- `C:\Users\Shay\AppData\Local\kenshi\save\Fresh start\quick.save`: SHA `B4C9EBB34A8C2BF49CAE053A3388C4104030AAF8FBE84B77A2C5B3AD22E27DBE`.
- Existing copied fixture `C:\Users\Shay\AppData\Local\kenshi\save\kah-fresh-start-5090-copy-20261013-152239\quick.save`: same SHA. These are quick-save hashes, not complete directory manifests.

No files on the rig were changed; no game launch, UI input, service start, or backend request occurred. Next action belongs to the setup owner: review these facts against the exact stage candidate, gather any remaining bounded facts, and stage only after required authorization and gates.
