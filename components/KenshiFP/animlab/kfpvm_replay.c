/* kfpvm_replay.c -- offline replay of KenshiFP's first-person viewmodel solver (kfp_viewmodel.inc, compiled as is).
 *
 * Usage: kfpvm_replay <rec.txt> <out.txt> [--calib L1R,L2R,L1L,L2L,K] [--set key=value]... [--set-at frame:key=value]...
 *                     [--cold] [--apply-all] [--quiet]
 *   --no-native  ignore the recording's native-pose group (use the post-IK skeleton of the next record)
 *   --no-rec-sets  ignore the recording's `# set` lines
 *   --apply-all  apply on every frame (default: only where the recording's napply counter shows the game applied)
 *   rec.txt  an `fp_vm rec dump` file from the game (per camera frame: inputs + the measured skeleton)
 *   out.txt  the replay's own `fp_vm rec dump` (same format, written by the plugin's vm_rec_dump), so every metric
 *            script reads the game and the replay the same way
 *   --set    = `fp_vm set key value` before frame 0 (same keys, same parser: the plugin's kah_fp_vm)
 *   --calib  skeleton lengths (dm) + prop scale; default: measured from the recording (printed as "calib ...")
 *
 * Model: the game's per-frame order is camera callback (vm_frame: measure the skeleton the last apply left, build the
 * targets) -> animation update -> Skeleton::setAnimationState (hook: native pose, then vm_apply = IK). Here a fake
 * skeleton (Bip01 spine/neck/head/clavicles/arms/hands/props, Ogre parent-derived transforms) stands in for the game:
 * the native pose of apply i is rebuilt from the recording (shoulders, arm directions, hand axes of record i+1 = what
 * the game rendered after apply i; native arm lengths from the calibration), world = skeleton space (scale 1),
 * camera from the recorded eye/yaw/pitch, ui state / dt / swing progress / zoom / shots / holster from the record. */
#include "prelude.h"
#include "gen_helpers.h"
#include "kfp_viewmodel.inc"

/* ---------------- recording ---------------- */
typedef struct { double x, y, z; } D3;
typedef struct {
    float t, dt; char st[16]; int ti, cls, on; float w; int swing; float swu, prog, kick, fire; int omode; float yaw, pitch, zoom;
    D3 v[17];                 /* out p f u, oc, mp mf mu, Lsh Lel Lwr Rsh Rel Rwr, eye rt up fw */
    int phase, wih; float stch; unsigned napp; int has_napp;
    int has5; float wb; D3 mh, mfx; float zf; D3 hd, nk, sp, hy, hz; int has_hyz;
    int nok; D3 nj[2][3], nhx[2], nhy[2], nlp[2]; double nlq[2][4];   /* native (pre-IK) pose of this frame's apply */
} Rin;
/* `# set <frame> <key> <value>` lines of the recording (frame -1 = before it started) */
static struct { int f; char kv[96]; } g_rsets[1024]; static int g_nrsets, g_use_rsets = 1;
static Rin *R; static int RN;
static D3 g_org;
/* --abs-world (X1 miss): keep the recorded absolute world positions (no origin shift), so world math runs in float32 at
 * the game's magnitudes (floating-origin quantisation of the bone-world map in sources before the node map, e948f86) */
static int g_abs_world;

static int parse3(const char *s, D3 *o) { return sscanf(s, "%lf,%lf,%lf", &o->x, &o->y, &o->z) == 3; }
static int load_rec(const char *path)
{
    FILE *f = fopen(path, "r"); if (!f) return -1;
    static char line[8192]; int cap = 1024; R = malloc(sizeof(Rin) * cap); RN = 0;
    while (fgets(line, sizeof line, f)) {
        if (!strncmp(line, "# set ", 6) && g_nrsets < 1024) {
            int fr; char k[64]; float v;
            if (sscanf(line + 6, "%d %63s %f", &fr, k, &v) == 3) {
                g_rsets[g_nrsets].f = fr; snprintf(g_rsets[g_nrsets].kv, sizeof g_rsets[0].kv, "%s=%g", k, v); g_nrsets++; }
            continue; }
        if (line[0] == '#' || !strchr(line, '|')) continue;
        if (RN == cap) { cap *= 2; R = realloc(R, sizeof(Rin) * cap); }
        Rin *r = &R[RN]; memset(r, 0, sizeof *r); r->zf = 1.0f;
        char *grp[8]; int ng = 0; char *p = line;
        for (;;) { grp[ng++] = p; char *b = strchr(p, '|'); if (!b || ng == 8) break; *b = 0; p = b + 1; }
        int n;
        if (sscanf(grp[0], "%d %f %f %15s %d %d %d %f %d %f %f %f %f %d %f %f %f", &n, &r->t, &r->dt, r->st, &r->ti, &r->cls, &r->on,
                   &r->w, &r->swing, &r->swu, &r->prog, &r->kick, &r->fire, &r->omode, &r->yaw, &r->pitch, &r->zoom) != 17) continue;
        int k = 0; char *tok, *sv;
        for (int g = 1; g <= 2 && g < ng; g++)
            for (tok = strtok_r(grp[g], " \t\n", &sv); tok && k < 17; tok = strtok_r(NULL, " \t\n", &sv)) parse3(tok, &r->v[k++]);
        if (k < 17) continue;
        if (ng > 3) { D3 a, b; unsigned napp; float st;
            if (sscanf(grp[3], " %lf,%lf,%lf %lf,%lf,%lf %u %d %d %f", &a.x, &a.y, &a.z, &b.x, &b.y, &b.z, &napp, &r->phase, &r->wih, &st) == 10) { r->stch = st; r->napp = napp; r->has_napp = 1; }
            else r->wih = 1; }
        if (ng > 4) {
            char *x[12]; int nx = 0;
            for (tok = strtok_r(grp[4], " \t\n", &sv); tok && nx < 12; tok = strtok_r(NULL, " \t\n", &sv)) x[nx++] = tok;
            if (nx >= 3) { r->has5 = 1; r->wb = atof(x[0]); parse3(x[1], &r->mh); parse3(x[2], &r->mfx); }
            if (nx >= 7) { r->zf = atof(x[3]); parse3(x[4], &r->hd); parse3(x[5], &r->nk); parse3(x[6], &r->sp); }
            if (nx >= 9) { parse3(x[7], &r->hy); parse3(x[8], &r->hz); r->has_hyz = 1; }
        }
        if (ng > 5) {   /* native group (KenshiFP rec-native patch): nok, 6 joints, hand X/Y axes L R, prop local L R */
            char *x[24]; int nx = 0;
            for (tok = strtok_r(grp[5], " \t\n", &sv); tok && nx < 24; tok = strtok_r(NULL, " \t\n", &sv)) x[nx++] = tok;
            if (nx >= 15 && atoi(x[0]) == 1) {
                int ok = 1;
                for (int s = 0; s < 2; s++) {
                    for (int k = 0; k < 3; k++) ok &= parse3(x[1 + 3 * s + k], &r->nj[s][k]);
                    ok &= parse3(x[7 + 2 * s], &r->nhx[s]) & parse3(x[8 + 2 * s], &r->nhy[s]);
                    ok &= parse3(x[11 + 2 * s], &r->nlp[s]);
                    ok &= sscanf(x[12 + 2 * s], "%lf,%lf,%lf,%lf", &r->nlq[s][0], &r->nlq[s][1], &r->nlq[s][2], &r->nlq[s][3]) == 4;
                }
                r->nok = ok;
            }
        }
        RN++;
    }
    fclose(f);
    if (RN && !g_abs_world) g_org = R[0].v[13];
    for (int i = 0; i < RN; i++) { R[i].v[13].x -= g_org.x; R[i].v[13].y -= g_org.y; R[i].v[13].z -= g_org.z; }
    return RN;
}
static Vec3 f3(D3 a) { return (Vec3){ (float)a.x, (float)a.y, (float)a.z }; }
/* camera numbers of record r -> world (origin-shifted) */
static Vec3 c2w(const Rin *r, D3 c, int pos)
{
    Vec3 rt = f3(r->v[14]), up = f3(r->v[15]), fw = f3(r->v[16]);
    Vec3 w = vm_add(vm_add(vm_mul(rt, (float)c.x), vm_mul(up, (float)c.y)), vm_mul(fw, (float)c.z));
    return pos ? vm_add(f3(r->v[13]), w) : w;
}

/* ---------------- fake skeleton ---------------- */
typedef struct { const char *name; int parent; Vec3 lp; Quat lq; Vec3 ls; Vec3 dp; Quat dq; Vec3 ds; } Bone;
enum { B_ROOT, B_SPINE, B_NECK, B_HEAD, B_CLAV_L, B_CLAV_R, B_UA_L, B_UA_R, B_FA_L, B_FA_R, B_HA_L, B_HA_R, B_PROP1, B_PROP2, B_N };
static Bone g_b[B_N] = {
    { "root", -1 }, { "Bip01 Spine", 0 }, { "Bip01 Neck", 1 }, { "Bip01 Head", 2 }, { "Bip01 L Clavicle", 2 }, { "Bip01 R Clavicle", 2 },
    { "Bip01 L UpperArm", 4 }, { "Bip01 R UpperArm", 5 }, { "Bip01 L Forearm", 6 }, { "Bip01 R Forearm", 7 },
    { "Bip01 L Hand", 8 }, { "Bip01 R Hand", 9 }, { "Bip01 Prop1", 10 }, { "Bip01 Prop2", 11 } };
static const Quat QI = { 1, 0, 0, 0 };
static void fk_update(void)
{
    for (int i = 0; i < B_N; i++) {
        Bone *b = &g_b[i];
        if (b->parent < 0) { b->dp = b->lp; b->dq = b->lq; b->ds = b->ls; continue; }
        Bone *p = &g_b[b->parent];
        b->dq = quat_norm(quat_mul(p->dq, b->lq));
        b->ds = vm_v(p->ds.x * b->ls.x, p->ds.y * b->ls.y, p->ds.z * b->ls.z);
        b->dp = vm_add(p->dp, quat_rotvec(p->dq, vm_v(p->ds.x * b->lp.x, p->ds.y * b->lp.y, p->ds.z * b->lp.z)));
    }
}
/* set bone i's locals so that its derived transform is (P, Q, S), parents already placed */
static void fk_place(int i, Vec3 P, Quat Q, Vec3 S)
{
    Bone *b = &g_b[i];
    if (b->parent < 0) { b->lp = P; b->lq = Q; b->ls = S; fk_update(); return; }
    fk_update(); Bone *p = &g_b[b->parent];
    Quat ci = quat_conj(p->dq); Vec3 d = quat_rotvec(ci, vm_sub(P, p->dp));
    b->lp = vm_v(d.x / p->ds.x, d.y / p->ds.y, d.z / p->ds.z);
    b->lq = quat_norm(quat_mul(ci, Q));
    b->ls = vm_v(S.x / p->ds.x, S.y / p->ds.y, S.z / p->ds.z);
    fk_update();
}
static Bone *fk_find(const void *name)
{
    for (int i = 0; i < B_N; i++) if (!strcmp(g_b[i].name, (const char *)name)) return &g_b[i];
    return NULL;
}
static void *fk_getbone(void *skel, const void *name) { (void)skel; return fk_find(name); }
static const Quat *fk_getdori(void *n) { fk_update(); return &((Bone *)n)->dq; }
static const Vec3 *fk_getdpos(void *n) { fk_update(); return &((Bone *)n)->dp; }
static const Quat *fk_getori(void *n) { return &((Bone *)n)->lq; }
static void fk_setori(void *n, const Quat *q) { ((Bone *)n)->lq = *q; }
static void fk_needupd(void *n, char f) { (void)n; (void)f; }
static void *fk_getparent(void *n) { Bone *b = n; return b->parent < 0 ? NULL : &g_b[b->parent]; }
static void fk_setpos(void *n, const Vec3 *p) { ((Bone *)n)->lp = *p; }
static const Vec3 *fk_getpos(void *n) { return &((Bone *)n)->lp; }
static const Vec3 *fk_getdscale(void *n) { fk_update(); return &((Bone *)n)->ds; }
/* --bw-lag: inside the apply, the character's bone-world query returns the PREVIOUS apply's pose (hypothesis test for
 * the game's clavicle-based world<->skeleton map lagging one frame behind the native pose: X1 jitter) */
static int g_bw_lag, g_in_apply; static Bone g_b_prev[B_N];
static Vec3 *fk_bone_world(void *c, Vec3 *ret, const void *name)
{
    (void)c; Bone *b = fk_find(name); fk_update();
    if (b && g_bw_lag && g_in_apply) b = &g_b_prev[b - g_b];
    *ret = b ? b->dp : vm_v(0, 0, 0); return ret;
}
static int char_position(void *c, Vec3 *out) { (void)c; fk_update(); *out = g_b[B_ROOT].dp; return 1; }

/* quaternion from orthonormal axes (columns X, Y, Z) */
static Quat q_axes(Vec3 X, Vec3 Y, Vec3 Z)
{
    float m00 = X.x, m10 = X.y, m20 = X.z, m01 = Y.x, m11 = Y.y, m21 = Y.z, m02 = Z.x, m12 = Z.y, m22 = Z.z, tr = m00 + m11 + m22; Quat q;
    if (tr > 0) { float s = sqrtf(tr + 1.0f) * 2; q = (Quat){ 0.25f * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s }; }
    else if (m00 > m11 && m00 > m22) { float s = sqrtf(1.0f + m00 - m11 - m22) * 2; q = (Quat){ (m21 - m12) / s, 0.25f * s, (m01 + m10) / s, (m02 + m20) / s }; }
    else if (m11 > m22) { float s = sqrtf(1.0f + m11 - m00 - m22) * 2; q = (Quat){ (m02 - m20) / s, (m01 + m10) / s, 0.25f * s, (m12 + m21) / s }; }
    else { float s = sqrtf(1.0f + m22 - m00 - m11) * 2; q = (Quat){ (m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25f * s }; }
    return quat_norm(q);
}
/* bone frame: X along dir, Y as close to ref as possible */
static Quat q_xref(Vec3 dir, Vec3 ref)
{
    Vec3 X = vm_norm(dir), Z = vm_cross(X, ref);
    if (vm_len(Z) < 1e-4f) Z = vm_cross(X, fabsf(X.y) < 0.9f ? vm_v(0, 1, 0) : vm_v(1, 0, 0));
    Z = vm_norm(Z); return q_axes(X, vm_cross(Z, X), Z);
}

/* ---------------- calibration ---------------- */
static float C_L1[2], C_L2[2], C_K = 1.0f; static int g_have_calib;
static int cmpf(const void *a, const void *b) { float x = *(const float *)a, y = *(const float *)b; return x < y ? -1 : x > y; }
static float median(float *a, int n) { if (n <= 0) return -1; qsort(a, n, sizeof(float), cmpf); return a[n / 2]; }
static float dlen(D3 a, D3 b) { double x = a.x - b.x, y = a.y - b.y, z = a.z - b.z; return (float)sqrt(x * x + y * y + z * z); }
static void calibrate(void)
{
    float *a = malloc(sizeof(float) * (RN + 1)); int n;
    for (int s = 0; s < 2; s++) {
        int sh = 7 + 3 * s, el = 8 + 3 * s, wr = 9 + 3 * s;
        n = 0; for (int i = 0; i < RN; i++) if (R[i].w < 0.001f) a[n++] = dlen(R[i].v[sh], R[i].v[el]);   /* native frames */
        if (n < 5) { n = 0; for (int i = 0; i < RN; i++) { float st = s == 1 && R[i].stch > 0.5f ? R[i].stch : 1.0f; a[n++] = dlen(R[i].v[sh], R[i].v[el]) / st; } }
        C_L1[s] = median(a, n);
        n = 0; for (int i = 0; i < RN; i++) a[n++] = dlen(R[i].v[el], R[i].v[wr]);
        C_L2[s] = median(a, n);
    }
    /* prop scale K: weapon grip offset in the hand frame = K * pldp + plsl * (prop forward), on full-viewmodel frames */
    n = 0;
    for (int i = 0; i < RN; i++) {
        const Rin *r = &R[i];
        if (!(r->w >= 0.99f && r->wih && r->has_hyz && r->on)) continue;
        int c = r->cls ? 1 : 0;
        /* hand-local coordinates by dot products: camera numbers are a mirrored frame (rt = fw x up), so the
         * recorded axis triple is left-handed there; dots are handedness-free */
        Vec3 o = vm_sub(f3(r->v[4]), f3(r->v[12]));
        Vec3 off = vm_v(vm_dot(o, vm_norm(f3(r->mh))), vm_dot(o, vm_norm(f3(r->hy))), vm_dot(o, vm_norm(f3(r->hz))));
        Quat lq = quat_norm(g_vm_pldq[c]);
        if (g_vm_groll[c] != 0.0f) { float h = g_vm_groll[c] * 0.0087266f; Vec3 ax = vm_axis(g_vm_ax[c][0]);
            lq = quat_norm(quat_mul(lq, (Quat){ cosf(h), ax.x * sinf(h), ax.y * sinf(h), ax.z * sinf(h) })); }
        if (g_vm_plfix & (c ? 1 : 2)) off = vm_sub(off, vm_mul(quat_rotvec(lq, vm_axis(g_vm_ax[c][0])), g_vm_plsl[c]));
        Vec3 pd = g_vm_pldp[c]; float l2 = vm_dot(pd, pd);
        if (l2 > 1e-6f) a[n++] = vm_dot(off, pd) / l2;
    }
    C_K = n >= 5 ? median(a, n) : 1.0f;
    free(a);
}

/* ---------------- native pose for an apply ---------------- */
static int g_nat;   /* record whose measured skeleton stands in for the native pose */
static int g_napp_rec = -1;   /* record whose recorded native group drives the current apply (-1 = none) */
static int g_use_native = 1, g_nat_used;
static int g_cls_fill[2];
static void set_native(int i)
{
    const Rin *r = &R[i]; Vec3 one = vm_v(1, 1, 1);
    const Rin *nr = g_use_native && g_napp_rec >= 0 && R[g_napp_rec].nok ? &R[g_napp_rec] : NULL;
    Vec3 up = f3(r->v[15]);
    Vec3 J[2][3]; for (int s = 0; s < 2; s++) for (int k = 0; k < 3; k++) J[s][k] = c2w(r, r->v[7 + 3 * s + k], 1);
    Vec3 sp, nk, hd;
    if (r->has5 && (r->sp.x != 0 || r->sp.y != 0 || r->sp.z != 0)) { sp = c2w(r, r->sp, 1); nk = c2w(r, r->nk, 1); hd = c2w(r, r->hd, 1); }
    else { Vec3 m = vm_mul(vm_add(J[0][0], J[1][0]), 0.5f); nk = vm_add(m, vm_mul(up, 0.5f)); sp = vm_sub(m, vm_mul(up, 4.0f)); hd = vm_add(nk, vm_mul(up, 1.2f)); }
    fk_update(); memcpy(g_b_prev, g_b, sizeof g_b_prev);
    fk_place(B_ROOT, vm_v(0, 0, 0), QI, one);
    fk_place(B_SPINE, sp, QI, one); fk_place(B_NECK, nk, QI, one); fk_place(B_HEAD, hd, QI, one);
    for (int s = 0; s < 2; s++) {
        Vec3 S = J[s][0], E = J[s][1], W = J[s][2];
        if (nr) { S = c2w(nr, nr->nj[s][0], 1); E = c2w(nr, nr->nj[s][1], 1); W = c2w(nr, nr->nj[s][2], 1); }
        fk_place(B_CLAV_L + s, vm_lerp(nk, S, 0.35f), QI, one);
        Quat qua = q_xref(vm_sub(E, S), up);
        fk_place(B_UA_L + s, S, qua, one);
        Vec3 En = nr ? E : vm_add(S, vm_mul(vm_norm(vm_sub(E, S)), C_L1[s]));
        Quat qfa = q_xref(vm_sub(W, E), up);
        fk_place(B_FA_L + s, En, qfa, one);
        Vec3 Hn = nr ? W : vm_add(En, vm_mul(vm_norm(vm_sub(W, E)), C_L2[s]));
        Quat qh = qfa;
        if (nr) { Vec3 X = vm_norm(c2w(nr, nr->nhx[s], 0)), Y = vm_norm(c2w(nr, nr->nhy[s], 0)); qh = q_axes(X, Y, vm_norm(vm_cross(X, Y))); }
        else if (s == 1 && r->has_hyz) qh = q_axes(vm_norm(c2w(r, r->mh, 0)), vm_norm(c2w(r, r->hy, 0)), vm_norm(c2w(r, r->hz, 0)));
        fk_place(B_HA_L + s, Hn, qh, vm_v(C_K, C_K, C_K));
        Bone *pb = &g_b[B_PROP1 + s]; int c = g_cls_fill[0];
        if (nr) { pb->lp = f3(nr->nlp[s]); pb->lq = quat_norm((Quat){ (float)nr->nlq[s][0], (float)nr->nlq[s][1], (float)nr->nlq[s][2], (float)nr->nlq[s][3] }); }
        else { pb->lp = g_vm_pldp[c]; pb->lq = quat_norm(g_vm_pldq[c]); }
        pb->ls = one;
    }
    if (nr) g_nat_used++;
    fk_update();
}
static void fk_native(void *skel, const void *set, float w, const void *bmap) { (void)skel; (void)set; (void)w; (void)bmap; set_native(g_nat); }

/* ---------------- warm start ----------------
 * A recording that starts with the viewmodel up (VMQUICK segments start after the frozen poses) has solver state
 * from before the recording: start from record 0 (pose, blend, phase, off-hand target, elbow direction) instead of a
 * cold draw. Roll / swing history is not recorded: those settle within the first frames (gate: --skip). */
static int g_warm = 1, g_napp_mode = 1, g_skipped;
static void warm_start(void)
{
    const Rin *r = &R[0], *n1 = &R[1]; int c = r->cls ? 1 : 0;
    VmPose o = { f3(r->v[0]), f3(r->v[1]), f3(r->v[2]) };
    if (g_vm_plsl[c] != 0.0f && (g_vm_plfix & (c ? 1 : 2))) o.p = vm_sub(o.p, vm_mul(o.f, g_vm_plsl[c]));
    g_vm_skel = g_b;   /* else the first vm_frame sees a new skeleton and resets everything */
    g_vm_cur = o; g_vm_have_cur = 1; memset(&g_vm_vel, 0, sizeof g_vm_vel);
    float lo = 0, hi = 1; for (int k = 0; k < 30; k++) { float m = 0.5f * (lo + hi); if (m * m * (3 - 2 * m) < r->w) lo = m; else hi = m; }
    g_vm_wl = 0.5f * (lo + hi); g_vm_w = r->w; g_vm_phase = r->phase; g_vm_ph_t = 1.0f; g_vm_class = c;
    g_vm_oc = f3(r->v[3]); g_vm_ocv = vm_v(0, 0, 0); g_vm_have_oc = 1;
    Vec3 d = vm_sub(f3(n1->v[11]), f3(n1->v[12]));
    if (vm_len(d) > 1e-3f) { g_vm_elbe = vm_norm(d); g_vm_have_elbe = 1;
#ifdef AL_HAVE_ELB_CB
        g_vm_elb_cb = g_vm_elbe; g_vm_have_cb = 1;   /* grid-winner hysteresis (X1 source): start on the recorded side */
#endif
    }
    g_vm_swing = r->swing && r->swu < 1.0f; g_vm_swu = r->swu; g_vm_sw0 = o;
}

/* ---------------- fake character ---------------- */
static char g_pc[0x800], g_anim[0x100]; static void *g_vt[0x400 / 8]; static int g_wep_melee, g_wep_ranged;
static void *fk_rw(void *pc) { (void)pc; return &g_wep_ranged; }
static char g_ent[0x100], g_node[0x100];
static void *fk_parent_node(void *e) { (void)e; return g_node; }
static Quat *fk_node_ori(void *n, Quat *r) { (void)n; *r = QI; return r; }
static Vec3 *fk_node_pos(void *n, Vec3 *r) { (void)n; *r = vm_v(0, 0, 0); return r; }
static Vec3 *fk_node_scale(void *n, Vec3 *r) { (void)n; *r = vm_v(1, 1, 1); return r; }

static void reply_append(KAH_Reply *r, const char *t) { (void)r; (void)t; }   /* a set's reply is a state dump: unused */
static int do_set(const char *kv)
{
    char k[128]; const char *eq = strchr(kv, '='); if (!eq || eq - kv >= (int)sizeof k) return 0;
    memcpy(k, kv, eq - kv); k[eq - kv] = 0;
    const char *argv[4] = { "fp_vm", "set", k, eq + 1 }; KAH_Reply rp = { NULL, reply_append };
    int q = g_al_quiet; g_al_quiet = 1; int rc = kah_fp_vm("animlab", 4, argv, &rp, NULL); g_al_quiet = q;
    if (rc != KAH_OK) fprintf(stderr, "kfpvm_replay: set %s failed\n", kv);
    return rc == KAH_OK;
}

int main(int argc, char **argv)
{
    if (argc < 3) { fprintf(stderr, "usage: kfpvm_replay <rec.txt> <out.txt> [--calib L1R,L2R,L1L,L2L,K] [--set k=v]... [--set-at frame:k=v]... [--quiet] [--abs-world] [--bw-lag]\n"); return 2; }
    const char *sets_at[256], *cl_set[256]; int nsa = 0, ncl_set = 0;
    for (int a = 3; a < argc; a++) if (!strcmp(argv[a], "--abs-world")) g_abs_world = 1;
    if (load_rec(argv[1]) < 2) { fprintf(stderr, "kfpvm_replay: no frames in %s\n", argv[1]); return 1; }
    /* plugin wiring */
    g_get_bone_world = fk_bone_world; g_skel_getbone = fk_getbone; g_oldnode_getdori = fk_getdori; g_oldnode_getdpos = fk_getdpos;
    g_oldnode_getori = fk_getori; g_oldnode_setori = fk_setori; g_oldnode_needupd = fk_needupd; g_oldnode_getparent = fk_getparent;
    g_oldnode_setpos = fk_setpos; g_oldnode_getpos = fk_getpos; g_oldnode_getdscale = fk_getdscale;
    g_vm_setanim_orig = fk_native; g_vm_hooked = 1;
    for (int i = 0; i < B_N; i++) { g_b[i].lq = QI; g_b[i].ls = vm_v(1, 1, 1); }
    *(void **)g_pc = g_vt; g_vt[0x3D0 / 8] = (void *)fk_rw;
    *(void **)(g_pc + CHAR_ANIM) = g_anim; *(void **)(g_anim + ANIM_SKELETON) = (void *)g_b;
    g_anim_ent_off = 0x10; *(void **)(g_anim + 0x10) = g_ent;   /* body entity -> scene node = identity */
    g_get_parent_scenenode = fk_parent_node; g_node_getdori_v = fk_node_ori; g_node_getdpos_v = fk_node_pos; g_node_getdscale_v = fk_node_scale;
    for (int a = 3; a < argc; a++) {
        if (!strcmp(argv[a], "--quiet")) g_al_quiet = 1;
        else if (!strcmp(argv[a], "--cold")) g_warm = 0;
        else if (!strcmp(argv[a], "--apply-all")) g_napp_mode = 0;
        else if (!strcmp(argv[a], "--no-rec-sets")) g_use_rsets = 0;
        else if (!strcmp(argv[a], "--no-native")) g_use_native = 0;
        else if (!strcmp(argv[a], "--bw-lag")) g_bw_lag = 1;
        else if (!strcmp(argv[a], "--abs-world")) ;
        else if (!strcmp(argv[a], "--set") && a + 1 < argc) { if (ncl_set < 256) cl_set[ncl_set++] = argv[++a]; }
        else if (!strcmp(argv[a], "--set-at") && a + 1 < argc) { if (nsa < 256) sets_at[nsa++] = argv[++a]; }
        else if (!strcmp(argv[a], "--calib") && a + 1 < argc) {
            if (sscanf(argv[++a], "%f,%f,%f,%f,%f", &C_L1[1], &C_L2[1], &C_L1[0], &C_L2[0], &C_K) != 5) { fprintf(stderr, "bad --calib\n"); return 2; }
            g_have_calib = 1; }
        else { fprintf(stderr, "kfpvm_replay: unknown arg %s\n", argv[a]); return 2; }
    }
    /* the recording's own `# set -1` lines (settings live before it started) come first, --set after them wins */
    if (g_use_rsets) for (int s = 0; s < g_nrsets; s++) if (g_rsets[s].f < 0) do_set(g_rsets[s].kv);
    for (int s = 0; s < ncl_set; s++) if (!do_set(cl_set[s])) return 2;
    if (!g_have_calib) calibrate();
    printf("calib %.4f,%.4f,%.4f,%.4f,%.4f\n", C_L1[1], C_L2[1], C_L1[0], C_L2[0], C_K);
    /* weapon class per frame: the class of the nearest frame that showed the viewmodel (on) */
    int *cf = malloc(sizeof(int) * RN), last = -1;
    for (int i = RN - 1; i >= 0; i--) { if (R[i].on) last = R[i].cls; cf[i] = last; }
    last = -1; for (int i = 0; i < RN; i++) { if (R[i].on) last = R[i].cls; if (cf[i] < 0) cf[i] = last >= 0 ? last : R[i].cls; }
    g_vm_class = cf[0]; g_cls_fill[0] = cf[0];
    g_nat = 0; set_native(0);
    if (g_warm && R[0].w > 0.001f && RN > 1) warm_start();
    g_vm_rec = calloc(VM_RECN, sizeof(VmRec)); g_vm_rn = 0; g_al_clock = 0; QueryPerformanceCounter(&g_vm_rec_t0); g_vm_rec_on = 1;
    unsigned shots = 0; int n = RN < VM_RECN ? RN : VM_RECN;
    for (int i = 0; i < n; i++) {
        const Rin *r = &R[i];
        for (int s = 0; s < nsa; s++) { int fr; const char *c = strchr(sets_at[s], ':');
            if (c && sscanf(sets_at[s], "%d:", &fr) == 1 && fr == i) do_set(c + 1); }
        if (g_use_rsets) for (int s = 0; s < g_nrsets; s++) if (g_rsets[s].f == i) do_set(g_rsets[s].kv);
        if (i) g_al_clock += r->dt;
        g_fpc_ui_state = r->st; g_fpc_fs_prog = r->prog; g_view.applied = r->zoom; g_view.target = r->zoom;
        g_yaw = r->yaw * 0.017453293f; g_pitch = r->pitch * 0.017453293f;
        g_last_eye = f3(r->v[13]); g_view_have_anchor = 0; g_tx = g_tz = 0;
        if (i && r->fire > R[i - 1].fire + 0.01f) shots++;
        g_combat_actual_shots = shots;
        { int lower = r->phase == VMP_LOWER; int ons = strcmp(r->st, "holstered") && strcmp(r->st, "down") && strcmp(r->st, "off") && strcmp(r->st, "none");
          g_fpc_holster_pending = lower && ons; }
        g_cls_fill[0] = cf[i];
        *(void **)(g_pc + CHAR_WEAPON_IN_HANDS) = r->wih ? (cf[i] ? (void *)&g_wep_ranged : (void *)&g_wep_melee) : NULL;
        vm_frame(g_pc, 0);
        g_nat = i + 1 < RN ? i + 1 : i;
        /* the game skips the animation update (no Skeleton::setAnimationState, so no apply) on some frames: napply
         * (re-maps inside full-weight applies) then does not increment and the skeleton keeps the last pose. Skip
         * the apply there too (only provable on frames where the viewmodel is up: napply counts only those). */
        int skip_apply = g_napp_mode && i + 1 < RN && r->has_napp && R[i + 1].has_napp && R[i + 1].napp == r->napp
                         && r->w * r->zf > 0.001f && R[i + 1].w * R[i + 1].zf > 0.001f;
        if (skip_apply) { g_skipped++; continue; }
        g_napp_rec = i;
        g_in_apply = 1; hooked_vm_setanim(g_b, NULL, 1.0f, NULL); g_in_apply = 0;
        g_napp_rec = -1;
    }
    int w = vm_rec_dump(argv[2]);
    printf("frames %d written %d skipped_applies %d native_applies %d rec_sets %d\n", n, w, g_skipped, g_nat_used, g_nrsets);
    return w > 0 ? 0 : 1;
}
