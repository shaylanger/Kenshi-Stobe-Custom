# STOBE stateful relationship system: audit, implementation and automated test plan

Date: 2026-10-02 (Shay local time). Status: design and source audit complete; implementation not started. This document authorizes no deployment by itself. Requested deliverable: audit and plan, ready for a later build.

Canonical working copy: `C:\KenshiModding\STOBE_relationship_system_audit_and_implementation_plan.md`.

## 1. Scope and settled decisions

Extend STOBE's relationship subsystem, with native telemetry additions in Stobe.dll and limited KenshiFP integration where its real action bridge supplies outcome attribution. Do not build a separate competing relationship mod. Preserve the single directed affinity scale -100..100 and existing eleven tiers. Keep relationship type independent of tier. Player characters can be actors, victims and witnesses under the same rules.

Replace R4 entirely when this feature is enabled. An attack affects victim → attacker, never attacker → victim merely for attacking. Generalize defense tracking to NPC vs NPC. Ordinary retaliation does not produce an aggression penalty. Severe maiming can still create a distinct grievance in the aggressor without treating the defender as an initiator.

Negative knowledge requires direct experience while aware, witnessed evidence, or justified later inference. Unconscious victims accrue latent facts. On recovery they can infer missing property was taken by their remembered KO attacker unless better evidence exists. Actual theft by C must not leak into B's beliefs. Enslavement is attributed to the actual known enslaver/owner, not automatically the KO attacker. Beneficial care can count while unconscious using verified provider attribution.

Outsider carry has two stages: suspicious interference when known, then verified outcome. Do not charge an unconscious victim immediately; retain the initial component and resolve awareness on waking. Squad/player-faction inventory management and carrying are exempt from routine theft/kidnapping penalties. Genuine rescue remains positive. Exemptions do not erase insults, betrayal, broken promises or witnessed harm to loved ones.

Unseen theft does not affect personal affinity. Nearby is not equivalent to witnessed. Friend treatment propagates only to verified conscious witnesses, once, with no recursive cascade. Normal commerce gives almost nothing; exceptional trade cannot buy devotion. Distinct genuine lifesaving incidents retain large gains, while repeated treatment of one injury cannot be farmed.

Surrender willingness follows survival pressure and courage, separately from affection. Hatred may influence tone and later betrayal, but must not categorically block surrender or rational ceasefire terms. Emergent STOBE recruitment requires affinity >=76 plus meaningful trust evidence and no unresolved severe grievance. Vanilla scripted paid recruits and vanilla slave recruitment remain untouched. A complete non-scripted slave escape can sometimes cross the threshold and produce a willing recruit, never a guaranteed recruit.

## 2. Audit evidence and baseline

Read-only audit on DESKTOP-JFLPK99, device `39a13270-d7ef-4497-a1b1-feb6780cf90b`, WSL `DwemerAI4Skyrim3`. No game launched, stopped or controlled; no DLL installed; no live migration performed.

| Component | Audited source / baseline |
|---|---|
| Server | `/var/www/html/StobeServer`, HEAD `5f71138acd1290aab2a577c48457becfb16d021e`; working tree clean at inspection |
| Native STOBE | `/root/STOBE-src`, HEAD `dedc49dc31186f9ac3290ddc23ae54d8c59ac4be`; current files, not merely commit contents, inspected |
| KenshiFP | `/root/KenshiFP`, HEAD `200102f93a111db1d98c6b9304fe9850b682569d` |
| Workspace | `C:\KenshiModding`, HEAD `86ef663c763639e0fb55c966d53795372a15d0e0`; multiple unrelated modifications/untracked projects, preserve them |
| Harness (since 2026-10-02) | standalone Kenshi Automation Harness mod `C:\KenshiModding\Kenshi-Automation-Harness` (commands in `src/Commands.cpp`, read its `AGENTS.md`); Stobe commands via `/root/STOBE-src/src/StobeHarnessBridge.cpp`; clients `stobe-auto` (= kah.py) and `stobe-say`; `tools/automation/` |

Instructions read: server AGENTS.md, docs/agent-guide.md, docs/building.md; native AGENTS.md and packaged mod/docs/Stobe/AGENTS.md; workspace CLAUDE.md; standalone harness AGENTS.md. Workspace currently records in-game tests on hold. This planning request does not require changing that state. Earlier automation notes are stale about needing Shay to launch/install; use the current workflow when later testing is authorized, and never stop a user-owned game.

Existing baseline executed on staging `/root/stobe-work/ss-merge`, disposable `stobe_test` DB:

`stobe-tests /root/stobe-work/ss-merge 'relationship_(system|stance|rollback)_regression'`

Result: 3 suites passed, 0 failures, 0 known failures. This establishes existing regressions only, not the new system or real game telemetry. The broader runner documents existing failures; do not silently label new failures as known or weaken tests.

### Confirmed implementation facts

| Area | Evidence / implication |
|---|---|
| Affinity | `lib/relationship_manager.php` TIERS and chat helper updater use -100..100 with fixed tier boundaries |
| R4 | `lib/chat_helper_functions.php:stobeRelationshipOnAttack` parses prose, applies -10 victim and -4 attacker, wall-clock 900s throttle in conf_opts; called by `lib/negotiation_engine.php:stobeNegTickThrottled` |
| Persistence | `stobePersistNpcRelationshipMap` updates core_npc text and extended_data maps, then stamps timeline; use this boundary rather than a parallel affinity store |
| Dialogue evaluator | `stobeEvaluateRelationshipsForTurn` consumes incoming/reply text and maps. It remains an independent writer unless constrained; mechanical outcomes must not be counted again by it |
| Recruitment | chat helper action-list code exposes JoinParty to outsiders without a general >=76 trust gate; `Functions.cpp` ACT_JOIN_PARTY has execution/fallback paths; autonomy and director have other action paths to audit when enforcing the gate |
| Surrender | negotiation engine initiative checks live ratio, hostile-to-player state and personality courage; no affinity term in this trigger |
| Betrayal | negotiation engine around affinity lookup requires negative affinity for one personality-driven path and increases chance at <=-20; preserve this separation |
| Defense | `main.cpp:PlayerSideIsDefending` returns false for non-player faction; `attackingYou_hook` uses current target as evidence. This is insufficient as a generalized encounter origin model |
| Event transport | `Utils.cpp:LogGameEvent` uses serials for people/geography/local logs, then sends prose DATA + people JSON through stream.php. No dedicated structured actor/target event fields are emitted in the inspected path |
| Nearby people | BuildEventPeopleJson captures nearby context, not proof of sight/hearing. Server sparse-people recovery and state annotation must not fabricate witnesses |
| KO/recovery | polling EmitKnockedOutEvent resolves attribution but sends victim serial with target zero; attacker remains prose. setProneState hook can also emit unknown-attacker KO. EmitRecoveredEvent exists |
| Healing | hook emits provider/recipient serials and kit name, with session/burst suppression; no measured before/after bleeding, blood or critical recovery in that emitted payload |
| Looting | isItOkForMeToLoot_hook emits before the original permission result, with victim serial zero. This is an attempted/check event, NOT evidence an item moved |
| Slavery | polling EmitSlaveryEvent can resolve owner and sends owner serial in the target position; setChainedMode hook omits owner attribution and logs before the original call |
| Prison | setPrisonMode_hook reports victim only, before original call; no captor or completed cage transition attribution |
| Carry | EmitCarryPickupEvent/DropEvent have both serials, but no verified bed/cage/safety destination or awareness state |
| Property/trade | inventory snapshots and matched transfer deltas already exist; pickup trade path uses ResolveLikelyTraderForActor, so seller attribution can be heuristic |
| Save state | playthrough_policy.php lists gameplay tables explicitly; unknown new tables are not automatically saved. playthrough_rollback.php restores relationship-owned keys and prunes future history; new ledger/state must join both full switching and rollback |

Native source anchors above were inspected directly. Exact locations can move; builders must revalidate HEAD and working trees before edits. Legacy extension classes/async workers may write maps independently: audit every writer and call site in the first phase, not just the conversational path.

## 3. Telemetry contract and remaining technical probes

Use a versioned structured event envelope alongside existing prose. Prefer POST JSON rather than growing GET URLs. Preserve old endpoints and prose consumers. Add a validating adapter at ingress after the playthrough runtime barrier and before social processing. Never rely on parsing names for authoritative blame.

Required envelope:

`schema_version, event_id, campaign_id, timeline_epoch, native_session_id, sequence, game_ts, capture_ts, event_kind, source, origin(setup/gameplay), actor_id/serial, target_id/serial, actor/target_faction, actor/target_squad, state_before, state_after, encounter_id, agreement_id, item_deltas, location, witnesses, attribution_evidence`.

Identity is campaign + valid entity identity, not name alone or serial alone. Serials can be reused after fixture reload/import. Use storage_id/profile resolution where valid, preserve rename aliases, and reject ambiguous mapping rather than merge unnamed actors. Do not create relationship entries under generic shared template names. Keep serial-keyed pending evidence until a unique named profile exists; binding must prove identity and must not attach old evidence to a reused serial.

State captures consciousness (including sleeping vs KO), health parts/max, blood/max, bleeding/deterioration, hunger/fullness (native 0..3; UI 0..300), slavery/owner, carried-by, bed/cage occupancy, inventory multiset with item identity/count/value/slot/ownership, and faction/squad membership at event time. Null means unknown, never zero or false by default.

Event ID must be stable across retries. Namespace it by campaign/epoch/session; persistent monotonic sequence per session. Detect transport duplicates without suppressing distinct same-tick events. Order-sensitive events use capture sequence, tolerate bounded late delivery, and retain causal links. Load barriers discard stale queued old-epoch events. No historical backfill of penalties when enabling the feature.

| Event family | Native additions required before activating effects |
|---|---|
| Combat | explicit real attack order/awareness and successful hit actor; directed encounter initiator; damage outcome thresholds; separate attacker from victim in KO/limb/death; suppress duplicate hook/poll events |
| Loot/theft | confirmed inventory removal/addition, owner/victim ID, item count/value/importance, stolen flag separately from caught detection, observer attribution; permission checks get attempt kind only |
| Slavery | preserve explicit chaining actor and owner role separately; confirm resulting state after call; freeing actor before owner is cleared; recover actual owner identity when awake |
| Prison | correlate real captor action/order with actual cage entry/release; distinguish lawful agreed custody from coercion; unknown captor gives no invented penalty |
| Aid | sample treatment start and meaningful end/threshold, blood/bleeding stabilization, prior damage source, supplied medicine; no credit for an attempted order |
| Carry | pickup/drop + original conscious state, carrier identity, destination/occupancy and safe outcome. Position change alone is not rescue |
| Food | donor → recipient transfer linked to consumption/fullness improvement and need before; distinguish own food and routine squad supply |
| Trade | completed transaction, actual payment/item change, exact seller when known, reference value/economic significance; heuristic seller never gets confident effects |
| Witnesses | bounded candidates with consciousness, range, event-time line of sight/hearing or explicit awareness evidence. Verify available KenshiLib APIs before implementation |
| Slave escape | connected rescuer/escape incident, shackles/slave/captivity transitions, protection and treatment, hostile-area exit and sustained freedom; unlock alone isn't completed escape |

Research remaining is bounded implementation probing, not another broad design round: confirm safe visibility/awareness APIs and stolen/caught hooks; confirm inventory completed-transfer interception and prison captor linkage; confirm safe bleeding/slave/cage fixture setters; identify the exact transport/bootstrap entry to retain envelope; verify current entity IDs across reload; inspect all relationship/action writers. If an engine signal cannot be proven, ship that category disabled with a reported blocker, never substitute omniscience. Core framework and reliable combat can start immediately.

## 4. Server architecture and persistence

Proposed focused files: `lib/social_event_contract.php`, `social_incidents.php`, `social_perception.php`, `social_rules.php`, `social_relationship_writer.php`, `social_recruitment.php`; `data/social_relationship_rules.json`; bounded diagnostics tool `tools/social_relationship_inspect.php`. Names are proposed, not existing files.

Flow: validated raw event → incident update → observer-specific knowledge → semantic consequence → deterministic delta → atomic relationship/history/evidence commit. Native only reports facts. Mechanical magnitude never calls an LLM. Dialogue evaluation may classify insults/promises or refine a note/type, but cannot rewrite mechanical severity or reveal hidden objective actors.

New proposed gameplay tables: social_event_inbox (normalized facts and dedup), social_incident (state/version/checkpoints), social_belief (observer knowledge/pending facts), social_effect (unique incident/observer/culprit/component application ledger), social_evidence (trust/grievance summaries). Add all through reviewed schema updates, authoritative playthrough policy, manifest version/migration rules, snapshot/export/import/cleanup categories and rollback. Do not merely add SQL tables and assume saves work.

Store full event objective truth in protected diagnostics; prompts receive only observer beliefs and known facts. False-blame notes must say inferred responsibility internally and must never become globally confirmed theft history. Later evidence may correct attribution with a compensating effect, not silently delete history. No rumor system is required in first release.

Use one transaction for ledger uniqueness, current pair row lock, delta application through canonical persistence, trust/grievance update and timeline stamp. Acquire multiple NPC locks in stable ID order. Do not apply stale whole-map snapshots from parallel dialogue/worker events. Refactor the writer boundary where necessary to accept a delta under lock. Duplicate event or failed transaction produces zero partial effect.

Incident states: opened → active → pending_awareness/outcome → resolved → archived. Combat effects apply immediate known aggression, then ONLY incremental severity escalation, not a full penalty at every hit, KO and fight end. Aid reward applies verified positive transition, not kit tick. Carry creates a pending initial component plus an outcome component. Death has witness effects, but a dead victim cannot wake for latent penalties.

Persist open incidents and latent facts; a process restart must not forget an unconscious victim's evidence. Rollback needs cutoff checkpoints of incident state, beliefs, inventory baselines, trust/grievance counters and ledger. Restoring only affinity is insufficient. Separate server playthrough switch, same-save game-time rollback, and load at the same timestamp with a new epoch. Snapshot state by game-time plus sequence. Remove future applied effects/replay cursors consistently; no penalty replay after rollback. Cover NEVER_CLEAR_RELATIONSHIP_DATA explicitly: if it preserves affinity, preserve corresponding evidence coherently and discard future transient incident state, with documented semantics.

Limit active incident count, witness count, event size, late-event window and per-worker batch. Never drop unresolved latent severe incidents as ordinary cache eviction; checkpoint them. Use indexed identifiers and query budgets. No per-hit LLM calls; aggregate routine damage. Feature settings: master OFF initially, shadow mode, then category flags. When new rules enabled, R4 is mutually excluded. Disabled mode must produce no new affinity changes; switching flags cannot replay old events. Report degraded telemetry.

## 5. Initial numerical rules (tunable hypotheses)

All ranges below are proposals, not verified gameplay balance. Centralize configuration with version and validation. Use seeded deterministic variability keyed by incident + observer + effect + rules version; reload/retry cannot reroll. Round once after modifiers. Scale stays -100..100; tier recalculated by existing helper.

| Semantic consequence | Base range before context |
|---|---:|
| Intentional aggression, no meaningful injury | -8..-15 |
| Meaningful assault / injury | -15..-28 |
| Serious assault / KO | -25..-40 |
| Critical deliberate harm | -35..-55 |
| Deliberate permanent maiming | -45..-70 |
| Minor accidental friendly fire | 0..-3 |
| Defensive ordinary retaliation | 0 aggression penalty |
| Defensive severe maiming grievance | -8..-20, no aggression/betrayal tag |
| Routine successful healing | +1..+3 |
| Meaningful stabilization / serious aid | +5..+12 |
| Genuine lifesaving rescue | +20..+35 |
| Needed food, moderate hunger | +2..+5 |
| Food resolves extreme survival need | +6..+12 |
| Known outsider pickup suspicion | -5..-12 |
| Verified safe bed/rescue outcome | +8..+18; select higher rescue class if lifesaving |
| Coercive imprisonment | -20..-40 |
| Enslavement | -65..-90 |
| Shackles freed without completed escape | +8..+18 |
| Completed slavery escape (total incident budget) | +15..+65 |
| Caught trivial / ordinary theft | -3..-8 / -8..-18 |
| Caught major property / primary weapon / near-total belongings | -20..-35 / -25..-45 / -35..-55 |
| Unconscious missing property blamed on remembered attacker | matching property range ×0.8 confidence |
| Ordinary fair trade | 0 |
| Favorable / materially generous / exceptional deal | +1..+2 / +2..+4 / +4..+6 |
| Ordinary gift | +1..+4; survival gifts use aid rules instead |
| Honored coercive ceasefire | 0..+2 |
| Ordinary distinct kept promise | +1..+3 |
| Meaningful broken promise | -5..-15 |
| Deliberate deal betrayal / harmed after surrender | -20..-40 additional betrayal component |
| Defense of another from genuine danger | +5..+15, or lifesaving class |
| Mild / serious dialogue insult | -1..-3 / -3..-8, conservative semantic classification |

Interpret ranges as categories, not additive rewards for every raw signal. Serious assault → critical → limb loss upgrades the existing harm budget with incremental differences. Theft and betrayal are independently meaningful and can add. A full escape's +15..+65 includes chains, escort, protection, feeding and related treatment within that incident; do not sum the top of every component. A receptive slave starting +18 can reach >=76 at the rare high end with verified extraordinary rescue evidence; others remain +25..+55 or go their own way.

Proposed modifiers: known intentional harm 1.0; confirmed accident 0.25; unknown intent does not invent accident. Neutral meaningful harm up to 1.1; major betrayal of a close companion up to 1.3; ordinary aid received while Cold/Hateful 0.6/0.35, but distinct lifesaving and liberation minimum effectiveness 0.65. Personality max range 0.85..1.15, only from grounded markers. Cap routine final gains to configured class maxima. Severe enslaving/betrayal constraints can force affinity no higher than -56/-31 respectively when certain, after applying delta; do not force type/tier from uncertain observations.

Repetition: routine aid once per injury episode, repeats 0; gifts/trade decreasing weights 1, 0.5, 0.25 and category budget <=+6 per in-game day, economic-only cumulative progression ceiling +30 (never reduce an already higher relationship). Major distinct rescue weight >=0.8; ten real separate lifesaving episodes can reach Bonded. Harm has no positive-style farming cap; same encounter dedup only. A second distinct deliberate assault can increase severity up to 1.15. Self-inflicted harm followed by healing gets no rescue trust evidence; staged loops with a collaborator require risk attribution checks. Avoid universal passive decay/forgiveness in this release.

Witness propagation, based on witness → victim BEFORE event: neutral 0; acquaintance 0.05..0.10; friendly 0.15..0.25; fond 0.25..0.40; devoted 0.40..0.55; bonded 0.55..0.70 of justified direct negative magnitude. Positive weights at half these rates. Conscious actual witness only; no propagation from synthetic relationship changes; once per observer/incident/component, no recursive friend-of-friend spread. Snapshot pre-event affinities prevents order dependence. Squad status of witness doesn't exempt harm to their friend.

Recruitment: threshold >=76 plus strong verified rescue, lifesaving, repeated major aid or genuine companion history; economic evidence alone never qualifies. Preserve existing companions across migration. Apply deterministic authorization at all ordinary STOBE action dispatch paths, not just prompt hiding; native consumes validated request context and doesn't intercept vanilla recruitment. Explicit forced/cheat mode stays a documented override. NPC motive, independence, obligations and practical availability may still refuse above threshold. Rescue can offer recruitment once after freedom; not merely set faction automatically.

## 6. Build phases and acceptance gates

| Phase | Deliverables | Required gate before proceeding |
|---|---|---|
| 0: audit follow-through | identify every relationship writer/action dispatch path; exact identity mapping; telemetry API probes; fixture/server isolation specification | ambiguous telemetry listed, no invented native exports; ready probes for each category |
| 1: framework | envelope, persistence, incident/knowledge models, locked writer, deterministic rules, flags, shadow diagnostics, migrations/rollback | replay/property tests; concurrency and migration/save restoration tests; old client and disabled mode compatibility |
| 2: combat | generalized origin/defense, threshold escalation, KO/limb/death attribution, consent/duel context, surrender separation | real player/NPC and NPC/NPC fights plus offline large/multi-party traces; no reverse aggression penalty |
| 3: unconscious perception | KO inventory baseline, latent harm, recovery attribution, slavery owner/captor evidence | C loots B after A KOs B; no immediate negative; correct inferred A blame; correct slaver C blame |
| 4: aid and carry | treatment outcome severity, food linkage, carrier/destination checks, squad exemptions, rescue incident budget | real medicine/bed/food tests; same injury anti-farm; distinct lifesaving progression |
| 5: property and agreements | confirmed caught theft, item significance, trade budget, gift meaning, deal honored/breached | no permission-check penalty, no unseen theft blame, no six-trade Bonded, verified deal outcomes |
| 6: witnesses/dialogue | verified sensory evidence, friend propagation, insults, observer prompt knowledge filter | conscious/occluded/absent/KO variants; no recursive cascade or hidden culprit disclosure |
| 7: recruitment/escape | full slave escape tracker, gate across dispatch paths, motives and exceptions | low/high trust scenarios; random slave can sometimes qualify; vanilla path unchanged |
| 8: full validation | regression suite, automated game matrix, overnight bounded soak, installation manifest, rollback recipe, final report | zero unexplained new failures; every requirement traced; real-game gates passed or explicitly blocked |

For each phase implement its tests with the feature, prove bug regressions fail without fixes, then validate and checkpoint. Do not defer telemetry tests to the end. Use isolated branches/worktrees and staged PHP DB tests. Follow existing build scripts and ABI requirements; snapshot native changes into components before source commits. Do not modify unrelated workspace changes, install pending unrelated builds, change providers, or merge/release as part of this plan.

## 7. Automation design

Use the standalone harness through `stobe-auto` (switched over 2026-10-02; the old integrated backend is gone). New general commands go into the harness repo, Stobe-specific ones into `StobeHarnessBridge.cpp`. Harness commands execute on game thread, test-only, bounds checked. All proposed new command names below need implementation; none are claimed available today.

Existing controls: load/save/status/wait-world, spawn, chars/find, teleport, select, attack, health, ko, kill, hunger, give, transfer, buy, money, equip/unequip, inv/hp/where. `relation` changes FACTION relation, NOT directed STOBE personal affinity. `recruit` is setup-only and bypasses the behavior under test. `health` writes all body parts and cannot by itself prove bleeding stabilization. `transfer` manually removes/adds inventory and refuses equipped items; it does not prove stealth detection or the real loot action path.

Add bounded inspection: `social-state` JSON (IDs, conscious/sleep/KO, blood/bleeding, owner, prison/carry/bed, membership); `objects` (bed/cage/storage IDs + occupants); exact completed transaction trace; source event sequence; `social-inspect` server command (both directed maps, belief, incident, ledger, trust, grievance, rule breakdown). Add setup setters for per-part injury/blood/bleeding and valid slave/captive state only after safe API probes. Tag all forced mutations setup origin, exclude them from normal social scoring unless explicitly testing ingestion.

Add real action drivers where bridge cannot provide them: first-aid, pickup/drop, put-in-bed, imprison/release, free chains, real loot/steal with detection state. Prefer existing real STOBE/KenshiFP orders before inventing setters. Have an action ID linking order, native result and social event. Administrative setters only prepare state. For witnessing use actual positioned/occluded characters and actual sensing paths; offline injected witness lists validate server logic only.

Runner proposed location: `tools/automation/social_relationship_runner.py`; declarative scenarios and independent oracle fixtures under `tests/social_relationship/`. One runner owns game control via lease. Capture preflight installed DLL SHA256, source commits, rules hash, selected fixture checksum, server playthrough ID/timeline and active backend. Existing scripts archive logs, launch and detect health. No game ownership conflict permitted.

Server isolation is mandatory: fixture game save and corresponding disposable server playthrough must be paired and checked before any mutations. A fixture game reload alone does not reset database relationship/history/serial evidence. Prefer a staged server pointed to disposable DB and matching client test configuration, preserving normal configuration for restoration. If that cannot be isolated, explicitly switch to a dedicated test playthrough using supported runtime barriers, snapshot and restore original identity; never test destructive save/migration cases against live user data.

State machine: acquire lease → verify isolation/build → restore fixture pair → launch → wait-world/readiness → capture baseline → stage → perform real action → await native evidence → await server effect/queue drain → assert → archive → reset pair → next. Use game-time predicates plus wall-time watchdog, not fixed sleeps or acceleration as evidence. At speed >10 use current safety watcher; hunger guard for player/squad. Unexpected combat, path failure, crash or provider outage captures diagnostics and ends that scenario. Pause first, preserve logs before restart. Do not classify environmental failure as pass or hide it with unlimited retries.

Checkpoint `run_manifest.json` and append-only `results.jsonl` atomically after every command/assertion. Store run/scenario/attempt IDs, fixture/setup seeds, resolved serial map, game/server epoch, pre/post state, command transcripts, native raw envelopes, rule breakdown, source revisions, log offsets, expected/observed, pending waits, bug ID and next action. Save checkpoints in C:\KenshiTestRuns\social-relationships\<run-id> and summaries in C:\KenshiModding\archive. Keep raw logs out of git.

Resume after timeout: read manifest, verify current revisions/backend/epoch/game ownership; resume pending read-only wait if state matches. Otherwise archive incomplete attempt and rerun only that scenario from fixture pair. Never blindly replay a mutation after lost acknowledgement. Completed passing scenarios remain completed for the same build/rules; a fix reruns affected scenarios plus shared integration gates. Mark invalidated passes if underlying code changes. Each detected bug records reproducer, evidence, severity, root cause, fix commit and rerun result. Test → identify → fix in staging → build/install when game closed → rerun continues automatically within later authorized test scope.

## 8. Requirement-to-test matrix

Modes: U=pure deterministic/unit/property, I=disposable DB/HTTP/replay, G=real game harness. G is required for native hook/action behavior; replay alone is not a substitute. Test IDs are local to this new plan and do not renumber existing STOBE test rows.

| ID | Scenario and decisive assertion | Modes |
|---|---|---|
| SR01 | Every tier boundary -100..100; directed maps; clamp/type independent; deterministic retry delta | U/I |
| SR02 | A deliberately attacks B: immediate B→A loss; A→B unchanged until separate consequence | U/I/G |
| SR03 | B retaliates normally in NPC/NPC fight: no A→B aggression penalty; repeat with player on each side | U/I/G |
| SR04 | Multi-party fight, late joiner and defender protecting friend: origin retained; unrelated pair not mislabeled | U/I/G |
| SR05 | Many hits then KO then combat_end: one escalated harm budget, not stacked full penalties | U/I/G |
| SR06 | Duel/consent and accidental hit: distinct intent; no invented consent; second distinct assault still matters | U/I/G |
| SR07 | Defensive limb loss grievance distinct from aggression; duplicate limb hook/poll applies once | U/I/G |
| SR08 | B KO by A, C takes property: B has no immediate loss toward C or A for theft; wake missing item blames A | U/I/G |
| SR09 | Same but B has verified better evidence of C: C blamed; no double inferred A charge | U/I/G |
| SR10 | KO from unknown actor, own item consumption, restored item or normal squad inventory change: no invented theft blame | U/I/G |
| SR11 | C enslaves unconscious B after A's attack: latent until aware; enslaver C receives slavery penalty; A only harm | U/I/G |
| SR12 | Unknown owner/captor, actor versus later owner, repeated chaining/poll: no false attribution/duplicate | U/I/G |
| SR13 | Conscious theft caught versus unseen; permission denied/check-only; confirmed removal absent: only confirmed known loss scores | U/I/G |
| SR14 | Trivial item versus primary weapon/most belongings, starving victim's food, returned property: severity and budgets appropriate | U/I/G |
| SR15 | Heal unconscious critically bleeding B with real medicine: stabilization verified; provider credited, not every tick | U/I/G |
| SR16 | Routine aid repeated same episode gives bounded/zero extras; ten distinct genuine lifesaving episodes can reach >=91 | U/I/G |
| SR17 | A injures B then patches B; staged self-harm or accomplice loop: no cheap positive trust farming | U/I/G |
| SR18 | Outsider pickup conscious versus KO: initial suspicion only when known; bed/safe outcome resolves second component | U/I/G |
| SR19 | Carry ends in cage/slavery/dump/death/unknown destination: outcome fact required and attributed; no generic drop rescue | U/I/G |
| SR20 | Same carrying/looting/equipment controls on squad member: no routine penalties; critical rescue positive | U/I/G |
| SR21 | Hungry recipient supplied food then eats: need/consumption reward; full NPC, own food, repeated supply do not farm | U/I/G |
| SR22 | Ordinary trades near zero; six exceptional deals cannot reach Bonded; economic-only affinity cannot qualify recruit | U/I/G |
| SR23 | Missing/heuristic seller, shared faction purse, atomic buy failure: no guessed personal reward or partial effect | U/I/G |
| SR24 | Friend harmed/helped, actual witness with affinity 0/31/56/76/91: expected scaling and direction | U/I/G |
| SR25 | Witness absent/occluded/asleep/KO; server nearby recovery: zero omniscient propagation | U/I/G |
| SR26 | Multiple friends and simultaneous events: pre-event relationships, single-hop bounded propagation, no cascade | U/I/G |
| SR27 | Insult heard by friend versus unseen dialogue: dialogue event validated once; mechanical consequences not counted twice by LLM | U/I/G |
| SR28 | Enemy affinity -85 with low health: surrender offered; rational payment/ceasefire accepted; no affection gate | U/I/G |
| SR29 | Dishonest hated enemy can betray; honored coercive deal minimal gain; attacking after accepted surrender adds betrayal | U/I/G |
| SR30 | Join at 75/76 with/without trust, grievance, independent personality: dispatch gates enforce actual outcomes | U/I/G |
| SR31 | Join bypass attempts via autonomy/director/inline action; forced override and already-companion migration | U/I/G |
| SR32 | Non-scripted slave +10/+20 complete escape: varied lawful results, some >=76; chains only/failed escape no guaranteed join | U/I/G |
| SR33 | Vanilla paid recruit and vanilla slave escape recruitment unchanged; real faction/squad membership proves join | I/G |
| SR34 | Unknown/generic names, rename, same-name NPCs, reused serial after reload: no cross-entity attribution | U/I/G |
| SR35 | Duplicate retry, same-tick distinct events, out-of-order KO/theft/wake: exactly once and correct causal state | U/I/G |
| SR36 | Concurrent dialogue + game effect + worker update to same map: no lost deltas, ledger/snapshot atomic | I |
| SR37 | Crash between ledger/map/history writes and server restart mid-KO/carry/escape: recover without partial or duplicate effect | I/G |
| SR38 | Rollback before attack, during KO, after loot before wake: maps/evidence/incidents/baselines/cursors restore together | I/G |
| SR39 | A→B→A server playthrough switch, New, old save upgrade, export/import: global/unmanaged data preserved | I/G |
| SR40 | Failed migration/capture, stale old-epoch HTTP event, runtime barrier, NEVER_CLEAR option: documented consistent state | I |
| SR41 | Feature disabled/shadow/category flags, old DLL/protocol: no R4 double-count or retroactive backlog | U/I/G |
| SR42 | Hidden objective culprit in dialogue/history: victim prompt knows only inferred A blame; C truth stays diagnostic | I/G |
| SR43 | Large combat flood, witness caps, bounded unresolved ledger, cleanup/restart: no lost severe event or unbounded growth | U/I/G |
| SR44 | Harness interruption/lost acknowledgement/fix/rebuild: manifest resumes safely; no duplicate mutation or fabricated pass | I/G |

Each G scenario includes: fixture checksum and server identity, exact setup commands, baseline captured, actual action, expected native event fields, observer knowledge before/after, independently computed expected range, direction, ledger cardinality, trust/grievance, actual game state and timeout/cleanup. Implement these as executable manifests in phase 1, enriching native scenarios with each phase. Explicit BLOCKED until fixtures/control APIs exist, never silently skip.

Oracles must assert independent invariants and pinned numerical examples, not compute expected results by calling the function under test. Add property tests: unknown awareness never negative, squad control never theft/kidnap, duplicate never doubles, effect bounds, distinct rescue progression, anti-trade farming, no recursive propagation, monotonic severity thresholds. Fuzz malformed payloads, null states, ID ambiguity, huge witness lists and invalid game-time. Replay sanitized real raw envelopes collected by G tests through actual HTTP ingress, not only internal functions.

## 9. Release gates and few human checks

Automate syntax/native portable tests, disposable DB migrations/rollback/concurrency, replay, actual game setup/action/state/log assertions, crash detection and fix/rerun bookkeeping. Record tested builds and full installed hashes. Automated scenario runs must also verify genuine game actions, not just test setters or NPC claims. Use mocked model output for repeatable dispatch invariants, plus a small seeded live-provider smoke batch for real prompt/action integration; report provider flakiness separately.

Performance gate: baseline and feature runs on the same fixture/build/provider settings; compare event-ingress p50/p95, queue drain delay, DB queries/writes per incident, game frame time, memory/ledger growth, foreground time-to-first-speech. Initial target: no per-hit model calls, bounded per-event work, <=10% p95 foreground latency regression and <=5% frame-time regression over baseline; thresholds are proposed acceptance budgets and need stable repeated measurement before judging pass. Stress tests should not silently drop critical KO/recovery/slavery transitions due to queue priority or debounce.

Human checks should be limited to a short subjective balance/play-feel review and voice tone/audio if requested. Visibility, equipment, membership and relationship logic should be verified automatically wherever state/telemetry is available. UI screenshot inspection is an agent task where capture works; existing capture notes say HUD may be absent, so fix capture before declaring visual coverage. Any remaining non-automatable native action must name the exact blocker and a minimal manual procedure; do not ask Shay to rerun the whole matrix.

Ready-to-test package: source commits, DLL hashes, client/server protocol versions, rules version, disabled/shadow defaults, fixture installer, one runner entry point, resume instruction, full machine-readable matrix, known blockers, regression report and rollback instructions. Ready-to-build now means the architecture and behavior are settled; bounded engine probes and telemetry work are explicitly included in phases 0–3, not falsely claimed proven.

## 10. Next builder checklist

1. Read this plan and current repository instructions; recheck source/installed builds and unrelated work. Do not use pending unrelated DLL builds as the baseline without reconciliation.
2. Create isolated source worktrees/staging DB; inspect all writers and action routes. Preserve configured providers, credentials and live gameplay.
3. Implement framework, event transport, identity/epoch and test manifests first. Lock save/rollback behavior before enabling scores.
4. Fix native attribution, then activate reliable combat in shadow mode. Continue phase gates in order.
5. Use the standalone harness (`stobe-auto`/`stobe-say`), paired fixtures and resume logs; later launch/install only within the authorized testing session and with game ownership confirmed.
6. Run automatic identify/fix/revalidate loop; keep results honest about U/I versus G coverage. Final subjective checks can wait until automated gates pass.

Overall difficulty: high, feasible with existing foundations. Highest risk is false attribution/knowledge, then identity and rollback, then duplicate scoring and interactions with existing writers. Balance is configurable and lower technical risk. No calendar estimate is asserted before engine probes confirm visibility, completed theft and captivity hooks.
