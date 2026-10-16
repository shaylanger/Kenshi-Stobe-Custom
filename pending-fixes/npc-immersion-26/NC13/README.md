# NC13 = NC12 (9BEA63E7) + ACTIVITY_SIGHT_DIAG (diagnostic only, NO behaviour change)

DLL: `NC13\Stobe.dll` SHA256 `B1BB36650D95C2D6BF62F871DDCD2E56B4EAF16550106B03CA254CC1ADEC008E` (`RESULT NC-BUILD PASS objects=69`, build.out.txt). Gitignored. NOT installed anywhere; the 5090-i5 operator installs it.
Work tree `C:\KenshiTestRuns\imm26-nc13\{src,legacy-v1,tests}` (copy of NC12 tree + `python3 nc13edit.py <tree>`); patch `nc13-over-nc12.patch` (`patch -p1` in an NC12 tree's src dir parent; only `src/ActivityRuntimeBindings.cpp`).
Build: `NC\build.ps1 -Out C:\KenshiTestRuns\imm26-nc13\build -SrcDir ...\src -LegacyDir ...\legacy-v1`.

## Log (grep `ACTIVITY_SIGHT_DIAG` in stobe.log)
Written from ProposalFacts when pass 0 (character sphere) ran and NO Hunt candidate was emitted; max once per 5 s per actor.
- Summary: `actor= requester= hour=<game hour 0-24> sphereCharacter= animals=<animal characters in the sphere> logged=<<=8> sightDrops= typeDrops= emitted= huntEmitted=0 actorSeen=<actor sensory seen.size> actorVision= actorVisionTown= requesterSeen= requesterVision=`
- One line per animal (cap 8): `ACTIVITY_SIGHT_DIAG animal actor= serial= dist= dead= ko= canISee= canIHear= data=1 dCanSee= dCanHear= fov=` (`data=0` = getDataFor NULL; `sd=null` = actor has no SensoryData).
Reading: `animals=0` => goats not in the 600 u / 96 cap sphere; `animals>0 canISee=0` => sight gate drops them (look at data/dist/hour).
