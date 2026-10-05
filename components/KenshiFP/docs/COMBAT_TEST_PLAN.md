# KenshiFP Player-Controlled Combat Test Plan
Updated: 2026-10-05. Owner: FP combat development agent. Status: native lifecycle probe and camera/control implementation built and offline-validated; game evidence pending coordinator. Manual combat implementation continues.
Coordination: C:\KenshiModding\FP_COMBAT_COORDINATION_CONTEXT.md (received: m45 baseline).
Design: KENSHI_BIG_MOD_IDEAS_CONTEXT.md section 24.
Game-test owner retains installs, launches, fixture preparation and master test batches.

## Execution contract
- Run only against an explicitly scheduled candidate revision/DLL; never substitute it into an active master batch.
- Before run: record baseline/candidate/harness revisions, SHA256 of installed DLLs, config, plugin options (including KEP crossbow/damage), save-copy identity, actor handles, actual equipment/stats/conditions.
- Existing harness accepted replies are not evidence of gameplay completion.
- Readiness/setup failures are INVALID, not PASS. Repair and repeat; an incomplete run cannot validate a requirement.
- End each row with RESULT <id> PASS|FAIL|INVALID <evidence>; archive raw machine-readable observations and failure excerpt paths.
- Restore the main DLL/config while Kenshi is closed; verify restoration hashes before master tests resume.
- No tests on Shay's own save. Save copies reset between independently destructive scenarios.
- No permanent test-only aim/accuracy/readiness overrides in production. Input injection must enter the same controller as physical input.
- Full acceptance requires every mechanical row passing on the combined source after extraction merge; statistical gates accepted and visual/feel checks reviewed separately.
- Current proposed IDs below are stable requirement IDs, not claims that executable scenarios exist yet.

## Existing harness reuse
status, speed, hp/detail, stat/setstat, inv, iteminfo/equip, sections, teleport, spawn, recruit/select, relation, attack/order, health/hunger, load/wait-world, screenshot and scenario runner.
Use exact #serial/index identities, refresh after load, and verify setup. Pinning/protect may modify normal combat: use only when necessary and disclose the effect; do not protect a victim during damage/XP assertions.
Reuse current fp_mode/fp_state where backward-compatible. Add prefixed commands through the plugin extension API before proposing shared harness ABI changes.

## Planned plugin commands (contracts; not all implemented)
- fp_control on|off; fp_actor <ref>; fp_inspect <ref>; fp_camera <distance>
- fp_combat_input aim|fire|reload|block <down|up>: same input path as user; edge semantics, explicit release and state gates.
- fp_combat_aim <world point> or <actor> <part>: derive view direction, not a guaranteed hit; skeleton/world point observations required.
- fp_combat_state: actual controlled/inspected actor, weapon, input ownership, native combat phase, aim/reload/animation readiness, loaded ammo, reload elapsed/max and measured action counters.
- fp_combat_events after=<sequence>: bounded event stream with overflow detection; input rejection reason, actual shot/impact/victim/part/ammo/XP and revision. A synthetic expected decrement is not evidence.
- fp_combat_reset: resets telemetry/transient input only, never grants ammo, health or readiness.
Missing general queries may need shared harness additions, coordinated with its owner; native event telemetry belongs with the feature if possible.

## Gate 0: source/build/offline controller
| ID | Requirement | Acceptance evidence |
|---|---|---|
| B01 | Complete shared baseline captured | commit and file manifest including active untracked includes/assets |
| B02 | Candidate builds independently | compiler success, exported plugin entry, SHA256, no live paths in output |
| B03 | Controller input edges | held fire emits one request; release/repress emits another only when legal |
| B04 | Reload/readiness/ownership | native reload and readiness gate actions; UI/KO/invalid actor clears intent |
| B05 | Timing and transitions | paused/invalid time cannot complete reload; owner/weapon change cannot transfer actions |
| B06 | Telemetry integrity | measured state, bounded events, overflow reported, versioned schema |
Offline tests are necessary but do not prove engine calls/animations/hit behavior.

## Gate 1: camera/control
| ID | Requirement | Acceptance evidence |
|---|---|---|
| C01 | Zoom between FP and third person preserves control | camera coordinates + same actor/WASD response |
| C02 | Wheel affects distance only | speed unchanged; UI scrolling does not also zoom |
| C03 | Inspect without transfer | camera/input actor stable, stats/inventory actor correct |
| C04 | Explicit transfer/fallback | released inputs, restored native controls, other squad AI unaffected |
| C05 | Lifecycle | load, KO, invalid handle, interiors, stairs; no stuck controls |
Visual camera collision, body visibility and ADS alignment require screenshots/inspection as well as numeric checks.

## Gate 2: ranged mechanics
| ID | Requirement | Acceptance evidence |
|---|---|---|
| R01 | Hold aim / release lower | weapon and animation state agree, both camera views |
| R02 | One legal trigger / one actual shot | input, native shot event, measured loaded/inventory ammo delta |
| R03 | No AI duplicate firing | loaded actor aimed without fire has zero shots; no extra shot after trigger |
| R04 | Visible native-duration reload | no loaded grant before completion; shot rejected during reload; actual animation/time |
| R05 | Manual/automatic reload equivalent | same weapon capacity/ammo/duration; configurable behavior |
| R06 | Finite ammo | correct ammo type, empty/missing ammo, inventory capacity; no creation or underflow |
| R07 | Native damage/XP/hostility | real victim health/armour and shooter XP/aggression, not narration |
| R08 | Spatial body-part hit | directed low-spread diagnostic + actual intersection/part + health delta; no weighted reroll |
| R09 | Intervening NPC | first actual collision victim injured; original aimed actor unchanged when occluded |
| R10 | Cover/parallax | FP/third-person muzzle obstruction prevents shooting through walls |
| R11 | Animated anatomy | moving/race/robot/missing limbs map correctly; nearest valid intersection |
| R12 | Lifecycle/input | UI, pause, actor/weapon swap, KO, reload/save/load, speed/FPS; no inherited fire |
| R13 | KEP compatibility | crossbow/damage option matrix, no duplicate spread/wound effects |
Diagnostic forced spread may isolate hit routing but cannot count toward balance evidence; ordinary production RNG must be used for R14-R16.

## Gate 3: ranged parity and tactical balance
| ID | Requirement | Acceptance evidence |
|---|---|---|
| R14 | Torso accuracy parity | matched native/manual hit rates with sample counts and intervals |
| R15 | Fire-rate/damage parity | shots/game minute, reload time, ammo and damage/game minute |
| R16 | Limb-target tactical impact | miss rates, armour, limb distribution and time to incapacitate |
Matrix: low/medium/high crossbow skill x independent Perception bands; first fixed weapon/quality and stationary human target, then weapon accuracy requirements, distances, movement, injuries/gear, races and armour.
Record effective stats and environmental modifiers immediately before each block. Keep input/aim protocol, target pose and RNG policy explicit.
Use native centre-of-target combat vs reproducible manual torso aim as initial reference; aiming at a leg is a separate tactic, not silently compared with native torso shooting.
Pilot sample size first; choose equivalence margin and powered sample size before production comparisons. Use confidence intervals/equivalence tests, not 'no significant difference means equal'.
Repeated shots at one target are not necessarily independent; reset health/pose and use replicated blocks/seeds where supported. Do not invent controllable engine seeds if none exist.
Report casualties/KO/target movement that invalidate conditions. Do not pool different weapon/config/skill cells to mask a regression.
No final balance PASS until tolerances and missing native dependencies are defined from measured baselines.

## Gate 4: melee feasibility and mechanics (phase 2)
| ID | Requirement | Acceptance evidence |
|---|---|---|
| M01 | Ready click starts native swing | input->wind-up latency, native technique starts without waiting for autonomous initiative |
| M02 | Commitment/recovery | spam cannot increase rate or reset timers; move/block cannot cancel committed swing |
| M03 | Block legal and responsive | actual defence phase/outcome, no blanket immunity or unrelated AI-turn delay |
| M04 | Skill/weapon/injury effects | matched controls demonstrate real speed/defence/damage effects |
| M05 | Native impact/enemy reaction | enemy threatens/defends; one impact; armour/XP/hostility retained |
| M06 | Miss/spacing/recovery | real whiff/obstruction and vulnerability, no remote chase/hit |
| M07 | Buffer | at most one short own-recovery request; expiration and no inherited actions |
| M08 | Lifecycle/crowds | multiple attackers, KO, limbs, unarmed, UI, load, fallback and actor changes |
| M09 | Animation compatibility | vanilla first, individual MCA/DodgeStrafe/Great Anims, then full loadout |
If M01 only passes by spam-forcing a flag or waiting for AI initiative, phase 2 feasibility fails even if health changes.

## Gate 5: merged regression and reliability
| ID | Requirement | Acceptance evidence |
|---|---|---|
| S01 | Extraction integration | gameplay goals/actions work without FP dependency; controls use correct actor identity |
| S02 | Normal/fallback combat | no changes to uncontrolled NPC/squad/native shooting outside manual ownership |
| S03 | Repeated transitions | no stuck aim/reload/control after repeated switching/loading |
| S04 | Soak/performance | bounded polling/event memory, frame cost and action integrity across long run |
| S05 | Release restoration | main build/config verified and test owner can resume existing batch |

## Visual/user checks
ADS alignment and reload readability; zoom/body/clipping; attack/block responsiveness; tactical enjoyment and high-skill limb precision.
Keep these separate from automated mechanical results. No finite suite guarantees absence of all bugs.

## Current evidence
2026-10-05: plan created from live source/SDK and existing harness documentation. Coordination baseline pending. No game commands, installations or game validations performed by this agent.

## Native lifecycle prerequisite P01 (first candidate)
The baseline defines KFP_MANUAL_AIM=0: out-of-combat raise/fire is disabled because field-forcing conflicts with native AI tasks. Do not count that prototype as a validated foundation or enable its instant reload. Before implementing manual dispatch, record native state transitions, animationUpdate callbacks and GunClass::shoot invocations with actual ammo before/after, target identity and stat argument. State integers remain raw until empirically mapped. Polling alone can miss intra-frame events; hook events preserve these. Native target attribution and projectile collision/body-part selection are separate unresolved requirements.

Probe command contract: fp_combat_probe begin|end|state|events [after_sequence]|clear. Recording defaults off. begin resets capture; events returns a bounded sequence log and reports lost records. No command dispatches attacks, reloads, draw, target selection or game-state writes. The coordinator runs P01 in a disposable native crossbow fixture: FP off, then FP on, unchanged native auto combat, initial ammo/skills/equipment recorded via existing harness. Drain events frequently; overflow makes a lifecycle trace incomplete. Include idle, draw, aim, several fire/reload cycles and ammo exhaustion. Record per-limb health/inventory independently. Capture is observational, not proof of manual input or balance.

P01 PASS requires verified command registration, actual native shot callbacks with observable ammo changes, animation callbacks, non-overflowing ordered trace, and clean fixture restore. A missing actor, absent callbacks, unreadable raw state or invalid setup is FAIL with setup=invalid/unresolved and evidence; never a fabricated success. Mapping raw state values to safe manual-action readiness is a separate pending engineering task, not proven by P01 capture. Game runtime/P01 execution is pending coordinator ownership.

## Recorded validations (2026-10-05)
- B07 PASS: gcc C11 -Wall -Wextra -Werror, plain and UndefinedBehaviorSanitizer -fno-sanitize-recover=all. The production probe include is compiled against mocked readable engine regions. Covers capture-off gating, native observed fields, missing actor/unknown fields, unrelated actor exclusion, shot argument identity/ammo before-after, invalid command/sequence/overflow parsing, bounded pagination/lost-record reporting, capture reset ID, and no replenishment writes. Does not establish native offsets or engine lifecycle correctness.
- B08 PASS: eight Python unittest decoder/assessment tests. Covers flattened harness replies, loss/reset, missing CSV columns, sequence gaps/footer inconsistencies, actual paired shot/ammo observations, absent actor/animation/pairs, identity changes and insufficient cycles. Initial truncation test mistakenly retained a valid float; fixed fixture to omit a whole CSV field, then all eight passed.
- B01 partial/build validation PASS: isolated RE_Kenshi MinGW DLL built with expected exported startPlugin symbol. DLL remains uninstalled. Source reviewed: include + new command + post-movement tick + observations in existing hooks; no new hooks or shared actor/STOBE changes.
- ASan attempt FAILED/UNRESOLVED: diagnostic loop required other agent to stop isolated test; targeted process absence confirmed afterward. Root cause not determined; no ASan success claimed. All new offline runs have 20s subprocess timeout, 15s CPU limit, 1MiB output file limit and disabled core dump. No unbounded ASan reruns.
- P01 and every C/R/M/S gameplay row: NOT RUN / PENDING coordinator. Native state mapping, targetless weapon lifecycle, manual firing, reload animation/timing, projectile collision/body-part attribution, XP and parity remain unvalidated.

## Reproducible runner and coordinator wrapper
Offline (WSL, never contacts game): python3 components/KenshiFP/tests/run_offline.py --out <private-artifacts-directory>.
Coordinator-only P01: python3 components/KenshiFP/tests/capture_native_ranged.py --kah-client C:/KenshiModding/Kenshi-Automation-Harness/client/kah.py --dir <installed-harness-folder> --out <new-results-subdirectory> --seconds 60 --min-shots 3. Paths must be converted to WSL paths when using WSL Python. This wrapper does not install/launch/load/equip, issue attacks, heal or change speed. Coordinator prepares selected crossbow actor and sustained native combat on disposable fixture. It observes native FP-off and FP-on cycles, records setup metadata, drains pages with capture IDs, saves raw replies/CSVs, and verifies FP toggle restoration. Separate coordinator restoration of installed DLL hash is still required. A protected target may be used only to sustain this lifecycle probe if disclosed; those results cannot validate damage or accuracy parity.

## Delivered candidate / pending game validation
- Source revision pushed on fp-combat: 538851a6f8f605ffd7a2f80b124a03b5f36f35e3.
- Candidate: C:\KenshiTestRuns\fp-combat\candidates\538851a\KenshiFP.dll.
- SHA256: 9357105baaa1236cd89df0ecf1d606d9d58accf208b9017e214c73ca28325cf8.
- Immutable coordinator request: C:\KenshiTestRuns\fp-combat\requests\20261005-2043-native-ranged-probe.txt.
- P01 result pending. No game execution by this agent; no native readiness, manual-control, reload animation, hit/body-part, accuracy-parity or melee validation claimed. Later docs-only commits do not change this candidate DLL/source identity.

## Camera/control implementation and offline evidence (2026-10-05)
- Implemented commands: fp_control state|take; fp_camera state|distance <0..12>|wheel <-2400..2400>. Existing fp_mode on|off and fp_state retain their contracts. Earlier planned command spellings are proposals, not executable commands.
- Defaults: direct_default=1; camera_zoom=1; key_take_control=F6 (0x75). Wheel changes camera distance, retaining persistent direct controls and old toggle fallback. Physical wheel/WASD respect foreground focus; camera_zoom=0 offers legacy throttle.
- B09 PASS plain GCC and UBSan: full-handle pinning, inspection isolation, explicit transfer, outsider refusal, UI key guard, fallback persistence, missing actor without silent fallback, unload/reload, bounded/finite zoom, eye threshold and frame-rate smoothing. Release callback tested; real engine movement-vector clearing and collision remain unvalidated.
- B07/B08 re-run PASS after control integration; isolated MinGW DLL build PASS. No game commands or installs by development agent.
- Coordinator numeric subset C00: tests/validate_camera_control.py --kah-client <kah.py> --dir <installed-harness> --out <new-directory> --actor-a <awake-squad-ref> --actor-b <different-awake-squad-ref>. Open clear space, closed UI, unpaused disposable fixture required. Actual applied camera distance must exceed 0.75m; confinement that prevents zoom is invalid setup rather than evidence against collision.
- C00 observations cover portions of C01-C04 only. It records raw replies and summary; it does not claim physical WASD, UI/focus scrolling, visible inventory panels, moving transfer, body/head rendering, clipping, C05 lifecycle or full gameplay PASS. Wrapper restores original toggle/requested distance, leaves actor-a selected/controlled; coordinator restores fixture and installed hashes.
