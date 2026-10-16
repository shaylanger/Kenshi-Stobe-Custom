# NC23 = NC22 + row 26-a Attack cleanup + sfP (row 26-d Hunt grant import) (imm26-sfW)

Tree: `C:\KenshiTestRuns\imm26-nc23` (NC22 tree + `imm26-sfP/sfPedit.py` + `nc23edit.py`). Build: `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc23 -Out ...\build` -> BUILD OK objects=69, SHA256 `00864789988CD50B4B298E1DBC932ACC4A4668725C2FC872F799E04D5FD7EC50` (`NC23\Stobe.dll`, gitignored). NOT installed.

26-a (nc23edit.py, ActivityNativeExecutor.cpp CancelOwned): Attack cleanup completes once our captured order is no longer in the order list (we removed it, or the engine ended it); NativeEnded (goal/action/movement idle) is kept only for Travel/WorkResource. Cause: the NPC's own combat AI keeps fighting a retaliating target, NativeEnded never turned true, Release stayed pending, Hunt stuck phase 4, no terminal report. New log per false return: `ACTIVITY_CANCEL_DIAG id= branch=actor_mismatch|no_orders_receiver|capture_mismatch|cancel_refused|native_not_ended` (5 s per id+branch).
26-d (sfP): ImportGrant no longer demands live sight of the offer's exact animal; logs ACTIVITY_GRANT_SOURCE_DIAG on reject.
Tests: `offline-tests.sh` (WSL; baseline source test fails on NC22 with 12, passes on NC23; also runs sfP offline + NC22 suite) -> RESULT nc23-offline PASS. `components/STOBE/tests/cpp/attack_cleanup_source_tests.py`.
Note: Utils.h is not included (it pulls windows.h min/max macros that break std::min/max in this file); Log is forward-declared at global scope and called as `::Log`.
