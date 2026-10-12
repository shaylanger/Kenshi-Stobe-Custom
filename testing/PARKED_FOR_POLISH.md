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
