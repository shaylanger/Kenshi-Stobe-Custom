# imm26-fix26fcamp: camp-qualified ClearGroup resumes after save/load (row 26-f)

Root cause (inv26f report `C:\KenshiTestRuns\agents\out\imm26-inv26f\out-20261016-210817.md`): `ActivityResume.php:115` compared the OLD epoch's
`campZone {candidateId, scopeDigest}` with the fresh candidate's by strict equality. Both are world+session scoped natively (new on every load), so the match
could never succeed; and `ActivityAgreementAdapter::resume()` would have copied the OLD zone into the new grant, which native `ImportGrant` rejects.

Fix (server only, native unchanged):
- `stobeActivityResumeSelect`: a camp-qualified agreement only requires the fresh candidate to still carry a `campZone` array (the exact `agreedTargets` list stays the identity); the selected fresh zone is returned as `campZone`.
- `stobeActivityResumeForChat` passes it to `resume(..., ?array $campZone)`.
- `ActivityAgreementAdapter::resume()` validates it (`keys`, `opaqueZoneId` v1:+48 hex, `sha256`) and rebinds `agreement.campZone` before `ground()`; missing/malformed zone throws and the job stays pending (the existing catch in `stobeActivityResumeForChat`). The digest check still runs on the stored (old) record first.
- Non-camp ClearGroup, Hunt, Mine: unchanged.

## Files
- `apply.py <site root> [--no-tests]`: anchor-asserted (each anchor exactly once), idempotent (`ALREADY`), edits `lib/activity/ActivityResume.php`, `lib/activity/ActivityAgreementAdapter.php`, `tests/imm26_wpR1_activity_resume_regression.php`.
- `deploy.sh [--check] <site root>...` (WSL): backup tar next to the site (`bak-pre-fix26fcamp-<site>.tar.gz`), apply.py, `php -l`, SHA256. Refuses `/var/www/html/*` and ss-merge.
- Rowtools (`testing/live-stobe-queue/imm26-assert/rowtools/`): `reloadcheck_a.py` (`same_terms` compares campZone presence only; new clause `camp_zone_rebound`: continuation zone present, v1:+48 hex id, 64 hex digest, id differs from the old one),
  `reloadcheck_sfe.py` (26-f: SETUP-FAIL when `reseat.txt` has `SCENE-LOST`), `reloaddefs_sfe.sh.candidate` (new `rs_probe26f`, called at the end of `rs_reseat26f`: chars 600 / where per serial / relation -100 before-value
  into `reseat.txt`, last line `RESEAT-OK n of n` or `SCENE-LOST only k of n ...`), selftest fakes `reloadscen_sfe.py` / `reloadfake_sfe.py` / `reload-sfe-selftest.sh` (zone-not-rebound, zone-dropped, scene-lost, probe evidence).
  The candidate was built on the existing `reloaddefs_sfe.sh.candidate` (includes fix26f4): swap at a row boundary, never mid-run: `cp reloaddefs_sfe.sh.candidate reloaddefs_sfe.sh`.

## Deployed (this ticket)
`/root/imm26/compose`, 5090-i5 `/tmp/stobe-imm26-5090-i5/site`, 5090-i3 `/tmp/stobe-imm26-5090/site`, `/tmp/stobe-sfo-manual/site`. NOT 5090-i4, NOT the live tree, NOT ss-merge. Not yet on the 4080 lane sites.

## 4080 apply (i4 / i3 lane site, then row rerun)
Copy `pending-fixes/imm26-fix26fcamp/` to the 4080 WSL (scp), then `bash deploy.sh --check <lane site>` and `bash deploy.sh <lane site>` (lane sites are `/tmp/stobe-imm26-4080-*/site`; opcache serves the change after about 1 min, no game restart).

## Operator rerun
`bash rowtools/reload-run-sfe.sh 26-f <lane> --save kah-imm26-4080-i4h` (alias `reload-run-sfe.sh 26-f <lane>`), after the swap of `reloaddefs_sfe.sh.candidate`.
PASS needs old_record_superseded, continuation_record_exists, grant_re_emitted_in_outbox, resume_start_not_rejected, camp_zone_rebound, plus native ACTIVITY start / NATIVE_TRAVEL_START on the new agreement id.
`SETUP-FAIL scene lost across the save/load` = the load dropped bandits/hostility (see `reseat.txt` probe lines); fix the scene, never weaken the exact-targets rule.

## Offline proof
See the commit message. wpR1 fails 43/4 on the unpatched lib with the new tests (camp NEW zone), passes 47/0 patched; u4, u4b, sf26e, inv26, camp-scope, wpE kinds, wpR1 area goal, wpR2 identical to the unpatched baseline.
