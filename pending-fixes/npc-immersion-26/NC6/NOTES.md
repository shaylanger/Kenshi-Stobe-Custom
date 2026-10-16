# NC6 = NC5 (25252267) + abandon observation gap on the real clock (row 13-b)

DLL: `NC6\Stobe.dll` SHA256 `3ADDE488907B46ECD47DA76354A7BD091C9EA63EFBE8D2C48B68EAE5D174259D` (VS2010 x64, `RESULT NC-BUILD PASS objects=69`, build.out.txt; built with `NC\build.ps1 -Out C:\KenshiTestRuns\imm26-nc6\build -SrcDir ...\imm26-nc6\src -LegacyDir ...\imm26-nc5\legacy-v1` copy). Gitignored; also at `C:\KenshiTestRuns\imm26-nc6\build\out\Stobe.dll`. NOT installed on any lane.
Patch: `nc6-over-nc5.patch` (`patch -p1 --binary` over the NC5 src; verified IDENTICAL to `C:\KenshiTestRuns\imm26-nc6\src`). Delta: `src/N2Policy.h`, `src/main.cpp`.

Root cause (confirmed from source): `AbandonTracker::Observe` reset `farSince` when `nowSec - lastSeen > GapSeconds()` (10 GAME s), but `N2AbandonWatch` scans every 2 s REAL (main.cpp, `nowTick - g_lastAbandonScanTick < 2000`) and `nowSec` is game time. At speed 0.5 (game ~12x real) a scan step is ~25 game s > 10, so every scan reset the 20 game-s far-timer and `N2_ABANDON` never fired. Demo against NC5 semantics (25 game s per scan, 200 scans): `fires=0`.
The NC5 hold (HoldSeconds 900 game s, PollPending) never used the gap, so it is not affected by this bug; it only runs after the proof, which this bug prevented in game.

Fix: new `Observe(..., nowSec, realSec, out)`; the gap test uses the real clock (`GetTickCount()/1000.0` from main.cpp; `GapSeconds()` stays 10, now REAL seconds = 5 missed scans). Far-timer (20 game s), episode, hold stay in game time. Real clock going backwards (tick wrap) or game clock going backwards also restarts. The old 7-arg `Observe` remains as a wrapper (realSec = nowSec) so legacy callers/tests are unchanged.

Tests (`tests/n2_logic_tests.cpp`): new `TestAbandonSpeed` (game speed 0.5x/1x/4x/12x with a 2 s real scan: fires exactly once at the expected scan, `seconds>=20`, no repeat; 25-game-s step fires; a >10 s real pause still restarts; real/game clock reversal restarts; KO hold at 12x released on wake). `N2 logic tests: 180 passed, 0 failed` (was 151). Full NC suite on the NC6 src (`NC/tests/run.sh`): 20/20 PASS, `SUMMARY failures=0` (n2_entity 15 passed).
In game (not run): row 13-b at speed 0.5: partner downed, another squad member within 25 m then > 30 m for 20 game s -> one `N2_ABANDON` line.
