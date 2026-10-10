"""fists-gen-patch.py <fist_keys.inc> <out patch.py>: generates pending-fixes/kfp-fists-na1.py from the lab's native.py fists tables (WSL)."""
import sys
inc = open(sys.argv[1]).read().strip()
out = sys.argv[2]
TEMPLATE = r'''#!/usr/bin/env python3
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

TABLES = r"""@@TABLES@@"""


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

'''
s = TEMPLATE.replace('@@TABLES@@', inc)
open(out, 'w').write(s)
print('wrote', out)
