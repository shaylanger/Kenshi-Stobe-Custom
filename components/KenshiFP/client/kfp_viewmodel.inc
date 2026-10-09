/* kfp_viewmodel.inc -- FP "viewmodel" presentation layer (PT13/PT14/PT17, rework PT26-PT29).
 *
 * Kenshi's combat animations hold the weapon at hip height and out to the side, outside a first-person view.
 * This layer poses the arms the way FP games do (Skyrim/KCD): the WEAPON gets a pose fixed in the camera
 * frame per state (position of its grip + blade/bolt direction + its roll), and both arms reach it by
 * analytic two-bone IK (upper arm + forearm, elbow toward a pole, forearm twist shared with the wrist).
 *  - sword: ready = blade up-forward right of center; block = blade horizontal across the view; swing =
 *    a procedural path (wind-up top right -> strike through the center -> follow-through bottom left ->
 *    back to ready, Catmull-Rom through key poses, progress = the swing animation's own progress).
 *  - crossbow: ready = held low right pointing forward; aim = stock to the shoulder, limbs horizontal,
 *    bolt toward the crosshair; reload = lowered nose-down in front (not in the face); fire = short kick.
 *  - zoom (PT29): the pose is built from the UNZOOMED eye (fp_view anchor), so zooming out only moves the
 *    camera: the body keeps the same hold.
 * The off-hand keeps its native transform relative to the weapon while the native animation holds the
 * weapon two-handed (crossbow grip) and sits on a support point on the crossbow (ranged) / a rest point
 * out of view (one-handed sword).
 *
 * Where: Entity::_updateAnimation calls the VIRTUAL Skeleton::setAnimationState(set, float, map) right
 * before the bone matrices are built. The hook calls the original (native pose), then rewrites the local
 * orientations of UpperArm, Forearm, Hand on both sides (skeleton space). vm_frame (per camera frame)
 * builds the targets in the camera frame, maps them into skeleton space (basis from the clavicles + spine
 * measured in both spaces) and leaves them for the hook. Open loop: no feedback lag, no fighting the
 * native swing.
 *
 * Weapon axes: the weapon hangs off "Bip01 Prop1/2" (child of the L/R hand). Which local prop axis is the
 * blade/bolt (f) and which is the edge/top (u) is per weapon class (ax_* keys, probed in game: fp_vm probe).
 *
 * Single translation unit: included from kenshifp_client.c. Tuning: harness `fp_vm`, ini keys viewmodel / vm_*. */

typedef void (*osi_setanim_t)(void *skel, const void *stateset, float w, const void *bmap);
#define OGRE_OSI_SETANIM_SYM "?setAnimationState@Skeleton@Ogre@@UEAAXAEBVAnimationStateSet@2@MAEBV?$map@V?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@_NU?$less@V?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@@2@V?$STLAllocator@U?$pair@$$CBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@_N@std@@V?$CategorisedAllocPolicy@$0A@@Ogre@@@Ogre@@@std@@@Z"

enum { VM_READY, VM_AIM, VM_RELOAD, VM_BLOCK, VM_NT };
static const char *const g_vm_tname[VM_NT] = { "ready", "aim", "reload", "block" };

/* A weapon pose in camera numbers: x = right, y = up, z = forward (world units, dm, from the unzoomed eye).
 * p = grip (prop bone origin), f = weapon forward (blade tip / bolt), u = weapon up (sword edge / crossbow top). */
typedef struct { Vec3 p, f, u; } VmPose;
#define VP(px,py,pz,fx,fy,fz,ux,uy,uz) { {px,py,pz}, {fx,fy,fz}, {ux,uy,uz} }
/* [class 0 = melee, 1 = ranged][state] */
static VmPose g_vm_pose[2][VM_NT] = {
    /* calibrated in game 2026-10-08 (FOV 70 vertical; the HUD covers y/z < ~-0.33; arm reach ~4.5 dm) */
    /* sword: grips at z >= 4.6 (PT17: 4.0 left the wrist at z 3.4, the arm mesh sliced open by the plane) so the wrist (~0.5 behind the grip) stays in front of the 3 dm near clip (at z 2.8-3.2 the
     * cuff was cut off mid-screen: floating glove, C2); ready raised clear of the HUD buttons (C4) */
    { VP( 2.8f,-1.05f,4.6f,  -0.35f, 0.85f, 0.40f,   -0.5f, 0.0f, 0.85f),    /* sword ready: blade up-forward, right */
      VP( 2.8f,-1.05f,4.6f,  -0.35f, 0.85f, 0.40f,   -0.5f, 0.0f, 0.85f),    /* (aim = ready) */
      VP( 2.8f,-1.05f,4.6f,  -0.35f, 0.85f, 0.40f,   -0.5f, 0.0f, 0.85f),    /* (reload = ready) */
      VP( 2.2f,-0.35f,4.6f,  -1.00f, 0.08f, 0.22f,    0.0f, 0.3f, 1.0f) },   /* sword block: blade across the view in front of
                                                                              * the face (hilt upper right, Chivalry 2 parry); was chest-high (y -0.8) */
    /* crossbow (Chivalry 2 reference, 2026-10-08): the right hand is either wholly in front of the 3 dm near clip (ready,
     * reload: grip z >= 4.4, the hand shows the hold) or wholly behind it (aim: grip at the eye plane, no hand/arm in view,
     * the glove shards at z 2.0-2.8 are gone). Model measured 2026-10-08 (3 grip depths): limbs 3.87 f + 1.0 u, half
     * span 3.2 dm, bolt tip ~5.85 f + 1.0 u (the old 5.0/0.84/1.7 numbers were wrong). The spring routes every
     * hidden <-> visible change below the view (vm_xwp) so the hand never crosses the near plane on screen. */
    { VP( 2.6f,-1.5f, 4.4f,  -0.30f,-0.25f, 0.92f,    0.0f, 1.0f, 0.0f),     /* ready: low carry at the right hip, nose down-left 15 deg, limbs
                                                                              * just below the centre (y/z ~ -0.1); grip bottom y/z -0.29 keeps the whole
                                                                              * bow above the HUD line -0.33 (at y -1.5 the hand sat under it, PT28) */
      VP( 0.00f,-1.80f,0.10f, 0.00f, 0.00f, 1.00f,    0.0f, 1.0f, 0.0f),     /* aim: grip at the eye plane (hand/arm hidden), limbs at z ~4 span
                                                                              * ~65 % of the half width, level, lower third (y/z -0.2), bolt tip at
                                                                              * -0.16 just under the crosshair (Chivalry 2 photo: tip ~ -0.17) */
      VP( 1.6f,-1.1f, 4.8f,  -0.40f,-0.30f, 0.87f,   -0.915f,0.19f,-0.356f), /* reload: lowered, nose down-left 25 deg, rolled ~70 deg to the left so
                                                                              * the top faces the eye (u is orthogonal to f: the old 0.15,0.75,-0.5
                                                                              * was nearly anti-parallel and ended top-up-and-away, uz +0.28, PT28) */
      VP( 2.6f,-1.5f, 4.4f,  -0.30f,-0.25f, 0.92f,    0.0f, 1.0f, 0.0f) } }; /* (block = ready) */
/* sword swing key poses, 0.6 dm deeper and the strike/follow-through 0.45-0.5 dm lower than before PT17: a centred wrist
 * at the old height left the forearm no way off the bottom edge before the near plane (elbow search failed, cut cuff).
 * (the path starts at the pose the swing began from and ends at the ready pose) */
/* u = edge, leads the motion (about the difference of the neighbouring keys' blade directions) */
#define VM_SWK 5
static VmPose g_vm_swk[VM_SWK] = {
    VP( 3.0f, 0.5f, 4.6f,   0.22f, 0.88f, 0.22f,   -0.20f,-0.40f, 0.30f),  /* wind-up, raised top right, blade cocked back-right (out at the
                                                                            * top-right corner), arm in from the right edge */
    VP( 1.3f,-0.45f,4.8f,  -0.55f, 0.45f, 0.70f,   -0.30f,-1.20f, 0.45f),  /* strike: blade diagonal up-left */
    VP( 0.4f,-0.6f, 4.8f,  -0.92f, 0.02f, 0.38f,    0.00f,-1.00f, 0.05f),  /* strike: blade sweeps flat across the center (in view) */
    VP(-0.6f,-0.9f, 4.6f,  -0.90f,-0.18f, 0.40f,    0.20f,-0.95f,-0.05f),  /* follow-through left, blade still in view above the HUD */
    VP( 0.9f,-1.55f,4.6f,  -0.55f, 0.30f, 0.78f,    0.10f,-0.90f, 0.40f) };/* recovery: dips low (grip just above the HUD) back to the guard,
                                                                            * no second sweep across the view */
/* key times (start, keys, end), own clock over g_vm_sw_dur: anticipation (slower wind-up) ~30%, fast strike across
 * ~20%, follow-through decel, low recovery to the guard (reference: 1H melee 0.4-0.8 s, Chivalry/KCD-style) */
static float g_vm_swk_u[VM_SWK + 2] = { 0.0f, 0.28f, 0.38f, 0.47f, 0.58f, 0.78f, 1.0f };
static int   g_vm_ax[2][2] = { { 2, 3 }, { 2, -1 } }; /* crossbow up = -X: the native aim holds it so (bolt above the grip) */  /* [class][f,u]: prop-local axis 1..3 = X,Y,Z, <0 = negative (probed in game) */
static int   g_vm_whand[2] = { 1, 1 };                /* [class] weapon hand: 0 = L (Prop1), 1 = R (Prop2) */
static Vec3  g_vm_rest = { -2.6f, -5.5f, 1.2f };      /* off-hand rest (one-handed melee), camera numbers */
static Vec3  g_vm_sup = { 1.6f, -0.5f, 0.4f };        /* aim: off-hand under the fore-stock, f,u,s weapon numbers (s = left);
                                                        * within reach of the bent arm (4.8 was 1.1 dm out of reach: oerr); 1.6 keeps the
                                                        * fingers behind the near clip in the eye-plane aim (3.6 put the glove at z 3.4) */
/* elbow pole [class][L,R], camera numbers; ranged R points out right so the forearm stays out of the aim view */
static Vec3  g_vm_pole[2][2] = { { { -0.8f, -1.0f, -0.4f }, { 0.8f, -1.0f, -0.4f } },
                                 { { -0.5f, -1.5f, 0.0f }, { 1.2f, -1.2f, -0.2f } } };
static float g_vm_fire_hold = 0.45f;                  /* after a shot: keep the aim pose this long before reloading (> kick) */
/* motion: every pose change runs through a critically damped spring (smooth start AND end, velocity carried over
 * from a swing / kick into the next move; exact solution, frame-rate independent); omega = 1.8 / tau */
static VmPose g_vm_vel; static Vec3 g_vm_ocv;
static float g_vm_maxdt = 0.05f;                       /* animation step cap: a hitch frame must not jump the weapon */
static float g_vm_om_draw = 16.0f;                     /* draw rise / holster lowering */
/* draw / holster: the weapon rises from below the view on a draw and is lowered out of it on a holster; the
 * native<->viewmodel blend (w) only runs while the weapon is below the view */
enum { VMP_NORMAL, VMP_DRAW, VMP_LOWER };
static int   g_vm_phase; static float g_vm_ph_t, g_vm_wl, g_vm_lower_dur = 0.30f;
static VmPose g_vm_low[2] = {
    { { 1.6f,-7.0f, 4.2f }, { -0.20f,-0.75f, 0.63f }, { -0.5f, 0.0f, 0.85f } },   /* sword: grip + blade below the view (blade
                                                                                 * down: the native draw blade points forward, its tip flashed in at y/z -0.55, s8 71).
                                                                                 * PT17: in front of the near clip (was z 2.0: the holster drop crossed the arm tube band
                                                                                 * at y/z -0.55, forearm cut open, PT30 cut=1); y -7 so the blade tip is off the bottom
                                                                                 * edge when the sheathe takes the sword after the 0.3 s lowering (y -5.5: tip at -0.65) */
    { { 1.5f,-4.5f, 4.4f }, { -0.20f,-0.60f, 0.77f }, {  0.0f, 1.0f, 0.0f } } };  /* crossbow: below the view at the ready depth
                                                                                 * (PT17: at z 2.0 the hand sat behind the 3 dm near clip while the bow
                                                                                 * rose into view = a bow floating without a hand; now the draw/holster
                                                                                 * is a straight rise/drop with the hand in front of the plane) */
static float g_vm_kick_t = -1.0f, g_vm_kick_rise = 0.06f;   /* fire kick: time since the shot; rise (ease-out) then smooth return */
static int g_vm_rlnat = 1; static float g_vm_rlw, g_vm_rltr = 0.5f, g_vm_rlblend = 0.2f, g_vm_rl_dy = 0.0f;
static Vec3 g_vm_rl_p0; static int g_vm_have_rl0;   /* X3 native reload: weight, bow start pos (skeleton) */
static float g_vm_rl_t; static float g_vm_rl_per = 1.3f, g_vm_rl_amp = 1.0f;  /* reload: time in reload, spanning cycle period (amp 1.6 dipped the hand behind the HUD) */
/* ranged near-plane routing: while the current grip and the target grip lie on different sides of the near clip (zc),
 * the spring heads for a waypoint below the view (y g_vm_xwp_y, z = zc -/+ g_vm_xwp_dz on the target's side) so the hand
 * and the stock cross the near plane under the bottom edge; once both are on the same side the real target takes over.
 * Reads as a dip-and-raise (ready -> aim, aim -> reload), like raising a crossbow from a low carry. */
static int   g_vm_xwp_on = 1; static float g_vm_xwp_y = -3.6f, g_vm_xwp_dz = 1.0f, g_vm_xwp_tol = 0.8f; static int g_vm_xwp;
static Quat  g_vm_plc; static int g_vm_pl_n;           /* prop local: candidate for a lasting native change */
static float g_vm_fire_t;
static int   g_vm_ti = -1;                     /* weapon pose state of the last update (VM_*) */
/* baked prop locals (Prop2 under the R hand, measured 2026-10-08 in steady holds): [0] = the native ready / block
 * local (sword and crossbow ready share it: it comes from the anim), [1] = the native crossbow AIM local (hand on
 * the grip handle). The crossbow always uses [1] (plfix): the native local swings ~97 deg between ready and aim and
 * jumps at a draw (bow coming off the back), which moved the hand around the bow / threw the bow into the face. */
static Quat  g_vm_pldq[2] = { { 0.600f, 0.267f, 0.724f, -0.211f }, { 0.656f, 0.195f, 0.084f, -0.725f } };
static Vec3  g_vm_pldp[2] = { { 0.737f, 0.180f, -0.299f }, { 0.693f, 0.201f, -0.510f } };
static float g_vm_groll[2] = { 60.0f, 0.0f };  /* [class] grip roll, deg (sword 60: fingers behind the hilt, reads as a fist): turns the hand around the hilt (about the
                                                * blade/bolt axis, prop origin fixed); Kenshi hands have no finger bones */
static float g_vm_plsl[2] = { 1.0f, 0.0f };   /* [class] grip slide, dm: the weapon sits this far toward the tip in the
                                                * hand (the hand holds nearer the pommel; the hand stays at the pose). Sword: the long katana handle stuck out ~1.1 dm
                                                * past the little finger as a grey cylinder, its end cut by the near clip (e4 211-216); 0.7 still left a pommel stub in the block */
static int   g_vm_plfix = 3;   /* bit 0 crossbow, bit 1 sword: the native swing anims move the katana in the hand (the
                                 * changed local lasted > 8 frames and was taken: the hilt slid out of the closed fingers,
                                 * open-hand look, C1); the sword keeps the ready-hold grip */
static Quat  g_vm_plq[2]; static Vec3 g_vm_plp[2]; static int g_vm_have_pl[2];  /* [class] steady prop local (outside reload);
                                                * kept across draws: a draw straight into a reload used the native reload local */
static float g_vm_oerr;                       /* measured off-hand wrist - its target, dm (PT28) */
static Vec3  g_vm_oc; static int g_vm_have_oc;   /* off-hand target (smoothed), camera numbers */
static float g_vm_off_near = 3.5f;                    /* native off-hand within this of the weapon grip = 2-handed */
static float g_vm_aim_dist = 400.0f;                  /* aim: the bolt converges on the crosshair at this range */
static float g_vm_tau = 0.08f, g_vm_tau_rl = 0.15f, g_vm_tau_w = 0.12f;
static float g_vm_twist = 0.5f;                       /* share of the wrist twist the forearm takes */
static float g_vm_kick_dur = 0.30f;                    /* kick return time */
static Vec3  g_vm_kick_p = { 0.0f, 0.15f, -0.12f };   /* fire kick at its peak: grip offset, mostly muzzle climb (a 0.4 push back put the
                                                        * stock behind the near clip: the hand looked detached from the bow) */
static float g_vm_kick_up = 0.20f;

static osi_setanim_t g_vm_setanim_orig;
static int   g_cfg_vm = 1;                  /* ini viewmodel=0|1 */
static void *g_vm_skel;
static int   g_vm_dead, g_vm_hooked, g_vm_basis_ok, g_vm_hold, g_vm_names;
static const char *g_vm_state = "off";
static unsigned long g_vm_calls, g_vm_applied, g_vm_reuse, g_vm_frames, g_vm_ikfail;
static float g_vm_w;                        /* blend native -> viewmodel, 0..1 */
static int   g_vm_class;                    /* 0 melee, 1 ranged (last on state) */
static int g_vm_eclamp = 1, g_vm_eclamp_n; static float g_vm_ectol = 0.0f, g_vm_eclamp_eye;
static float g_vm_nc = 1.5f;               /* X2: near plane while the ranged viewmodel is shown (0 = off) */
static float vm_nearclip(float base) { return (g_vm_nc > 0.0f && g_vm_class == 1 && g_vm_w > 0.01f && base > g_vm_nc) ? g_vm_nc : base; }
static int   g_vm_melee;
static VmPose g_vm_cur;                     /* current weapon pose (camera numbers) */
static int   g_vm_have_cur;
/* targets for the hook (skeleton space) */
static Vec3  g_vm_tp, g_vm_tf, g_vm_tu;     /* weapon grip + axes */
static Vec3  g_vm_op;                       /* off-hand target (rest / support) */
static int   g_vm_omode;                    /* 0 rest (keep native hand ori), 1 native-relative if near / support */
static Vec3  g_vm_tpole[2];
static int   g_vm_have_t;
/* bone write bookkeeping: [side][0 ua,1 fa,2 ha] */
static Quat  g_vm_bq[2][3], g_vm_wq[2][3];
static int   g_vm_have_written[2];
/* upper-arm stretch (W1): a walking game hitch (one 0.1 s anim step) swings the shoulder ~2 dm back while the eye
 * stays ahead, so the weapon grip fell out of reach for that frame and jumped toward the camera. As FP viewmodel
 * rigs do, the UPPER arm (behind / below the view) lengthens just enough to keep the hand on its target; the
 * visible forearm and hand keep their length. g_vm_stretch = max upper-arm factor (1 = off). */
/* arm from the screen edge (C2): the camera near clip is 3 dm and the shoulder sits ~2 dm BEHIND the eye, so with the
 * natural arm the elbow (and often the wrist) is always behind the near plane: the forearm was cut off mid-screen and
 * the glove floated. As FP viewmodel rigs do, the weapon-hand ELBOW is placed so the arm leaves the view at an edge:
 * the forearm (natural length) runs from the wrist to a point outside the view frustum (or to where it crosses the
 * near plane outside the view); the upper arm (behind the near plane / outside the view) takes whatever length
 * reaches that elbow. Direction closest to g_vm_elbd (camera numbers, wrist -> elbow) that keeps every cut off
 * screen. Weight fades out with the zoom-out distance (the body is seen from behind there). */
static int   g_vm_elb[2] = { 1, 1 };                 /* [class] on (ranged too: the ready arm leaves at the right edge) */
static Vec3  g_vm_elbd = { 0.60f, -0.50f, -0.62f };  /* preferred wrist -> elbow direction (lower right, back) */
/* wrist (PT17, Shay 2026-10-09: the swing folded the wrist in half, up to 102 deg): for the sword the forearm follows the
 * arm (preferred elbow = blend of g_vm_elbd and the natural shoulder/elbow IK elbow, g_vm_elb_nat), kept on the cone
 * around the blade where the hand holds it with a straight wrist (half angle = the grip's hand-X/blade angle, ~50 deg,
 * +-g_vm_wband), and the blade ROLL follows the forearm (g_vm_wroll): the hand stays in line with the forearm, so the
 * swing is carried by the shoulder and elbow. g_vm_wfix 0 = the 0750f26a behaviour (fixed elbow direction, keyed roll). */
static int   g_vm_wfix = 1; static float g_vm_wband = 12.0f, g_vm_elb_nat = 0.0f, g_vm_wroll = 1.0f, g_vm_hcos = 0.64f;
/* zoom out (PT29, Shay 2026-10-09: zoomed out the eye-relative hold put the hand at the side of the head): the viewmodel
 * is a first-person device, so it fades out between g_vm_zf0 and g_vm_zf1 dm of camera distance and the body plays the
 * native third-person animations (natural hold/swing seen from outside). g_vm_zfade 0 = the old eye-relative hold. */
static int   g_vm_zfade = 1; static float g_vm_zf0 = 2.0f, g_vm_zf1 = 8.0f, g_vm_zf = 1.0f;
static unsigned char g_vm_nm_head[32], g_vm_nm_neck[32]; static Vec3 g_vm_mhd, g_vm_mnk, g_vm_msp;   /* head/neck/spine, camera numbers */
static float g_vm_elb_fx = 1.245f, g_vm_elb_fy = 0.700f, g_vm_elb_m = 0.45f, g_vm_elb_zc = 3.0f, g_vm_elb_zoom = 4.0f;
static float g_vm_elb_r = 0.55f;   /* arm mesh radius (forearm + gauntlet), dm: the near plane slices the TUBE, not its axis. With
                                    * only the axis kept in front, the plane cut the near side of the glove/forearm open on screen
                                    * (hollow arch, dark inside + lit rim: PT17 sword follow-through f3i_434-440, ready cuff) */
static float g_vm_elb_stmax = 3.0f, g_vm_elb_tau = 0.04f;
/* swing->block cap (Shay 2026-10-09, option-stretch.jpg): ready and block keep the full cap g_vm_elb_stmax; only the block
 * entered by aborting a swing (the high-elbow moment, upper-arm stretch 2.87) gets the cap g_vm_swb_cap, blended in/out
 * over g_vm_swb_tau s (no pop). g_vm_swb = that block is on, g_vm_swb_w = blend 0..1, vm_stmax() = the cap in use. */
static float g_vm_swb_cap = 1.3f, g_vm_swb_tau = 0.12f, g_vm_swb_trig = 99.0f, g_vm_s2_want, g_vm_swb_w; static int g_vm_swb;
static float vm_stmax(void) { return g_vm_elb_stmax + (fminf(g_vm_swb_cap, g_vm_elb_stmax) - g_vm_elb_stmax) * g_vm_swb_w; }
/* S1 (Shay 2026-10-09): the sword edge never faces the camera. kappa = grip constant (hand X -> edge, about the blade),
 * edge_tol = largest allowed cos(edge, wrist->eye). S2: re-seed the elbow pick on entering block / ready. */
static int   g_vm_edge = 1, g_vm_have_ekap, g_vm_reseed_on = 1, g_vm_rsmode = -1, g_vm_edge_nok;
static float g_vm_edge_tol = 0.0f, g_vm_ekap, g_vm_edge_pred, g_vm_reseed, g_vm_reseed_dur = 0.25f, g_vm_reseed_tau = 0.05f;
static float g_vm_hroll = 0.0f;   /* option A (Shay decision 2026-10-09): extra sword hand+blade roll about the blade, deg (0 = off) */
static float g_vm_elb_keep = 1.5f, g_vm_elb_rate = 1750.0f, g_vm_elb_dmax = 24.0f, g_vm_elb_ptau = 0.03f;
/* wrist look-ahead (PT30): predicted output poses of the next frames + coarse DP over their passing elbows */
#define VM_LAH 12
#define VM_LAA 24
static int   g_vm_elb_la = 1, g_vm_elb_lah = 8, g_vm_fut_n, g_vm_la_n, g_vm_la_c[VM_LAH]; static unsigned g_vm_fid, g_vm_la_fid = 0xffffffffu;
static float g_vm_elb_lama = 12.0f, g_vm_elb_lawm = 0.1f, g_vm_sw_ur;
static VmPose g_vm_fut[VM_LAH]; static Vec3 g_vm_la_e[VM_LAH][VM_LAA * 7]; static float g_vm_la_cc[VM_LAH][VM_LAA * 7];
static Vec3  g_vm_rbe = { -0.740f, -0.546f, 0.392f };   /* PT30-FLIP: swing-ready elbow branch, output-pose frame (f,u,f x u) */
static float g_vm_rbw = 0.5f, g_vm_rbwr = 0.5f;          /* its weight in the elbow pick while drawing / at ready (0 = off); 2.0 while
                                                          * drawing spun the blade ~260 deg over 0.6 s after every draw (m78 f8) */
static int   g_vm_wrlwarm = 1;   /* roll refinement starts from last frame's roll (PT30) */
static float g_vm_wrl = 2.2f, g_vm_wrlmin = 2.6f, g_vm_wrllag = 6.0f, g_vm_rs, g_vm_rsv, g_vm_rs_lag; static int g_vm_have_rs;   /* roll jerk limit (0 = off) */
static unsigned g_vm_pk[4];   /* wrist picks: within the rate step, 2x, 4x, anywhere */   /* + max pick speed deg/s, max cone offset deg */   /* wrist fix: weight of the previous elbow in the straight-wrist pick (no flips) */
static Vec3  g_vm_pick; static int g_vm_pick_ok;   /* wrist fix: this frame's elbow pick (camera space), made with the blade roll */
static Vec3  g_vm_elbe; static int g_vm_have_elbe, g_vm_elb_ok; static float g_vm_elb_w, g_vm_elb_wz;
static float g_vm_l1n[2]; static void *g_vm_b0[2]; static int g_vm_l1fix = 1;
static int g_vm_fptol = 1; static float g_vm_stdb = 0.0f, g_vm_st_prev[2] = { 1.0f, 1.0f };
static unsigned long g_vm_fp_exact, g_vm_fp_near, g_vm_fp_nat, g_vm_fp_long;
static float g_vm_stretch = 1.6f, g_vm_st_last[2] = { 1.0f, 1.0f }, g_vm_st_max[2] = { 1.0f, 1.0f };
static Vec3  g_vm_fpn[2], g_vm_fpw[2]; static int g_vm_fpw_on[2];
static int   g_vm_hitch_ms, g_vm_hitch_per, g_vm_hitch_n;   /* test: forced game hitch (ms) every N frames (0 = once) */
static unsigned char g_vm_nm_arm[2][32], g_vm_nm_fore[2][32], g_vm_nm_hand[2][32], g_vm_nm_prop[2][32];
static unsigned char g_vm_nm_clav[2][32], g_vm_nm_spine[32];
/* native (pre-IK) snapshot from the hook, skeleton space: prop pos/ori, hand pos/ori per side */
static Vec3  g_vm_npp[2], g_vm_nhp[2]; static Quat g_vm_npq[2], g_vm_nhq[2]; static int g_vm_nat_ok;
static Quat  g_vm_orel; static int g_vm_have_orel;   /* off-hand ori relative to the weapon prop (native, last near) */
static Vec3  g_vm_oprel; static int g_vm_off_near_now;
/* diag (camera numbers / degrees) */
static float g_vm_elev, g_vm_az, g_vm_target_e, g_vm_target_a, g_vm_he[2], g_vm_ha[2];
static Vec3  g_vm_mj[2][3];                  /* measured [L,R][shoulder,elbow,wrist] camera numbers (PT28 arm-in-view check) */
static Vec3  g_vm_mp, g_vm_mf, g_vm_mu;     /* measured weapon grip + forward + up (edge / crossbow top), camera numbers */
static Vec3  g_vm_mh, g_vm_mfx, g_vm_mhy, g_vm_mhz; static float g_vm_wb;   /* measured weapon-hand bone X (toward the fingers) and forearm bone X,
                                                        * camera numbers; wrist bend = angle(elbow->wrist, hand X), deg (PT17) */
static float g_vm_tilt_cur;                 /* compat: blade rise above the view plane (deg) */
static int   g_vm_hand = 1;                 /* compat (state print): weapon hand of the current class */
/* swing */
static float g_vm_sw_dur = 0.62f, g_vm_swt, g_vm_swu; static int g_vm_sw_clock = 1;  /* 1 = own clock (not the native anim progress) */
static int   g_vm_swing, g_vm_swings;
static float g_vm_sw_pose = -1.0f;          /* test: >=0 freezes the swing path at this u while ready */
static VmPose g_vm_sw0;                     /* pose the swing started from */
static float g_vm_sw_maxstep, g_vm_sw_last_step; static Vec3 g_vm_sw_prevf; static int g_vm_sw_n, g_vm_sw_log = 1;
static float g_vm_sw_emin, g_vm_sw_emax, g_vm_sw_amin, g_vm_sw_amax;
static float g_vm_sw_rate[128], g_vm_sw_rmax, g_vm_sw_rmed;   /* blade angular speed per frame (deg/s): snap check */
/* fire kick */
static float g_vm_kick, g_vm_kick_pose = -1.0f; static unsigned g_vm_shots0; static int g_vm_kicks;
static float g_fpc_fs_prog;                 /* tentative decl; defined in kfp_controls.inc (free-swing anim progress 0..1) */
static const char *g_fpc_ui_state;          /* tentative decl; defined in kfp_controls.inc */
static unsigned g_combat_actual_shots;      /* tentative decl; defined in kfp_combat_native.inc */
static Vec3 g_vm_s2w[3]; static Vec3 g_vm_w2s[3]; static float g_vm_scale = 1.0f;   /* skel<->world map (rows) */
static Vec3 g_vm_cms, g_vm_cmw;
/* ---- per-frame recorder + frozen replay (every-frame animation review) ----
 * fp_vm rec on|off|dump <file>: one record per camera frame (vm_frame): time, dt, ui state, pose state, class, blend
 * w, swing u, kick, off-hand mode, the commanded pose (out) + off-hand target, the measured weapon pose and both
 * arms' shoulder/elbow/wrist (camera numbers; measured in frame n = what frame n-1 rendered).
 * fp_vm replay <n> [t]|off: holds recorded frame n on screen (w=1): the measured pose of n (= record n+1's
 * measurement), or with t the commanded pose; the off-hand goes to the recorded hand position. */
typedef struct { float t, dt; char st[12]; signed char ti; unsigned char cls, swing, omode, on;
                 float w, swu, prog, kick, fire, yaw, pitch, zoom;
                 VmPose out; Vec3 oc; Vec3 mp, mf, mu; Vec3 mj[2][3]; Vec3 eye, rt, up, fw; Vec3 rootf, roota; unsigned napp; unsigned char phase, wih; float stch; Vec3 mh, mfx; float wb, zf; Vec3 hd, nk, sp, hy, hz; } VmRec;
#define VM_RECN 6000
static VmRec *g_vm_rec;   /* heap (on first rec on): a static 1.3 MB .bss made the plugin fail to load */ static int g_vm_rn, g_vm_rec_on; static LARGE_INTEGER g_vm_rec_t0;
static int g_vm_rp = -1, g_vm_rp_t;          /* replay frame (-1 off), 1 = commanded pose */
static float g_vm_fpscap;                    /* test: cap the frame rate (Hz, 0 off) */
static VmPose g_vm_out; static float g_vm_kick_eff, g_vm_dt;

static void vm_names(void)
{
    if (g_vm_names) return;
    make_mstr_long(g_vm_nm_arm[0], "Bip01 L UpperArm");   /* >=16 chars: heap strings, kept */
    make_mstr_long(g_vm_nm_arm[1], "Bip01 R UpperArm");
    make_mstr_long(g_vm_nm_clav[0], "Bip01 L Clavicle");
    make_mstr_long(g_vm_nm_clav[1], "Bip01 R Clavicle");
    make_mstr(g_vm_nm_fore[0], "Bip01 L Forearm");
    make_mstr(g_vm_nm_fore[1], "Bip01 R Forearm");
    make_mstr(g_vm_nm_spine, "Bip01 Spine");
    make_mstr(g_vm_nm_head, "Bip01 Head");
    make_mstr(g_vm_nm_neck, "Bip01 Neck");
    make_mstr(g_vm_nm_hand[0], "Bip01 L Hand");
    make_mstr(g_vm_nm_hand[1], "Bip01 R Hand");
    make_mstr(g_vm_nm_prop[0], "Bip01 Prop1");
    make_mstr(g_vm_nm_prop[1], "Bip01 Prop2");
    g_vm_names = 1;
}

static Vec3  vm_v(float x, float y, float z) { return (Vec3){ x, y, z }; }
static Vec3  vm_sub(Vec3 a, Vec3 b) { return (Vec3){ a.x-b.x, a.y-b.y, a.z-b.z }; }
static Vec3  vm_add(Vec3 a, Vec3 b) { return (Vec3){ a.x+b.x, a.y+b.y, a.z+b.z }; }
static Vec3  vm_mul(Vec3 a, float s) { return (Vec3){ a.x*s, a.y*s, a.z*s }; }
static float vm_dot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
static Vec3  vm_cross(Vec3 a, Vec3 b) { return (Vec3){ a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x }; }
static float vm_len(Vec3 a) { return sqrtf(vm_dot(a, a)); }
static Vec3  vm_norm(Vec3 a) { float l = vm_len(a); return l > 1e-6f ? vm_mul(a, 1.0f / l) : a; }
static Vec3  vm_lerp(Vec3 a, Vec3 b, float t) { return vm_add(a, vm_mul(vm_sub(b, a), t)); }
static Vec3  vm_axis(int code) { int a = code < 0 ? -code : code; float s = code < 0 ? -1.0f : 1.0f;
    return a == 1 ? vm_v(s, 0, 0) : a == 2 ? vm_v(0, s, 0) : vm_v(0, 0, s); }

/* proper rotation whose columns are (a, b', a x b') with b' = b orthogonalized against a */
static Quat vm_frame_quat(Vec3 a, Vec3 b)
{
    a = vm_norm(a); b = vm_norm(vm_sub(b, vm_mul(a, vm_dot(a, b))));
    Vec3 c = vm_cross(a, b);
    float m00 = a.x, m10 = a.y, m20 = a.z, m01 = b.x, m11 = b.y, m21 = b.z, m02 = c.x, m12 = c.y, m22 = c.z;
    float tr = m00 + m11 + m22; Quat q;
    if (tr > 0.0f) { float s = sqrtf(tr + 1.0f) * 2.0f; q = (Quat){ 0.25f*s, (m21-m12)/s, (m02-m20)/s, (m10-m01)/s }; }
    else if (m00 > m11 && m00 > m22) { float s = sqrtf(1.0f + m00 - m11 - m22) * 2.0f; q = (Quat){ (m21-m12)/s, 0.25f*s, (m01+m10)/s, (m02+m20)/s }; }
    else if (m11 > m22) { float s = sqrtf(1.0f + m11 - m00 - m22) * 2.0f; q = (Quat){ (m02-m20)/s, (m01+m10)/s, 0.25f*s, (m12+m21)/s }; }
    else { float s = sqrtf(1.0f + m22 - m00 - m11) * 2.0f; q = (Quat){ (m10-m01)/s, (m02+m20)/s, (m12+m21)/s, 0.25f*s }; }
    return quat_norm(q);
}
static Quat vm_fromto(Vec3 a, Vec3 b)
{
    a = vm_norm(a); b = vm_norm(b);
    float d = vm_dot(a, b);
    if (d < -0.9999f) {
        Vec3 o = fabsf(a.x) < 0.9f ? vm_v(1, 0, 0) : vm_v(0, 1, 0);
        Vec3 ax = vm_norm(vm_cross(a, o)); return (Quat){ 0, ax.x, ax.y, ax.z };
    }
    Vec3 c = vm_cross(a, b);
    return quat_norm((Quat){ 1.0f + d, c.x, c.y, c.z });
}
static VmPose vm_pose_norm(VmPose p)
{
    p.f = vm_norm(p.f);
    p.u = vm_norm(vm_sub(p.u, vm_mul(p.f, vm_dot(p.f, p.u))));
    return p;
}
/* draw start pose: the crossbow rises straight up into its ready pose (same x/z and orientation, from the low pose's
 * height, Shay 2026-10-09); the sword starts at g_vm_low (the holster lowers both to g_vm_low) */
static VmPose vm_draw_low(int cls)
{
    VmPose p = g_vm_low[cls];
    if (cls == 1) { p = g_vm_pose[1][VM_READY]; p.p.y = g_vm_low[1].p.y; }
    return vm_pose_norm(p);
}
static VmPose vm_pose_lerp(VmPose a, VmPose b, float t)
{
    VmPose r = { vm_lerp(a.p, b.p, t), vm_lerp(a.f, b.f, t), vm_lerp(a.u, b.u, t) };
    return vm_pose_norm(r);
}
/* Catmull-Rom on Vec3 with non-uniform key times (t0..t3, segment t1..t2) */
static Vec3 vm_cr(Vec3 p0, Vec3 p1, Vec3 p2, Vec3 p3, float t0, float t1, float t2, float t3, float t)
{
    float d12 = t2 - t1; if (d12 < 1e-4f) return p1;
    float s = (t - t1) / d12;
    Vec3 m1 = vm_mul(vm_sub(p2, p0), d12 / fmaxf(t2 - t0, 1e-4f));
    Vec3 m2 = vm_mul(vm_sub(p3, p1), d12 / fmaxf(t3 - t1, 1e-4f));
    float s2 = s*s, s3 = s2*s;
    float h00 = 2*s3 - 3*s2 + 1, h10 = s3 - 2*s2 + s, h01 = -2*s3 + 3*s2, h11 = s3 - s2;
    return vm_add(vm_add(vm_mul(p1, h00), vm_mul(m1, h10)), vm_add(vm_mul(p2, h01), vm_mul(m2, h11)));
}
/* swing path at u in [0,1]: start pose -> keys -> end pose */
static VmPose vm_swing_at(VmPose start, VmPose end, float u)
{
    VmPose k[VM_SWK + 2]; k[0] = start; for (int i = 0; i < VM_SWK; i++) k[i+1] = vm_pose_norm(g_vm_swk[i]); k[VM_SWK+1] = end;
    const float *t = g_vm_swk_u; int n = VM_SWK + 2;
    if (u <= 0.0f) return vm_pose_norm(start);
    if (u >= 1.0f) return vm_pose_norm(end);
    int i = 0; while (i < n - 2 && u > t[i+1]) i++;
    int a = i > 0 ? i - 1 : i, d = i + 2 < n ? i + 2 : i + 1;
    float ta = i > 0 ? t[a] : t[i] - (t[i+1] - t[i]), td = i + 2 < n ? t[d] : t[i+1] + (t[i+1] - t[i]);
    VmPose r;
    /* the start and end poses are at rest: phantom keys equal to the next key mirrored through them give a zero
     * tangent there (ease out of the guard into the wind-up, ease back into the guard) */
    VmPose ka = k[a], kd = k[d];
    if (i == 0) { ka.p = k[i+1].p; ka.f = k[i+1].f; ka.u = k[i+1].u; ta = t[i+1] - 2.0f * (t[i+1] - t[i]); }
    if (i + 2 >= n) { kd.p = k[i].p; kd.f = k[i].f; kd.u = k[i].u; td = t[i] + 2.0f * (t[i+1] - t[i]); }
    r.p = vm_cr(ka.p, k[i].p, k[i+1].p, kd.p, ta, t[i], t[i+1], td, u);
    r.f = vm_cr(ka.f, k[i].f, k[i+1].f, kd.f, ta, t[i], t[i+1], td, u);
    r.u = vm_cr(ka.u, k[i].u, k[i+1].u, kd.u, ta, t[i], t[i+1], td, u);
    return vm_pose_norm(r);
}

/* critically damped spring toward t: x(t) = t + (d + (v0 + om d) t) e^-om t (exact for a constant target) */
static void vm_spring3(Vec3 *x, Vec3 *v, Vec3 t, float om, float dt)
{
    Vec3 d = vm_sub(*x, t), B = vm_add(*v, vm_mul(d, om));
    float e = expf(-om * dt);
    Vec3 A = vm_add(d, vm_mul(B, dt));
    *x = vm_add(t, vm_mul(A, e));
    *v = vm_mul(vm_sub(B, vm_mul(A, om)), e);
}
static void vm_pose_spring(VmPose *c, VmPose *v, VmPose t, float om, float dt)
{
    vm_spring3(&c->p, &v->p, t.p, om, dt); vm_spring3(&c->f, &v->f, t.f, om, dt); vm_spring3(&c->u, &v->u, t.u, om, dt);
    *c = vm_pose_norm(*c);
}
/* fire kick envelope at time t since the shot: 0 -> 1 ease-out over the rise, then a smooth (cosine) return */
static float vm_kick_env(float t)
{
    if (t < 0.0f) return 0.0f;
    if (t < g_vm_kick_rise) return sinf(1.5707963f * t / g_vm_kick_rise);
    float r = (t - g_vm_kick_rise) / g_vm_kick_dur;
    return r >= 1.0f ? 0.0f : 0.5f * (1.0f + cosf(3.14159265f * r));
}
static float vm_qang(Quat a, Quat b)
{
    float d = fabsf(a.w*b.w + a.x*b.x + a.y*b.y + a.z*b.z); if (d > 1.0f) d = 1.0f;
    return 2.0f * acosf(d) * 57.29578f;
}

/* skeleton <-> world (game coords) */
static Vec3 vm_w2s_dir(Vec3 v) { return vm_mul(vm_v(vm_dot(v, g_vm_w2s[0]), vm_dot(v, g_vm_w2s[1]), vm_dot(v, g_vm_w2s[2])), 1.0f / g_vm_scale); }
static Vec3 vm_s2w_dir(Vec3 v) { return vm_mul(vm_v(vm_dot(v, g_vm_s2w[0]), vm_dot(v, g_vm_s2w[1]), vm_dot(v, g_vm_s2w[2])), g_vm_scale); }
static Vec3 vm_w2s_pos(Vec3 p) { return vm_add(g_vm_cms, vm_w2s_dir(vm_sub(p, g_vm_cmw))); }

/* upper-arm length (skeleton space) from the native forearm offset; derived positions may carry last frame's stretch */
static float vm_l1(void *ua, const Vec3 *ps, const Vec3 *pe)
{
    float d = vm_len(vm_sub(*pe, *ps));
    if (!g_vm_l1fix) return d;
    for (int i = 0; i < 2; i++) if (g_vm_l1n[i] > 1e-4f && g_vm_b0[i] == ua) return g_vm_l1n[i];
    return d;
}
/* two-bone IK on one arm, skeleton space. Ht/Qt = hand bone target (derived pos/ori); keep_ori = keep the
 * hand's native derived orientation instead of Qt. Writes local orientations blended by w. */
static int vm_ik(int side, void *ua, void *fa, void *ha, Vec3 Ht, Quat Qt, int keep_ori, Vec3 pole, float w,
                 const Vec3 *Et, float ew)
{
    void *cl = g_oldnode_getparent(ua);
    if (!readable(cl, 8)) return 0;
    const Quat *pc = g_oldnode_getdori(cl), *pua = g_oldnode_getdori(ua), *pfa = g_oldnode_getdori(fa), *pha = g_oldnode_getdori(ha);
    const Vec3 *ps = g_oldnode_getdpos(ua), *pe = g_oldnode_getdpos(fa), *ph = g_oldnode_getdpos(ha);
    if (!readable((void *)pc, 16) || !readable((void *)pua, 16) || !readable((void *)pfa, 16) || !readable((void *)pha, 16)
        || !readable((void *)ps, 12) || !readable((void *)pe, 12) || !readable((void *)ph, 12)) return 0;
    Quat Dc = *pc, Dua = *pua, Dfa = *pfa, Dh = *pha; Vec3 S = *ps, E = *pe, H = *ph;
    if (keep_ori) Qt = Dh;
    float L1 = vm_l1(ua, ps, pe), L2 = vm_len(vm_sub(H, E));
    if (L1 < 1e-4f || L2 < 1e-4f) return 0;
    Vec3 d = vm_sub(Ht, S); float D = vm_len(d);
    float st = 1.0f;
    if (g_vm_stretch > 1.0f && g_oldnode_setpos && w > 0.001f) {
        float need = D / 0.995f - L2;                     /* upper-arm length that reaches the target */
        if (need > L1) { st = fminf(need / L1, g_vm_stretch); st = 1.0f + (st - 1.0f) * fminf(w, 1.0f);
            if (g_vm_stdb > 0.0f && fabsf(st - g_vm_st_prev[side]) < g_vm_stdb) st = g_vm_st_prev[side];
            g_vm_st_prev[side] = st; L1 *= st; }
    }
    Vec3 n = D > 1e-5f ? vm_mul(d, 1.0f / D) : vm_norm(vm_sub(H, S));
    float dmin = fabsf(L1 - L2) + 0.02f * (L1 + L2), dmax = (L1 + L2) * 0.995f;
    if (D < dmin) D = dmin; if (D > dmax) D = dmax;
    float a = (L1*L1 - L2*L2 + D*D) / (2.0f * D), h = sqrtf(fmaxf(0.0f, L1*L1 - a*a));
    Vec3 pp = vm_sub(pole, vm_mul(n, vm_dot(pole, n)));
    if (vm_len(pp) < 1e-4f) { Vec3 ce = vm_sub(E, S); pp = vm_sub(ce, vm_mul(n, vm_dot(ce, n))); }
    pp = vm_norm(pp);
    Vec3 E2 = vm_add(S, vm_add(vm_mul(n, a), vm_mul(pp, h))), H2 = vm_add(S, vm_mul(n, D));
    if (Et && ew > 0.001f) {   /* elbow target (arm from the screen edge): upper arm S -> elbow at any length */
        float L1n = vm_l1(ua, ps, pe);
        Vec3 Ew = vm_lerp(E2, *Et, fminf(ew, 1.0f));
        Vec3 de = vm_sub(Ew, S); float le = vm_len(de);
        float s2 = le / L1n; if (side == 1) g_vm_s2_want = s2; if (s2 > vm_stmax()) s2 = vm_stmax(); if (s2 < 0.4f) s2 = 0.4f;
        E2 = vm_add(S, vm_mul(vm_norm(de), L1n * s2));
        H2 = vm_add(E2, vm_mul(vm_norm(vm_sub(Ht, E2)), L2));
        st = 1.0f + (s2 - 1.0f) * fminf(w, 1.0f);
        if (w < 0.999f) { E2 = vm_add(S, vm_mul(vm_norm(de), L1n * st)); H2 = vm_add(E2, vm_mul(vm_norm(vm_sub(Ht, E2)), L2)); }
    }
    Quat r1 = vm_fromto(vm_sub(E, S), vm_sub(E2, S));
    Quat Dua2 = quat_norm(quat_mul(r1, Dua));
    Vec3 v = quat_rotvec(r1, vm_sub(H, E));
    Quat r2 = vm_fromto(v, vm_sub(H2, E2));
    Quat Dfa2 = quat_norm(quat_mul(r2, quat_mul(r1, Dfa)));
    {   /* forearm takes a share of the wrist twist (about the forearm bone) */
        const Quat *plh = g_oldnode_getori(ha);
        Quat Lh = readable((void *)plh, 16) ? *plh : (Quat){ 1, 0, 0, 0 };
        Quat want = quat_mul(Qt, quat_conj(Lh));
        Quat dl = quat_norm(quat_mul(want, quat_conj(Dfa2)));
        Vec3 ax = vm_norm(vm_sub(H2, E2));
        float pr = dl.x*ax.x + dl.y*ax.y + dl.z*ax.z;
        Quat tw = quat_norm((Quat){ dl.w, ax.x*pr, ax.y*pr, ax.z*pr });
        if (tw.w < 0) tw = (Quat){ -tw.w, -tw.x, -tw.y, -tw.z };
        tw = quat_slerp((Quat){ 1, 0, 0, 0 }, tw, g_vm_twist);
        Dfa2 = quat_norm(quat_mul(tw, Dfa2));
    }
    Quat nl[3] = { quat_norm(quat_mul(quat_conj(Dc), Dua2)), quat_norm(quat_mul(quat_conj(Dua2), Dfa2)),
                   quat_norm(quat_mul(quat_conj(Dfa2), Qt)) };
    void *b[3] = { ua, fa, ha };
    for (int j = 0; j < 3; j++) {
        Quat q = w >= 0.999f ? nl[j] : quat_norm(quat_slerp(g_vm_bq[side][j], nl[j], w));
        g_oldnode_setori(b[j], &q); g_oldnode_needupd(b[j], 1);
        g_vm_wq[side][j] = q;
    }
    g_vm_have_written[side] = 1;
    g_vm_st_last[side] = st; if (st > g_vm_st_max[side]) g_vm_st_max[side] = st;
    if (fabsf(st - 1.0f) > 0.0001f) {                    /* forearm bone local position = upper-arm length */
        Vec3 fp = vm_mul(g_vm_fpn[side], st);
        g_oldnode_setpos(fa, &fp); g_oldnode_needupd(fa, 1);
        g_vm_fpw[side] = fp; g_vm_fpw_on[side] = 1;
    }
    return 1;
}

/* skeleton <-> world map from the clavicles + spine (world via getBoneWorldPosition, skeleton via derived pos).
 * Called in vm_frame (measurement) AND at apply time (setAnimationState): the character moves/turns and the anim
 * moves the torso between the camera callback and the anim update, so targets mapped with the camera-time map
 * landed off by one frame of root motion (walking: weapon 1-3 dm off, jumping with the gait) and by the torso
 * snap at a swing start. Mapping at apply time pins the weapon to the camera. */
static int vm_basis(Vec3 lat, Vec3 up, Vec3 e[3]);
static Vec3 vm_c2w_pos(Vec3 c); static Vec3 vm_c2w_dir(Vec3 c);
static void *g_vm_pc; static int g_vm_applymap = 1, g_vm_in_map, g_vm_wih; static unsigned long g_vm_napply;
static Vec3 g_vm_root_f, g_vm_root_a;
static int char_position(void *c, Vec3 *out);
static int g_vm_mapnode = 1, g_vm_have_moff; static Vec3 g_vm_moff; static float g_vm_map_res, g_vm_map_resmax; static unsigned long g_vm_map_node_n, g_vm_map_fb_n;
/* X1: exact map from the body entity's scene node: world = Pn + Qn * (Sn * skel). Returns 1 when used. */
static int vm_map_node(void *pc, Vec3 cms, Vec3 cmw_meas)
{
    if (!g_vm_mapnode || !g_node_getdori_v || !g_node_getdpos_v || !g_node_getdscale_v || !g_get_parent_scenenode || g_anim_ent_off < 0) return 0;
    void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8) ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
    if (!readable((void *)((uintptr_t)anim + g_anim_ent_off), 8)) return 0;
    void *ent = *(void **)((uintptr_t)anim + g_anim_ent_off);
    if (!readable(ent, 0x100)) return 0;
    void *node = g_get_parent_scenenode(ent);
    if (!readable(node, 0x100)) return 0;
    Quat q; Vec3 pn, sn; g_node_getdori_v(node, &q); g_node_getdpos_v(node, &pn); g_node_getdscale_v(node, &sn);
    q = quat_norm(q);
    if (sn.x < 1e-4f || fabsf(sn.y - sn.x) > 1e-3f * sn.x || fabsf(sn.z - sn.x) > 1e-3f * sn.x) return 0;
    Vec3 c[3] = { quat_rotvec(q, vm_v(1, 0, 0)), quat_rotvec(q, vm_v(0, 1, 0)), quat_rotvec(q, vm_v(0, 0, 1)) };
    Vec3 cmo = vm_add(pn, vm_mul(quat_rotvec(q, cms), sn.x)), off = vm_sub(cmw_meas, cmo);
    g_vm_map_res = g_vm_have_moff ? vm_len(vm_sub(off, g_vm_moff)) : 0.0f;
    if (!g_vm_have_moff || g_vm_map_res > 0.05f) { g_vm_moff = off; g_vm_have_moff = 1; }   /* origin shift / first frame */
    else if (g_vm_map_res > g_vm_map_resmax) g_vm_map_resmax = g_vm_map_res;
    Vec3 cmw = vm_add(cmo, g_vm_moff);
    for (int k = 0; k < 3; k++) {
        g_vm_w2s[k] = c[k];
        g_vm_s2w[k] = vm_v(k == 0 ? c[0].x : k == 1 ? c[0].y : c[0].z, k == 0 ? c[1].x : k == 1 ? c[1].y : c[1].z, k == 0 ? c[2].x : k == 1 ? c[2].y : c[2].z);
    }
    g_vm_scale = sn.x; g_vm_cms = cms; g_vm_cmw = cmw;
    return 1;
}
static int vm_map(void *pc, void *skel)
{
    Vec3 cw[2], spw, cs[2], sps, ew[3], es[3];
    for (int i = 0; i < 2; i++) {
        g_get_bone_world(pc, &cw[i], g_vm_nm_clav[i]);
        void *cb = g_skel_getbone(skel, g_vm_nm_clav[i]);
        const Vec3 *d = readable(cb, 8) ? g_oldnode_getdpos(cb) : NULL;
        if (!readable((void *)d, 12)) return 0;
        cs[i] = *d;
    }
    g_get_bone_world(pc, &spw, g_vm_nm_spine);
    {   void *sb = g_skel_getbone(skel, g_vm_nm_spine);
        const Vec3 *d = readable(sb, 8) ? g_oldnode_getdpos(sb) : NULL;
        if (!readable((void *)d, 12)) return 0;
        sps = *d; }
    Vec3 cmw = vm_mul(vm_add(cw[0], cw[1]), 0.5f), cms = vm_mul(vm_add(cs[0], cs[1]), 0.5f);
    if (!vm_basis(vm_sub(cw[1], cw[0]), vm_sub(cmw, spw), ew) || !vm_basis(vm_sub(cs[1], cs[0]), vm_sub(cms, sps), es)) return 0;
    float ls = vm_len(vm_sub(cs[1], cs[0]));
    g_vm_scale = ls > 1e-6f ? vm_len(vm_sub(cw[1], cw[0])) / ls : 1.0f;
    /* w2s rows: skeleton component k of a world vector = sum_i es_i[k] * dot(v, ew_i) */
    g_vm_w2s[0] = vm_v(0, 0, 0); g_vm_w2s[1] = g_vm_w2s[0]; g_vm_w2s[2] = g_vm_w2s[0];
    g_vm_s2w[0] = g_vm_w2s[0]; g_vm_s2w[1] = g_vm_w2s[0]; g_vm_s2w[2] = g_vm_w2s[0];
    for (int i = 0; i < 3; i++) {
        float es_[3] = { es[i].x, es[i].y, es[i].z }, ew_[3] = { ew[i].x, ew[i].y, ew[i].z };
        for (int k = 0; k < 3; k++) {
            g_vm_w2s[k] = vm_add(g_vm_w2s[k], vm_mul(ew[i], es_[k]));
            g_vm_s2w[k] = vm_add(g_vm_s2w[k], vm_mul(es[i], ew_[k]));
        }
    }
    g_vm_cms = cms; g_vm_cmw = cmw;
    if (vm_map_node(pc, cms, cmw)) g_vm_map_node_n++; else g_vm_map_fb_n++;
    return 1;
}
/* commanded pose (camera numbers: g_vm_out, off-hand g_vm_oc, poles) -> skeleton-space IK targets */
static void vm_targets(void)
{
    g_vm_tp = vm_w2s_pos(vm_c2w_pos(g_vm_out.p));
    g_vm_tf = vm_norm(vm_w2s_dir(vm_c2w_dir(g_vm_out.f)));
    g_vm_tu = vm_norm(vm_w2s_dir(vm_c2w_dir(g_vm_out.u)));
    g_vm_op = vm_w2s_pos(vm_c2w_pos(g_vm_oc));
    for (int i = 0; i < 2; i++) g_vm_tpole[i] = vm_norm(vm_w2s_dir(vm_c2w_dir(g_vm_pole[g_vm_class][i])));
}

/* Runs inside setAnimationState, after the original posed the skeleton. */
static float vm_elbow(void *ua, void *fa, void *ha, Vec3 Ph, Vec3 *Et);
static int vm_elb_pref(void *ua, void *fa, void *ha, Vec3 Ph, Vec3 *d0o);
static void vm_apply(void *skel)
{
    void *b[2][4];                       /* ua fa ha prop */
    for (int i = 0; i < 2; i++) {
        b[i][0] = g_skel_getbone(skel, g_vm_nm_arm[i]); b[i][1] = g_skel_getbone(skel, g_vm_nm_fore[i]);
        b[i][2] = g_skel_getbone(skel, g_vm_nm_hand[i]); b[i][3] = g_skel_getbone(skel, g_vm_nm_prop[i]);
        for (int j = 0; j < 4; j++) if (!readable(b[i][j], 8)) return;
        if (g_oldnode_getparent(b[i][2]) != b[i][1] || g_oldnode_getparent(b[i][1]) != b[i][0]) { g_vm_ikfail++; return; }
        /* bone not reset since our last write (another layer skipped a frame): restore the native local first,
         * never stack on our own output */
        for (int j = 0; j < 3; j++) {
            const Quat *lq = g_oldnode_getori(b[i][j]);
            if (!readable((void *)lq, 16)) return;
            Quat q = *lq;
            if (g_vm_have_written[i] && !memcmp(&q, &g_vm_wq[i][j], sizeof(Quat))) {
                q = g_vm_bq[i][j]; g_oldnode_setori(b[i][j], &q); g_oldnode_needupd(b[i][j], 1); g_vm_reuse++;
            }
            g_vm_bq[i][j] = q;
        }
        {   const Vec3 *fpp = g_oldnode_getpos(b[i][1]);
            if (!readable((void *)fpp, 12)) return;
            Vec3 fp = *fpp;
            int ours = g_vm_fpw_on[i] && !memcmp(&fp, &g_vm_fpw[i], sizeof(Vec3));
            if (ours) g_vm_fp_exact++;
            else if (g_vm_fpw_on[i] && g_vm_fptol) {   /* X1: our write came back changed by float noise, or a stale stretched pos: never adopt it as native */
                float lw = vm_len(g_vm_fpw[i]), ln = vm_len(g_vm_fpn[i]), lf = vm_len(fp);
                if (vm_len(vm_sub(fp, g_vm_fpw[i])) <= 1e-3f * fmaxf(lw, 1e-3f)) { ours = 1; g_vm_fp_near++; }
                else if (ln > 1e-4f && lf > ln * 1.01f && vm_dot(fp, g_vm_fpn[i]) > 0.999f * lf * ln) { ours = 1; g_vm_fp_long++; }
                else g_vm_fp_nat++;
            }
            if (ours && g_oldnode_setpos) {
                fp = g_vm_fpn[i]; g_oldnode_setpos(b[i][1], &fp); g_oldnode_needupd(b[i][1], 1);
            }
            g_vm_fpw_on[i] = 0; g_vm_fpn[i] = fp; g_vm_st_last[i] = 1.0f;
        }
    }
    /* native snapshot */
    for (int i = 0; i < 2; i++) {
        const Quat *hq = g_oldnode_getdori(b[i][2]), *lpq = g_oldnode_getori(b[i][3]);
        const Vec3 *hp = g_oldnode_getdpos(b[i][2]), *lpp = g_oldnode_getpos(b[i][3]);
        const Vec3 *hs = g_oldnode_getdscale ? g_oldnode_getdscale(b[i][2]) : NULL;
        if (!readable((void *)hq, 16) || !readable((void *)lpq, 16) || !readable((void *)hp, 12) || !readable((void *)lpp, 12)) return;
        Vec3 sc = readable((void *)hs, 12) ? *hs : vm_v(1, 1, 1), lp = *lpp;
        g_vm_nhq[i] = *hq; g_vm_nhp[i] = *hp;
        {   const Vec3 *us = g_oldnode_getdscale ? g_oldnode_getdscale(b[i][0]) : NULL;
            float k = readable((void *)us, 12) ? us->x : 1.0f;
            g_vm_b0[i] = b[i][0]; g_vm_l1n[i] = vm_len(g_vm_fpn[i]) * k; }
        g_vm_npq[i] = quat_norm(quat_mul(*hq, *lpq));
        g_vm_npp[i] = vm_add(*hp, quat_rotvec(*hq, vm_v(lp.x*sc.x, lp.y*sc.y, lp.z*sc.z)));
    }
    g_vm_nat_ok = 1;
    float we = g_vm_w * g_vm_zf;                         /* zoomed out: native animation (PT29) */
    if (!g_vm_have_t || we <= 0.001f) return;
    if (g_vm_applymap && g_vm_pc && !g_vm_in_map) {      /* re-map the targets with this update's root + torso */
        g_vm_in_map = 1;
        if (vm_map(g_vm_pc, skel)) { vm_targets(); g_vm_napply++; }
        char_position(g_vm_pc, &g_vm_root_a);
        g_vm_in_map = 0;
    }
    int wh = g_vm_whand[g_vm_class] ? 1 : 0, oh = !wh;
    /* weapon prop target -> weapon hand target */
    Quat Qp = quat_norm(quat_mul(vm_frame_quat(g_vm_tf, g_vm_tu),
                                 quat_conj(vm_frame_quat(vm_axis(g_vm_ax[g_vm_class][0]), vm_axis(g_vm_ax[g_vm_class][1])))));
    const Quat *lpq = g_oldnode_getori(b[wh][3]); const Vec3 *lpp = g_oldnode_getpos(b[wh][3]);
    float rlr = (g_vm_rlnat && g_vm_class == 1) ? g_vm_rlw : 0.0f; rlr = rlr * rlr * (3.0f - 2.0f * rlr);
    const Vec3 *hs = g_oldnode_getdscale ? g_oldnode_getdscale(b[wh][2]) : NULL;
    Vec3 sc = readable((void *)hs, 12) ? *hs : vm_v(1, 1, 1), lp = *lpp;
    Quat lq = *lpq;
    /* crossbow reload: the native anim moves the prop off the hand (bow down to the stirrup, up to 4 dm away), so
     * the hand could not bring it to the reload pose (it flew through the view). Keep the prop on the hand as in
     * the ready/aim holds (last local seen outside reload). */
    /* Also any one-frame native change of the prop local (the crossbow rolled 90 deg for a frame at a holster
     * start) and the holster lowering: the prop keeps its last steady local; a new local is taken only when it
     * lasts 8 frames (another weapon / grip). */
    {   int pc_ = g_vm_class ? 1 : 0;
        int frz = (g_vm_class == 1 && g_vm_ti == VM_RELOAD) || g_vm_phase == VMP_LOWER;
        if (!g_vm_have_pl[pc_] || (g_vm_plfix & (pc_ ? 1 : 2))) {
            g_vm_plq[pc_] = quat_norm(g_vm_pldq[pc_]); g_vm_plp[pc_] = g_vm_pldp[pc_]; g_vm_have_pl[pc_] = 1;
            if (g_vm_plfix & (pc_ ? 1 : 2)) frz = 1;
        }
        if (!frz) {
            if (!g_vm_have_pl[pc_] || (vm_qang(lq, g_vm_plq[pc_]) < 6.0f && vm_len(vm_sub(lp, g_vm_plp[pc_])) < 0.15f)) {
                g_vm_plq[pc_] = lq; g_vm_plp[pc_] = lp; g_vm_have_pl[pc_] = 1; g_vm_pl_n = 0;
            } else {
                if (g_vm_pl_n > 0 && vm_qang(lq, g_vm_plc) < 2.0f) g_vm_pl_n++; else { g_vm_plc = lq; g_vm_pl_n = 1; }
                if (g_vm_pl_n >= 8) { g_vm_plq[pc_] = lq; g_vm_plp[pc_] = lp; g_vm_pl_n = 0; } else frz = 1;
            }
        }
        if (frz && g_vm_have_pl[pc_] && g_oldnode_setpos && we >= 0.5f) {
            Quat lqn = lq; Vec3 lpn = lp;
            lq = g_vm_plq[pc_]; lp = g_vm_plp[pc_];
            if (rlr > 0.0f) { lq = quat_norm(quat_slerp(lq, lqn, rlr)); lp = vm_lerp(lp, lpn, rlr); }   /* X3: native prop local */
            if (g_vm_groll[pc_] != 0.0f) {
                float h = g_vm_groll[pc_] * 0.0087266f; Vec3 ax = vm_axis(g_vm_ax[pc_][0]);
                lq = quat_norm(quat_mul(lq, (Quat){ cosf(h), ax.x * sinf(h), ax.y * sinf(h), ax.z * sinf(h) }));
            }
            if (g_vm_plsl[pc_] != 0.0f && g_vm_scale > 1e-6f) {
                float sk = fabsf(sc.y) > 1e-3f ? sc.y : 1.0f;
                lp = vm_add(lp, vm_mul(quat_rotvec(lq, vm_axis(g_vm_ax[pc_][0])), g_vm_plsl[pc_] / (g_vm_scale * sk)));
            }
            g_oldnode_setori(b[wh][3], &lq); g_oldnode_setpos(b[wh][3], &lp); g_oldnode_needupd(b[wh][3], 1);
        }
    }
    if (g_vm_wfix && g_vm_class == 0) {   /* wrist (PT17): roll the blade about itself so the hand lines up with the forearm */
        Vec3 fax = vm_axis(g_vm_ax[0][0]), hx0 = vm_norm(quat_rotvec(quat_conj(lq), vm_v(1, 0, 0)));
        g_vm_hcos = vm_dot(hx0, fax);
        g_vm_pick_ok = 0;
        if (g_vm_wroll > 0.0f) {   /* aim at this frame's preferred elbow (the wrist moves with the roll: refine twice) */
            Vec3 f = vm_norm(g_vm_tf); Quat Qp0 = Qp; float pst = 0.0f;
            if (g_vm_wrlwarm && g_vm_wrl > 0.0f && g_vm_have_rs) {   /* warm start from last frame's roll */
                float h0 = 0.5f * g_vm_rs; pst = g_vm_rs;
                Qp = quat_norm(quat_mul((Quat){ cosf(h0), f.x * sinf(h0), f.y * sinf(h0), f.z * sinf(h0) }, Qp0));
            }
            for (int it = 0; it < 2; it++) {
                Quat Qh0 = quat_norm(quat_mul(Qp, quat_conj(lq))); Vec3 dc;
                Vec3 Ph0 = vm_sub(g_vm_tp, quat_rotvec(Qh0, vm_v(lp.x*sc.x, lp.y*sc.y, lp.z*sc.z)));
                int pr = vm_elb_pref(b[wh][0], b[wh][1], b[wh][2], Ph0, &dc);
                g_vm_pick_ok = pr == 2; g_vm_pick = dc;
                if (!pr) break;
                Vec3 a = vm_norm(vm_w2s_dir(vm_c2w_dir(vm_mul(dc, -1.0f))));
                Vec3 hx = vm_norm(quat_rotvec(Qh0, vm_v(1, 0, 0)));
                Vec3 hp = vm_sub(hx, vm_mul(f, vm_dot(hx, f))), ap = vm_sub(a, vm_mul(f, vm_dot(a, f)));
                if (vm_len(hp) < 1e-3f || vm_len(ap) < 1e-3f) break;
                float psi = atan2f(vm_dot(f, vm_cross(hp, ap)), vm_dot(hp, ap)) * fminf(g_vm_wroll, 1.0f) * 0.5f;   /* half angle */
                Qp = quat_norm(quat_mul((Quat){ cosf(psi), f.x * sinf(psi), f.y * sinf(psi), f.z * sinf(psi) }, Qp)); pst += 2.0f * psi;
            }
            if (g_vm_wrl > 0.0f) {   /* roll jerk limit (PT30): each step at most wrl x the last one (min wrlmin deg), lag <= wrllag deg */
                float dtc = fminf(fmaxf(g_vm_dt, 0.004f), g_vm_maxdt);
                if (!g_vm_have_rs) { g_vm_rs = pst; g_vm_rsv = 0.0f; g_vm_have_rs = 1; g_vm_rs_lag = 0.0f; }
                else { float dl = pst - g_vm_rs; while (dl > 3.14159265f) dl -= 6.2831853f; while (dl < -3.14159265f) dl += 6.2831853f;
                    float lim = fmaxf(g_vm_wrl * fabsf(g_vm_rsv) * dtc, g_vm_wrlmin * 0.0174533f), st = fmaxf(-lim, fminf(lim, dl));
                    {   float lg = g_vm_wrllag * 0.0174533f; if (dl - st > lg) st = dl - lg; else if (dl - st < -lg) st = dl + lg;   }   /* lag cap: the wrist bends at most wrllag deg */
                    g_vm_rs += st; g_vm_rsv = st / dtc; g_vm_rs_lag = fabsf(dl - st) * 57.29578f; }
                float h = 0.5f * g_vm_rs; Qp = quat_norm(quat_mul((Quat){ cosf(h), f.x * sinf(h), f.y * sinf(h), f.z * sinf(h) }, Qp0));
            } else g_vm_have_rs = 0;
        }
    }
    if (g_vm_class == 0 && g_vm_eclamp) {   /* S1: the edge never faces the camera */
        Vec3 bf = vm_norm(quat_rotvec(Qp, vm_axis(g_vm_ax[0][0]))), be = quat_rotvec(Qp, vm_axis(g_vm_ax[0][1]));
        Vec3 to = vm_norm(vm_sub(vm_w2s_pos(vm_c2w_pos(vm_v(0, 0, 0))), g_vm_tp));
        Vec3 tp_ = vm_sub(to, vm_mul(bf, vm_dot(to, bf))), ep = vm_sub(be, vm_mul(bf, vm_dot(be, bf)));
        float lt = vm_len(tp_), le_ = vm_len(ep);
        if (lt > 1e-3f && le_ > 1e-3f) {
            tp_ = vm_mul(tp_, 1.0f / lt); ep = vm_mul(ep, 1.0f / le_);
            float c = vm_dot(ep, tp_) * lt, tol = g_vm_ectol;
            g_vm_eclamp_eye = c;
            if (c > tol && lt > fabsf(tol)) {
                float th0 = atan2f(vm_dot(bf, vm_cross(tp_, ep)), vm_dot(tp_, ep));   /* edge angle from the eye dir */
                float thw = acosf(fmaxf(-1.0f, fminf(1.0f, tol / lt)));             /* allowed |angle| >= thw */
                float d = (th0 >= 0.0f ? thw : -thw) - th0, h = 0.5f * d;
                Qp = quat_norm(quat_mul((Quat){ cosf(h), bf.x * sinf(h), bf.y * sinf(h), bf.z * sinf(h) }, Qp));
                g_vm_eclamp_n++;
            }
        }
    }
    Quat Qh = quat_norm(quat_mul(Qp, quat_conj(lq)));
    Vec3 Ph = vm_sub(g_vm_tp, quat_rotvec(Qh, vm_v(lp.x*sc.x, lp.y*sc.y, lp.z*sc.z)));
    if (g_vm_class == 0 && g_vm_hroll != 0.0f) {   /* option A: roll the hand (and the blade with it) about the forearm axis at the wrist: palm turns, wrist stays straight, the blade moves */
        Vec3 hx = vm_norm(quat_rotvec(Qh, vm_v(1, 0, 0))); float h = g_vm_hroll * 0.0087266f;
        Qh = quat_norm(quat_mul((Quat){ cosf(h), hx.x * sinf(h), hx.y * sinf(h), hx.z * sinf(h) }, Qh)); }
    if (g_vm_class == 0) {   /* S1: grip constant kappa = angle about the blade from the hand X axis to the edge */
        Quat Qpf = quat_norm(quat_mul(Qh, lq));
        Vec3 bf = vm_norm(quat_rotvec(Qpf, vm_axis(g_vm_ax[0][0]))), be = quat_rotvec(Qpf, vm_axis(g_vm_ax[0][1]));
        Vec3 hx = quat_rotvec(Qh, vm_v(1, 0, 0));
        Vec3 hp = vm_sub(hx, vm_mul(bf, vm_dot(hx, bf))), ep = vm_sub(be, vm_mul(bf, vm_dot(be, bf)));
        if (vm_len(hp) > 1e-3f && vm_len(ep) > 1e-3f) { g_vm_ekap = atan2f(vm_dot(bf, vm_cross(hp, ep)), vm_dot(hp, ep)); g_vm_have_ekap = 1; }
    }
    /* off-hand */
    Vec3 Po = g_vm_op; Quat Qo = g_vm_nhq[oh]; int keep = 1;
    {   Vec3 dn = vm_sub(g_vm_nhp[oh], g_vm_npp[wh]);
        g_vm_off_near_now = g_vm_scale * vm_len(dn) < g_vm_off_near;
        if (g_vm_off_near_now) {
            g_vm_orel = quat_norm(quat_mul(quat_conj(g_vm_npq[wh]), g_vm_nhq[oh]));
            g_vm_oprel = quat_rotvec(quat_conj(g_vm_npq[wh]), dn); g_vm_have_orel = 1;
        }
        /* ranged: the off-hand always holds the support point; its orientation follows the weapon as in the
         * native 2-handed grip (last seen near) */
        if (g_vm_omode && g_vm_have_orel) { Qo = quat_norm(quat_mul(Qp, g_vm_orel)); keep = 0; }
    }
    if (rlr > 0.0f) {   /* X3: native two-hand reload moved into view: bow at the hold point (+ rltr of its native travel) */
        const Vec3 *pS = g_oldnode_getdpos(b[wh][0]);
        Vec3 S0 = readable((void *)pS, 12) ? *pS : g_vm_nhp[wh];
        Vec3 vn = vm_sub(g_vm_nhp[wh], S0);
        if (!g_vm_have_rl0) { g_vm_rl_p0 = vn; g_vm_have_rl0 = 1; }
        Vec3 vt = vm_sub(Ph, S0);
        if (g_vm_scale > 1e-6f) vt = vm_add(vt, vm_w2s_dir(vm_c2w_dir(vm_v(0.0f, g_vm_rl_dy, 0.0f))));
        Quat R = vm_fromto(vm_lerp(vn, g_vm_rl_p0, 1.0f - g_vm_rltr), vt);
        Ph = vm_lerp(Ph, vm_add(S0, quat_rotvec(R, vn)), rlr); Qh = quat_norm(quat_slerp(Qh, quat_norm(quat_mul(R, g_vm_nhq[wh])), rlr));
        Vec3 Pon = vm_add(S0, quat_rotvec(R, vm_sub(g_vm_nhp[oh], S0))); Quat Qon = quat_norm(quat_mul(R, g_vm_nhq[oh]));
        Po = vm_lerp(Po, Pon, rlr); Qo = quat_norm(quat_slerp(keep ? g_vm_nhq[oh] : Qo, Qon, rlr)); keep = 0;
    } else g_vm_have_rl0 = 0;
    {   Vec3 Et; float ew = vm_elbow(b[wh][0], b[wh][1], b[wh][2], Ph, &Et);
        if (!vm_ik(wh, b[wh][0], b[wh][1], b[wh][2], Ph, Qh, 0, g_vm_tpole[wh], we, &Et, ew)) g_vm_ikfail++; }
    if (!vm_ik(oh, b[oh][0], b[oh][1], b[oh][2], Po, Qo, keep, g_vm_tpole[oh], we, NULL, 0.0f)) g_vm_ikfail++;
    g_vm_applied++;
}

static void hooked_vm_setanim(void *skel, const void *set, float w, const void *bmap)
{
    g_vm_setanim_orig(skel, set, w, bmap);
    if (!skel || skel != g_vm_skel || g_vm_dead) return;
    g_vm_calls++;
    /* May run nested inside a guarded caller (the camera weld): save and
     * restore the guard so a fault here doesn't strand the caller's jmp_buf. */
    jmp_buf saved; memcpy(saved, g_guard_jb, sizeof(jmp_buf));
    int was = g_guard_armed; DWORD wtid = g_guard_tid;
    if (setjmp(g_guard_jb)) {
        g_vm_dead = 1; g_vm_w = 0.0f;
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
        || !g_oldnode_getpos) {
        logline("[vm] viewmodel unavailable (setAnimationState=%p)", t); return;
    }
    g_vm_hooked = install_hook(t, (void *)hooked_vm_setanim, (void **)&g_vm_setanim_orig);
    logline(g_vm_hooked ? "[vm] viewmodel hook installed (Skeleton::setAnimationState, IK)"
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

/* camera frame (world): unzoomed eye (game coords) + right/up/forward */
static Vec3 g_vm_eye, g_vm_rt, g_vm_up, g_vm_fw;
static Vec3 vm_c2w_dir(Vec3 c) { return vm_add(vm_add(vm_mul(g_vm_rt, c.x), vm_mul(g_vm_up, c.y)), vm_mul(g_vm_fw, c.z)); }
static Vec3 vm_c2w_pos(Vec3 c) { return vm_add(g_vm_eye, vm_c2w_dir(c)); }
static Vec3 vm_w2c_dir(Vec3 w) { return vm_v(vm_dot(w, g_vm_rt), vm_dot(w, g_vm_up), vm_dot(w, g_vm_fw)); }
/* skeleton-space position -> camera numbers (unzoomed eye) */
static Vec3 vm_s2c_pos(Vec3 s) { return vm_w2c_dir(vm_sub(vm_add(g_vm_cmw, vm_s2w_dir(vm_sub(s, g_vm_cms))), g_vm_eye)); }
static int vm_elb_out(Vec3 x)   /* camera point outside the view frustum by the arm margin */
{
    float m = g_vm_elb_m;
    return x.x > g_vm_elb_fx * x.z + m || x.x < -g_vm_elb_fx * x.z - m || x.y < -g_vm_elb_fy * x.z - m || x.y > g_vm_elb_fy * x.z + m;
}
/* wrist W, elbow candidate E, shoulder S (camera numbers): every near-plane cut / end of the visible arm off screen */
static int vm_elb_pass(Vec3 W, Vec3 E, Vec3 S, float L1n)
{
    float zc = g_vm_elb_zc, zt = g_vm_elb_zc + g_vm_elb_r, le = vm_len(vm_sub(E, S));
    if (le > L1n * vm_stmax() || le < L1n * 0.4f) return 0;
    if (W.z <= zc - g_vm_elb_r) return 1;                    /* hand wholly behind the near plane: nothing drawn */
    if (W.z < zt && !vm_elb_out(W)) return 0;                /* hand sliced by the near plane in view: no elbow fixes it */
    /* the arm surface (axis z - radius) must stay in front of the plane until the arm is off screen */
    if (E.z < zt) return W.z < zt || vm_elb_out(vm_lerp(W, E, (W.z - zt) / (W.z - E.z)));
    if (!vm_elb_out(E)) return 0;
    if (S.z < zt) return vm_elb_out(vm_lerp(E, S, (E.z - zt) / (E.z - S.z)));
    return 1;
}
/* wrist -> elbow direction e on the straight-wrist cone: forearm (-e) at th +- band from the blade f (radians) */
static Vec3 vm_cone(Vec3 e, Vec3 f, float th, float band)
{
    Vec3 a = vm_mul(e, -1.0f); float c = vm_dot(a, f), al = acosf(fmaxf(-1.0f, fminf(1.0f, c)));
    float al2 = al < th - band ? th - band : al > th + band ? th + band : al;
    if (al2 == al) return e;
    Vec3 pp = vm_sub(a, vm_mul(f, c));
    if (vm_len(pp) < 1e-4f) pp = vm_cross(f, fabsf(f.y) < 0.9f ? vm_v(0, 1, 0) : vm_v(1, 0, 0));
    pp = vm_norm(pp);
    return vm_mul(vm_add(vm_mul(f, cosf(al2)), vm_mul(pp, sinf(al2))), -1.0f);
}
static float vm_cone_dev(Vec3 e, Vec3 f, float th, float band)   /* radians outside the band */
{
    float al = acosf(fmaxf(-1.0f, fminf(1.0f, -vm_dot(e, f))));
    return fmaxf(0.0f, fabsf(al - th) - band);
}
/* melee wrist fix: preferred wrist -> elbow direction (camera space) for the wrist at Ph (skeleton space): g_vm_elbd
 * blended with the natural shoulder/elbow IK elbow (g_vm_elb_nat), kept on the straight-wrist cone around the blade.
 * Shared by the blade roll (vm_apply) and vm_elbow so both aim at the same elbow. 0 = bones unreadable / not melee. */
/* S1: cos(edge, wrist->eye) for the wrist -> elbow candidate e (camera numbers), blade fb, wrist W (eye = origin) */
static float g_vm_edgesgn = -1.0f, g_vm_edge_pen = 4.0f;
static float vm_edge_eye(Vec3 e, Vec3 fb, Vec3 W)
{
    Vec3 a = vm_mul(e, -1.0f), pa = vm_sub(a, vm_mul(fb, vm_dot(a, fb)));
    if (vm_len(pa) < 1e-4f || vm_len(W) < 1e-4f) return -1.0f;
    pa = vm_norm(pa);
    Vec3 ed = vm_add(vm_mul(pa, cosf(g_vm_ekap)), vm_mul(vm_cross(fb, pa), sinf(g_vm_ekap)));
    return -g_vm_edgesgn * vm_dot(ed, vm_norm(W));
}
static int vm_elb_pref(void *ua, void *fa, void *ha, Vec3 Ph, Vec3 *d0o)
{
    if (!(g_vm_wfix && g_vm_class == 0)) return 0;
    const Vec3 *ps = g_oldnode_getdpos(ua), *pe = g_oldnode_getdpos(fa), *ph = g_oldnode_getdpos(ha);
    if (!readable((void *)ps, 12) || !readable((void *)pe, 12) || !readable((void *)ph, 12)) return 0;
    float L1n = vm_l1(ua, ps, pe) * g_vm_scale, L2 = vm_len(vm_sub(*ph, *pe)) * g_vm_scale;
    if (L1n < 0.1f || L2 < 0.1f) return 0;
    Vec3 W = vm_s2c_pos(Ph), S = vm_s2c_pos(*ps), d0 = vm_norm(g_vm_elbd);
    Vec3 fb = vm_norm(vm_w2c_dir(vm_s2w_dir(g_vm_tf)));
    float th = acosf(fmaxf(-1.0f, fminf(1.0f, g_vm_hcos))), band = g_vm_wband * 0.0174533f;
    Vec3 dv = vm_sub(W, S); float D = vm_len(dv);
    if (D > 1e-3f && g_vm_elb_nat > 0.0f) {   /* natural elbow: two-bone IK shoulder -> wrist, elbow toward the pole */
        Vec3 n = vm_mul(dv, 1.0f / D), pole = g_vm_pole[0][g_vm_whand[0] ? 1 : 0];
        float Dc = fminf(fmaxf(D, fabsf(L1n - L2) + 0.01f), (L1n + L2) * 0.995f);
        float aa = (L1n*L1n - L2*L2 + Dc*Dc) / (2.0f * Dc), hh = sqrtf(fmaxf(0.0f, L1n*L1n - aa*aa));
        Vec3 pp = vm_sub(pole, vm_mul(n, vm_dot(pole, n)));
        if (vm_len(pp) > 1e-4f) {
            Vec3 En = vm_add(S, vm_add(vm_mul(n, aa), vm_mul(vm_norm(pp), hh)));
            d0 = vm_norm(vm_lerp(d0, vm_norm(vm_sub(En, W)), g_vm_elb_nat));
        }
    }
    Vec3 pref = vm_cone(d0, fb, th, band);
    *d0o = pref;
    /* wrist-straight elbows that pass the near-plane / view-edge rule (vm_elb_pass): forearm at th + dd from the blade
     * (|dd| <= g_vm_elb_dmax), cost = preference + previous elbow - upper-arm stretch - offset beyond 8 deg; the pick
     * moves at most g_vm_elb_rate deg/s while a passing direction lies within that step (the passing band can vanish
     * and reappear elsewhere: the offset region bridges it with a bent-but-legal wrist instead of a jump).
     * 2 = passing pick, 1 = preference only (vm_elbow searches). */
    Vec3 ax = vm_mul(fb, -1.0f), u1 = vm_norm(vm_cross(ax, fabsf(ax.y) < 0.9f ? vm_v(0, 1, 0) : vm_v(1, 0, 0))), u2 = vm_cross(ax, u1);
    Vec3 kp = g_vm_have_elbe ? g_vm_elbe : pref; float kw = g_vm_have_elbe && g_vm_reseed <= 0.0f ? g_vm_elb_keep : 0.0f;
    int eg = g_vm_edge && g_vm_have_ekap, eonly = 0;   /* S1 */
    float stepc = g_vm_have_elbe ? cosf(fminf(3.0f, g_vm_elb_rate * 0.0174533f * fminf(fmaxf(g_vm_dt, 0.004f), g_vm_maxdt))) : -2.0f;
    float sstep = g_vm_have_elbe ? fminf(3.0f, g_vm_elb_rate * 0.0174533f * fminf(fmaxf(g_vm_dt, 0.004f), g_vm_maxdt)) : 3.0f;
    float tc[3] = { stepc, cosf(fminf(3.1f, 2.0f * sstep)), cosf(fminf(3.1f, 4.0f * sstep)) };
    float tb[4] = { -1e9f, -1e9f, -1e9f, -1e9f }, ta[4] = { 0 }, td[4] = { 0 };
    float tbo[4] = { -1e9f, -1e9f, -1e9f, -1e9f }, tao[4] = { 0 }, tdo[4] = { 0 };   /* S1: edge-away candidates only */
    if (g_vm_reseed > 0.0f) tc[0] = tc[1] = tc[2] = -2.0f;   /* S2: global pick */
    float bl = -1e9f, bg = -1e9f, la = 0, ld = 0, ga = 0, gd = 0; int nd = (int)(g_vm_elb_dmax / 4.0f);
    /* look-ahead (PT30): the passing band can switch sides within one frame (end of the strike), a causal pick then
     * jumps (blade roll 75 deg in one frame). Passing directions of the next frames (wrist / blade predicted from
     * g_vm_fut, wrist offset kept in the pose frame, shoulder fixed) on a coarse grid (15 deg az x 8 deg offset);
     * backward minimax DP (max over continuations of the min step cosine); the pick below pays for a best
     * continuation step above g_vm_elb_lama deg. Once per frame (the roll refinement calls twice). */
    int lan = 0;
    if (g_vm_elb_la && g_vm_have_elbe && g_vm_fut_n > 0 && g_vm_reseed <= 0.0f) {
        if (g_vm_la_fid != g_vm_fid) {
            g_vm_la_fid = g_vm_fid; g_vm_la_n = 0;
            VmPose o0 = g_vm_out; Vec3 s0 = vm_cross(o0.f, o0.u), dw = vm_sub(W, o0.p);
            Vec3 ol = vm_v(vm_dot(dw, o0.f), vm_dot(dw, o0.u), vm_dot(dw, s0));
            for (int k = 0; k < g_vm_fut_n; k++) {
                VmPose o = g_vm_fut[k]; Vec3 sk = vm_cross(o.f, o.u);
                Vec3 Wk = vm_add(o.p, vm_add(vm_add(vm_mul(o.f, ol.x), vm_mul(o.u, ol.y)), vm_mul(sk, ol.z)));
                Vec3 ak = vm_mul(vm_norm(o.f), -1.0f), v1 = vm_norm(vm_cross(ak, fabsf(ak.y) < 0.9f ? vm_v(0, 1, 0) : vm_v(1, 0, 0))), v2 = vm_cross(ak, v1);
                int n = 0, no = 0; static unsigned char okf[VM_LAA * 7]; Vec3 fk = vm_norm(o.f);
                for (int i = 0; i < VM_LAA; i++) for (int j = -3; j <= 3; j++) {
                    float phi = i * (6.2831853f / VM_LAA), t = th + j * 0.1396263f;
                    if (t < 0.0f || fabsf(j * 8.0f) > g_vm_elb_dmax + 1e-3f) continue;
                    Vec3 e = vm_add(vm_mul(ak, cosf(t)), vm_mul(vm_add(vm_mul(v1, cosf(phi)), vm_mul(v2, sinf(phi))), sinf(t)));
                    if (vm_elb_pass(Wk, vm_add(Wk, vm_mul(e, L2)), S, L1n)) {
                        okf[n] = !eg || vm_edge_eye(e, fk, Wk) <= g_vm_edge_tol; no += okf[n]; g_vm_la_e[k][n++] = e; }
                }
                if (no > 0 && no < n) { int m = 0; for (int c = 0; c < n; c++) if (okf[c]) g_vm_la_e[k][m++] = g_vm_la_e[k][c]; n = m; }   /* S1 */
                if (!n) break;
                g_vm_la_c[k] = n; g_vm_la_n = k + 1;
            }
            if (g_vm_la_n > 0) {
                int L = g_vm_la_n - 1;
                for (int c = 0; c < g_vm_la_c[L]; c++) g_vm_la_cc[L][c] = 1.0f;
                for (int k = L - 1; k >= 0; k--) for (int a = 0; a < g_vm_la_c[k]; a++) {
                    float best = -2.0f;
                    for (int b2 = 0; b2 < g_vm_la_c[k + 1]; b2++) {
                        float d = fminf(vm_dot(g_vm_la_e[k][a], g_vm_la_e[k + 1][b2]), g_vm_la_cc[k + 1][b2]); if (d > best) best = d; }
                    g_vm_la_cc[k][a] = best;
                }
            }
        }
        lan = g_vm_la_n > 0;
        if (lan) tc[0] = tc[1] = tc[2] = -2.0f;   /* the step is in the cost: one tier */
    }
    /* PT30-FLIP: drawing / ready (not swinging): prefer the elbow branch every swing ends on, so the first wind-up after
     * a draw doesn't have to cross branches where the passing band vanishes within a frame */
    Vec3 rbe = vm_v(0, 0, 0); float rbw = 0.0f;
    if (!g_vm_swing && g_vm_ti == VM_READY) {
        rbw = g_vm_phase == VMP_DRAW ? g_vm_rbw : g_vm_phase == VMP_NORMAL ? g_vm_rbwr : 0.0f;
        Vec3 of = vm_norm(g_vm_out.f), ou = vm_norm(g_vm_out.u), os = vm_cross(of, ou);
        rbe = vm_norm(vm_add(vm_add(vm_mul(of, g_vm_rbe.x), vm_mul(ou, g_vm_rbe.y)), vm_mul(os, g_vm_rbe.z)));
    }
    for (int pass = 0; pass < 2; pass++) {
        int na = pass ? 17 : 90, ndd = pass ? 9 : 2 * nd + 1;
        float a0 = pass ? (bl > -1e8f ? la : ga) - 0.0698132f : 0.0f, as = pass ? 0.00872665f : 0.0698132f;
        float d0_ = pass ? (bl > -1e8f ? ld : gd) - 0.0698132f : -nd * 0.0698132f, ds = pass ? 0.0174533f : 0.0698132f;
        if (pass && bl <= -1e8f) break;
        for (int i = 0; i < na; i++) for (int j = 0; j < ndd; j++) {
            float phi = a0 + i * as, dd = d0_ + j * ds, t = th + dd;
            if (fabsf(dd) > g_vm_elb_dmax * 0.0174533f + 1e-4f || t < 0.0f) continue;
            Vec3 e = vm_add(vm_mul(ax, cosf(t)), vm_mul(vm_add(vm_mul(u1, cosf(phi)), vm_mul(u2, sinf(phi))), sinf(t)));
            Vec3 E = vm_add(W, vm_mul(e, L2));
            if (!vm_elb_pass(W, E, S, L1n)) continue;
            float ee = eg ? vm_edge_eye(e, fb, W) : -1.0f;
            int eok = !eg || ee <= g_vm_edge_tol;   /* S1 */
            if (eonly && !eok) continue;
            float sc = vm_dot(e, pref) + kw * vm_dot(e, kp) - 0.5f * fabsf(vm_len(vm_sub(E, S)) - L1n) / L1n
                     - 3.0f * fmaxf(0.0f, fabsf(dd) - 0.1396263f) + rbw * vm_dot(e, rbe)
                     - g_vm_edge_pen * fmaxf(0.0f, ee - g_vm_edge_tol);   /* S1: least edge-facing fallback */
            if (lan) {   /* worst step on the best path: from the previous pick, then the predicted frames */
                float g = vm_dot(e, kp), gb = -2.0f;
                for (int b2 = 0; b2 < g_vm_la_c[0]; b2++) { float d = fminf(vm_dot(e, g_vm_la_e[0][b2]), g_vm_la_cc[0][b2]); if (d > gb) gb = d; }
                g = fminf(g, gb);
                sc -= g_vm_elb_lawm * fmaxf(0.0f, acosf(fmaxf(-1.0f, fminf(1.0f, g))) * 57.29578f - g_vm_elb_lama);
            }
            {   float kd = vm_dot(e, kp); int ti = kd >= tc[0] ? 0 : kd >= tc[1] ? 1 : kd >= tc[2] ? 2 : 3;
                if (sc > tb[ti]) { tb[ti] = sc; ta[ti] = phi; td[ti] = dd; }
                if (eok && sc > tbo[ti]) { tbo[ti] = sc; tao[ti] = phi; tdo[ti] = dd; }   }
        }
        if (!pass && eg) {   /* S1: an edge-away elbow passes -> only those (refine pass too) */
            int any = 0; for (int q = 0; q < 4; q++) any |= tbo[q] > -1e8f;
            if (any) { for (int q = 0; q < 4; q++) { tb[q] = tbo[q]; ta[q] = tao[q]; td[q] = tdo[q]; } eonly = 1; } else g_vm_edge_nok++;
        }
        if (!pass) {   /* refine around the best of the nearest non-empty tier */
            int ti = 0; while (ti < 3 && tb[ti] <= -1e8f) ti++;
            if (tb[ti] > -1e8f) { bl = tb[ti]; la = ta[ti]; ld = td[ti]; g_vm_pk[ti]++;
                for (int q = 0; q < 4; q++) tb[q] = -1e9f;
                tc[0] = tc[1] = tc[2] = -2.0f; }   /* refine pass: everything lands in tier 0 */
        } else if (tb[0] > bl) { bl = tb[0]; la = ta[0]; ld = td[0]; }
    }
    if (bl <= -1e8f) return 1;
    {   float phi = la, t = th + ld; (void)bg; (void)ga; (void)gd;
        Vec3 e = vm_norm(vm_add(vm_mul(ax, cosf(t)), vm_mul(vm_add(vm_mul(u1, cosf(phi)), vm_mul(u2, sinf(phi))), sinf(t))));
        if (g_vm_have_elbe && g_vm_reseed > 0.0f && g_vm_reseed_tau > 0.0f) {   /* S2: glide to the re-seeded pick */
            float sa = 1.0f - expf(-fminf(fmaxf(g_vm_dt, 0.004f), g_vm_maxdt) / g_vm_reseed_tau);
            Vec3 es = vm_lerp(kp, e, sa); if (vm_len(es) > 1e-3f) e = vm_norm(es);
        } else
        if (g_vm_have_elbe && g_vm_elb_ptau > 0.0f) {   /* low-pass the pick when the smoothed direction passes too */
            float sa = 1.0f - expf(-fminf(fmaxf(g_vm_dt, 0.004f), g_vm_maxdt) / g_vm_elb_ptau);
            Vec3 es = vm_norm(vm_lerp(kp, e, sa));
            if (vm_elb_pass(W, vm_add(W, vm_mul(es, L2)), S, L1n) && vm_cone_dev(es, fb, th, g_vm_elb_dmax * 0.0174533f) <= 0.0f) e = es;
        }
        if (eg) g_vm_edge_pred = vm_edge_eye(e, fb, W);
        *d0o = e;   }
    return 2;
}
/* weapon-hand elbow target (skeleton space) for the arm-from-the-edge mode; returns its weight (0 = natural IK) */
static Vec3 g_vm_elb_cb; static int g_vm_have_cb; static float g_vm_elb_hyst = 0.05f, g_vm_elb_slow = 0.35f, g_vm_elb_small = 4.0f;
static float vm_elbow(void *ua, void *fa, void *ha, Vec3 Ph, Vec3 *Et)
{
    g_vm_elb_w = 0.0f;
    if (!g_vm_elb[g_vm_class ? 1 : 0]) { g_vm_have_elbe = 0; return 0.0f; }
    const Vec3 *ps = g_oldnode_getdpos(ua), *pe = g_oldnode_getdpos(fa), *ph = g_oldnode_getdpos(ha);
    if (!readable((void *)ps, 12) || !readable((void *)pe, 12) || !readable((void *)ph, 12)) return 0.0f;
    float L1n = vm_l1(ua, ps, pe) * g_vm_scale, L2 = vm_len(vm_sub(*ph, *pe)) * g_vm_scale;
    if (L1n < 0.1f || L2 < 0.1f) return 0.0f;
    Vec3 W = vm_s2c_pos(Ph), S = vm_s2c_pos(*ps), d0 = vm_norm(g_vm_elbd);
    int wf = g_vm_wfix && g_vm_class == 0, direct = 0; Vec3 fb = vm_v(0, 0, 1); float th = 0.0f, band = 0.0f;
    if (wf) {
        fb = vm_norm(vm_w2c_dir(vm_s2w_dir(g_vm_tf)));
        th = acosf(fmaxf(-1.0f, fminf(1.0f, g_vm_hcos))); band = g_vm_wband * 0.0174533f;
        Vec3 dp; int pr = g_vm_pick_ok ? 2 : vm_elb_pref(ua, fa, ha, Ph, &dp); if (g_vm_pick_ok) dp = g_vm_pick; if (pr) d0 = dp;
        g_vm_pick_ok = 0;
        if (pr == 2) direct = 1;
    }
    Vec3 best = d0;
    int ok = direct || vm_elb_pass(W, vm_add(W, vm_mul(d0, L2)), S, L1n);
    if (!ok) {   /* coarse search: passing direction closest to d0 (elbow right of / below the wrist, not ahead) */
        float bd = -99.0f;
        for (int i = 0; i < 24; i++) for (int j = 0; j < 12; j++) {
            float az = 6.2831853f * i / 24.0f, el = -1.45f + 2.9f * j / 11.0f;
            Vec3 e = vm_v(cosf(el) * cosf(az), sinf(el), cosf(el) * sinf(az));
            if (e.x < -0.25f || e.z > 0.35f) continue;
            float dd = vm_dot(e, d0) - (wf ? 2.0f * vm_cone_dev(e, fb, th, band) : 0.0f);
            if (dd > bd && vm_elb_pass(W, vm_add(W, vm_mul(e, L2)), S, L1n)) { bd = dd; best = e; }
        }
        if (bd > -99.0f && g_vm_have_cb && g_vm_elb_hyst > 0.0f) {   /* X1: hysteresis on the grid winner */
            Vec3 e = g_vm_elb_cb;
            float dd = vm_dot(e, d0) - (wf ? 2.0f * vm_cone_dev(e, fb, th, band) : 0.0f);
            if (dd >= bd - g_vm_elb_hyst && vm_elb_pass(W, vm_add(W, vm_mul(e, L2)), S, L1n)) best = e;
        }
        g_vm_have_cb = bd > -99.0f; if (g_vm_have_cb) g_vm_elb_cb = best;
        if (bd > -99.0f) {   /* refine on the arc d0 -> best: the passing direction nearest d0 (continuous) */
            float lo = 0.0f, hi = 1.0f;
            for (int k = 0; k < 14; k++) { float mid = 0.5f * (lo + hi); Vec3 e = vm_norm(vm_lerp(d0, best, mid));
                if (vm_elb_pass(W, vm_add(W, vm_mul(e, L2)), S, L1n)) hi = mid; else lo = mid; }
            best = vm_norm(vm_lerp(d0, best, hi)); ok = 1;
        }
    }
    g_vm_elb_ok = ok;
    {   /* smooth the direction (the search can step); exact first frame */
        float tau = g_vm_elb_tau;
        if (g_vm_have_elbe && g_vm_elb_slow > tau && acosf(fmaxf(-1.0f, fminf(1.0f, vm_dot(g_vm_elbe, best)))) < g_vm_elb_small * 0.0174533f)
            tau = g_vm_elb_slow;   /* X1: small toggles glide */
        float a = g_vm_have_elbe ? 1.0f - expf(-fminf(g_vm_dt, g_vm_maxdt) / tau) : 1.0f;
        if (wf && direct) a = 1.0f;   /* the wrist pick moves continuously (rate-limited): exact, the roll aims at it */
        g_vm_elbe = g_vm_have_elbe ? vm_norm(vm_lerp(g_vm_elbe, best, a)) : best; g_vm_have_elbe = 1;
    }
    float wz = g_vm_zfade ? 1.0f : 1.0f - g_view.applied / g_vm_elb_zoom; if (wz < 0) wz = 0; if (wz > 1) wz = 1;   /* zfade: the whole viewmodel fades */
    g_vm_elb_wz = wz;
    *Et = vm_add(Ph, vm_w2s_dir(vm_c2w_dir(vm_mul(g_vm_elbe, L2))));
    g_vm_elb_w = wz;
    return wz;
}
static float vm_elev_of(Vec3 c) { return atan2f(c.y, c.z) * 57.29578f; }
static float vm_az_of(Vec3 c)   { return atan2f(c.x, c.z) * 57.29578f; }

/* Per camera frame, after the eye/orientation are final. */
static void vm_frame_core(void *pc, int body_down)
{
    static LARGE_INTEGER f, last;
    LARGE_INTEGER now; QueryPerformanceCounter(&now);
    if (!f.QuadPart) QueryPerformanceFrequency(&f);
    float dt = last.QuadPart ? (float)(now.QuadPart - last.QuadPart) / (float)f.QuadPart : 0.0f;
    last = now;
    if (dt > 0.1f) dt = 0.1f;
    g_vm_dt = dt;
    if (!g_vm_hooked || g_vm_dead) return;
    vm_names();
    g_vm_frames++;
    if (g_vm_class == 1 && g_vm_frames % 600 == 0) logline("X1 fp exact=%lu near=%lu long=%lu nat=%lu st=%.4f,%.4f fpn=%.4f,%.4f map node=%lu fb=%lu res=%.4f resmax=%.4f",
        g_vm_fp_exact, g_vm_fp_near, g_vm_fp_long, g_vm_fp_nat, g_vm_st_last[0], g_vm_st_last[1], vm_len(g_vm_fpn[0]), vm_len(g_vm_fpn[1]), g_vm_map_node_n, g_vm_map_fb_n, g_vm_map_res, g_vm_map_resmax);

    const char *st = g_fpc_ui_state ? g_fpc_ui_state : "off";
    int ti = -1, hold = 0, on = 1, want_swing = 0;
    if      (!strcmp(st, "ready"))      ti = VM_READY;
    else if (!strcmp(st, "aiming"))     ti = VM_AIM;
    else if (!strcmp(st, "reloading"))  ti = VM_RELOAD;
    else if (!strcmp(st, "blocking"))   ti = VM_BLOCK;
    else if (!strcmp(st, "swinging"))   { ti = VM_READY; want_swing = 1; }
    else if (!strcmp(st, "recovering")) ti = VM_READY;
    else if (!strcmp(st, "staggered"))  hold = 1;
    else on = 0;                                       /* holstered/down/off/none */
    if (!g_cfg_vm || !g_fp_mode || !pc || body_down || !g_have_eye) on = 0;
    /* fire: a shot keeps the aim pose g_vm_fire_hold s (kick on top) before the reload pose */
    if (g_combat_actual_shots != g_vm_shots0) {
        if (g_combat_actual_shots > g_vm_shots0 && g_vm_class == 1) {
            g_vm_kick_t = 0.0f; g_vm_kicks++; g_vm_fire_t = g_vm_fire_hold;
            logline("[vm] fire #%d: aim pose held %.2fs + kick (state=%s)", g_vm_kicks, g_vm_fire_hold, st);
        }
        g_vm_shots0 = g_combat_actual_shots;
    }
    if (g_vm_fire_t > 0.0f) { g_vm_fire_t -= dt; if (ti == VM_RELOAD || ti == VM_READY) ti = VM_AIM; }
    g_vm_ti = ti;
    g_vm_state = st; g_vm_hold = hold;
    {   /* S2: entering block / ready (incl. recovering) re-seeds the elbow pick */
        int m = !on || g_vm_class != 0 ? -1 : ti == VM_BLOCK ? 2 : ti == VM_READY && !want_swing ? 1 : 0;
        if (m != g_vm_rsmode && m > 0 && g_vm_reseed_on) g_vm_reseed = g_vm_reseed_dur;
        else if (g_vm_reseed > 0.0f) g_vm_reseed -= dt;
        g_vm_rsmode = m;
    }

    void *skel = NULL;
    if (pc) {
        void *anim = readable((void *)((uintptr_t)pc + CHAR_ANIM), 8) ? *(void **)((uintptr_t)pc + CHAR_ANIM) : NULL;
        skel = readable(anim, ANIM_SKELETON + 8) ? *(void **)((uintptr_t)anim + ANIM_SKELETON) : NULL;
    }
    if (skel != g_vm_skel) { g_vm_have_written[0] = g_vm_have_written[1] = 0; g_vm_fpw_on[0] = g_vm_fpw_on[1] = 0; g_vm_w = 0.0f; g_vm_wl = 0.0f; g_vm_phase = VMP_NORMAL; g_vm_have_cur = 0; g_vm_have_t = 0; g_vm_have_orel = 0; g_vm_have_oc = 0; g_vm_have_pl[0] = g_vm_have_pl[1] = 0; }
    g_vm_skel = skel;
    if (!skel) return;

    /* measure (world = game coords): both props + arm joints in world; skeleton<->world map */
    Vec3 pw[2], jw[2][3], bw[3] = { { 0 } };
    int ok = 1;
    g_vm_pc = pc;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; ok = 0; }
    else {
        guard_arm();
        for (int i = 0; i < 2; i++) {
            g_get_bone_world(pc, &pw[i], g_vm_nm_prop[i]);
            g_get_bone_world(pc, &jw[i][0], g_vm_nm_arm[i]);
            g_get_bone_world(pc, &jw[i][1], g_vm_nm_fore[i]);
            g_get_bone_world(pc, &jw[i][2], g_vm_nm_hand[i]);
        }
        g_get_bone_world(pc, &bw[0], g_vm_nm_head); g_get_bone_world(pc, &bw[1], g_vm_nm_neck); g_get_bone_world(pc, &bw[2], g_vm_nm_spine);
        ok = vm_map(pc, skel);
        char_position(pc, &g_vm_root_f);
        g_guard_armed = 0;
    }
    g_vm_basis_ok = ok;
    if (!ok) return;

    /* camera frame from the UNZOOMED eye (PT29); eye is Ogre-world (floating origin): game = ogre - (g_tx,0,g_tz) */
    Vec3 eo = g_view_have_anchor ? g_view_anchor : g_last_eye;
    g_vm_eye = vm_v(eo.x - g_tx, eo.y, eo.z - g_tz);
    float cp = cosf(g_pitch), sp = sinf(g_pitch), cy = cosf(g_yaw), sy = sinf(g_yaw);
    g_vm_fw = vm_v(sy*cp, -sp, cy*cp);                   /* g_pitch>0 = looking down */
    g_vm_up = vm_v(sy*sp, cp, cy*sp);
    g_vm_rt = vm_cross(g_vm_fw, g_vm_up);
    g_vm_mhd = vm_w2c_dir(vm_sub(bw[0], g_vm_eye)); g_vm_mnk = vm_w2c_dir(vm_sub(bw[1], g_vm_eye)); g_vm_msp = vm_w2c_dir(vm_sub(bw[2], g_vm_eye));
    {   float a = g_vm_zf1 > g_vm_zf0 ? (g_view.applied - g_vm_zf0) / (g_vm_zf1 - g_vm_zf0) : 0.0f;
        a = a < 0 ? 0 : a > 1 ? 1 : a; g_vm_zf = g_vm_zfade ? 1.0f - a * a * (3.0f - 2.0f * a) : 1.0f; }

    int cls = 0;
    {   void *wih = readable((void *)((uintptr_t)pc + CHAR_WEAPON_IN_HANDS), 8) ? *(void **)((uintptr_t)pc + CHAR_WEAPON_IN_HANDS) : NULL;
        void **vt = readable(pc, 8) ? *(void ***)pc : NULL;
        void *rw = readable((void *)((uintptr_t)vt + 0x3D0), 8) ? ((void *(*)(void *))vt[0x3D0/8])(pc) : NULL;
        g_vm_melee = wih && wih != rw; g_vm_wih = wih != NULL;
        cls = (wih && wih == rw) ? 1 : 0;
    }
    /* measured: weapon grip (prop) + forward in camera numbers (post-IK of the last apply) */
    {   int wh = g_vm_whand[cls] ? 1 : 0;
        g_vm_hand = wh;
        for (int i = 0; i < 2; i++) { Vec3 c = vm_w2c_dir(vm_sub(pw[i], g_vm_eye)); g_vm_he[i] = vm_elev_of(c); g_vm_ha[i] = vm_az_of(c); }
        g_vm_mp = vm_w2c_dir(vm_sub(pw[wh], g_vm_eye));
        for (int i = 0; i < 2; i++) for (int k = 0; k < 3; k++) g_vm_mj[i][k] = vm_w2c_dir(vm_sub(jw[i][k], g_vm_eye));
        g_vm_oerr = g_vm_have_oc ? vm_len(vm_sub(g_vm_mj[!wh][2], g_vm_oc)) : -1.0f;
        g_vm_elev = vm_elev_of(g_vm_mp); g_vm_az = vm_az_of(g_vm_mp);
        void *pb = g_skel_getbone(skel, g_vm_nm_prop[wh]);
        const Quat *q = readable(pb, 8) ? g_oldnode_getdori(pb) : NULL;
        if (readable((void *)q, 16)) {
            g_vm_mf = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(*q, vm_axis(g_vm_ax[cls][0])))));
            g_vm_mu = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(*q, vm_axis(g_vm_ax[cls][1])))));
            g_vm_tilt_cur = asinf(fmaxf(-1.0f, fminf(1.0f, g_vm_mf.y))) * 57.29578f;
        }
        {   /* wrist bend (PT17): the hand bone X axis against the forearm (elbow -> wrist) */
            void *hb = g_skel_getbone(skel, g_vm_nm_hand[wh]), *fb = g_skel_getbone(skel, g_vm_nm_fore[wh]);
            const Quat *hq = readable(hb, 8) ? g_oldnode_getdori(hb) : NULL, *fq = readable(fb, 8) ? g_oldnode_getdori(fb) : NULL;
            if (readable((void *)hq, 16)) { g_vm_mh = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(*hq, vm_v(1, 0, 0)))));
                g_vm_mhy = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(*hq, vm_v(0, 1, 0)))));   /* PT33: palm-facing measure */
                g_vm_mhz = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(*hq, vm_v(0, 0, 1))))); }
            if (readable((void *)fq, 16)) g_vm_mfx = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(*fq, vm_v(1, 0, 0)))));
            g_vm_wb = acosf(fmaxf(-1.0f, fminf(1.0f, vm_dot(vm_norm(vm_sub(g_vm_mj[wh][2], g_vm_mj[wh][1])), g_vm_mh)))) * 57.29578f;
        }
    }

    if (g_vm_rp >= 0 && g_vm_rp < g_vm_rn) {            /* frozen replay of a recorded frame */
        const VmRec *q = &g_vm_rec[g_vm_rp], *nx = g_vm_rp + 1 < g_vm_rn ? &g_vm_rec[g_vm_rp + 1] : q;
        int whq = g_vm_whand[q->cls] ? 1 : 0;
        VmPose out = q->out; Vec3 oc = q->oc;
        if (!g_vm_rp_t) { out.p = nx->mp; out.f = nx->mf; out.u = nx->mu; oc = nx->mj[!whq][2]; }
        out = vm_pose_norm(out);
        g_vm_class = q->cls; g_vm_ti = q->ti; g_vm_w = 1.0f; g_vm_omode = q->omode; g_vm_cur = out; g_vm_have_cur = 1;
        g_vm_out = out; g_vm_oc = oc; g_vm_have_oc = 1; g_vm_phase = VMP_NORMAL; g_vm_wl = 1.0f;
        goto targets;
    }
    float adt = fminf(dt, g_vm_maxdt);
    g_vm_fid++; g_vm_fut_n = 0;
    {   int holster = !on && g_cfg_vm && g_fp_mode && pc && !body_down && g_have_eye && !strcmp(st, "holstered");
        /* R holster (kfp_controls): the game's sheathe waits g_fpc_holster_delay while we lower the weapon, still in
         * the hand, out of the view; then it leaves the hand below the view and the blend runs out there */
        int pend = on && g_fpc_holster_pending;
        if (pend && g_vm_phase != VMP_LOWER && g_vm_wl > 0.0f) { g_vm_phase = VMP_LOWER; g_vm_ph_t = 0.0f; g_vm_swing = 0; }
        if (on && !pend && g_vm_phase == VMP_LOWER) g_vm_phase = VMP_NORMAL;      /* drawn again / holster cancelled */
        if (on && g_vm_wl <= 0.0f) {                                              /* draw: start below the view */
            g_vm_class = cls; g_vm_cur = vm_draw_low(cls); memset(&g_vm_vel, 0, sizeof g_vm_vel);
            g_vm_have_cur = 1; g_vm_phase = VMP_DRAW; g_vm_ph_t = 0.0f; g_vm_have_oc = 0; g_vm_swing = 0;
        }
        if (!on && holster && g_vm_wl > 0.0f && g_vm_have_cur && g_vm_phase != VMP_LOWER) {
            g_vm_phase = VMP_LOWER; g_vm_ph_t = 0.0f; g_vm_swing = 0;
        }
        if (!on && !holster) g_vm_phase = VMP_NORMAL;                             /* FP off / down: plain fade */
        g_vm_ph_t += adt;
        int wup = on || (g_vm_phase == VMP_LOWER && g_vm_ph_t < g_vm_lower_dur);
        g_vm_wl += (wup ? 1.0f : -1.0f) * adt / g_vm_tau_w;
        g_vm_wl = g_vm_wl < 0.0f ? 0.0f : g_vm_wl > 1.0f ? 1.0f : g_vm_wl;
        g_vm_w = g_vm_wl * g_vm_wl * (3.0f - 2.0f * g_vm_wl);
    }
    if (!on && g_vm_wl <= 0.0f) { g_vm_w = 0.0f; g_vm_have_cur = 0; g_vm_have_oc = 0; g_vm_swing = 0; g_vm_phase = VMP_NORMAL; return; }
    if (on) g_vm_class = cls;
    if (hold) return;
    if (ti < 0 && g_vm_phase != VMP_LOWER) { if (!on) goto targets; return; }

    {   VmPose tgt;
        if (g_vm_phase == VMP_LOWER || ti < 0) tgt = vm_pose_norm(g_vm_low[g_vm_class]);
        else tgt = vm_pose_norm(g_vm_pose[g_vm_class][ti]);
        if (g_vm_class == 1 && ti == VM_AIM && g_vm_phase != VMP_LOWER) {   /* bolt converges on the crosshair */
            Vec3 b = tgt.p; tgt.f = vm_norm(vm_v(-b.x, -b.y, g_vm_aim_dist - b.z));
            tgt = vm_pose_norm(tgt);
        }
        /* crossbow reload: a readable spanning cycle on top of the lowered, canted reload hold: the bow is pulled
         * back/down and its muzzle dips with each pull, then eases back (period g_vm_rl_per) */
        if (ti == VM_RELOAD && g_vm_class == 1 && g_vm_phase != VMP_LOWER) {
            g_vm_rl_t += adt;
            float c = g_vm_rl_t < 0.45f ? 0.0f : 0.5f - 0.5f * cosf(6.2831853f * (g_vm_rl_t - 0.45f) / g_vm_rl_per);
            c *= g_vm_rlnat ? 0.0f : g_vm_rl_amp;
            tgt.p = vm_add(tgt.p, vm_mul(vm_v(-0.10f, -0.25f, -0.35f), c));
            tgt.f = vm_add(tgt.f, vm_mul(vm_v(0.0f, -0.18f, 0.0f), c));
            tgt = vm_pose_norm(tgt);
        } else g_vm_rl_t = 0.0f;
        {   int rlon = ti == VM_RELOAD && g_vm_class == 1 && g_vm_phase == VMP_NORMAL && on;
            g_vm_rlw += (rlon ? 1.0f : -1.0f) * adt / fmaxf(g_vm_rlblend, 0.01f);
            g_vm_rlw = g_vm_rlw < 0.0f ? 0.0f : g_vm_rlw > 1.0f ? 1.0f : g_vm_rlw; }
        if (g_vm_phase == VMP_DRAW) {                    /* hold below the view until the blend is done, then rise */
            if (g_vm_w < 0.98f) tgt = vm_draw_low(g_vm_class);
            else if (g_vm_ph_t > 0.9f) g_vm_phase = VMP_NORMAL;
        }
        if (!g_vm_have_cur) { g_vm_cur = tgt; g_vm_have_cur = 1; memset(&g_vm_vel, 0, sizeof g_vm_vel); }
        /* swing (melee): own clock, progress = the free swing's anim progress when it runs */
        int posed = g_vm_sw_pose >= 0.0f && ti == VM_READY && g_vm_class == 0;
        static int prev_ws; int ws_edge = want_swing && !prev_ws; prev_ws = want_swing;
        if (g_vm_class == 0 && (ws_edge || posed) && !g_vm_swing && ti == VM_READY && g_vm_phase != VMP_LOWER) {
            g_vm_swing = 1; g_vm_swt = 0.0f; g_vm_swu = 0.0f; g_vm_sw0 = posed ? tgt : g_vm_cur; g_vm_swings += !posed;
            g_vm_sw_maxstep = 0.0f; g_vm_sw_n = 0; g_vm_sw_prevf = g_vm_cur.f;
            g_vm_sw_emin = g_vm_sw_amin = 999.0f; g_vm_sw_emax = g_vm_sw_amax = -999.0f;
        }
        if (g_vm_swing && (ti != VM_READY || g_vm_class != 0)) {     /* block / weapon change aborts the swing */
            logline("[vm] swing #%d aborted at u=%.2f (state=%s)", g_vm_swings, g_vm_swu, st); g_vm_swing = 0;
        }
        /* swing->block high elbow (option-stretch.jpg: the block after a swing settles on the high elbow solution, upper-arm
         * stretch 2.87, elbow 5 dm above the shoulder; a plain block from ready is the low one, 2.03): latched for the rest
         * of the block once the uncapped elbow target wants more than g_vm_swb_trig, so the plain block and ready keep
         * the full cap and stay as they are */
        if (ti != VM_BLOCK || g_vm_class != 0) g_vm_swb = 0;
        else if (!g_vm_swb && g_vm_s2_want > g_vm_swb_trig) {
            g_vm_swb = 1; logline("[vm] swing->block high elbow: stretch %.2f > %.2f, elbow cap %.2f (state=%s)", g_vm_s2_want, g_vm_swb_trig, g_vm_swb_cap, st);
        }
        g_vm_swb_w = g_vm_swb_tau > 1e-3f ? fminf(1.0f, fmaxf(0.0f, g_vm_swb_w + (g_vm_swb ? 1.0f : -1.0f) * dt / g_vm_swb_tau)) : (float)g_vm_swb;
        if (g_vm_swing) {
            VmPose sw_prev = g_vm_cur;
            g_vm_swt += dt;
            /* progress: the free swing's anim progress while it is valid, else advance by time from where it is
             * (never jump to the absolute clock: the anim progress runs slower early, that jump was a snap) */
            float pu = !g_vm_sw_clock && g_fpc_fs_prog > 0.0f && g_fpc_fs_prog <= 1.0f && want_swing ? g_fpc_fs_prog : -1.0f;
            float u = posed ? fminf(1.0f, g_vm_sw_pose) : pu >= 0.0f ? fmaxf(g_vm_swu, pu)
                    : fminf(1.0f, g_vm_swu + adt / g_vm_sw_dur);
            g_vm_sw_ur = adt > 1e-4f && !posed ? fmaxf(0.0f, (u - g_vm_swu) / adt) : 0.0f;
            g_vm_swu = u;
            g_vm_cur = vm_swing_at(g_vm_sw0, tgt, u);
            if (adt > 1e-4f) {                            /* carried into the spring when the swing ends / is cut */
                g_vm_vel.p = vm_mul(vm_sub(g_vm_cur.p, sw_prev.p), 1.0f / adt);
                g_vm_vel.f = vm_mul(vm_sub(g_vm_cur.f, sw_prev.f), 1.0f / adt);
                g_vm_vel.u = vm_mul(vm_sub(g_vm_cur.u, sw_prev.u), 1.0f / adt);
            }
            {   float step = acosf(fmaxf(-1.0f, fminf(1.0f, vm_dot(g_vm_cur.f, g_vm_sw_prevf)))) * 57.29578f;
                g_vm_sw_prevf = g_vm_cur.f; g_vm_sw_last_step = step; if (step > g_vm_sw_maxstep && g_vm_sw_n > 0) g_vm_sw_maxstep = step;
                if (g_vm_sw_n > 0 && g_vm_sw_n <= 128 && dt > 1e-4f) g_vm_sw_rate[g_vm_sw_n - 1] = step / dt;
                g_vm_sw_n++;
                float e = vm_elev_of(g_vm_mp), a = vm_az_of(g_vm_mp);
                if (e < g_vm_sw_emin) g_vm_sw_emin = e; if (e > g_vm_sw_emax) g_vm_sw_emax = e;
                if (a < g_vm_sw_amin) g_vm_sw_amin = a; if (a > g_vm_sw_amax) g_vm_sw_amax = a;
                if (g_vm_sw_log && !posed)
                    logline("[vmsw] #%d n=%d dt=%.3f u=%.3f prog=%.3f tgt=%.2f,%.2f,%.2f f=%.2f,%.2f,%.2f meas=%.2f,%.2f,%.2f mf=%.2f,%.2f,%.2f",
                            g_vm_swings, g_vm_sw_n, dt, u, g_fpc_fs_prog, g_vm_cur.p.x, g_vm_cur.p.y, g_vm_cur.p.z,
                            g_vm_cur.f.x, g_vm_cur.f.y, g_vm_cur.f.z, g_vm_mp.x, g_vm_mp.y, g_vm_mp.z, g_vm_mf.x, g_vm_mf.y, g_vm_mf.z);
            }
            if (u >= 1.0f && !posed) {
                g_vm_swing = 0;
                {   /* snap check: max vs median blade angular speed over the swing (frame-time independent) */
                    int m = g_vm_sw_n - 1 < 128 ? g_vm_sw_n - 1 : 128; float t[128];
                    memcpy(t, g_vm_sw_rate, sizeof(float) * (m > 0 ? m : 0));
                    for (int i = 1; i < m; i++) { float x = t[i]; int j = i - 1; while (j >= 0 && t[j] > x) { t[j+1] = t[j]; j--; } t[j+1] = x; }
                    g_vm_sw_rmed = m > 0 ? t[m / 2] : 0.0f; g_vm_sw_rmax = m > 0 ? t[m - 1] : 0.0f;
                }
                logline("[vm] swing #%d %.2fs u_end=%.2f prog=%.2f frames=%d maxstep=%.1f rate_max=%.0f rate_med=%.0f ratio=%.2f elev=%.1f..%.1f az=%.1f..%.1f",
                        g_vm_swings, g_vm_swt, g_vm_swu, g_fpc_fs_prog, g_vm_sw_n, g_vm_sw_maxstep,
                        g_vm_sw_rmax, g_vm_sw_rmed, g_vm_sw_rmed > 1.0f ? g_vm_sw_rmax / g_vm_sw_rmed : 0.0f,
                        g_vm_sw_emin, g_vm_sw_emax, g_vm_sw_amin, g_vm_sw_amax);
            }
        } else {
            float om = g_vm_phase != VMP_NORMAL ? g_vm_om_draw : 1.8f / (ti == VM_RELOAD ? g_vm_tau_rl : g_vm_tau);
            g_vm_xwp = 0;
            if (g_vm_class == 1 && g_vm_xwp_on && g_vm_phase == VMP_NORMAL) {
                float zc = g_vm_elb_zc; int hc = g_vm_cur.p.z < zc, ht = tgt.p.z < zc;
                if (hc != ht) {
                    /* two stages (PT17): first straight down at the current depth, then across the plane down there; a
                     * diagonal path crossed z 3.0-3.55 (the arm tube band) at y/z -0.5..-0.7: forearm cut open at the bottom edge */
                    int low = g_vm_cur.p.y < g_vm_xwp_y + g_vm_xwp_tol;
                    float wz = low ? (ht ? zc - g_vm_xwp_dz : zc + g_vm_xwp_dz) : g_vm_cur.p.z;
                    tgt.p = vm_v(0.5f * (g_vm_cur.p.x + tgt.p.x), g_vm_xwp_y, wz);
                    g_vm_xwp = 1 + !low; om = 1.8f / g_vm_tau;
                }
            }
            vm_pose_spring(&g_vm_cur, &g_vm_vel, tgt, om, adt);
        }
        /* fire kick (ranged) */
        if (g_vm_kick_t >= 0.0f) { g_vm_kick_t += adt; if (g_vm_kick_t > g_vm_kick_rise + g_vm_kick_dur) g_vm_kick_t = -1.0f; }
        g_vm_kick = vm_kick_env(g_vm_kick_t);
        float k = g_vm_kick_pose >= 0.0f ? g_vm_kick_pose : g_vm_kick;
        VmPose out = g_vm_cur;
        if (k > 0.0f && g_vm_class == 1) {
            float e = fminf(1.0f, k);
            out.p = vm_add(out.p, vm_mul(g_vm_kick_p, e));
            out.f = vm_add(out.f, vm_v(0, g_vm_kick_up * e, 0)); out = vm_pose_norm(out);
        }
        /* grip slide: the poses place the HAND (tuned so the wrist stays in front of the near clip and the arm leaves
         * at an edge); the weapon sits plsl further along its blade in that hand. Sliding the hand back instead put the
         * wrist behind the near clip in the recovery (z 2.79, s7 198-200) */
        if (g_vm_plsl[g_vm_class ? 1 : 0] != 0.0f && (g_vm_plfix & (g_vm_class ? 1 : 2)))
            out.p = vm_add(out.p, vm_mul(out.f, g_vm_plsl[g_vm_class ? 1 : 0]));
        /* wrist look-ahead (PT30): the next frames' output poses (melee): the swing path at the current progress rate,
         * else the pose spring toward the same target (exact for a constant target) */
        if (g_vm_wfix && g_vm_class == 0 && g_vm_elb_la) {
            float pdt = fminf(fmaxf(adt, 0.008f), 0.033f), u = g_vm_swu, ur = g_vm_sw_ur > 0.0f ? g_vm_sw_ur : 1.0f / g_vm_sw_dur;
            float om = g_vm_phase != VMP_NORMAL ? g_vm_om_draw : 1.8f / g_vm_tau;
            VmPose c = g_vm_cur, v = g_vm_vel; int sw = g_vm_swing; float sl = g_vm_plfix & 2 ? g_vm_plsl[0] : 0.0f;
            if (sw && posed) ur = 0.0f;
            for (int k = 0; k < g_vm_elb_lah && k < VM_LAH; k++) {
                if (sw) { VmPose cp = c; u = fminf(1.0f, u + ur * pdt); c = vm_swing_at(g_vm_sw0, tgt, u);
                    v.p = vm_mul(vm_sub(c.p, cp.p), 1.0f / pdt); v.f = vm_mul(vm_sub(c.f, cp.f), 1.0f / pdt); v.u = vm_mul(vm_sub(c.u, cp.u), 1.0f / pdt);
                    if (u >= 1.0f) sw = 0; }
                else vm_pose_spring(&c, &v, tgt, om, pdt);
                VmPose o = c; if (sl != 0.0f) o.p = vm_add(o.p, vm_mul(o.f, sl));
                g_vm_fut[k] = o; g_vm_fut_n = k + 1;
            }
        }
        g_vm_target_e = vm_elev_of(out.p); g_vm_target_a = vm_az_of(out.p);
        g_vm_out = out; g_vm_kick_eff = k;
        /* off-hand: under the fore-stock (support point, f,u,s weapon numbers) while aiming a crossbow; otherwise
         * the rest point out of view (the arm can't reach the fore-stock in the low ready/reload holds and a hand
         * floating under the bow looked broken). The target glides between the two (no snap). */
        Vec3 oc = g_vm_rest; g_vm_omode = 0;
        if (g_vm_class == 1 && ti == VM_AIM && g_vm_phase == VMP_NORMAL) {
            Vec3 s = vm_cross(out.f, out.u);
            oc = vm_add(out.p, vm_add(vm_add(vm_mul(out.f, g_vm_sup.x), vm_mul(out.u, g_vm_sup.y)), vm_mul(s, g_vm_sup.z)));
            g_vm_omode = 1;
        }
        if (!g_vm_have_oc) { g_vm_oc = oc; g_vm_ocv = vm_v(0, 0, 0); g_vm_have_oc = 1; }
        else vm_spring3(&g_vm_oc, &g_vm_ocv, oc, 1.8f / g_vm_tau, adt);
    }
targets:
    vm_targets();
    g_vm_have_t = g_vm_have_cur;
}

static void vm_frame(void *pc, int body_down)
{
    if (g_vm_fpscap > 0.5f) {                   /* test: low frame rate (choppiness shows there) */
        static LARGE_INTEGER fq, prev; LARGE_INTEGER now;
        if (!fq.QuadPart) QueryPerformanceFrequency(&fq);
        double per = 1.0 / g_vm_fpscap;
        for (;;) { QueryPerformanceCounter(&now);
            double el = prev.QuadPart ? (double)(now.QuadPart - prev.QuadPart) / (double)fq.QuadPart : per;
            if (el >= per) break;
            if (per - el > 0.002) Sleep(1); }
        prev = now;
    }
    if (g_vm_hitch_ms > 0 && ++g_vm_hitch_n >= (g_vm_hitch_per > 0 ? g_vm_hitch_per : 1)) {   /* test: game hitch */
        g_vm_hitch_n = 0; Sleep((DWORD)g_vm_hitch_ms); if (g_vm_hitch_per <= 0) g_vm_hitch_ms = 0;
    }
    vm_frame_core(pc, body_down);
    if (g_vm_rec_on && g_vm_rn < VM_RECN) {
        VmRec *q = &g_vm_rec[g_vm_rn++]; LARGE_INTEGER now, fq; QueryPerformanceCounter(&now); QueryPerformanceFrequency(&fq);
        q->t = (float)((double)(now.QuadPart - g_vm_rec_t0.QuadPart) / (double)fq.QuadPart); q->dt = g_vm_dt;
        snprintf(q->st, sizeof(q->st), "%s", g_vm_state ? g_vm_state : "?");
        q->ti = (signed char)g_vm_ti; q->cls = (unsigned char)g_vm_class; q->swing = (unsigned char)g_vm_swing;
        q->omode = (unsigned char)g_vm_omode; q->on = g_vm_have_t && g_vm_w > 0.001f;
        q->w = g_vm_w; q->swu = g_vm_swu; q->prog = g_fpc_fs_prog; q->kick = g_vm_kick_eff; q->fire = g_vm_fire_t;
        q->yaw = g_yaw * 57.29578f; q->pitch = g_pitch * 57.29578f; q->zoom = g_view.applied;
        q->out = g_vm_out; q->oc = g_vm_oc; q->mp = g_vm_mp; q->mf = g_vm_mf; q->mu = g_vm_mu;
        memcpy(q->mj, g_vm_mj, sizeof(q->mj));
        q->eye = g_vm_eye; q->rt = g_vm_rt; q->up = g_vm_up; q->fw = g_vm_fw;
        q->rootf = g_vm_root_f; q->roota = g_vm_root_a; q->napp = (unsigned)g_vm_napply;
        q->phase = (unsigned char)g_vm_phase; q->wih = (unsigned char)g_vm_wih;
        q->stch = g_vm_st_last[g_vm_whand[g_vm_class] ? 1 : 0];
        q->mh = g_vm_mh; q->hy = g_vm_mhy; q->hz = g_vm_mhz; q->mfx = g_vm_mfx; q->wb = g_vm_wb; q->zf = g_vm_zf; q->hd = g_vm_mhd; q->nk = g_vm_mnk; q->sp = g_vm_msp;
        if (g_vm_rn >= VM_RECN) g_vm_rec_on = 0;
    }
}
static int vm_rec_dump(const char *path)
{
    FILE *fo = fopen(path, "w"); if (!fo) return -1;
    fprintf(fo, "# n t dt st ti cls on w swing swu prog kick fire omode yaw pitch zoom | out p f u | oc | mp mf mu | Lsh Lel Lwr Rsh Rel Rwr | eye rt up fw (world) | rootf roota napply phase wih stretch | wb mh mfx zf head neck spine\n");
    for (int i = 0; i < g_vm_rn; i++) { const VmRec *q = &g_vm_rec[i];
        fprintf(fo, "%d %.4f %.4f %s %d %d %d %.3f %d %.4f %.4f %.3f %.3f %d %.2f %.2f %.2f |", i, q->t, q->dt, q->st, q->ti, q->cls, q->on,
                q->w, q->swing, q->swu, q->prog, q->kick, q->fire, q->omode, q->yaw, q->pitch, q->zoom);
        const Vec3 *v[] = { &q->out.p, &q->out.f, &q->out.u, &q->oc, &q->mp, &q->mf, &q->mu,
                            &q->mj[0][0], &q->mj[0][1], &q->mj[0][2], &q->mj[1][0], &q->mj[1][1], &q->mj[1][2], &q->eye, &q->rt, &q->up, &q->fw };
        for (int k = 0; k < 17; k++) fprintf(fo, k == 13 ? " | %.4f,%.4f,%.4f" : " %.4f,%.4f,%.4f", v[k]->x, v[k]->y, v[k]->z);
        fprintf(fo, " | %.4f,%.4f,%.4f %.4f,%.4f,%.4f %u %d %d %.3f", q->rootf.x, q->rootf.y, q->rootf.z, q->roota.x, q->roota.y, q->roota.z, q->napp, q->phase, q->wih, q->stch);
        fprintf(fo, " | %.1f %.4f,%.4f,%.4f %.4f,%.4f,%.4f %.3f %.4f,%.4f,%.4f %.4f,%.4f,%.4f %.4f,%.4f,%.4f %.4f,%.4f,%.4f %.4f,%.4f,%.4f\n", q->wb, q->mh.x, q->mh.y, q->mh.z,
                q->mfx.x, q->mfx.y, q->mfx.z, q->zf, q->hd.x, q->hd.y, q->hd.z, q->nk.x, q->nk.y, q->nk.z, q->sp.x, q->sp.y, q->sp.z,
                q->hy.x, q->hy.y, q->hy.z, q->hz.x, q->hz.y, q->hz.z); }
    fclose(fo); return g_vm_rn;
}

/* ---- tuning ---- */
static float *vm_vec_field(Vec3 *v, char c) { return c == 'x' ? &v->x : c == 'y' ? &v->y : c == 'z' ? &v->z : NULL; }
/* keys: <m|r>_<state>_<p|f|u><x|y|z>, sw<1..4>_<p|f|u><x|y|z>, swu<1..4>, ax_<m|r>_<f|u>, hand_<m|r>,
 * low_<m|r>_<p|f|u><x|y|z>, rest_<xyz>, sup_<xyz>, pole<m|r><L|R>_<xyz>, fire_hold, offnear, aimdist, tau, taurl, tauw, twist, sw_dur, sw_pose, kick_pose,
 * kick_<xyz>, kick_up, swlog */
static float *vm_pose_field(VmPose *p, const char *k)   /* k = "px" etc */
{
    if (strlen(k) != 2) return NULL;
    Vec3 *v = k[0] == 'p' ? &p->p : k[0] == 'f' ? &p->f : k[0] == 'u' ? &p->u : NULL;
    return v ? vm_vec_field(v, k[1]) : NULL;
}
static int vm_set(const char *k, float x)
{
    float *fp = NULL;
    if ((k[0] == 'm' || k[0] == 'r') && k[1] == '_') {
        int c = k[0] == 'r';
        for (int i = 0; i < VM_NT; i++) { size_t n = strlen(g_vm_tname[i]);
            if (!strncmp(k + 2, g_vm_tname[i], n) && k[2+n] == '_') { fp = vm_pose_field(&g_vm_pose[c][i], k + 3 + n); break; } }
    } else if (!strncmp(k, "low_", 4) && (k[4] == 'm' || k[4] == 'r') && k[5] == '_') fp = vm_pose_field(&g_vm_low[k[4] == 'r'], k + 6);
    else if (!strncmp(k, "sw", 2) && k[2] >= '1' && k[2] <= '0' + VM_SWK && k[3] == '_') fp = vm_pose_field(&g_vm_swk[k[2]-'1'], k + 4);
    else if (!strncmp(k, "swu", 3) && k[3] >= '1' && k[3] <= '0' + VM_SWK && !k[4]) fp = &g_vm_swk_u[k[3]-'0'];
    else if (!strncmp(k, "ax_", 3) && (k[3] == 'm' || k[3] == 'r') && k[4] == '_' && (k[5] == 'f' || k[5] == 'u')) {
        int c = x < 0 ? -(int)(-x + 0.5f) : (int)(x + 0.5f); if (c == 0 || c < -3 || c > 3) return 0;
        g_vm_ax[k[3] == 'r'][k[5] == 'u'] = c; return 1;
    }
    else if (!strcmp(k, "hand_m")) { g_vm_whand[0] = x != 0.0f; return 1; }
    else if (!strcmp(k, "hand_r")) { g_vm_whand[1] = x != 0.0f; return 1; }
    else if (!strcmp(k, "hand"))   { g_vm_whand[0] = g_vm_whand[1] = x != 0.0f; return 1; }
    else if (!strncmp(k, "rest_", 5)) fp = vm_vec_field(&g_vm_rest, k[5]);
    else if (!strncmp(k, "sup_", 4)) fp = vm_vec_field(&g_vm_sup, k[4]);
    else if (!strncmp(k, "pole", 4) && (k[4] == 'm' || k[4] == 'r') && (k[5] == 'L' || k[5] == 'R') && k[6] == '_')
        fp = vm_vec_field(&g_vm_pole[k[4] == 'r'][k[5] == 'R'], k[7]);
    else if (!strcmp(k, "fire_hold")) { if (x >= 0 && x < 3) g_vm_fire_hold = x; return 1; }
    else if (!strncmp(k, "kick_", 5) && k[5] && !k[6]) fp = vm_vec_field(&g_vm_kick_p, k[5]);
    else if (!strcmp(k, "kick_up")) fp = &g_vm_kick_up;
    else if (!strcmp(k, "kick_pose")) fp = &g_vm_kick_pose;
    else if (!strcmp(k, "offnear")) fp = &g_vm_off_near;
    else if (!strcmp(k, "aimdist")) fp = &g_vm_aim_dist;
    else if (!strcmp(k, "twist")) fp = &g_vm_twist;
    else if (!strcmp(k, "sw_pose")) fp = &g_vm_sw_pose;
    else if (!strcmp(k, "swlog")) { g_vm_sw_log = x != 0.0f; return 1; }
    else if (!strcmp(k, "applymap")) { g_vm_applymap = x != 0.0f; return 1; }
    else if (!strcmp(k, "groll"))   { if (x > -360 && x < 360) g_vm_groll[0] = x; return 1; }
    else if (!strcmp(k, "grollr"))  { if (x > -360 && x < 360) g_vm_groll[1] = x; return 1; }
    else if (!strcmp(k, "plsl"))    { if (x > -3 && x < 3) g_vm_plsl[0] = x; return 1; }
    else if (!strcmp(k, "plslr"))   { if (x > -3 && x < 3) g_vm_plsl[1] = x; return 1; }
    else if (!strcmp(k, "plfix"))   { g_vm_plfix = (int)x & 3; return 1; }
    else if (!strcmp(k, "omdraw"))  { if (x > 1 && x < 100) g_vm_om_draw = x; return 1; }
    else if (!strcmp(k, "maxdt"))   { if (x > 0.005f && x <= 0.1f) g_vm_maxdt = x; return 1; }
    else if (!strcmp(k, "lowerdur")) { if (x >= 0 && x < 2) g_vm_lower_dur = x; return 1; }
    else if (!strcmp(k, "kickrise")) { if (x > 0.005f && x < 1) g_vm_kick_rise = x; return 1; }
    else if (!strcmp(k, "kickdur"))  { if (x > 0.02f && x < 2) g_vm_kick_dur = x; return 1; }
    else if (!strcmp(k, "xwp"))     { g_vm_xwp_on = x > 0.5f; return 1; }
    else if (!strcmp(k, "xwpy"))    { if (x < 0 && x > -10) g_vm_xwp_y = x; return 1; }
    else if (!strcmp(k, "xwptol"))  { if (x >= 0 && x < 5) g_vm_xwp_tol = x; return 1; }
    else if (!strcmp(k, "xwpdz"))   { if (x > 0 && x < 5) g_vm_xwp_dz = x; return 1; }
    else if (!strcmp(k, "wfix"))    { g_vm_wfix = x > 0.5f; g_vm_have_elbe = 0; return 1; }
    else if (!strcmp(k, "wband"))   { if (x >= 0 && x < 90) g_vm_wband = x; return 1; }
    else if (!strcmp(k, "elbnat"))  { if (x >= 0 && x <= 1) g_vm_elb_nat = x; return 1; }
    else if (!strcmp(k, "wroll"))   { if (x >= 0 && x <= 1) g_vm_wroll = x; return 1; }
    else if (!strcmp(k, "zfade"))   { g_vm_zfade = x > 0.5f; return 1; }
    else if (!strcmp(k, "zf0"))     { if (x >= 0 && x < 50) g_vm_zf0 = x; return 1; }
    else if (!strcmp(k, "zf1"))     { if (x >= 0 && x < 50) g_vm_zf1 = x; return 1; }
    else if (!strcmp(k, "rlnat"))   { g_vm_rlnat = x != 0; return 1; }
    else if (!strcmp(k, "rltr"))    { if (x >= 0 && x <= 1) g_vm_rltr = x; return 1; }
    else if (!strcmp(k, "rlblend")) { if (x >= 0 && x <= 2) g_vm_rlblend = x; return 1; }
    else if (!strcmp(k, "rl_dy"))   { if (x >= -5 && x <= 5) g_vm_rl_dy = x; return 1; }
    else if (!strcmp(k, "rlper"))   { if (x > 0.2f && x < 5) g_vm_rl_per = x; return 1; }
    else if (!strcmp(k, "rlamp"))   { if (x >= 0 && x < 3) g_vm_rl_amp = x; return 1; }
    else if (!strcmp(k, "tau"))    { if (x > 0.005f && x < 2) g_vm_tau = x; return 1; }
    else if (!strcmp(k, "taurl"))  { if (x > 0.005f && x < 3) g_vm_tau_rl = x; return 1; }
    else if (!strcmp(k, "tauw"))   { if (x > 0.005f && x < 3) g_vm_tau_w = x; return 1; }
    else if (!strcmp(k, "swclock")) { g_vm_sw_clock = x != 0.0f; return 1; }
    else if (!strcmp(k, "sw_dur")) { if (x > 0.05f && x <= 12) g_vm_sw_dur = x; return 1; }
    else if (!strcmp(k, "edgeclamp")) { g_vm_eclamp = x != 0; return 1; }
    else if (!strcmp(k, "edgectol")) { if (x >= -1 && x <= 1) g_vm_ectol = x; return 1; }
    else if (!strcmp(k, "edgepen")) { if (x >= 0 && x <= 50) g_vm_edge_pen = x; return 1; }
    else if (!strcmp(k, "edgesgn")) { g_vm_edgesgn = x < 0 ? -1.0f : 1.0f; return 1; }
    else if (!strcmp(k, "elbslow")) { if (x >= 0 && x <= 2) g_vm_elb_slow = x; return 1; }
    else if (!strcmp(k, "elbsmall")) { if (x >= 0 && x <= 30) g_vm_elb_small = x; return 1; }
    else if (!strcmp(k, "elbhyst")) { if (x >= 0 && x <= 1) g_vm_elb_hyst = x; return 1; }
    else if (!strcmp(k, "nearclip")) { if (x >= 0 && x <= 10) g_vm_nc = x; return 1; }
    else if (!strcmp(k, "l1fix")) { g_vm_l1fix = x != 0; return 1; }
    else if (!strcmp(k, "fptol")) { g_vm_fptol = x != 0; return 1; }
    else if (!strcmp(k, "mapnode")) { g_vm_mapnode = x != 0; g_vm_map_resmax = 0; g_vm_have_moff = 0; return 1; }
    else if (!strcmp(k, "stdb")) { if (x >= 0 && x <= 0.5f) g_vm_stdb = x; return 1; }
    else if (!strcmp(k, "stretch")) { if (x >= 1 && x <= 2.5f) g_vm_stretch = x; return 1; }
    else if (!strcmp(k, "hroll"))   { if (x > -360 && x < 360) g_vm_hroll = x; return 1; }
    else if (!strcmp(k, "swbcap"))   { if (x >= 0.4f && x <= 5.0f) g_vm_swb_cap = x; return 1; }   /* elbow stretch cap in the swing->block pose only */
    else if (!strcmp(k, "edge"))      { g_vm_edge = x > 0.5f; return 1; }   /* S1 edge-away elbow pick */
    else if (!strcmp(k, "edgetol"))   { if (x >= -1.0f && x <= 1.0f) g_vm_edge_tol = x; return 1; }
    else if (!strcmp(k, "reseed"))    { g_vm_reseed_on = x > 0.5f; return 1; }   /* S2 */
    else if (!strcmp(k, "reseeddur")) { if (x >= 0.0f && x <= 2.0f) g_vm_reseed_dur = x; return 1; }
    else if (!strcmp(k, "reseedtau")) { if (x >= 0.0f && x <= 1.0f) g_vm_reseed_tau = x; return 1; }
    else if (!strcmp(k, "swbtrig"))  { if (x >= 1.0f && x <= 5.0f) g_vm_swb_trig = x; return 1; }
    else if (!strcmp(k, "swbtau"))   { if (x >= 0.0f && x <= 1.0f) g_vm_swb_tau = x; return 1; }
    else if (!strcmp(k, "elbstmax")) { if (x >= 0.4f && x <= 5.0f) g_vm_elb_stmax = x; return 1; }   /* upper-arm stretch cap of the elbow target (option B, Shay 2026-10-09) */
    else if (!strcmp(k, "elb"))     { g_vm_elb[0] = ((int)x) & 1; g_vm_elb[1] = (((int)x) >> 1) & 1; return 1; }
    else if (!strcmp(k, "elbdx"))   { g_vm_elbd.x = x; return 1; }
    else if (!strcmp(k, "elbdy"))   { g_vm_elbd.y = x; return 1; }
    else if (!strcmp(k, "elbdz"))   { g_vm_elbd.z = x; return 1; }
    else if (!strcmp(k, "elbm"))    { if (x >= 0 && x < 3) g_vm_elb_m = x; return 1; }
    else if (!strcmp(k, "elbzc"))   { if (x >= 0 && x < 10) g_vm_elb_zc = x; return 1; }
    else if (!strcmp(k, "elbr"))    { if (x >= 0 && x < 2) g_vm_elb_r = x; return 1; }
    else if (!strcmp(k, "elbrate")) { if (x > 0 && x < 100000) g_vm_elb_rate = x; return 1; }
    else if (!strcmp(k, "elbdmax")) { if (x >= 0 && x < 45) g_vm_elb_dmax = x; return 1; }
    else if (!strcmp(k, "elbla"))   { g_vm_elb_la = x > 0.5f; return 1; }
    else if (!strcmp(k, "elblah"))  { if (x >= 1 && x <= VM_LAH) g_vm_elb_lah = (int)x; return 1; }
    else if (!strcmp(k, "elblama")) { if (x >= 0 && x < 180) g_vm_elb_lama = x; return 1; }
    else if (!strcmp(k, "elblawm")) { if (x >= 0 && x < 10) g_vm_elb_lawm = x; return 1; }
    else if (!strcmp(k, "wrl"))     { if (x >= 0 && x < 20) { g_vm_wrl = x; g_vm_have_rs = 0; } return 1; }
    else if (!strcmp(k, "wrlmin"))  { if (x >= 0 && x < 90) g_vm_wrlmin = x; return 1; }
    else if (!strcmp(k, "wrlwarm")) { g_vm_wrlwarm = x > 0.5f; return 1; }
    else if (!strcmp(k, "wrllag"))  { if (x >= 0 && x < 180) g_vm_wrllag = x; return 1; }
    else if (!strcmp(k, "elbptau")) { if (x >= 0 && x < 1) g_vm_elb_ptau = x; return 1; }
    else if (!strcmp(k, "rbw"))     { if (x >= 0 && x < 20) g_vm_rbw = x; return 1; }
    else if (!strcmp(k, "rbwr"))    { if (x >= 0 && x < 20) g_vm_rbwr = x; return 1; }
    else if (!strcmp(k, "elbkeep")) { if (x >= 0 && x < 20) g_vm_elb_keep = x; return 1; }
    else if (!strcmp(k, "elbtau"))  { if (x > 0.001f && x < 1) g_vm_elb_tau = x; return 1; }
    else if (!strcmp(k, "stmax"))   { g_vm_st_max[0] = g_vm_st_max[1] = 1.0f; return 1; }
    else if (!strcmp(k, "hitch"))   { g_vm_hitch_ms = x >= 0 && x <= 500 ? (int)x : 0; g_vm_hitch_n = 0; return 1; }
    else if (!strcmp(k, "hitchper")) { g_vm_hitch_per = x >= 0 && x <= 10000 ? (int)x : 0; return 1; }
    else if (!strcmp(k, "fpscap")) { g_vm_fpscap = x >= 5 && x <= 1000 ? x : 0.0f; return 1; }
    if (!fp) return 0;
    *fp = x; return 1;
}

static int vm_ini(const char *line)
{
    int v; float fv; char key[48];
    if (ini_int(line, "viewmodel", &v)) { g_cfg_vm = !!v; return 1; }
    /* vm_<key>=<v> for any fp_vm set key */
    if (strncmp(line, "vm_", 3)) return 0;
    const char *eq = strchr(line, '='); size_t n = eq ? (size_t)(eq - line - 3) : 0;
    if (!eq || n == 0 || n >= sizeof(key)) return 0;
    memcpy(key, line + 3, n); key[n] = 0;
    while (n && (key[n-1] == ' ' || key[n-1] == '\t')) key[--n] = 0;
    fv = (float)atof(eq + 1);
    return vm_set(key, fv);
}

static int kah_fp_vm(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)u;
    char b[2600];
    const char *a = argc > 1 ? argv[1] : "state";
    if (!strcmp(a, "on"))  { g_cfg_vm = 1; g_vm_dead = 0; }
    else if (!strcmp(a, "off")) g_cfg_vm = 0;
    else if (!strcmp(a, "set") && argc > 3) {
        if (!vm_set(argv[2], (float)atof(argv[3]))) {
            r->append(r, "keys: <m|r>_<ready|aim|reload|block>_<p|f|u><x|y|z> sw<1-4>_<p|f|u><x|y|z> swu<1-4> ax_<m|r>_<f|u> (+-1..3) "
                         "hand_m hand_r rest_<xyz> sup_<xyz> pole<m|r><L|R>_<xyz> fire_hold offnear aimdist twist tau taurl tauw "
                         "sw_dur sw_pose(-1 off) kick_pose(-1 off) kick_<xyz> kick_up swlog");
            return KAH_ERROR;
        }
    } else if (!strcmp(a, "rec") && argc > 2) {
        if (!strcmp(argv[2], "on")) { if (!g_vm_rec) g_vm_rec = (VmRec *)calloc(VM_RECN, sizeof(VmRec)); if (!g_vm_rec) { r->append(r, "rec: no memory"); return KAH_ERROR; } g_vm_rn = 0; QueryPerformanceCounter(&g_vm_rec_t0); g_vm_rec_on = 1; }
        else if (!strcmp(argv[2], "off")) g_vm_rec_on = 0;
        else if (!strcmp(argv[2], "dump") && argc > 3) { int n = vm_rec_dump(argv[3]);
            snprintf(b, sizeof(b), "rec dump %s frames=%d", argv[3], n); r->append(r, b); return n < 0 ? KAH_ERROR : KAH_OK; }
        snprintf(b, sizeof(b), "rec on=%d frames=%d", g_vm_rec_on, g_vm_rn); r->append(r, b); return KAH_OK;
    } else if (!strcmp(a, "replay") && argc > 2) {
        if (!strcmp(argv[2], "off")) g_vm_rp = -1;
        else { int n = atoi(argv[2]); if (n < 0 || n >= g_vm_rn) { r->append(r, "replay: no such frame"); return KAH_ERROR; }
               g_vm_rp_t = argc > 3 && argv[3][0] == 't'; g_vm_rp = n; }
        const VmRec *q = g_vm_rp >= 0 ? &g_vm_rec[g_vm_rp] : NULL;
        if (q) snprintf(b, sizeof(b), "replay %d st=%s ti=%d cls=%d w=%.2f swu=%.3f kick=%.2f t=%.3f", g_vm_rp, q->st, q->ti, q->cls, q->w, q->swu, q->kick, q->t);
        else snprintf(b, sizeof(b), "replay off");
        r->append(r, b); return KAH_OK;
    } else if (!strcmp(a, "bones")) {
        /* list skeleton bones (index name local-ori) whose name contains the filter (default "Finger") */
        typedef unsigned short (*nb_t)(void *); typedef void *(*bi_t)(void *, unsigned short); typedef const void *(*nm_t)(void *);
        HMODULE og = GetModuleHandleA("OgreMain_x64.dll");
        nb_t nb = og ? (nb_t)GetProcAddress(og, "?getNumBones@Skeleton@Ogre@@UEBAGXZ") : NULL;
        bi_t bi = og ? (bi_t)GetProcAddress(og, "?getBone@Skeleton@Ogre@@UEBAPEAVOldBone@2@G@Z") : NULL;
        nm_t nm = og ? (nm_t)GetProcAddress(og, "?getName@OldNode@Ogre@@QEBAAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@XZ") : NULL;
        const char *flt = (argc > 2 && argv[2][0]) ? argv[2] : "Finger";
        int n = snprintf(b, sizeof(b), "bones nb=%d bi=%d nm=%d skel=%p", nb != NULL, bi != NULL, nm != NULL, g_vm_skel);
        if (nb && bi && nm && readable(g_vm_skel, 8)) {
            unsigned short cnt = nb(g_vm_skel); n += snprintf(b + n, sizeof(b) - n, " n=%u", cnt);
            for (unsigned short i = 0; i < cnt && n < (int)sizeof(b) - 120; i++) {
                void *bo = bi(g_vm_skel, i); if (!readable(bo, 8)) continue;
                const unsigned char *st = (const unsigned char *)nm(bo); if (!readable((void *)st, 32)) continue;
                size_t res = *(const size_t *)(st + 24); const char *str = res >= 16 ? *(const char *const *)st : (const char *)st;
                if (!readable((void *)str, 4) || !strstr(str, flt)) continue;
                const Quat *q = g_oldnode_getori(bo); const Vec3 *ps = g_oldnode_getpos(bo);
                n += snprintf(b + n, sizeof(b) - n, " | %u %.40s q=%.3f,%.3f,%.3f,%.3f p=%.2f,%.2f,%.2f", i, str,
                              q ? q->w : 0, q ? q->x : 0, q ? q->y : 0, q ? q->z : 0, ps ? ps->x : 0, ps ? ps->y : 0, ps ? ps->z : 0);
            }
        }
        r->append(r, b); return KAH_OK;
    } else if (!strcmp(a, "probe")) {
        /* native (pre-IK) prop + hand axes of both sides in camera numbers */
        int n = snprintf(b, sizeof(b), "probe nat=%d scale=%.3f", g_vm_nat_ok, g_vm_scale);
        for (int i = 0; i < 2 && g_vm_nat_ok; i++) {
            Vec3 pp = vm_w2c_dir(vm_sub(vm_add(g_vm_cmw, vm_s2w_dir(vm_sub(g_vm_npp[i], g_vm_cms))), g_vm_eye));
            n += snprintf(b + n, sizeof(b) - n, " %c: p=%.2f,%.2f,%.2f", i ? 'R' : 'L', pp.x, pp.y, pp.z);
            for (int ax = 1; ax <= 3; ax++) {
                Vec3 c = vm_norm(vm_w2c_dir(vm_s2w_dir(quat_rotvec(g_vm_npq[i], vm_axis(ax)))));
                n += snprintf(b + n, sizeof(b) - n, " %c=%.2f,%.2f,%.2f", 'W' + ax, c.x, c.y, c.z);
            }
            float dn = g_vm_scale * vm_len(vm_sub(g_vm_nhp[!i], g_vm_npp[i]));
            n += snprintf(b + n, sizeof(b) - n, " offdist=%.2f", dn);
        }
        snprintf(b + n, sizeof(b) - n, " near=%d orel=%d", g_vm_off_near_now, g_vm_have_orel);
        r->append(r, b); return KAH_OK;
    } else if (!strcmp(a, "dump")) {
        int n = 0;
        for (int c = 0; c < 2; c++) for (int i = 0; i < VM_NT; i++) { VmPose *p = &g_vm_pose[c][i];
            n += snprintf(b + n, sizeof(b) - n, "%c_%s p=%.2f,%.2f,%.2f f=%.2f,%.2f,%.2f u=%.2f,%.2f,%.2f | ", c ? 'r' : 'm', g_vm_tname[i],
                          p->p.x, p->p.y, p->p.z, p->f.x, p->f.y, p->f.z, p->u.x, p->u.y, p->u.z); }
        for (int i = 0; i < VM_SWK; i++) { VmPose *p = &g_vm_swk[i];
            n += snprintf(b + n, sizeof(b) - n, "sw%d@%.2f p=%.2f,%.2f,%.2f f=%.2f,%.2f,%.2f u=%.2f,%.2f,%.2f | ", i + 1, g_vm_swk_u[i+1],
                          p->p.x, p->p.y, p->p.z, p->f.x, p->f.y, p->f.z, p->u.x, p->u.y, p->u.z); }
        snprintf(b + n, sizeof(b) - n, "ax m=%d,%d r=%d,%d hand m=%d r=%d rest=%.1f,%.1f,%.1f sup=%.1f,%.1f,%.1f polemR=%.1f,%.1f,%.1f polerL=%.1f,%.1f,%.1f polerR=%.1f,%.1f,%.1f",
                 g_vm_ax[0][0], g_vm_ax[0][1], g_vm_ax[1][0], g_vm_ax[1][1], g_vm_whand[0], g_vm_whand[1],
                 g_vm_rest.x, g_vm_rest.y, g_vm_rest.z, g_vm_sup.x, g_vm_sup.y, g_vm_sup.z,
                 g_vm_pole[0][1].x, g_vm_pole[0][1].y, g_vm_pole[0][1].z, g_vm_pole[1][0].x, g_vm_pole[1][0].y, g_vm_pole[1][0].z,
                 g_vm_pole[1][1].x, g_vm_pole[1][1].y, g_vm_pole[1][1].z);
        r->append(r, b); return KAH_OK;
    } else if (strcmp(a, "state")) { r->append(r, "usage: fp_vm state|probe|dump|on|off|set <key> <value>|rec on|off|dump <file>|replay <n> [t]|off"); return KAH_ERROR; }
    snprintf(b, sizeof(b),
        "vm on=%d hooked=%d dead=%d state=%s hold=%d w=%.2f class=%s elev=%.1f az=%.1f target=%.1f,%.1f basis=%d "
        "hand=%c lh=%.1f,%.1f rh=%.1f,%.1f melee=%d tilt=%.1f swing=%d swu=%.2f swings=%d sw_maxstep=%.1f "
        "sw_ratio=%.2f sw_elev=%.1f,%.1f sw_az=%.1f,%.1f kicks=%d kick=%.2f fire=%.2f mp=%.2f,%.2f,%.2f mf=%.2f,%.2f,%.2f mu=%.2f,%.2f,%.2f tp=%.2f,%.2f,%.2f tf=%.2f,%.2f,%.2f "
        "near=%d calls=%lu applied=%lu reuse=%lu ikfail=%lu frames=%lu zoom=%.2f "
        "pl=%d,%d plq0=%.3f,%.3f,%.3f,%.3f plp0=%.3f,%.3f,%.3f plq1=%.3f,%.3f,%.3f,%.3f plp1=%.3f,%.3f,%.3f phase=%d hpend=%d hprog=%.2f "
        "omode=%d oerr=%.2f Lsh=%.2f,%.2f,%.2f Lel=%.2f,%.2f,%.2f Lwr=%.2f,%.2f,%.2f Rsh=%.2f,%.2f,%.2f Rel=%.2f,%.2f,%.2f Rwr=%.2f,%.2f,%.2f stretch=%.2f,%.2f st_max=%.2f,%.2f elb=%d,%d,%.2f elbe=%.2f,%.2f,%.2f xwp=%d wb=%.1f mh=%.2f,%.2f,%.2f zf=%.2f wfix=%d pk=%u,%u,%u,%u hd=%.2f,%.2f,%.2f nk=%.2f,%.2f,%.2f sp=%.2f,%.2f,%.2f swb=%d,%.2f,%.2f,%.2f edge=%d,%.1f,%.2f,%d rsd=%.2f",
        g_cfg_vm, g_vm_hooked, g_vm_dead, g_vm_state, g_vm_hold, g_vm_w, g_vm_class ? "ranged" : "melee",
        g_vm_elev, g_vm_az, g_vm_target_e, g_vm_target_a, g_vm_basis_ok,
        g_vm_hand ? 'R' : 'L', g_vm_he[0], g_vm_ha[0], g_vm_he[1], g_vm_ha[1], g_vm_melee, g_vm_tilt_cur,
        g_vm_swing, g_vm_swu, g_vm_swings, g_vm_sw_maxstep, g_vm_sw_rmed > 1.0f ? g_vm_sw_rmax / g_vm_sw_rmed : 0.0f,
        g_vm_sw_emin, g_vm_sw_emax, g_vm_sw_amin, g_vm_sw_amax,
        g_vm_kicks, g_vm_kick, g_vm_fire_t, g_vm_mp.x, g_vm_mp.y, g_vm_mp.z, g_vm_mf.x, g_vm_mf.y, g_vm_mf.z, g_vm_mu.x, g_vm_mu.y, g_vm_mu.z,
        g_vm_cur.p.x, g_vm_cur.p.y, g_vm_cur.p.z, g_vm_cur.f.x, g_vm_cur.f.y, g_vm_cur.f.z,
        g_vm_off_near_now, g_vm_calls, g_vm_applied, g_vm_reuse, g_vm_ikfail, g_vm_frames, g_view.applied,
        g_vm_have_pl[0], g_vm_have_pl[1], g_vm_plq[0].w, g_vm_plq[0].x, g_vm_plq[0].y, g_vm_plq[0].z, g_vm_plp[0].x, g_vm_plp[0].y, g_vm_plp[0].z,
        g_vm_plq[1].w, g_vm_plq[1].x, g_vm_plq[1].y, g_vm_plq[1].z, g_vm_plp[1].x, g_vm_plp[1].y, g_vm_plp[1].z,
        g_vm_phase, g_fpc_holster_pending, g_fpc_holster_prog, g_vm_omode, g_vm_oerr,
        g_vm_mj[0][0].x, g_vm_mj[0][0].y, g_vm_mj[0][0].z, g_vm_mj[0][1].x, g_vm_mj[0][1].y, g_vm_mj[0][1].z,
        g_vm_mj[0][2].x, g_vm_mj[0][2].y, g_vm_mj[0][2].z, g_vm_mj[1][0].x, g_vm_mj[1][0].y, g_vm_mj[1][0].z,
        g_vm_mj[1][1].x, g_vm_mj[1][1].y, g_vm_mj[1][1].z, g_vm_mj[1][2].x, g_vm_mj[1][2].y, g_vm_mj[1][2].z,
        g_vm_st_last[0], g_vm_st_last[1], g_vm_st_max[0], g_vm_st_max[1],
        g_vm_elb[g_vm_class ? 1 : 0], g_vm_elb_ok, g_vm_elb_w, g_vm_elbe.x, g_vm_elbe.y, g_vm_elbe.z, g_vm_xwp, g_vm_wb, g_vm_mh.x, g_vm_mh.y, g_vm_mh.z, g_vm_zf, g_vm_wfix, g_vm_pk[0], g_vm_pk[1], g_vm_pk[2], g_vm_pk[3],
        g_vm_mhd.x, g_vm_mhd.y, g_vm_mhd.z, g_vm_mnk.x, g_vm_mnk.y, g_vm_mnk.z, g_vm_msp.x, g_vm_msp.y, g_vm_msp.z, g_vm_swb, g_vm_swb_w, vm_stmax(), g_vm_s2_want,
        g_vm_edge && g_vm_have_ekap, g_vm_ekap * 57.29578f, g_vm_edge_pred, g_vm_edge_nok, g_vm_reseed);
    r->append(r, b);
    return KAH_OK;
}
