# KenshiFP keyframe sword strokes: data format

Patch: `pending-fixes/kfp-keyframe-stroke.py` (keyframe-player, Shay 2026-10-11). Opt-in per stroke; with `kfmask = 0`
(compiled default) nothing shipped changes. Independent of `kfp-stroke-line` (applies before or after it, same result).

## Model
A keyframe stroke = 2..6 keys of the WEAPON, given in screen terms, plus per-segment easing. KenshiFP interpolates the
weapon pose; everything downstream (arm IK, elbow pick, wrist roll, E1 edge lead, inline, near clip) is the shipped code.

- **Screen space**: x, y in -1..1 (x right, y up; 0,0 = screen centre), zoom-0 FP camera, tan half-angles
  1.245 (x) / 0.70 (y) = the lab's 1600x900 view. Pixel: `px = (x+1)*800`, `py = (1-y)*450`. Off-screen values are allowed.
- **Camera space** (depth, offsets): decimetres, x right, y up, z forward from the eye. A screen point (x, y) at depth z is
  the camera point `(x*1.245*z, y*0.70*z, z)`.
- **Hilt** = screen point (hx, hy) at camera depth hz (dm).
- **Tip** = screen point (tx, ty); its depth is solved so the tip is the class blade length L from the hilt (far root of the
  ray/sphere intersection; closest approach when unreachable). Blade direction f = hilt -> tip.
- **Edge** (u): roll r (deg) about the blade from the key's lead direction. r = 0: the edge faces the tip's key-to-key
  motion (tip of the previous key -> tip of the next key, one-sided at the ends), made perpendicular to f; positive r rotates
  by `u cos r + (f x u) sin r` (same sign convention as the screen-line `sline roll`).
- **Time** t = swing time u (0..1 over `sw_dur`), strictly increasing (>= 0.005 apart), first key t > 0.005, last < 0.995;
  otherwise the stroke falls back to its key-arc / screen-line path.
- **Interpolation** between keys: hilt (hx, hy, hz) and tip (tx, ty) are Catmull-Rom over the key times in screen coords
  (collinear tip keys = exactly straight screen path; the ends extrapolate linearly); orientation = the two keys' edges
  carried onto the interpolated blade and slerped about it (shortest roll).
- **Easing** per segment (stored on the key that STARTS the segment): cubic Bezier time warp
  `e(s) = 3(1-s)^2 s ea + 3(1-s) s^2 eb + s^3`, s = segment fraction; `ea = eb = 0` means linear (same as 1/3, 2/3).
- **Wind-up** (u < t of key 1): smoothstep blend from the pose the swing started in (ready) to key 1.
- **Recovery** (u > t of the last key): quadratic blend to ready through a control point pulled toward the stroke's key-arc
  recovery key by `rk` (0 = straight back), same as the screen-line recovery.
- **Grip offset per weapon class** (one key set serves all weapons of a class): commanded grip `p = hilt - (ox, oy, oz)`;
  class picked from the 2H state: c0 one-handed, c1 heavy (2H kind 0), c2 polearm (2H kind 1). c0 = the screen-line lab fit
  (L 8, offset 0.10 0 0.80); c1 L 10, c2 L 14 are uncalibrated placeholders.

## Tables (fp_tables / live tables, no rebuild)
| table | rows | columns |
|---|---|---|
| `kf` | 0..15 = stroke + 4 x class | 54 = 6 keys x 9: `k<i>t k<i>hx k<i>hy k<i>hz k<i>tx k<i>ty k<i>r k<i>ea k<i>eb` (i = 1..6) |
| `kfh` | 0..15 = stroke + 4 x class | `n rk lead`: n keys used (< 2 = off), rk recovery pull, lead = E1 edge-lead weight on top of the authored roll (1 = shipped lead, 0 = authored edge only) |
| `kfc` | 0..3 = class | `L ox oy oz` |
| `kfmask` | scalar | bit r = kf row r is a keyframe stroke (fp_vm key `kfmask`, 0..65535) |

Weapon classes (per-class rows, fix-build 2026-10-11; same index as `kfc`): class 0 = 1H (rows 0-3, the sword rows, unchanged),
class 1 = 2H heavy/light (Buster Sword, Fragment Axe, katana 2H-light; rows 4-7), class 2 = 2H polearm (Naginata, polearms,
Crab Maul; rows 8-11), class 3 = 1H hacker/cleaver (weapon skill category 4, not 2H; rows 12-15). Row = stroke + 4 x class; e.g. heavy stroke 0 = `kf.4`, `kfh.4`, kfmask bit 4 (16).


Rows are NUMBERS, so address them as `<row>.<col>` (a bare number after the table is a FLAT index: `kf.2 = ...` writes
from element 2 of row 0). File example (stroke 2, 5 keys):
```
kf.2.k1t = 0.28 0.45 0.40 3.6 -0.05 1.2 -14 0 0   0.40 0.38 -0.20 4.2 -0.04 0.62 0 0 0   0.52 ...   (all 54 or fewer)
kfh.2.n = 5 0.6 1
kfmask = 4
```
Single values: `kf.2.k3tx = 0.05`; game `fp_vm set kfmask 4`, `fp_vm set t.kf.2.k3tx 0.05`; lab `--set kfmask=4`,
`--tables <file>`. A kf stroke wins over the screen-line / key-arc path of the same stroke; the screen-line `inl` weight
and recovery-edge (kfp-stroke-recedge) still apply when that stroke's `slmask` bit is also set (used to match PT17-v2 s0).
Recordings carry the variant (`# set -1 t.kf.<i>` lines), so the lab replays a filmed kf take with no extra file.

## Lab
Binaries: `components/KenshiFP/animlab/kf/build-kf.sh` -> `/root/animlab-build/kfpvm_kf` (replay adapter) and
`kfpvm_kfpath` (`kfpvm_kfpath.c`: commanded path, no IK, ms). Tools in `components/KenshiFP/animlab/kf/`: `kfstroke.py`
(fit / make / path), `kfcheck.py` (every swing check over the sword pool, same objective as stroke-fix obj.py), `kfwhy.py`.
`kfpreview.py <tables file> [--mp4] [--pool] [--label=X]` (kf-lab): replays one pool recording with the set (~1.5 s),
judges its stroke swing with every lab swing check (path dev/late/angle, SR38 end band, span/centre/fast, SR39/40 travel,
sweep + wind-up exit, SR41 return edge away, arc edge, wrist, blade, stroke length, churn, inline, framing), writes
`strip.png` (zoom 0, tip path + 10% band + crosshair per tile) + `checks.txt`, `--mp4` a full + 1/2 speed clip (NVENC),
`--pool` the whole pool (kfcheck); prints `RESULT KFPREVIEW-s<N> PASS|FAIL ...` (default out
`C:\KenshiTestRuns\kf-lab\preview\<name>\`). `kfstroke.py preview` calls it. Agreement (one source: the adapter compiles
the plugin's own kfp_viewmodel.inc + this patch): `kfagree.sh <game kf take rec>` replays a filmed kf take with the lab
built from that DLL's exact source and compares every arm joint / hand axis (agree-pose.sh), `RESULT KFAGREE`.
