# REL (stateful relationships): context

Status 2026-10-06: REL is built (phases 1-8), merged and live on the server and in Stobe.dll; the REL builder role
and its feature branch are finished. Install state: `REL_INSTALL_MANIFEST.md`; row results: `REL_FINAL_REPORT.md`;
open rows: `STOBE_relationship_system_audit_and_implementation_plan.md` section 8. Builder history (phase deliveries,
run m4-m9 notes) was removed 2026-10-06: `git log -p` on this folder.

## Design in code
- `lib/social_event_contract.php` (validation), `social_store.php` (ingest/apply/pending/checkpoint/rollback),
  `social_interpreter.php` (phase 2 combat + phase 3 KO/theft/enslavement), `social_identity.php`
  (storage_id+name binding), `social_rules.php` + `data/social_relationship_rules.json` (phase2-v1).
- Native: `SocialEventProtocol.{h,cpp}` (envelopes), `Utils.cpp` (capture flag, shared sequence,
  `SocialPostStructured`), `main.cpp` (`SocialEntityFor`, `SocialEmitHarm`, emitters in attackingYou,
  major damage, KO, recovered, limb, death, slavery, transfer aggregation).

- Phase 4/5 code: `lib/social_care.php` (trait: aid/carry/food), `lib/social_property.php` (trait:
  theft/gift/trade), `lib/social_agreements.php` (deal outcomes; hooked from `stobeNegApplyConsequences`).
- Runner: 22 steps incl. `legacy_negotiation` (needs `/tmp/negtest`, created by the runner) and
  `mutation_proof` (15 mutations). Regression events must be in game-time order (later ts) or they are "late".

## Coordinator rules (2026-10-03)
- **Never purge the live social tables unless the coordinator says so** (an m9 purge hit a running m10 batch).
- Live tables get pruned by fixture reloads anyway; judge runs from `C:\KenshiTestRuns\<run>\rel\*.inspect.txt`
  (summary script: `/root/stobe-work/social-phase1/m5_summary.py <run>`) and the archived stobe.log in
  `C:\KenshiTestRuns\logs\<time>-stop\`.
