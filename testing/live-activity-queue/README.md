# ActivityGoals gameplay rows — blocked pending exact composed release pin

These row emitters are immutable operator specifications. They print instructions only; they do not contact a rig, issue a KAH command, alter a save, call a backend, or manufacture a result.

## Release dependency (hard block)

`ACTIVITY_COMPOSED_RELEASE_SHA256=UNSUPPLIED` — no composed exact candidate SHA was provided for these rows. The known uncomposed native DLL `57C4E56F046244C7D19F7EEA793B12F85F6B0B1CB4FB1A78773C3A7393C207A8` and server manifest `F945555082E196930B872A7D15354D85097D0A23EF0A0DA72F2D39193FA6780B` are component identities only; neither is the composed installed release pin and neither authorizes gameplay. The activity package is currently uninstalled. Every row must remain BLOCKED until the release coordinator supplies an exact reviewed composed release SHA and its native/server component manifest, both rig operators confirm that exact composition is installed and loaded, and each rig verifies its isolated copied save, matching schema/API version, private transport configuration, active source, and session readiness. If the composition changes, author a new row ID with the new pin; do not edit these row files.

Run row emitters only to print their instruction packets. For every live execution use both rigs when safe isolated matching setups exist: 4080 and 5090 each need a separately verified copied save and exact same composed release. Never use a production/shared server or live user save.

## Rows and dependencies

| ID | Scenario | Dependency |
|---|---|---|
| `AG-GAME-001` | Grounded activity proposal, explicit agreement/grant scope binding, exact route candidate identity | Exact composed release pin and a fresh, grounded source + route candidate |
| `AG-GAME-002` | Native route dispatch, observed arrival, then fresh activity-source scan | AG-GAME-001 accepted exact scope/route receipt |
| `AG-GAME-003` | Hunt action, completion, attributable transfer/reward | Fresh matching Hunt agreement + AG-GAME-002 route/arrival/rescan receipt |
| `AG-GAME-004` | Mine action, completion, attributable transfer/reward | Fresh matching Mine agreement + AG-GAME-002 route/arrival/rescan receipt |
| `AG-GAME-005` | ClearGroup action, fixed target-set completion/cleanup, attributable outcome | Fresh matching ClearGroup agreement + AG-GAME-002 route/arrival/rescan receipt |
| `AG-GAME-006` | Cancel/revoke cleanup | Exact active proposed/accepted activity record and native action lifecycle receipt |
| `AG-GAME-007` | Source-unavailable fail-closed | Exact accepted agreement/route and post-arrival fresh scan that proves the agreed source is unavailable |

Rows 003–005 each cover a separate activity agreement and route lifecycle; do not reuse a different activity's grant or scan. Rows 006–007 use separate isolated copied-save scenarios and must not be combined with a still-running activity row.

## Common evidence and timing rules

Each live row produces exactly one final `RESULT <ID> PASS|FAIL <evidence>` line. A `BLOCKED` instruction printed from the emitter is planning state, not a live test result. In `FAIL setup`, include the observed gate and receipt; in `FAIL evidence`, name missing proof; in `INCONCLUSIVE`, explain why the row ended without an assertion. One result line only per row.

For proposal/acceptance, retain the native chat line and reply, authenticated backend activity record and decision/grant envelope, actor/requester/world identity, activity-purpose scope, and separate route scope. Capture `discoveryRef`/activity source identity separately from `routeRef.candidateId`; route facts (kind, label, endpoint, actor/world) must match the authenticated native route-candidate snapshot. The model-selected candidate ID alone is insufficient evidence.

For route/action rows retain the native order start and end/cleanup receipt, exact route candidate ID/endpoint, observed arrival timestamp/location, and a fresh activity scan timestamped after arrival. Record the exact freshly selected source handle/ID and resource/target set. Hunt/Mine also require before/after requested item counts, exact produced quantity, transfer target and attributable reward/report. ClearGroup requires the agreed fixed serial set, per-target terminal outcome, no action against unagreed targets, native cleanup, and any explicit reward/report; do not infer a reward or relationship change. Proposal, travel acceptance, and route arrival do not authorize Hunt/Mine/ClearGroup work unless the separate activity scope was expressly accepted.

Keep each game-time segment under 10 real minutes, record a progress receipt at least every 5 minutes, and end a row at its stated bound. A row that cannot reach its assertion in the bound is `INCONCLUSIVE`, not a pass. Do not run another row while the native order/goal from the prior row is still active.

All state-changing chat in a test should be direct KAH with the exact resolved NPC name and no `ui` suffix. Never infer an NPC's acceptance from a model flag alone: the authenticated service's exact displayed terms, scoped grant, and native acknowledgement must agree. Invalid, tampered, stale, cross-actor, wrong-world, changed-scope, missing-route, and unavailable-source outcomes must fail closed with no out-of-scope native dispatch/reward.
