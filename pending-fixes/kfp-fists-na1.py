#!/usr/bin/env python3
"""kfp-fists-na1.py -- KenshiFP FP fists (NA1): unarmed punches from the animation lab's key tables.

Usage: python3 kfp-fists-na1.py <KenshiFP tree root | its client dir>   (e.g. /root/KenshiFP; asserts every anchor, applies once)

What it adds (client/kfp_viewmodel.inc, client/kfp_controls.inc):
- Fist mode: unarmed ready stance (R with nothing to draw: g_fpc_fists) and no weapon in hands -> both arms are driven
  from the fist key tables instead of the weapon path. Guard pose while ready/blocking; during a free swing (LMB) the
  technique the native picked (CombatTechniqueData::animation: badpunch, ma chudan, ma 2strike, shoteiL) plays its
  table on the native progress clock (g_fpc_fs_prog, = the lab's clock: native clip length / anim speed). Techniques
  without a table (kicks, headbutt, ...) play the ma chudan table (logged once per swing as fallback=1).
- Per hand the lab's solve: prop target VP(p,f,u) -> hand target through the class-0 prop local (g_vm_pldq/pldp, grip
  roll g_vm_groll, grip slide g_vm_plsl); the left hand uses the biped mirror (quat x,y and pos z negated, roll
  180 - groll) exactly as the animlab drive's --side L; natural 2-bone IK (vm_ik, no elbow pick, hinge off during the
  fist apply: the lab sets wroll=0 edgeclamp=0 wfix=0 hroll=0 e1inl=0 hinge=0 elb=0).
- Camera near clip lowered to g_vm_nc (1.5) while the fists are shown, as the crossbow (X2): the lab's nearcut for the
  fists is 2.0 against it.
- Commands: fp_vm set fist_ua 0|1 (default 1), fp_vm set fist_tech <table index 0-3 | -1> (take rows: the free swing
  re-picks the native technique until it is that table's; -1 = native choice), fp_vm fist (state: on, tech, table, fallback, u, n, targets, measured
  wrists), one log line per swing "[vm] fist swing tech='..' table=.. fallback=..".
Tables: animlab native.py fists on the unarmed FP body (vmrec-fist-z0-a.txt frame 100, 4080 2026-10-10), harness
d988203 (v4: R wind-up chamber on screen); regenerate with the lab and re-run components/KenshiFP/animlab/fists-gen-patch.py when the lab tables change.
"""
import os, sys

TABLES = r"""/* KenshiFP fist key tables (candidate, NOT installed): animlab native.py fists, badpunch, ma chudan, ma 2strike, shoteiL.
 * Poses VP(p, f, u) in camera numbers (dm), KenshiFP prop target convention for the weapon class 0 path; L rows
 * are in the drive's --side L convention (mirrored grip, as dual wield). Guard = start/end pose of every technique.
 * Key u = per technique (the swing clock runs over the native clip length / anim speed mult).
 * Wrists straight (hand X on the solved forearm); fingers: the game hand mesh has no finger bones (fixed hand).
 * Solver settings the lab used: fp_vm set wroll=0 edgeclamp=0 wfix=0 hroll=0 e1inl=0 hinge=0 elb=0 */
static VmPose g_vm_fist_guard[2] = { VP(0.578f, -1.974f, 4.571f, -0.762f, 0.279f, 0.585f, -0.223f, -0.960f, 0.168f),   /* R */
                                     VP(-2.209f, -1.997f, 5.314f, -0.458f, -0.211f, 0.864f, -0.138f, 0.976f, 0.165f) }; /* L */
/* badpunch (native 1.50 s; strikers L; key path p95 0.33 dm; PASS) */
static float g_vm_fist_u_badpunch[10] = { 0.0f, 0.133f, 0.178f, 0.422f, 0.511f, 0.578f, 0.689f, 0.889f, 0.933f, 1.0f };
static VmPose g_vm_fist_badpunch[2][8] = {
    { VP(0.428f, -2.077f, 4.662f, -0.775f, 0.269f, 0.572f, -0.225f, -0.963f, 0.149f),
      VP(-0.040f, -2.278f, 4.662f, -0.812f, 0.250f, 0.527f, -0.228f, -0.968f, 0.109f),
      VP(0.326f, -2.650f, 4.631f, -0.783f, 0.220f, 0.582f, -0.221f, -0.973f, 0.070f),
      VP(0.533f, -2.483f, 4.203f, -0.795f, 0.276f, 0.540f, -0.230f, -0.961f, 0.153f),
      VP(0.449f, -2.378f, 4.187f, -0.802f, 0.285f, 0.524f, -0.233f, -0.958f, 0.165f),
      VP(0.166f, -2.227f, 4.129f, -0.825f, 0.299f, 0.480f, -0.241f, -0.954f, 0.178f),
      VP(0.582f, -2.326f, 4.216f, -0.789f, 0.286f, 0.544f, -0.230f, -0.958f, 0.171f),
      VP(0.640f, -2.215f, 4.440f, -0.754f, 0.258f, 0.604f, -0.219f, -0.966f, 0.139f) },   /* R */
    { VP(-2.673f, -2.244f, 5.694f, -0.631f, -0.331f, 0.701f, -0.141f, 0.938f, 0.316f),
      VP(-2.706f, -1.937f, 5.684f, -0.638f, -0.297f, 0.710f, -0.130f, 0.951f, 0.281f),
      VP(-2.992f, -2.378f, 5.044f, -0.517f, -0.219f, 0.828f, -0.158f, 0.974f, 0.159f),
      VP(-1.544f, -0.553f, 6.554f, -0.594f, -0.092f, 0.799f, 0.104f, 0.976f, 0.189f),
      VP(-1.875f, -2.612f, 4.712f, -0.303f, -0.148f, 0.941f, -0.111f, 0.987f, 0.119f),
      VP(-2.775f, -2.208f, 4.891f, -0.452f, -0.170f, 0.875f, -0.157f, 0.981f, 0.109f),
      VP(-2.717f, -3.022f, 5.344f, -0.544f, -0.320f, 0.776f, -0.134f, 0.946f, 0.296f),
      VP(-2.445f, -2.505f, 5.337f, -0.496f, -0.261f, 0.828f, -0.132f, 0.965f, 0.225f) } }; /* L */
/* ma chudan (native 1.60 s; strikers LR; key path p95 0.40 dm; PASS) */
static float g_vm_fist_u_ma_chudan[10] = { 0.0f, 0.083f, 0.208f, 0.292f, 0.354f, 0.458f, 0.729f, 0.854f, 0.938f, 1.0f };
static VmPose g_vm_fist_ma_chudan[2][8] = {
    { VP(0.296f, -2.427f, 4.298f, -0.794f, 0.254f, 0.552f, -0.226f, -0.967f, 0.119f),
      VP(0.405f, -2.494f, 4.500f, -0.775f, 0.233f, 0.587f, -0.221f, -0.971f, 0.094f),
      VP(0.547f, -2.429f, 4.787f, -0.766f, 0.239f, 0.596f, -0.220f, -0.970f, 0.106f),
      VP(-0.621f, -1.764f, 5.443f, -0.880f, 0.091f, 0.466f, -0.012f, -0.985f, 0.170f),
      VP(-0.895f, -1.628f, 5.159f, -0.896f, 0.087f, 0.435f, -0.002f, -0.982f, 0.190f),
      VP(-0.448f, -1.097f, 5.166f, -0.871f, 0.140f, 0.471f, -0.020f, -0.968f, 0.251f),
      VP(-0.009f, -2.224f, 5.040f, -0.828f, 0.180f, 0.531f, -0.139f, -0.983f, 0.117f),
      VP(0.422f, -2.057f, 4.769f, -0.783f, 0.247f, 0.571f, -0.197f, -0.969f, 0.150f) },   /* R */
    { VP(-3.052f, -2.471f, 5.103f, -0.538f, -0.241f, 0.808f, -0.158f, 0.970f, 0.184f),
      VP(-0.903f, -0.933f, 6.161f, -0.525f, -0.118f, 0.843f, 0.115f, 0.972f, 0.207f),
      VP(-2.737f, -2.392f, 4.968f, -0.463f, -0.195f, 0.865f, -0.148f, 0.979f, 0.142f),
      VP(-3.092f, -2.569f, 5.155f, -0.556f, -0.261f, 0.789f, -0.158f, 0.965f, 0.208f),
      VP(-3.095f, -2.582f, 5.161f, -0.558f, -0.263f, 0.787f, -0.158f, 0.965f, 0.211f),
      VP(-3.067f, -2.502f, 5.120f, -0.545f, -0.247f, 0.802f, -0.158f, 0.969f, 0.191f),
      VP(-3.112f, -2.682f, 5.206f, -0.571f, -0.282f, 0.771f, -0.158f, 0.959f, 0.234f),
      VP(-2.397f, -2.185f, 5.431f, -0.522f, -0.266f, 0.811f, -0.142f, 0.964f, 0.224f) } }; /* L */
/* ma 2strike (native 1.90 s; strikers R; key path p95 0.33 dm; PASS) */
static float g_vm_fist_u_ma_2strike[11] = { 0.0f, 0.088f, 0.246f, 0.351f, 0.456f, 0.526f, 0.596f, 0.667f, 0.754f, 0.895f, 1.0f };
static VmPose g_vm_fist_ma_2strike[2][9] = {
    { VP(0.333f, -2.461f, 4.331f, -0.785f, 0.243f, 0.569f, -0.223f, -0.969f, 0.106f),
      VP(0.226f, -2.324f, 4.140f, -0.821f, 0.292f, 0.490f, -0.239f, -0.956f, 0.169f),
      VP(0.517f, -2.482f, 4.497f, -0.765f, 0.234f, 0.600f, -0.220f, -0.971f, 0.099f),
      VP(0.307f, -2.401f, 4.230f, -0.805f, 0.271f, 0.527f, -0.231f, -0.962f, 0.143f),
      VP(-0.134f, -1.526f, 5.061f, -0.846f, 0.177f, 0.504f, -0.083f, -0.976f, 0.203f),
      VP(-0.779f, -1.299f, 5.196f, -0.890f, 0.100f, 0.444f, 0.004f, -0.974f, 0.228f),
      VP(0.256f, -2.258f, 5.040f, -0.803f, 0.207f, 0.558f, -0.170f, -0.978f, 0.118f),
      VP(0.468f, -2.491f, 4.472f, -0.769f, 0.233f, 0.595f, -0.220f, -0.971f, 0.096f),
      VP(0.547f, -2.349f, 4.661f, -0.765f, 0.246f, 0.595f, -0.220f, -0.968f, 0.117f) },   /* R */
    { VP(-1.393f, -1.831f, 5.012f, -0.273f, -0.114f, 0.955f, -0.123f, 0.989f, 0.083f),
      VP(-1.655f, -1.492f, 4.850f, -0.268f, -0.072f, 0.961f, -0.154f, 0.988f, 0.031f),
      VP(-2.723f, -1.483f, 5.257f, -0.548f, -0.207f, 0.810f, -0.174f, 0.976f, 0.131f),
      VP(-1.814f, -1.605f, 4.764f, -0.273f, -0.071f, 0.959f, -0.157f, 0.987f, 0.028f),
      VP(-2.617f, -1.909f, 4.917f, -0.428f, -0.145f, 0.892f, -0.163f, 0.983f, 0.081f),
      VP(-2.594f, -1.929f, 4.908f, -0.423f, -0.144f, 0.895f, -0.162f, 0.983f, 0.081f),
      VP(-2.880f, -1.842f, 5.092f, -0.509f, -0.185f, 0.840f, -0.169f, 0.979f, 0.113f),
      VP(-3.087f, -2.314f, 5.479f, -0.661f, -0.349f, 0.664f, -0.188f, 0.934f, 0.305f),
      VP(-2.274f, -2.398f, 5.504f, -0.527f, -0.298f, 0.796f, -0.133f, 0.954f, 0.269f) } }; /* L */
/* shoteiL (native 1.50 s; strikers L; key path p95 0.34 dm; PASS) */
static float g_vm_fist_u_shoteil[7] = { 0.0f, 0.133f, 0.311f, 0.400f, 0.778f, 0.867f, 1.0f };
static VmPose g_vm_fist_shoteil[2][5] = {
    { VP(0.785f, -2.632f, 4.399f, -0.741f, 0.222f, 0.634f, -0.216f, -0.972f, 0.088f),
      VP(0.671f, -2.189f, 4.936f, -0.759f, 0.259f, 0.598f, -0.220f, -0.965f, 0.139f),
      VP(0.617f, -2.521f, 4.245f, -0.784f, 0.267f, 0.561f, -0.226f, -0.964f, 0.142f),
      VP(0.449f, -2.457f, 4.186f, -0.803f, 0.279f, 0.526f, -0.232f, -0.960f, 0.156f),
      VP(0.583f, -2.486f, 4.229f, -0.788f, 0.272f, 0.552f, -0.228f, -0.962f, 0.149f) },   /* R */
    { VP(-2.853f, -3.221f, 5.340f, -0.567f, -0.346f, 0.747f, -0.140f, 0.935f, 0.327f),
      VP(-2.238f, -1.156f, 5.858f, -0.618f, -0.190f, 0.762f, -0.037f, 0.976f, 0.214f),
      VP(-1.235f, -0.788f, 6.383f, -0.562f, -0.109f, 0.820f, 0.108f, 0.973f, 0.203f),
      VP(-1.250f, -0.497f, 6.161f, -0.557f, -0.082f, 0.826f, 0.098f, 0.982f, 0.164f),
      VP(-1.344f, -1.723f, 5.508f, -0.510f, -0.220f, 0.832f, -0.003f, 0.967f, 0.255f) } }; /* L */"""


def patch(path, edits):
    s = open(path, encoding='utf-8', newline='').read()
    if 'g_vm_fist_on' in s or 'g_fpc_fs_name' in s:
        print('already applied: %s' % path); return
    for old, new in edits:
        n = s.count(old)
        assert n == 1, '%s: anchor found %d times: %r' % (path, n, old[:80])
        s = s.replace(old, new)
    open(path, 'w', encoding='utf-8', newline='').write(s)
    print('patched %s' % path)


root = sys.argv[1] if len(sys.argv) > 1 else '/root/KenshiFP'
C = os.path.join(root, 'client') if os.path.isdir(os.path.join(root, 'client')) else root   # tree root or the client dir (animlab build.sh --patch)

VM_DECL_OLD = "static float vm_nearclip(float base) { return (g_vm_nc > 0.0f && g_vm_class == 1 && g_vm_w > 0.01f && base > g_vm_nc) ? g_vm_nc : base; }"
VM_DECL_NEW = """static int   g_vm_fist_on, g_vm_fist_ua = 1;  /* NA1 fists: this frame unarmed fist mode; fp_vm set fist_ua 0|1 */
static float vm_nearclip(float base) { return (g_vm_nc > 0.0f && (g_vm_class == 1 || g_vm_fist_on) && g_vm_w > 0.01f && base > g_vm_nc) ? g_vm_nc : base; }"""

UI_OLD = "static const char *g_fpc_ui_state;          /* tentative decl; defined in kfp_controls.inc */\n"
UI_NEW = UI_OLD + ("static int   g_fpc_fists;                    /* tentative decl; defined in kfp_controls.inc (NA1 fists) */\n"
                   "static void *g_fpc_fs_tech;                 /* tentative decl; defined in kfp_controls.inc (NA1 fists) */\n")

FIST_CODE = TABLES + r"""
/* NA1 fists (animlab native.py fists, Shay 2026-10-10: use the native animations as the guide): per technique the key
 * u (0 and 1 = the guard) and per hand [R, L] the keyed prop targets; interpolation = vm_swing_at (Catmull-Rom, zero
 * tangent at the guard). */
typedef struct { const char *anim; const float *u; const VmPose *k[2]; int n; } VmFistTech;
static const VmFistTech g_vm_fist_tech[] = {
    { "badpunch",   g_vm_fist_u_badpunch,   { g_vm_fist_badpunch[0],   g_vm_fist_badpunch[1] },   (int)(sizeof g_vm_fist_badpunch[0] / sizeof(VmPose)) },
    { "ma chudan",  g_vm_fist_u_ma_chudan,  { g_vm_fist_ma_chudan[0],  g_vm_fist_ma_chudan[1] },  (int)(sizeof g_vm_fist_ma_chudan[0] / sizeof(VmPose)) },
    { "ma 2strike", g_vm_fist_u_ma_2strike, { g_vm_fist_ma_2strike[0], g_vm_fist_ma_2strike[1] }, (int)(sizeof g_vm_fist_ma_2strike[0] / sizeof(VmPose)) },
    { "shoteiL",    g_vm_fist_u_shoteil,    { g_vm_fist_shoteil[0],    g_vm_fist_shoteil[1] },    (int)(sizeof g_vm_fist_shoteil[0] / sizeof(VmPose)) },
};
#define VM_NFIST ((int)(sizeof g_vm_fist_tech / sizeof g_vm_fist_tech[0]))
static char  g_fpc_fs_name[48];             /* tentative decl; set in kfp_controls.inc (free-swing technique animation) */
static int   g_vm_fist_force = -1;          /* fp_vm set fist_tech i: free swings re-pick until table i's technique (-1 native) */
static int   g_vm_fist_ti = -1, g_vm_fist_fb; static float g_vm_fist_u; static unsigned long g_vm_fist_n, g_vm_fist_sw;
static const void *g_vm_fist_tech_p;        /* the free-swing tech the current table belongs to */
static VmPose g_vm_fist_cur[2];             /* this frame's targets [L, R], camera numbers */
static VmPose vm_fist_at(const VmFistTech *T, int s, float u)   /* s: 0 = R row, 1 = L row (table order) */
{
    VmPose g = g_vm_fist_guard[s], k[16 + 2]; int nk = T->n < 16 ? T->n : 16, n = nk + 2;
    const float *t = T->u;
    k[0] = vm_pose_norm(g); for (int i = 0; i < nk; i++) k[i + 1] = vm_pose_norm(T->k[s][i]); k[n - 1] = k[0];
    if (u <= 0.0f || u >= 1.0f) return k[0];
    int i = 0; while (i < n - 2 && u > t[i + 1]) i++;
    int a = i > 0 ? i - 1 : i, d = i + 2 < n ? i + 2 : i + 1;
    float ta = i > 0 ? t[a] : t[i] - (t[i + 1] - t[i]), td = i + 2 < n ? t[d] : t[i + 1] + (t[i + 1] - t[i]);
    VmPose ka = k[a], kd = k[d], r;
    if (i == 0) { ka = k[i + 1]; ta = t[i + 1] - 2.0f * (t[i + 1] - t[i]); }
    if (i + 2 >= n) { kd = k[i]; td = t[i] + 2.0f * (t[i + 1] - t[i]); }
    r.p = vm_cr(ka.p, k[i].p, k[i + 1].p, kd.p, ta, t[i], t[i + 1], td, u);
    r.f = vm_cr(ka.f, k[i].f, k[i + 1].f, kd.f, ta, t[i], t[i + 1], td, u);
    r.u = vm_cr(ka.u, k[i].u, k[i + 1].u, kd.u, ta, t[i], t[i + 1], td, u);
    return vm_pose_norm(r);
}
static void vm_fist_targets(void)
{
    if (g_fpc_fs_tech) {
        if (g_fpc_fs_tech != g_vm_fist_tech_p) {   /* a new swing: pick its table */
            g_vm_fist_tech_p = g_fpc_fs_tech; g_vm_fist_ti = 1; g_vm_fist_fb = 1;
            for (int i = 0; i < VM_NFIST; i++) if (!strcmp(g_fpc_fs_name, g_vm_fist_tech[i].anim)) { g_vm_fist_ti = i; g_vm_fist_fb = 0; break; }
            g_vm_fist_sw++;
            logline("[vm] fist swing tech='%s' table=%s fallback=%d", g_fpc_fs_name, g_vm_fist_tech[g_vm_fist_ti].anim, g_vm_fist_fb);
        }
        g_vm_fist_u = isfinite(g_fpc_fs_prog) ? fmaxf(0.0f, fminf(1.0f, g_fpc_fs_prog)) : 0.0f;
    } else { g_vm_fist_tech_p = NULL; g_vm_fist_u = 0.0f; }
    for (int s = 0; s < 2; s++)   /* s: 0 = R, 1 = L (table rows); stored [L, R] */
        g_vm_fist_cur[1 - s] = g_vm_fist_tech_p ? vm_fist_at(&g_vm_fist_tech[g_vm_fist_ti], s, g_vm_fist_u) : vm_pose_norm(g_vm_fist_guard[s]);
}
/* both hands to their fist targets: the lab drive's per-side solve (R: weapon path class 0; L: --side L mirror) */
static void vm_fist_apply(void *b[2][4], float we)
{
    int hg = g_vm_hinge; g_vm_hinge = 0;
    vm_fist_targets();
    for (int i = 0; i < 2; i++) {   /* 0 = L, 1 = R */
        VmPose P = g_vm_fist_cur[i];
        Vec3 tp = vm_w2s_pos(vm_c2w_pos(P.p)), tf = vm_norm(vm_w2s_dir(vm_c2w_dir(P.f))), tu = vm_norm(vm_w2s_dir(vm_c2w_dir(P.u)));
        Quat Qp = quat_norm(quat_mul(vm_frame_quat(tf, tu), quat_conj(vm_frame_quat(vm_axis(g_vm_ax[0][0]), vm_axis(g_vm_ax[0][1])))));
        Quat lq = quat_norm(g_vm_pldq[0]); Vec3 lp = g_vm_pldp[0]; float gr = g_vm_groll[0];
        if (!i) { lq.x = -lq.x; lq.y = -lq.y; lp.z = -lp.z;
                  gr = (6 - abs(g_vm_ax[0][0]) - abs(g_vm_ax[0][1]) == 3 ? 0.0f : 180.0f) - gr; }   /* drive --side L */
        if (gr != 0.0f) { float h = gr * 0.0087266f; Vec3 ax = vm_axis(g_vm_ax[0][0]);
            lq = quat_norm(quat_mul(lq, (Quat){ cosf(h), ax.x * sinf(h), ax.y * sinf(h), ax.z * sinf(h) })); }
        const Vec3 *hs = g_oldnode_getdscale ? g_oldnode_getdscale(b[i][2]) : NULL;
        Vec3 sc = readable((void *)hs, 12) ? *hs : vm_v(1, 1, 1);
        if (g_vm_plsl[0] != 0.0f && g_vm_scale > 1e-6f) {
            float sk = fabsf(sc.y) > 1e-3f ? sc.y : 1.0f;
            lp = vm_add(lp, vm_mul(quat_rotvec(lq, vm_axis(g_vm_ax[0][0])), g_vm_plsl[0] / (g_vm_scale * sk)));
        }
        Quat Qh = quat_norm(quat_mul(Qp, quat_conj(lq)));
        Vec3 Ph = vm_sub(tp, quat_rotvec(Qh, vm_v(lp.x * sc.x, lp.y * sc.y, lp.z * sc.z)));
        Vec3 pole = vm_norm(vm_w2s_dir(vm_c2w_dir(g_vm_pole[0][i])));
        if (!vm_ik(i, b[i][0], b[i][1], b[i][2], Ph, Qh, 0, pole, we, NULL, 0.0f)) g_vm_ikfail++;
    }
    g_vm_hinge = hg;
    g_vm_fist_n++; g_vm_applied++;
}

/* Runs inside setAnimationState, after the original posed the skeleton. */"""

APPLY_OLD = "    if (!g_vm_have_t || we <= 0.001f) return;\n"
APPLY_NEW = "    if (g_vm_fist_on) { if (we > 0.001f) vm_fist_apply(b, we); return; }   /* NA1 fists: both arms from the fist tables */\n" + APPLY_OLD

FLAG_OLD = "        g_vm_melee = wih && wih != rw; g_vm_wih = wih != NULL;\n"
FLAG_NEW = FLAG_OLD + "        g_vm_fist_on = g_vm_fist_ua && !wih && g_fpc_fists;   /* NA1: unarmed ready stance (R with nothing to draw) */\n"

SET_OLD = '    else if (!strcmp(k, "hinge"))   { g_vm_hinge = x > 0.5f; return 1; }\n'
SET_NEW = SET_OLD + ('    else if (!strcmp(k, "fist_ua")) { g_vm_fist_ua = x != 0.0f; return 1; }   /* NA1 fists */\n'
                     '    else if (!strcmp(k, "fist_tech")) { g_vm_fist_force = (x >= 0.0f && x < VM_NFIST) ? (int)x : -1; return 1; }   /* NA1: force a technique (take rows), -1 = native */\n')

Q_OLD = '    } else if (!strcmp(a, "hinge")) {   /* E5 */\n'
Q_NEW = r"""    } else if (!strcmp(a, "fist")) {   /* NA1 fists state (camera numbers, dm) */
        char fb[700]; const VmPose *L = &g_vm_fist_cur[0], *R = &g_vm_fist_cur[1];
        snprintf(fb, sizeof fb, "fist ua=%d force=%d on=%d fists=%d wih=%d tech='%s' table=%s fallback=%d u=%.3f swings=%lu n=%lu w=%.2f zf=%.2f state=%s "
            "tL=%.2f,%.2f,%.2f tR=%.2f,%.2f,%.2f wrL=%.2f,%.2f,%.2f wrR=%.2f,%.2f,%.2f elL=%.2f,%.2f,%.2f elR=%.2f,%.2f,%.2f ikfail=%lu",
            g_vm_fist_ua, g_vm_fist_force, g_vm_fist_on, g_fpc_fists, g_vm_wih, g_vm_fist_tech_p ? g_fpc_fs_name : "-",
            g_vm_fist_tech_p ? g_vm_fist_tech[g_vm_fist_ti].anim : "guard", g_vm_fist_fb, g_vm_fist_u, g_vm_fist_sw, g_vm_fist_n,
            g_vm_w, g_vm_zf, g_vm_state ? g_vm_state : "?", L->p.x, L->p.y, L->p.z, R->p.x, R->p.y, R->p.z,
            g_vm_mj[0][2].x, g_vm_mj[0][2].y, g_vm_mj[0][2].z, g_vm_mj[1][2].x, g_vm_mj[1][2].y, g_vm_mj[1][2].z,
            g_vm_mj[0][1].x, g_vm_mj[0][1].y, g_vm_mj[0][1].z, g_vm_mj[1][1].x, g_vm_mj[1][1].y, g_vm_mj[1][1].z, g_vm_ikfail);
        r->append(r, fb); return KAH_OK;
""" + Q_OLD

patch(os.path.join(C, 'kfp_viewmodel.inc'), [
    (VM_DECL_OLD, VM_DECL_NEW),
    (UI_OLD, UI_NEW),
    ("\n/* Runs inside setAnimationState, after the original posed the skeleton. */", "\n" + FIST_CODE),
    (APPLY_OLD, APPLY_NEW), (FLAG_OLD, FLAG_NEW), (SET_OLD, SET_NEW), (Q_OLD, Q_NEW)])

patch(os.path.join(C, 'kfp_controls.inc'), [
    ("static void fpc_free_swing(void *pc) {\n",
     "static void fpc_tech_name(void *tech,char *out,size_t n);\nstatic char g_fpc_fs_name[48];   /* NA1: free-swing technique animation (fist tables) */\nstatic void fpc_free_swing(void *pc) {\n"),
    ("    if (!readable(tech,TECH_ANIM_SPEED+4)) {++g_fpc_fs_notech;return;}\n",
     "    if (!readable(tech,TECH_ANIM_SPEED+4)) {++g_fpc_fs_notech;return;}\n"
     "    if (g_fpc_fists && g_vm_fist_force>=0 && g_vm_fist_force<VM_NFIST) {   /* NA1 take rows: re-pick until the forced technique */\n"
     "        char nm[48];int k;for (k=0;k<48;k++) {fpc_tech_name(tech,nm,sizeof nm);if (!strcmp(nm,g_vm_fist_tech[g_vm_fist_force].anim)) break;\n"
     "            void *t2=g_fpc_choose(stats,5.0f,30.0f,tech,1);if (readable(t2,TECH_ANIM_SPEED+4)) tech=t2;}\n"
     "        if (k==48) logline(\"[vm] fist force: '%s' not picked in 48 tries (got '%s')\",g_vm_fist_tech[g_vm_fist_force].anim,nm);\n"
     "    }\n"),
    ("    g_fpc_fs_anim=anim;g_fpc_fs_tech=tech;g_fpc_fs_start_ms",
     "    fpc_tech_name(tech,g_fpc_fs_name,sizeof g_fpc_fs_name);\n    g_fpc_fs_anim=anim;g_fpc_fs_tech=tech;g_fpc_fs_start_ms")])

