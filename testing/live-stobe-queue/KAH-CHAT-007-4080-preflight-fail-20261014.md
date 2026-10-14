# KAH-CHAT-007 — 4080 isolated i3 fresh preflight setup failure

- Result: `FAIL setup`
- Observed UTC: 2026-10-14 02:18:40
- Clearance: Agent Validator CLEARed this exact isolated i3 read-only preflight and one resolver row, with an immediate stop on any unverified pin or incoherent target. No retry is authorized by that clearance.
- Existing failures preserved: `KAH-CHAT-007-4080-session-read-setup-fail-20261014.receipt.md` and `KAH-CHAT-007-4080-route-fail-20261014.receipt.md` remain unchanged.
- Invocation: one call to `tools/automation/remote-bash-stdin-4080.ps1` using body SHA-256 `0E69B5C154799A35CEE0E463C09055F6D5040759D36F77B243EE3E9C611BE3DB`. Guarded wrapper SHA-256 `4183EFF82B0DF15E77C34DC1FD3A3101ED29334282551314762CB82FE3ECFC31`; synced `rig-env.sh` SHA-256 `A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D`.

## Fresh evidence

- Wrapper verified remote host `DESKTOP-NQQPA73` before starting Git Bash. The i3 route preflight passed: `KAH_INSTANCE=3`, `KENSHI_DIR=/c/KenshiInst/3`, `KDIR=/c/KenshiInst/3`, `KAH_DIR=C:\KenshiInst\3\mods\AutomationHarness`, and inbox/lock were clear.
- Instance marker reported `instance=3 synced=2026-10-13T12:00:52 from=C:\Program Files (x86)\Steam\steamapps\common\Kenshi`.
- Exactly one process matched the isolated i3 executable: PID 3452, `C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe`.
- On-disk Stobe SHA-256 matched `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`; on-disk AutomationHarness SHA-256 matched `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- i3 config matched `ServerHost=127.0.0.1`, `ServerPort=18084`. The private health endpoint returned HTTP-success JSON with `database=true`, UTF8, `database_schema_ready=true`, and `database_upgrade_required=false`. The observed PHP process arguments bound only `127.0.0.1:18084` to `/tmp/stobe-standalone4080/site`.

## Stop reason and boundary

The running-module query printed the expected i3 PID/path but emitted no `LOADED_MODULE=Stobe.dll` or `LOADED_MODULE=AutomationHarness.dll` lines; its output instead contained PowerShell `CLIXML`/`Preparing modules for first use` noise. Therefore the loaded-DLL pin was not established, even though the files on disk matched. The subsequent WSL session helper emitted no sanitized ready/generation result, and the `stobe-auto status` and input-isolation sections were never reached. The preflight was not complete.

This is a setup/evidence failure, not a product result. Per the stop rule, no `chars`, name/handle `where`, `stobe_ping`, chat, game input, focus/window change, queue mutation, game launch, save change, or service change was attempted. The temporary read-only preflight body and session helper hashes are recorded above and below; they did not modify the rig. The earlier receipt chain is preserved.

`RESULT KAH-CHAT-007 FAIL setup: loaded-module proof absent; session-generation and KAH world/isolation gates not reached; no resolver query issued`

Supporting one-shot session helper SHA-256: `C3620F171FE5096CC636AC593996342C66825CB3D29E46F9214C458AD826C30B`.

