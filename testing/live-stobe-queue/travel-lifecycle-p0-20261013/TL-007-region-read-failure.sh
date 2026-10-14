#!/usr/bin/env bash
# Immutable operator packet emitter. Prints instructions only; never sends commands.
cat <<'ROW'
ROW TL-007 — regional endpoint read failure fails closed
Status: NOT RUNNABLE / NOT QUEUED / NOT EXECUTED. No rig, save, backend, service, or queue action is authorized.
Sources: r-v3/r4.md (failed read must say routing cannot be confirmed and must produce no point/event/action), c-v2/C6.md (no endpoint/read failure means no trip write). Exact input: “Would you lead me to the Pits?”
Prerequisite: separate disposable isolated fixture with a review-pinned, safe endpoint-read failure mode and a receipt proving the read failed. No fault injection method is named in the source plans; absent an independently reviewed failure fixture, this row remains BLOCKED. Do not create a failure by editing DB/files or inventing a KAH command.
Candidate hashes only: Stobe DLL 128171DCA37821BCB254C601BD7145E9888EB22DC7CE33B3F3497C1283827620; source manifest 88D85D31A2D75CFD6CDAD49E54529411B61F7114985693DBC2B199357352846D; server source manifest E4168F120D8ED9E0530256C7495033E254A68FAFBBDC79636B8661D46015645D; payload 67DBAACDDBFB322E48EC02CBDCB1D68CA206368CC4CB9149232634C870FFB604. Exact pair release review, installed hashes, copied-save/backend/session/world/actor, current fixture hash, and readback are PENDING.
Action after all gates: capture trip/event/outbox baseline and the endpoint-read-failure receipt; send the exact request once; capture exact reply/decision and full after-state. No retry, acceptance, start, order, or dispatch.
PASS only if the reply states routing cannot be confirmed and there is no trip/proposal/point/event/action write; preserve the existing trip byte-for-byte if present. Correlate native inbox/reply, backend decision, failure receipt, actor/trip IDs, before/after state and hashes.
One line: `RESULT TL-007 PASS|FAIL <read-failure proof, no-write diff and receipt paths>`.
Before-send missing failure fixture/pins is `FAIL setup: ...`; missing post-send records is `FAIL evidence: ...`; invented route or any write/action is `FAIL product: ...` only with complete scoped evidence. No cleanup mutation. Current row is blocked pending a reviewed read-failure fixture.
Rig-specific recipes are NOT SOURCEABLE YET for current candidate pair. Do not queue or execute.
ROW
