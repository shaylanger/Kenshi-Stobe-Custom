# REL builder: active context (resume here)

Role: REL builder (see `C:\KenshiModding\testing\README.md`). Never launch Kenshi, install DLLs, touch
the live server, `/root/STOBE-src`, `C:\StobeBuild` or the `stobe`/`stobe_test` DBs.

## Where things are
- Server branch: `/root/stobe-work/social-phase1/server`, `feature/social-phase1`, pushed to github
  `origin feature/social-phase1` (force-pushed with lease after each rebase onto `origin/stobe`).
  Before a delivery: `git fetch origin stobe && git rebase origin/stobe`, rerun the runner, push.
- Native: `/root/stobe-work/social-phase1/native-workspace` (local git only). Branch `live-base` =
  snapshot of the live `/root/STOBE-src` working tree; `feature/social-phase1` = REL commits on top.
  To pick up live changes: `git checkout live-base`, rsync `/root/STOBE-src/src/` (exclude `*.bak*`),
  `tests/cpp/`, `CMakeLists.txt`, `Stobe.vcxproj`, `mod/Stobe.ini` into `components/STOBE/`, commit,
  `git checkout feature/social-phase1 && git rebase --autostash live-base`.
  Delivery patch: `git diff --relative=components/STOBE live-base feature/social-phase1 -- components/STOBE
  > C:\KenshiModding\pending-fixes\rel-native-phaseN.patch`; verify with
  `rsync -a --exclude '*.bak*' /root/STOBE-src/ /tmp/rel-verify/ && git -C /tmp/rel-verify apply <patch>`,
  build privately: `python3 server/tools/automation/build_social_private.py /tmp/rel-verify/src`.
- Offline gate: `cd server && STOBE_DB_NAME=stobe_social_phase1_test python3 tests/run_social_phase1.py`
  (17 steps). One suite: `bash tests/social_relationship/runtest.sh tests/<file>.php`.
  Mutation proof: `bash tests/social_relationship/mutation_proof.sh`.
- Native portable tests: `/root/stobe-work/social-phase1/build-tests` (cmake on native-workspace).
- Deliveries: `DELIVERY.md` (one dated section each). In-game scenarios:
  `server/tests/social_relationship/ingame/` + `RUN_ORDER.md`. SR states: `scenarios.json` field
  `rel_state` (+ `offline_tests`, `ingame_scenarios`, `open_blockers`), regenerate with
  `python3 tests/social_relationship/update_states.py "$(cat tests/social_relationship/states_phase3.json)"`
  (phase-2 states are defaults in the script; add new phases to a states file).
- Diagnostics tool: `server/tools/social_relationship_inspect.php` (see header).

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

## Since run m4 (REL merged live)
- Live `/root/STOBE-src` now contains REL phase 5. `live-base` was synced to it (67d737e) and
  `feature/social-phase1` reset onto it (old history: tag `rel-phase5-delivered`). Native patches are now
  INCREMENTAL against live (`rel-native-m4-fix.patch` = first one).
- Live server has REL merged (dcf71ac); the server branch is now live HEAD + fixes.
- Live runs with Playthrough Saves off: campaign `legacy` (see DELIVERY.md "Fix for run m4").

## Phases 6-7 (2026-10-03)
- Server: `lib/social_dialogue.php`, `lib/social_recruitment.php`, witness echoes in `social_interpreter.php`
  (`witnesses()`), escape in `escapeProgress()`/`freed()`. Tests `social_witness_regression`,
  `social_recruitment_regression`. Delivery 6/7 = server `307b011`, `rel-native-p67.patch`.
- Live `/root/STOBE-src` already contains every REL native patch up to m5; `live-base` synced (a7f69ca).
- Waiting for: m5 reruns and the Phase 6/7 scenarios; probes 5, 17, 18, 20; fixture "Home beds" for SR18/19.
- Next (after results): Phase 8 (full validation, retention for social_event_inbox, soak) only when asked.

## Coordinator rules (2026-10-03)
- **Never purge the live social tables unless the coordinator says so** (an m9 purge hit a running m10 batch).
- Live tables get pruned by fixture reloads anyway; judge runs from `C:\KenshiTestRuns\<run>\rel\*.inspect.txt`
  (summary script: `/root/stobe-work/social-phase1/m5_summary.py <run>`) and the archived stobe.log in
  `C:\KenshiTestRuns\logs\<time>-stop\`.
- Native patches are incremental against live `/root/STOBE-src`; sync `live-base` first (other fixers change main.cpp).

## Status
- Delivery 5 (Phases 1-5): server `3cd48b5` on live `1a8fc3f`, `rel-native-phase5.patch`, private DLL 0fb7e3ca.
- Stopped after Phase 5 as instructed (coordinator 2026-10-03). Waiting for the coordinator's in-game results
  and probe answers 1-16 (DELIVERY.md). Next: fix REL bugs from those runs, calibrate rules from the probes,
  then Phase 6 (witnesses/dialogue: needs a sensing API probe first).
