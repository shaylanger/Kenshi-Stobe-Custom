# NC5 = NC4a (2D1CC322) + N5b: abandoned_in_danger held while the partner is knocked out (row 13-b)

DLL: `NC5\Stobe.dll` SHA256 `25252267D3C07BE39E176685EE4CEEBF5A3933DCC12BF8B9204FB7F6B9A380B4` (VS2010 x64, `RESULT NC-BUILD PASS objects=69`, build.out.txt, built with `NC\build.ps1 -Out C:\KenshiTestRuns\imm26-nc5\build -SrcDir ...\imm26-nc5\src -LegacyDir ...\imm26-nc5\legacy-v1`). Gitignored; also at `C:\KenshiTestRuns\imm26-nc5\build\out\Stobe.dll`. NOT installed on any lane.
Patch: `nc5-over-nc4a.patch` (`diff -ruN a/src b/src`; from `NC` over the NC4a tree with `patch -p1 --binary`, CRLF files; verified: patched NC4a src == `C:\KenshiTestRuns\imm26-nc5\src`). Composed tree `C:\KenshiTestRuns\imm26-nc5\src` (+ `legacy-v1`).
Delta (4 files): `src/N2Policy.h`, `src/NativeAttention.h/.cpp`, `src/main.cpp`.

Behaviour
- Before: `N2AbandonWatch` posted `abandoned_in_danger` the moment the 20 s far-timer proved it, even with the partner still knocked out.
- Now `AbandonTracker::Observe` HOLDS the proven event when the partner state is knocked_out (returns false, stores it per (leaver,partner)); downed/bleeding_out partners are conscious and still fire at once.
- `main.cpp` polls the held pairs every scan (2 s) before the normal observe loop: `PollPending(leaver, partner, present, alive, conscious, nowSec, &ev)`:
  - partner conscious again (alive, not unconscious; may still be downed) -> POLL_POST_WOKE: post with the episode's facts (`partner_state` stays `knocked_out`, evidence_id `abandon:<leaver>:<partner>:<episode start>` unchanged, dedupe intact);
  - hold reaches `HoldSeconds()` = 900 game seconds (or the game clock went backwards) while the partner is alive and still KO -> POLL_POST_TIMEOUT: posted anyway (the server N5a path accepts a KO native episode), so the fact is never lost;
  - partner dead, or both not readable past the hold -> POLL_DROP, no post (log `N2_ABANDON: held event dropped`).
  - The held entry survives the partner's episode being erased by the wake (NotePartnerState PS_NONE); `Reset()` (load/new game) clears it.
- Post body moved into `N2PostAbandon()` (unchanged logic: both must be player-faction, witnesses, `observer_saw_leaving`, same facts, no agreement_id); the log line gets `held=<game s>`. New `NativeAttention::IsAlive/IsConscious`.
- Server pairing: N5a (ee28e15, agreement_id optional) deployed; with this build the normal 13-b path is a conscious victim, so the effect applies without the waived conscious check.

Tests (`tests/n2_logic_tests.cpp`, full file; `tests/n2_before_after.sh`): new `TestAbandonHold` (hold on KO, no fire while KO, release on wake incl. after the episode was erased, once only, timeout post, dead/absent drop, downed/bleeding fire at once, two leavers, Reset, clock reversal). Existing KO fire checks switched to DOWNED/BLEEDING_OUT (KO is now deliberately held). Before (NC4a src): 45 compile errors (no PendingCount/PollPending). After: `N2 logic tests: 151 passed, 0 failed` (g++ -std=c++11 -Wall). Full NC suite on the NC5 src (`tests/run.sh` from NC4a, unchanged): 20/20 RESULT PASS, `SUMMARY failures=0`.
In game (not run): row 13-b = squad member KO'd, another squad member walks > 30 m for 20 s after being within 25 m; expect NO N2_ABANDON line / server event until the partner wakes, then one `N2_ABANDON ... state=knocked_out ... held=<n>` and a `abandoned_in_danger` effect row. Squad members only (N5c not built).
