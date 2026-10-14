#!/usr/bin/env bash
# Immutable operator packet emitter. Prints instructions only; never sends commands.
cat <<'ROW'
ROW TL-006 — explicit regional request with no proven endpoint fails closed
Status: NOT RUNNABLE / NOT QUEUED / NOT EXECUTED. No rig, save, backend, or queue action is authorized.
Sources: c-v2/C6.md and r-v3/r4.md. Exact input: “Would you lead me to the Pits?” Expected on no supported endpoint: say routing cannot be confirmed; no trip write, point, event, or action.
Prerequisite: separate disposable isolated branch with a reviewed fixture proving the resolver returns no endpoint for this actor/world. A missing or undocumented endpoint-read method is a setup/tooling gap, not evidence of no endpoint. Preserve an accepted local trip only if the fixture's reviewed transition baseline confirms this branch; capture it byte-for-byte.
Candidate hashes only: Stobe DLL 128171DCA37821BCB254C601BD7145E9888EB22DC7CE33B3F3497C1283827620; source manifest 88D85D31A2D75CFD6CDAD49E54529411B61F7114985693DBC2B199357352846D; server source manifest E4168F120D8ED9E0530256C7495033E254A68FAFBBDC79636B8661D46015645D; payload 67DBAACDDBFB322E48EC02CBDCB1D68CA206368CC4CB9149232634C870FFB604. Pair release review, exact installed hashes, copied save/backend/session/world/actor, resolver fixture/current hash, and state/event readback procedure remain PENDING.
Action: Before send, record the resolver's no-endpoint receipt plus trip/event/outbox baseline. Send the exact request once. Record exact native/backend result and after-state; do not accept or dispatch and do not repeat.
PASS only if the system reports routing cannot be confirmed and creates no proposal/trip/point/event/action, with all correlated evidence and unchanged baseline. One terminal line: `RESULT TL-006 PASS|FAIL <no-endpoint proof, unchanged trip/event state and receipt paths>`.
Pre-send mismatch/missing resolver proof is `FAIL setup: ...`; post-send missing receipts is `FAIL evidence: ...`; fabricated destination or any write/action despite verified no endpoint is `FAIL product: ...` only with complete evidence. No cleanup mutation.
The existing sources have no exact utterance for R4's “where does the route go?” question; omitted. Rig-specific recipes are NOT SOURCEABLE YET for current candidate pair.
ROW
