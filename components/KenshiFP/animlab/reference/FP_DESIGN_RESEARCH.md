# FP animation design research: published game numbers -> lab checks

Agent `fp-design-research`, 2026-10-11. Goal: turn published first-person (FP) animation design knowledge into numbers the
animation lab can check, so fewer game takes fail review. Companion to `out-defaults/REFERENCE.md` (human mocap, PR1-PR11 in
harness `docs/animlab/STATUS.md`): mocap says what a body does, these numbers say what shipped games show the player.

Method: web search + fetch of wikis, engine source and animation guides. Observation only: no game asset or video was downloaded.
Frame-stepping public footage was not done (it needs the videos; see Q6). Every number below has its source; numbers marked
"community" come from fan wikis, which track patch data but are not official.

Sources (ids used in the tables):

| id | source |
|---|---|
| CH2 | Chivalry 2 weapon timing table (fan wiki, data 2022-08-29): https://chivalry.wiki.gg/wiki/Category:Weapons_(Chivalry_II) |
| CH2c | Chivalry 2 combat page (riposte/counter windows): https://chivalry.wiki.gg/wiki/Combat_(Chivalry_II) |
| CH2x | Chivalry 2 Heavy Crossbow (reload 5.2 s): https://chivalry.wiki.gg/wiki/Heavy_Crossbow |
| CH2p | Chivalry 2 update 1.015 (windup changes, e.g. Highland Sword overhead 0.40 -> 0.45 s): https://mp1st.com/news/chivalry-2-update-1-015-rides-out-today-for-combat-changes-this-march-29 |
| MOR | Mordhau combat 2.0 patch notes (parry window 400 -> 350 ms, parry recovery 650 -> 350 ms, strike release -75 ms, neutral windups +50 ms, combo windups -100 ms): https://steamdb.info/patchnotes/13618125 ; longsword miss recovery 550 ms (main) / 400 ms (alt): https://steamdb.info/patchnotes/4423941 |
| MOg | Mordhau attack = windup (feint/morph possible) / release (damaging) / afterblow; combo skips recovery: https://www.magicgameworld.com/mordhau-short-guide-to-weapons/ |
| TF2 | Team Fortress 2 melee: 0.2 s input -> damage, 0.8 s swing interval (bat 0.5 s): https://wiki.teamfortress.com/wiki/Melee |
| HL2c | Half-Life 2 crowbar `CROWBAR_REFIRE 0.4f`, `CROWBAR_RANGE 75`: https://raw.githubusercontent.com/ValveSoftware/source-sdk-2013/master/src/game/shared/hl2mp/weapon_crowbar.cpp |
| HL2b | Half-Life 2 viewmodel bob (`CalcViewmodelBob`/`AddViewmodelBob`): https://raw.githubusercontent.com/ValveSoftware/source-sdk-2013/master/src/game/shared/hl2/basehlcombatweapon_shared.cpp |
| HL1b | Half-Life 1 view bob + idle sway (`V_CalcBob`, `v_iyaw/iroll/ipitch`): https://raw.githubusercontent.com/ValveSoftware/halflife/master/cl_dll/view.cpp |
| Q1b | Quake `cl_bob 0.02, cl_bobcycle 0.6, cl_bobup 0.5`, clamp -7..4: https://ara-mdk.googlesource.com/platform/external/quake/+/9fd67c44777b350dc56f3e70c88963b0d966ffc7/quake/src/WinQuake/view.c |
| SRC | Source engine viewmodels render at 54 deg: https://developer.valvesoftware.com/wiki/Viewmodels_in_Blender ; TF2 viewmodel FOV 54: https://wiki.teamfortress.com/wiki/Viewmodel |
| CS2 | CS2 `viewmodel_fov` 54-68 (default 60), offsets x -2.5..2.5 / z -2..2: https://totalcsgo.com/commands/fov-and-viewmodel |
| OMW | OpenMW "first person field of view" (hands/held objects) default 60; small values hide the hands: https://openmw.readthedocs.io/en/latest/reference/modding/settings/camera.html |
| SKY | Skyrim FOV default 65 (community), a high `fDefault1stPersonFOV` makes drawn-weapon arms "goofy and bowed": https://steamcommunity.com/app/489830/discussions/0/3184615258409805795 , https://stepmodifications.org/wiki/Guide:Skyrim_INI/Display ; weapon speeds sword 1.0, mace 0.8: https://pt.uesp.net/wiki/Skyrim:Weapon |
| MOC1 | FP animation guide (arms camera 70-75 deg vs world 90-100; ADS 8-15 frames, heavy up to 25; sway -50..-80% when aiming; breathing 12-18/min; head bob 30-60% of "realistic"; screen effects < 1 s): https://mocaponline.com/blogs/mocap-news/first-person-animation-guide |
| MOC2 | Sword melee animation guide (1H swing 0.4-0.8 s; anticipation 0.1-0.2 s light; swing 6-12 frames @30 light, 12-24 heavy; fastest point at 60-70% of the arc; horizontal follow-through 30-60 deg past centre; heavy recovery 0.8-1.5 s; combo window at ~70% of recovery; hit stop 1-4 frames): https://mocaponline.com/blogs/mocap-news/sword-melee-animation-guide |
| UT2 | Unturned II devlog 041: FP melee swings blend toward the third-person pose so reach and the hit point read: https://devtrackers.gg/unturned/p/d8f64325-unturned-ii-devlog-041 |
| ME | Mirror's Edge (DICE, GDC "Creating First Person Movement for Mirror's Edge"): a camera on the mocapped head did not work, the FP camera/arms were hand-keyed: https://gdcvault.com/play/1012171/Creating-First-Person-Movement-for , https://www.gameanim.com/?p=2058 |
| DL2 | Dying Light 2 (Techland animation director): FP avatar animation is hand-keyed, enemies mocap; impact strength was pulled back toward balance: https://3dvf.com/en/redaction/dying-light-2-stay-human-our-interview-with-techland-about-the-gut-feeling-update-focused-on-combat-animations-and-physics/ |
| DLk | Dying Light dropkick: jump, camera and gravity tuned so the player's legs never cover the enemy and the target stays on screen after impact: https://80.lv/articles/developing-dying-light-s-iconic-dropkick-move |
| BLx | Bannerlord crossbow reload ~10 s light / ~20 s heavy (mod article, version unknown; scales with skill): https://nexusmods.com/mountandblade2bannerlord/articles/332 |

Not found (searched, no published numbers): Kingdom Come: Deliverance 1/2 timing or camera write-ups, Dark Messiah, Dishonored
(only "kill animations must not move the viewpoint jarringly", https://www.moddb.com/news/dishonored-in-vr-arkane-is-thinking-about-it),
Mordhau absolute per-weapon tables (the wikis are paywalled/blocked to fetch), Skyrim hit-frame times, Warband swing formula.

"Ours" = KenshiFP compiled tables 4f49590b through the drive (from `out-defaults/REFERENCE.md`): sword strokes 0-3 wind-up
0.00 / 0.00 / 0.05 / 0.23 s (share 0 / 0 / .09 / .40), stroke 0.55 / 0.18 / 0.52 / 0.20 s, whole motion 0.58-0.60 s.

## 1. One-handed sword (and 1H axe/mace)

| property | typical range in shipped games | sources |
|---|---|---|
| wind-up (input -> strike starts) | 0.12-0.20 s light (sword .15, short sword .125, rapier .12, falchion .20, 1H axe .175, 1H warhammer .20); light anticipation 0.1-0.2 s | CH2, MOC2 |
| input -> first damage | 0.2 s (TF2 all melee but spy) | TF2 |
| strike/release (damaging sweep) | 0.40-0.50 s (sword .425, short .40, falchion .475, axe .45, warhammer .50); light swing 0.2-0.4 s (6-12 frames @30) | CH2, MOC2 |
| wind-up share of wind-up + strike | 0.22-0.32 (CH2 light) | CH2 (derived) |
| recovery after a miss / full chain | 0.65-0.90 s (CH2); Mordhau longsword miss recovery 0.40-0.55 s | CH2, MOR |
| whole swing (input -> ready again) | 0.4-0.8 s (MOC2 1H), refire 0.4 s (HL2 crowbar), 0.5-0.8 s (TF2), 1.2-1.4 s (CH2 incl. recovery) | MOC2, HL2c, TF2, CH2 |
| where the swing is fastest | 60-70% through the arc (accelerate in, slow out after contact) | MOC2 |
| horizontal follow-through | 30-60 deg past the centre line | MOC2 |
| combo | next attack skips recovery / starts at ~70% of recovery; combo windups 0.1 s shorter than neutral (Mordhau) | MOg, MOC2, MOR |
| heavy (held) | light wind-up + 0.35 s hold (CH2 heavies = light + .35) | CH2 |
| hit stop / slowdown | 1-4 frames pause or 2-4 frames slowed | MOC2 |
| FP readability tricks | swing blends toward the 3rd-person pose to show reach and hit point (UT2); FP arms are hand-keyed, not head-camera mocap (ME, DL2) | UT2, ME, DL2 |

## 2. Two-handed (greatsword, longsword, 2H axe, maul, polearm)

| property | typical range | sources |
|---|---|---|
| wind-up | 0.20-0.43 s (longsword .225, dane axe .275, greatsword .325, messer .325, battle axe .33, halberd .35, pole axe .35, spear .35, maul .375, highland .425); overheads up to 0.475 | CH2, CH2p |
| strike/release | 0.47-0.65 s (longsword .475, dane axe .50, pole axe .50, messer .525, greatsword .55, maul .55, halberd .60, highland .65); thrust-only spear/lance .35 | CH2 |
| wind-up share of wind-up + strike | 0.32-0.41 (longsword .32, dane axe .35, greatsword/battle axe/halberd .37, messer .38, highland .40, maul/pole axe .41) vs 1H 0.22-0.32 | CH2 (derived) |
| ratio 2H / 1H | wind-up x1.5-2.8, strike x1.1-1.5, recovery x1.1-1.9 (CH2); heavy swing ~2x light frames (MOC2) | CH2, MOC2 |
| recovery | 0.8-1.4 s (CH2 0.8-1.4; MOC2 heavy 0.8-1.5) | CH2, MOC2 |
| human mocap (for contrast) | axe chop wind-up share 0.43-0.68, chop 0.16-0.37 s (PR5) | REFERENCE.md |

## 3. Crossbow

| property | typical range | sources |
|---|---|---|
| reload | 5.2 s heavy (CH2, longest of its crossbows); ~10 s light / ~20 s heavy before skill (Bannerlord, mod article); "slow" everywhere | CH2x, BLx |
| aim-in (ADS) transition | 8-15 frames @30 = 0.27-0.50 s responsive, up to 25 frames = 0.83 s heavy | MOC1 |
| sway while aiming | reduced 50-80% vs hip | MOC1 |
| idle breathing | 12-18 cycles/min (0.2-0.3 Hz), very small amplitude | MOC1 |
| counter/parry vs bolts | 0.25 s window (CH2) | CH2c |

## 4. Unarmed (fists, kicks)

| property | typical range | sources |
|---|---|---|
| jab / kick | CH2 jab and kick cannot be cancelled (no numbers) | CH2c |
| FP kick framing | the player's own legs must never cover the target, target stays on screen after impact; camera/gravity tuned together | DLk |
| fast melee interval | TF2 bat 0.5 s, 0.2 s to damage | TF2 |

## 5. Framing, FOV, bob, sway (all families)

| property | typical range | sources |
|---|---|---|
| viewmodel FOV | 54 (Source/HL2/TF2), 60 (CS2 default, OpenMW), 54-68 (CS2 range), 70-75 (MOC1 recommendation); world FOV 65 (Skyrim), 75 (HL2), 90-100 (MOC1) | SRC, CS2, OMW, SKY, MOC1 |
| viewmodel / world FOV ratio | 0.70-0.85 (54/75 = .72, 70-75/90-100 = .75-.78) | derived |
| too-high arms FOV | arms look "goofy and bowed" (Skyrim); too low hides the hands (OpenMW) | SKY, OMW |
| walk bob (HL2 viewmodel, at max 320 u/s) | bob = 0.005 x speed = 1.6 u peak; viewmodel right 0.8 x bob = 1.3 u (~3 cm), up/forward 0.1 x bob = 0.16 u, roll 0.5 x bob = 0.8 deg, pitch 0.4 x bob = 0.64 deg, yaw 0.3 x bob = 0.5 deg; cycle 0.45 s at full speed; clamp -7..4 u | HL2b |
| walk bob (HL1/Quake, older and bigger) | bob = 0.01-0.02 x speed, clamp -7..4 u; viewmodel roll = bob (up to ~3 deg at 320 u/s), yaw 0.5 x bob, pitch 0.3 x bob, forward 0.4 x bob; cycle 0.6-0.8 s | HL1b, Q1b |
| idle sway (HL1) | yaw 0.3 deg @ cycle 2, pitch 0.3 deg @ 1, roll 0.1 deg @ 0.5 | HL1b |
| head bob size | 30-60% of a realistic head bob | MOC1 |
| screen effects / shake | none lasting > 1 s; DL2 pulled impact strength back | MOC1, DL2 |
| own-body glimpses | Mirror's Edge shows the body only when looking down / reaching, not constantly | ME |

## 6. Proposed lab checks (FD1-FD9; owner animlab-spec decides; inferred until Shay/coord confirm)

| id | rule | threshold | would have caught | answers |
|---|---|---|---|---|
| FD1 | stroke peak timing: the tip screen speed peaks in the second half of the stroke (accelerate in, decelerate after contact) | peak at u_stroke 0.45-0.80 (MOC2 60-70%, margin for 33 ms sampling) | strokes that snap at the wind-up top then coast (R17 snap, E1 "wrist flip at the top"), a stroke that is fastest at its start reads as a twitch | R17 blade.snap (adds the timing side), PR1 spikes at u .28 |
| FD2 | 1H wind-up exists but is short | 1H wind-up 0.08-0.25 s and share 0.15-0.35 of wind-up+stroke; flag 0.00 | ours strokes 0/1 have 0.00 s wind-up: no anticipation, the stroke starts from ready (a reviewer reads it as "no swing start") | PR5 (1H side), R9 moves; QUESTION Q1 (wind-up churn history) |
| FD3 | 2H timing differs from 1H | 2H wind-up 0.20-0.45 s, share 0.30-0.45; strike 0.45-0.65 s; wind-up >= 1.5 x the 1H wind-up of the same build | 2H family reusing the 1H key times (ours: the 1H .28 wind-up for every 2H weapon) | PR5: game data says share 0.32-0.41, the mocap 0.43 floor is too strict for a game; use 0.30 |
| FD4 | horizontal strokes cross the screen centre and follow through | tip crosses screen x = 0.5 and ends >= 0.15 screen width past it (~30 deg at our FOV); vertical/overhead strokes end below the centre line | short strokes that stop before centre (coord "stroke.len" reviews), arcs too short to read (PR4 path 0.7-1.2 arm) | R17 stroke.len (makes the coord rule numeric), PR4 (screen-space version that respects R22) |
| FD5 | walk bob of the weapon is small and smooth | over a walk: grip lateral excursion <= 3% of screen width, vertical <= 2% of height, weapon roll <= 3 deg peak-to-peak, period 0.4-0.9 s (HL2/HL1/Quake) | the 90-deg roll mid-walk (E3), branch flips during walk | R6 branch (gives an absolute walk limit instead of only a ref recording) |
| FD6 | still poses breathe slowly, never shake | in aim/ready-still: periodic motion only < 0.5 Hz and <= 0.5 deg / 0.5% screen; any energy above 2 Hz = shake | X1 aim shake; a solver oscillation that stilljit p95 misses because it is slow but large | R12 stilljit (frequency side; makes it build-independent) |
| FD7 | aim-in transition takes a visible but short time | ready -> aim pose within 10% of final in 0.25-0.85 s (MOC1 8-25 frames @30); < 0.1 s = snap | the C1 "aim stopped playing" class (0 s or never), and a snap-to-aim that reads as a pop | R9 moves (timing side), PR11 |
| FD8 | crossbow reload is long and readable | native reload kept: duration >= 2 s and not shortened vs the native clip; the weapon stays >= 50% on screen through it | a sped-up/cut reload; the C-class "reload not visible" | R23 reload (adds duration + visibility) |
| FD9 | FP kick: legs/arms never cover the target | during a kick the screen centre third (x .33-.67, y .33-.67) is covered <= 25% by own body | the fist Misses where the arm/leg fills a third of the screen (FIST-ma_chudan, FIST-ma_2strike, FIST-badpunch 2026-10-10) | U14 / PR9 (kick candidate limits), U24 lens (adds a coverage number) |

Supported without a new check: PR6 (2H spacing), R8 (the 30-deg hold limit is Shay's look; games give no wrist data), R22 (keep
framing; no change proposed: FD4 is screen-space so it works inside the current framing).

## 7. Questions for Shay (batched; taste calls the research can't settle)

- Q1 Wind-up: shipped games give every 1H swing a 0.12-0.2 s anticipation (20-30% of the swing); ours has none on strokes 0/1. Want a short wind-up (straight back along the arc, no roll: churn stays banned), or keep the instant start?
- Q2 Two-handed timing: should heavy weapons/polearms swing slower than 1H (games: wind-up 1.5-2.8x, strike 1.1-1.5x longer), or keep Kenshi's native attack timing for both?
- Q3 Separate arms FOV: most FP games draw the arms at a narrower FOV (54-75) than the world (75-100) so arms don't stretch at the edges. KenshiFP draws them with the world camera. Is a viewmodel FOV a framing change you want to avoid (R22), or worth a side-by-side video?
- Q4 Swing reach: Unturned II blends the FP swing toward the third-person pose so the hit point reads. Want long horizontal strokes that clearly cross the centre (FD4), even if the arm extends more?
- Q5 Hit feedback: games add 1-4 frames of hit stop or a short camera kick on contact. Wanted for FP melee, or none?
- Q6 Footage study: frame-stepping public gameplay videos (Chivalry 2, Mordhau, KCD2) would give the screen-position numbers no wiki has (where the hands sit, how far strokes cross). OK to fetch public videos for measurement only (no game files)?
