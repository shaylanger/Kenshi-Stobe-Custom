# 4080 i3 minimal readiness snapshot — 2026-10-14 05:39 UTC

**Outcome: incomplete setup evidence (not gameplay).** The single Agent-Validator-cleared retry reached isolated instance 3 and exited 0, but the marker check did not verify equality and the output includes a `sha256sum` error. Do not use this receipt to clear any gameplay row; do not retry this one-shot.

- Exact command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\pending-fixes\rig4080-validation\native-minimal-readiness-4080i3.sh`
- Body SHA-256: `5A76439541A343BFFCB6A975ADDB68D388A7C8EF2371A8759FF331AAE947EB38`
- Wrapper SHA-256: `14172A542326B6058630FF2D2CEB21E3A369900352E9E4A69F0332A3BD718E47`
- Packet SHA-256: `80FC6B85EFEFB4B0F4F0CD0518A02EB02A548F8F66B48417DBF64725DD8EAAAB`
- Process exit: `0`
- Route: `RESULT 4080-I3-ROUTE PASS`, isolated `C:\KenshiInst\3`, inbox clear.
- Game: PID `3452`; world `newgame:Empire Citizen`, paused `0`, speed `1.0`; native time day 10, 03:39; input isolation `on`, injected keys/mouse `0`; `focused=1`.
- Loaded module files: Stobe on-disk SHA-256 `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`; AutomationHarness on-disk SHA-256 `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- Actors: 11 within 300; nearest external actor Kiva `[Sand Ninja Genin] #2659912192/16`, distance `8.0`.
- Snapshot terminal line: `CAPTURE_COMPLETE native_setup_snapshot_only=1 session_auth=UNVERIFIED chat=0 resolver=0 physical_input=0 game_world_mutation=0`.
- Marker output: `_present=true` twice, hashes blank, `marker_bytes_equal=false`; output also contained `sha256sum: '"/"': No such file or directory` and PowerShell CLIXML interleaving. Therefore session identity remains unverified despite process exit 0 and the snapshot completion marker.
- Actions excluded: no chat, resolver, order, physical input, save, queue, service, install, restart, or gameplay row.
- Next: diagnose the marker/hash output from local artifacts only; obtain fresh exact review and row-specific Validator clearance before any further rig contact. Separately, this receipt is setup evidence only and does not count as an in-game test.
