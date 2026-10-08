/* kfp_viewmodel.inc -- FP "viewmodel" presentation layer (PT13/PT14/PT17).
 *
 * Kenshi's combat animations hold the weapon at hip height and out to the
 * side, outside a first-person camera's view, so in FP the player barely sees
 * the weapon. This layer keeps the native animations (swing, block, reload)
 * but moves BOTH arms as one rigid piece -- rotated about the midpoint between
 * the shoulders -- so the weapon hand sits at a per-state spot in the view,
 * like other FP games. Rigid = the two hands keep their relative pose, so
 * two-handed grips (crossbow, bow, two-handers) stay intact.
 *
 * Where: Entity::_updateAnimation calls the VIRTUAL Skeleton::setAnimationState
 * (set, float, const map<string,bool>&) directly (disassembly: OgreMain+0xc2aac
 * -> +0x343200) right before the bone matrices are built; the OldSkeletonInstance
 * overload is never called. The hook calls the original, then rewrites the two
 * upper arms' local orientation AND position (rigid rotation g_vm_R about the
 * shoulder midpoint, skeleton space).
 *
 * How much: closed loop, per camera frame (after the weld forced this frame's
 * animation): measure the weapon hand in the view, build the world rotation
 * that carries it onto the target ray (same reach from the shoulder midpoint),
 * take a smoothed fraction, map it into skeleton space (basis from the
 * clavicles + spine in both spaces) and accumulate into g_vm_R. Swing/stagger
 * HOLD g_vm_R so the native arc plays on top of the raised stance.
 *
 * Single translation unit: included from kenshifp_client.c. Tuning: harness
 * `fp_vm`, ini keys viewmodel / vm_*. */

typedef void (*osi_setanim_t)(void *skel, const void *stateset, float w, const void *bmap);
#define OGRE_OSI_SETANIM_SYM "?setAnimationState@Skeleton@Ogre@@UEAAXAEBVAnimationStateSet@2@MAEBV?$map@V?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@_NU?$less@V?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@2@V?$STLAllocator@U?$pair@$$CBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@_N@std@@V?$CategorisedAllocPolicy@$0A@@Ogre@@@Ogre@@@std@@@Z"

enum { VM_READY, VM_AIM, VM_RELOAD, VM_BLOCK, VM_NT };
static const char *const g_vm_tname[VM_NT] = { "ready", "aim", "reload", "block" };
/* weapon-hand target in the view, degrees: elevation (down<0), azimuth (right>0) */
static float g_vm_te[VM_NT] = { -28.0f, -9.0f, -26.0f, -16.0f };
static float g_vm_ta[VM_NT] = {  16.0f,  5.0f,   8.0f,  12.0f };
static osi_setanim_t g_vm_setanim_orig;
static int   g_cfg_vm = 1;                  /* ini viewmodel=0|1 */
static float g_vm_tau      = 0.12f;         /* seconds: approach time constant */
static float g_vm_tau_rl   = 0.40f;         /* slower while reloading */
static float g_vm_maxdeg   = 110.0f;        /* clamp on the total arm rotation */

static void *g_vm_skel;                     /* controlled char's OldSkeletonInstance */
static Quat  g_vm_R = { 1, 0, 0, 0 };       /* skeleton-space rigid arm rotation */
static float g_vm_ang;                      /* its angle, deg (diag) */
static float g_vm_elev, g_vm_az, g_vm_target_e, g_vm_target_a; /* last measure (deg) */
static int   g_vm_hold, g_vm_dead, g_vm_hooked, g_vm_basis_ok;
static const char *g_vm_state = "off";
static unsigned long g_vm_calls, g_vm_applied, g_vm_reuse, g_vm_frames;
static Quat  g_vm_bq[2], g_vm_wq[2];        /* base / last-written local orientation */
static Vec3  g_vm_bp[2], g_vm_wp[2];        /* base / last-written local position */
static int   g_vm_have_written[2];
static unsigned char g_vm_nm_arm[2][32], g_vm_nm_clav[2][32], g_vm_nm_spine[32], g_vm_nm_hand[2][32];
static int   g_vm_hand = 1;                 /* tracked weapon hand: 0 = L, 1 = R (fp_vm set hand, ini vm_hand) */
static float g_vm_he[2], g_vm_ha[2];       /* both hands in the view (deg, diag) */
/* wrist tilt (melee only): extra rotation of the weapon hand about the camera-right axis so a one-handed
 * blade rises out of the view ray instead of pointing straight away (end-on, unreadable). */
static float g_vm_tilt[VM_NT] = { 25.0f, 0.0f, 0.0f, 30.0f };
static float g_vm_tilt_cur;                 /* smoothed, deg */
static Vec3  g_vm_tilt_ax;                  /* camera-right in skeleton space */
static int   g_vm_melee;                    /* weapon in hands is not the ranged weapon */
static Quat  g_vm_hbq, g_vm_hwq; static int g_vm_h_written;
/* PT14: procedural melee swing -- the native free/combat swing barely moves the blade in the view, so while
 * "swinging" the hand target runs an arc (start -> end, eased) and the wrist tilt sweeps with it. */
static float g_vm_sw[6] = { -8.0f, 24.0f, -30.0f, -12.0f, 50.0f, -20.0f };   /* e0 a0 e1 a1 tilt0 tilt1 */
static float g_vm_sw_dur = 0.35f, g_vm_swt, g_vm_swu;
static int   g_vm_swing, g_vm_swings;
static float g_vm_sw_pose = -1.0f;          /* test: >=0 freezes the swing arc at this u while ready */
static float g_fpc_fs_prog;                 /* tentative decl; defined in kfp_controls.inc (free-swing anim progress 0..1) */
static int   g_vm_names;

static const char *g_fpc_ui_state;          /* tentative decl; defined in kfp_controls.inc */

static void vm_names(void)
{
    if (g_vm_names) return;
    make_mstr_long(g_vm_nm_arm[0], "Bip01 L UpperArm");   /* >=16 chars: heap strings, kept */
    make_mstr_long(g_vm_nm_arm[1], "Bip01 R UpperArm");
    make_mstr_long(g_vm_nm_clav[0], "Bip01 L Clavicle");
    make_mstr_long(g_vm_nm_clav[1], "Bip01 R Clavicle");
    make_mstr(g_vm_nm_spine, "Bip01 Spine");
    make_mstr(g_vm_nm_hand[0], "Bip01 L Hand");
    make_mstr(g_vm_nm_hand[1], "Bip01 R Hand");
    g_vm_names = 1;
}

static Vec3  vm_sub(Vec3 a, Vec3 b) { return (Vec3){ a.x-b.x, a.y-b.y, a.z-b.z }; }
static Vec3  vm_add(Vec3 a, Vec3 b) { return (Vec3){ a.x+b.x, a.y+b.y, a.z+b.z }; }
static Vec3  vm_mul(Vec3 a, float s) { return (Vec3){ a.x*s, a.y*s, a.z*s }; }
static float vm_dot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
static Vec3  vm_cross(Vec3 a, Vec3 b) { return (Vec3){ a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x }; }
static float vm_len(Vec3 a) { return sqrtf(vm_dot(a, a)); }
static Vec3  vm_norm(Vec3 a) { float l = vm_len(a); return l > 1e-6f ? vm_mul(a, 1.0f / l) : a; }

static Quat vm_axis_angle(Vec3 a, float ang)
{
    float l = vm_len(a);
    if (l < 1e-6f) return (Quat){ 1, 0, 0, 0 };
    float s = sinf(ang * 0.5f) / l;
    return (Quat){ cosf(ang * 0.5f), a.x*s, a.y*s, a.z*s };
}

/* Runs inside setAnimationState, after the original posed the skeleton. */
static void vm_apply(void *skel)
{
    void *b[2], *par[2];
    Vec3 p[2]; Quat pdq[2]; Vec3 pdp[2], ps[2];
    for (int i = 0; i < 2; i++) {
        b[i] = g_skel_getbone(skel, g_vm_nm_arm[i]);
        if (!readable(b[i], 8)) return;
        par[i] = g_oldnode_getparent(b[i]);
        if (!readable(par[i], 8)) return;
        const Quat *lq = g_oldnode_getori(b[i]);
        const Vec3 *lp = g_oldnode_getpos(b[i]);
        const Quat *dq = g_oldnode_getdori(par[i]);
        const Vec3 *dp = g_oldnode_getdpos(par[i]);
        const Vec3 *dsc = g_oldnode_getdscale ? g_oldnode_getdscale(par[i]) : NULL;
        if (!readable((void *)lq, 16) || !readable((void *)lp, 12) || !readable((void *)dq, 16)
            || !readable((void *)dp, 12)) return;
        Quat q = *lq; Vec3 v = *lp;
        /* Bone not reset since our last write (manually controlled, e.g. the
         * locomotion layer owns it and skipped a frame): start from the saved
         * base, never stack on our own output. */
        if (g_vm_have_written[i] && !memcmp(&q, &g_vm_wq[i], sizeof(Quat))
            && !memcmp(&v, &g_vm_wp[i], sizeof(Vec3))) { q = g_vm_bq[i]; v = g_vm_bp[i]; g_vm_reuse++; }
        g_vm_bq[i] = q; g_vm_bp[i] = v;
        pdq[i] = *dq; pdp[i] = *dp;
        ps[i] = readable((void *)dsc, 12) ? *dsc : (Vec3){ 1, 1, 1 };
        Vec3 sv = { v.x*ps[i].x, v.y*ps[i].y, v.z*ps[i].z };
        p[i] = vm_add(pdp[i], quat_rotvec(pdq[i], sv));          /* unmodified derived position */
    }
    Vec3 c = vm_mul(vm_add(p[0], p[1]), 0.5f);
    for (int i = 0; i < 2; i++) {
        Vec3 np = vm_add(c, quat_rotvec(g_vm_R, vm_sub(p[i], c)));
        Quat ip = quat_conj(pdq[i]);
        Quat nq = quat_norm(quat_mul(quat_mul(quat_mul(ip, g_vm_R), pdq[i]), g_vm_bq[i]));
        Vec3 lv = quat_rotvec(ip, vm_sub(np, pdp[i]));
        lv.x /= (fabsf(ps[i].x) > 1e-6f ? ps[i].x : 1.0f);
        lv.y /= (fabsf(ps[i].y) > 1e-6f ? ps[i].y : 1.0f);
        lv.z /= (fabsf(ps[i].z) > 1e-6f ? ps[i].z : 1.0f);
        g_oldnode_setori(b[i], &nq);
        g_oldnode_setpos(b[i], &lv);
        g_oldnode_needupd(b[i], 1);
        g_vm_wq[i] = nq; g_vm_wp[i] = lv; g_vm_have_written[i] = 1;
    }
    if (fabsf(g_vm_tilt_cur) > 0.05f && vm_len(g_vm_tilt_ax) > 0.5f) {
        void *hb = g_skel_getbone(skel, g_vm_nm_hand[g_vm_hand ? 1 : 0]);
        void *hp = readable(hb, 8) ? g_oldnode_getparent(hb) : NULL;
        const Quat *hq = readable(hb, 8) ? g_oldnode_getori(hb) : NULL;
        const Quat *hdq = readable(hp, 8) ? g_oldnode_getdori(hp) : NULL;   /* lazily updated after our arm write */
        if (readable((void *)hq, 16) && readable((void *)hdq, 16)) {
            Quat q = *hq;
            if (g_vm_h_written && !memcmp(&q, &g_vm_hwq, sizeof(Quat))) q = g_vm_hbq;
            g_vm_hbq = q;
            Quat T = vm_axis_angle(g_vm_tilt_ax, g_vm_tilt_cur * 0.0174533f);
            Quat nq = quat_norm(quat_mul(quat_mul(quat_mul(quat_conj(*hdq), T), *hdq), q));
            g_oldnode_setori(hb, &nq); g_oldnode_needupd(hb, 1);
            g_vm_hwq = nq; g_vm_h_written = 1;
        }
    } else g_vm_h_written = 0;
    g_vm_applied++;
}

static void hooked_vm_setanim(void *skel, const void *set, float w, const void *bmap)
{
    g_vm_setanim_orig(skel, set, w, bmap);
    if (!skel || skel != g_vm_skel || g_vm_dead || g_vm_R.w > 0.99999f) return;
    g_vm_calls++;
    /* May run nested inside a guarded caller (the camera weld): save and
     * restore the guard so a fault here doesn't strand the caller's jmp_buf. */
    jmp_buf saved; memcpy(saved, g_guard_jb, sizeof(jmp_buf));
    int was = g_guard_armed; DWORD wtid = g_guard_tid;
    if (setjmp(g_guard_jb)) {
        g_vm_dead = 1; g_vm_R = (Quat){ 1, 0, 0, 0 };
        logline("[vm] apply FAULTED -- viewmodel disabled");
    } else {
        guard_arm(); vm_apply(skel);
    }
    memcpy(g_guard_jb, saved, sizeof(jmp_buf));
    g_guard_tid = wtid; g_guard_armed = was;
}

static void vm_install(HMODULE ogre)
{
    void *t = ogre ? (void *)GetProcAddress(ogre, OGRE_OSI_SETANIM_SYM) : NULL;
    if (!t || !g_skel_getbone || !g_oldnode_getori || !g_oldnode_setori || !g_oldnode_needupd
        || !g_oldnode_getdori || !g_oldnode_getdpos || !g_oldnode_getparent || !g_get_bone_world
        || !g_oldnode_getpos || !g_oldnode_setpos) {
        logline("[vm] viewmodel unavailable (setAnimationState=%p)", t); return;
    }
    g_vm_hooked = install_hook(t, (void *)hooked_vm_setanim, (void **)&g_vm_setanim_orig);
    logline(g_vm_hooked ? "[vm] viewmodel hook installed (Skeleton::setAnimationState)"
                        : "[vm] viewmodel hook FAILED");
}

/* orthonormal basis from a lateral vector and an up-ish vector */
static int vm_basis(Vec3 lat, Vec3 up, Vec3 e[3])
{
    e[0] = vm_norm(lat);
    Vec3 u = vm_sub(up, vm_mul(e[0], vm_dot(up, e[0])));
    if (vm_len(u) < 1e-4f || vm_len(lat) < 1e-4f) return 0;
    e[1] = vm_norm(u);
    e[2] = vm_cross(e[0], e[1]);
    return 1;
}

static void vm_ease_off(float dt)
{
    float a = dt / (dt + 0.15f);
    g_vm_R = quat_norm(quat_slerp(g_vm_R, (Quat){ 1, 0, 0, 0 }, a));
    if (g_vm_R.w > 0.99999f) g_vm_R = (Quat){ 1, 0, 0, 0 };
}

/* Per camera frame, after the eye/orientation are final. */
static void vm_frame(void *pc, int body_down)
{
    static LARGE_INTEGER f, last;
    LARGE_INTEGER now; QueryPerformanceCounter(&now);
    if (!f.QuadPart) QueryPerformanceFrequency(&f);
    float dt = last.QuadPart ? (float)(now.QuadPart - last.QuadPart) / (float)f.QuadPart : 0.0f;
    last = now;
    if (dt > 0.1f) dt = 0.1f;
    if (!g_vm_hooked || g_vm_dead) return;
    vm_names();
    g_vm_frames++;

    const char *st = g_fpc_ui_state ? g_fpc_ui_state : "off";
    int ti = -1, hold = 0, on = 1;
    int was_swing = g_vm_swing; g_vm_swing = 0;
    if      (!strcmp(st, "ready"))      ti = VM_READY;
    else if (!strcmp(st, "aiming"))     ti = VM_AIM;
    else if (!strcmp(st, "reloading"))  ti = VM_RELOAD;
    else if (!strcmp(st, "blocking"))   ti = VM_BLOCK;
    else if (!strcmp(st, "swinging"))   { ti = VM_READY; g_vm_swing = 1; }
    else if (!strcmp(st, "recovering")) {    /* "swinging" lasts ~0.1 s; the swing anim runs on through recovering */
        ti = VM_READY;
        int fs_run = g_fpc_fs_prog > 0.0f && g_fpc_fs_prog < 1.0f;
        int fs_stale = !(g_fpc_fs_prog > 0.0f && g_fpc_fs_prog <= 1.0f);
        if (was_swing && (fs_run || (fs_stale && g_vm_swt < g_vm_sw_dur))) g_vm_swing = 1;
    }
    else if (!strcmp(st, "staggered"))  hold = 1;
    else on = 0;                                       /* holstered/down/off/none */
    if (!g_cfg_vm || !g_fp_mode || !pc || body_down || !g_have_eye) on = 0;
    int posed = g_vm_sw_pose >= 0.0f && ti == VM_READY && !g_vm_swing;
    if (posed) g_vm_swing = 1;
    g_vm_state = st; g_vm_hold = hold;
    /* arc progress: the free swing's own anim progress when it advances (game time, any game speed), else
     * real time over sw_dur (native combat swings) */
    if (g_vm_swing) {
        if (!was_swing) { g_vm_swt = 0.0f; g_vm_swings++; }
        else g_vm_swt += dt;
        float pu = g_fpc_fs_prog > 0.0f && g_fpc_fs_prog <= 1.0f ? g_fpc_fs_prog : -1.0f;
        g_vm_swu = posed ? fminf(1.0f, g_vm_sw_pose) : pu >= 0.0f ? pu : fminf(1.0f, g_vm_swt / g_vm_sw_dur);
    } else {
        if (was_swing) logline("[vm] swing #%lu %.2fs u_end=%.2f prog=%.2f", (unsigned long)g_vm_swings, g_vm_swt, g_vm_swu, g_fpc_fs_prog);
        g_vm_swt = g_vm_swu = 0.0f;
    }

    void *skel = NULL;
    if (pc) {
        void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8) ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
        skel = readable(anim, ANIM_SKELETON + 8) ? *(void **)((uintptr_t)anim + ANIM_SKELETON) : NULL;
    }
    if (skel != g_vm_skel) { g_vm_have_written[0] = g_vm_have_written[1] = 0; g_vm_R = (Quat){ 1, 0, 0, 0 }; }
    g_vm_skel = skel;
    if (!skel) return;

    /* measure (world = game coords): hand, shoulders, clavicles + spine in world and skeleton space */
    Vec3 h, hb[2], sh[2], cw[2], spw, cs[2], sps;
    int ok = 1;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; ok = 0; }
    else {
        guard_arm();
        g_get_bone_world(pc, &hb[0], g_vm_nm_hand[0]);
        g_get_bone_world(pc, &hb[1], g_vm_nm_hand[1]);
        for (int i = 0; i < 2; i++) {
            g_get_bone_world(pc, &sh[i], g_vm_nm_arm[i]);
            g_get_bone_world(pc, &cw[i], g_vm_nm_clav[i]);
            void *cb = g_skel_getbone(skel, g_vm_nm_clav[i]);
            const Vec3 *d = readable(cb, 8) ? g_oldnode_getdpos(cb) : NULL;
            if (!readable((void *)d, 12)) ok = 0; else cs[i] = *d;
        }
        g_get_bone_world(pc, &spw, g_vm_nm_spine);
        void *sb = g_skel_getbone(skel, g_vm_nm_spine);
        const Vec3 *d = readable(sb, 8) ? g_oldnode_getdpos(sb) : NULL;
        if (!readable((void *)d, 12)) ok = 0; else sps = *d;
        g_guard_armed = 0;
    }
    if (!ok) { g_vm_basis_ok = 0; return; }

    /* eye is Ogre-world (floating origin); bone world is game coords = ogre - (g_tx,0,g_tz) */
    Vec3 eye = { g_last_eye.x - g_tx, g_last_eye.y, g_last_eye.z - g_tz };
    float cp = cosf(g_pitch), sp = sinf(g_pitch), cy = cosf(g_yaw), sy = sinf(g_yaw);
    Vec3 fw = { sy*cp, -sp, cy*cp };                   /* g_pitch>0 = looking down */
    Vec3 up = { sy*sp, cp, cy*sp };                    /* fw rotated 90 deg up */
    Vec3 rt = vm_cross(fw, up);
    for (int i = 0; i < 2; i++) {
        Vec3 w = vm_sub(hb[i], eye);
        g_vm_he[i] = atan2f(vm_dot(w, up), vm_dot(w, fw)) * 57.29578f;
        g_vm_ha[i] = atan2f(vm_dot(w, rt), vm_dot(w, fw)) * 57.29578f;
    }
    h = hb[g_vm_hand ? 1 : 0];
    Vec3 v = vm_sub(h, eye);
    g_vm_elev = atan2f(vm_dot(v, up), vm_dot(v, fw)) * 57.29578f;
    g_vm_az   = atan2f(vm_dot(v, rt), vm_dot(v, fw)) * 57.29578f;

    if (!on) { vm_ease_off(dt); return; }
    if (hold) return;
    g_vm_target_e = g_vm_te[ti]; g_vm_target_a = g_vm_ta[ti];
    if (g_vm_swing && g_vm_melee) {
        float u = g_vm_swu * g_vm_swu * (3.0f - 2.0f * g_vm_swu);
        g_vm_target_e = g_vm_sw[0] + (g_vm_sw[2] - g_vm_sw[0]) * u;
        g_vm_target_a = g_vm_sw[1] + (g_vm_sw[3] - g_vm_sw[1]) * u;
    }

    /* skeleton <-> world basis (lateral = clavicle line, up = spine -> clavicle midpoint) */
    Vec3 ew[3], es[3];
    Vec3 cmw = vm_mul(vm_add(cw[0], cw[1]), 0.5f), cms = vm_mul(vm_add(cs[0], cs[1]), 0.5f);
    g_vm_basis_ok = vm_basis(vm_sub(cw[1], cw[0]), vm_sub(cmw, spw), ew)
                 && vm_basis(vm_sub(cs[1], cs[0]), vm_sub(cms, sps), es);
    if (!g_vm_basis_ok) return;
    {   /* tilt: camera-right mapped into skeleton space; melee = weapon in hands is not the ranged weapon */
        Vec3 rb = { vm_dot(rt, ew[0]), vm_dot(rt, ew[1]), vm_dot(rt, ew[2]) };
        g_vm_tilt_ax = vm_add(vm_add(vm_mul(es[0], rb.x), vm_mul(es[1], rb.y)), vm_mul(es[2], rb.z));
        void *wih = readable((void *)((uintptr_t)pc + CHAR_WEAPON_IN_HANDS), 8) ? *(void **)((uintptr_t)pc + CHAR_WEAPON_IN_HANDS) : NULL;
        void **vt = readable(pc, 8) ? *(void ***)pc : NULL;
        void *rw = readable((void *)((uintptr_t)vt + 0x3D0), 8) ? ((void *(*)(void *))vt[0x3D0/8])(pc) : NULL;
        g_vm_melee = wih && wih != rw;
        float tt = g_vm_melee ? g_vm_tilt[ti] : 0.0f;
        if (g_vm_swing && g_vm_melee) {
            float u = g_vm_swu * g_vm_swu * (3.0f - 2.0f * g_vm_swu);
            tt = g_vm_sw[4] + (g_vm_sw[5] - g_vm_sw[4]) * u;
        }
        g_vm_tilt_cur += (tt - g_vm_tilt_cur) * (dt / (dt + g_vm_tau));
    }

    /* target ray from the eye; point on it at the hand's current reach from the shoulder midpoint */
    float te = g_vm_target_e * 0.0174533f, ta = g_vm_target_a * 0.0174533f;
    Vec3 dir = vm_norm(vm_add(vm_add(vm_mul(fw, cosf(te) * cosf(ta)), vm_mul(up, sinf(te))),
                              vm_mul(rt, cosf(te) * sinf(ta))));
    Vec3 c = vm_mul(vm_add(sh[0], sh[1]), 0.5f);
    Vec3 hc = vm_sub(h, c);
    float r = vm_len(hc);
    Vec3 ec = vm_sub(eye, c);
    float bq = vm_dot(dir, ec), cq = vm_dot(ec, ec) - r*r, disc = bq*bq - cq;
    float s = disc >= 0.0f ? -bq + sqrtf(disc) : -bq;            /* far root / closest approach */
    if (s < 0.0f) s = 0.0f;
    Vec3 tc = vm_sub(vm_add(eye, vm_mul(dir, s)), c);

    /* world rotation hc -> tc, smoothed fraction, mapped into skeleton space */
    Vec3 a1 = vm_norm(hc), a2 = vm_norm(tc);
    Vec3 ax = vm_cross(a1, a2);
    float sn = vm_len(ax), cs_ = vm_dot(a1, a2);
    if (sn < 1e-5f) return;
    float ang = atan2f(sn, cs_);
    float tau = ti == VM_RELOAD ? g_vm_tau_rl : (g_vm_swing && g_vm_melee) ? 0.03f : g_vm_tau;
    ang *= dt / (dt + tau);
    Vec3 k = vm_mul(ax, 1.0f / sn);
    Vec3 kb = { vm_dot(k, ew[0]), vm_dot(k, ew[1]), vm_dot(k, ew[2]) };
    Vec3 ks = vm_add(vm_add(vm_mul(es[0], kb.x), vm_mul(es[1], kb.y)), vm_mul(es[2], kb.z));
    Quat R = quat_norm(quat_mul(vm_axis_angle(ks, ang), g_vm_R));
    float tot = 2.0f * acosf(fminf(1.0f, fabsf(R.w))) * 57.29578f;
    if (tot <= g_vm_maxdeg) g_vm_R = R;
    g_vm_ang = 2.0f * acosf(fminf(1.0f, fabsf(g_vm_R.w))) * 57.29578f;
}

static int vm_set(const char *k, float x)
{
    for (int i = 0; i < VM_NT; i++) {
        char e[24], a[24];
        snprintf(e, sizeof(e), "%s_e", g_vm_tname[i]); snprintf(a, sizeof(a), "%s_a", g_vm_tname[i]);
        if (!strcmp(k, e)) { g_vm_te[i] = x; return 1; }
        if (!strcmp(k, a)) { g_vm_ta[i] = x; return 1; }
    }
    if (!strcmp(k, "tau"))    { if (x > 0.01f && x < 2) g_vm_tau = x; return 1; }
    if (!strcmp(k, "taurl"))  { if (x > 0.01f && x < 3) g_vm_tau_rl = x; return 1; }
    if (!strcmp(k, "max"))    { g_vm_maxdeg = x; return 1; }
    if (!strncmp(k, "tilt_", 5)) {
        for (int i = 0; i < VM_NT; i++) if (!strcmp(k + 5, g_vm_tname[i])) { g_vm_tilt[i] = x; return 1; }
        return 0;
    }
    {   static const char *const swk[6] = { "sw_e0", "sw_a0", "sw_e1", "sw_a1", "sw_t0", "sw_t1" };
        for (int i = 0; i < 6; i++) if (!strcmp(k, swk[i])) { g_vm_sw[i] = x; return 1; }
        if (!strcmp(k, "sw_pose")) { g_vm_sw_pose = x; return 1; }
        if (!strcmp(k, "sw_dur")) { if (x > 0.05f && x < 2) g_vm_sw_dur = x; return 1; } }
    if (!strcmp(k, "hand"))   { g_vm_hand = x != 0.0f; g_vm_R = (Quat){ 1, 0, 0, 0 }; return 1; }
    return 0;
}

static int vm_ini(const char *line)
{
    int v; float fv;
    if (ini_int(line, "viewmodel", &v)) { g_cfg_vm = !!v; return 1; }
    for (int i = 0; i < VM_NT; i++) {
        char e[32], a[32];
        snprintf(e, sizeof(e), "vm_%s_e", g_vm_tname[i]); snprintf(a, sizeof(a), "vm_%s_a", g_vm_tname[i]);
        if (ini_float(line, e, &fv)) { g_vm_te[i] = fv; return 1; }
        if (ini_float(line, a, &fv)) { g_vm_ta[i] = fv; return 1; }
    }
    if (ini_float(line, "vm_tau", &fv)) { vm_set("tau", fv); return 1; }
    if (ini_int(line, "vm_hand", &v)) { g_vm_hand = !!v; return 1; }
    return 0;
}

static int kah_fp_vm(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)u;
    char b[900];
    const char *a = argc > 1 ? argv[1] : "state";
    if (!strcmp(a, "on"))  { g_cfg_vm = 1; g_vm_dead = 0; }
    else if (!strcmp(a, "off")) g_cfg_vm = 0;
    else if (!strcmp(a, "set") && argc > 3) {
        if (!vm_set(argv[2], (float)atof(argv[3]))) {
            r->append(r, "keys: ready_e ready_a aim_e aim_a reload_e reload_a block_e block_a tau taurl max hand(0=L,1=R) tilt_ready tilt_aim tilt_reload tilt_block sw_e0 sw_a0 sw_e1 sw_a1 sw_t0 sw_t1 sw_dur sw_pose(-1 off)");
            return KAH_ERROR;
        }
    } else if (strcmp(a, "state")) { r->append(r, "usage: fp_vm state|on|off|set <key> <value>"); return KAH_ERROR; }
    snprintf(b, sizeof(b),
        "vm on=%d hooked=%d dead=%d state=%s hold=%d ang=%.1f elev=%.1f az=%.1f target=%.1f,%.1f basis=%d "
        "hand=%c lh=%.1f,%.1f rh=%.1f,%.1f melee=%d tilt=%.1f swing=%d swu=%.2f swings=%d "
        "calls=%lu applied=%lu reuse=%lu frames=%lu "
        "ready=%.0f,%.0f aim=%.0f,%.0f reload=%.0f,%.0f block=%.0f,%.0f tau=%.2f max=%.0f",
        g_cfg_vm, g_vm_hooked, g_vm_dead, g_vm_state, g_vm_hold, g_vm_ang, g_vm_elev, g_vm_az,
        g_vm_target_e, g_vm_target_a, g_vm_basis_ok,
        g_vm_hand ? 'R' : 'L', g_vm_he[0], g_vm_ha[0], g_vm_he[1], g_vm_ha[1], g_vm_melee, g_vm_tilt_cur, g_vm_swing, g_vm_swu, g_vm_swings, g_vm_calls, g_vm_applied, g_vm_reuse, g_vm_frames,
        g_vm_te[0], g_vm_ta[0], g_vm_te[1], g_vm_ta[1], g_vm_te[2], g_vm_ta[2], g_vm_te[3], g_vm_ta[3],
        g_vm_tau, g_vm_maxdeg);
    r->append(r, b);
    return KAH_OK;
}
