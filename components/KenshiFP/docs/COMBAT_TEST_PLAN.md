# KenshiFP Player-Controlled Combat Test Plan
Updated: 2026-10-06. Status: manual ranged/melee adapter in main (KenshiFP FE26573F on both rigs, FP-only since the m49 decoupling; harness 2995EE5E), manual combat OFF by default. Passed rows are deleted (run logs `archive/test-run-2026-10-05-m41.md`, `archive/test-run-2026-10-06-m49.md`); the tables hold open rows only.
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
Visual camera collision, body visibility and ADS alignment require screenshots/inspection as well as numeric checks.

## Gate 1b: FP controls (scheme 2026-10-06, KenshiFP 6E5D502B+)
Wrapper `tests/ingame/fp-controls.sh` (fixture kah-fpxbow: Axima crossbow player, Malzin mate, Skaera hostile; usage in its header). Input enters through `fp_keys press|native` (same tick path as the physical buttons) and `fp_combat input`; evidence is `fp_keys state` counters, `fp_combat state` (wih, fp_ui_state, actual_shots, ammo), `fp_camera state|probe`, `fp_melee state`, `where`/`hp`, KenshiFP.log. Not yet run in game.
| ID | Requirement | Acceptance evidence |
|---|---|---|
Visual rows (screenshot or Shay's eye, MASTER section 2): K01 native-walk marker, the K03 context-menu visuals, the HUD01 label look.

## Gate 1c: FP stealth attacks (KenshiFP 7B8175EF+)
Sneaking + LMB drawn (melee) on a character that does not perceive the attacker (`SensoryData::amIAwareOfThisGuy(attacker, needToSeeOrHear=1)` = 0) gives the vanilla sneak-mode order `STEALTH_KNOCKOUT` (228: walk up, `getStealthKOChance` roll); aware/unreadable target = the normal K05 engage. Holstered LMB stays non-combat (scheme). Evidence: `fp_keys state` sneak_* fields, `fp_keys sneak [show]` (crosshair probe), KenshiFP.log `[controls] LMB sneak=1 target= target_aware= aware_any= ko_chance= path= task=` and `[controls] sneak result=ko|dead|failed|timeout|lost`. Wrapper `tests/ingame/fp-stealth.sh` (kah-fpxbow, each row spawns its own neutral target; skills stealth/assassination 100 for the run).
| ID | Requirement | Acceptance evidence |
|---|---|---|

## Gate 2: ranged mechanics
| ID | Requirement | Acceptance evidence |
|---|---|---|
| R10 | Cover/parallax | FP/third-person muzzle obstruction prevents shooting through walls |
| R11 | Animated anatomy | moving/race/robot/missing limbs map correctly; nearest valid intersection (`fp-manual-anatomy.sh`: R11-MOVE/RACE/LIMB); PASS 4080 b21 (MOVE/RACE/LIMB); PASS 5090 m49 (MOVE dec-5090-2, LIMB dec-5090-4, RACE dec-5090-5 with bone-point aim) |
| R12 | Lifecycle/input | UI, pause, actor/weapon swap, KO, reload/save/load, speed/FPS; no inherited fire |
Diagnostic forced spread may isolate hit routing but cannot count toward balance evidence; ordinary production RNG must be used for R14-R16.

## Gate 3: ranged parity and tactical balance
| ID | Requirement | Acceptance evidence |
|---|---|---|
| R14 | Torso accuracy parity | matched native/manual hit rates with sample counts and intervals |
| R15 | Fire-rate/damage parity | shots/game minute, reload time, ammo and damage/game minute |
| R16 | Limb-target tactical impact | miss rates, armour, limb distribution and time to incapacitate (`fp-manual-limbs.sh`) |
Matrix: low/medium/high crossbow skill x independent Perception bands; first fixed weapon/quality and stationary human target, then weapon accuracy requirements, distances, movement, injuries/gear, races and armour.
Record effective stats and environmental modifiers immediately before each block. Keep input/aim protocol, target pose and RNG policy explicit.
Use native centre-of-target combat vs reproducible manual torso aim as initial reference; aiming at a leg is a separate tactic, not silently compared with native torso shooting.
Pilot sample size first; choose equivalence margin and powered sample size before production comparisons. Use confidence intervals/equivalence tests, not 'no significant difference means equal'.
Repeated shots at one target are not necessarily independent; reset health/pose and use replicated blocks/seeds where supported. Do not invent controllable engine seeds if none exist.
Report casualties/KO/target movement that invalidate conditions. Do not pool different weapon/config/skill cells to mask a regression.
No final balance PASS until tolerances and missing native dependencies are defined from measured baselines.

**Gate 3 DECISION (Shay, 2026-10-06): manual aim may beat the game's dice for now** (real targets move, which adds difficulty native shooting never has; no skill wobble added; revisit if it plays overpowered). R14 = report the hit-rate difference, not a pass/fail margin; R15 and R16 stay in force. Original proposal, kept for reference: Baselines (4080, 80 dm, crossbows 30,
perception 59, stationary human, production RNG): torso hits manual b8 18/20 + b27 20/20 = 38/40 (0.95), native b8 18/20 +
b25 17/20 + b27 17/20 = 52/60 (0.87); difference +0.08, 90% CI [-0.01, +0.18]. Damage/hit manual 21.5/20.5 vs native
22.4/21.4. Real s/shot manual 13.1/12.9 vs native game s 6.4/6.3.
- **R14 torso accuracy:** TOST equivalence on the hit-rate difference (manual - native), margin +/-0.15 absolute, alpha 0.05
  (90% CI inside the margin). About 85 shots per arm per cell (true difference 0, power 0.8, p ~0.88); +/-0.10 needs ~190 per
  arm. Shots in replicated blocks of 20 with target health/pose reset between blocks. The current pooled data (40/60) is not
  yet equivalent (CI upper 0.18 > 0.15): manual aim at a stationary torso may be more accurate than native, which is
  expected for player aim. If the powered run confirms manual > native + 0.15, that is a balance decision, not a mechanics bug.
- **R15 fire rate/damage:** manual must not fire faster than native: game-time s/shot manual >= 0.9x native per cell.
  Damage per hit: ratio manual/native with its 90% CI inside [0.85, 1.18].
- **R16 limb targeting:** leg aim lands on the leg >= 0.8 of hits; leg targeting must not incapacitate faster than torso
  aim by more than 20% (time to KO/immobile), so limb aim is a tactic, not a dominant exploit.

## Gate 4: melee feasibility and mechanics (phase 2)
| ID | Requirement | Acceptance evidence |
|---|---|---|
If M01 only passes by spam-forcing a flag or waiting for AI initiative, phase 2 feasibility fails even if health changes.

Notes (2026-10-05, KenshiFP 62464E5D): B17 offline covers AI refusal, click buffer, latency, owned-only approach refusal, hold ground, spam switch and swing timing. M01 latency is product-measured (`last_latency_ms`, harness round trip ~0.3 s per call). M02 uses the product spam switch `fp_melee spam 15 200` (wrapper clicks really ran at ~0.8 s each: 8 swings + 7 rejected = native pace) and asserts `min_swing_gap >= last_swing_len`. M06: no AI combat locomotion while owned (`hold_halts`, `approach_refused`), out-of-reach click counted `out_of_reach`; evidence includes target drift to rule out the pin. M04 windows use the spam switch (wrapper clicks capped every window at ~6 swings); M04-DMG picks the stat that moves the native `primaryweapondamage` for the weapon (katana = cutting; strength gave +7%); M04-DEF uses 3x windows and logs a native-AI control on FAIL. M08-UNARMED hit evidence = flesh drop or `melee_hits` (native addWound calls by the fighter, cut+blunt > 0); blood is reported only (older cuts keep bleeding: m50-b blood 77.7->76.9 with no hit); M08-CROWD clicks at legal native moments (two attackers, no RMB block -> mostly STUMBLE, where clicks are rejected natively).

## Gate 5: merged regression and reliability
| ID | Requirement | Acceptance evidence |
|---|---|---|
| S01 | Extraction integration | gameplay goals/actions work without FP dependency; controls use correct actor identity |
| S02 | Normal/fallback combat | no changes to uncontrolled NPC/squad/native shooting outside manual ownership |
| S03 | Repeated transitions | no stuck aim/reload/control after repeated switching/loading (`fp-manual-transitions.sh`) |

## Gate 6: Shay playtest 2026-10-07 (5090, KenshiFP 07376F24; logs `C:\KenshiTestRuns\logs\20261007-shay-play\`)
Most of these broke under combined actions (toggle FP off/on, two weapons, squad switching, fight then talk), so every row
needs a compound scenario (several actions in a row, toggles between them), not one isolated action.
| ID | Problem (Shay) | Want / log evidence | State (KenshiFP commit) |
|---|---|---|---|
| PT04 | Movement feels far too fast with no athletics gear | find out: KenshiFP drive speed, PG athletics accel hook (f212cbc), time scale; compare vs vanilla run speed with the same char | measured m54: FP W 12.5 u/s vs vanilla run 54.1 u/s; Shay decision (target speed) |
| PT06 | Hold-RMB context menu doesn't work any more | menu opens on hold | fixed 1a70eb1, wrapper `tests/ingame/fp-playtest.sh` |
| PT13 | Crossbow not visible in FP (out of FOV) | whole crossbow visible; raised on aim; reload clearly visible | coordinator (viewmodel), not in the wrapper |
| PT17 | FP combat view/animations overall | coordinator plays it on the 4080 (screenshots), compares with other FP melee/crossbow games, then fixes | coordinator on the 4080, not in the wrapper |
| PT20 | No way to switch which squad member you control in FP | squad bar right-click menu -> "Control" | fixed 968a5f6, wrapper `tests/ingame/fp-playtest.sh` (FP RMB menu path via fp_keys ctl click; squad-bar portrait path not automated) |

## Visual/user checks
ADS alignment and reload readability; zoom/body/clipping; attack/block responsiveness; tactical enjoyment and high-skill limb precision.
Keep these separate from automated mechanical results. No finite suite guarantees absence of all bugs.

## Current state
PASS (evidence in `archive/test-run-2026-10-05-m41.md`, `archive/test-run-2026-10-06-m49.md`, `C:\KenshiTestRuns\fp-combat\results\merged-1\RESULT.txt`): P01, P02, C00, B14/B14-frame, R01-R09 and R13 (both rigs again on the decoupled KenshiFP FE26573F, m49), R11 (both rigs), FP-EYE (`fp-eye-drift.sh`: the FP eye no longer rises while aiming; both rigs m49), S04 (both rigs; 5090 overshoot = native-AI baseline per S04-CTRL), M00-M07 (4080), R12 subset (pause, FP off, actor swap), S02 for ranged (P01 FP off/on A/B), S01 (= decoupling DC1-DC5: Stobe goals/actions work with the KenshiFP DLL absent, m49).
Reconfirmed m50 (`archive/test-run-2026-10-06-m50.md`): R10 + R10-CTRL (4080 b33), R12-UI/KO/SWAP/SPEED/LOAD (4080 b36b), R14, R15, R16, S03 (5090 B), M08-UI/KO/LOAD/UNARMED/CROWD/ACTOR/LIMB (4080 b37, KenshiFP 29DEC0D2). Also PASS m50: C01, C02, C03, C04-TAKE, C04-FALLBACK (4080 b36b); controls K01, K03, Z01, Z01-INT, DOWN01 (4080 b37; rows deleted above).
Also PASS m50 on KenshiFP 44458ACE (NavMesh-crash fix fc60924; 5090 P/Q): stealth ST01, ST02, ST03; ranged R01-R06 + R12 subset again (free-aim fix); C01, C03, C04-TAKE, C04-FALLBACK, C05-KO, C05-INVALID, C05-LOAD, C05-INTERIOR; no crash, no weld jump.
Also PASS m50: C01-C04, C05-KO/INVALID/LOAD/INTERIOR on both rigs (5090 T, 4080 b45); M09 life rows M08-* in mca/dodge/full (4080 b45/b46), M09 melee rows in all 5 loadouts (bm43).
Also PASS m50 on KenshiFP 8469D760: M09 vanilla all rows (4080 b48) + mca life rows, so M09 is closed in all 5 loadouts; C05-STAIRS on a real world stair (5090, kah-fpstairs); S05-BUILD on both rigs (S05-RESUME earlier in m50); controls K01-K06 and stealth ST01-ST03 (rows deleted above).
Open: no automated rows. Gate 3 tolerances decided 2026-10-06 (R14 report-only, R15/R16 in force, reconfirmed m50). Left: the visual/user checks below (Shay, MASTER section 2) and Shay's call on turning manual combat on by default (it stays OFF until then).
Method notes still valid: P01 needs a background `rangedtest <shooter> <target> shots 60 timeout 220 attack` to keep the native target; P02 needs `combatmode Shay block off passive off`; melee target = CombatClass+0x298 (swing target) / +0x2C8 (ordered target), +0x290 is always 0; game units are decimetres (eye = `where` y + 19 dm); R08 wrapper re-aims at the neck/chest bone, aims beside an arm that covers the aim point (else the aimed part or that arm counts) and retakes shots whose pose at the trigger no longer fits the aim; R09 blocker sits on the eye->target line ~13 dm up; R11-RACE uses Shek first (Hive drones bob 2.5 dm).

## Open notes (from the development log; history of finished candidates/requests: git log -p of this file)
- STOP before gameplay enable: truce guard, physical mouse dispatch conflicts, lifecycle/identity/thread/fault handling, dt/speed ownership, reload interruption/lowering, TPS actual-camera/muzzle/ADS, projectile target modifiers/spatial part routing and melee/root motion all remain unresolved. See full FP_COMBAT_DESIGN_RE.md.
- R10 pending native acceptance: actual-camera scene-to-world ray now used by manual adapter, nearest <=80m static/visual obstruction; verify crosshair vs true bolt path at FP/near/far TPS and both floating origins. Native animated NPC aim selection/muzzle-vs-camera obstruction remains incomplete.
- R12/S02 pending truce cases: conservative interim gate rejects manual shots while any STOBE truce slot is active; clicks during truce must not queue/replay on expiry; normal/unowned actors untouched. Test precise victim checks and truce starting while a projectile is in flight before replacing broad gate.
- R12 pending engine input validation: preserve actual inventory/stat/squad-widget MyGUI clicks, modifier selection/orders, releasing previously held buttons, focus/window/UI changes mid-aim; zero vanilla attack/move orders from consumed unmodified world fire/aim clicks; no manual shot from UI or modifier passthrough. GUI refresh query and callback threading need runtime evidence. No new manual candidate packaged.

## Reproducible runner and coordinator wrapper
Offline (WSL, never contacts game): python3 components/KenshiFP/tests/run_offline.py --out <private-artifacts-directory>.
Coordinator-only P01: python3 components/KenshiFP/tests/capture_native_ranged.py --kah-client C:/KenshiModding/Kenshi-Automation-Harness/client/kah.py --dir <installed-harness-folder> --out <new-results-subdirectory> --seconds 60 --min-shots 3. Paths must be converted to WSL paths when using WSL Python. This wrapper does not install/launch/load/equip, issue attacks, heal or change speed. Coordinator prepares selected crossbow actor and sustained native combat on disposable fixture. It observes native FP-off and FP-on cycles, records setup metadata, drains pages with capture IDs, saves raw replies/CSVs, and verifies FP toggle restoration. Separate coordinator restoration of installed DLL hash is still required. A protected target may be used only to sustain this lifecycle probe if disclosed; those results cannot validate damage or accuracy parity.
