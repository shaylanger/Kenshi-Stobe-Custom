# fix26f2: 26-f offer through the sfO ClearGroup seam (reloaddefs_sfe.sh.candidate)

Root cause (4080-i4 op16, evidence C:\KenshiTestRuns\imm26-4080-i4\rows\26-f, s1..s1d): the native side is fine. The s1/s1b/s1c prompts carry a ClearGroup candidate (campZone Rebirth, agreedTargets 4, activityPermitted true) but Cind is already in melee ("Attack Target: Gannor", combat.in_combat=true) and the MODEL answers "Busy - Gannor's on me" / ATTACK with activity_decision NONE. Rewording cannot fix that.
By s1d the bandits' own `ATTACK@Cind/Shay` calls register a PERSONAL_TRUCE (Functions.cpp:3788, ActivityPolicySupport.cpp:350 `active_ceasefire`), so s1d has no ClearGroup candidate at all. The offer must land in the first turn. No native or server change is needed.

Fix (candidate only, live file untouched):
- `rs_inject_arm` arms the sfO one-shot seam (`inject-propose.sh <lane> Cind ClearGroup`) right before the FIRST offer say (after the scene check and rs_guard). The seam replaces only the model's choice with a PROPOSE built from that turn's own native candidate; the "Yes", the native scope check, save+load and resume stay real. Opt out: `RW_INJECT_PROPOSE=0` (old model-only behaviour). Arm failure (rc != 0, rc 4 = seam not deployed) = SETUP-FAIL with the reason, before any say.
- `rs_inject_done` after the offer loop: `--status` + `--disarm` into `inject_status.txt` (an unused marker must not fire on the accept/resume turns).
- sfP `rl_say` override (reloaddefs_sfp.sh): Cind is player faction so her reply is a "(PC)" line; the rowlib `rl_say` only matched "(NPC)" and blocked ROW_WAIT=150 s per say, past the ~117 s proposal TTL.
- `rs_wait_delivery` (copy of sfi si_wait_delivery): wait for the RECHAT_TIMING follow-up of the offer say before the "Yes". Evidence `delivery_<step>.txt`.
- Accept retried once (RW_26F_ACCEPT_TRIES=2, step `2b`) while the offer is still `proposed`; offer-poll up to RW_26F_OFFER_POLLS=5 dumps after each say.
- `rs_poll_resume` (copy of sa_poll_resume, fix26ad): the continuation appears ~100 s after the s3 say; polls the post-load dump up to RW_RESUME_POLL=150 s. Never-resumes is still a FAIL; the checker is unchanged (no assertion weakened). Evidence `resume_poll.txt`.
- New evidence files in the row dir: `inject_arm.txt`, `inject_status.txt`, `delivery_<step>.txt`, `resume_poll.txt`.

Tests (all offline): `bash rowtools/fix26f-selftest.sh` 11/11 PASS; `bash rowtools/reload-sfe-selftest.sh` run on a STAGED copy with the candidate swapped in (see the final report for the result line). New selftest checks: 26-f-inject-armed-once-cleargroup, -armed-after-scene-before-first-say, -disarmed-after-offer-before-accept, -disarmed-once, -evidence-files, -delivery-and-resume-poll-evidence, -optout-arms-nothing, -arm-refused-setup-fail-no-say.

Swap (only when no operator on lane 4080-i4 is running reload-run-sfe.sh / a list that uses reloaddefs_sfe.sh):
    cd C:/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools && cp reloaddefs_sfe.sh.candidate reloaddefs_sfe.sh
Candidate sha256 is printed by `sha256sum reloaddefs_sfe.sh.candidate` (the commit message carries the prefix). One call unchanged: `bash rowtools/reload-run-sfe.sh 26-f 4080-i4 --save <S>`. The seam must be deployed on the lane (`bash rowtools/inject-propose-deploy.sh 4080-i4`; sfO redeployed it on 885a7fff).

Honesty note: with the seam the offer turn is injected exactly as for 26-d, so a PASS proves accept -> native scope check -> save+load -> resume, not the model's own choice to propose. The s1 turn still needs a groundable native ClearGroup candidate, which exists while the bandits are not yet under a personal truce.

RISK (cannot be settled offline): if the bandits already hold a personal truce when the PROPOSE is built (their chat issued ATTACK@Cind/Shay before the first offer say), the seam logs `STOBE_TEST_ACTIVITY_INJECT: no groundable candidate`, rs_inject_done removes the marker, and the row ends SETUP-FAIL "no ClearGroup proposal". The next fix would then be a recipe step that quiets the bandits' STOBE chat (e.g. lane initiative off for Dust Bandits, or a shorter scene) before the first say. Also unhandled: Cind killing the fixed target set between accept and save (job completes before the load).
