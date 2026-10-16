# NC15 = NC14 (65953AA0...) + camp town identity keyed on the GameData sid (row 14-c)

Root cause (NC12 diag, op9c): every TownList entry has `TownBase.handle.serial == 0` (`ACTIVITY_CAMP_TOWNS_DIAG raw=378 accepted=0 handle_serial_zero:378`), so `ValidFacts` and `ExplainFacts` rejected all towns and the camp catalog was empty.
Fix (src\ActivityCampNativeAdapter.h, src\ActivityCampTownReader.cpp only):
- new `SidKey(sid,x,z)` = nonzero FNV-1a 64 over `sid@round(x),round(z)` (sid alone is not unique); `ReadFacts` sets `runtimeSerial = SidKey(...)` when the handle serial is 0 (nonzero handle serials still key on the handle).
- `ValidFacts`: `runtimeSerial != 0 && (handleSerial == 0 || runtimeSerial == handleSerial)`; handle fields are informational. Formal types (Outpost 1, SlaveCamp 5, Military 6), radius, name, sid and finite checks unchanged.
- diag: `ExplainFacts` returns `ok_sid_keyed` instead of `handle_serial_zero`; the TOWNS_DIAG line carries `nc15=sid_key`. Live check: `ACTIVITY_CAMP_TOWNS_DIAG ... accepted=>0 ... reasons=ok_sid_keyed:N`, then ACTIVITY_CAMP_DIAG formalTownBases>0.

DLL: `NC15\Stobe.dll` SHA256 `9EABD486FBF8F996D2153DDA5FD8FE057DBC55AF93D1DCAA433A046841CE5748` (`RESULT NC-BUILD PASS objects=69`, build.out.txt). Gitignored. NOT installed anywhere; the 5090-i5 operator installs it.
Offline tests (WSL g++ -std=c++14 against the NC15 src): `nc15_sidkey_tests.cpp` `RESULT NC15_SIDKEY_TESTS PASS checks=20 failures=0`; the existing `N1\tests\tests-activity-adapter.cpp` and `activity-camp-native-adapter-20261014\ActivityCampNativeAdapterTests.cpp` still pass (exit 0).
Reproduce: copy `C:\KenshiTestRuns\imm26-nc14\{src,legacy-v1,tests}` to a new tree, `python3 nc15edit.py <tree>` (asserts anchors), build with `NC\build.ps1 -Out <tree>\build -SrcDir <tree>\src -LegacyDir <tree>\legacy-v1`. Work tree `C:\KenshiTestRuns\imm26-nc15`. Patch: `nc15-over-nc14.patch`.
After the catalog works the offer still needs a hostile member Cind can SEE inside the camp borders (ActivityRuntimeBindings.cpp:629-631); live recipe in imm26-unblock-gated\latest.md row 14-c.
