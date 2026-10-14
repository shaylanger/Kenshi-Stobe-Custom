# Isolated 5090 instance-3 acquire/stage receipt

- Operation: exact validator-cleared acquire-lock.ps1 -Apply on 2026-10-14.
- Script SHA256: 967BDC6A07D4BD67864D1EF794E2BB6F9A1AACAEDFB0EA0CA643E3D55EBE2A58; stage script FD5BDCC96B33C69708706605FCB76E9547329D915ED34B68DE464C0D63A6FC13 verified before operation.
- Standard sandbox escalation accepted; command exited 1.
- RESULT 5090-I3-UI-STAGE FAIL setup: existing instance-3 runner (acquire-lock.ps1 line 9).
- Exact guard stopped operation before FileMode.CreateNew; no lock acquired, no stage command executed, no DLL/config/save mutation, no launch/services.
- Next step: independently identify actual instance-3 runner PID/liveness read-only, then separately review recovery. Do not retry unchanged, take over lock, or stop any process by inference.
- This was setup, not gameplay validation.
