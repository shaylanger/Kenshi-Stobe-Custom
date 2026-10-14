# P0 travel lifecycle operator packets

**State: NOT RUNNABLE / NOT QUEUED / NOT EXECUTED.** These emitters print instructions only; they do not contact KAH, a rig, a game, a save, a backend, or a queue. No row may be scheduled until the queue supervisor and sole rig operator verify the exact composed build, server pair, isolated save/session, actor state, and row-specific evidence method.

The packets cover the requested work after the existing KAH-CHAT-003 proposal baseline:

| Order | Packet | Source / purpose | Row gate |
|---|---|---|---|
| 1 | `TL-001-consent-idempotence.sh` | C2 non-consent questions/clarifications/pace/ack and one explicit acceptance; includes one labeled authored quote-as-question probe supported by C2. | KAH-CHAT-003 PASS or separately reviewed natural/seeded proposal with exact IDs. |
| 2 | `TL-002-repeated-acceptance-idempotence.sh` | C3 repeated acceptance without duplicate transition/event. | Fresh accepted/requested branch, no start receipt. |
| 3 | `TL-003-eligible-start-matching-ack.sh` | C3 eligible “Lead the way” and matching fresh native ACK. | Accepted supported point, exact trip/request scope, no prior start. |
| 4 | `TL-008-requested-no-start-claim.sh` | R3 requested state reports movement unconfirmed. | REQUESTED state and proven absence of a start receipt. |
| 5 | `TL-009-stale-or-mismatched-ack.sh` | R3 stale/cross-actor ACK cannot authorize progress wording. | Reviewed, safe source-backed stale or mismatched receipt fixture; never forge an ACK. |
| 6 | `TL-010-cancelled-truthfulness.sh` | R3 cancelled terminal wording only. | Pre-existing cancelled fixture; row does not cancel. END/cancel trigger wording is explicitly blocked and uncovered until a safe disposable fixture and exact supported trigger are reviewed. |
| 7 | `TL-011-completed-truthfulness.sh` | R3 completed terminal wording. | Pre-existing completed fixture; row does not complete. |
| 8 | `TL-012-unrelated-terminal-turn.sh` | R3 unrelated/terminal turn cannot imply “on my way.” | Reviewed terminal/unrelated branch. |
| 9 | `TL-004-region-lore-preserves-trip.sh` | C6/R4 lore is NONE and preserves the active local trip byte-for-byte. | Accepted local trip and approved byte/readback method. |
| 10 | `TL-005-region-plan-coarse-proposal.sh` | C6/R4 explicit region request may create only a coarse PROPOSE with uncertainty; no accept/dispatch. | Proven in-region endpoint and reviewed transition semantics for the existing accepted leg. **Blocked:** source text does not define whether the prior local leg is replaced or coexists. |
| 11 | `TL-006-region-no-endpoint.sh` | C6/R4 no endpoint yields no trip/point/event/action. | Reviewed resolver fixture proving no endpoint. |
| 12 | `TL-007-region-read-failure.sh` | R4 endpoint read failure says routing cannot be confirmed and writes nothing. | Reviewed safe failure fixture; no fault injection is sourced by the plans. |

The existing KAH-CHAT-003 emitter remains unchanged and is a prerequisite, not part of this packet's checksum set. Source plan literals are preserved. Authored player probes are explicitly labeled and mapped to behavior named by C2/R3; no NPC utterance is fabricated. The R4 “where does the route go?” branch is deliberately omitted because the source packet says that exact input is not frozen. No unsupported KAH command, SQL edit, native order, teleport, cancellation, or test-state mutation is introduced.

## Candidate pins and current release gates

The exact candidate references shared across these packets are:

- Native Stobe DLL: `128171DCA37821BCB254C601BD7145E9888EB22DC7CE33B3F3497C1283827620`
- Native source manifest: `88D85D31A2D75CFD6CDAD49E54529411B61F7114985693DBC2B199357352846D`
- Native payload manifest: `D4F3998B8315C493B414A628D5C60668EC135D670D1E8109B7AF680F0D6D2FC7`
- Server source manifest: `E4168F120D8ED9E0530256C7495033E254A68FAFBBDC79636B8661D46015645D`
- Server payload: `67DBAACDDBFB322E48EC02CBDCB1D68CA206368CC4CB9149232634C870FFB604`
- Server composition: `8E25AE3C909F4307AEB31FEAFF170D4EEC702910599CAC7EDB97CE443799919E`
- Server independent component review: `A7C8CD4373C35CC18DFA902D87BB37607848B8512FB5AF4813E81DAFCEE5C5A7`
- Native independent component review: `24B63F39A0F812C09021F697D1D25A05D2D4E92A3EA3350FC38990314FCA9AF3`

These identify the current source candidates and component reviews, **not an approved or installed release pair**. The joint Activity/native-server contract review is REVISE and the pair-source gate is absent; exact pair review and `StageForValidation`, current installed hashes, disposable save manifest, backend/session/load/world identity, and row-specific readback/event/ACK procedures remain gates. Server `RELEASE_HOLD` remains in force. Component reviews and historical per-rig runtime hashes do not clear these gates.

No separate current-build 5090 or 4080 execution recipe is supplied: the existing rig routes point to older runtime pins and do not prove compatibility with this candidate pair. The authorized operators must select and record the isolated route only after pair approval, then supply current install/save/session/actor receipts to the queue supervisor. These packets do not create queue entries.

## Sources pinned by this authoring pass

- `c-v2/C2.md`: `025A0A94EFB3146671F9ECA4A76BE5D1B63BBC59B551B373862504D9EE414A04`
- `c-v2/C3.md`: `981731F33FBEC4F298A0DB80D6352BD4431E9C1DB3FCA7DD7450B74189583492`
- `c-v2/C6.md`: `9549AA7F6997B3EAD18C6CA64C6C1EB6F42F9A08F46A308D8ECD179425679D4F`
- `r-v3/r3.md`: `DFEBA7140CD6F248FBD18E5850AF9BD3C273DFB53BD4494E657C3689A1C5CB4E`
- `r-v3/r4.md`: `03B706F4ABB38D6FA801B2F87F33C6F4BC17F4838A88C02DD85CE8A1823EC963`
- Existing `kah-chat-003-voluntary-travel-proposal.sh`: `D08A836FE43B6F1E42CD095D84EFBA591661A2510518A33DA4EB37A346B94404`

## Verification

Each emitter passed local Git Bash `-n`; execution printed exactly one `RESULT TL-nnn` template and no live command. WSL is unavailable in this session (`Wsl/Service/CreateInstance/E_ACCESSDENIED`), so no WSL tests or live rows were run. The exact-hash review record is `INDEPENDENT-REVIEW.md`; its verdict applies only to its listed frozen artifacts and does not clear runtime or release gates.
