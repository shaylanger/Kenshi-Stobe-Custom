#!/usr/bin/env bash
# Immutable operator packet emitter. Prints instructions only; never sends commands.
cat <<'ROW'
ROW TL-010 — CANCELLED status is truthful and terminal
Status: NOT RUNNABLE / NOT QUEUED / NOT EXECUTED. No cancellation is performed by this row.
Source: r-v3/r3.md (cancelled language matches state; unrelated/terminal turns do not become “on my way”). This packet tests only a pre-existing CANCELLED terminal state.
Authored player probe: “What is the status of our trip?” maps to R3’s CANCELLED-status truthfulness intent. This row observes a pre-existing cancelled fixture only; it does not cancel a live trip. Score semantic agreement with the pinned raw state, not an unsourced exact reply string. The separate END/cancel wording trigger branch from R3 is explicitly BLOCKED and not covered here until a safe disposable fixture and exact supported trigger are reviewed.
Candidate refs (not authorization): DLL 128171DCA37821BCB254C601BD7145E9888EB22DC7CE33B3F3497C1283827620; source manifest 88D85D31A2D75CFD6CDAD49E54529411B61F7114985693DBC2B199357352846D; server source manifest E4168F120D8ED9E0530256C7495033E254A68FAFBBDC79636B8661D46015645D; payload 67DBAACDDBFB322E48EC02CBDCB1D68CA206368CC4CB9149232634C870FFB604. Release review/install hashes, isolated save/backend/session/load/world/actor, cancelled fixture and read-only receipts all PENDING.
Action after gates: verify exact CANCELLED lifecycle and event state before send. Send the authored probe once. Do not issue cancel or end commands. Capture exact final reply/raw state and before/after lifecycle.
Evidence: actor/trip/request/load/world scope, exact CANCELLED raw state, turn/raw model/final reply/action/event, native/backend correlation, no active start and timestamps. PASS only when cancelled wording matches state and no “on my way”/present-progress claim or action occurs.
One line: `RESULT TL-010 PASS|FAIL <CANCELLED state, exact reply/action and receipts>`.
Stop on any pin mismatch or inability to prove cancelled state. No cleanup mutation. Rig-specific recipes are NOT SOURCEABLE YET. Do not count this row as coverage of an END/cancel request.
ROW
