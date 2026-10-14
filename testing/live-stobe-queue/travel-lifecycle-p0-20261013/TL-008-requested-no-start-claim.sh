#!/usr/bin/env bash
# Immutable operator packet emitter. Prints instructions only; never sends commands.
cat <<'ROW'
ROW TL-008 — REQUESTED is not a started trip
Status: NOT RUNNABLE / NOT QUEUED / NOT EXECUTED. No rig or queue action is authorized.
Source: r-v3/r3.md. Expected: requested says movement is unconfirmed in plain words; no present-progress claim without a matching fresh native start receipt.
Authored player probe: “Are we moving yet?” This maps to R3’s supported REQUESTED behavior (“movement is unconfirmed in plain words”); judge the raw/final answer and state, not an unprovided historical transcript or exact reply string. This is a player input, not invented NPC dialogue.
Required candidate references (not install authorization): Stobe DLL 128171DCA37821BCB254C601BD7145E9888EB22DC7CE33B3F3497C1283827620; source manifest 88D85D31A2D75CFD6CDAD49E54529411B61F7114985693DBC2B199357352846D; server source manifest E4168F120D8ED9E0530256C7495033E254A68FAFBBDC79636B8661D46015645D; payload 67DBAACDDBFB322E48EC02CBDCB1D68CA206368CC4CB9149232634C870FFB604. Exact pair review, installed hashes, copied-save/backend/session/load/world/actor, REQUESTED fixture, and raw-state/rendered-reply procedure are PENDING.
Action after all gates: obtain REQUESTED lifecycle without any start receipt through a reviewed natural or fixture path; capture exact scoped raw state. Send the authored probe once. No native order, movement trigger, stale receipt, or retry.
Evidence: exact request and no-start native receipt state; actor/trip/request/load/world identity; freshness; before/after lifecycle; exact raw model output and final rendered reply; native/backend correlation; action/event/outbox diff; all hash receipts. PASS only if movement is explicitly unconfirmed and no present-progress claim/action occurs.
One terminal line: `RESULT TL-008 PASS|FAIL <REQUESTED state, no-start proof, exact reply and receipt paths>`.
Use setup/evidence/product/inconclusive classifications as in R3. No cleanup mutation. Rig-specific recipes are NOT SOURCEABLE YET for this candidate pair.
ROW
