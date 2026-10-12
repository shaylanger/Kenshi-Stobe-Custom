#!/usr/bin/env python3
"""kfp-fist-zpunch.py <KenshiFP root | client dir>: FP punch synthesizer for the native fists (NA1 redesign, fists-redesign 2026-10-11).

Why (Shay 2026-10-11 16:45 on NA1-fists.mp4: "not punches at all, the hands just move around on the screen; the arms don't
extend; both hands stay side by side"): measured on fisthook3 fh3b, the FP R arm is ALREADY fully straight in the guard
(shoulder 2.9 dm behind the eye, wrist at z 4.6, upper arm stretched 1.4x to reach it), so a punch has nowhere to go; the
native wrists only nudge it (fn_k 0.15) and Kenshi's native techniques (spins, ducks, haymakers) never put a fist in front of
the eye anyway. FP games author FP arms separately; this does the same, timed and chosen by the game's technique:
- guard: both wrists close to the face (bent arms, z 2.7-3.0, lower corners), small idle bob; block = tighter, higher guard;
- per technique a table (hand, type straight|hook|upper, native peak u; from the native clips: animlab native.py traj/render of
  the vanilla + Great Anims Mod skeletons, game-checked on fh3b: Lead jab L peak u .31, Hook L u .43) schedules FP punches so
  the FP fist lands at the native peak: wind-up (pull toward the shoulder / cock out / drop) -> fast strike (ease-out) to
  the crosshair at full reach (clamped to the stretched arm reach) -> hold -> slower recovery to the guard;
- unknown technique: a punch triggers when a native wrist drives forward fast in front of the chest (fp_fb, fp_vz);
- off hand pulls to the chin while the other strikes; hand keeps its guard orientation relative to the arm line + a
  corkscrew roll at extension; hooks raise the elbow (IK pole).
Live keys (fp_vm set): fp_on (default 1 since guard v5, 2026-10-11) fp_g{L,R}{x,y,z} fp_b{L,R}{x,y,z} fp_t{L,R}{x,y,z} fp_reach fp_tw
fp_ts fp_th fp_tr fp_wb fp_hk fp_up fp_oc fp_rq fp_gyaw fp_gpit fp_grol fp_spit fp_fb fp_vz fp_bob; test switch
fp_fire <0..5> (fires one punch now: hand = v%2 (0 L, 1 R), type = v/2) for deterministic takes. `fp_vm fist` adds
fp=<on> fpe=L,R fpev=<last event>. Log: "[vm] fp punch hand=L type=straight src=table|detect|fire tech='..' u=..".
Asserts its anchors; idempotent; applies before or after kfp-fist-strike (touches none of its anchor lines)."""
import sys, os
root = sys.argv[1]
p = os.path.join(root, 'kfp_viewmodel.inc')
if not os.path.exists(p):
    p = os.path.join(root, 'client', 'kfp_viewmodel.inc')
s = open(p).read()
TAG = '/* kfp-fist-zpunch */'
if TAG in s:
    print('kfp-fist-zpunch: already applied', p); sys.exit(0)

CODE = TAG + r"""   /* FP punch synthesizer (fists-redesign): table/detect-timed FP punches from a bent-arm guard */
static int   g_vm_fp_on = 1, g_vm_fp_fb = 1, g_vm_fp_fire = -1;
static Vec3  g_vm_fp_g[2]  = { { -1.30f, -0.90f, 3.00f }, { 1.90f, -1.20f, 2.80f } };   /* guard v5 (fists-redesign, Shay MVP 2026-10-11); guard wrists [L, R], camera dm */
static Vec3  g_vm_fp_gb[2] = { { -0.70f, -0.25f, 2.60f }, { 0.80f, -0.30f, 2.50f } };   /* block guard */
static Vec3  g_vm_fp_t[2]  = { { -0.30f, -0.20f, 5.00f }, { 0.30f, -0.20f, 5.00f } };   /* straight strike aim (ray from the eye) */
static float g_vm_fp_reach = 0.97f, g_vm_fp_tw = 0.20f, g_vm_fp_ts = 0.09f, g_vm_fp_th = 0.07f, g_vm_fp_tr = 0.30f;
static float g_vm_fp_wb = 0.55f, g_vm_fp_hk = 2.4f, g_vm_fp_up = 1.8f, g_vm_fp_oc = 0.3f, g_vm_fp_rq = 50.0f;
static float g_vm_fp_tmax = 6.0f, g_vm_fp_hq = 1.0f, g_vm_fp_wf = 0.55f;
static float g_vm_fp_spx = 0.0f, g_vm_fp_sroll = 0.0f;   /* strike hand pitch (fingers forward) / roll about the punch line, deg */   /* max strike depth; strike hand frame share; wind-up time share (then hold) */
static float g_vm_fp_gyaw = 0.0f, g_vm_fp_gpit = 0.0f, g_vm_fp_grol = 0.0f, g_vm_fp_spit = 0.0f, g_vm_fp_vz = 25.0f, g_vm_fp_bob = 0.04f;
typedef struct { const char *name; int n; struct { int hand, type; float u; } ev[3]; } VmFpTech;   /* hand 0 L 1 R; type 0 straight 1 hook 2 upper */
static const VmFpTech g_vm_fp_tech[] = {   /* native peak u per technique (animlab native.py on the game skeletons; prefix match) */
    { "Lead jab", 1, { { 0, 0, 0.30f } } },
    { "Hook", 1, { { 0, 1, 0.44f } } },
    { "badpunch", 1, { { 0, 1, 0.53f } } },
    { "ma chudan", 2, { { 1, 0, 0.36f }, { 0, 0, 0.55f } } },
    { "ma 2strike", 2, { { 0, 0, 0.34f }, { 1, 2, 0.57f } } },
    { "ma 2punchie", 2, { { 1, 0, 0.30f }, { 0, 0, 0.50f } } },
    { "shoteiL", 1, { { 0, 0, 0.30f } } },
    { "Elbow punch", 1, { { 1, 1, 0.45f } } },
    { "Surprise uppercut", 2, { { 0, 0, 0.35f }, { 1, 2, 0.74f } } },
    { "Flying blow", 1, { { 1, 0, 0.41f } } },
    { "desperate attack", 0, { { 0, 0, 0.0f } } },
    /* kicks / spins / taunts: no FP punch, the guard stays (and the detect fallback stays off) */
    { "headbutt", 0, { { 0, 0, 0.0f } } },
    { "flyknee", 0, { { 0, 0, 0.0f } } },
    { "flykick", 0, { { 0, 0, 0.0f } } },
    { "kicklow", 0, { { 0, 0, 0.0f } } },
    { "megakick", 0, { { 0, 0, 0.0f } } },
    { "Pontera", 0, { { 0, 0, 0.0f } } },
    { "Middle kick", 0, { { 0, 0, 0.0f } } },
    { "Knee kick", 0, { { 0, 0, 0.0f } } },
    { "Just high kick", 0, { { 0, 0, 0.0f } } },
    { "Armada", 0, { { 0, 0, 0.0f } } },
    { "Chapa Giratoria", 0, { { 0, 0, 0.0f } } },
    { "Dodge kick", 0, { { 0, 0, 0.0f } } },
    { "Ball kick", 0, { { 0, 0, 0.0f } } },
    { "Kick to the groin", 0, { { 0, 0, 0.0f } } },
    { "Pinok nejdan", 0, { { 0, 0, 0.0f } } },
    { "Pryzhok razvorot", 0, { { 0, 0, 0.0f } } },
    { "Vertushka", 0, { { 0, 0, 0.0f } } },
    { "S nogi nahui", 0, { { 0, 0, 0.0f } } },
    { "Taunt unarmed", 0, { { 0, 0, 0.0f } } },
    { "Battlecry taunt", 0, { { 0, 0, 0.0f } } },
    { "S razvorota", 0, { { 0, 0, 0.0f } } },
};
#define VM_NFP ((int)(sizeof g_vm_fp_tech / sizeof g_vm_fp_tech[0]))
typedef struct { int on, type, src; float tau, t0; Vec3 P0; } VmFpEv;
static VmFpEv g_vm_fp_ev[2];
static const void *g_vm_fp_techp; static int g_vm_fp_ti = -1, g_vm_fp_done[3];
static float g_vm_fp_rate, g_vm_fp_pu, g_vm_fp_tt, g_vm_fp_clock, g_vm_fp_cool[2], g_vm_fp_e[2];
static Vec3  g_vm_fp_G[2], g_vm_fp_out[2], g_vm_fp_np[2], g_vm_fp_S[2], g_vm_fp_Gs[2]; static int g_vm_fp_hG[2], g_vm_fp_hn[2];
static unsigned long g_vm_fp_tick_n, g_vm_fp_nev; static char g_vm_fp_last[96];
static const char *vm_fp_tn(int t) { return t == 1 ? "hook" : t == 2 ? "upper" : "straight"; }
static float vm_fp_ss(float x) { x = x < 0 ? 0 : x > 1 ? 1 : x; return x * x * (3 - 2 * x); }
/* strike point: on the eye ray through T (the punch lands on the crosshair line, never pulled sideways by the reach
 * clamp), as deep as the arm reaches from its shoulder S (at most fp_tmax) */
static Vec3 vm_fp_aim(Vec3 T, Vec3 S, float R)
{
    Vec3 d = vm_norm(T); float b = vm_dot(d, S), c = vm_dot(S, S) - R * R, q = b * b - c, t;
    t = q > 0.0f ? b + sqrtf(q) : b;
    if (t > g_vm_fp_tmax) t = g_vm_fp_tmax;
    if (t < 1.0f) t = 1.0f;
    return vm_mul(d, t);
}
static void vm_fp_start(int h, int type, float tau, int src)
{
    VmFpEv *E = &g_vm_fp_ev[h & 1];
    E->on = 1; E->type = type < 0 ? 0 : type > 2 ? 2 : type; E->src = src; E->tau = tau; E->t0 = tau;
    E->P0 = g_vm_fp_hn[h & 1] ? g_vm_fp_out[h & 1] : g_vm_fp_G[h & 1];
    g_vm_fp_nev++;
    snprintf(g_vm_fp_last, sizeof g_vm_fp_last, "%c-%s-%s", (h & 1) ? 'R' : 'L', vm_fp_tn(E->type), src == 0 ? "table" : src == 1 ? "detect" : "fire");
    logline("[vm] fp punch hand=%c type=%s src=%s tech='%s' u=%.2f", (h & 1) ? 'R' : 'L', vm_fp_tn(E->type),
            src == 0 ? "table" : src == 1 ? "detect" : "fire", g_fpc_fs_tech ? g_fpc_fs_name : "-", g_fpc_fs_prog);
}
/* once per frame: technique bookkeeping, event scheduling (table / detect / fire), event clocks */
static void vm_fp_tick(void)
{
    float dt = fminf(fmaxf(g_vm_dt, 0.0f), g_vm_maxdt), lead = g_vm_fp_tw + g_vm_fp_ts;
    const void *tp = g_fpc_fs_tech; float u = isfinite(g_fpc_fs_prog) ? g_fpc_fs_prog : 0.0f;
    g_vm_fp_clock += dt; g_vm_fp_tick_n++;
    if (tp != g_vm_fp_techp) {
        g_vm_fp_techp = tp; g_vm_fp_ti = -1; g_vm_fp_rate = 0.0f; g_vm_fp_pu = u; g_vm_fp_tt = 0.0f;
        g_vm_fp_done[0] = g_vm_fp_done[1] = g_vm_fp_done[2] = 0;
        if (tp) for (int k = 0; k < VM_NFP; k++)
            if (!strncmp(g_fpc_fs_name, g_vm_fp_tech[k].name, strlen(g_vm_fp_tech[k].name))) { g_vm_fp_ti = k; break; }
    } else if (tp) {
        g_vm_fp_tt += dt;
        if (dt > 1e-4f) { float r = (u - g_vm_fp_pu) / dt;
            if (r > 0.05f && r < 5.0f) g_vm_fp_rate = g_vm_fp_rate > 0.0f ? g_vm_fp_rate + 0.3f * (r - g_vm_fp_rate) : r; }
        g_vm_fp_pu = u;
    }
    if (tp && g_vm_fp_ti >= 0) {   /* table: start each event so its strike ends at the native peak */
        const VmFpTech *T = &g_vm_fp_tech[g_vm_fp_ti]; float rate = g_vm_fp_rate > 0.0f ? g_vm_fp_rate : 0.7f;
        for (int k = 0; k < T->n && k < 3; k++) if (!g_vm_fp_done[k]) {
            float tau = (u - T->ev[k].u) / rate;
            if (tau >= -lead) { g_vm_fp_done[k] = 1; if (tau < g_vm_fp_th) vm_fp_start(T->ev[k].hand, T->ev[k].type, tau, 0); }
        }
    }
    for (int h = 0; h < 2; h++) {   /* detect (unknown technique): a native wrist drives forward fast in front of the chest */
        Vec3 N = vm_s2c_pos(g_vm_nhp[h]);
        if (g_vm_fp_cool[h] > 0.0f) g_vm_fp_cool[h] -= dt;
        if (tp && g_vm_fp_ti < 0 && g_vm_fp_fb && g_vm_fp_tt > 0.10f && g_vm_fp_hG[h] && dt > 1e-4f && g_vm_fp_cool[h] <= 0.0f) {
            float vz = (N.z - g_vm_fp_np[h].z) / dt;
            if (vz > g_vm_fp_vz && N.z > 2.0f) { vm_fp_start(h, 0, -g_vm_fp_ts - 0.12f, 1);   /* late: short wind-up */ g_vm_fp_cool[h] = 0.5f; }
        }
        g_vm_fp_np[h] = N;
    }
    if (g_vm_fp_fire >= 0) { vm_fp_start(g_vm_fp_fire % 2, g_vm_fp_fire / 2, -lead, 2); g_vm_fp_fire = -1; }
    for (int h = 0; h < 2; h++) { VmFpEv *E = &g_vm_fp_ev[h];
        if (E->on) { E->tau += dt; if (E->tau > g_vm_fp_th + g_vm_fp_tr) E->on = 0; } }
}
/* hand h's FP wrist (camera numbers) this frame; e = its extension share (orientation / off hand) */
static Vec3 vm_fp_wrist(int h, void **bb, int blk)
{
    if (h == 0) vm_fp_tick();
    float sx = h ? 1.0f : -1.0f, dt = fminf(fmaxf(g_vm_dt, 0.0f), g_vm_maxdt), a = 1.0f - expf(-dt / 0.10f);
    Vec3 Gt = blk ? g_vm_fp_gb[h] : g_vm_fp_g[h];
    g_vm_fp_G[h] = g_vm_fp_hG[h] ? vm_lerp(g_vm_fp_G[h], Gt, a) : Gt; g_vm_fp_hG[h] = 1;
    Vec3 G = g_vm_fp_G[h], S = vm_v(sx * 1.4f, -2.4f, -1.5f); float reach = 7.0f;
    {   const Vec3 *ps = g_oldnode_getdpos(bb[0]), *pe = g_oldnode_getdpos(bb[1]), *ph = g_oldnode_getdpos(bb[2]);
        if (readable((void *)ps, 12) && readable((void *)pe, 12) && readable((void *)ph, 12)) {
            float L1 = vm_l1(bb[0], ps, pe), L2 = vm_len(vm_sub(*ph, *pe));
            S = vm_s2c_pos(*ps); reach = g_vm_fp_reach * (L1 * (g_vm_stretch > 1.0f ? g_vm_stretch : 1.0f) + L2);
        } }
    g_vm_fp_S[h] = S; g_vm_fp_Gs[h] = G;
    G.y += g_vm_fp_bob * sinf(6.2832f * 0.9f * g_vm_fp_clock + 1.3f * h);
    VmFpEv *E = &g_vm_fp_ev[h]; Vec3 P = G; float e = 0.0f;
    if (E->on) {
        Vec3 T = g_vm_fp_t[h], C, wd;
        Vec3 ws = vm_norm(vm_sub(S, E->P0));   /* wind-up = pull toward the shoulder (+ cock out / drop for hook / upper) */
        if (E->type == 1) { T = vm_v(sx * 0.10f, T.y + 0.15f, T.z * 0.85f); wd = vm_norm(vm_add(ws, vm_norm(vm_v(sx * 1.0f, -0.2f, -0.6f)))); }
        else if (E->type == 2) { T = vm_v(sx * 0.20f, T.y + 0.40f, T.z * 0.85f); wd = vm_norm(vm_add(ws, vm_norm(vm_v(0.0f, -1.0f, -0.4f)))); }
        else wd = ws;
        T = vm_fp_aim(T, S, reach);
        Vec3 Pw = vm_add(E->P0, vm_mul(wd, g_vm_fp_wb));
        if (E->type == 1) C = vm_add(vm_mul(vm_add(Pw, T), 0.5f), vm_v(sx * g_vm_fp_hk, 0.25f, 0.0f));
        else if (E->type == 2) C = vm_add(vm_mul(vm_add(Pw, T), 0.5f), vm_v(0.0f, -g_vm_fp_up, -0.3f));
        else C = vm_add(vm_mul(vm_add(Pw, T), 0.5f), vm_v(0.0f, 0.15f, 0.0f));
        float tau = E->tau, ts = fmaxf(g_vm_fp_ts, 0.01f), tw = fmaxf(g_vm_fp_tw, 0.01f), tr = fmaxf(g_vm_fp_tr, 0.01f);
        if (tau < -ts) P = vm_lerp(E->P0, Pw, vm_fp_ss((tau - E->t0) / fmaxf((-ts - E->t0) * fmaxf(g_vm_fp_wf, 0.1f), 0.01f)));   /* pull, then hold cocked */
        else if (tau < 0.0f) { float x = (tau + ts) / ts, t = 1.0f - (1.0f - x) * (1.0f - x), q = 1.0f - t;
            P = vm_add(vm_add(vm_mul(Pw, q * q), vm_mul(C, 2.0f * q * t)), vm_mul(T, t * t)); e = t; }
        else if (tau < g_vm_fp_th) { P = T; e = 1.0f; }
        else { float x = vm_fp_ss((tau - g_vm_fp_th) / tr); P = vm_lerp(T, G, x); e = 1.0f - x; }
        Vec3 d = vm_sub(P, S); float D = vm_len(d);
        if (D > reach && D > 1e-3f) P = vm_add(S, vm_mul(d, reach / D));
    } else {   /* off hand: toward the chin while the other hand strikes */
        float eo = g_vm_fp_e[1 - h];
        P = vm_add(P, vm_mul(vm_v(-sx * 0.06f, 0.08f, -0.42f), g_vm_fp_oc * eo));
    }
    g_vm_fp_e[h] = e; g_vm_fp_out[h] = P; g_vm_fp_hn[h] = 1;
    return P;
}
/* hand orientation: fitted guard axes + guard tweak, follows the arm line, corkscrew at extension; hook raises the elbow */
static void vm_fp_orient(int h, Quat *Qt, Vec3 *pole)
{
    float sx = h ? 1.0f : -1.0f, e = g_vm_fp_e[h];
    Vec3 X, Y;
    if (g_vm_fn_hq[h]) { X = g_vm_fn_Gx[h]; Y = g_vm_fn_Gy[h]; }
    else { X = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(*Qt, vm_v(1, 0, 0))))); Y = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(*Qt, vm_v(0, 1, 0))))); }
    Quat Rg = quat_norm(quat_mul(vm_axang(vm_v(0, 1, 0), sx * g_vm_fp_gyaw * 0.0174533f),
              quat_mul(vm_axang(vm_v(1, 0, 0), g_vm_fp_gpit * 0.0174533f), vm_axang(vm_v(0, 0, 1), sx * g_vm_fp_grol * 0.0174533f))));
    X = quat_rotvec(Rg, X); Y = quat_rotvec(Rg, Y);
    Vec3 a0 = vm_norm(vm_sub(g_vm_fp_Gs[h], g_vm_fp_S[h])), a1 = vm_norm(vm_sub(g_vm_fp_out[h], g_vm_fp_S[h]));
    Quat Ra = vm_fromto(a0, a1);
    Quat Rs = quat_norm(quat_mul(vm_axang(a1, -sx * g_vm_fp_rq * e * 0.0174533f), vm_axang(vm_v(1, 0, 0), g_vm_fp_spit * e * 0.0174533f)));
    X = quat_rotvec(Rs, quat_rotvec(Ra, X)); Y = quat_rotvec(Rs, quat_rotvec(Ra, Y));
    if (e > 0.0f && g_vm_fp_hq > 0.0f) {   /* strike frame: knuckles forward (hand X between arm line and view axis), palm down */
        Vec3 Xs = vm_norm(vm_add(a1, vm_v(0, 0, 1))), up = vm_v(0, -1, 0);   /* v4: the camera frame is left-handed: Zs = down gives the true palm (-Z) down (v2 Zs = up rendered palm UP: game 140 zpA3) */
        Vec3 Zs = vm_norm(vm_sub(up, vm_mul(Xs, vm_dot(up, Xs)))), Ys = vm_norm(vm_v(Zs.y * Xs.z - Zs.z * Xs.y, Zs.z * Xs.x - Zs.x * Xs.z, Zs.x * Xs.y - Zs.y * Xs.x));
        float k = fminf(g_vm_fp_hq, 1.0f) * vm_fp_ss(e * 1.4f);
        X = vm_norm(vm_lerp(X, Xs, k)); Y = vm_lerp(Y, Ys, k); Y = vm_norm(vm_sub(Y, vm_mul(X, vm_dot(X, Y))));
        /* game 140 zpA3 (frame review): with X forward / Z up the rendered fingers point UP (palm-strike look): the glove
         * fingers run along hand +Z, not X. Pitch the strike frame about the camera X (fp_spx deg, fingers -> forward) and
         * roll it about the punch line (fp_sroll deg: which side the palm faces) */
        Quat Rp = quat_norm(quat_mul(vm_axang(a1, sx * g_vm_fp_sroll * k * 0.0174533f), vm_axang(vm_v(1, 0, 0), g_vm_fp_spx * k * 0.0174533f)));
        X = quat_rotvec(Rp, X); Y = quat_rotvec(Rp, Y);
    }
    *Qt = vm_frame_quat(vm_norm(vm_w2s_dir(vm_c2w_dir(X))), vm_norm(vm_w2s_dir(vm_c2w_dir(Y))));
    if (g_vm_fp_ev[h].on && g_vm_fp_ev[h].type == 1) {
        Vec3 pc = vm_lerp(g_vm_pole[0][h], vm_v(sx * 1.0f, 0.3f, -0.2f), e);
        *pole = vm_norm(vm_w2s_dir(vm_c2w_dir(pc)));
    }
}
"""

PAIRS = [
    ("""static void vm_fist_native_apply(void *b[2][4], float we)
{
""",
     """static Vec3 vm_s2c_pos(Vec3 s);
""" + CODE + """static void vm_fist_native_apply(void *b[2][4], float we)
{
"""),
    ("""        if (h.z < g_vm_fn_zmin) h.z = g_vm_fn_zmin;
""",
     """        if (g_vm_fp_on) { h = vm_fp_wrist(i, b[i], blk); h0 = h; } else   /* kfp-fist-zpunch */
        if (h.z < g_vm_fn_zmin) h.z = g_vm_fn_zmin;
"""),
    ("""        {   float yl = g_vm_fn_ymin * h.z""",
     """        if (!g_vm_fp_on) {   float yl = g_vm_fn_ymin * h.z"""),
    ("""        if (!vm_ik(i, b[i][0], b[i][1], b[i][2], Ph, Qt, 0, pole, we, NULL, 0.0f)) g_vm_ikfail++;
""",
     """        if (g_vm_fp_on) vm_fp_orient(i, &Qt, &pole);   /* kfp-fist-zpunch */
        if (!vm_ik(i, b[i][0], b[i][1], b[i][2], Ph, Qt, 0, pole, we, NULL, 0.0f)) g_vm_ikfail++;
"""),
    ("""    else if (!strcmp(k, "fn_k")) fp = &g_vm_fn_k;
""",
     """    else if (!strcmp(k, "fp_on")) { g_vm_fp_on = x != 0.0f; g_vm_fp_hG[0] = g_vm_fp_hG[1] = g_vm_fp_hn[0] = g_vm_fp_hn[1] = 0; return 1; }   /* kfp-fist-zpunch */
    else if (!strcmp(k, "fp_fire")) { g_vm_fp_fire = (x >= 0.0f && x < 6.0f) ? (int)x : -1; return 1; }
    else if (!strcmp(k, "fp_fb")) { g_vm_fp_fb = x != 0.0f; return 1; }
    else if (!strncmp(k, "fp_g", 4) && (k[4] == 'L' || k[4] == 'R') && k[5] >= 'x' && k[5] <= 'z' && !k[6]) fp = vm_vec_field(&g_vm_fp_g[k[4] == 'R'], k[5]);
    else if (!strncmp(k, "fp_b", 4) && (k[4] == 'L' || k[4] == 'R') && k[5] >= 'x' && k[5] <= 'z' && !k[6]) fp = vm_vec_field(&g_vm_fp_gb[k[4] == 'R'], k[5]);
    else if (!strncmp(k, "fp_t", 4) && (k[4] == 'L' || k[4] == 'R') && k[5] >= 'x' && k[5] <= 'z' && !k[6]) fp = vm_vec_field(&g_vm_fp_t[k[4] == 'R'], k[5]);
    else if (!strcmp(k, "fp_reach")) fp = &g_vm_fp_reach;
    else if (!strcmp(k, "fp_tw")) fp = &g_vm_fp_tw;
    else if (!strcmp(k, "fp_ts")) fp = &g_vm_fp_ts;
    else if (!strcmp(k, "fp_th")) fp = &g_vm_fp_th;
    else if (!strcmp(k, "fp_tr")) fp = &g_vm_fp_tr;
    else if (!strcmp(k, "fp_wb")) fp = &g_vm_fp_wb;
    else if (!strcmp(k, "fp_hk")) fp = &g_vm_fp_hk;
    else if (!strcmp(k, "fp_up")) fp = &g_vm_fp_up;
    else if (!strcmp(k, "fp_oc")) fp = &g_vm_fp_oc;
    else if (!strcmp(k, "fp_rq")) fp = &g_vm_fp_rq;
    else if (!strcmp(k, "fp_gyaw")) fp = &g_vm_fp_gyaw;
    else if (!strcmp(k, "fp_gpit")) fp = &g_vm_fp_gpit;
    else if (!strcmp(k, "fp_grol")) fp = &g_vm_fp_grol;
    else if (!strcmp(k, "fp_spit")) fp = &g_vm_fp_spit;
    else if (!strcmp(k, "fp_vz")) fp = &g_vm_fp_vz;
    else if (!strcmp(k, "fp_bob")) fp = &g_vm_fp_bob;
    else if (!strcmp(k, "fp_tmax")) fp = &g_vm_fp_tmax;
    else if (!strcmp(k, "fp_hq")) fp = &g_vm_fp_hq;
    else if (!strcmp(k, "fp_wf")) fp = &g_vm_fp_wf;
    else if (!strcmp(k, "fp_spx")) fp = &g_vm_fp_spx;
    else if (!strcmp(k, "fp_sroll")) fp = &g_vm_fp_sroll;
    else if (!strcmp(k, "fn_k")) fp = &g_vm_fn_k;
"""),
    ("""        {   size_t o = strlen(fb);   /* native fists */
""",
     """        {   size_t o = strlen(fb);   /* kfp-fist-zpunch */
            snprintf(fb + o, sizeof fb - o, " fp=%d fpe=%.2f,%.2f fpev=%s fpn=%lu", g_vm_fp_on, g_vm_fp_e[0], g_vm_fp_e[1],
                     g_vm_fp_last[0] ? g_vm_fp_last : "-", g_vm_fp_nev); }
        {   size_t o = strlen(fb);   /* native fists */
"""),
]
for old, new in PAIRS:
    assert s.count(old) == 1, 'anchor not found / not unique: ' + old[:80]
    s = s.replace(old, new, 1)
open(p, 'w', newline='\n').write(s)
print('kfp-fist-zpunch: ok', p)
