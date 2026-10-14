#!/usr/bin/env bash
# Immutable operator packet emitter. Prints instructions only; never sends commands.
cat <<'ROW'
ROW TL-004 — regional lore is NONE and preserves the accepted local trip
Status: NOT RUNNABLE / NOT QUEUED / NOT EXECUTED. No rig or queue action is authorized.
Sources: c-v2/C6.md (exact utterances and byte-for-byte trip rule), r-v3/r4.md (lore decision NONE); the authored row probes are the exact frozen C6 inputs “What do you know about Vain/the Pits?” and “Have you been there?”
Prerequisite: disposable isolated branch with one verified accepted local trip and exact trip/actor/session/world identities; route/provenance readback and byte-level state comparison must be documented. Separate a fresh copy for the row if required by the fixture owner. Do not alter trip state to make the test pass.
Candidate pair references (not release authorization): Stobe DLL 128171DCA37821BCB254C601BD7145E9888EB22DC7CE33B3F3497C1283827620; source manifest 88D85D31A2D75CFD6CDAD49E54529411B61F7114985693DBC2B199357352846D; server source manifest E4168F120D8ED9E0530256C7495033E254A68FAFBBDC79636B8661D46015645D; payload 67DBAACDDBFB322E48EC02CBDCB1D68CA206368CC4CB9149232634C870FFB604. Pair release review, current installed hashes, save/backend/session/world, active-trip snapshot, and read-only route/event/outbox procedure remain PENDING.
Action: Record the full existing trip bytes/fields and event/outbox baseline. Send each exact lore utterance once to the same verified actor, one at a time. Capture answer and post-turn state after each. No explicit travel request in this row.
PASS only if each turn is NONE/no action and the accepted local trip is byte-for-byte unchanged, with no event/outbox additions or destination/point/consent mutation. Require native inbox/reply, correlated backend raw/final/decision, knowledge/source fields, actor/trip IDs, before/after byte comparison, and exact hashes/receipt paths. Speech alone is not PASS.
Exactly one terminal line: `RESULT TL-004 PASS|FAIL <lore decisions, unchanged trip bytes, event/outbox diff and receipts>`.
Fail closed: missing byte-readback method or state pin is setup/evidence failure; lore yielding PROPOSE/ACCEPT, trip change, invented fact beyond evidence, or action/event is product failure only with complete scoped receipts. No cleanup mutation.
The R4 “where does the route go?” probe is excluded: the cited packet explicitly says that exact text is not source-frozen. Do not paraphrase or invent it.
Rig-specific recipes are NOT SOURCEABLE YET for this candidate. Queue supervisor must pin a fresh isolated copy and operator must reverify installed build/backend/session/actor.
ROW
