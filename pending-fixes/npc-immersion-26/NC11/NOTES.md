# NC11 = NC10 (E1302B77) + diagnostic log lines only (no behaviour change)

DLL: `NC11\Stobe.dll` SHA256 `C66D75E8DB36B9FF7170D36D75F3E0ECD83929FF8E9EDA812B2178DD0A6B4033` (VS2010 x64, `RESULT NC-BUILD PASS objects=69`, build.out.txt). Gitignored; also `C:\KenshiTestRuns\imm26-nc11\build\out\Stobe.dll`. NOT installed anywhere.
Patch `nc11-over-nc10.patch` (diff -ru over `src` and `legacy-v1`); `nc11edit.py <root>` = anchored edit script (run on an NC10 tree). Work tree `C:\KenshiTestRuns\imm26-nc11\{src,legacy-v1,tests}`. Build: `NC\build.ps1 -Out ...\imm26-nc11\build -SrcDir ...\src -LegacyDir ...\legacy-v1` (PowerShell).
Tests: `NC10-WILD-TESTS PASS`, `NC9-RING-TESTS PASS 6/6` (offline, unchanged code). Strings verified present in the DLL. Compile-proof only for the glue (game types).

All lines go through the normal STOBE `Log()` and are rate limited (about 5 s). Items 1 and 3 are in both `src` (namespace Activity) and `legacy-v1` (ActivityV1Legacy; line carries `.v1`).

## Log lines (grep the STOBE log, e.g. `grep -E "ACTIVITY_(MINE_EXACT|CAMP|HOSTILE)_DIAG"`)

1. Row 25-b, ActivityPolicySupport.cpp, when MineSourcePermitted returns exact_output_unavailable (per node serial):
`ACTIVITY_MINE_EXACT_DIAG node=<serial> entry=MineSourcePermitted[.v1] item=<product item id or empty> bsid=<building sid> special=<int> destroyed=<0|1> production=<0|1> product=<0|1> productItem=<sid|null> productSection=<0|1> inventory=<0|1> [storedItems=<n> badIdx=<i> badItem=<sid> nullItem=<0|1> inOutputSection=<0|1>] clause=<...>`
clause (first failing check, same order as ExactSection): special_function_not_27, destroyed, no_production_building, no_production_item, product_item_null, product_item_id_empty, product_item_id_mismatch, product_section_null, building_inventory_null, section_inventory_mismatch, stored_item_null_or_nodata, stored_item_foreign_id (a stored item whose id != product item), stored_item_not_in_output_section, all_items_ok_unexpected.

2. Row 14-c, ActivityRuntimeBindings.cpp ProposalFacts (camp-discover), two lines:
`ACTIVITY_CAMP_DIAG stage=zones actor=<serial> discoverOk=<0|1> formalTownBases=<n> actorPos=x,y,z actorSees faction=<sid> factionName=<n> notReal=<0|1> | zone<i>=<knownName> sid=<town sid> type=<townType> radius=<r> dist=<actor horizontal dist> actorInside=<1|0|-1(read failed)> ...` (up to 6 zones; one per actor per 5 s; formalTownBases=0 or discoverOk=0 = no scene possible).
`ACTIVITY_CAMP_DIAG stage=<group_targets_rejected|no_formal_zone|no_zone_qualifies|zone_ambiguous> actor=<serial> target=<serial> targetName=<n> faction=<sid> factionName=<n> notReal=<0|1> groupTargets=<n> formalTownBases=<n> relActorToTarget=<float> | zone<i>=<name> actorInside=<..> targetInside=<..> membersInside=<k>/<resolved> ...` (per hostile ClearGroup target, per target 5 s; stage names which gate rejected the group: no fixed hostile group, no TownBase at all, no zone holds actor + all targets, or more than one zone does).

3. Row 26-a, VerifyGrant when requester_now_hostile is raised (per actor):
`ACTIVITY_HOSTILE_DIAG ns=Activity[.v1] agreement=<id> actor=<serial> actorName=.. actorSerial=.. actorFaction=<sid> actorFactionName=.. actorRelToOther=<rel> actorAttackTarget=<serial|0> actorInCombat=<0|1> requesterName=.. requesterSerial=.. requesterFaction=.. requesterFactionName=.. requesterRelToOther=.. requesterAttackTarget=.. requesterInCombat=.. actorEnemyOfReq=<0|1> reqEnemyOfActor=<0|1>`
Reading: faction relation negative with that faction = faction enmity; attack target equal to the other serial = active fight; in-combat flag shows a fight on either side.
