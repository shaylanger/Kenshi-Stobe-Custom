#!/usr/bin/env python3
"""kfp-2h-ready.py <KenshiFP root | client dir>: READY-ONLY extra 2H class transform (heavy / polearm), like the block extra.

Why: heavy 2H weapons (Fragment Axe, Buster Sword) at rest (ready/walk): the Axe head sits above the top edge of the
screen. Tilting the whole 2H class transform (vm.tworH_*) brings the head into view but also rotates every swing: wrist
bend > 50 (SR10) arc_gate FAIL in game (takes 183/184, tables hv-g..hv-k). The ready pose needs its own offset that the
swing does not carry.
Change: g_vm_2hrr[kind] (deg: pitch, yaw, roll) / g_vm_2hdr[kind] (dm, camera numbers) are added to the 2H class
transform with a ready weight: 1 at rest; 0 while blocking (follows the state over twortau s, smoothstep) and during a
swing: it fades out over the wind-up (1 - smoothstep(0, tworua, swing u), so the stroke frames u >= tworua are not
rotated) and fades back in over twortau s after the swing ends (the swing ends ON the ready target, so no pop).
The wrist look-ahead evaluates the same weight at its future u. Defaults 0 = nothing shipped changes.
Live keys (fp_vm set / live tables vm.<key>): tworrH_x|y|z, twodrH_x|y|z (P = polearm), tworua (default 0.25),
twortau (default 0.35 s). Asserts its anchors; idempotent."""
import sys, os
root = sys.argv[1]
cdir = root if os.path.exists(os.path.join(root, 'kenshifp_client.c')) else os.path.join(root, 'client')
TAG = '/* kfp-2h-ready */'
p = os.path.join(cdir, 'kfp_viewmodel.inc')
s = open(p).read()
if TAG in s:
    print('kfp-2h-ready: already applied'); sys.exit(0)

R = [
 ('static float g_vm_2hbw;                                /* block blend 0..1 (follows the target state) */\n',
  'static float g_vm_2hbw;                                /* block blend 0..1 (follows the target state) */\n'
  'static Vec3  g_vm_2hrr[2], g_vm_2hdr[2];               ' + TAG + ' /* per kind: extra rotation deg / translation dm at READY only\n'
  '                                                        * (weight vm_2h_rdw: 0 while blocking and over the swing) */\n'
  'static float g_vm_2hrw = 1.0f;                         /* ready blend 0..1 (1 = not blocking, not swinging) */\n'
  'static float g_vm_2hrua = 0.25f, g_vm_2hrtau = 0.35f;  /* ready extra gone by swing u tworua; back in over twortau s */\n'),
 ('static VmPose vm_2h_xf(VmPose o)                       /* the 2H class transform of a melee pose (identity one-handed) */\n',
  'static float vm_2h_rdw(void)                           /* ready-only weight (kfp-2h-ready) */\n'
  '{\n'
  '    float r = g_vm_2hrw * g_vm_2hrw * (3.0f - 2.0f * g_vm_2hrw);\n'
  '    if (g_vm_swing) r = fminf(r, 1.0f - vm_sstep(0.0f, g_vm_2hrua, g_vm_swu));\n'
  '    return r;\n'
  '}\n'
  'static VmPose vm_2h_xf(VmPose o)                       /* the 2H class transform of a melee pose (identity one-handed) */\n'),
 ('    Vec3 r = vm_mul(vm_add(g_vm_2hr[k], vm_mul(g_vm_2hrb[k], b)), w * 0.01745329f);\n'
  '    o.p = vm_add(vm_add(g_vm_2hpv, vm_2h_rot(vm_sub(o.p, g_vm_2hpv), r)), vm_mul(vm_add(g_vm_2hd[k], vm_mul(g_vm_2hdb[k], b)), w));\n',
  '    float rr = vm_2h_rdw();\n'
  '    Vec3 r = vm_mul(vm_add(vm_add(g_vm_2hr[k], vm_mul(g_vm_2hrb[k], b)), vm_mul(g_vm_2hrr[k], rr)), w * 0.01745329f);\n'
  '    o.p = vm_add(vm_add(g_vm_2hpv, vm_2h_rot(vm_sub(o.p, g_vm_2hpv), r)),\n'
  '                 vm_mul(vm_add(vm_add(g_vm_2hd[k], vm_mul(g_vm_2hdb[k], b)), vm_mul(g_vm_2hdr[k], rr)), w));\n'),
 ('        g_vm_2hbw += (ti == VM_BLOCK ? 1.0f : -1.0f) * adt / fmaxf(g_vm_2htau, 0.01f); g_vm_2hbw = g_vm_2hbw < 0.0f ? 0.0f : g_vm_2hbw > 1.0f ? 1.0f : g_vm_2hbw;\n',
  '        g_vm_2hbw += (ti == VM_BLOCK ? 1.0f : -1.0f) * adt / fmaxf(g_vm_2htau, 0.01f); g_vm_2hbw = g_vm_2hbw < 0.0f ? 0.0f : g_vm_2hbw > 1.0f ? 1.0f : g_vm_2hbw;\n'
  '        g_vm_2hrw += (ti != VM_BLOCK && !g_vm_swing ? 1.0f : -1.0f) * adt / fmaxf(g_vm_2hrtau, 0.01f);   /* kfp-2h-ready */\n'
  '        g_vm_2hrw = g_vm_2hrw < 0.0f ? 0.0f : g_vm_2hrw > 1.0f ? 1.0f : g_vm_2hrw;\n'),
 ('                VmPose o = vm_2h_xf(c); if (sl != 0.0f) o.p = vm_add(o.p, vm_mul(o.f, sl));\n',
  '                float su_ = g_vm_swu; int ss_ = g_vm_swing; g_vm_swu = u; g_vm_swing = sw;   /* ready weight at the future u */\n'
  '                VmPose o = vm_2h_xf(c); g_vm_swu = su_; g_vm_swing = ss_; if (sl != 0.0f) o.p = vm_add(o.p, vm_mul(o.f, sl));\n'),
 ('    else if (!strncmp(k, "tworb", 5) && (k[5] == \'H\' || k[5] == \'P\') && k[6] == \'_\' && k[7] && !k[8]) fp = vm_vec_field(&g_vm_2hrb[k[5] == \'P\'], k[7]);\n',
  '    else if (!strncmp(k, "tworb", 5) && (k[5] == \'H\' || k[5] == \'P\') && k[6] == \'_\' && k[7] && !k[8]) fp = vm_vec_field(&g_vm_2hrb[k[5] == \'P\'], k[7]);\n'
  '    else if (!strncmp(k, "twodr", 5) && (k[5] == \'H\' || k[5] == \'P\') && k[6] == \'_\' && k[7] && !k[8]) fp = vm_vec_field(&g_vm_2hdr[k[5] == \'P\'], k[7]);\n'
  '    else if (!strncmp(k, "tworr", 5) && (k[5] == \'H\' || k[5] == \'P\') && k[6] == \'_\' && k[7] && !k[8]) fp = vm_vec_field(&g_vm_2hrr[k[5] == \'P\'], k[7]);\n'
  '    else if (!strcmp(k, "tworua"))  { if (x > 0.01f && x <= 1.0f) g_vm_2hrua = x; return 1; }\n'
  '    else if (!strcmp(k, "twortau")) { if (x > 0.01f && x <= 5.0f) g_vm_2hrtau = x; return 1; }\n'),
]
for a, b in R:
    n = s.count(a)
    assert n == 1, 'kfp-2h-ready: anchor found %d times: %s' % (n, a[:70])
    s = s.replace(a, b)
open(p, 'w').write(s)
print('kfp-2h-ready: applied')
