#!/usr/bin/env python3
"""kfp-stroke-recedge.py <KenshiFP root | client dir>: screen-line strokes turn the blade edge away IMMEDIATELY in the return.

Why (Shay 2026-10-11, PT17-v2 review, SR41 accepted the straight strokes otherwise): in the rising stroke's recovery, as
soon as the cut ends and the arm returns to rest at the centre, the blade must rotate to face away from the player
immediately; the old key-arc rising stroke did that, the screen-line one keeps the edge facing the swing (toward the
camera, edge z -0.8 in the game rec sjudge-pt17v2-b pt17v2s3a) through the whole return and only turns at rest.
Cause (lab, 2026-10-11): in the return the visible blade roll is the wfix straight-wrist roll (+ S1 elbow pick), not the
commanded edge (the commanded edge is already the ready edge from the recovery start, a commanded-edge blend changed
nothing measured); the straight-wrist roll only reaches its rest value once the arm is back at rest. An S2 elbow re-pick
at the cut end flipped the weapon 180 deg in one frame; raising the E1 lead weight into the return hit the e1cap wrap.
What: the wfix roll offset of the settled ready pose is remembered (relative to the commanded orientation); in the
return of a screen-line stroke with table `slrec` (rows s0..s3, cols `rw r0 r1`) the applied roll offset blends from the
straight-wrist roll to that remembered rest offset with weight rw, ramping in over swing u r0..r1 (smoothstep; 0 = ub..ub+.06), and stays
there to the end of the swing (the rest pose then has the same roll: no release snap). The jerk limiter runs after it.
rw = 0 = old behaviour. Default: stroke 3 (rising) only, rw .5 (wrist bend <= 50: rw .7+ bends it 57-70), u .78-.92
(lab on pt17v2s3a: animlab path rec= .12-.13 vs .22/.20 base, spike/blade/arc PASS) (SR41: paths unchanged).
Live: `slrec.s3 = 0.5 0.78 0.92` in a tables file. Needs kfp-stroke-line. Asserts anchors; idempotent."""
import sys, os
root = sys.argv[1]
cdir = root if os.path.exists(os.path.join(root, 'kenshifp_client.c')) else os.path.join(root, 'client')
TAG = '/* kfp-stroke-recedge */'
S3 = os.environ.get('RECEDGE_S3', '0.5f, 0.78f, 0.92f')


def edit(name, pairs):
    p = os.path.join(cdir, name)
    s = open(p).read()
    if TAG in s:
        print('kfp-stroke-recedge: %s already applied' % name); return
    for old, new in pairs:
        assert s.count(old) == 1, 'kfp-stroke-recedge: anchor in %s: %r' % (name, old[:70])
        s = s.replace(old, new)
    open(p, 'w').write(s)


edit('kfp_viewmodel.inc', [
    ('static float g_vm_slmask = ',
     'static float g_vm_slrec[VM_NSTROKE][3] = { { 0.0f, 0.0f, 0.0f }, { 0.0f, 0.0f, 0.0f }, { 0.0f, 0.0f, 0.0f }, { ' + S3 + ' } };   ' + TAG +
     ' /* return: weight rw of the rest roll, ramp over u r0..r1 (0 = ub..ub+.06); rw 0 = straight-wrist roll */\n'
     'static float g_vm_slrr; static int g_vm_slrr_ok;   ' + TAG + ' /* wfix roll offset of the settled ready pose */\n'
     'static float g_vm_slmask = '),
    ('            if (g_vm_wrl > 0.0f) {   /* roll jerk limit',
     '            {   float pw_ = pst; while (pw_ > 3.14159265f) pw_ -= 6.2831853f; while (pw_ < -3.14159265f) pw_ += 6.2831853f;   ' + TAG + '\n'
     '                if (!g_vm_swing && g_vm_ti == VM_READY) { g_vm_slrr = pw_; g_vm_slrr_ok = 1; }   /* remember the rest roll */\n'
     '                else if (g_vm_swing && g_vm_slrr_ok && vm_sl_on() && g_vm_slrec[g_vm_stroke][0] > 0.0f) {\n'
     '                    const float *c_ = g_vm_sln[g_vm_stroke];   /* same ua/ub as vm_swing_at */\n'
     '                    float ua_ = c_[SL_UA] > 0.0f ? c_[SL_UA] : g_vm_swk_u[1], ub_ = c_[SL_UB] > ua_ + 0.05f ? fminf(c_[SL_UB], 0.97f) : g_vm_swk_u[5];\n'
     '                    if (ub_ <= ua_ + 0.05f) ub_ = fminf(0.97f, ua_ + 0.3f);\n'
     '                    float wr_ = fminf(1.0f, g_vm_slrec[g_vm_stroke][0]) * vm_sstep(g_vm_slrec[g_vm_stroke][1] > 0.0f ? g_vm_slrec[g_vm_stroke][1] : ub_, g_vm_slrec[g_vm_stroke][2] > g_vm_slrec[g_vm_stroke][1] ? g_vm_slrec[g_vm_stroke][2] : ub_ + 0.06f, g_vm_swu);\n'
     '                    if (wr_ > 0.0f) { float d_ = g_vm_slrr - pw_; while (d_ > 3.14159265f) d_ -= 6.2831853f; while (d_ < -3.14159265f) d_ += 6.2831853f;\n'
     '                        pst = pw_ + d_ * wr_; float h_ = 0.5f * pst;   /* return: blade turns to its rest roll right after the cut */\n'
     '                        Qp = quat_norm(quat_mul((Quat){ cosf(h_), f.x * sinf(h_), f.y * sinf(h_), f.z * sinf(h_) }, Qp0)); } } }\n'
     '            if (g_vm_wrl > 0.0f) {   /* roll jerk limit'),
])
edit('kfp_tables.inc', [
    ('    KT_VEC1("sltoff", g_vm_sltoff), KT_SCAL("slmask", g_vm_slmask),\n',
     '    KT_VEC1("sltoff", g_vm_sltoff), KT_SCAL("slmask", g_vm_slmask),\n'
     '    { "slrec", (float *)g_vm_slrec, KT_NF(g_vm_slrec), 3, "rw r0 r1", KT_RSL, NULL },   ' + TAG + '\n'),
])
print('kfp-stroke-recedge: applied')
