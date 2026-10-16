# NC24 = NC23 + row 25-b: natural mine product resolved through node -> functionality -> produces (imm26-sfW)

Tree `C:\KenshiTestRuns\imm26-nc24` (NC23 tree + `nc24edit.py`; edits src/ and legacy-v1/ ActivityPolicySupport.cpp). BUILD OK objects=69, SHA256 `23F17E78BF0DFC6C852E11F261214357EE92637B6EBBE6A8C71E4FBCB5C52795` (`NC24\Stobe.dll`, gitignored). NOT installed.
Cause (imm26-fxC): Iron Resource 42248-gamedata.base -functionality-> Ore mine 1869 (type BUILDING_FUNCTIONALITY) -produces-> Raw Iron 1866 (ITEM). NaturalOutput only read ITEM refs of the node's own record, so `natural_product_unresolved`.
Fix: for each ref of type BUILDING_FUNCTIONALITY read its `produces` list (ITEM refs, bounded 32); how label `gamedata:functionality>produces`. ResolveNaturalProduct unchanged (1 item OK, several = natural_product_ambiguous). ACTIVITY_MINE_EXACT_DIAG lists= now also prints ` fn=<sid>[list:n,...]` for each first-hop functionality record.
Tests: `offline-tests.sh` (WSL) -> RESULT nc24-offline PASS (source test `components/STOBE/tests/cpp/mine_functionality_produces_source_tests.py`: 10 failures on NC23, 0 on NC24; also reruns the NC23 offline suite).
Unproven offline: the clause after the product resolves (lease/output polling for a node without an _NV_updateOutput hook; NC12 README section 1).
