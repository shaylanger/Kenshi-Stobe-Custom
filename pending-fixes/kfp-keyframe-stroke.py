#!/usr/bin/env python3
"""kfp-keyframe-stroke.py <KenshiFP root | client dir>: keyframe sword strokes ("keyframe player", Shay 2026-10-11 19:05).

Why: authoring a stroke through the key-arc tables (5 grip/blade/edge keys, Catmull-Rom in 3D camera space) or the
screen-line row (pivot sphere, 19 coupled columns) needs an optimizer: the screen path is only indirectly controlled.
A keyframe stroke is written directly in SCREEN terms: 2-6 keys of the weapon (hilt screen point + depth, tip screen
point, edge roll, time) and per-segment easing; KenshiFP interpolates and the existing arm IK (vm_apply: elbow pick,
wrist roll, E1 lead, inline) places the hands on the grip. Collinear tip keys give an exactly straight screen path.

What (opt-in per stroke: bit n of fp_vm key `kfmask`, default 0 = nothing shipped changes; a kf stroke wins over the
screen-line / key-arc path of the same stroke, everything downstream of vm_swing_at is unchanged):
  - key k (table `kf`, row = stroke 0..3, cols k<i>t k<i>hx k<i>hy k<i>hz k<i>tx k<i>ty k<i>r k<i>ea k<i>eb, i = 1..6):
    t = swing time u (0..1, increasing), hilt = screen point (hx, hy) (-1..1, y up, zoom-0 FP view, tan half-angles
    1.245 / 0.70 = the lab's 1600x900 view) at camera depth hz (dm); tip = screen point (tx, ty), its depth puts it at
    the class blade length L from the hilt (far root; closest approach when unreachable); r = edge roll (deg about the
    blade, 0 = edge leads along the tip's key-to-key motion, same sign as sline roll); ea eb = cubic Bezier time warp of
    the segment that STARTS at this key, e(s) = 3(1-s)^2 s ea + 3(1-s) s^2 eb + s^3 (0 0 = linear)
  - between keys: hilt (hx hy hz) and tip (tx ty) Catmull-Rom over the key times (screen coords, so collinear tip keys
    stay on their line; ends extrapolate linearly), blade f = hilt -> tip, edge = the two keys' edges carried onto f and
    slerped about f (shortest roll); grip p = hilt - class offset (table `kfc`, rows c0 1H / c1 heavy / c2 polearm,
    cols `L ox oy oz` camera numbers: c0 = the screen-line fit L 8, sltoff 0.10 0 0.80)
  - before key 1: smoothstep blend start pose -> key 1 (wind-up ends ON key 1); after the last key: quadratic blend to
    ready through a control point pulled toward the stroke's key-arc recovery key by rk (as the screen-line recovery)
  - table `kfh` rows 0..3 cols `n rk lead`: n = keys used (< 2 = off), rk, lead = weight of the E1 edge lead on top of
    the authored roll (1 = shipped lead, 0 = the authored edge alone)
Live tables (no rebuild): `kf.0 = <54 values>`, `kf.0.k3tx = 0.1`, `kfh.0 = 5 0.6 1`, `vm.kfmask = 1`
(`fp_vm set kfmask 1`, `fp_vm set t.kf.0.k3tx 0.1`). Lab: kfpvm_replay --tables / --set, components/KenshiFP/animlab/
kfpvm_kfpath.c (path sampler) and kf/kfpreview.py (strip + every swing check). Independent of kfp-stroke-line (applies
before or after it; its anchors are untouched). Asserts its anchors; idempotent."""
import sys, os
root = sys.argv[1]
cdir = root if os.path.exists(os.path.join(root, 'kenshifp_client.c')) else os.path.join(root, 'client')
TAG = '/* kfp-keyframe-stroke */'
NK, NC = 6, 9
COLS = ' '.join('k%d%s' % (i + 1, c) for i in range(NK) for c in ('t', 'hx', 'hy', 'hz', 'tx', 'ty', 'r', 'ea', 'eb'))

# compiled defaults (inactive while kfmask = 0): stroke 0 = PT17-v2 stroke 0 fitted as keys, stroke 2 = E6 overhead
# keyframe candidate (keyframe-player 2026-10-11); 1, 3 empty (n = 0)
KF = {
    0: None,
    2: None,
}
KFH = {0: '0.0f, 0.6f, 1.0f', 1: '0.0f, 0.6f, 1.0f', 2: '0.0f, 0.6f, 1.0f', 3: '0.0f, 0.6f, 1.0f'}


def row(vals):
    vals = list(vals or []) + [0.0] * (NK * NC - len(vals or []))
    return ', '.join('%.4ff' % v for v in vals)


CODE = r'''
''' + TAG + r'''
/* Keyframe strokes (keyframe player, Shay 2026-10-11): stroke n with bit n of g_vm_kfmask and kfh n >= 2 = keys of the
 * weapon in screen space (hilt screen point + depth, tip screen point, edge roll, time, per-segment easing); hilt + tip
 * Catmull-Rom on the screen, blade = hilt -> tip, edge slerped about the blade, grip = hilt - class offset. Live tables
 * kf (rows 0..3, cols k<i>t hx hy hz tx ty r ea eb), kfh (n rk lead), kfc (rows c0 1H, c1 heavy, c2 polearm: L ox oy oz),
 * fp_vm key kfmask. Docs: pending-fixes/kfp-keyframe-stroke.py, components/KenshiFP/docs/LIVE_TABLES.md. */
#define VM_KFN 6
#define VM_KFC 9
enum { KF_T, KF_HX, KF_HY, KF_HZ, KF_TX, KF_TY, KF_R, KF_EA, KF_EB };
static float g_vm_kf[VM_NSTROKE][VM_KFN * VM_KFC] = {
    { @KF0@ },
    { @KF1@ },
    { @KF2@ },
    { @KF3@ } };
static float g_vm_kfh[VM_NSTROKE][3] = { { @KFH0@ }, { @KFH1@ }, { @KFH2@ }, { @KFH3@ } };   /* n rk lead */
static float g_vm_kfc[3][4] = { { 8.0f, 0.10f, 0.0f, 0.80f }, { 10.0f, 0.10f, 0.0f, 0.80f }, { 14.0f, 0.10f, 0.0f, 0.80f } };   /* L ox oy oz (c1/c2 uncalibrated) */
static float g_vm_kfmask = 0.0f;   /* bit n = stroke n is a keyframe stroke */
static const float g_vm_kftx = 1.245f, g_vm_kfty = 0.70f;   /* FP view tan half-angles (zoom 0, 16:9, vertical FOV 70) */
static int vm_kf_n(void)
{
    if (g_vm_stroke < 0 || g_vm_stroke >= VM_NSTROKE || !(((int)g_vm_kfmask >> g_vm_stroke) & 1)) return 0;
    int n = (int)g_vm_kfh[g_vm_stroke][0]; if (n < 2) return 0; if (n > VM_KFN) n = VM_KFN;
    const float *k = g_vm_kf[g_vm_stroke];
    if (k[KF_T] < 0.005f || k[(n - 1) * VM_KFC + KF_T] > 0.995f) return 0;
    for (int i = 1; i < n; i++) if (k[i * VM_KFC + KF_T] < k[(i - 1) * VM_KFC + KF_T] + 0.005f) return 0;   /* times must increase */
    return n;
}
static float vm_kf_leadw(void) { return vm_kf_n() ? fmaxf(0.0f, fminf(1.0f, g_vm_kfh[g_vm_stroke][2])) : 1.0f; }
static const float *vm_kf_cls(void) { return g_vm_kfc[g_vm_2h ? (g_vm_2hk ? 2 : 1) : 0]; }
static float vm_kf_ss(float x) { x = fmaxf(0.0f, fminf(1.0f, x)); return x * x * (3.0f - 2.0f * x); }
static float vm_kf_ease(float ea, float eb, float s)
{
    s = fmaxf(0.0f, fminf(1.0f, s)); if (ea == 0.0f && eb == 0.0f) return s;
    float a = 1.0f - s; return 3.0f * a * a * s * ea + 3.0f * a * s * s * eb + s * s * s;
}
static Vec3 vm_kf_hilt(float hx, float hy, float hz) { return vm_v(hx * g_vm_kftx * hz, hy * g_vm_kfty * hz, hz); }
static Vec3 vm_kf_tip(Vec3 H, float tx, float ty, float L)
{
    Vec3 r = vm_norm(vm_v(tx * g_vm_kftx, ty * g_vm_kfty, 1.0f));
    float b = vm_dot(r, H), q = b * b - (vm_dot(H, H) - L * L);
    return vm_mul(r, fmaxf(q > 0.0f ? b + sqrtf(q) : b, 0.5f));
}
/* scalar Catmull-Rom (non-uniform times), ends extrapolated linearly */
static float vm_kf_cr(const float *k, int n, int col, int i, float tq)
{
    float t1 = k[i * VM_KFC], t2 = k[(i + 1) * VM_KFC], p1 = k[i * VM_KFC + col], p2 = k[(i + 1) * VM_KFC + col];
    float t0, p0, t3, p3, d = t2 - t1; if (d < 1e-4f) return p1;
    if (i > 0) { t0 = k[(i - 1) * VM_KFC]; p0 = k[(i - 1) * VM_KFC + col]; } else { t0 = t1 - d; p0 = 2.0f * p1 - p2; }
    if (i + 2 < n) { t3 = k[(i + 2) * VM_KFC]; p3 = k[(i + 2) * VM_KFC + col]; } else { t3 = t2 + d; p3 = 2.0f * p2 - p1; }
    float s = (tq - t1) / d, m1 = (p2 - p0) * d / fmaxf(t2 - t0, 1e-4f), m2 = (p3 - p1) * d / fmaxf(t3 - t1, 1e-4f);
    float s2 = s * s, s3 = s2 * s;
    return (2*s3 - 3*s2 + 1) * p1 + (s3 - 2*s2 + s) * m1 + (-2*s3 + 3*s2) * p2 + (s3 - s2) * m2;
}
/* key pose j (hilt, tip, edge with roll about the blade) */
static void vm_kf_key(const float *k, int n, int j, float L, Vec3 *H, Vec3 *T, Vec3 *U)
{
    const float *c = k + j * VM_KFC;
    *H = vm_kf_hilt(c[KF_HX], c[KF_HY], c[KF_HZ]); *T = vm_kf_tip(*H, c[KF_TX], c[KF_TY], L);
    int a = j > 0 ? j - 1 : j, b = j + 1 < n ? j + 1 : j;
    const float *ca = k + a * VM_KFC, *cb = k + b * VM_KFC;
    Vec3 Ta = vm_kf_tip(vm_kf_hilt(ca[KF_HX], ca[KF_HY], ca[KF_HZ]), ca[KF_TX], ca[KF_TY], L);
    Vec3 Tb = vm_kf_tip(vm_kf_hilt(cb[KF_HX], cb[KF_HY], cb[KF_HZ]), cb[KF_TX], cb[KF_TY], L);
    Vec3 f = vm_norm(vm_sub(*T, *H)), dir = vm_sub(Tb, Ta), u = vm_sub(dir, vm_mul(f, vm_dot(dir, f)));
    if (vm_len(u) < 1e-5f) { u = vm_v(0.0f, 1.0f, 0.0f); u = vm_sub(u, vm_mul(f, vm_dot(u, f))); }
    u = vm_norm(u);
    if (c[KF_R] != 0.0f) { float r = c[KF_R] * 0.0174533f; u = vm_add(vm_mul(u, cosf(r)), vm_mul(vm_cross(f, u), sinf(r))); }
    *U = u;
}
static VmPose vm_kf_pose(int n, float uq)
{
    const float *k = g_vm_kf[g_vm_stroke], *cl = vm_kf_cls(); float L = cl[0];
    int i = 0; while (i < n - 2 && uq > k[(i + 1) * VM_KFC]) i++;
    float t1 = k[i * VM_KFC], t2 = k[(i + 1) * VM_KFC];
    float e = vm_kf_ease(k[i * VM_KFC + KF_EA], k[i * VM_KFC + KF_EB], (uq - t1) / fmaxf(t2 - t1, 1e-4f)), tq = t1 + e * (t2 - t1);
    Vec3 H = vm_kf_hilt(vm_kf_cr(k, n, KF_HX, i, tq), vm_kf_cr(k, n, KF_HY, i, tq), vm_kf_cr(k, n, KF_HZ, i, tq));
    Vec3 T = vm_kf_tip(H, vm_kf_cr(k, n, KF_TX, i, tq), vm_kf_cr(k, n, KF_TY, i, tq), L), f = vm_norm(vm_sub(T, H));
    Vec3 Ha, Ta, Ua, Hb, Tb, Ub; vm_kf_key(k, n, i, L, &Ha, &Ta, &Ua); vm_kf_key(k, n, i + 1, L, &Hb, &Tb, &Ub);
    Vec3 a = vm_sub(Ua, vm_mul(f, vm_dot(Ua, f))), b = vm_sub(Ub, vm_mul(f, vm_dot(Ub, f)));
    if (vm_len(a) < 1e-5f) a = b; if (vm_len(b) < 1e-5f) b = a;
    a = vm_norm(a); b = vm_norm(b);
    float th = atan2f(vm_dot(f, vm_cross(a, b)), vm_dot(a, b)) * e;   /* edge slerp about the blade */
    Vec3 u = vm_add(vm_mul(a, cosf(th)), vm_mul(vm_cross(f, a), sinf(th)));
    VmPose r = { vm_sub(H, vm_v(cl[1], cl[2], cl[3])), f, u };
    return vm_pose_norm(r);
}
static VmPose vm_kf_swing_at(VmPose start, VmPose end, float u)
{
    int n = vm_kf_n();
    if (!n) return vm_swing_at(start, end, u);
    if (u <= 0.0f) return vm_pose_norm(start);
    if (u >= 1.0f) return vm_pose_norm(end);
    const float *k = g_vm_kf[g_vm_stroke]; float t0 = k[KF_T], tl = k[(n - 1) * VM_KFC + KF_T];
    if (u < t0) return vm_pose_lerp(start, vm_kf_pose(n, t0), vm_kf_ss(u / t0));
    if (u <= tl) return vm_kf_pose(n, u);
    VmPose a = vm_kf_pose(n, tl), kk = vm_pose_norm(g_vm_swkp[VM_SWK - 1]), m, r;
    float w = vm_kf_ss((u - tl) / (1.0f - tl)), rk = fmaxf(0.0f, fminf(1.0f, g_vm_kfh[g_vm_stroke][1]));
    m.p = vm_lerp(vm_lerp(a.p, end.p, 0.5f), kk.p, rk); m.f = vm_lerp(vm_lerp(a.f, end.f, 0.5f), kk.f, rk); m.u = vm_lerp(vm_lerp(a.u, end.u, 0.5f), kk.u, rk);
    float w0 = (1.0f - w) * (1.0f - w), w1 = 2.0f * (1.0f - w) * w, w2 = w * w;
    r.p = vm_add(vm_add(vm_mul(a.p, w0), vm_mul(m.p, w1)), vm_mul(end.p, w2));
    r.f = vm_add(vm_add(vm_mul(a.f, w0), vm_mul(m.f, w1)), vm_mul(end.f, w2));
    r.u = vm_add(vm_add(vm_mul(a.u, w0), vm_mul(m.u, w1)), vm_mul(end.u, w2));
    return vm_pose_norm(r);
}
#define vm_swing_at(s_, e_, u_) vm_kf_swing_at(s_, e_, u_)   /* every later caller (E1 lead, swing apply) goes through the kf dispatch */
'''


def edit(name, pairs):
    p = os.path.join(cdir, name)
    s = open(p).read()
    if TAG in s:
        print('kfp-keyframe-stroke: %s already applied' % name); return
    for old, new in pairs:
        assert s.count(old) == 1, 'kfp-keyframe-stroke: anchor in %s: %r' % (name, old[:70])
        s = s.replace(old, new)
    open(p, 'w').write(s)


code = CODE
for i in range(4):
    code = code.replace('@KF%d@' % i, row(KF.get(i))).replace('@KFH%d@' % i, KFH[i])

LEAD = '        w = vm_sstep(w0_, w0_ + g_vm_swl_in, u) * (1.0f - vm_sstep(g_vm_swl_se + 0.06f, g_vm_swl_se + 0.06f + g_vm_swl_out, u));\n'
edit('kfp_viewmodel.inc', [
    ('\n/* E1: edge leads the arc.', code + '\n/* E1: edge leads the arc.'),
    (LEAD, LEAD + '        w *= vm_kf_leadw();   /* kfp-keyframe-stroke: kfh lead weight (1 = shipped E1 lead) */\n'),
    ('    else if (!strcmp(k, "strokes")) {',
     '    else if (!strcmp(k, "kfmask")) { g_vm_kfmask = fmaxf(0.0f, fminf(15.0f, floorf(x))); return 1; }   ' + TAG + '\n'
     '    else if (!strcmp(k, "strokes")) {'),
])
edit('kfp_tables.inc', [
    ('    KT_SCAL("elbkeep", g_vm_elb_keep), KT_SCAL("elbtau", g_vm_elb_tau),\n',
     '    KT_SCAL("elbkeep", g_vm_elb_keep), KT_SCAL("elbtau", g_vm_elb_tau),\n'
     '    { "kf", (float *)g_vm_kf, KT_NF(g_vm_kf), VM_KFN * VM_KFC, "' + COLS + '", KT_RNUM, NULL },   ' + TAG + '\n'
     '    { "kfh", (float *)g_vm_kfh, KT_NF(g_vm_kfh), 3, "n rk lead", KT_RNUM, NULL },\n'
     '    { "kfc", (float *)g_vm_kfc, KT_NF(g_vm_kfc), 4, "L ox oy oz", KT_RNUM, NULL }, KT_SCAL("kfmask", g_vm_kfmask),\n'),
])
print('kfp-keyframe-stroke: applied')
