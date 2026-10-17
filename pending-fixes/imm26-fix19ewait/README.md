# imm26-fix19ewait (row 19-e: silent 'wait' in stobeCommitmentResumeCheck)
Evidence: imm26-5090-i5-op20 (agents/out/imm26-5090-i5-op20/out-20261016-202130.md). Lane stobeserver.log 02:10:01-02:10:37: s4 (req_6ad2d8f9b7b1b) people list = [Shay] only
(Cind not in the 80u list; a Breth fight was running, Shay KO'd 02:09:48, recovered 02:10:00, combat_end 02:10:12), no "Trip resume injected"; s5 (req_6ad2d917adb4e) people = [Shay, Cind], a fresh Cind
gamedata snapshot (travel_lifecycle) had arrived 02:10:28, resume injected 02:10:37.

## Verdict: the wait is correct by design; no resume-logic defect
stobeCommitmentResumeCheck waits (transient, never fails the trip) for exactly four reasons: not_in_people (NPC beyond the 80u participant list), no_snapshot (no fresh receipt-bound native
travel_lifecycle snapshot, <= 120 gamets), absence_unverified (native has not proven the old trip work is gone), unavailable (incapacitated / in_combat). All four are safety gates, covered by
tests/imm26_trip_resume_regression.php section 4 ("transient misses: stay interrupted_by_load ... resumes on the next eligible turn") and the docblock. s4 happened during a real fight with Cind out of
range and before the next native snapshot, so a wait on that turn is the designed behaviour; the resume came on the next eligible turn (s5), which matches Shay's rule (next chat/bored turn once the NPC is
eligible, never immediately). Which of the four fired on s4 cannot be proven from the old log (silent); the new log line says it next run.

## Change (logging only, no verdict/state/action change)
lib/commitment_native_bridge.php: new stobeCommitmentSnapshotDiag(); wait verdicts carry a 'detail' array; stobeCommitmentResumeAction writes ONE INFO line
`Trip resume wait | {"npc","why","gamets","interrupted_gamets","resume_count","agreement_id", + inputs}` per wait. Inputs: not_in_people -> people_n, stored_serial; no_snapshot -> receipt_header,
snapshot (first failing gate: receipt_header|receipt_mismatch|no_lifecycle|serial_mismatch|bad_world|bad_generation|stale|ok), snapshot_serial, live_serial, world_id, generation, age_gamets, age_unix;
absence_unverified -> absent_flag, absence_age_gamets, absence_age_unix, absence_id_world_ok; unavailable -> reasons.
The pre-interrupt branch (reconcile has not entered interrupted_by_load after a load: unusable snapshot / other world than pinned / load_changed) writes a DEBUG `Trip resume wait` line with why=not_interrupted_yet + the same snapshot inputs.
Run: `python3 apply.py <tree-root> [--check]` then `python3 apply_test.py <tree-root>` (idempotent, *.bak-fix19ewait); test: `STOBE_DB_NAME=stobe_test php tests/imm26_trip_resume_regression.php` (83/83; 12 new checks fail on the unpatched lib).
Trees patched: /root/imm26/compose, /tmp/stobe-imm26-5090/site, -5090-i5/site, /tmp/stobe-sfo-manual/site. NOT patched: /tmp/stobe-imm26-5090-i4/site (ab2 pilot freeze; run apply.py on it after the pilot).
The live tree /var/www/html/StobeServer and /root/stobe-work/ss-merge do not carry the imm26 trip-resume code at all (lib/commitment_native_bridge.php there is the old 13.8 KB file, untracked in the stobe branch), so
they are NOT patched: imm26 server changes reach them only through the compose merge (same as fix02bxsrv f697886c).

## Recipe consequence (19-e)
Commit 2c74cf05 (s5 so the server ingests the native running receipt) stays right: rd_19e keeps s4 = first post-load chat turn (resume turn) and s5 = receipt-carrying line. The op20 s4 FAIL was an
environmental fight (Breth attacked, Shay KO'd 02:09:48) with Cind outside the 80u list, not a recipe/logic error: rerun on a calm lane. If a rerun still shows no resume on s4, read
`grep -a "Trip resume wait" <lane>/site/log/stobeserver.log` (why + inputs) before changing anything; a possible row-tool hardening (wait for no combat / Cind in the people list before s4) is left to the row owner.
