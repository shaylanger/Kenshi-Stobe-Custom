# NC8 = NC7 (EBA2200D) + relaxed Hunt ProvenWild (Shay ruling 2026-10-15, memory hunt-wild-animals-pass)

DLL: `NC8\Stobe.dll` SHA256 `140C2D4658F12B97585EC6B7668A39756E9ABE1990F3CF867A13BA73FE2432C3` (VS2010 x64, `RESULT NC-BUILD PASS objects=69`, build.out.txt). Gitignored; also `C:\KenshiTestRuns\imm26-nc8\build\out\Stobe.dll`. NOT installed anywhere.
Patch `nc8-over-nc7.patch` (`patch -p1 --binary` inside a dir holding NC7 `src` + `legacy-v1`; made with `diff -ruN a b`): `{src,legacy-v1}/ActivityPolicySupport.cpp` edited, `{src,legacy-v1}/ActivityWildVerdict.h` new. `nc8edit.py` = the edit script (WSL python3). Work tree `C:\KenshiTestRuns\imm26-nc8\{src,legacy-v1}`. Build (PowerShell, not Git Bash): `NC\build.ps1 -Out ...\imm26-nc8\build -SrcDir ...\imm26-nc8\src -LegacyDir ...\imm26-nc8\legacy-v1`.

## What changed
- Semantic: an animal is now PROVEN WILD (Hunt allowed) when its faction is not real (isNotARealFaction, fundamental OT_NONE), its platoon is animals-only and not a trader, and its squad is SQ_ROAMING with no base/home town, home building, occupied town, slaves or stuff. The squad-template requirements (template faction ref == current faction, animals/animals2 ref contains species, template non-null) are DROPPED as blockers and only appended to the log line as a non-blocking note (`templateFactionRef=0|1 templateSpeciesRef=0|1`, or `template=none`).
- Still refused: owned/slave animals (`owned_target`, unchanged, checked earlier), real faction, mixed or trader platoon, non-roaming squad, any town/home/building/slave/stuff ownership.
- Refusal reason split (was `animal_ownership_not_proven_wild`): `animal_not_wild_identity_unavailable` (faction/data/platoon/squad/gamedata unreadable), `animal_not_wild_real_faction`, `animal_not_wild_squad_type` (not animals-only / trader / not roaming), `animal_not_wild_ownership`. The first failing clause in that order wins; the code appears as `policyReason` in the prompt.
- One log line per refusal, rate limited to once per ~5 s per animal serial: `ACTIVITY_WILD_REFUSED reason=<code> serial=<n> species=<sid> faction=<sid> <template note>`.
- Decision logic is the pure header `ActivityWildVerdict.h` (`Stobe::ActivityWild::Verdict(WildFacts)`), unit-tested offline.

## Tests
`activity_wild_verdict_tests.cpp` (WSL: `g++ -std=c++03 -o /tmp/t activity_wild_verdict_tests.cpp && /tmp/t`, it includes `../src/ActivityWildVerdict.h`, so run it from `C:\KenshiTestRuns\imm26-nc8\tests` or copy the header next to it): `RESULT NC8-WILD-TESTS PASS 14/14`. The Kenshi-type glue (building WildFacts from Character/Platoon) is only compile-checked by the DLL build; it needs a live Hunt prompt to prove (a natural herd goat should now give suitable:true, policyReason "").

## components/STOBE
Not touched: `components/STOBE/src/ActivityPolicySupport.cpp` is the older lineage (no InspectMineLease/baseline etc.; same ProvenWild still present there), so copying NC's file would regress it. The same edit (new header + the ProvenWild block + the call at the animal branch) can be applied there separately.
