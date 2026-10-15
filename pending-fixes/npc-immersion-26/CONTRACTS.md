# NPC-immersion 26: server <-> native contract list (2026-10-15)

Assembled from wpA/wpC1/wpC2/wpD/wpE `NOTES.md`, N1/N2c `NOTES.md`, the WP handoffs in `C:\KenshiTestRuns\agents\imm26-wp*.handoff.md`, the "Native contract" section of `testing/NPC_IMMERSION_26_HANDOFF.md`, and checked against the code in `/root/imm26/wp*` (server) and `N1/src`, `N2c/src`, `components/STOBE/src` (native). Mismatches were verified in code, not copied from notes.

## RULE (top)
**Native work is always based on the NEWEST `components/STOBE/src` tree, including `world_towns` (main.cpp, uncommitted).** N1 was built on the older E607 baseline (no `world_towns`; fails the build-stobe guard) and must be composed onto the newest tree; N2c is already on the newest tree. `build-stobe.ps1` / `build_portable.bat` SOURCES list is stale vs the newest tree (lacks Activity*, ProfilePortrait, BodyguardContractProbe; N2 adds NativeAttention + N2SocialWatch): read the CMake/vcxproj list instead.

Legend: Server = server patch tree state in `/root/imm26/wp<X>` (the `.patch` files wpA/wpB are still 0 bytes on 15:3x; the trees hold the code); Native = N1 (`N1/src`, activity/travel) or N2c (`N2c/src`, social/awareness). "ok" = field names, types and units match; "MISMATCH n" = see the action list.

## 1. `/context` (native -> server), WP-C2 item 11 attention, WP-C1 item 5/7 bystanders

| Field | JSON shape | Producer | Consumer | WP | Server fallback when absent | Server impl | Native impl |
|---|---|---|---|---|---|---|---|
| `native_ai.attention` | `{"observed":true,"busy","sleeping","injured","crippled","bleeding","exhausted","afraid","fleeing","hungry","in_combat":bool,"blood_pct":0-100,"busy_reason":"<=40 ascii, omitted when not busy"}` | native (`NativeAttention::WithAttention`, only when native_ai observed) | server `imm26C2AttentionNormalize` (`native_ai_context.php`), `imm26_c2_attention.php` | C2 / 11 | derived facts from stored NPC row (blood, combat) valid only when row pushed this turn (game_ts within 120 s); else no attention limits | yes (wpC2) | yes (N2c) | ok |
| `nearby[].role` | `"trader|shopkeeper|guard|medic|slave"` (omitted when empty) | native Context.cpp nearby actors | wanted by C1 discretion/referrals | C1 / 5, 7 | bracket title only; relation by faction/employer | NOT consumed: `stobeSocialPrivacyObservation` (lib/social_privacy.php) audience whitelist drops it | yes (N2c) | MISMATCH 4 |
| `nearby[].squad_name`, `squad_id`, `settlement` | `squad_name` string, `squad_id` **int** (`ToString((int)serial)`), `settlement` string; omitted when empty | native | wanted by C1 (same squad/settlement relation) | C1, B | none | NOT consumed (same whitelist) | yes (N2c) | MISMATCH 4 |
| `referral_people[].public_title` | string | native `NpcReferralPeople` (bracket title) | `npc_referrals.php`, `imm26_c1_referrals.php` | C1 / 7 | alphabetical | yes | yes (existing) | ok |
| `referral_people[].role` / `occupation_public` | string | requested by C1 | none | C1 / 7 | titles only | not read | NOT emitted | MISMATCH 5 |
| `environment.building_type` (next to `building_name`) | string | requested by C1 optional | none | C1 | none | not read | not emitted | open (optional, C1 says optional) |

## 2. `native_ai` additions (WP-D items 18, 23), producer N1 (`NativeAiAwareness::CaptureJson`)

| Field | JSON shape | Consumer | Server fallback | Server | Native |
|---|---|---|---|---|---|
| `active_job` | `{"observed":true,"name":"<description>"|null}` | `native_ai_context.php` (needs observed:true and non-empty name) | "state unknown" line when snapshot stale/unmatched | yes (wpD) | yes (N1) ok |
| `active_package` | `{"observed":true,"package_name":str|null,"target":{serial,name}|null,"employer":{..}|null}` | same | same | yes | yes ok |
| `player_orders` | `[{"type":"Follow|Patrol|Guard|Hold","target":{"serial":N,"name":".."}|null}]` max 4; `null` = unreadable, `[]` = none | same (only these 4 types kept) | none | yes | yes ok |
| `temporary_companion` | N1 emits `{"observed":true,"present":bool,"source":"legacy_follow","squad_member":false,"since_game_ts","age_game_seconds","expires_gamets"}`; WP-D notes list `agreement_id` too | server reads only `present` (bool) and `expires_gamets` | no companion line | yes | yes; `agreement_id` NOT emitted (server ignores it, harmless; doc-only difference, ACTION 12) |

## 3. Owned travel dispatch (server -> native `OWNED_TRAVEL@{json}`) and receipts, WP-D 20/21/23

| Field | Shape | Producer | Consumer | Fallback | Status |
|---|---|---|---|---|---|
| start payload | `{"operation":"start","actor_serial","speaker_serial","agreement_id","request_id","world_id","session_generation","plan_hash","expires_gamets","kind":"follow|route","open_ended":bool,"x","y","z","label","candidate_id"}` | server `commitment_native_bridge.php` | native `NativeTravelLifecycle` (`expires_gamets` mandatory, `kind` follow|route, x/y/z mandatory) | legacy dispatch kept when no native snapshot | expires_gamets/kind/x/y/z ok; **`open_ended` is not read by native** (MISMATCH 6) |
| release | `{"operation":"release",...,"task_id"}`; REPLACE issues a new start (new request_id) only after the release receipt | server | native `ReleaseOwned` | new terms parked until release confirmed | ok (both implemented) |
| failure receipt `reason` | server maps by substring: `expired`/`agreement_expired`, `hostile`, `target_unconscious`, `leader_unconscious`, `incapacitated`, `path`; anything else = "I cannot tell" | native `NativeTravelLifecycle::Emit` | server `stobeImm26FailureText` | "cannot tell" | native emits free-form reasons (`owned_*`, `native_*`, `controller_*`, `route_travel_failed`...) and none of the closed tokens `path_blocked`, `hostile_in_way`, `leader_unconscious`, `expired`, `actor_incapacitated` (only `target_unconscious` exists, in Autonomy, not travel): MISMATCH 7 |
| `travel_lifecycle.participation` | `{"schema_version":1,"mode":"travel_accompaniment","qualified","conscious_alive_all","world_id","agreement_id","task_id","actor_serial","partner_serial","actor_storage_id","partner_storage_id","actor_name","partner_name","first_gamets","last_gamets","terminal_gamets","qualified_samples","progress_samples","actor_distance","partner_distance","endpoint_progress","max_separation"}` | native N2c `ParticipationEvidence.h` | server `stobeParticipationAward` (base `relationship_participation.php`) | no award | keys and types match (checked); game-untested |

## 4. Activity ops (native -> server `activity.php`, signed HMAC like poll/report), WP-E 22/25/26

| Field | Shape | Producer | Consumer | Fallback | Status |
|---|---|---|---|---|---|
| `event` op | `{"operation":"event","context":{worldId,actor,requester,now},"agreementId","event":{"id":"[A-Za-z0-9:_-]{1,64}","kind":"threat|injury|progress|phase|arrival|handback",...}}` | N1 `ActivityTransport::QueueActivityEvent` (<= 8 per poll, 3 attempts/90 s, <= 40 per agreement) | wpE `ActivityEvents.php` (dedup `activity:<agreementId>:ev:<id>`) | no remark | kinds, ids (`arr`,`p<N>`,`t<n>`,`ia<n>`,`ir<n>`,`ret`,`hb`), threat `subject`,`distance`; injury `who`,`healthPercent` int; progress `delivered`,`quantity`,`resource`; phase `phase`; arrival `place`; handback `resource`,`count`,`toRequester:true` all match: ok (needs shared signing key on both sides) |
| terminal `report.reason` | allow-list: no_observed_suitable_reachable_target, target_lost, timeout, expired, cancelled_by_player, actor_incapacitated, route_unreachable, threat_too_high, inventory_full | server accepts (`stobeActivityNormalizeReason`) | N1 does NOT send `reason` | outcome text without reason | MISMATCH 8 |
| terminal `report.handBack` | `{"status":"handed_over|failed|not_applicable","reason"?}` | server accepts (`stobeActivityNormalizeHandBack`) | N1 keeps it in the legacy status row only (`handBackStatus/Reason/Amount`) | none | MISMATCH 8 |
| envelope `handback:true` | top-level, outside signed digest | server `ActivityAgreementAdapter` only when `/var/lib/stobe/activity-handback`=1 and kind has handback | N1 `Agreement::handBack` (string compare to "true") | hand-back off (default OFF both sides) | ok |
| report `participation` (activity_accompaniment) | same object as section 3 with `mode:"activity_accompaniment"` | server consumes `request.participation` in `activity.php` | native does NOT produce it (N2c patched travel receipts only) | no award | MISMATCH 9 |
| camp scope v3 (opaque zone + digest) for ClearGroup | per `activity-camp-native-integration-20261014` | server | native N1 base includes the camp tree | ClearGroup fails closed | not re-verified here; needed before a camp zone is offered |
| Gather/Scout/Escort native facts | agreement requires native facts whose `kind` equals the agreement kind | server holds these kinds back (`native:false`) | not produced | fail closed | by design |

## 5. Social events (native -> server `/social_event.php`), WP-A 12/13, WP-B

| Field | Shape | Producer | Consumer | Fallback | Status |
|---|---|---|---|---|---|
| `event_kind: abandoned_in_danger` | standard envelope (schema_version 1, event_id, campaign_id, timeline_epoch, native_session_id, incident_id, sequence, game_ts, origin gameplay, witnesses); actor = leaver, target = abandoned; facts `evidence_id` ("abandon:<leaver>:<partner>:<episodeStart>" matches token regex `[A-Za-z0-9_.:-]{1,128}`), `partner_state` knocked_out|bleeding_out|downed, `distance_m` int >= 30, `seconds` int >= 20, `observer_saw_leaving` bool | N2c `N2AbandonWatch` (every 2 s, armed after leaver within 25 m) | server `SocialInterpreter::abandonedInDanger` (wpA, kind added to `SocialEventContract::KINDS`, rules range [-25,-12]) | no effect | **server requires `facts.agreement_id` (token) but native does not send it**: every event returns `invalid_evidence` (MISMATCH 1). **server requires `target.conscious === true`, native fires while the partner is still knocked out (conscious false/omitted)**: `unaware_observer`, no effect (MISMATCH 2) |
| entity optional `in_player_squad` | bool, omitted when unknown | N2c entity export | `SocialEventContract::entity` (validates bool, stores) | null = unknown | ok |
| entity optional `squad_id` | string `squad_<platoon handle serial>` | N2c | WP-B ties wanted it | none | `entity()` returns a fixed key list and drops it (MISMATCH 3); inconsistent with the int `nearby[].squad_id` (MISMATCH 4) |
| entity optional `squad_name`, `settlement` | strings <= 64 | N2c | WP-B ties wanted them | none | dropped by `entity()` (MISMATCH 3) |
| `item_transfer` `facts.transfer_evidence` | `{"verified":bool,"method":"same_live_item_whole_stack|direct_item_handover","items":[..],"transfer_id","agreement_ticket"?}` | N2c (ported) | base `SocialEventContract` | amount-delta heuristics | method/items ok; `agreement_ticket` flow (restitution against a verified agreement term) NOT ported by N2c: MISMATCH 10 |
| disclosure/"secrets" ledger events | none defined | no producer | WP-A reserved components `confidence_kept/betrayed` | trust kind `share_secrets` from aff only | open, no producer, not a mismatch |

## 6. Proximity / optional bored turn (native -> `stream.php`), WP-C2 items 8, 9, 11

| Field | Shape | Producer | Consumer | Fallback | Status |
|---|---|---|---|---|---|
| optional bored call | `...stream.php?mode=autochat&optional=1&profile=<urlenc npc name>&attn=<urlenc attention JSON>` | N2c `N2SocialWatch` + `ChatBox::TriggerOptionalBoredTurn` (2 s scan, 90 s global, 10 min per NPC; also right after a nearby `combat_start`) | `processor/bored.php` (`$roll=-1`, claim-only, `imm26C2ParseRequestAttention`) | server answers "ok" and does nothing when nothing claimable; without the call remarks wait for the 3 h x 50 % tick | ok (param names match: `optional`, `profile`, `attn`) |

## 7. Server-only settings the contracts depend on
`SOCIAL_RELATIONSHIP_MODE=enabled` and `SOCIAL_FIGHTS_LIVE=true` (WP-A ledger components); `/var/lib/stobe/activity-enabled`=1, `activity-transport.key` (>= 32 chars, also `STOBE_ACTIVITY_TRANSPORT_SECRET` / key file beside the DLL on the native side), `/var/lib/stobe/activity-handback` (default off), `activity-purposes.json`; all `IMM26_*` flags default on. Native: `[Settings] FollowExpiryGameHours` (default 24, 0 = off).

## ACTION ITEMS for the coordinator (12; mismatches 1-10 verified in code)

1. **abandoned_in_danger: `agreement_id` required by server, never sent by native.** Fix server (wpA): make `agreement_id` optional (fall back to `evidence_id` for the incident hash). Owner: wpA3. Without it the feature is dead.
2. **abandoned_in_danger: victim must be conscious, native fires while the partner is knocked out.** Pick one: server accepts an unconscious victim and applies the effect when the victim next reports conscious (deferred), or native defers the post until the partner wakes (fact `partner_state` kept from the episode). Recommended: native defers (server rule "victim must know" stays). Owner: N2 follow-up (`N2AbandonWatch`) or wpA3.
3. **Entity extras dropped:** `SocialEventContract::entity` should whitelist optional `squad_id` (string <= 64), `squad_name`, `settlement` and WP-B ties should use them (same squad beyond the player squad, same settlement). Owner: wpA/wpB.
4. **Nearby role/squad/settlement not consumed:** extend `stobeSocialPrivacyObservation` audience (lib/social_privacy.php) and `imm26_c1_discretion.php` relation to read `role`, `squad_name`, `squad_id`, `settlement`; make `squad_id` one type everywhere (native nearby = int, entity = `"squad_<n>"`: use the string form in both). Owner: wpC1 + N2.
5. **referral_people `role`:** C1 wants it, N2c did not emit it (only `public_title`). Either add `role` to `NpcReferralPeople::CaptureJson` (reuse `NativeAttention::RoleFor`) or drop the request from C1 notes. Owner: N2/nativecomp.
6. **OWNED_TRAVEL `open_ended` ignored by native:** follow ends at `AtAgreedEndpoint`/`RouteArrival` against x/y/z (= speaker position at dispatch). A WP-D implicit follow therefore completes almost at once instead of lasting until `expires_gamets`. Native: when `open_ended` is true, ignore arrival and end only at expiry or release. Owner: nativecomp (`NativeTravelLifecycle.cpp` line ~473).
7. **Failure reason tokens:** native emits free-form strings, none of the tokens the server maps (`path_blocked`, `hostile_in_way`, `leader_unconscious`, `expired`, `actor_incapacitated`). Result today: NPC always says it cannot tell (safe degrade). Native should map its terminal reasons to the closed token list (or server should also map `owned_travel_*`/`native_order_*`). Owner: nativecomp or wpD.
8. **Activity terminal report lacks `reason` and `handBack`:** N1 writes them only into the legacy status row. Add `"reason":"<allow-list token>"` and `"handBack":{...}` to the report body in `ActivityTransport.cpp`. Owner: nativecomp.
9. **Activity accompaniment participation:** server consumes `report.participation` (mode `activity_accompaniment`), no native producer. Either wire `ParticipationEvidence` into the activity goal/transport or accept that activity trips never award shared-experience. Owner: nativecomp (or leave, record as known gap).
10. **`agreement_ticket` in transfer proofs not ported** (N2c notes). Needed for restitution against a verified agreement term (WP-B repair). Owner: native follow-up.
11. **Compose base:** N1 (E607 base, no `world_towns`) and N2c (newest tree) must be composed onto the newest `components/STOBE/src` (main.cpp, ActivityController.cpp, ActivityTransport.cpp, Utils, Globals hunks collide); update the build SOURCES list; native glue is compile-verified only, nothing ran in game. Owner: imm26-nativecomp (running).
12. **Doc fix:** WP-D notes/handoff list `temporary_companion.agreement_id`; neither N1 nor the server uses it. Edit the note to `{present, expires_gamets}`. Also provision the activity signing key + `activity-enabled` on every lane before expecting any `event`/`report` to be accepted (silent drop otherwise).
