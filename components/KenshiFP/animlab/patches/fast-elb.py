#!/usr/bin/env python3
"""Lab speed patch (gpu-lab 2026-10-11, Shay: CPU maxed by kfpvm replays): exact branch-and-bound in vm_elb_pref, the
elbow grid search that is ~80% of a replay (gprof). Results are BIT-IDENTICAL to the unpatched source (verified on the
corpus pools, animlab/fastcheck.sh); only work that cannot change the pick is skipped:
  (1) the look-ahead cost only lowers a candidate's score (g_vm_elb_lawm >= 0, term >= 0): a candidate whose score
      before it cannot beat its tier's best (strict >) is skipped before the 100-200 look-ahead dot products;
  (2) max over the next frame's candidates of min(dot, cc): visited in cc-descending order, stop once cc <= best
      (min(.,cc) <= cc) -- the max of the same value set, identical bits; same for the look-ahead DP levels.
build.sh applies it to every build (skip with --no-fast or AL_NO_FAST=1). Sources without the anchors are left unchanged.
Usage: fast-elb.py <client dir>"""
import sys, os
p = os.path.join(sys.argv[1], 'kfp_viewmodel.inc'); s = open(p).read()
if 'g_al_fast_ord' in s: print('fast-elb already applied'); sys.exit(0)
A1 = '''            if (lan) {   /* worst step on the best path: from the previous pick, then the predicted frames */
                float g = vm_dot(e, kp), gb = -2.0f;
                for (int b2 = 0; b2 < g_vm_la_c[0]; b2++) { float d = fminf(vm_dot(e, g_vm_la_e[0][b2]), g_vm_la_cc[0][b2]); if (d > gb) gb = d; }'''
B1 = '''            if (lan && g_vm_elb_lawm >= 0.0f) {   /* fast-elb (lab): the look-ahead term only lowers sc -> skip a loser */
                float kd_ = vm_dot(e, kp); int ti_ = kd_ >= tc[0] ? 0 : kd_ >= tc[1] ? 1 : kd_ >= tc[2] ? 2 : 3;
                if (sc <= tb[ti_] && (!eok || sc <= tbo[ti_])) continue;
            }
            if (lan) {   /* worst step on the best path: from the previous pick, then the predicted frames */
                float g = vm_dot(e, kp), gb = -2.0f;
                for (int o2 = 0; o2 < g_vm_la_c[0]; o2++) { int b2 = g_al_fast_ord[0][o2]; if (!g_al_fast_nan[0] && g_vm_la_cc[0][b2] <= gb) break;
                    float d = fminf(vm_dot(e, g_vm_la_e[0][b2]), g_vm_la_cc[0][b2]); if (d > gb) gb = d; }'''
A2 = '''                int L = g_vm_la_n - 1;
                for (int c = 0; c < g_vm_la_c[L]; c++) g_vm_la_cc[L][c] = 1.0f;
                for (int k = L - 1; k >= 0; k--) for (int a = 0; a < g_vm_la_c[k]; a++) {
                    float best = -2.0f;
                    for (int b2 = 0; b2 < g_vm_la_c[k + 1]; b2++) {
                        float d = fminf(vm_dot(g_vm_la_e[k][a], g_vm_la_e[k + 1][b2]), g_vm_la_cc[k + 1][b2]); if (d > best) best = d; }
                    g_vm_la_cc[k][a] = best;
                }'''
B2 = '''                int L = g_vm_la_n - 1;
                for (int c = 0; c < g_vm_la_c[L]; c++) g_vm_la_cc[L][c] = 1.0f;
                al_fast_sort(L);
                for (int k = L - 1; k >= 0; k--) { for (int a = 0; a < g_vm_la_c[k]; a++) {
                    float best = -2.0f;
                    for (int o2 = 0; o2 < g_vm_la_c[k + 1]; o2++) { int b2 = g_al_fast_ord[k + 1][o2]; if (!g_al_fast_nan[k + 1] && g_vm_la_cc[k + 1][b2] <= best) break;
                        float d = fminf(vm_dot(g_vm_la_e[k][a], g_vm_la_e[k + 1][b2]), g_vm_la_cc[k + 1][b2]); if (d > best) best = d; }
                    g_vm_la_cc[k][a] = best;
                } al_fast_sort(k); }'''
A3 = 'static VmPose g_vm_fut[VM_LAH]; static Vec3 g_vm_la_e[VM_LAH][VM_LAA * 7]; static float g_vm_la_cc[VM_LAH][VM_LAA * 7];'
B3 = A3 + '''
static short g_al_fast_ord[VM_LAH][VM_LAA * 7];   /* fast-elb (lab): candidate order by cc descending (stable) */
static int g_al_fast_nan[VM_LAH];   /* a NaN cc (fminf ignores it) = no pruning on that level */
static int g_vm_la_c[VM_LAH];
static void al_fast_sort(int k)
{
    int n = g_vm_la_c[k]; short *o = g_al_fast_ord[k]; const float *c = g_vm_la_cc[k];
    g_al_fast_nan[k] = 0; for (int i = 0; i < n; i++) if (c[i] != c[i]) g_al_fast_nan[k] = 1;
    for (int i = 0; i < n; i++) {   /* insertion sort, n <= 168 */
        short v = (short)i; int j = i;
        while (j > 0 && c[o[j - 1]] < c[v]) { o[j] = o[j - 1]; j--; }
        o[j] = v;
    }
}'''
A0 = """            Vec3 E = vm_add(W, vm_mul(e, L2));
            if (!vm_elb_pass(W, E, S, L1n)) continue;
            float ee = eg ? vm_edge_eye(e, fb, W) : -1.0f;"""
B0 = """            Vec3 E = vm_add(W, vm_mul(e, L2));
            if (g_vm_edge_pen >= 0.0f && g_vm_elb_lawm >= 0.0f) {   /* fast-elb (lab): the score with no edge/look-ahead
                * penalty (each >= 0; IEEE rounding is monotone) bounds sc: a candidate that cannot beat its tier is skipped
                * before the pass test, the edge test and the look-ahead (it never updates tb/tbo, identical pick) */
                float ub_ = vm_dot(e, pref) + kw * vm_dot(e, kp) - 0.5f * fabsf(vm_len(vm_sub(E, S)) - L1n) / L1n
                     - 3.0f * fmaxf(0.0f, fabsf(dd) - 0.1396263f) + rbw * vm_dot(e, rbe)
                     - g_vm_edge_pen * 0.0f
                     - (rbw > 0.0f ? g_vm_rbpen * fmaxf(0.0f, g_vm_rbcos - vm_dot(e, rbe)) : 0.0f);
                float kd_ = vm_dot(e, kp); int ti_ = kd_ >= tc[0] ? 0 : kd_ >= tc[1] ? 1 : kd_ >= tc[2] ? 2 : 3;
                if (ub_ <= tb[ti_] && ub_ <= tbo[ti_]) continue;
            }
            if (!vm_elb_pass(W, E, S, L1n)) continue;
            float ee = eg ? vm_edge_eye(e, fb, W) : -1.0f;"""
A5 = """            float sc = vm_dot(e, pref) + kw * vm_dot(e, kp) - 0.5f * fabsf(vm_len(vm_sub(E, S)) - L1n) / L1n
                     - 3.0f * fmaxf(0.0f, fabsf(dd) - 0.1396263f) + rbw * vm_dot(e, rbe)
                     - g_vm_edge_pen * fmaxf(0.0f, ee - g_vm_edge_tol)    /* S1: least edge-facing fallback */
                     - (rbw > 0.0f ? g_vm_rbpen * fmaxf(0.0f, g_vm_rbcos - vm_dot(e, rbe)) : 0.0f);   /* ready: branch A only */"""
A6 = """        for (int i = 0; i < na; i++) for (int j = 0; j < ndd; j++) {
            float phi = a0 + i * as, dd = d0_ + j * ds, t = th + dd;
            if (fabsf(dd) > g_vm_elb_dmax * 0.0174533f + 1e-4f || t < 0.0f) continue;
            Vec3 e = vm_add(vm_mul(ax, cosf(t)), vm_mul(vm_add(vm_mul(u1, cosf(phi)), vm_mul(u2, sinf(phi))), sinf(t)));"""
B6 = """        float al_ct[32], al_st[32];   /* fast-elb (lab): the same cosf/sinf values, computed once per row/column (ndd <= 23) */
        for (int j = 0; j < ndd && j < 32; j++) { float dd = d0_ + j * ds, t = th + dd; al_ct[j] = cosf(t); al_st[j] = sinf(t); }
        for (int i = 0; i < na; i++) { float al_phi = a0 + i * as; Vec3 al_uu = vm_add(vm_mul(u1, cosf(al_phi)), vm_mul(u2, sinf(al_phi)));
        for (int j = 0; j < ndd; j++) {
            float phi = a0 + i * as, dd = d0_ + j * ds, t = th + dd;
            if (fabsf(dd) > g_vm_elb_dmax * 0.0174533f + 1e-4f || t < 0.0f) continue;
            Vec3 e = j < 32 ? vm_add(vm_mul(ax, al_ct[j]), vm_mul(al_uu, al_st[j]))
                            : vm_add(vm_mul(ax, cosf(t)), vm_mul(vm_add(vm_mul(u1, cosf(phi)), vm_mul(u2, sinf(phi))), sinf(t)));"""
A7 = """                if (eok && sc > tbo[ti]) { tbo[ti] = sc; tao[ti] = phi; tdo[ti] = dd; }   }
        }"""
B7 = """                if (eok && sc > tbo[ti]) { tbo[ti] = sc; tao[ti] = phi; tdo[ti] = dd; }   }
        } }"""
A8 = """            for (int k = 0; k < g_vm_fut_n; k++) {
                VmPose o = g_vm_fut[k]; Vec3 sk = vm_cross(o.f, o.u);"""
B8 = """            float al_lpc[VM_LAA], al_lps[VM_LAA], al_ltc[7], al_lts[7];   /* fast-elb (lab): same values, once per frame */
            for (int i = 0; i < VM_LAA; i++) { float phi = i * (6.2831853f / VM_LAA); al_lpc[i] = cosf(phi); al_lps[i] = sinf(phi); }
            for (int j = -3; j <= 3; j++) { float t = th + j * 0.1396263f; al_ltc[j + 3] = cosf(t); al_lts[j + 3] = sinf(t); }
            for (int k = 0; k < g_vm_fut_n; k++) {
                VmPose o = g_vm_fut[k]; Vec3 sk = vm_cross(o.f, o.u);"""
A9 = """                    Vec3 e = vm_add(vm_mul(ak, cosf(t)), vm_mul(vm_add(vm_mul(v1, cosf(phi)), vm_mul(v2, sinf(phi))), sinf(t)));"""
B9 = """                    Vec3 e = vm_add(vm_mul(ak, al_ltc[j + 3]), vm_mul(vm_add(vm_mul(v1, al_lpc[i]), vm_mul(v2, al_lps[i])), al_lts[j + 3])); (void)phi;"""
for a in (A0, A1, A2, A3, A5, A6, A7, A8, A9):
    if s.count(a) != 1: print('fast-elb: anchors not found in this source, skipped'); sys.exit(0)
# g_vm_la_c is declared later in the file (with g_vm_elb_la); the forward definition above needs the later one dropped
A4 = 'g_vm_fut_n, g_vm_la_n, g_vm_la_c[VM_LAH];'
if s.count(A4) != 1: print('fast-elb: g_vm_la_c declaration not found, skipped'); sys.exit(0)
i3, i4 = s.find(A3), s.find(A4)
if i4 < i3:   # declared before the arrays: just add the sorter after the arrays, no redeclaration
    B3 = B3.replace('static int g_vm_la_c[VM_LAH];\n', '')
else:
    s = s.replace(A4, 'g_vm_fut_n, g_vm_la_n;')
s = s.replace(A8, B8).replace(A9, B9).replace(A6, B6).replace(A7, B7).replace(A0, B0).replace(A1, B1).replace(A2, B2).replace(A3, B3)
open(p, 'w').write(s); print('fast-elb applied')
