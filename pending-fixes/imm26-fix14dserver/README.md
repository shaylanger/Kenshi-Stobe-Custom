# imm26-fix14dserver (row 14-d: "Unexpected activity fields" on ClearGroup)
Evidence: imm26-5090-i5-op21 (agents/out/imm26-5090-i5-op21/out-20261016-210034.md), lane stobeserver.log 02:52:47, req_6ad2e2f8eadf4.
The rejected intent: {"kind":"ClearGroup","sourceId":...,"targetSerial":526123040,"discoveryRef":"activity-proposal:3318359296:27","campZoneRef":{candidateId,scopeDigest},"agreedTargets":[5 serials]}.

## Verdict: the prompt is wrong, the adapter is right
- campZoneRef is ALREADY in the adapter allowlist (object {candidateId,scopeDigest}, ClearGroup only). It is not what was rejected.
- The offending fields: `targetSerial` as a TOP-LEVEL key (not in the allowlist), `discoveryRef` as a bare string (adapter needs an object {candidateId,targetSerial}; it would then fail 'Missing discovery reference'), and `routeRef` missing (required object).
- Cause: lib/activity/activity_prompt.php said "discoveryRef candidateId/targetSerial for the activity source" and never said these are object keys; the model flattened them.
- The earlier 14-d reject (01:06, boundedQuantity on ClearGroup) is a different, already fixed issue (fix14dsrv normalisation in propose()).

## Change
Only lib/activity/activity_prompt.php: discoveryRef / routeRef / campZoneRef are named as OBJECTS with their exact keys, plus one complete ClearGroup example (no quantity). Adapter and validation untouched (no loosening; the lane-specific huntA1/A2 edits in the 5090/i5 adapters are not touched either).
Run: `python3 apply.py <tree-root> [--check]` then `python3 apply_test.py <tree-root>` (idempotent, *.bak-fix14dserver).
Test: `STOBE_DB_NAME=stobe_test php tests/imm26_wpE_activity_kinds_regression.php` (62/62 patched; 55/55 unpatched; the 3 prompt checks fail on the unpatched prompt, the 4 adapter-strictness checks pass on both). Other activity tests (camp-scope, u4, u4b, sf26e, wpR1, inv26) identical to baseline (all pass).
Trees patched: /root/imm26/compose, /tmp/stobe-imm26-5090/site, -5090-i5/site, /tmp/stobe-sfo-manual/site. NOT patched: /tmp/stobe-imm26-5090-i4/site (ab2 freeze), 4080 sites (4080 operator), live tree and ss-merge (imm26 reaches them through the compose merge).
