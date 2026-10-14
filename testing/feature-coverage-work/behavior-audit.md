# Behavior and immersion audit: second 11 requirements

Read-only audit against `testing/HANDOFF.md`, project source/status notes, existing test plans, and available receipts. The requirement strings below are copied verbatim from the audit assignment. I did not find the originating direct-user message containing these exact sentences in the reviewed files; their original conversation provenance is therefore unavailable here. No wording has been reconstructed.

The current checkpoint is `testing/HANDOFF.md` (2026-10-14). The combined NPC immersion server/native candidate remains under release hold, with no install/runtime proof for the composed package. Candidate source, static review, and offline fixtures are recorded separately from live behavior. `GATED` means the relevant implementation or test is staged but lacks a required runnable/current-build gate; `PARTIAL` means related behavior has some evidence but this exact requirement is incomplete; `UNRUN` means no matching behavior run was found; `FAIL` means a current-build receipt directly failed the requirement.

## 1. Actual game behavior

**Exact requirement:** “Make NPCs aware of actual game behavior: escort/patrol/job/combat target; Jonin Soap should not deny following when game assigns it.”

**Implementation/evidence:** Candidate context readers are `pending-fixes/npc-immersion/combined-release/live/lib/native_ai_context.php` and `npc_conversation_context.php`; the native capture integration is described in `pending-fixes/npc-immersion/INTEGRATION.md` and `components/STOBE/docs/AUTONOMY_PLAN.md`. `pending-fixes/basic-ingame-smoke/conversation-coverage.md` proposes P0 AI checks but explicitly says the actual native goal and response must be correlated. KAH-TRAVEL-DEST-BASELINE-001 recorded Tsetseg as autonomously moving with `current_goal=OTHER`, but asked only for a travel preference; it does not prove that her answer used that state. KAH-CHAT-005 similarly observed autonomous movement without testing what the NPC knew about it. The exact Jonin Soap behavior has no matching test/receipt; the name appears in `pending-fixes/bodyguard-assignment-forensics/REPORT.md` as a member of the 13-person squad, with the assignment trigger unresolved.

**Status: PARTIAL.** Native-state context exists in the candidate path and adjacent autonomy work, but no matching conversation test proves escort, patrol, job, or combat-target awareness. The supplied Jonin Soap wording was not found verbatim in project files. **Blocker/next test:** current composed build and request-time native snapshot are unverified. With a copied fixture where the game itself assigns Jonin Soap to follow, capture the actual goal/order and the context delivered for his reply; ask what he is doing and verify he acknowledges following without denying the observed state. Repeat with a job/combat target only if safely available.

## 2. Shared plans and commitments

**Exact requirement:** “Remember commitments as shared plans: proposer, agreement, leader, end.”

**Implementation/evidence:** `pending-fixes/commitments-lifecycle/commitment_lifecycle.php`, `commitment_native_bridge.php`, and `travel_companionship.php` model proposer/acceptance metadata, immutable terms, leadership, explicit end condition, and native requested/running/completed/cancelled/failed states. `pending-fixes/commitments-lifecycle/STATUS.md` says source was delivered to the combined release but final cross-load proof is pending and no tests/runtime/build/install were performed by that owner. Live KAH-CHAT-003 is only an unearned-consent proposal check (`testing/live-stobe-queue/KAH-CHAT-003-5090-20261013.receipt.md`); KAH-TRAVEL-DEST-BASELINE-001 explicitly passed preference capture with no agreement or trip (`testing/live-stobe-queue/KAH-TRAVEL-DEST-BASELINE-001-5090-20261014.receipt.md`). Travel lifecycle packets TL-001–012 are reviewed for packet scope but remain not runnable/queued/executed pending exact pair/install/session gates; see `testing/STOBE_TEST_QUEUE_LEDGER.md` and `testing/live-stobe-queue/travel-lifecycle-p0-20261013/`.

**Status: GATED.** The lifecycle model is staged; no end-to-end current-build receipt proves shared recall. **Blocker/next test:** pair/install/release gates remain open. Create one NPC-proposed and one player-proposed plan, record both parties’ agreement and who leads, then verify later recall and a native-confirmed terminal end without treating a proposal or arrival as completion.

## 3. Changed plans and acknowledgment

**Exact requirement:** “Explain plan changes naturally and acknowledge original plan.”

**Implementation/evidence:** The commitment source describes known-plan continuity, explicit correction instead of invented excuses, consent before changing active terms, and grounded endings (`pending-fixes/commitments-lifecycle/INTEGRATION.md`; `commitment_lifecycle.php`). The staged limitation is explicit in `pending-fixes/commitments-lifecycle/STATUS.md`: an active trip must end before a different agreement replaces it; seamless alternative-then-replacement is not implemented. TL-004/TL-005 test lore/coarse-region handling and TL-010–012 test terminal truthfulness, but the exact lifecycle packet family is not executable yet (`testing/STOBE_TEST_QUEUE_LEDGER.md`). KAH-CHAT-005 is a separate live destination-resolver failure, not a changed-plan test (`testing/live-stobe-queue/KAH-CHAT-005-5090-20261014.receipt.md`).

**Status: GATED.** Prompt guidance exists, but changed-plan speech and acknowledgment have no live receipt, and replacing an active plan has a documented capability limit. **Blocker/next test:** after a committed trip is active, ask about a different destination and verify the NPC names the original plan and asks/gets consent before ending or replacing it; separately test cancellation and any new plan after exact native cleanup.

## 4. NPC priorities

**Exact requirement:** “NPCs’ priorities: work/hunger/injuries/duties/possessions/plans.”

**Implementation/evidence:** `pending-fixes/npc-immersion/relationship/STATUS.md` assigns explicit profile goals/occupation plus native current-state and commitment readers to `npc_motivation_context.php`; it warns that a job title alone does not establish a present duty and no excuse should be invented. `pending-fixes/basic-ingame-smoke/conversation-coverage.md` proposes P0 AI and TRUST checks for a real current job, hunger/injury/combat state, and grounded constraints. KAH-TRAVEL-DEST-BASELINE-001 is a preference-only turn and does not test priority conflicts; KAH-CHAT-005 fails destination resolution and does not test work or survival priorities.

**Status: GATED.** The priority context is staged and no current-build conversation receipt tests it. **Blocker/next test:** combined context integration/release is unverified. Use one copied NPC with a verified active job or hunger/injury state and a conflicting request; compare the response against fresh native facts, then change the state and repeat. Check duty/possession/commitment cases separately; do not count plausible explanations without state evidence.

## 5. Separate kinds of trust

**Exact requirement:** “Separate kinds of trust: company vs lending weapons/risk/secrets.”

**Implementation/evidence:** `pending-fixes/npc-immersion/relationship/STATUS.md` says `npc_motivation_context.php` distinguishes company, reliability, property/repayment, safety, risk, and disclosure using existing affinity/type/history and attributable events; it forbids adding invented meters. `pending-fixes/conversation-naturalness/RESULT.md` records offline `conversation-naturalness` and `relationship-context` fixtures, while `pending-fixes/activity-goals-main/a18-rebased-candidate-20261013/validation/RECEIPTS.md` records 26-assertion live/merge source-context fixtures. These are source/fixture results, not generated dialogue or behavior. No live receipt was found contrasting willingness to spend time together with lending a weapon, accepting risk, or keeping a secret.

**Status: GATED.** Domain-specific context is staged; evidence does not show those domains changing independently in NPC behavior. **Blocker/next test:** integrated current build and live model checks are absent. Hold NPC/profile constant and compare company, weapon loan, risky escort, and secret requests across grounded histories; verify each response uses the relevant existing evidence and does not generalize company affinity into consent for property/risk/disclosure.

## 6. Relationship development through experience

**Exact requirement:** “Develop relationships through experiences/follow-through/abandonment/returns/travel.”

**Implementation/evidence:** Existing REL mechanics cover attributable combat, aid/rescue, property return, and negotiated promise/loan outcomes; `docs/REL_FINAL_REPORT.md` records many prior in-game rows (for example SR16/SR18 aid, SR22 trading, SR28–29 deal follow-through), while SR13–14 theft/returned-property rows were waiting on a reliable caught signal and Shay’s decision at that report’s checkpoint. The newer `pending-fixes/relationship-experiences/STATUS.md` says its summary/adapter is staged and untested, new rewards are not active until verified participation evidence is wired, and it adds no abandonment penalty. `pending-fixes/commitments-lifecycle/STATUS.md` also says no automatic relationship rewards are wired to travel arrival alone.

**Status: PARTIAL.** Some established event-based relationship changes have historical test evidence, but there is no proof for the full experience/follow-through/abandonment/returns/travel set. Travel/participation rewards remain inactive, and absence/cancellation does not currently add an abandonment penalty. **Blocker/next test:** current release integration and verified participation/restitution producers are open. On a copied save, test an agreed activity that is completed, abandoned, resumed/returned to, and materially repaid; inspect canonical relationship events/effects and native participation or inventory proof at each transition.

## 7. Negotiated alternatives

**Exact requirement:** “Negotiate alternatives instead of binary refusal.”

**Implementation/evidence:** Destination/relationship candidate sources include `pending-fixes/npc-immersion/relationship/STATUS.md` (feasible bounded alternatives) and staged `destination_discovery.php`/`travel_companionship.php`. Direct current-build counterevidence exists: KAH-CHAT-005 on 5090 returned a generic practical-place refusal after the backend proposed “Squin gate, Stenn Desert”; destination validation rejected the counteroffer before it was spoken, so the player could not accept it. Receipt: `testing/live-stobe-queue/KAH-CHAT-005-5090-20261014.receipt.md`. KAH-CHAT-004 also ended without a place proposal (`testing/live-stobe-queue/KAH-CHAT-004-5090-20261013.receipt.md`). KAH-TRAVEL-DEST-BASELINE-001 did let Tsetseg name Vain as a preference, but explicitly recorded no resolved candidate, consent, agreement, or trip (`testing/live-stobe-queue/KAH-TRAVEL-DEST-BASELINE-001-5090-20261014.receipt.md`).

**Status: FAIL.** A live current-build negotiation path discarded a generated alternative and delivered a generic refusal. The preference-only pass does not offset that failure. **Blocker/next test:** resolver fix and current composed build/install proof are still required. Re-run a distinct cleared request with one valid bounded alternative and one unavailable destination; verify the valid alternative reaches native speech and only explicit player agreement creates the agreement/order.

## 8. Personal, imperfect knowledge

**Exact requirement:** “Personal imperfect knowledge: saw/heard/remembers/suspects, avoid omniscience.”

**Implementation/evidence:** `pending-fixes/npc-immersion/situated/INTEGRATION.md` and candidate `situated_dialogue.php` keep observed, remembered, reported, likely, and unknown evidence separate and prohibit global-catalog knowledge or invented hearsay; the status explicitly says source-only, not deployed, and no tests/game run. `pending-fixes/basic-ingame-smoke/conversation-coverage.md` proposes P1 KNOW but marks calibration/correction and actual sighting/event evidence as required. Tsetseg’s live preference answer included “I've seen the red rivers from a distance,” but the baseline receipt says no destination candidate metadata was attached and Vain was only a preference, not independently resolved personal knowledge (`testing/live-stobe-queue/KAH-TRAVEL-DEST-BASELINE-001-5090-20261014.receipt.md`).

**Status: UNRUN.** No receipt found that validates the required personal knowledge categories or a correction. The preference response is not a knowledge-provenance test. **Blocker/next test:** situated context is not deployed and its producer wiring is unproven. Query one verified personal sighting, one likely region, and one unknown detail; correct an unsupported assumption and compare the delivered response with actor-bound sighting/event provenance.

## 9. Occasional shared-activity reactions

**Exact requirement:** “React occasionally during shared activities without repetitive commentary.”

**Implementation/evidence:** Candidate `pending-fixes/npc-immersion/situated/lib/situated_dialogue.php` records only confirmed shared-activity transitions, claims them for the actual requester/listener, and uses cooldown/deduplication in an existing eligible bored turn. `pending-fixes/npc-immersion/situated/INTEGRATION.md` states the producer calls are not wired/proven, no timers or workers are added, terminal goal-report turns must suppress duplicate remarks, and this owner ran no tests. The staged activity fixtures in `pending-fixes/npc-immersion/combined-release-destination-discovery-incomplete-hunt-20261013/VALIDATION-5090.md` cover activity proposal/grounding only; they do not test incidental remarks.

**Status: GATED.** Remark selection and throttling exist only as source-level guidance; no tested producer-to-speech path was found. **Blocker/next test:** confirmed producer integration and exact composed release are missing. During one genuine shared activity, capture a real threat/progress/arrival transition, verify one relevant remark, then replay the same event and trigger unrelated eligible turns to verify dedupe/cooldown and no repetitive commentary.

## 10. Activity endings and follower distinction

**Exact requirement:** “Proper activity ending/release temporary behavior and distinguish temporary companion vs permanent follower.”

**Implementation/evidence:** Commitment source and `pending-fixes/commitments-lifecycle/INTEGRATION.md` specify explicit end conditions, exact owned-task release, cleanup confirmation, and no generic stop of unrelated vanilla AI. The native side is owned by `components/STOBE/src/NativeTravelLifecycle.cpp` and the pending lifecycle package. `components/STOBE/docs/AUTONOMY_PHASE2_PLAN.md` describes normal stop/cancel and job-preservation tests. TL-010/TL-011/TL-012 cover cancellation/completion/unrelated-turn truthfulness at packet level, but the queue ledger says the travel packet set remains blocked and specifically that the TL-010 END/cancel trigger is uncovered. No receipt was found showing temporary companion behavior contrasted against a permanent follower.

**Status: GATED.** Exact cleanup is designed but no current-build game receipt proves the temporary-vs-permanent distinction or end-to-end release. **Blocker/next test:** native/server pair and runtime gates remain open; TL-010 trigger coverage is incomplete. In one copied save, compare an NPC on a temporary agreed trip with a permanent vanilla follower, end/cancel the trip, and prove only the agreement-owned behavior stops while unrelated jobs/follow behavior remains intact.

## 11. Personality, repetition, uncertainty, and correction

**Exact requirement:** “Consistent personalities without repetition; allow uncertainty/corrections rather than inventing explanations.”

**Implementation/evidence:** Personality guidance is assigned to staged `npc_motivation_context.php` (`pending-fixes/npc-immersion/relationship/STATUS.md`). `pending-fixes/conversation-naturalness/RESULT.md` describes an offline prompt candidate aimed at answering the latest turn, reducing repetition, and avoiding unsupported claims; it explicitly says no model/game test was made. `pending-fixes/basic-ingame-smoke/conversation-coverage.md` records one CD1 speech-only pass for immediate boundary/knowledge limits, but durable boundary memory and full native/raw matching were not proved. It also records live memory extraction/correction failures: the natural-ruins preference was not persisted, and “You can talk normally again” did not clear the brief setting. The named exact live receipt for CD1 was not linked in that coverage file.

**Status: PARTIAL.** Some narrow boundary/knowledge-limit behavior has a plan-level report, and prompt regressions pass offline; personality consistency, non-repetition, and correction behavior have no full live proof. **Blocker/next test:** personality/immersion context remains staged and model behavior is unverified. Use the same NPC across a friendly request, a grounded refusal, and a neutral return; correct one factual assumption and ask one repeated question. Compare the replies against enabled profile/personality facts and captured context, checking for uncertainty or correction without invented causes or repeated boilerplate.

## Cross-audit limitations

- No requirement above earns a full `PASS` from the evidence reviewed. The current `KAH-TRAVEL-DEST-BASELINE-001` PASS is strictly a preference-capture/no-consent result; it is not a trip, shared plan, personal-knowledge, or travel-lifecycle pass.
- `pending-fixes/basic-ingame-smoke/conversation-coverage.md` and `pending-fixes/live-conversation-history/REMAINING-WORK-AUDIT.md` are test plans/audits. The latter says its 11-scenario complex conversation pass is queued and not proof; full Ambulin/Jonin/original eastern-ridge transcripts are unavailable.
- Several offline fixtures pass for prompt assembly, bounded activity proposals, and parser policies. They do not validate generated dialogue, installed code, runtime event producers, or native behavior.
- The current source and release blockers cited above are based on project status/checkpoint files; no rigs, queues, services, database, or implementation files were touched for this audit.
