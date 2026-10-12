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
