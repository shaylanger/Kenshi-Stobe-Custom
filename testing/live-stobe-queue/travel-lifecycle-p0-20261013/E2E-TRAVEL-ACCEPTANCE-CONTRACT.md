# P0 travel agreement → actual trip: end-to-end test contract

Date: 2026-10-14  
Owner: travel E2E test contract  
State: authored contract; **not runnable yet**. This document adds no product-code changes and authorizes no game, save, server, rig, or queue actions.

## Goal and pass definition

Prove that one NPC's explicit offer, the player's acceptance, the persisted agreement, native-owned start, movement, arrival, and cleanup all describe one immutable trip. Speech is evidence of dialogue only; it never proves dispatch, movement, arrival, or cleanup. A full E2E PASS requires every stage below to pass on the same actor, speaker, agreement, destination, session/load/world scope, and compatible native/server build pair. A missing signal is `FAIL evidence`, not a product PASS.

The contract complements the frozen TL rows in this directory; it does not supersede their safety gates or authorize the candidate hashes listed in `README.md`.

## Required identity tuple

Capture and correlate this tuple at every transition:

`{campaign_id, session_generation, load_id, world_id, actor_id+serial, speaker_id+serial, agreement_id, trip_id, offer_id, endpoint_id, destination label+coordinates, request_id, native_task_id, game_tick}`

Fields that are not supported by a current read-only source must be reported as unavailable. Do not infer identity from NPC name, speech text, current selection, or a stale log line. The tuple must remain immutable from accepted consent through terminal state, except monotonic lifecycle phase/timestamps and documented native task identifiers.

## End-to-end rows

Each row uses a fresh disposable branch or a source-reviewed pre-existing state. Rows must not manufacture database rows, inject native orders, teleport, cancel unrelated work, or mutate production state. Capture before/after state and raw/final model decision, server action, event/outbox delta, native receipt, and read-only status view where applicable.

| ID | Scenario | Required assertions | Evidence / failure rule |
|---|---|---|---|
| E2E-01 | Offer then clarification/questions | Offer is tied to actor/speaker and endpoint. Questions, acknowledgements, pace, quote-as-question, and regional lore do not accept, dispatch, rotate the endpoint, or erase the offer. | Reuse TL-001 probes. Exact before/after agreement/event/action diff; any mutation is product FAIL. |
| E2E-02 | Explicit acceptance with refreshed observation IDs | Accept once after the offer has been re-observed under changed observation/message IDs. Preserve the original offer/agreement/endpoint and destination; create one accepted transition. | Pair raw offer and accepted state by stable agreement/offer IDs; observation IDs may differ. No exact state readback means FAIL evidence. |
| E2E-03 | Duplicate acceptance | Repeat the same affirmative after acceptance. No new agreement, event, dispatch, or changed destination; reply acknowledges existing plan naturally without repeating rules. | Reuse TL-002; compare durable state and event/outbox counts. |
| E2E-04 | Start request and native-owned dispatch | “Lead the way” against an eligible accepted agreement yields exactly one native-owned task for that actor and exact endpoint. Matching ACK is fresh and scoped to the same request/world/load; stale, mismatched, or ambiguous ACK cannot claim that travel started. | Reuse TL-003, TL-008, TL-009. Capture order/event plus native task and ACK. `REQUESTED` alone is not a start. |
| E2E-05 | Movement over multiple game ticks | Same actor remains alive/conscious/path-valid, retains exact destination, and moves toward it in at least two successive game-time intervals with net progress. No duplicate task/order appears. | Use the existing `p0-owned-progress.sh` movement sampler; retain each state sample and log offset. If sampling cannot expose task owner/destination or game tick, mark FAIL evidence. |
| E2E-06 | Arrival then exact cleanup | Native endpoint-reached evidence (not merely entering a rough search radius) transitions this agreement to completed; one completion acknowledgement, only its owned movement/task is released, and unrelated native jobs remain. | Existing TL-011 covers truthful completed wording, not the complete native arrival/cleanup assertion. Add read-only task/receipt comparison before/after. No safe ownership-specific cleanup oracle currently documented: row blocked pending instrumentation. |
| E2E-07 | Status view through lifecycle | “Right Now/Dealings” shows this NPC-led agreement and its true phase: proposed/accepted/requested/moving/arrived/completed/cancelled/failed. Never report “on the way” before fresh native ACK; never show stale/other-actor trip. | Capture UI/status output and compare against native/server state after each transition. No current UI snapshot adapter is pinned in the frozen P0 packet. |
| E2E-08 | Ambiguous or failed dispatch | Simulate only a reviewed safe transport/native failure fixture. Keep agreement and truthful phase; do not claim started/moving, do not retry into duplicate native tasks, and allow a later explicit retry only if semantics define it. | Existing TL-008/TL-009 cover no-start and bad ACK truthfulness. No live fault injection or safe runtime failure switch is approved; use offline fixture until reviewed. |
| E2E-09 | Reload / stale receipt | On a copied save/session reload, old ACK/task cannot authorize current movement claims. Preserve durable accepted plan only if current authenticated load policy says so; otherwise explain it expired/needs reconfirmation. | Capture old/new load/session IDs and status read. Current native status reader explicitly lacks KAH session-generation binding; full row blocked until that seam exists. |
| E2E-10 | Hostile relation | Hostile NPC refuses ordinary voluntary following from conversation opening; no proposal/acceptance/dispatch is created. A specifically supported hostile/fight arrangement must remain a separate action and cannot inherit travel consent. | Fresh hostile and neutral control branches; compare first response, lifecycle, and native task. Existing prompt/policy tests are static; no live model pass. |
| E2E-11 | Changed plan / endpoint | A blocked/changed route is explained as a change to the original plan. Any alternative destination, leader, or purpose requires explicit new consent; stale plan rejection must not be repeated after a matching agreement. | No immutable-plan-change scenario is in TL-001..012. Add after exact change semantics and state oracle are approved. |
| E2E-12 | Region-only discussion vs regional travel | Lore/question about Vain/Pits preserves current agreement and causes no action. Explicit regional intent may create a coarse proposal only with grounded region evidence and disclosed uncertainty; agreement to a specific endpoint is still required before dispatch. | Reuse TL-004..007. Assert no point/action for lore/no-endpoint, one coarse proposal for supported region, then run normal consent/start gates for selected endpoint. |

## Harness observability audit

Available in the frozen harness packet:

- `p0-final-invocation` driver can record target speech, server native-inbox deltas, exact actor handle, current state/position, `TRAVEL_LOCATION` action deltas, repeated action counts, movement samples, destination proximity, and terminal actor state. It has a tested “do not send acceptance until exact NPC offer is observed” gate.
- TL-001..012 define speech probes and require before/after lifecycle/event/outbox snapshots, fresh matching ACK checks, and truthful state language.
- The current native status-reader source binding provides actor/speaker/agreement/request/world/time checks and separate terminal arrival vs cleanup fields. Its integration note says it cannot read KAH `session_generation`; full generation binding is unavailable.
- The coarse-region fixture exercises consent and ordinary order validation offline, but it does not establish native dispatch/progress/arrival.

Not sufficiently observable / must be supplied before live PASS:

1. **One supported read-only lifecycle/event/outbox oracle** returning stable agreement/trip/offer/endpoint IDs and per-transition event counts. Existing packet instructions require this but do not provide a runnable current-build command.
2. **Native task ownership and cleanup oracle** proving the exact task belongs to this agreement and that only that task was cleared at terminal completion. Existing movement sampling can inspect AI/destination; it does not prove scoped cleanup is safe.
3. **Session-generation binding** across KAH and native travel receipt. Native status reader documents this gap; attach an independently authenticated KAH receipt or add a supported binding before claiming full tuple integrity.
4. **UI status capture** tied to exact target and lifecycle phase. No pinned adapter/receipt is in the frozen TL packet.
5. **Reviewed safe fixtures** for failed dispatch, reload/stale ACK, changed-plan/cancel, hostile relation, and exact arrival. Do not create these by direct DB writes or live fault injection.

## Execution gates and result format

Keep the frozen README gates: exact composed native/server pair review, current installed hashes, copied-save manifest, backend/session/load/world identity, actor map, proposal/trip/agreement/point IDs, and readback/event/ACK procedure. The TL README marks its hashes as candidate references only and the pair release gate absent. Therefore this contract is **not queued or runnable today**.

For every row emit exactly one line:

`RESULT E2E-nn PASS|FAIL product|FAIL evidence|FAIL setup|INCONCLUSIVE <stable IDs, observed phase/action/event counts, movement deltas, receipt paths>`

Full end-to-end travel PASS requires E2E-01 through E2E-12, with each gated subrow either passed or explicitly classified by approved scope. Setup/evidence failures do not count as product failures or passes. Never weaken assertions to turn unavailable instrumentation into PASS.

## Existing packet checks performed for this contract

- Read frozen `README.md`, TL-001, TL-003 and the current `p0-owned-progress.sh` / `p0-start-move-invocation.sh` sources. The emitters are instruction-only and explicitly NOT RUNNABLE / NOT QUEUED / NOT EXECUTED.
- Reviewed current coarse-region exact-source review and native status-reader integration note. Region fixture has current owner-run 61-assertion PASS and 9-file lint receipt; independent re-run was blocked by WSL `E_ACCESSDENIED`. This is offline evidence only.
- No product source, build, install, game, save, server, or queue was changed or exercised.

