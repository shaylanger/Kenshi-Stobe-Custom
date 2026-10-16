# NC14 = NC13 (B1BB3665) + the missing SightDiag call site (diagnostic only, NO behaviour change)

NC13 defined `ProposalTrace::SightDiag()` but never called it (0 ACTIVITY_SIGHT_DIAG lines in two goat runs).
NC14 calls it first thing in `~ProposalTrace()` (src\ActivityRuntimeBindings.cpp:528), before `if(emitted) return`, so it fires whenever pass 0 ran and no kind=Hunt candidate was emitted, even if a Mine candidate was. SightDiag self-gates (`huntEmitted||!scanned` return) and keeps the 1 per 5 s per actor rate limit. New members `diagActor/diagRequester` set right after both characters resolve.

DLL: `NC14\Stobe.dll` SHA256 `65953AA0745F7A43281D50EF1D1B6D79FF6E6F496927BCFE3B5128AC5FE5C95D` (`RESULT NC-BUILD PASS objects=69`, build.out.txt). Gitignored. NOT installed anywhere.
Reproduce: copy the NC13 tree (`C:\KenshiTestRuns\imm26-nc13\{src,legacy-v1,tests}`), `python3 nc14edit.py <tree>` (asserts anchors), build with `NC\build.ps1 -Out ... -SrcDir ...\src -LegacyDir ...\legacy-v1`. Work tree `C:\KenshiTestRuns\imm26-nc14`. Patch: `nc14-over-nc13.patch` (diff -u).
Log format: see NC13\README.md.
