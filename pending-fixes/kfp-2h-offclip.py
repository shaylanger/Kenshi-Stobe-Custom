#!/usr/bin/env python3
"""kfp-2h-offclip.py <KenshiFP root | client dir>: PT30, the two-handed off-hand forearm never crosses the near clip in view.
Why: PT30 sword (Gate 6, PT17-W "cut=0") regressed 4/4 runs on both rigs (B17B98D5, CAA044C1, 08AAF9BF: sword cut=100-158,
all [4] = OFF-HAND forearm elbow z ~2.3 -> wrist z ~4.2 crossing the 3 dm near clip inside the screen, block pose + once in
ready; Shay SR29 "no clipped or hollow limbs"). Lab bisect (pt30-fix 2026-10-11, replay of corpus pt30-blockcut-CAA044C1):
live base cut 0, base + kfp-2h-light cut 156, all pending minus kfp-2h-light cut 0 => kfp-2h-light (katana now two-handed,
off hand on the handle) is the breaker. The weapon arm has the PT17 tube rule (vm_elbow / vm_elb_pass: the arm surface stays
in front of the near plane until the arm is off screen); the off arm only had the pole IK, so the handle grip pulled its
elbow behind the plane with the forearm crossing it on screen.
What: vm_elbow_off(): while the 2H off-hand grip is active (melee, g_vm_2hw > 0) the natural pole-IK elbow of the off arm
is computed exactly as vm_ik does (same pole, stretch, clamps); when it passes vm_elb_pass nothing changes (weight 0: every
pose that was clean stays bit-identical, accepted strokes untouched); when it fails, the passing elbow direction nearest to
it (grid over the sphere, elbow left of / below the wrist, then a bisection on the arc natural -> winner = the boundary,
continuous with the natural elbow at the switch) is handed to vm_ik as the elbow target with the zoom weight (as the weapon
arm). Live key `fp_vm set oelb 0|1` (default 1). Independent of kfp-2h-light (also covers heavy/polearm 2H).
Asserts its anchors; idempotent."""
import os, sys
root = sys.argv[1]
cdir = root if os.path.exists(os.path.join(root, 'kenshifp_client.c')) else os.path.join(root, 'client')
TAG = '/* kfp-2h-offclip */'
p = os.path.join(cdir, 'kfp_viewmodel.inc')
s = open(p).read()
if TAG in s:
    print('kfp-2h-offclip: already applied'); sys.exit(0)
FN = TAG + r'''
static int g_vm_oelb_on = 1; static unsigned long g_vm_oelb_n;   /* off-arm near-clip elbow on / frames corrected */
static float vm_elbow_off(void *ua, void *fa, void *ha, Vec3 Po, Vec3 pole, float w, Vec3 *Et)
{
    if (!g_vm_oelb_on || g_vm_class != 0 || g_vm_2hw <= 0.0f) return 0.0f;
    const Vec3 *ps = g_oldnode_getdpos(ua), *pe = g_oldnode_getdpos(fa), *ph = g_oldnode_getdpos(ha);
    if (!readable((void *)ps, 12) || !readable((void *)pe, 12) || !readable((void *)ph, 12)) return 0.0f;
    Vec3 S = *ps, E = *pe, H = *ph;
    float L1 = vm_l1(ua, ps, pe), L2 = vm_len(vm_sub(H, E));
    if (L1 < 1e-4f || L2 < 1e-4f || g_vm_scale < 1e-6f) return 0.0f;
    float L1n = L1 * g_vm_scale, L2c = L2 * g_vm_scale;
    /* the natural elbow = vm_ik's pole solution (skeleton space) */
    Vec3 d = vm_sub(Po, S); float D = vm_len(d);
    if (g_vm_stretch > 1.0f && g_oldnode_setpos && w > 0.001f) {
        float need = D / 0.995f - L2;
        if (need > L1) { float st = fminf(need / L1, g_vm_stretch); st = 1.0f + (st - 1.0f) * fminf(w, 1.0f); L1 *= st; }
    }
    Vec3 n = D > 1e-5f ? vm_mul(d, 1.0f / D) : vm_norm(vm_sub(H, S));
    float dmin = fabsf(L1 - L2) + 0.02f * (L1 + L2), dmax = (L1 + L2) * 0.995f;
    if (D < dmin) D = dmin; if (D > dmax) D = dmax;
    float a = (L1*L1 - L2*L2 + D*D) / (2.0f * D), h = sqrtf(fmaxf(0.0f, L1*L1 - a*a));
    Vec3 pp = vm_sub(pole, vm_mul(n, vm_dot(pole, n)));
    if (vm_len(pp) < 1e-4f) { Vec3 ce = vm_sub(E, S); pp = vm_sub(ce, vm_mul(n, vm_dot(ce, n))); }
    pp = vm_norm(pp);
    Vec3 E2 = vm_add(S, vm_add(vm_mul(n, a), vm_mul(pp, h)));
    Vec3 W = vm_s2c_pos(Po), Sc = vm_s2c_pos(S), d0 = vm_norm(vm_sub(vm_s2c_pos(E2), W));
    if (vm_elb_pass(W, vm_add(W, vm_mul(d0, L2c)), Sc, L1n)) return 0.0f;   /* clean: the pole IK as before */
    Vec3 best = d0; float bd = -99.0f;
    for (int i = 0; i < 24; i++) for (int j = 0; j < 12; j++) {   /* elbow left of / below the wrist, not ahead (mirror of vm_elbow) */
        float az = 6.2831853f * i / 24.0f, el = -1.45f + 2.9f * j / 11.0f;
        Vec3 e = vm_v(cosf(el) * cosf(az), sinf(el), cosf(el) * sinf(az));
        if (e.x > 0.25f || e.z > 0.35f) continue;
        float dd = vm_dot(e, d0);
        if (dd > bd && vm_elb_pass(W, vm_add(W, vm_mul(e, L2c)), Sc, L1n)) { bd = dd; best = e; }
    }
    if (bd <= -99.0f) return 0.0f;
    {   float lo = 0.0f, hi = 1.0f;   /* boundary on the arc d0 -> best: continuous with the natural elbow */
        for (int k = 0; k < 14; k++) { float mid = 0.5f * (lo + hi); Vec3 e = vm_norm(vm_lerp(d0, best, mid));
            if (vm_elb_pass(W, vm_add(W, vm_mul(e, L2c)), Sc, L1n)) hi = mid; else lo = mid; }
        best = vm_norm(vm_lerp(d0, best, hi)); }
    g_vm_oelb_n++;
    float wz = g_vm_zfade ? 1.0f : 1.0f - g_view.applied / g_vm_elb_zoom; if (wz < 0) wz = 0; if (wz > 1) wz = 1;
    *Et = vm_add(Po, vm_w2s_dir(vm_c2w_dir(vm_mul(best, L2c))));
    return wz;
}
static float vm_elev_of(Vec3 c)'''
for old, new in [
    ('static float vm_elbow(void *ua, void *fa, void *ha, Vec3 Ph, Vec3 *Et);\n',
     'static float vm_elbow(void *ua, void *fa, void *ha, Vec3 Ph, Vec3 *Et);\n'
     'static float vm_elbow_off(void *ua, void *fa, void *ha, Vec3 Po, Vec3 pole, float w, Vec3 *Et);   ' + TAG + '\n'),
    ('static float vm_elev_of(Vec3 c)', FN),
    ('    if (!vm_ik(oh, b[oh][0], b[oh][1], b[oh][2], Po, Qo, keep, g_vm_tpole[oh], we, NULL, 0.0f)) g_vm_ikfail++;',
     '    {   Vec3 Eo; float eo = vm_elbow_off(b[oh][0], b[oh][1], b[oh][2], Po, g_vm_tpole[oh], we, &Eo);   ' + TAG + '\n'
     '        if (!vm_ik(oh, b[oh][0], b[oh][1], b[oh][2], Po, Qo, keep, g_vm_tpole[oh], we, eo > 0.001f ? &Eo : NULL, eo)) g_vm_ikfail++; }'),
    ('    else if (!strcmp(k, "nearclip")) {',
     '    else if (!strcmp(k, "oelb")) { g_vm_oelb_on = x > 0.5f; return 1; }   ' + TAG + '\n    else if (!strcmp(k, "nearclip")) {'),
]:
    assert s.count(old) == 1, 'kfp-2h-offclip: anchor %r' % old[:60]
    s = s.replace(old, new)
open(p, 'w').write(s)
print('kfp-2h-offclip: applied')
