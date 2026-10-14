# NPC feature coverage

Snapshot: 2026-10-14 checkpoint and receipts reviewed by the three linked audits.

This ledger covers the **10 social requirements** and **11 behavior/immersion requirements** as separate, numbered groups. The supplemental goals/travel chronology below does not add to that count. S01–S10 and B01–B11 are coverage labels only; test identifiers such as SR24, KAH-CHAT-005, TL-001, and AG-GAME-003 remain distinct.

The requirement wording is copied from the assigned audit lists. The social and behavior auditors did not find the originating direct-user messages containing those exact sentences in the project files. That provenance gap is retained here; wording has not been reconstructed. The audit reports contain the detailed source and evidence notes: [social audit](feature-coverage-work/social-audit.md), [behavior audit](feature-coverage-work/behavior-audit.md), and [goals/activity audit](feature-coverage-work/goals-audit.md).

**Release boundary:** the latest shared checkpoint records the composed server candidate under runtime/copied-save holds; the current AEF game build excludes server-side social and age changes. Exact-hash source/offline fixtures do not show that those changes are installed or working in the current game. See [HANDOFF](HANDOFF.md) and [social additions status](../pending-fixes/npc-social-additions/STATUS.md).

## Status legend

- **PASS** — evidence demonstrates the complete requirement at the relevant integrated/runtime level.
- **FAIL** — a current-build receipt directly contradicts the requirement.
- **PARTIAL** — related positive evidence exists, but a required behavior or lifecycle remains unproven. The evidence and missing part are named in the row.
- **UNRUN** — no matching behavior execution was found.
- **GATED** — a relevant implementation or test is staged/authored, but a required release, setup, or runtime gate prevents execution.

Offline fixtures, static review, packet review, preference discovery, and source presence do not by themselves establish installed or in-game behavior. A test packet's ID is not a result. Setup failure is not a product failure. Status is about the full requirement, not an adjacent narrow pass.

Social labels such as `personal_boundaries`, `conversation_privacy`, `player_preferences`, `referrals`, `followup_topics`, `communication_preferences`, and `attention_limits` identify component workstreams, not assigned individual owners. [Social additions STATUS](../pending-fixes/npc-social-additions/STATUS.md) names `social_additions_integrator` as coordinator and `nav_owner` as central hook/release owner; it does not assign feature-level owners for those labels.

## Social requirements — 10

### S01 — Personal boundaries

> Personal boundaries you can learn: an NPC might dislike slavery, refuse theft, or avoid a faction; discover principles through conversation.

**Implementation:** [npc_personal_boundaries.php](../pending-fixes/npc-social-additions/boundaries/npc_personal_boundaries.php); candidate copy in [release-candidate-runtime-validation](../pending-fixes/activity-goals-main/release-candidate-runtime-validation-20261013/server/live/lib/npc_personal_boundaries.php).

**Tests and receipts:** SOCIAL-ADDITIONS-RELEASE, 37 offline cases: [5090 receipt](../pending-fixes/rig5090-validation/social-additions-5090-20261013.md), [4080 receipt](../pending-fixes/rig4080-validation/social-additions-release-4080-runtime-20261013.md); authored [BOUNDARIES packet](../pending-fixes/npc-social-additions/operator-packets-20261013-r5/BOUNDARIES.md). A narrow 4080 acknowledgment is recorded in [rig status](../pending-fixes/rig4080-validation/STATUS.md), but it does not establish learning or persistence.

**Status: PARTIAL.** Profile-grounded prompt behavior has offline coverage. Actual conversation discovery, durable memory, and later recall are not proven. Current composed release is not installed.

**Owner / next test:** Workstream: `personal_boundaries` (no feature-level owner assigned in STATUS); `nav_owner` owns central hook/release and `social_additions_integrator` coordinates. On the exact composed candidate, state a slavery, theft, or faction principle; test an acceptable compromise and a correction; then test later recall. Inspect prompt facts and action dispatch separately.

### S02 — Witnessing and rumor

> Remember how you treated other people: witnessing help/mistreatment influences opinion; unwitnessed acts require believable rumor.

**Implementation:** native event/witness payload in [SocialEventProtocol.cpp](../components/STOBE/src/SocialEventProtocol.cpp); relationship rules in [relationship design](../docs/RELATIONSHIP_SYSTEM_DESIGN.md) and the server relationship interpreter/store.

**Tests and receipts:** REL SR24 (friend witnesses an event) and SR25 (asleep witness has no effect) passed in game; SR27 (dialogue insult listener data) is partial. Results are in [REL final report](../docs/REL_FINAL_REPORT.md), rows SR24–SR27.

**Status: PARTIAL.** Witnessed harm and an asleep/no-witness control have in-game evidence. Witnessed help as a social observation is not demonstrated. Believable rumor is expressly not required in the REL first release, so that part is absent from the documented design.

**Owner / next test:** Workstream: REL/native witness evidence (no named owner found in the reviewed design, architecture, final report, or integration status); no rumor owner or rumor source is assigned in the reviewed docs. Define attributable, fresh, one-hop rumor evidence, then test witnessed help, witnessed harm, believable rumor, and no-rumor controls without omniscience or recursive spread.

### S03 — Relationships between NPCs

> Relationships between NPCs: friends/rivals/family/debts shape defense, trust, recommendations, refusals.

**Implementation:** directed affinity and persistence in [REL architecture](../docs/REL_ARCHITECTURE.md) and [REL design](../docs/RELATIONSHIP_SYSTEM_DESIGN.md); relationship-conditioned dialogue and referral context in the candidate server files relationship_conversation.php, npc_conversation_context.php, and npc_referrals.php under [release-candidate-runtime-validation](../pending-fixes/activity-goals-main/release-candidate-runtime-validation-20261013/server/live/lib/).

**Tests and receipts:** REL SR04 (friend defense) and SR24 (witness propagation) passed in game in [REL final report](../docs/REL_FINAL_REPORT.md). RELATIONSHIP-CONTEXT passed 26 offline assertions: [5090 receipt](../pending-fixes/rig5090-validation/relationship-context-5090-20261013.md).

**Status: PARTIAL.** Directed affinity and a friend-defense consequence are evidenced. No discriminating cross-behavior test shows known NPC-to-NPC friend/rival/family/debt ties changing trust, referral, and refusal.

**Owner / next test:** Workstreams: relationship-conditioned conversation and REL/native event evidence; no named owner for either role or typed-tie coverage was found in the reviewed docs/status. Verify a typed relationship fact and scope, then test defense, trust language, referral, and refusal for a tied pair and a no-known-tie control.

### S04 — Public and private context

> Different reactions in public and private: avoid smuggling or criticizing boss near guards/coworkers; listeners matter.

**Implementation:** [social_privacy.php](../pending-fixes/npc-social-additions/privacy/lib/social_privacy.php), native-snapshot requirements in [HOOKS.md](../pending-fixes/npc-social-additions/HOOKS.md), and the composed server candidate.

**Tests and receipts:** SOCIAL-ADDITIONS-RELEASE's 37 offline cases bind context to a current snapshot and reject sight/hearing claims from a nearby list alone. CD5 on 4080 refused an absolute secrecy promise but added unsupported “public area” language; see [CD5 review](../pending-fixes/rig4080-validation/complex-dialogue/CD5.md) and [prompt capture](../pending-fixes/rig4080-validation/complex-dialogue/CD5-privacy-prompt.txt). A later corrected prompt showed privacy unknown/no confirmed close shared audience in [4080 status](../pending-fixes/rig4080-validation/STATUS.md).

**Status: PARTIAL.** Narrow uncertainty handling is evidenced; the controlled public/private listener matrix and guard/coworker behavior are not.

**Owner / next test:** Workstream: `conversation_privacy` (no feature-level owner assigned in STATUS); `nav_owner` owns central hook/release and `social_additions_integrator` coordinates. On the exact current build, use a private scene, a visible guard/coworker, and stale or missing audience data. Ask about the same sensitive act and verify only observed listeners affect the response.

### S05 — Preferences

> Remember preferences: preferred name, faction dislike, travel habits carry forward.

**Implementation:** pair-scoped preference storage and readback in [npc_preferences.php](../pending-fixes/npc-social-additions/preferences/npc_preferences.php), with supported address, likes/dislikes, travel, and social fields.

**Tests and receipts:** SOCIAL-ADDITIONS-RELEASE offline preference validation/state fixture; historical 4080 preference set/correct/forget smoke in [rig status](../pending-fixes/rig4080-validation/STATUS.md). KAH-TRAVEL-DEST-BASELINE-001 on 5090 records one-turn preference discovery only: [receipt](live-stobe-queue/KAH-TRAVEL-DEST-BASELINE-001-5090-20261014.receipt.md).

**Status: PARTIAL.** Generic preference persistence and reading have historical runtime evidence. A matched current-candidate sequence for preferred name, faction dislike, and travel-habit carry-forward is missing. The travel baseline is not memory or consent proof.

**Owner / next test:** Workstream: `player_preferences` (no feature-level owner assigned in STATUS); `nav_owner` owns central hook/release and `social_additions_integrator` coordinates. Set each preference in a separate turn, verify next-turn and reload readback, correction/forget behavior, and rejection of quotes, hypotheticals, and third-party speech.

### S06 — Referrals and introductions

> Introductions/referrals: recommend a knowledgeable NPC and useful introduction.

**Implementation:** [npc_referrals.php](../pending-fixes/npc-social-additions/referrals/npc_referrals.php) and native visibility source [NpcReferralPeople.cpp](../components/STOBE/src/NpcReferralPeople.cpp) / [NpcReferralPeople.h](../components/STOBE/src/NpcReferralPeople.h); authored [REFERRALS packet](../pending-fixes/npc-social-additions/operator-packets-20261013-r5/REFERRALS.md).

**Tests and receipts:** SOCIAL-ADDITIONS-RELEASE offline fixture covers visible/current/identity-bound referral context and empty, untitled, and stale controls. 4080 actual prompt context included referral guidance in [rig status](../pending-fixes/rig4080-validation/STATUS.md). No user-facing referral or introduction receipt was found.

**Status: UNRUN** for user-visible recommendation/introduction; only plumbing and context are evidenced.

**Owner / next test:** Workstream: `referrals` (no feature-level owner assigned in STATUS); `nav_owner` owns central hook/release and the native referral build; `social_additions_integrator` coordinates. Test a visible, titled, relevant contact, then absent, stale, untitled, and irrelevant contacts. Check expertise and that the NPC does not invent friendship, availability, location, or an arranged introduction.

### S07 — Follow-up topics

> Follow-up conversations only for unfinished remembered threads.

**Implementation:** [social_followups.php](../pending-fixes/npc-social-additions/followups/social_followups.php); topic claiming requires a uniquely active topic and an eligible optional-speech slot. The newer DDED253A source has not been proven installed in the composed/runtime package; see [validation matrix](../pending-fixes/npc-social-additions/VALIDATION-MATRIX-20261013.md).

**Tests and receipts:** real 4080 F1 topic creation and historical F2 dismissal are recorded in [validation matrix](../pending-fixes/npc-social-additions/VALIDATION-MATRIX-20261013.md) and [rig status](../pending-fixes/rig4080-validation/STATUS.md). The current choice fix passed four fake-database cases: [offline receipt](../pending-fixes/rig4080-validation/followup-choice-4080-runtime-20261013.md).

**Status: PARTIAL** (current source/release is gated). Topic creation and a later exact dismissal have historical runtime evidence. The newer listener-choice fix has offline evidence only; deferral and one-time resumption at a later eligible slot are unproven.

**Owner / next test:** Workstream: `followup_topics` (no feature-level owner assigned in STATUS); `nav_owner` owns central hook/release and `social_additions_integrator` coordinates. Install the exact reviewed source, then test topic creation, direct dismissal overriding contradictory extraction, deferral while attention blocks, one later resumption, and no repeat after closure.

### S08 — Communication preferences

> Establish communication preferences such as quiet unless danger, tell before changing plans, don't attack unless attacked.

**Implementation:** [social_communication.php](../pending-fixes/npc-social-additions/communication/social_communication.php). This module controls speech amount and plan-notice preferences only; it does not authorize actions or control native combat. Attack commands are excluded from preference extraction.

**Tests and receipts:** SOCIAL-ADDITIONS-RELEASE offline grammar/state fixture; historical brief/normal preference persistence in [4080 status](../pending-fixes/rig4080-validation/STATUS.md). KAH-TRAVEL-DEST-BASELINE-001 does not test plan-change notice.

**Status: PARTIAL.** Brief/normal speech preferences have historical runtime evidence. Quiet-unless-danger and tell-before-changing-plans lack a matched runtime sequence. “Don't attack unless attacked” is not implemented by this speech-only module.

**Owner / next test:** Workstream: `communication_preferences` (no feature-level owner assigned in STATUS); `nav_owner` owns central hook/release and `social_additions_integrator` coordinates. Test quiet/urgent speech and plan-change notice with correction and reload. The combat rule needs a separately owned authoritative action policy and attacked/unprovoked native-dispatch controls.

### S09 — Social repair

> Social repair through apology/explanation/restitution/changed behavior gradually; one apology doesn't erase serious betrayal.

**Implementation:** staged repair ledger/dialogue under [pending-fixes/social-repair](../pending-fixes/social-repair/) and the candidate server social_repair_* files. Policy caps relief, retains historical harm, and preserves residual grievance after serious/repeated harm.

**Tests and receipts:** REL SR29 betrayal after an accepted coercive deal passed in [REL final report](../docs/REL_FINAL_REPORT.md). 4080 exact-item restitution retained the -17 harm penalty; the staged 10-case repair fixture passed in [4080 status](../pending-fixes/rig4080-validation/STATUS.md) and [remaining-coverage receipt](../pending-fixes/rig4080-validation/social-repair-remaining-coverage-4080-runtime-20261013.md). The live terms/refusal/completion packet is instructions-only: [social-repair-terms-refusal-completion-842CEB.sh](live-stobe-queue/social-repair-terms-refusal-completion-842CEB.sh).

**Status: PARTIAL** (integrated release/runtime gated). Restitution with retained harm has older isolated runtime evidence; apology policy has offline evidence. Explanation and changed-behavior recovery over time are not evidenced as a complete path; staged repair source is unshipped.

**Owner / next test:** social_repair_owner; nav_owner owns compatible release integration. After release, test serious betrayal, a rejected and accepted specific apology, verified partial/full restitution, later changed behavior, bounded gradual relief, residual grievance after one apology, and idempotence.

### S10 — Attention and postponement

> Natural limits on attention: busy/frightened/exhausted/fighting NPCs can postpone conversations.

**Implementation:** [social_attention.php](../pending-fixes/npc-social-additions/attention/social_attention.php) gates optional speech on verified combat/activity, preserves urgent/manual responses, and does not invent fear, pain, exhaustion, or urgency.

**Tests and receipts:** SOCIAL-ADDITIONS-RELEASE offline neutral/combat/unknown/direct-message gate; [validation matrix](../pending-fixes/npc-social-additions/VALIDATION-MATRIX-20261013.md) says runtime behavior is open. The older 4080 smoke did not exercise busy-versus-idle variants; see [4080 status](../pending-fixes/rig4080-validation/STATUS.md).

**Status: GATED.** Source/offline evidence exists, but no in-game postponement/resumption matrix has run. Fear and exhaustion lack supported signals in this module.

**Owner / next test:** Workstream: `attention_limits` (no feature-level owner assigned in STATUS); `nav_owner` owns central hook/release and `social_additions_integrator` coordinates. Test one observed busy/activity state, combat, and idle recovery with the same pending topic. Manual questions must still receive an answer; an optional follow-up must wait while blocked and resume once when eligible. Keep fear/exhaustion UNRUN without authoritative signals.

## Behavior and immersion requirements — 11

### B01 — Actual game behavior

> Make NPCs aware of actual game behavior: escort/patrol/job/combat target; Jonin Soap should not deny following when game assigns it.

**Implementation:** candidate [native_ai_context.php](../pending-fixes/npc-immersion/combined-release/live/lib/native_ai_context.php) and npc_conversation_context.php; capture integration is described in [NPC immersion integration](../pending-fixes/npc-immersion/INTEGRATION.md) and [autonomy plan](../components/STOBE/docs/AUTONOMY_PLAN.md).

**Tests and receipts:** P0 AI checks in [conversation-coverage plan](../pending-fixes/basic-ingame-smoke/conversation-coverage.md); KAH-TRAVEL-DEST-BASELINE-001 observed Tsetseg at current_goal=OTHER but did not test whether her answer used that state. Jonin Soap's exact behavior has no matching test; [bodyguard report](../pending-fixes/bodyguard-assignment-forensics/REPORT.md) only lists him in the 13-person squad.

**Status: PARTIAL.** Candidate native-state context exists, but escort, patrol, job, combat-target awareness has no matching conversation receipt.

**Owner / next test:** native_ai_awareness; nav_owner owns integration/release. On a copied fixture where the game assigns Jonin Soap to follow, capture the actual order and prompt context, ask what he is doing, and compare answer with the order. Test job/combat target only where safely available.

### B02 — Shared plans and commitments

> Remember commitments as shared plans: proposer, agreement, leader, end.

**Implementation:** [commitment_lifecycle.php](../pending-fixes/commitments-lifecycle/commitment_lifecycle.php), [commitment_native_bridge.php](../pending-fixes/commitments-lifecycle/commitment_native_bridge.php), and travel_companionship.php; these model proposer/acceptance, terms, leadership, end condition, and native lifecycle states.

**Tests and receipts:** KAH-CHAT-003 tests an unearned-consent proposal boundary, not shared recall: [receipt](live-stobe-queue/KAH-CHAT-003-5090-20261013.receipt.md). KAH-TRAVEL-DEST-BASELINE-001 explicitly has no agreement or trip: [receipt](live-stobe-queue/KAH-TRAVEL-DEST-BASELINE-001-5090-20261014.receipt.md). TL-001–012 are authored packet IDs only; [travel packet README](live-stobe-queue/travel-lifecycle-p0-20261013/README.md) says NOT RUNNABLE / NOT QUEUED / NOT EXECUTED.

**Status: GATED.** Lifecycle source is staged, but no end-to-end current-build receipt proves shared recall.

**Owner / next test:** commitments_lifecycle and nav_owner/native_travel_lifecycle. After pair/install gates, create one NPC-proposed and one player-proposed plan, record agreement and leader, then verify later recall and native-confirmed terminal end.

### B03 — Changed plans

> Explain plan changes naturally and acknowledge original plan.

**Implementation:** [commitment lifecycle integration](../pending-fixes/commitments-lifecycle/INTEGRATION.md) and commitment_lifecycle.php; prompts require grounded correction and consent before replacing terms. [Status](../pending-fixes/commitments-lifecycle/STATUS.md) documents that an active trip must end before a new agreement replaces it.

**Tests and receipts:** TL-004/TL-005 and TL-010–012 cover adjacent lore/region/terminal cases only; all travel packets remain gated in [queue ledger](STOBE_TEST_QUEUE_LEDGER.md). KAH-CHAT-005 is a destination-resolver failure, not a changed-plan test: [receipt](live-stobe-queue/KAH-CHAT-005-5090-20261014.receipt.md).

**Status: GATED.** No live changed-plan speech or original-plan acknowledgment receipt exists; seamless alternative-then-replacement is a documented capability limit.

**Owner / next test:** commitments_lifecycle and nav_owner/native_travel_lifecycle. With an active committed trip, ask about another destination and verify the original plan is named and consent is obtained before replacement; then test cleanup, cancellation, and any new plan.

### B04 — Priorities

> NPCs’ priorities: work/hunger/injuries/duties/possessions/plans.

**Implementation:** [npc_motivation_context.php](../pending-fixes/npc-immersion/relationship/lib/npc_motivation_context.php) and current-state/commitment readers per [integration status](../pending-fixes/npc-immersion/INTEGRATION.md).

**Tests and receipts:** P0 AI/TRUST checks in [conversation-coverage plan](../pending-fixes/basic-ingame-smoke/conversation-coverage.md). The travel preference baseline and KAH-CHAT-005 do not test priority conflicts.

**Status: GATED.** Priority context is staged; no current-build conversation receipt tests it.

**Owner / next test:** relationship_conversation_owner; nav_owner owns integration/release. Give a copied NPC a verified active job or hunger/injury state that conflicts with a request; compare answer to fresh facts, then change state and repeat. Test duties, possessions, and commitments separately.

### B05 — Separate kinds of trust

> Separate kinds of trust: company vs lending weapons/risk/secrets.

**Implementation:** npc_motivation_context.php in the relationship candidate distinguishes company, reliability, property/repayment, safety, risk, and disclosure using existing facts.

**Tests and receipts:** [conversation-naturalness results](../pending-fixes/conversation-naturalness/RESULT.md) and [A18 rebased candidate receipts](../pending-fixes/activity-goals-main/a18-rebased-candidate-20261013/validation/RECEIPTS.md) are offline/source-context evidence, not generated-dialogue behavior. No live receipt contrasts these trust domains.

**Status: GATED.** Context is staged; behavior showing independent trust domains is unproven.

**Owner / next test:** relationship_conversation_owner; nav_owner owns integration/release. Hold an NPC/profile constant and compare company, weapon loan, risky escort, and secret requests against grounded histories. Verify one domain does not imply consent in another.

### B06 — Relationship development through experiences

> Develop relationships through experiences/follow-through/abandonment/returns/travel.

**Implementation:** existing REL covers attributable combat, aid/rescue, property return, and negotiated promise/loan outcomes; new read-only summary is in [relationship-experiences status](../pending-fixes/relationship-experiences/STATUS.md). New awards are inactive until participation is proven; no abandonment penalty is added.

**Tests and receipts:** historical REL SR16/SR18 aid, SR22 trading, and SR28–29 deal outcomes in [REL final report](../docs/REL_FINAL_REPORT.md); newer participation/travel rewards have no live result.

**Status: PARTIAL.** Some event-based changes have historical game evidence; the full experience/follow-through/abandonment/return/travel set is not proved.

**Owner / next test:** relationship_experiences and commitments_lifecycle; nav_owner owns integration. On a copied save, test an agreed activity completed, abandoned, resumed/returned to, and materially repaid; inspect relationship events and native participation/inventory evidence at each transition.

### B07 — Negotiated alternatives

> Negotiate alternatives instead of binary refusal.

**Implementation:** feasible alternatives are guided by relationship_conversation_owner and destination-discovery/travel_companionship candidate logic.

**Tests and receipts:** current-build KAH-CHAT-005 on 5090 returned a generic refusal after the backend proposed “Squin gate, Stenn Desert”; destination validation rejected it before speech: [receipt](live-stobe-queue/KAH-CHAT-005-5090-20261014.receipt.md). KAH-CHAT-004 ended without a place proposal: [receipt](live-stobe-queue/KAH-CHAT-004-5090-20261013.receipt.md). The “Vain” result in KAH-TRAVEL-DEST-BASELINE-001 is preference-only, with no candidate/consent/trip.

**Status: FAIL.** A live current-build negotiation discarded an alternative and delivered a generic refusal. The preference-only result does not offset this failure.

**Owner / next test:** relationship_conversation_owner and current destination-resolver owner recorded in HANDOFF, /root/coarse_region_goal_integration. After resolver fix and exact composed install, test a valid bounded alternative and an unavailable destination; verify valid wording reaches native speech and only explicit agreement creates a trip.

### B08 — Personal, imperfect knowledge

> Personal imperfect knowledge: saw/heard/remembers/suspects, avoid omniscience.

**Implementation:** candidate [situated_dialogue.php](../pending-fixes/npc-immersion/situated/lib/situated_dialogue.php) separates observed, remembered, reported, likely, and unknown evidence.

**Tests and receipts:** [conversation-coverage plan](../pending-fixes/basic-ingame-smoke/conversation-coverage.md) proposes P1 KNOW checks but requires provenance and correction evidence. The “I've seen the red rivers from a distance” line in KAH-TRAVEL-DEST-BASELINE-001 was not backed by destination-candidate metadata; see [receipt](live-stobe-queue/KAH-TRAVEL-DEST-BASELINE-001-5090-20261014.receipt.md).

**Status: UNRUN.** No behavior receipt validates the requested knowledge categories or a correction.

**Owner / next test:** situated_dialogue; nav_owner owns producer integration/release. Query one verified sighting, one likely region, and one unknown detail; correct an unsupported assumption and compare the response with actor-bound event/sighting provenance.

### B09 — Occasional shared-activity reactions

> React occasionally during shared activities without repetitive commentary.

**Implementation:** candidate situated_dialogue.php records confirmed shared-activity transitions and uses cooldown/deduplication in an eligible bored turn. Producer wiring is not proven; see [situated dialogue integration](../pending-fixes/npc-immersion/situated/INTEGRATION.md).

**Tests and receipts:** candidate activity fixtures in [5090 validation](../pending-fixes/npc-immersion/combined-release-destination-discovery-incomplete-hunt-20261013/VALIDATION-5090.md) cover proposal/grounding, not incidental remarks. No producer-to-speech receipt was found.

**Status: GATED.** No tested producer-to-speech path exists.

**Owner / next test:** situated_dialogue; nav_owner owns producer integration/release. During a genuine shared activity, capture a real threat/progress/arrival transition, verify one relevant remark, replay it, and check dedupe/cooldown across later eligible turns.

### B10 — Activity endings and follower distinction

> Proper activity ending/release temporary behavior and distinguish temporary companion vs permanent follower.

**Implementation:** [commitment lifecycle integration](../pending-fixes/commitments-lifecycle/INTEGRATION.md) and [NativeTravelLifecycle.cpp](../components/STOBE/src/NativeTravelLifecycle.cpp) describe exact owned-task release and protection of unrelated vanilla behavior.

**Tests and receipts:** [Autonomy phase 2 plan](../components/STOBE/docs/AUTONOMY_PHASE2_PLAN.md) describes stop/cancel and job preservation. TL-010/011/012 cover terminal wording at packet level; the [travel README](live-stobe-queue/travel-lifecycle-p0-20261013/README.md) says packets are not runnable, and TL-010 cancellation trigger coverage is explicitly missing. No temporary-versus-permanent follower receipt was found.

**Status: GATED.** No current-build game receipt proves the distinction or end-to-end release.

**Owner / next test:** commitments_lifecycle, nav_owner/native_travel_lifecycle, and activity_owner for activity cleanup. After exact pair/install gates, compare a temporary agreed trip with a permanent vanilla follower in one copied save; end/cancel the trip and prove only agreement-owned behavior stops.

### B11 — Personality, repetition, uncertainty, correction

> Consistent personalities without repetition; allow uncertainty/corrections rather than inventing explanations.

**Implementation:** personality guidance in npc_motivation_context.php; offline prompt candidate in [conversation-naturalness results](../pending-fixes/conversation-naturalness/RESULT.md).

**Tests and receipts:** offline prompt regressions are recorded in that result. The [conversation-coverage plan](../pending-fixes/basic-ingame-smoke/conversation-coverage.md) records a narrow CD1 speech-only pass, but no linked receipt proving durability or full native/raw matching. The same plan/status records failed natural-ruins preference extraction and an earlier failure to clear “brief” communication mode.

**Status: PARTIAL.** Narrow boundary/knowledge-limit behavior and offline prompt regressions exist; personality consistency, non-repetition, and correction have no full live proof.

**Owner / next test:** relationship_conversation_owner and situated_dialogue; nav_owner owns integration/release. Use the same NPC for a friendly request, grounded refusal, and neutral return; correct one factual assumption and repeat one question. Compare replies with enabled profile facts and captured context.

## Supplemental goals, destination, travel, and activity scope

These scope records preserve chronology and unresolved interpretation. They are not additional numbered requirements.

| Scope record | User wording or recorded scope | Evidence and status | Owner / next test |
|---|---|---|---|
| Earlier delegation | H034 records: “Start the other work using subagents.” | Delegation instruction; it does not change feature scope. | Coordinator tracks parallel owners. |
| Destination choice and area | H032 records: “Laru invited me toward an eastern ridge; after I agreed, she said she needed a place she could find. Fix NPCs choosing destinations and honoring described areas, then summarize the plan.” H033 begins: “Confirmed: that is what I want.” | Destination choice has current failures and a narrow preference-only pass. KAH-CHAT-004 5090: FAIL destination discovery, [receipt](live-stobe-queue/KAH-CHAT-004-5090-20261013.receipt.md). KAH-CHAT-005 5090: resolver FAIL, [receipt](live-stobe-queue/KAH-CHAT-005-5090-20261014.receipt.md). KAH-TRAVEL-DEST-BASELINE-001 5090: preference-only PASS, [receipt](live-stobe-queue/KAH-TRAVEL-DEST-BASELINE-001-5090-20261014.receipt.md). 4080 baseline: FAIL conversation, [receipt](../pending-fixes/rig4080-validation/travel-destination-baseline-001-4080i3-20261014.md). Overall PARTIAL with observed failures. | `/root/coarse_region_goal_integration` is the recorded integration owner; release coordination owns exact composition/install. Next: test an NPC-selected supported point/area, consent, and movement as distinct transitions on an exact installed pair. |
| Broad purpose-based search | H033 records: “Confirmed: that is what I want. Could goals support generic purpose-based search (hunt crabs, clear bandits, get meat, find iron) using game-state approximate locations? These are examples, not hardcoded requests.” The examples are illustrative, not fixed prompts or hardcoded targets. | Existing catalog/observed-source candidate has offline focused Hunt, activity, and discovery-enrichment fixtures; see [5090 validation](../pending-fixes/npc-immersion/combined-release-destination-discovery-incomplete-hunt-20261013/VALIDATION-5090.md) and [4080 discovery receipt](../pending-fixes/rig4080-validation/activity-discovery-4080-runtime-20261013.md). HANDOFF also records prior live offer failures and a stale Mine proposal before acceptance/action; native validation rejected the stale/null target. These do not prove a full live search-to-completion loop. Known/observed reachable sources are narrower than autonomous search of unseen areas. | `activity_discovery_server_integration`; release owner `nav_owner`. After composed install, verify fresh game-grounded offer, route, arrival, fresh scan, action, and terminal result. Keep unseen-region search deferred unless separately authorized and implemented. |
| Explicit broad-finder deferral | H050 records: “Why is current implementation narrower than the full idea? Build the full idea except the broader purpose-based destination finder for now.” H053 records: “Build the first two parts of that finder, build them, review current work, and use more agents if faster.” The meaning of “first two parts” is unspecified. | Broad autonomous search was explicitly deferred by H050. H053 authorizes some finder work but does not define which parts; the record does not clearly revoke deferral of the broader finder as a whole. | Preserve the ambiguity. Do not treat later implementation scope as evidence that the broad finder was authorized or complete. |
| Activity extension and goal lifecycle | H054 records: “Start hunting/mining/camp activities as an isolated extension, so I can test navigation without affecting it; later integrate it.” H055 records: “Explain how activities extend the goal system with an example; list goal activities.” The audit notes H055 requested an explanation/list, not runtime acceptance. | Offline native/server prerequisites have receipts, but the seven live AG-GAME-001–007 emitters are blocked because ACTIVITY_COMPOSED_RELEASE_SHA256 is unsupplied and the activity package is uninstalled. See [activity queue README](live-activity-queue/README.md), [activity status](../pending-fixes/activity-goals-main/STATUS.md), and [release-gate receipt](../pending-fixes/activity-goals-main/release-gate-validation-20261013.md). No full live activity result exists. | `activity_goals_remediation` and `activity_discovery_server_integration`; release coordinator supplies exact reviewed composition. Then run AG-GAME-001 scope/proposal, 002 route/arrival/rescan, 003 Hunt, 004 Mine, 005 ClearGroup, 006 cancel/revoke, and 007 source unavailable on both verified isolated rigs. |
| Named map areas and travel lifecycle | H032 records: “Laru invited me toward an eastern ridge; after I agreed, she said she needed a place she could find. Fix NPCs choosing destinations and honoring described areas, then summarize the plan.” H157 records the later Icthy follow-up as support for named map areas (Vain/Pits) and rough plans despite an uncertain exact point. The available H157 entry is a summary, not a verbatim message. The travel packet defines lore inquiry as not consent (TL-004); no direct-user source for that exact distinction was found in the reviewed chronology. | **No runtime result.** TL-001–012 are reviewed instruction packets only, NOT RUNNABLE / NOT QUEUED / NOT EXECUTED; [README](live-stobe-queue/travel-lifecycle-p0-20261013/README.md) states exact pair/install/session gates. TL-005 leaves unresolved whether a coarse region plan replaces or coexists with a prior local leg; TL-010 has no safe cancellation trigger. Offline fixture evidence is mixed: [4080 receipt](../pending-fixes/rig4080-validation/coarse-region-integration-runtime-20261013.md) says the latest reviewed rerun passed `COARSE-REGION-LIFECYCLE` with 52 assertions, but explicitly no game/save/server/DB was used; [5090 receipt](../pending-fixes/today-dialogue-fixes/coarse-region-integration/validation-5090-offline-receipt-B6DC360C.md) is a local PHP fixture that failed the “map/lore question remains NONE” assertion. Earlier 4080 setup/fixture failures were superseded by its corrected latest rerun. These receipt scopes differ from the goals-audit prose describing physical-host lore failures; neither receipt is runtime evidence, and the installed lifecycle remains unproven. | `/root/coarse_region_goal_integration` is the recorded integration owner; release coordinator and queue supervisor own the pair/execution gates. Reconcile the offline fixture failure, then after exact reviewed install run lore with an active trip, explicit area proposal, supported endpoint, no endpoint, and read failure; keep consent, start, completion, and cancellation as separate assertions. |
| Camp | H054 includes “camp”; the current activity classes and AG-GAME packets cover Hunt, Mine, and ClearGroup, with no camp implementation/row found. | UNMAPPED / UNRUN. Do not silently equate camp with one of the other activity types. | No camp owner is recorded. Map the intended camp behavior to a source and test row before claiming coverage. |

## Coverage snapshot and open gaps

- Across the 21 numbered requirements, no full requirement has a PASS. Current classifications are 11 PARTIAL, 7 GATED, 2 UNRUN, and 1 FAIL. B07 is the direct current-build failure: KAH-CHAT-005 rejected a generated alternative before speech.
- The “Vain” preference result is limited to preference discovery: structured decision and destination were NONE/empty, with no agreement, order, or trip. It does not pass destination choice, area travel, shared-plan recall, or lifecycle requirements.
- Offline/source evidence is not an installed release. Current composed server/native candidates remain held behind exact pair, copied-save, session, and runtime gates; the activity package is uninstalled.
- Activity emitters AG-GAME-001–007 and travel packets TL-001–012 are authored test IDs, not executed results. The current live game evidence does not prove the full NPC plan → destination/area → consent → travel → arrival → activity → completion chain.
- H033’s examples are illustrative; H050 defers the broader purpose-based finder; H053 authorizes unspecified “first two parts”; H054 separately authorizes the hunting/mining/camp activity extension; H055 asks for explanation/listing only, not runtime acceptance. Camp behavior remains unmapped.
