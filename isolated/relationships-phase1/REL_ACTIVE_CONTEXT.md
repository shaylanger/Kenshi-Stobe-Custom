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

## Status
- Delivery 3 (Phases 1-3): server `68c0c25` on live `2b3593c`, `rel-native-phase3.patch`, private DLL b588f9c8.
- Stopped after Phase 3 as instructed. Next: Phase 4 (aid and carry) after the coordinator's game probes
  1-9 (DELIVERY.md) come back; fix REL bugs from the master plan first.
