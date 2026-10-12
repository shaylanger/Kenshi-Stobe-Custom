# Parked for later polish (2026-10-11 20:05, m107)

Shay 20:00: credits burning; cut everything not moving forward, ship an MVP now with keyframed
"passable" animations, GPU work stopped. This file lists what was in progress so it can be resumed
and made perfect later. Agent status/handoff files in `C:\KenshiTestRuns\agents\` hold the detail.

## Stopped / parked work
- **GPU lab** (gpu-lab, gpu-wire): CuPy/CUDA port of lab evaluators. 19:33 TDR on the 5090 came from an
  untested elb_kernel (raw heap pointers in the no-heap capture). GPU kernel runs banned. Tooling for
  GPU-vs-CPU agreement exists (gpu-agree.py, optimizer --eval gpu|cpu, gpu/kfpgpu.py). Handoffs:
  agents/gpu-lab.status, gpu-wire.handoff.md.
- **Table/optimizer strokes** (stroke-fix, sj-line): E6 s2 CMA tables (/root/strokefix opt-s2b/c),
  screen-line mode (kfp-stroke-line, accepted for PT17-v2 s0/s3). Superseded by keyframes (Shay 19:30).
- **Lab polish:** hud-check (HUD band/whole-weapon-hidden, decision pending), judge-vec (judge/takecheck
  vectorize, profile in jv-tmp), animlab-maintainer gate rebaseline (gate.sh --update-baseline),
  Taste/rule maps. Keyframe take checks in kfcheck (kf-lab DONE).
- **Speed tooling:** speed-scout r10 items 3b/4/5 + WSL detacher (speed-scout.handoff.md).
- **Regression filler:** OFF. Lists parked in `C:\KenshiTestRuns\queue\filler.off\`; restore only for
  the final build (Shay: no regression until final results).
- **Look items still not perfect:** Cleaver strokes (for-shay/CLEAVER README), Naginata arc/twosp/seen
  game-vs-lab divergence (agents/kfp-fixer.note-from-polearm-fix, tables pa-v4..6), heavy 2H tilt
  variants fail SR10 (WEAPONS-v2), Axe blade-seen on h0w1 s0, s3 recovery (TRAVEL-MIN video not made),
  keyframe s0 game take fails wrist/blade checks though Shay approved the look (kf-s0b).
- **Open tickets:** PT30 sword block off-hand near-clip regression (fix kfp-2h-offclip, in MVP build);
  polearm ready elbow zoom-reset mid zoom-in (kfp-elb-zoomreset amend, in MVP build); B03-B06 offline
  stubs (kfp-probe-schema).

## MVP plan (in progress)
1. fix-build agent: one combined pipeline build (offclip, 2h-ready, zoomreset amend, probe-schema) +
   confirm lists only.
2. One keyframe agent: passable keyframe strokes for what is missing (E6 s2 overhead, heavy 2H, Cleaver,
   Naginata) - lab basic checks + one game take each, one for-shay video.
3. Fists v2: existing video (for-shay/NA1-FISTS-v2) goes to Shay as is.

## MVP result
- **E6 s2 overhead (sword) keyframes shipped (kf-mvp, 20:1x):** 5 keys, kfmask 4, default live-tables file
- **Heavy 2H stroke 1 (kf-h1 20:21):** class-1 row 5 (kf.5/kfh.5, kfmask bit 5 -> 63478) = kf.4 keys time-reversed + x-mirrored, roll -20, hz 6.0 (rising B>T, near-identical to s3 kf.7 except depth); lab kfpreview PASS all checks on Buster (wb 46.9) + Fragment Axe (wb 49.8, near limit); 120 mirror/descending variants all failed blade (Axe edge-on) or wrist; no game take. Polish: a distinct descending L>R s1.
- **Naginata stroke 3 rising (kf-pa3b 20:22):** class-2 row 11 (kf.11/kfh.11, kfmask bit 11 -> 65526) = Naginata s0 kf.8 keys time-reversed, hx x0.5, tx x3, ty x4, roll -57. Lab kfpreview --stroke 3 on pa-192-i3/pav6: blade + wrist PASS, span B>T+L>R; path/inline/ang(8)/ctr(.195)/framed/fast FAIL (`C:/KenshiTestRuns/tables/pa3b/n0.5340_-57.tbl`). Rough; no game take. Polish: steeper diagonal, recentre.
- **Naginata stroke 1 (kf-pa1 20:18):** class-2 row 9 = sword row-2 overhead keys (kf.9/kfh.9, kfmask bit 9 -> 63316). Lab kfpreview --stroke 1 on pa-192-i3/pav6 rec: all checks PASS (ang 74, trav .47, ctr .010, span T>B; variant `C:/KenshiTestRuns/tables/pa1-r2.tbl`). Other sources (cleaver 12/13/14, heavy 4/6) FAIL. Rough: same overhead shape as stroke 2. No game take.
  `components/KenshiFP/tables/fp_tables.txt` = `<Kenshi>\mods\KenshiFP\fp_tables.txt` on both rigs + lane instances
  (5090 D:\KenshiInst\2,3; 4080 C:\KenshiInst\2). Lab kfpreview s2 PASS all checks (ang 86, trav .47, arc 12/12, wrist 45);
  game take 300-kfmvp-e6s2 PASS (12 take checks, 0 lab FAILs; C:\KenshiTestRuns\kfmvp-e6s2).
- **Rough:** blade dips briefly off the bottom at u .70-.80; kf rows/kfmask are shared by ALL weapon classes, so this
  file also gives heavy/polearm stroke 2 the sword keys (lab on Buster/Axe: wrist 86 FAIL). Resume: per-class kf rows in
  `pending-fixes/kfp-keyframe-stroke.py` (row = stroke + 4*class, kfmask 12 bits), then add the heavy sets
  (C:\KenshiTestRuns\kf-mvp\HEAVY-NOTES.txt: heavy s0 z1 passes Buster, Axe near-miss blade seen; heavy s2 f5 fails churn/inline).
- **Heavy 2H s0 diagonal keyframes (kf-heavy, 20:1x):** class-1 rows `kf.4`/`kfh.4` + 2H ready keys `vm.twodH_*/tworH_*` (hv-e) in
  `components/KenshiFP/tables/fp_tables.txt`, kfmask bit 16 (now 20). Lab kfpreview PASS all checks on Buster AND Fragment Axe recs
  (set heavy-kf\g6 = gen.py 0 0.55 -1.0 5.5 0 0.66 1.18; perpendicular blade, hz 5.5 keeps the Axe head seen to u .64). No game take.
  Rough: needs the per-class kfp-keyframe-stroke build installed first (installed C54C8EBF clamps kfmask to 15, so the file was NOT
  copied to the game dirs yet: copy it with that build). Axe blade-seen margin is thin (0.062/0.05). Resume: game take via
  fp-weapon-sweep.sh sweep-wc-heavy.list WS_TABLES=<this file>; s2 = agent kf-heavy-s2.
- **Heavy 2H s2 overhead (kf-heavy-s2, 20:1x):** class-1 rows kf.6/kfh.6 (kfmask bit 64) in `components/KenshiFP/tables/fp_tables.txt`; also `C:KenshiTestRuns	ableshv-kf-s2.tbl` (shared-row form) + in `hv-kf-mvp.tbl` (both rigs). Lab kfpreview k6 (E6 s2 keys x-0.1, roll const -30): Buster + Axe blade seen, wrist 39, arc 7/8 + 10/11, crosses T>B.- **Rough (s2 heavy):** lab still FAILs churn + inline (stroke fb 29/68 > 40: blade tilts toward/away from camera mid-stroke); 16 variants (heavy-kfk*,m*; s2v.py) did not clear it, raising hz makes it worse; no game take yet, needs per-class DLL (fix-build).
- **Long Cleaver keyframes (kf-cleaver, 20:1x):** class-3 (1H hacker, wcat 4) rows kf.12-15/kfh.12-15 (kfmask bits 12-15, file kfmask now 61524) in `components/KenshiFP/tables/fp_tables.txt`; source `components/KenshiFP/animlab/kf/tables/clv-mvp-mk.py` (`clv-mvp.txt` rows 0-3 lab form, `clv-mvp-rows12.txt`). 3-key strokes: s0 diagonal UR->LL, s1 backhand UL->LR, s2 overhead, s3 rising LL->UR. Lab kfpreview on take 205-clv-sr37 rec: blade seen on all 4 (0.07-0.14), crosses the screen (trav .60-.65; s2 .34), arm off the head. NOT copied to game dirs: needs the per-class DLL (fix-build) installed first (an older DLL clamps kfmask and would key strokes for every weapon).
- **Rough (cleaver):** no game take; full lab checks still FAIL churn/inline/edge/span/fast/wrist (s0/s1 wrist, s2 blade points into the screen = reads as a stab, trav .34); placeholder L 8 / grip of class 0. Resume: install per-class DLL + copy fp_tables.txt, one take with `WS_TABLES` + WS_STROKES=0,1,2,3 (fp-weapon-sweep.sh line 169 `sleep 2.4` -> `sleep 1; pf_waitst ready 9; sleep 0.6`, cleaver-fix2 ticket 1), then tune edges (roll) per key.
- **Naginata/polearm (kf-polearm 20:10):** shipped in `components/KenshiFP/tables/fp_tables.txt` (installed both rigs): pa-v6 two-hand ready/block keys (`vm.*P`, off hand on the shaft, game twohand .88), `kfc.2.L = 8 0.10 0 0.80` (class 2 grip offset = sword's; 14 placeholder failed), stroke 2 = sword E6 overhead keys on class-2 row 10 (kfmask bit 10). Lab kfpreview s2 on game take pa-192-i3/pav6 rec: all checks PASS (variant `C:\KenshiTestRuns\tables\pc2.tbl`, old shared-row semantics). No game take yet.
- Rough: stroke 0 is still the inherited screen-line diagonal (lab: trav .29, ctr .32 off-centre, hook); hand keys pa-kf7 (`tables\pa-kf7.tbl`) improved it (ang 32, blade/wrist ok) but path/trav still FAIL, not shipped. Resume: author class-2 row 8 (stroke 0) with `kfstroke.py make` + `kfpreview.py --rec C:/KenshiTestRuns/pa-192-i3/pav6/001-Naginata/take.vmrec.txt --stroke 0` (keep hilt y >= -1.3, z 3-4.6 so the shaft stays in view), then one game take; check kfpreview reads per-class rows (adapter rebuild via kf/build-kf.sh).
- **Naginata stroke 0 (kf-pa0 20:17):** class-2 row kf.8/kfh.8 + kfmask bit 8 in fp_tables.txt (keys C:/KenshiTestRuns/tables/pa0/f.tbl, gen pa0/gen.py). Lab kfpreview on pa-192 pav6 rec: blade seen, stroke len, span R>L, trav .74, wrist 40, framed PASS; path FAIL (ang 9 = too flat, wants 38-47; ctr .19 right of centre). 36 candidates tried: steeper ones (ang 30+) lose blade (tip offscreen at end / foreshortened mid-stroke). No game take.
- **Combined build 0E4C44E3 (fix-build, 20:14):** kfp-pipeline run-1011-210805 gate PASS (combined, known-base only), staged + installed on 5090 (Steam + D:\KenshiInst\2,3) and 4080 (Steam + C:\KenshiInst\2); fp_tables.txt 4114846 copied to all six game folders. In: per-class kf rows (class 0 1H rows 0-3, 1 2H heavy/light 4-7, 2 polearm 8-11, 3 hacker/cleaver 12-15, kfmask 16 bits; map in KEYFRAME_FORMAT.md), kfp-2h-offclip (PT30 off-hand cut, lab 151->0), kfp-2h-ready (ready-only 2H offset, keys tworrH_*), fist guard v5 + fp_on 1 compiled defaults, kfp-elb-zoomreset reset moved to camera distance 0, kfp-probe-schema (B06). Lab kfpreview per class on the committed tables: 1H s2 PASS, heavy s0 PASS (Buster rec), polearm s2 PASS (Naginata rec), cleaver s0 FAIL blade (known rough).
- **Naginata stroke 3 (kf-pa3 20:20): NOT shipped**, row 11 stays procedural. kfpreview --stroke 3 on pa-192-i3/pav6 rec, 9 candidates (`C:\KenshiTestRuns\tables\pa3A..N.tbl`, results `pa3*.log`): E6 overhead copy (A) fails blade/path/ang; reversed/mirrored/y-flipped variants worse; cleaver s3 keys (G) blade+wrist ok but stroke/path/span FAIL (no screen crossing). Resume: author with `kfstroke.py make --stroke 3` from G (low-left to high-right path).
  Unconfirmed in game (no takes, Shay order): all of the above. Open: Naginata ready elbow after zoom-out (polearm ticket 2) is NOT fixed: the lab zoom-ramp replay stays 5.2 dm off with the reset at zoom 0; a forced elbow reset ~40 frames later fixes it, so a second state holds it (see kfp-elb-zoomreset.py docstring).
- **1H sword stroke 1 (kf-s1 20:19):** class-0 row kf.1/kfh.1 + kfmask bit 1 in fp_tables.txt (keys C:/KenshiTestRuns/kf-author/s1/g.tbl, gen s1/gen.py: s0 fit reversed = backhand, lateral x1.3). Lab kfpreview: blade seen, crosses screen (trav 0.66), wrist ok, no head fail; inline check FAIL (polish). Unconfirmed in game.
- **Heavy 2H stroke 3 rising (kf-h3 20:20):** class-1 row kf.7/kfh.7 + kfmask bit 7 (128) in fp_tables.txt (keys C:/KenshiTestRuns/heavy-kf/r3h.tbl: kf.4 s0 keys time-reversed, x mirrored, roll -20); lab all checks PASS on Buster Sword and Fragment Axe recs; unconfirmed in game.
