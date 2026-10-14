#!/usr/bin/env bash
# Immutable operator packet emitter. Prints instructions only; never sends commands.
cat <<'ROW'
ROW TL-012 — unrelated or terminal turn does not imply “on my way”
Status: NOT RUNNABLE / NOT QUEUED / NOT EXECUTED. No rig or queue action is authorized.
Source: r-v3/r3.md: unrelated/terminal turns do not become “on my way”; stop on backend order/queue terms.
Authored player probe: “What else is going on?” maps to R3’s unrelated-turn rule: an unrelated/terminal turn must not be interpreted as travel start or narrated as “on my way.” This is a player input; evaluate raw state, final semantics, and action list without requiring an unsourced exact reply string.
Candidate refs only: Stobe DLL 128171DCA37821BCB254C601BD7145E9888EB22DC7CE33B3F3497C1283827620; source manifest 88D85D31A2D75CFD6CDAD49E54529411B61F7114985693DBC2B199357352846D; server source manifest E4168F120D8ED9E0530256C7495033E254A68FAFBBDC79636B8661D46015645D; payload 67DBAACDDBFB322E48EC02CBDCB1D68CA206368CC4CB9149232634C870FFB604. Exact release/install pins and isolated paired save/backend/session/load/world/actor/fixture/readback are PENDING.
Action after all gates: use a fresh branch with a terminal or unrelated state fixed by the reviewed fixture. Capture state, send the authored probe once, then capture raw state/final reply/actions. Do not dispatch or mutate travel state.
Evidence: exact input, actor/trip/request/load/world/freshness, raw model output and final reply, backend/native records, before/after trip/event/outbox, and all hash receipts. PASS only if no “on my way” or equivalent present-progress claim, no trip/action creation, and no backend order/queue terms leak into player-facing text.
One line: `RESULT TL-012 PASS|FAIL <fixture scope, exact reply/action and receipts>`.
Current status BLOCKED until fixture/readback route and exact release/runtime pins exist. No retry or cleanup mutation. Rig-specific recipes are NOT SOURCEABLE YET.
ROW
