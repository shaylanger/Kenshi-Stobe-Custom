#!/usr/bin/env python3
"""Lab game model (e6-climb4, 2026-10-10; Misses row "weapon hand 0.24 dm hand-frame offset"): the game renders the weapon
hand (wrist, elbow follows, grip with it) a CONSTANT vector off where the faithful replay puts it, constant in the HAND
frame (hand bone X/Y/Z): (0.23, 0.00, -0.07) dm, the same on every frame/state/stroke/build measured (comb2-e6r7 2E66CB37,
op-b7 e6r7 89FE2B1C, comb2 q-sword-z0-a draw+ready: p50 deviation 0.000-0.004, p90 0.01-0.035 dm; in camera frame it
swings by 0.1-0.3 dm, which is why the old maintainer note saw "x flips with the state"). Shoulders, the commanded pose,
the off-hand and the rendered wrist->grip vector all match the game exactly, so the game's weapon-hand IK target is
Ph = tp - Qh*(lp*sc) + Qh*delta. Modelled IN the solver (wrist pick Ph0 and the final Ph), so the elbow pick, the roll
refinement and the stretch see it like the game does.
Key `hoff` (lab only): --set hoffx=/hoffy=/hoffz= (sword) hoffrx=/hoffry=/hoffrz= (crossbow), dm, hand frame, default $AL_HOFF ("x,y,z") or 0.19,0.02,-0.10 for the sword, $AL_HOFFR or 0,0,0 for the crossbow (OFF: comb2-vmrec-q-crossbow-z0 ready 0.14 -> 0.02 dm with 0.11,-0.01,-0.03 but aim 0.18 -> 0.25, so the crossbow offset is state-dependent, not modelled yet) (fit: residual wrist offset 0.00 dm on all sword recs; raw replay gap (0.23,0.00,-0.07) shrinks less than 1:1 because the elbow/stretch react);
--set hoffx=0 hoffz=0 = the old lab. build.sh applies it to every replay build (skip with --no-hoff).
Usage: hand-offset.py <client dir>"""
import sys, os
p = os.path.join(sys.argv[1], 'kfp_viewmodel.inc'); s = open(p).read()
if 'g_al_hoff' in s: print('hand-offset already applied'); sys.exit(0)
x, y, z = (os.environ.get('AL_HOFF', '0.19,0.02,-0.10').split(',') + ['0', '0'])[:3]
rx, ry, rz = (os.environ.get('AL_HOFFR', '0,0,0').split(',') + ['0', '0'])[:3]
a0 = 'Vec3 Ph0 = vm_sub(g_vm_tp, quat_rotvec(Qh0, vm_v(lp.x*sc.x, lp.y*sc.y, lp.z*sc.z)));'
a1 = '    Vec3 Ph = vm_sub(g_vm_tp, quat_rotvec(Qh, vm_v(lp.x*sc.x, lp.y*sc.y, lp.z*sc.z)));'
a2 = '    else if (!strcmp(k, "nearclip"))'
if s.count(a1) != 1: print('hand-offset: anchor missing in this source, skipped'); sys.exit(0)
if s.count(a0) > 1 or s.count(a2) != 1: print('hand-offset: old source (no nearclip key), skipped'); sys.exit(0)   # build-6c9516b / f41f862 regress builds
H = 'vm_v(lp.x*sc.x - g_al_hoff[g_vm_class ? 1 : 0].x / g_vm_scale, lp.y*sc.y - g_al_hoff[g_vm_class ? 1 : 0].y / g_vm_scale, lp.z*sc.z - g_al_hoff[g_vm_class ? 1 : 0].z / g_vm_scale)'
s = s.replace(a0, 'Vec3 Ph0 = vm_sub(g_vm_tp, quat_rotvec(Qh0, %s));' % H)
s = s.replace(a1, '    Vec3 Ph = vm_sub(g_vm_tp, quat_rotvec(Qh, %s));' % H)
s = s.replace(a2, ''.join('    else if (!strcmp(k, "hoff%s%s")) { g_al_hoff[%d].%s = x; return 1; }\n' % (c, a, ci, a)
                          for ci, c in ((0, ''), (1, 'r')) for a in 'xyz') + a2)
d = 'static Vec3 g_vm_s2w[3];'
assert s.count(d) == 1
s = s.replace(d, 'static Vec3 g_al_hoff[2] = { { %.4ff, %.4ff, %.4ff }, { %.4ff, %.4ff, %.4ff } };   /* lab game model: weapon-hand target '
              'offset [sword, crossbow], hand frame, dm */\n%s' % (float(x), float(y), float(z), float(rx), float(ry), float(rz), d))
open(p, 'w').write(s); print('hand-offset applied (%s,%s,%s / %s,%s,%s)' % (x, y, z, rx, ry, rz))
