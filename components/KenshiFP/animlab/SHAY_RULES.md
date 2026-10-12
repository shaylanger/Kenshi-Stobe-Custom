# Shay's FP animation / presentation rules (the one place they live)

Every first-person animation / presentation rule Shay gave, copied word for word from where it was recorded
(memory files, testing/HANDOFF.md "SHAY" lines, animlab STATUS.md). Number = SRn; other docs point here by SRn.
Read this before any FP look work. Judge every lab check by its CODE against these rules: a check that contradicts
a rule is a lab bug (Misses class "check contradicts Shay rule"), never a reason to reject a fix.
Process rules (review, videos, screenshots) are SR33+.

Sources: M = memory file `C:\Users\Shay\.claude\projects\C--KenshiModding\memory\<name>.md`; H = testing/HANDOFF.md line;
S = Kenshi-Automation-Harness/docs/animlab/STATUS.md; R = components/KenshiFP/animlab/taste/rules.tsv (owner shay).

## Sword

| SR | rule (word for word) | when | source |
|---|---|---|---|
| SR1 | "During a sword swing the sharp edge must lead along the swing arc." "you overcorrect": "at the START of the swing (wind-up) the blade may be a bit offline/not aligned with the arc; it must line up as the stroke starts so that during the stroke the edge leads. So: no edge-alignment requirement in the wind-up, strict alignment through the stroke." | 2026-10-09 | M sword-edge-leads-arc; R1 |
| SR2 | "The wind-up keeps the ready grip: NO hand/forearm roll before the stroke (rejected; it made the forearm swing out)." "No sudden wrist/blade rolls (e.g. 90° mid-walk, 180° at wind-up peak)." Plus E5: same swing input -> same forearm roll (no forearm flip mid-stroke); E3: ready pose stable, no sudden ~90 deg roll mid-walk. | 2026-10-09 | M sword-edge-leads-arc; R3, R5, R6 |
| SR3 | "At rest (ready/walk/block) the edge faces away from the player, never toward." | 2026-10-09 | M sword-edge-leads-arc; R7 (S1) |
| SR4 | "In a real sword swing the blade is roughly in line with the forearm (continuation of the arm) and the motion comes from the arm and shoulder; the wrist contributes very little." | 2026-10-09 | M sword-inline-with-forearm; R2 |
| SR5 | "only the movement matters, not screen size: do NOT enlarge the arm or change framing to match Chivalry" | 2026-10-09 | M sword-inline-with-forearm; R22 |
| SR10 | Wrist bend: "holds <= 30 deg (PT30), swings <= 50 (Shay accepted wb36); solver-posed frames only, native-animation frames exempt (Shay 2026-10-10)"; swing-wrist spec video: LEFT ~40 accepted (taste t84/t85). | 2026-10-09/10 | R8; H 18:10 line |
| SR11 | "Diagonal (stroke 0) and rising (stroke 3) must each be one straight screen-space path at ~40-45 deg, corner to corner ("/" not "/\|"), and follow through until the blade tip nears the screen edge." Rejected: "diagonal stops mid-swing / mid-screen with odd movement at the end; rising is good for the first 60-70%, then the blade slides perpendicular to the stroke (no rotation) and ends tip-pointing at screen centre, and its angle is too steep." "Everything else in PT17 is accepted". | 2026-10-11 16:20 (PT17) | M sword-strokes-straight-45; H "SHAY 16:20-16:35 REVIEW VERDICTS"; R30 |
| SR12 | "EVERY swing/stroke is ideally one straight line across the screen, like other games: "just a straight swing/arc/path across the screen"" - the design target for NEW strokes. | 2026-10-11 | M sword-strokes-straight-45 |
| SR13 | "Never change a stroke Shay already accepted (e.g. backhand stroke 1) unless he says so directly": "if the check flags an accepted stroke, it is non-blocking for that stroke and goes to him as a question/video, no retune." "Never retune accepted strokes (stroke 1 etc.) unless Shay says so" | 2026-10-11 16:27 | M sword-strokes-straight-45; H 16:20-16:35 |
| SR14 | "tip travels most of the screen (starts in one outer 20% band, ends in the opposite; leaving the screen counts, long blades/polearms may go off screen)" | 2026-10-11 17:05 | M sword-strokes-straight-45 |
| SR15 | "fairness for blade length via a minimum angular sweep" | 2026-10-11 17:05 | M sword-strokes-straight-45; R31 |
| SR16 | "the straight path crosses the screen centre" | 2026-10-11 17:05 | M sword-strokes-straight-45 |
| SR17 | "A blade may start or end off screen: normal, don't restrict it (Shay 17:10); only the mid-stroke crossing must be visible." | 2026-10-11 17:10 | M sword-strokes-straight-45 |
| SR18 | "Refined (Shay 17:25): ending off screen is fine; a stroke that STARTS off screen must show the wind-up carrying the blade off screen (the blade visibly leaves the screen during the wind-up, no pop-in from outside). Off-screen start/end is never a failure by itself." | 2026-10-11 17:25 | M sword-strokes-straight-45; R32 |
| SR31 | "PT33 open hand: LEAVE FOR NOW (no finger curl, would slow the work)." | 2026-10-11 16:20 | H 16:20-16:35 |
| SR32 | "Z1: SWITCH chosen (fade with hidden body looks like a glitch)" | 2026-10-11 16:20 | H 16:20-16:35 |

## All weapons / all states

| SR | rule (word for word) | when | source |
|---|---|---|---|
| SR6 | "The arm must not make big fast elbow/forearm excursions (out to the side and back) while the weapon barely moves. Arm motion should follow weapon motion." E1: "the sword doesn't really move during that time, just the arm moves around a ton." | 2026-10-09 | M no-arm-churn; R4, U9 |
| SR7 | "Every viewmodel state test must automatically check that the pose visibly differs from ready when it should (aim, block, reload, swing: grip/prop displacement + weapon angle over a threshold). FAIL when the pose doesn't move." "How did this aim issue pass the fixer? This is a clear failure." | 2026-10-09 | M state-must-visibly-play; R9, U3 |
| SR8 | Zoom-out every build: "all animations at zoom 0 and zoom 25 on one sheet, plus the automatic zoom-out checks" (hand away from the head, weapon visible, wrist bend limit). "Numeric PASSes don't prove the look." | 2026-10-09 | M zoomout-every-build; CLAUDE.md VMQUICK; R14 |
| SR29 | No clipped or hollow limbs (near-plane cut) (PT17, X2, C4 Shay reviews). | 2026-10-09/10 | R13, U7 |
| SR23 | "I don't know the items so I can't give feedback, use the native in-game animations to guide you" - inferred/uncertain rules are set from native Kenshi animations, not sent to Shay as rule lists; real taste choices go to him as side-by-side videos. | 2026-10-10 | M native-animations-are-the-reference |

## Two-handed weapons

| SR | rule (word for word) | when | source |
|---|---|---|---|
| SR19 | "2hand weapons need to be 2 hand in fp". "Heavy weapons, polearms and any weapon the game itself holds with both hands get a two-handed first-person grip/poses, not the one-handed katana pose." "grip details come from the game's native animations" | 2026-10-10 | M fp-two-handed-weapons; R24 |
| SR20 | "Katanas/sabres/hackers/blunt: also two-handed in native stances; make them two-handed in FP only if it's an easy adaptation (existing strokes reused, just the off-hand grip added). If it means rebuilding the animations, keep them one-handed." | 2026-10-10 | M fp-two-handed-weapons |
| SR21 | One-handed weapons unchanged by the two-hand path (scope: heavy weapons + polearms). | 2026-10-10 | R29 |

## Unarmed (fists)

| SR | rule (word for word) | when | source |
|---|---|---|---|
| SR22 | NA1 v1 rejected: "not punches at all, the hands just move around on the screen ... trash in every way": black line artifact during the swing, arms don't extend, both hands stay side by side. Target: "a punch = striking arm visibly extends from a chin guard to full reach at the crosshair and back, other hand stays in guard, snap + short hold + slower recovery, derived from Kenshi's native unarmed motion and FP-game conventions." | 2026-10-11 16:45 | M fists-rejected-redesign |
| SR24 | The game's half-open hand is accepted: no fist-closed check. | 2026-10-10 | R U12 |
| SR25 | Palm-heel techniques become straight-wrist punches (wrist <= 30 deg); native palm strikes are not kept. | 2026-10-10 | R U17 |
| SR34 | Zoom 25 unarmed = the native third-person animation, unchanged (NA1 plan row, zoomout rule). | 2026-10-10 | R U13 |

## Crossbow

| SR | rule (word for word) | when | source |
|---|---|---|---|
| SR26 | Stock low (<= 25% from the bottom in ready), crossbow orientation unchanged (C2, C2b accepted). "crossbow FP view = approved + DONE (in installed build)". | 2026-10-10 18:10 | R10; H 18:10 line |
| SR27 | Bolt and strings rigid on the crossbow (C3). | 2026-10-10 | R11 |
| SR28 | No shake in still poses (aim) (X1). | 2026-10-10 | R12 |
| SR30 | Reload = the two-hand upright reload (native); "LEFT accepted, RIGHT rejected" (xbow-reload.mp4): the bow never tipped on its side with the nose down. | 2026-10-10 | R23 |

## Process / presentation

| SR | rule (word for word) | when | source |
|---|---|---|---|
| SR9 | "Every viewmodel/animation screenshot used as evidence must clearly show what is being judged: character on open ground, nothing solid filling the frame, camera angled so the arm/weapon motion is readable" "I have no idea how you are validating anything". Resolution: superseded by Shay 14:31 2026-10-11: "Lower resolution is wanted (we need to see things, not HD...)": filming lanes reduced (e.g. 1280x720) as long as sheets stay judgeable. No cursor / foreign overlay. | 2026-10-09; 2026-10-11 14:31 | M screenshots-must-be-judgeable; CLAUDE.md speed block; R15 |
| SR33 | Review before handing over: frame-by-frame review of every video before Shay; a noticed flaw = fix first. | 2026-10-09 | M review-before-handing-over |
| SR35 | Every visible FP feature that passes gets a short labelled review video + README in C:\KenshiTestRuns\for-shay\<ROW>\ for Shay. | 2026-10-11 | M visible-features-get-video |
| SR36 | Every review flaw -> lab Misses row + automatic check. | 2026-10-10 | M review-flaws-feed-the-lab |
| SR37 | Review videos show exactly 1 swing of each stroke type, once at full speed and once at 1/2 speed. Nothing more (no repeated swings, no 1/4 speed). (The E6 video, 6 swings per stroke, 1:31, real + 1/4 speed, broke this.) | 2026-10-11 18:05 | Shay via coordinator |
| SR38 | Swing strokes must end with the blade TIP in the last 10% (or less) of the screen (outer 10% band on the end side; off screen counts). Replaces the 20% end band. | 2026-10-11 18:15 | Shay direct |
| SR39 | E6 diagonal (stroke 0) and E6 overhead (stroke 2) ONLY, as shipped in E6 (BBF5B2A4): they don't pass through/near the screen centre, don't end in the end band, and tip travel is far too small: these two need about double the tip travel. Applies to these two strokes only, NOT a general threshold change for other strokes. | 2026-10-11 18:10 | Shay E6 review |
| SR40 | Tip-travel minimum for NEW strokes: if E6 had a tip-travel value, double it and use it as the minimum for all new strokes; E6 had none, so first a review video of a swing AT the proposed minimum (2x the measured E6 travel: s0 0.52, s2 0.38 of the screen diagonal); Shay judges it, and the value he approves becomes the minimum for all new strokes. | 2026-10-11 18:20 | Shay direct |
| SR41 | PT17-v2 straight strokes ACCEPTED (stroke 0 diagonal + stroke 3 rising, B17B98D5 / tables pt17v2-s0, pt17v2-s3a): "looks amazing ... feels like a real sword swing". Never retune their paths (SR13). Only fix: rising stroke recovery: as soon as the cut ends and the arm returns to rest at the centre, the blade must rotate to face away from the player IMMEDIATELY during the return (the old rising stroke did this right); now it stays facing the swing and only fixes itself later. | 2026-10-11 18:30 | Shay PT17-v2 review |

## Check audit (rules-audit, 2026-10-11 ~18:00; each check read in code)

| check id | code | rules enforced | contradiction? |
|---|---|---|---|
| moves | metrics.moves_ok / moves_each | SR7 | none |
| arc.edge / arc.wb | metrics.arc_gate (edge on stroke frames u .28-.58 only, wb <= 50) | SR1, SR10 | none (wind-up not judged) |
| churn.rev / churn.roll | metrics.churn_check (rev 450 px / 0.4 s, grip 250; wind-up roll <= 15) | SR6, SR2 | none |
| inline | metrics.inline_check / inline_each (forearm-blade median 30 / max 40; wrist share <= .6 stroke only) | SR4 | none |
| branch | metrics.ready_branch | SR2 (E3) | none |
| hinge | metrics.hinge_check | SR2 (E5) | none |
| stock | metrics.stock_ok | SR26 | none |
| bolt | metrics.bolt_ok | SR27 | none |
| reload | metrics.reload_check | SR30 | none |
| blade.snap / blade.seen | metrics.blade_check | SR17, SR18, SR23 | FIXED 769f29e (before this audit): seen was judged on every frame u .45-.95, so an off-screen follow-through failed; now off-screen tip frames outside SEE_MID (u .40-.58) are skipped. Verified complete. |
| spike | metrics.spike_check | SR2 | none (on-screen frames only) |
| stroke.len / stroke.oh | metrics.stroke_check (unclipped projection, len >= 240 px u .40-.78) | SR29-adjacent (coord) | none vs SR17 (unclipped). OPEN risk SR13: no non-blocking exemption for accepted strokes (s1); accepted recordings pass today |
| path / sweep / wexit / rep / thrust | metrics.path_one, swing_sweep, windup_exit, path_rep, thrust_one | SR11-SR16, SR18 (PATH_INFO = s1, s2 non-blocking = SR13) | none: unclipped tip path, off-screen end = edge 0, off-screen start needs visible exit |
| guard | metrics.guard_check | coord R18 | none |
| zoomband / bandleak | metrics.zoomband_check / bandleak_check | SR32, SR8 | none |
| framed | metrics.framed_check (a wrist in view >= 80% ready/block, >= 50% swing) | coord R35 / SR9 | OPEN risk SR17: a full corner-to-corner stroke whose wrist leaves at both ends could fail the 50% swing share; unproven on a recording, not changed |
| pool_predict / check_suite | metrics.pool_predict / check_suite | aggregates arc/blade/stroke/churn | same SR13 risk as stroke |
| wrist / restedge / stilljit / blade_native | spec.py | SR10, SR3, SR28, SR17/SR23 | none |
| vmcheck.wrist / wswing / zo / cut | components/KenshiFP/tests/ingame/fp-viewmodel.sh embedded vmcheck (held <= 30, swing <= 50, native exempt) | SR10, SR8, SR29 | none (STATUS taste note about t33/t34 "gates swings at 30" is stale) |
| autoreview.weapon / oneview / fragments / occluder / overlay / cursor / openground | autoreview.py, frames.py | SR7, SR26, SR32, SR9, SR29 | none: weapon refs only crossbow aim/fired/reload (no swing frames), sizes read from the video (1280x720 OK per SR9 14:31) |
| takecheck | takecheck.py + take-rules.txt | SR9 (setup) | none |
| wm.vis / near / twohand / seen | weapon_matrix.py | SR7, SR8, SR29, SR19-21, SR17 | none (vis only on ready/block/aim) |
| e6-takes | e6-takes.py | SR4, SR10, SR11, SR13 | none |
| fist C1-C7, hold, C9 | components/KenshiFP/animlab/fist-punch-check.py | SR22, SR25, SR7 (C9 report-only) | none |
| fist C8 off hand | fist-punch-check.py | SR22 "other hand stays in guard" | FIXED (rules-audit): required the off hand to PULL BACK (dz <= -.15 dm), so a guard hand that held still failed; now moves <= .5 dm and no drift toward the target (dz <= +.15); regress 35d fq0 now C8=PASS (still FAIL C1-C7/hold) |
| punch depth..offhand | punch-check.py | SR22 | none |
| punch sides | punch-check.py (guard hands >= 25% width apart, own halves) | SR22 | OPEN risk: a tight chin guard could fail it; Shay's complaint was hands moving together, not spacing; not changed |
| swings / match / plays / view U22 / hud U23 / lens U24 / hand U25 | fist-take-check.py | SR7, SR9, SR29, SR22, SR23 | none (full reach to the crosshair moves away from the lens) |
| black bar | blackbar-check.py | SR22 (no black line) | none |
| U1-U11, U15, U17-U20, U22 | spec.py unarmed | SR22, SR7, SR8, SR10, SR6, SR29, SR23-25 | none (U4 looser than the crosshair rule: gap, C2 holds the 42-55% box) |
| U21 arms never cross | spec.py unarmed (fist within 250 px of the other arm fails) | coord | OPEN risk: a centre chin-guard off hand near a rear-hand punch to the crosshair; not changed |
| stroke-cycle | stroke-cycle.py | SR13 | none |

Coverage gaps (not contradictions): nothing checks that the punching hand and the off hand move independently (SR22 "both hands stay side by side"); no mutation test covers C8.
