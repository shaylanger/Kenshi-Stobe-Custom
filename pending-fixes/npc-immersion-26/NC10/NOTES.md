# NC10 = NC9 (B171683E) + Hunt homeBuilding relaxation + Mine "No Faction" unowned

DLL: `NC10\Stobe.dll` SHA256 `E1302B7777BB0DC524351B8466550758B4B29716C8CD858CA56EE08D17180651` (VS2010 x64, `RESULT NC-BUILD PASS objects=69`, build.out.txt). Gitignored; also `C:\KenshiTestRuns\imm26-nc10\build\out\Stobe.dll`. NOT installed anywhere.
Patch `nc10-over-nc9.patch` (diff -ru a b over `src` and `legacy-v1`: ActivityWildVerdict.h, ActivityPolicySupport.cpp; apply with `patch -p1 --binary` inside a dir holding the NC9 tree). `nc10edit.py <root>` = anchored edit script. Work tree `C:\KenshiTestRuns\imm26-nc10\{src,legacy-v1,tests}`. Build: `NC\build.ps1 -Out ...\imm26-nc10\build -SrcDir ...\src -LegacyDir ...\legacy-v1` (run from PowerShell, not Git Bash, or the backslash paths are mangled).

## 1. Hunt (ActivityWildVerdict.h)
i5 op6 flags (NC9 log): natural and spawned wild herds all have baseTown=0 homeTown=0 homeBuilding=1 occupiedTown=0 slaves=0 stuff=0. `Verdict()` ownership clause is now `baseTown || homeTown || occupiedTown || slaves || stuff` (homeBuilding removed). It is only reached after the faction clause (`factionNotReal && fundamentalNone`) and squad clause (animalsOnly, not trader, roaming), so it only affects animals-only roaming non-trader squads in a not-real faction. homeBuilding stays in `WildFacts` and in the ACTIVITY_WILD_REFUSED `Flags()` log. Real-faction animals, traders, mixed platoons, non-roaming squads and the other five flags still refuse.

## 2. Mine (ActivityPolicySupport.cpp MineSourcePermitted)
`b->getFaction() && b->getFaction()!=actor->getFaction()` now also requires `!b->getFaction()->isNotARealFaction()` (same call WildRefusal uses), so a node in "No Faction" is treated as unowned; real other-faction nodes still return resource_owned_by_other_faction. Glue only (game types): proven by the DLL compile plus a live Mine proposal (expect no resource_owned_by_other_faction for the iron node in No Faction).

## Tests (offline, WSL g++ -std=c++03)
`tests/activity_wild_verdict_tests.cpp`: `RESULT NC10-WILD-TESTS PASS` (homeBuilding alone -> proven wild; homeBuilding does not rescue real faction/trader; homeBuilding+homeTown still owned; other NC8/NC9 rows unchanged). NC9 ring tests still PASS 6/6 (ApproachRing untouched). components/STOBE not touched (older lineage).
