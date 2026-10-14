#!/usr/bin/env bash
# Immutable gameplay-row packet emitter. Prints instructions only; never sends commands.
cat <<'ROW'
PACKET SOCIAL-REPAIR-TERMS-REFUSAL-COMPLETION — exact-candidate gameplay rows
STATUS: NOT RUNNABLE. Offline packet authoring does not stage, install, or authorize gameplay.

Frozen candidate identity (SHA-256):
  Stobe DLL:         842CEB786F338FFE06258F80E0CC0D96C8C1938F3F9F1115A0890EF21AF25FA8
  Source manifest:   7EAF6C685565C6208AD2D3CE9ED7BF0CCA9DC7D7865D06323A2AB9AEAFCD9691
  Payload manifest:  4DAEE651F39FC20029E5E2A4CC4671CA23E677CC2E036F16E70167F347494BCB
  Server manifest:   525EDA0D0E760F7A5775AF90E18B37C6CCA80699DD2048CEFD8952D324277C62

Important pin correction: the 63-hex Stobe value supplied in the dispatch request ended in
`...AF25FA`; the frozen build receipt and current queue ledger both give the complete
64-hex SHA-256 above, ending `...AF25FA8`. Use only the complete value printed here.

Run scope and authority:
  Both rigs: 5090 and 4080, independent copied-save runs, after the release composer and
  sole rig operators have prepared their isolated routes. Queue supervisor maps these rows
  into rig queues and records eligibility. Rig operators alone execute them later. This
  emitter itself makes no queue insertion and issues no rig, KAH, backend, or game command.
  Never use a personal/shared save, shared-Steam install, or shared/production backend.

Blocking gates — before any utterance or handover, verify and attach receipts for all:
  1. Reviewed staging receipt for this exact candidate and matching composed server source.
  2. Exact full Stobe DLL, source-manifest, payload-manifest, and composed server-manifest
     hashes above in the staged package and in the running process/backend source identity.
  3. Exact loaded Stobe module hash on the rig; no hash-prefix matching.
  4. Safe copied-save identity and manifest, copied-save origin, and successful isolated
     load; prove the save/backend pair is dedicated to this rig and disposable.
  5. Backend host/port, private isolated instance identity, campaign, timeline epoch,
     native session ID, actor and NPC durable storage identities, and request correlation
     are recorded and match between game, native receipts, and backend.
  6. Read-only native relationship baseline and canonical backend relationship/grievance
     baseline for the same actor/NPC pair. Preserve exact grievance ID, incident ID,
     participant identities, harm, known owed/returned/remaining quantities, trust impact,
     and current affinity. Do not infer identity or item lineage by display name.
  7. Current test world is safe, the NPC is directly addressable, and no unrelated trip,
     contract, combat, or pending handover can confound the row. No unchanged retries.

If any gate is absent, changed, or ambiguous, stop before sending and emit
`RESULT SOCIAL-REPAIR-<case> FAIL setup: <gate and observed evidence>` for each affected
case. Missing candidate staging, composed-source identity, installed hashes, or copied-save/
backend identity always keeps this packet NOT RUNNABLE. A later operator may mark it eligible
only by attaching all receipts and the queue supervisor's explicit exact-hash mapping.

Evidence contract shared by every case:
  Record one time-correlated bundle per case: exact player utterance/action; native Stobe
  `TEST_INBOX: say` and native NPC reply (or native action/relationship event for a handover);
  backend request ID and exact request payload; model/backend result and response delivery
  correlation; terminal dialogue/action completion record; durable social incident,
  relationship, agreement/term, and material-receipt state before and after; plus native
  relationship readout before and after. Record actual outputs and durable IDs, not just
  command ACKs or plausible wording. If the backend does not expose a named delivery or
  completion record, preserve the exact correlated event/log evidence and label the gap;
  never manufacture a PASS. Relationship readers must be supported read-only reads. Do not
  use commands that change affinity to create a test baseline.

Covered gameplay cases (run each independently on both rigs):

1. SOCIAL-REPAIR-TERMS — explicit, incident-bound proposed repair terms
   Starting state: one exact, already-recorded grievance with known original item prototype
   and quantity, and a current residual penalty. Use the established negotiation/dialogue
   path to ask about returning a specific quantity of that original stolen item for that
   exact grievance. Do not ask the model to invent an incident, identity, quantity, consent,
   proof, or affinity reward. If the supported deal UI/API cannot express the term, stop as
   `INCONCLUSIVE` and report the missing surface; do not improvise a new endpoint.
   PASS requires native utterance/reply plus correlated backend request, delivered terms,
   and terminal proposal record; exact player/NPC durable identities and grievance binding;
   accepted term fields and deadline/contract ID if accepted; before/after native and
   canonical relationship values; and proof that a proposal alone caused no item transfer,
   agreement acceptance, affinity reward, debt reduction, or action dispatch. A term may be
   tested only when the accepted contract is explicit and its exact term state is persisted.
   RESULT SOCIAL-REPAIR-TERMS PASS|FAIL <native_request=... reply=... backend_request=... delivery=... completion=... grievance=... terms=... relation_before_after=... no_dispatch=...>

2. SOCIAL-REPAIR-REFUSAL — refusal does not accept, dispatch, or grant repair credit
   Ask the NPC once about a clear, bounded repair proposal for the same grievance, then
   refuse the NPC's proposed terms once through the supported dialogue/negotiation path.
   Do not accept any alternate offer and do not perform a handover. If the NPC does not
   actually offer terms, report `INCONCLUSIVE` rather than fabricating a refusal branch.
   PASS requires native request/reply and correlated backend request, response delivery,
   and terminal refusal/contract state; explicit refusal recorded against the exact proposal;
   no accepted/active repair agreement, no repair action ticket emitted to native dispatch,
   no GIVE_ITEM/RETURN_ITEM action or movement/task dispatch, no canonical apology or
   restitution credit, and unchanged debt plus relationship values except independently
   evidenced ordinary dialogue effects allowed by current controls. Repeat only if the
   source-supported duplicate/idempotence check can resend the same refusal request identity
   without a new player action; a retry must not create another deal/event or alter state.
   RESULT SOCIAL-REPAIR-REFUSAL PASS|FAIL <native_request=... reply=... backend_request=... delivery=... completion=... refusal_state=... tickets=none actions=none debt_before_after=... relation_before_after=... duplicate=...>

3. SOCIAL-REPAIR-COMPLETION — evidence-backed fulfillment, residual grievance preserved
   Use only an explicit, persisted agreement whose player obligation is a unique exact
   original-item return tied to the same grievance and whose ticket/term identity is shown
   in the receipts. Perform only the existing manual player-to-NPC give-item handover.
   Never substitute a purchase, generic gift, inferred same-name item, or unsupported
   inventory drag/split/merge path. Stop if the source does not expose the required exact
   direct-handover proof or term completion readout.
   PASS requires (a) native successful handover event with actual accepted quantity and
   source/recipient inventory deltas; (b) backend request and delivered native proof receipt
   with transfer/event ID, item key, prototype, quantity, giver/recipient durable IDs,
   campaign, epoch, session and matching agreement ticket; (c) terminal backend completion
   record and persisted agreement term state VERIFIED/contract COMPLETE only when all
   accepted obligations have authoritative evidence; (d) canonical exact grievance state
   showing material debt reduced only by proven quantity, never below zero, with original
   harm/history and residual grievance/trust damage still recorded; and (e) before/after
   native and canonical relationship values. Re-deliver the exact same receipt/request only
   if the source-supported replay path is available and safe; it must not duplicate returned
   quantity, repair relief, contract allocation, or generic gift affinity. Never infer
   completion from NPC speech, HTTP success, ticket emission, inventory count alone, or a
   UI acknowledgement.
   RESULT SOCIAL-REPAIR-COMPLETION PASS|FAIL <native_handover=... backend_request=... delivery=... completion=... contract=... term_state=... grievance=... qty_before_after=... residual=... relation_before_after=... replay=...>

Canonical result rules:
  Emit exactly one terminal line for each case on each rig using the formats above.
  `PASS` requires every listed evidence item; `FAIL setup` is a gate failure before action;
  `FAIL evidence` means an action may have occurred but required correlation/state evidence
  is missing; `FAIL` with a product reason requires complete evidence showing behavior
  contrary to source contract; use `INCONCLUSIVE` when an expected path was unavailable or
  the event was not reached. Attach the durable receipt path to every non-PASS line.
  Never turn an evidence gap, unsupported path, unexecuted case, or component/offline PASS
  into a gameplay PASS.

Source requirements enforced here: canonical relationship is single-valued; apology,
emotional acceptance, restitution, remaining grievance, and restored trust are distinct;
no model text proves a transfer; repayment reduces only exact quantified material debt;
repair never erases historical harm or fully restores trust; serious/repeated harms retain
residual impact; terms bind to exact participants/session/campaign/epoch and unique proven
lineage; refusal does not accept or dispatch; duplicate speech, receipt, and allocation
cannot duplicate credit; unsupported and ambiguous provenance fails closed. Historical
theft without exact proof, arbitrary replacement items, ordinary drag/split/merge lineage,
cross-load proof, and unfinished/out-of-order contracts remain outside this packet.

END PACKET — immutable row definitions; do not edit this file after review. Corrections
require a new versioned packet path and a new hash/review.
ROW
