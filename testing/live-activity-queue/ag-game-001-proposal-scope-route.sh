#!/usr/bin/env bash
# Immutable AG-GAME-001 emitter. Prints the row packet only.
cat <<'ROW'
ROW AG-GAME-001 — grounded proposal and exact activity/route scope binding
STATUS: BLOCKED. Required `ACTIVITY_COMPOSED_RELEASE_SHA256` has not been supplied. Known component hashes do not satisfy this gate. Do not issue chat or accept an offer until the composed exact release is reviewed, installed, loaded, and recorded on this rig.
Run separately on 4080 and 5090 where each has the same verified composition on an isolated copied save/private matching backend. Preflight must record rig/instance/PID, save identity, native SHA, server manifest/component manifest, composed SHA, schema/API version, private transport/session readiness, actor/requester/world identity, and fresh native observations.

Select exactly one currently observed suitable activity source and one currently observed reachable native route candidate from authenticated context. Do not invent labels, IDs, endpoints, coordinates, resources, quantities, or targets. Record activity `discoveryRef` and route `routeRef.candidateId` separately. Use one grounded purpose (Hunt, Mine, or ClearGroup); ClearGroup must have the fixed agreed target serial set. A model-selected route ID is not enough: preserve the server-reconstructed exact route kind/label/endpoint and actor/world identity.

After release gates clear, use a single natural direct KAH request based only on the displayed current observations; capture the exact utterance and NPC reply. If an offer is displayed, accept only if exact activity kind/source/resource/quantity/target set and exact route candidate/endpoint are unchanged and visibly bound in the authenticated activity record. Do not accept altered, stale, cross-actor, cross-world, or ungrounded terms. No native order/action is expected from proposal alone.

Required receipt: proposal record ID/revision/status; authenticated actor/requester/world; displayed and persisted activity scope; separate route candidate ID and server-reconstructed route facts; explicit acceptance evidence and scoped grant envelope if acceptance is tested; native activity outbox/ack correlation; no unrelated travel/deal/order dispatch. Preserve before/after activity record and native logs.
Bound: one proposal/acceptance turn, maximum 5 real minutes after ready; if no grounded offer or matching route appears, end as INCONCLUSIVE/FAIL closed with no acceptance.
PASS: RESULT AG-GAME-001 PASS rig=<4080|5090> composed_sha=<exact> activity=<kind/source/resource/qty-or-targets> grant=<record/revision> route=<candidateId/kind/label/endpoint> actor_world=<receipt> native_ack=<receipt> unrelated_dispatch=none
Setup: RESULT AG-GAME-001 FAIL setup: <specific release/rig/save/schema/session/source/route gate and receipt>
Evidence: RESULT AG-GAME-001 FAIL evidence: <specific missing scope/route/grant/native-ack receipt>
ROW
