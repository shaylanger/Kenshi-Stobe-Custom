# KAH-CHAT-007 4080 preflight setup failure — session reader path conversion

- Timestamp: 2026-10-14 02:49:29 UTC.
- Outcome: `RESULT KAH-CHAT-007 FAIL setup: WSL session-generation reader received a mangled script path; session/world/actor gates remain unverified.`
- Local reviewed caller SHA-256: `4E396F981514E70C8ADDB3587CEA98624EB9FE77F94783E61B7CF291A4206E19`. Remote helper SHA-256 was freshly verified as `121956C2A61A4B59854BB12AC414C788A15B9A599D05680D98F78971D705A31F`.
- Fresh route checks passed for isolated i3 (`C:\KenshiInst\3`, instance 3, inbox clear). Loaded-module probe passed for PID 3452 at `C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe`: Stobe on-disk SHA `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`; Harness on-disk SHA `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`. INI points to `127.0.0.1:18084`; private backend health reports database/schema ready.
- The exact reviewed caller exited 0 but its captured output stopped after backend process listing; it did not print session-generation or KAH gate headers, so it is not counted as a completed preflight.
- A separate read-only completion pass stopped at session generation. WSL reported `python3: can't open file '/mnt/c/Users/Shay/C:/KenshiModding/pending-fixes/rig4080-validation/chat007-session-read-once.py'`; exit code 2. Git Bash path conversion mangled the intended `/mnt/c/KenshiModding/...` argument. The fail-closed body did not proceed to KAH world status, isolation, FP state, speaker, or fresh actor roster.
- Thus fresh session-generation, world/time/pause, input-isolation, and actor/target gates are unknown. No actor or resolver query, chat, game input, queue mutation, focus/window change, or service change occurred. CHAT-007 is not running. Prior receipts remain unchanged.
- Stop here. Fix the session-reader invocation through exact review before any further preflight; do not issue the resolver query on these incomplete gates.
