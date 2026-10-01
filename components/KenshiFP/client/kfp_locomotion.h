/* KenshiFP custom locomotion — pre-retargeted Bip01 clips (KFA2) played on manual bones,
 * mixed at runtime into a movement-driven 8-way blendspace + procedural turn-in-place.
 *
 * This header is #included ONCE into kenshifp_client.c, AFTER the shared Vec3/Quat types and
 * the quat helpers (quat_mul/norm/slerp/conj/rotvec) and the Ogre bone-op function pointers
 * (g_skel_getbone, g_oldnode_getinitori/getdori, g_oldnode_setori, g_oldnode_needupd,
 * g_oldbone_setmanual, g_disable_bone) are defined -- single translation unit.
 *
 * ALL retarget math (Destreza Humanoid_ -> Bip01) runs OFFLINE in tools/retarget_locomotion.py,
 * which bakes ready-to-play Bip01 LOCAL rotations into locomotion.kfa (KFA2). That mirrors how
 * every shipped Kenshi animation mod works. The runtime here samples the baked clips, mixes
 * them (spec re/LOCOMOTION_SPEC.md §D), applies turn-in-place (§E, simplified rotation-only),
 * and writes LOCAL orientations. Locals are facing-invariant -- Kenshi yaws the Bip01 root.
 *
 * Two engine flags are BOTH required per controlled bone (proven in-game 2026-07-30):
 *   OldBone::setManuallyControlled(1)            -- stops Ogre-side animation, AND
 *   OldSkeletonInstance::disableBone(name, 1)    -- stops KENSHI's own per-bone-masked layers.
 *
 * Blendspace (§D): shared normalized phase; 8 direction clips per gait tier (walk/jog);
 * moveAngle picks the two adjacent tiers to slerp; gait (from measured speed) mixes walk->jog;
 * idle<->locomotion crossfade; reversal latch snapshots the pose instead of spinning through.
 * Turn-in-place (§E simplified): per-foot yaw locks counter-rotate the legs so the feet stay
 * directionally planted while the game yaws the body; past TIP_STEP_ANGLE the foot "steps"
 * over TIP_STEP_TIME, borrowing the walk clip's swing pose for a natural leg lift.
 *
 * KFA2 layout: see tools/retarget_locomotion.py docstring.
 * [[kenshifp-custom-locomotion]]
 */
#ifndef KFP_LOCOMOTION_H
#define KFP_LOCOMOTION_H

#define KFA_MAXNAME 48

typedef struct {
    char   name[KFA_MAXNAME];  /* "Bip01 ..." target bone */
    int    flags;              /* 1 = hold (park at bind), 2 = hips (optional) */
    int    group;              /* ownership group: 0 = legs (thighs/calves/feet/toes),
                                * 1 = core (pelvis; the root rides with it), 2 = upper
                                * (spine/clavicles/arms/hands). While idle everything is
                                * released; TIP turns own ONLY the legs (core+upper stay
                                * fully vanilla); moving owns all three. */
    Quat   bindRot;            /* baker's bind local (reference; engine initial state is authoritative) */
} kfa_bone;

typedef struct {
    char    name[KFA_MAXNAME];
    float   fps;
    int     keys;
    float   length;            /* seconds */
    float **rot;               /* [numBones] each keys*4 xyzw LOCAL rot, or NULL if no track */
} kfa_clip;

static struct {
    int       loaded;
    int       numBones, numClips;
    kfa_bone *bones;
    kfa_clip *clips;
} g_kfa;

/* ---- config (ini) ---- */
static int   g_cfg_loco      = 0;     /* master enable (ini: locomotion) */
static int   g_cfg_loco_clip = -1;    /* -1 = full blendspace (normal); >=0 = force ONE clip (debug) */
static int   g_cfg_loco_hips = 1;     /* 1 = play the pelvis track (self-consistent with the baked
                                       * child locals + hip sway); 0 = parked at bind (debug) */
static float g_cfg_loco_walkref = 14.0f;  /* pure speed (units/s, game-speed divided out) of a walk */
static float g_cfg_loco_jogref  = 38.0f;  /* pure speed of a jog -- gait blends between the two */
static int   g_cfg_loco_facelock = 1;     /* 1 = body faces the CAMERA (true-FP strafe movement +
                                           * turn-in-place); 0 = vanilla orient-to-motion */
static float g_cfg_tip_start_deg = 35.0f; /* camera deviation that triggers a turn-in-place */
static float g_cfg_tip_turn_deg  = 180.0f;/* turn-in-place swivel rate (deg/s) */
static float g_cfg_headmax_deg   = 83.0f; /* neck-twist cap (Destreza HeadMax 1.45 rad): the
                                           * camera cannot yaw past this off the body while
                                           * standing -- the mouse drags the body through the
                                           * turn instead of free-spinning. 0 = no cap */
static int   g_cfg_loco_aim      = 1;     /* aim offsets: spine follows the camera pitch and
                                           * leads its yaw while moving (Destreza ApplyAimOffset) */
static float g_cfg_loco_aim_p    = 1.2f;  /* pitch gain (scales the .12/.15/.16 chain weights) */
static float g_cfg_loco_aim_y    = 0.8f;  /* yaw-lead gain */
static float g_cfg_loco_aim_r    = 0.5f;  /* roll bank: fraction of the yaw offset applied as a
                                           * lateral lean (look right -> torso tilts right) */
static float g_cfg_loco_lean     = 0.5f;  /* accel-lean spring gain multiplier (Destreza torso
                                           * lean: the body leans INTO starts/stops/strafes) */
static float g_cfg_loco_brake    = 6.0f;  /* glide brake (1/s): extra exponential damping on
                                           * the momentum slide after key release -- ~6 halves
                                           * the vanilla glide across walk/jog/sprint */
static float g_cfg_loco_frate    = 10.0f; /* moving body-follow: catch-up rate (rad/s) */
static float g_cfg_ik_lift       = 0.12f; /* lift pad added to RAISING foot corrections
                                           * (units; negative lowers). Hot-tune on stairs:
                                           * foot in the ground -> raise, hovering -> lower */
static int   g_cfg_loco_footik   = 1;     /* foot-to-ground IK: plant the feet on terrain/
                                           * stairs while we own the legs (TIP, stop-settle,
                                           * idle slope-claim). Uses the engine's ground
                                           * query, so building floors work too */
static float g_cfg_loco_fdead    = 0.0f;  /* moving body-follow deadzone (deg). 0 = body glued
                                           * to the camera while moving (no sustained yaw twist
                                           * in motion -- the yaw offsets are an IDLE behavior) */

/* ---- tuning constants (spec §D/§E) ---- */
#define LOCO_XFADE_T     0.30f   /* idle<->locomotion crossfade seconds */
#define LOCO_GAIT_RATE   6.0f    /* gait ease rate (1/s, exponential) */
#define LOCO_TURN_RATE   4.0f    /* moveAngle ease cap (rad/s) */
#define LOCO_REVERSAL    2.0f    /* |angle jump| beyond which we latch + pose-fade (rad) */
#define LOCO_FADE_T      0.25f   /* acquire/reversal pose crossfade seconds */
#define TIP_STEP_ANGLE   0.30f   /* body-vs-foot yaw error that triggers a step (rad) */
#define TIP_STEP_TIME    0.18f   /* seconds per turn-in-place step */
#define TIP_STEP_BLEND   0.70f   /* how much of the walk swing pose the stepping leg borrows */
#define TIP_ENGAGE_MB    0.35f   /* turn-in-place active while moveblend below this */
#define TIP_SWING_PH_L   0.30f   /* walk_F phase sampled for a LEFT-foot step pose */
#define TIP_SWING_PH_R   0.80f   /* ...and for a RIGHT-foot step */

/* ---- inputs, fed by the .c every frame BEFORE loco_update ---- */
static float g_loco_in_speed;    /* pure horizontal speed, units/s (game-speed divided out) */
static float g_loco_in_gs;       /* game-speed multiplier (scales animation time; 0 = paused) */
static int   g_loco_in_moving;   /* any WASD movement key held */
static float g_loco_in_heading;  /* world yaw of the commanded movement (valid when moving) */
static float g_loco_in_bodyyaw;  /* COMMANDED body yaw (facing lock) -- authoritative moveAngle
                                  * reference, no root calibration needed */
static int   g_loco_in_havebody;
static int   g_loco_in_turning;  /* TIP swivel in progress (fp_movement state machine) */
static int   g_loco_in_sneak;    /* Character::stealthMode -- selects the crouch clip set */
static float g_loco_in_pitch;    /* camera pitch (radians, + = looking down) */
static float g_loco_in_camyaw;   /* camera yaw -- vs bodyyaw it yields the aim yaw-lead */
static float g_loco_in_velx, g_loco_in_velz;  /* world velocity (accel-lean spring input) */
static float g_loco_in_posx, g_loco_in_posy, g_loco_in_posz;  /* character world position */
static int   g_loco_in_air;      /* fall/jump arc owns the body (fp_fall walk-off tier) --
                                  * ground foot-IK is meaningless, legs air-tuck instead */
static float g_loco_in_airtuck;  /* Destreza AirPose envelope, 0..0.85: zero at takeoff,
                                  * peak at the apex, back to zero as fall speed builds
                                  * (0.85 * max(0, 1 - |velY| / jumpVel), client-fed) */
static float g_loco_in_airland;  /* landing anticipation, 0..1 over the last ~0.25s of
                                  * the arc (client-fed from time-to-impact): ramps the
                                  * plant IK IN and the tuck OUT while still airborne,
                                  * so the feet reach down and pre-shape to the landing
                                  * surface BEFORE contact -- no neutral-landing pop */
static float (*g_loco_in_groundfn)(const Vec3 *p);  /* optional ground override
                                  * (perch mode: true mesh-surface heights so the
                                  * foot IK plants on the rock, not the terrain
                                  * far beneath it). Return <= -99998 to fall
                                  * through to the engine query. */
static float loco_gnd_q(const Vec3 *p)
{
    if (g_loco_in_groundfn) {
        float y = g_loco_in_groundfn(p);
        if (y > -99998.0f) return y;
    }
    return ((float (*)(const Vec3 *, char, char))(g_base + RVA_GROUND_AT))(p, 1, 0);
}


/* foot-IK state: measured at setup from the bind pose */
static float g_ik_a[2], g_ik_b[2];       /* thigh / shin lengths per leg */
static Vec3  g_ik_thighoff[2];           /* thigh initPos in pelvis frame */
static Vec3  g_ik_calfoff[2], g_ik_footoff[2];  /* calf/foot offsets (parent frames, SCALED) */
static Vec3  g_ik_toeoff[2];             /* toe offset in the foot frame (scaled) */
static float g_ik_toey;                  /* toe contact height at stance */
static Vec3  g_ik_bindfoot[2];           /* bind-global ankle positions (slope probe) */
static float g_ik_ankle0;                /* bind ankle height over ground (the "sole") */
static Vec3  g_root_bindpos;             /* bind-global root position */
static Quat  g_pelvis_bindL; static Vec3 g_pelvis_bindoff;   /* pelvis initPos in root frame */
static float g_ik_w;                     /* eased IK weight */
static float g_ik_drop;                  /* eased pelvis drop (skeleton units, <= 0) */
static int   g_ik_pospushed;             /* pelvis position written (must restore on release) */
static int   g_slope_hold;               /* idle slope-claim latch (hysteresis) */

/* torso accel-lean spring state (Destreza Player.cs, web main.ts:7396-7424) */
static float g_lean_f, g_lean_fv, g_lean_r, g_lean_rv;
static float g_lean_vsx, g_lean_vsz;   /* velocity low-pass (accel proxy) */

/* ---- small vector/quat helpers for the foot IK ---- */
static inline Vec3 v3_sub(Vec3 a, Vec3 b){ return (Vec3){ a.x-b.x, a.y-b.y, a.z-b.z }; }
static inline Vec3 v3_add(Vec3 a, Vec3 b){ return (Vec3){ a.x+b.x, a.y+b.y, a.z+b.z }; }
static inline Vec3 v3_scale(Vec3 a, float s){ return (Vec3){ a.x*s, a.y*s, a.z*s }; }
static inline float v3_dot(Vec3 a, Vec3 b){ return a.x*b.x + a.y*b.y + a.z*b.z; }
static inline Vec3 v3_cross(Vec3 a, Vec3 b){
    return (Vec3){ a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x };
}
static inline float v3_len(Vec3 a){ return sqrtf(v3_dot(a,a)); }
static inline Vec3 v3_norm(Vec3 a){
    float l = v3_len(a);
    return (l > 1e-12f) ? v3_scale(a, 1.0f/l) : (Vec3){ 0, 0, 0 };
}
static Quat loco_axis_angle(Vec3 a, float ang);   /* defined in the playback section */
/* minimal rotation taking unit vector a onto unit vector b */
static Quat quat_arc(Vec3 a, Vec3 b){
    float d = v3_dot(a, b);
    if (d >  0.999999f) return (Quat){ 1, 0, 0, 0 };
    if (d < -0.999999f){
        Vec3 ax = v3_cross((Vec3){1,0,0}, a);
        if (v3_dot(ax,ax) < 1e-12f) ax = v3_cross((Vec3){0,1,0}, a);
        return loco_axis_angle(ax, 3.14159265f);
    }
    Vec3 ax = v3_cross(a, b);
    if (d < -1) d = -1; if (d > 1) d = 1;
    return loco_axis_angle(ax, acosf(d));
}

/* Resolve "<dll dir>\locomotion.kfa" (next to KenshiFP.dll, same as KenshiFP.ini). */
static const char *kfp_loco_path(void){
    static char path[MAX_PATH];
    wchar_t dllw[MAX_PATH];
    DWORD n = GetModuleFileNameW(g_hinst, dllw, MAX_PATH);
    if (n && n < MAX_PATH){
        char dlla[MAX_PATH];
        int k = WideCharToMultiByte(CP_UTF8, 0, dllw, -1, dlla, sizeof dlla, NULL, NULL);
        if (k > 0){
            char *slash = strrchr(dlla, '\\');
            if (slash){ *slash = 0; snprintf(path, sizeof path, "%s\\locomotion.kfa", dlla); return path; }
        }
    }
    strcpy(path, "locomotion.kfa");   /* CWD fallback (game root) */
    return path;
}

/* little-endian readers over an in-memory buffer */
static int      g_kfa_off;
static const unsigned char *g_kfa_buf;
static long     g_kfa_size;
static int      kfa_ok(int need){ return g_kfa_off >= 0 && g_kfa_off + need <= g_kfa_size; }
static unsigned kfa_u32(void){ if(!kfa_ok(4)){g_kfa_off=-1;return 0;} unsigned v; memcpy(&v,g_kfa_buf+g_kfa_off,4); g_kfa_off+=4; return v; }
static int      kfa_i32(void){ return (int)kfa_u32(); }
static unsigned kfa_u16(void){ if(!kfa_ok(2)){g_kfa_off=-1;return 0;} unsigned short v; memcpy(&v,g_kfa_buf+g_kfa_off,2); g_kfa_off+=2; return v; }
static unsigned kfa_u8 (void){ if(!kfa_ok(1)){g_kfa_off=-1;return 0;} unsigned char v=g_kfa_buf[g_kfa_off]; g_kfa_off+=1; return v; }
static float    kfa_f32(void){ if(!kfa_ok(4)){g_kfa_off=-1;return 0;} float v; memcpy(&v,g_kfa_buf+g_kfa_off,4); g_kfa_off+=4; return v; }
static void     kfa_name(char *out){ unsigned ln=kfa_u16(); unsigned c=ln<KFA_MAXNAME-1?ln:KFA_MAXNAME-1;
    if(!kfa_ok((int)ln)){g_kfa_off=-1;out[0]=0;return;} memcpy(out,g_kfa_buf+g_kfa_off,c); out[c]=0; g_kfa_off+=ln; }
static float   *kfa_farr(int count){ if(!kfa_ok(count*4)){g_kfa_off=-1;return NULL;}
    float *a=(float*)malloc(count*sizeof(float)); if(a){ memcpy(a,g_kfa_buf+g_kfa_off,count*4); } g_kfa_off+=count*4; return a; }

/* blendspace clip wiring (resolved after load): spec §D order F FR R BR B BL L FL */
static int g_loco_walkclip[8], g_loco_jogclip[8], g_loco_idleclip;
static int g_loco_crouchclip[8], g_loco_crouchidle;   /* sneak tier (8-dir crouch walk) */
static int g_loco_bs_ok;    /* all 17 base clips found -> blendspace available */
static int g_loco_crouch_ok;/* crouch set present in the kfa */
static const char *LOCO_DIR_WALK[8] = {
    "MOB1_Walk_F_IPC",  "MOB1_Walk_FR_Loop_IPC", "MOB1_Walk_R_IPC",  "MOB1_Walk_BR_BkPd_Loop_IPC",
    "MOB1_Walk_B_IPC",  "MOB1_Walk_BL_BkPd_Loop_IPC", "MOB1_Walk_L_IPC", "MOB1_Walk_FL_Loop_IPC" };
static const char *LOCO_DIR_JOG[8] = {
    "MOB1_Jog_F_Loop_IPC",  "MOB1_Jog_FR_Loop_IPC", "MOB1_Jog_R_Loop_IPC",  "MOB1_Jog_BR_BkPd_Loop_IPC",
    "MOB1_Jog_B_Loop_IPC",  "MOB1_Jog_BL_BkPd_Loop_IPC", "MOB1_Jog_L_Loop_IPC", "MOB1_Jog_FL_Loop_IPC" };
#define LOCO_IDLE_CLIP "ANIM_Humanoid_IdleUnarmed"
static const char *LOCO_DIR_CROUCH[8] = {
    "MOB1_CrouchWalk_F_Loop_IPC",  "MOB1_CrouchWalk_FR_Loop_IPC",
    "MOB1_CrouchWalk_R_Loop_IPC",  "MOB1_CrouchWalk_BR_BkPd_Loop_IPC",
    "MOB1_CrouchWalk_B_Loop_IPC",  "MOB1_CrouchWalk_BL_BkPd_Loop_IPC",
    "MOB1_CrouchWalk_L_Loop_IPC",  "MOB1_CrouchWalk_FL_Loop_IPC" };

static int loco_find_clip(const char *nm){
    for (int c = 0; c < g_kfa.numClips; c++)
        if (strcmp(g_kfa.clips[c].name, nm) == 0) return c;
    return -1;
}

/* Load the KFA2 clip pack. The pack is EMBEDDED in the DLL as an RCDATA
 * resource (KFP_RES_KFA), so nothing extra has to ship or be kept next to the
 * binary -- that removes the "locomotion silently falls back to vanilla
 * because locomotion.kfa went missing" failure mode entirely, and matters for
 * the Steam Workshop where the item is a folder users never assemble by hand.
 * A locomotion.kfa FILE next to the DLL still WINS when present, so a custom
 * bake can be dropped in without rebuilding. Returns 1 on success. */
static int kfp_loco_load(void){
    if (g_kfa.loaded) return 1;
    unsigned char *buf = NULL;      /* owned only when loaded from file */
    const unsigned char *data = NULL;
    long sz = 0;
    const char *src = "embedded";

    FILE *f = fopen(kfp_loco_path(), "rb");
    if (f){
        fseek(f, 0, SEEK_END); sz = ftell(f); fseek(f, 0, SEEK_SET);
        if (sz < 12 || sz > 64*1024*1024){ fclose(f); logline("[loco] locomotion.kfa bad size %ld -- using embedded", sz); f = NULL; sz = 0; }
        else {
            buf = (unsigned char*)malloc(sz);
            if (!buf || fread(buf, 1, sz, f) != (size_t)sz){ free(buf); buf = NULL; sz = 0;
                logline("[loco] locomotion.kfa read failed -- using embedded"); }
            fclose(f);
            if (buf){ data = buf; src = "file override"; }
        }
    }
    if (!data){   /* embedded RCDATA copy */
        HRSRC r = FindResourceA(g_hinst, MAKEINTRESOURCEA(KFP_RES_KFA), RT_RCDATA);
        HGLOBAL h = r ? LoadResource(g_hinst, r) : NULL;
        const void *p = h ? LockResource(h) : NULL;
        DWORD rsz = r ? SizeofResource(g_hinst, r) : 0;
        if (!p || rsz < 12){
            logline("[loco] no clip pack (embedded resource missing) -- custom locomotion disabled");
            return 0;
        }
        data = (const unsigned char *)p; sz = (long)rsz;
    }
    g_kfa_buf = data; g_kfa_size = sz; g_kfa_off = 0;

    if (memcmp(data, "KFA2", 4) != 0){ free(buf); logline("[loco] bad magic (need KFA2 -- re-run tools/retarget_locomotion.py)"); return 0; }
    g_kfa_off = 4;
    int nb = kfa_i32(), nc = kfa_i32();
    if (nb <= 0 || nb > 128 || nc <= 0 || nc > 256){ free(buf); logline("[loco] bad counts %d/%d", nb, nc); return 0; }

    g_kfa.bones = (kfa_bone*)calloc(nb, sizeof(kfa_bone));
    g_kfa.clips = (kfa_clip*)calloc(nc, sizeof(kfa_clip));
    if (!g_kfa.bones || !g_kfa.clips){ free(buf); logline("[loco] oom"); return 0; }

    for (int i = 0; i < nb; i++){
        kfa_bone *b = &g_kfa.bones[i];
        kfa_name(b->name);
        b->flags = (int)kfa_u8();
        float rx=kfa_f32(), ry=kfa_f32(), rz=kfa_f32(), rw=kfa_f32();   /* file xyzw */
        b->bindRot = (Quat){ rw, rx, ry, rz };                          /* -> Ogre w,x,y,z */
        b->group = (strstr(b->name, "Spine") || strstr(b->name, "Clavicle")
                 || strstr(b->name, "Arm")   || strstr(b->name, "Hand")) ? 2
                 : (strstr(b->name, "Thigh") || strstr(b->name, "Calf")
                 || strstr(b->name, "Foot")  || strstr(b->name, "Toe")) ? 0 : 1;
    }
    for (int c = 0; c < nc && g_kfa_off >= 0; c++){
        kfa_clip *cl = &g_kfa.clips[c];
        kfa_name(cl->name);
        cl->fps = kfa_f32(); cl->keys = kfa_i32(); cl->length = kfa_f32();
        if (cl->keys <= 0 || cl->keys > 100000){ g_kfa_off = -1; break; }
        cl->rot = (float**)calloc(nb, sizeof(float*));
        if (!cl->rot){ g_kfa_off = -1; break; }
        for (int i = 0; i < nb; i++)
            if (kfa_u8()) cl->rot[i] = kfa_farr(cl->keys * 4);
    }
    free(buf); g_kfa_buf = NULL;
    if (g_kfa_off < 0){ logline("[loco] parse overran -- corrupt file"); return 0; }

    g_kfa.numBones = nb; g_kfa.numClips = nc; g_kfa.loaded = 1;

    /* resolve the blendspace clip set */
    g_loco_bs_ok = 1;
    for (int d = 0; d < 8; d++){
        g_loco_walkclip[d] = loco_find_clip(LOCO_DIR_WALK[d]);
        g_loco_jogclip[d]  = loco_find_clip(LOCO_DIR_JOG[d]);
        if (g_loco_walkclip[d] < 0 || g_loco_jogclip[d] < 0) g_loco_bs_ok = 0;
    }
    g_loco_idleclip = loco_find_clip(LOCO_IDLE_CLIP);
    if (g_loco_idleclip < 0) g_loco_bs_ok = 0;
    g_loco_crouch_ok = 1;
    for (int d = 0; d < 8; d++){
        g_loco_crouchclip[d] = loco_find_clip(LOCO_DIR_CROUCH[d]);
        if (g_loco_crouchclip[d] < 0) g_loco_crouch_ok = 0;
    }
    g_loco_crouchidle = loco_find_clip("MOB1_Crouch_Idle_V2_IPC");   /* the baked
        * name (bake log: clip 25); the V2-less name returned -1 and sampling
        * clip -1 in the stance bridge FAULTED the whole loco layer */
    if (g_loco_crouchidle < 0) g_loco_crouchidle = loco_find_clip("MOB1_Crouch_Idle_IPC");

    logline("[loco] loaded locomotion.kfa (KFA2): %d bones, %d clips (%ld bytes), blendspace=%s",
            nb, nc, sz, g_loco_bs_ok ? "OK" : "INCOMPLETE (single-clip only)");
    for (int c = 0; c < nc; c++)
        logline("[loco]   clip %-2d %-32s fps=%.1f keys=%d len=%.2f",
                c, g_kfa.clips[c].name, g_kfa.clips[c].fps, g_kfa.clips[c].keys, g_kfa.clips[c].length);
    return 1;
}

/* ============================ playback ============================ */

typedef struct {
    void *bone;    /* Kenshi OldBone* */
    Quat  park;    /* engine BIND local (initial state) -- pose for holds / undriven pelvis */
} loco_slot;

static loco_slot g_slots[128];
static int   g_loco_ready;   /* setup done */
static int   g_loco_dead;    /* faulted -> disabled for the session */
static float g_loco_phase;       /* shared locomotion phase [0,1) */
static float g_loco_idlephase;   /* idle clip phase [0,1) */
static void *g_loco_skel;    /* OldSkeletonInstance we set up on (for disableBone on release) */
static void *g_loco_root;    /* "Bip01" root bone (game-driven, never controlled) */
static void *g_loco_head;    /* "Bip01 Head" (game-driven): true camera attachment frame */
static Vec3  g_head_facelocal;   /* bind-frame face direction in the head bone's LOCAL frame:
                                  * eye offset = headDerived * this, so the camera rides the
                                  * head's ACTUAL animated orientation */

/* eased blendspace state */
static float g_loco_gait;        /* 0 = walk tier, 1 = jog tier */
static float g_loco_moveblend;   /* 0 = idle pose, 1 = locomotion pose */
static float g_loco_angle;       /* eased moveAngle (rad; 0 = fwd, + = right) */

/* facing calibration: root-bone-frame vector that points at world yaw 0..  Same trick as
 * bend_spine's g_fwd_local -- capture inv(rootDerived)*worldFwd(g_yaw) while the body is
 * known to face the camera (idle+sheathed+level; .c gates the call). */
static Vec3  g_loco_fwdref;
static int   g_loco_have_fwdref;

/* reversal latch: on a large moveAngle jump, snapshot the output pose and crossfade */
static Quat  g_loco_outpose[128];    /* last written pose (snapshot source) */
static int   g_loco_have_out;
static Quat  g_loco_prevpose[128];
static float g_loco_fade;            /* 1 -> 0 over LOCO_FADE_T */
/* game-pose snapshot taken at each group ACQUIRE: the idle-side blend target for
 * start/stop/TIP. Blending against the game's OWN pose (instead of bind or a baked
 * idle) makes both handoff directions seamless and automatically matches whatever
 * idle variant the game is in (normal, holding-injured-limb, ...). */
static Quat  g_loco_acqpose[128];
static Quat  g_root_acq, g_root_bind;/* root gets the same treatment: bind during
                                      * locomotion (baked chain), captured game pose at
                                      * the idle ends -- an unblended root snapped the
                                      * whole body at handback */
static float g_tip_linger;           /* keep legs owned briefly after a turn ends so the
                                      * counter-rotation can settle before handback */
static float g_sneak_cool;           /* sneak-toggle stance window: passive claims held off */
static int   g_stance_dbg;           /* frames of [stance] tracing left (toggle diag) */
static float g_stance_drop;          /* crouch pelvis lowering recovered from the
                                      * posed skeleton (KFA2 bakes rotations only,
                                      * so clip pelvis translation is lost) */
static float g_stancemix_w;          /* OWN-THE-TRANSITION weight: while a stance change
                                      * is in flight the loco holds ALL groups and renders
                                      * the idle base as blend(idle clip, crouch idle, sw)
                                      * -- release only after the pose already matches the
                                      * destination stance (no mid-transition snap) */
static float g_sneak_w;              /* eased sneak blend 0..1 (~0.25s): the crouch set is
                                      * MIXED with the stand set per bone (air-tuck pattern),
                                      * no snapshot crossfade, no transition pop */

/* turn-in-place state */
static int   g_slot_leg[2][3];       /* [L/R][thigh,calf,foot] slot indices, -1 if missing */
static int   g_slot_pelvis;
static int   g_slot_spine[3];        /* Spine, Spine1, Spine2 (aim-offset chain) */
static float g_tip_w;                /* TIP modifier weight, eased 0..1: engaging/disengaging
                                      * as a hard gate snapped the leg counter-rotations when
                                      * movement started mid-turn (and vice versa) */
static float g_tip_lock[2];          /* per-foot planted body-yaw */
static float g_tip_lockstart[2];
static int   g_tip_have[2];
static float g_tip_t[2];             /* step progress */
static int   g_tip_stepping;         /* -1 none, 0 L, 1 R */

/* group ownership: while idle EVERYTHING is released so the game's full idle set plays
 * (breathing, weapon stances, holding-injured-limb variants). We own:
 *   legs (thighs/calves/feet/toes): while moving OR during a turn-in-place
 *   core (pelvis + root):           only while moving (a TIP turn must leave the whole
 *                                   torso 100%% vanilla -- even a parked pelvis/root
 *                                   visibly jolts the game-animated upper body)
 *   upper (spine/clavicles/arms/hands): only while moving */
static int   g_upper_owned;
static int   g_lower_owned;   /* legs group */
static int   g_core_owned;    /* pelvis + root */

/* idle aim: while standing, the spine trio is claimed ON DEMAND (deadzone-gated) so
 * look up/down and the pre-TIP camera deviation bend the torso; released again when
 * the camera settles so vanilla idle breathing resumes on those bones */
static int   g_idleaim_owned;
static Quat  g_idleaim_base[3];
static int   g_upper_handback;   /* frames since the moving system released the upper: the
                                  * idle-aim claim must then use the UNBENT acqpose as its
                                  * base -- getori returns our still-bent settle pose and
                                  * re-applying offsets on it doubled the bend */

/* diagnostics: overwrite detector (should stay silent now that disableBone is applied) */
static int   g_loco_diag;
static Quat  g_loco_lastw[128];
static int   g_loco_havew[128];

static float loco_wrap_pi(float a){
    while (a >  3.14159265f) a -= 6.28318531f;
    while (a < -3.14159265f) a += 6.28318531f;
    return a;
}
static float loco_clampf(float v, float lo, float hi){ return v < lo ? lo : v > hi ? hi : v; }
static Quat  loco_axis_angle(Vec3 a, float ang){
    float l = sqrtf(a.x*a.x + a.y*a.y + a.z*a.z);
    if (l < 1e-9f) return (Quat){1,0,0,0};
    float h = ang * 0.5f, s = sinf(h) / l;
    return (Quat){ cosf(h), a.x*s, a.y*s, a.z*s };
}

/* sample one bone's LOCAL rotation from a clip at normalized phase [0,1) */
static Quat loco_sample(int clipIdx, int bone, float phase){
    if (clipIdx < 0 || clipIdx >= g_kfa.numClips)
        return g_slots[bone].park;   /* invalid clip = bind park, NEVER a fault
            * (a -1 from a failed name lookup faulted the whole loco layer) */
    kfa_clip *cl = &g_kfa.clips[clipIdx];
    const float *R = cl->rot ? cl->rot[bone] : NULL;
    if (!R) return g_slots[bone].park;
    float f = phase * (float)(cl->keys - 1);
    int k0 = (int)f; if (k0 < 0) k0 = 0; if (k0 > cl->keys-1) k0 = cl->keys-1;
    int k1 = k0+1;   if (k1 > cl->keys-1) k1 = cl->keys-1;
    float u = f - k0; if (u < 0) u = 0; else if (u > 1) u = 1;
    Quat q0 = quat_norm((Quat){ R[k0*4+3], R[k0*4+0], R[k0*4+1], R[k0*4+2] });
    Quat q1 = quat_norm((Quat){ R[k1*4+3], R[k1*4+0], R[k1*4+1], R[k1*4+2] });
    return quat_slerp(q0, q1, u);
}

/* make_mstr_long (build an MSVC std::string for getBone; SSO or heap) is forward-declared
 * static in the .c right before this header is included. */

/* BIND global rotation+position of a bone: compose initial states up the parent chain */
static int loco_bind_global(void *bone, Quat *outR, Vec3 *outP){
    void *chain[64]; int n = 0;
    for (void *b = bone; b && n < 64; b = g_oldnode_getparent(b)){
        if (!readable(b, 8)) return 0;
        chain[n++] = b;
    }
    Quat R = { 1, 0, 0, 0 }; Vec3 P = { 0, 0, 0 };
    for (int i = n - 1; i >= 0; i--){
        const Quat *lq = g_oldnode_getinitori(chain[i]);
        const Vec3 *lp = g_oldnode_getinitpos(chain[i]);
        if (!readable((void*)lq, 16) || !readable((void*)lp, 12)) return 0;
        P = v3_add(P, quat_rotvec(R, *lp));
        R = quat_norm(quat_mul(R, *lq));
    }
    *outR = R; *outP = P;
    return 1;
}
static int loco_bind_global_rot(void *bone, Quat *outR){
    Vec3 p; return loco_bind_global(bone, outR, &p);
}

static void *loco_getbone_by(void *skel, const char *name){
    unsigned char nm[64];
    void *heap = make_mstr_long(nm, name);
    void *b = g_skel_getbone(skel, nm);
    if (heap) free(heap);
    return readable(b, 8) ? b : NULL;
}

static int loco_slot_index(const char *nm){
    for (int i = 0; i < g_kfa.numBones; i++)
        if (strcmp(g_kfa.bones[i].name, nm) == 0) return i;
    return -1;
}

/* Resolve bones, mark them manual + disabled in Kenshi's animation pass, park at bind. */
static int loco_setup(void *skel){
    if (g_loco_ready) return 1;
    if (!g_kfa.loaded || !g_skel_getbone || !g_oldbone_setmanual || !g_oldnode_setori
        || !g_oldnode_needupd || !g_oldnode_getinitori){
        static int once; if (!once){ once=1;
            logline("[loco] setup blocked: kfa=%d getbone=%p setmanual=%p setori=%p needupd=%p initori=%p",
                    g_kfa.loaded, (void*)g_skel_getbone, (void*)g_oldbone_setmanual,
                    (void*)g_oldnode_setori, (void*)g_oldnode_needupd, (void*)g_oldnode_getinitori); }
        return 0;
    }
    /* First-run step tracer: a beta tester's crash log ended between the gate
     * diag and the disableBone line with NO retarget-FAULTED entry (i.e. the
     * fault bypassed the VEH guard -- fail-fast or off-thread). These one-shot
     * checkpoints bracket the fault site in the next such log. */
    static int trace1;
    int tr = !trace1; trace1 = 1;
    for (int i = 0; i < g_kfa.numBones; i++){
        loco_slot *s = &g_slots[i];
        unsigned char nm[64];
        void *heap = make_mstr_long(nm, g_kfa.bones[i].name);
        s->bone = g_skel_getbone(skel, nm);
        if (heap) free(heap);
        if (tr) logline("[loco] setup: bone %-2d '%s' -> %p", i, g_kfa.bones[i].name, s->bone);
        if (!readable(s->bone, 8)){ logline("[loco] setup: bone '%s' not found", g_kfa.bones[i].name); return 0; }
        /* park pose = the engine's OWN bind local (initial state == binding pose) */
        const Quat *iq = g_oldnode_getinitori(s->bone);
        s->park = readable((void*)iq, 16) ? *iq : g_kfa.bones[i].bindRot;
        g_loco_acqpose[i] = s->park;   /* safe default until the first acquire */
    }
    if (tr) logline("[loco] setup: all %d bones resolved -- taking manual ownership", g_kfa.numBones);
    for (int i = 0; i < g_kfa.numBones; i++){
        loco_slot *s = &g_slots[i];
        g_oldbone_setmanual(s->bone, 1);
        g_oldnode_setori(s->bone, &s->park);   /* park everything at bind; tracks overwrite below */
        g_oldnode_needupd(s->bone, 1);
    }
    if (tr) logline("[loco] setup: ownership taken -- disabling game anim layers");
    /* manuallyControlled alone is NOT enough in Kenshi: its own animation system keeps
     * blending per-bone-masked layers on top of manual bones. Kenshi's engine adds
     * disableBone(name, bool) to OldSkeletonInstance for exactly this. */
    g_loco_skel = skel;
    if (g_disable_bone){
        for (int i = 0; i < g_kfa.numBones; i++){
            unsigned char nm[64];
            void *heap = make_mstr_long(nm, g_kfa.bones[i].name);
            g_disable_bone(skel, nm, 1);
            if (heap) free(heap);
        }
        logline("[loco] disableBone applied to %d bones (game anim layers off)", g_kfa.numBones);
    } else
        logline("[loco] WARNING: disableBone export missing -- game anims will fight our pose");

    /* ROOT BONE: facing lives on the SCENE NODE (measured: root derived == bind while
     * idle), so the root is safe to park -- and it MUST be: the game's own locomotion
     * anims keep playing their root track (run = strong baked-in lean/sway) under our
     * body, which read as "the root rotates while sprinting". Park at bind + disable. */
    {
        unsigned char nm[64];
        void *heap = make_mstr_long(nm, "Bip01");
        g_loco_root = g_skel_getbone(skel, nm);
        if (heap) free(heap);
        if (!readable(g_loco_root, 8)) g_loco_root = NULL;
        if (g_loco_root){
            /* initialize the root pose refs HERE: setup marks ownership directly, so the
             * group-acquire path (which normally sets these) never runs on a fresh
             * session -- they stayed ZERO and quat_rotvec(zero-quat) degenerates to
             * identity (the collapsed-pelvis IK bug) */
            {
                const Quat *cl = g_oldnode_getori ? g_oldnode_getori(g_loco_root) : NULL;
                const Quat *bq = g_oldnode_getinitori(g_loco_root);
                g_root_bind = readable((void*)bq, 16) ? *bq : (Quat){1,0,0,0};
                g_root_acq  = readable((void*)cl, 16) ? *cl : g_root_bind;
            }
            g_oldbone_setmanual(g_loco_root, 1);
            const Quat *rq = g_oldnode_getinitori(g_loco_root);
            if (readable((void*)rq, 16)){
                g_oldnode_setori(g_loco_root, rq);
                g_oldnode_needupd(g_loco_root, 1);
            }
            if (g_disable_bone){
                heap = make_mstr_long(nm, "Bip01");
                g_disable_bone(skel, nm, 1);
                if (heap) free(heap);
            }
        }
    }
    /* leg + pelvis slot wiring for turn-in-place */
    /* head bone (game-driven): true camera attachment -- face direction in head frame */
    {
        unsigned char nm[64];
        void *heap = make_mstr_long(nm, "Bip01 Head");
        g_loco_head = g_skel_getbone(skel, nm);
        if (heap) free(heap);
        if (!readable(g_loco_head, 8)) g_loco_head = NULL;
        g_head_facelocal = (Vec3){ 0, 0, 1 };
        Quat hg;
        if (g_loco_head && g_oldnode_getparent && g_oldnode_getinitori
            && loco_bind_global_rot(g_loco_head, &hg))
            g_head_facelocal = quat_rotvec(quat_conj(hg), (Vec3){ 0, 0, 1 });
    }
    /* foot-IK geometry: BIND offsets (pose-independent, proven) x the node's DERIVED
     * SCALE -- the mechanism Kenshi's body sliders actually use. (Derived POSITIONS
     * sampled mid-pose gave inconsistent lengths -- stale lazy caches.) */
    {
        void *pv = loco_getbone_by(skel, "Bip01 Pelvis");
        Quat rr; Vec3 rp;
        if (g_loco_root && loco_bind_global(g_loco_root, &rr, &rp)) g_root_bindpos = rp;
        /* NOTE: derived-scale reads proved lazy-cache unreliable (garbage ~0.75 shrank
         * the chain -> phantom floating -> pelvis drop -> sinking). Pure bind geometry
         * until a trustworthy per-character scale source exists. */
        float sPelv = 1.0f;
        if (pv && g_oldnode_getinitpos){
            const Vec3 *pp = g_oldnode_getinitpos(pv);
            if (readable((void*)pp, 12)) g_pelvis_bindoff = *pp;   /* root-frame, pre-scale */
        }
        float sLegAvg = 1.0f;
        for (int f = 0; f < 2; f++){
            const char *thn = f ? "Bip01 R Thigh" : "Bip01 L Thigh";
            const char *cfn = f ? "Bip01 R Calf"  : "Bip01 L Calf";
            const char *ftn = f ? "Bip01 R Foot"  : "Bip01 L Foot";
            const char *ton = f ? "Bip01 R Toe0"  : "Bip01 L Toe0";
            void *tb = loco_getbone_by(skel, thn), *cb = loco_getbone_by(skel, cfn),
                 *fb = loco_getbone_by(skel, ftn), *ob = loco_getbone_by(skel, ton);
            g_ik_a[f] = g_ik_b[f] = 0;
            if (!(tb && cb && fb && g_oldnode_getinitpos)) continue;
            float sT = 1.0f, sC = 1.0f, sF = 1.0f;
            const Vec3 *tp = g_oldnode_getinitpos(tb);
            const Vec3 *cp = g_oldnode_getinitpos(cb);
            const Vec3 *fp2 = g_oldnode_getinitpos(fb);
            if (readable((void*)tp,12) && readable((void*)cp,12) && readable((void*)fp2,12)){
                g_ik_thighoff[f] = v3_scale(*tp, sPelv);
                g_ik_calfoff[f]  = v3_scale(*cp, sT);  g_ik_a[f] = v3_len(*cp) * sT;
                g_ik_footoff[f]  = v3_scale(*fp2, sC); g_ik_b[f] = v3_len(*fp2) * sC;
            }
            if (ob && g_oldnode_getinitpos){
                const Vec3 *op = g_oldnode_getinitpos(ob);
                if (readable((void*)op,12)) g_ik_toeoff[f] = v3_scale(*op, sF);
            }
            Quat fr; Vec3 fpw;
            if (fb && loco_bind_global(fb, &fr, &fpw)){
                float sLeg = (sT + sC) * 0.5f;
                g_ik_bindfoot[f] = v3_scale(fpw, sLeg);       /* probe spot approx */
                g_ik_ankle0 = fpw.y * sLeg;                   /* stance ankle height */
                g_ik_toey   = 0.03f * sLeg;
                sLegAvg = sLeg;
            }
        }
        (void)sLegAvg;
    }
    g_ik_w = 0; g_slope_hold = 0; g_ik_drop = 0; g_ik_pospushed = 0; g_stance_drop = 0;
    {   /* sanity-gate the IK geometry: refuse to run on bad measurements */
        int ok = (g_ik_a[0] > 2 && g_ik_a[0] < 8 && g_ik_b[0] > 2 && g_ik_b[0] < 8
               && g_ik_ankle0 > 0.2f && g_ik_ankle0 < 3.0f
               && v3_len(g_pelvis_bindoff) < 3.0f);
        logline("[ik] a=%.2f b=%.2f ankle0=%.2f pelvOff=(%.2f,%.2f,%.2f) rootP=(%.2f,%.2f,%.2f) %s",
                g_ik_a[0], g_ik_b[0], g_ik_ankle0,
                g_pelvis_bindoff.x, g_pelvis_bindoff.y, g_pelvis_bindoff.z,
                g_root_bindpos.x, g_root_bindpos.y, g_root_bindpos.z,
                ok ? "OK" : "BAD -- foot IK disabled");
        if (!ok) g_ik_a[0] = 0;   /* fails the ikActive geometry check */
    }
    g_slot_leg[0][0] = loco_slot_index("Bip01 L Thigh");
    g_slot_leg[0][1] = loco_slot_index("Bip01 L Calf");
    g_slot_leg[0][2] = loco_slot_index("Bip01 L Foot");
    g_slot_leg[1][0] = loco_slot_index("Bip01 R Thigh");
    g_slot_leg[1][1] = loco_slot_index("Bip01 R Calf");
    g_slot_leg[1][2] = loco_slot_index("Bip01 R Foot");
    g_slot_pelvis    = loco_slot_index("Bip01 Pelvis");
    g_slot_spine[0]  = loco_slot_index("Bip01 Spine");
    g_slot_spine[1]  = loco_slot_index("Bip01 Spine1");
    g_slot_spine[2]  = loco_slot_index("Bip01 Spine2");

    g_loco_ready = 1;
    g_loco_phase = 0; g_loco_idlephase = 0;
    g_loco_gait = 0; g_loco_moveblend = 0; g_loco_angle = 0;
    g_loco_fade = 0; g_loco_have_out = 0;
    g_upper_owned = 1;   /* everything acquired at setup; first idle update releases all */
    g_lower_owned = 1;
    g_core_owned  = 1;
    g_tip_have[0] = g_tip_have[1] = 0; g_tip_stepping = -1;
    g_loco_diag = 6;
    memset(g_loco_havew, 0, sizeof g_loco_havew);
    logline("[loco] setup OK: %d bones controlled (blendspace=%d clip=%d hips=%d)",
            g_kfa.numBones, g_loco_bs_ok, g_cfg_loco_clip, g_cfg_loco_hips);
    return 1;
}

/* Hand every controlled bone back to the game's animation. VEH-guarded by the caller. */
static void loco_release(void){
    if (!g_loco_ready) return;
    if (g_ik_pospushed && g_oldnode_setpos && g_slot_pelvis >= 0
        && readable(g_slots[g_slot_pelvis].bone, 8)){
        /* restore the pelvis bind position BEFORE the bone pointers are dropped */
        g_oldnode_setpos(g_slots[g_slot_pelvis].bone, &g_pelvis_bindoff);
        g_oldnode_needupd(g_slots[g_slot_pelvis].bone, 1);
    }
    g_ik_pospushed = 0; g_ik_drop = 0;
    for (int i = 0; i < g_kfa.numBones; i++){
        if (g_oldbone_setmanual && readable(g_slots[i].bone, 8))
            g_oldbone_setmanual(g_slots[i].bone, 0);
        g_slots[i].bone = NULL;
    }
    if (g_oldbone_setmanual && readable(g_loco_root, 8))
        g_oldbone_setmanual(g_loco_root, 0);
    if (g_disable_bone && readable(g_loco_skel, 8)){
        for (int i = 0; i < g_kfa.numBones; i++){
            unsigned char nm[64];
            void *heap = make_mstr_long(nm, g_kfa.bones[i].name);
            g_disable_bone(g_loco_skel, nm, 0);   /* re-enable game animation */
            if (heap) free(heap);
        }
        unsigned char nm[64];
        void *heap = make_mstr_long(nm, "Bip01");
        g_disable_bone(g_loco_skel, nm, 0);
        if (heap) free(heap);
    }
    g_loco_skel = NULL; g_loco_root = NULL; g_loco_head = NULL;
    g_idleaim_owned = 0;
    g_loco_ready = 0;
    logline("[loco] released -- bones returned to game animation");
}

/* Capture the facing reference while the body is known to face the camera (the .c gates the
 * call: FP, idle, sheathed, level look -- same conditions as calibrate_spine_fwd). */
static void loco_calibrate_facing(void){
    if (!g_loco_ready || !g_loco_root || !g_oldnode_getdori) return;
    const Quat *rd = g_oldnode_getdori(g_loco_root);
    if (!readable((void*)rd, 16)) return;
    g_loco_fwdref = quat_rotvec(quat_conj(*rd), (Vec3){ sinf(g_yaw), 0.0f, cosf(g_yaw) });
    if (!g_loco_have_fwdref) logline("[loco] facing reference calibrated");
    g_loco_have_fwdref = 1;
}

/* per-frame playback. Called from the FP tick with real dt seconds; g_loco_in_* fed first.
 * VEH-guarded by the caller. */
static void loco_update(float dt){
    if (!g_loco_ready || g_loco_dead || !g_kfa.loaded) return;
    if (dt < 0) dt = 0; if (dt > 0.25f) dt = 0.25f;
    float gs = loco_clampf(g_loco_in_gs, 0.0f, 6.0f);
    float dtA = dt * gs;                      /* animation time follows game speed (0 = paused) */

    /* ---- body yaw. Facing lives on the SCENE NODE (root bone is parked at bind), so
     * the COMMANDED facing from the .c's TIP state machine is the authority -- the body
     * follows our own faceDirection calls, so command == body to within a frame. ---- */
    int haveYaw = 0; float bodyYaw = 0;
    if (g_loco_in_havebody){
        bodyYaw = g_loco_in_bodyyaw;
        haveYaw = 1;
    }

    /* ---- eased blend parameters (spec §D) ---- */
    int moving = g_loco_in_moving
              || (g_loco_in_speed > 3.0f);   /* momentum: Kenshi keeps sliding after the
                                              * keys release -- keep the cycle playing (its
                                              * gait tracks the decaying speed, so the decel
                                              * animation FOLLOWS the physical glide) and
                                              * hand back only once the body actually stops,
                                              * when the game's anim state is idling too */
    float gaitT = moving
        ? loco_clampf((g_loco_in_speed - g_cfg_loco_walkref) /
                      (g_cfg_loco_jogref - g_cfg_loco_walkref > 1.0f ?
                       g_cfg_loco_jogref - g_cfg_loco_walkref : 1.0f), 0.0f, 1.0f)
        : 0.0f;                    /* stopping: wind the gait down too (jog -> walk -> idle) */
    float ge = dt * (moving ? LOCO_GAIT_RATE : 5.0f); if (ge > 1) ge = 1;
    g_loco_gait += (gaitT - g_loco_gait) * ge;
    /* SEQUENCED stop: while the gait winds down the cycle KEEPS PLAYING (a visible
     * jog->walk deceleration that picks up where the stride left off); only once the
     * gait reaches walk-level does the idle crossfade begin. Fading both at once made
     * a sprint stop dissolve mid-stride ("animation reset"). */
    int settling = (!moving && g_loco_gait < 0.25f);
    float mbT = moving ? 1.0f : (settling ? 0.0f : 1.0f);
    float mbStep = dt / LOCO_XFADE_T;
    if (g_loco_moveblend < mbT) g_loco_moveblend = (g_loco_moveblend + mbStep > mbT) ? mbT : g_loco_moveblend + mbStep;
    else                        g_loco_moveblend = (g_loco_moveblend - mbStep < mbT) ? mbT : g_loco_moveblend - mbStep;

    /* ---- group ownership (see decl comment). On acquire: snapshot the game's current
     * pose and crossfade into ours; parked bones (holds, undriven pelvis, root) are
     * re-parked at bind. On release the game re-blends its own animation. ---- */
    /* Hold ownership through the moveblend fade in BOTH directions: the pose blends
     * between the locomotion mix and the ACQUIRE-time game pose (g_loco_acqpose), so
     * the handoff happens only when our output already equals what the game will show.
     * (The engine does NOT crossfade on manual->auto handback -- measured snap.)
     * POST-SETTLE HOLD: after the fade completes, keep the bones parked on the captured
     * pose ~0.4s more -- the game's own hidden walk->idle blend needs that long to
     * finish, and handing back mid-ITS-blend was the residual walk-stop hitch (sprint
     * stops were clean only because the longer glide gave it time). */
    static float s_idleHold;
    if (moving) s_idleHold = 0;
    else if (g_loco_moveblend <= 0.02f && s_idleHold < 1.0f) s_idleHold += dt;
    int upperActive = (moving || g_loco_moveblend > 0.02f || s_idleHold < 0.4f);
    /* idle SLOPE-CLAIM: standing on stairs/slopes/uneven ground, claim the legs so the
     * foot IK can plant them; released again on flat ground (hysteresis, probed at the
     * bind foot spots every 4th frame). */
    if (g_cfg_loco_footik && RVA_GROUND_AT && g_loco_in_havebody && !upperActive){
        {
            float cyp = cosf(g_loco_in_bodyyaw), syp = sinf(g_loco_in_bodyyaw);
            Vec3 pc1 = { g_loco_in_posx, g_loco_in_posy + 2.0f, g_loco_in_posz };
            float gRef2 = loco_gnd_q(&pc1);
            float worst = 0;
            if (gRef2 > -100000.0f && gRef2 < 100000.0f
                && fabsf(gRef2 - g_loco_in_posy) < 4.0f){
                for (int f = 0; f < 2; f++){
                    Vec3 bf = g_ik_bindfoot[f];
                    Vec3 pr = { g_loco_in_posx + cyp * bf.x + syp * bf.z,
                                g_loco_in_posy + bf.y + 2.0f,
                                g_loco_in_posz - syp * bf.x + cyp * bf.z };
                    float gy = loco_gnd_q(&pr);
                    if (gy > -100000.0f && gy < 100000.0f
                        && fabsf(gy - gRef2) < 4.0f){
                        float dvp = fabsf(gy - gRef2);   /* RELATIVE to the char's ground */
                        if (dvp > worst) worst = dvp;
                    }
                }
            }
            if (!g_slope_hold && worst > 0.06f && g_sneak_cool <= 0) g_slope_hold = 1;
            else if (g_slope_hold && worst < 0.03f) g_slope_hold = 0;
        }
    } else if (upperActive) g_slope_hold = 0;
    if (g_loco_in_turning || g_tip_stepping >= 0) g_tip_linger = 0.25f;
    else if (g_tip_linger > 0) g_tip_linger -= dt;
    int wantGroup[3];
    /* DROP UNWIND HOLD: releasing the core while a pelvis IK drop is applied
     * bind-restores the pelvis IN ONE FRAME -- the "sudden correction the
     * frame after a sneak toggle". Keep legs+core owned until the drop has
     * eased back out (the IK-inactive path unwinds it, ~0.1s), then release
     * from the exact bind pose. */
    /* Only a GENUINE unwind holds ownership: when the plant IK is actively
     * solving, the drop is legitimately live and the normal claims already
     * cover ownership. Without this guard a wrong pose that makes the IK dive
     * (see the uncrouch stuck-crouch loop) pinned the groups indefinitely,
     * which kept the wrong pose alive -- the hold must never be able to
     * sustain the condition it is waiting on. */
    static int ik_was_active;
    int drop_unwind = g_ik_pospushed && fabsf(g_ik_drop) > 0.02f && !ik_was_active;
    int stance_drop_on = fabsf(g_stance_drop) > 0.005f;   /* crouch pelvis lowering
        * is applied through the CORE (pelvis position) -- hold that group while
        * it is non-zero or the hips snap back up to standing height */
    int stance_hold = g_stancemix_w > 0.01f;   /* own the WHOLE stance change:
        * the mid-transition release (own 111->100 in the [stance] trace) was a
        * full stand-vs-crouch snap -- release only once the transition mix has
        * eased back out */
    wantGroup[0] = upperActive || g_loco_in_turning || (g_tip_stepping >= 0)
                 || (g_tip_linger > 0) || g_slope_hold || g_loco_in_air
                 || drop_unwind || stance_hold;                                 /* legs:
                                     * airborne claims them for the tuck pose */
    wantGroup[1] = upperActive || g_slope_hold || g_loco_in_air || drop_unwind
                 || stance_hold || stance_drop_on;                                                /* core:
                                     * slope stance needs the pelvis for the IK drop */
    wantGroup[2] = upperActive || stance_hold;                                  /* upper */
    int *ownedPtr[3] = { &g_lower_owned, &g_core_owned, &g_upper_owned };
    for (int grp = 0; grp < 3; grp++){
        int want = wantGroup[grp];
        if (want == *ownedPtr[grp]) continue;
        for (int i = 0; i < g_kfa.numBones; i++){
            if (g_kfa.bones[i].group != grp) continue;
            g_oldbone_setmanual(g_slots[i].bone, want);
            if (g_disable_bone && readable(g_loco_skel, 8)){
                unsigned char nm[64];
                void *heap = make_mstr_long(nm, g_kfa.bones[i].name);
                g_disable_bone(g_loco_skel, nm, want ? 1 : 0);
                if (heap) free(heap);
            }
            if (want){
                const Quat *cq = g_oldnode_getori ? g_oldnode_getori(g_slots[i].bone) : NULL;
                g_loco_prevpose[i] = readable((void*)cq, 16) ? *cq : g_slots[i].park;
                g_loco_acqpose[i]  = g_loco_prevpose[i];   /* idle-side blend target */
                /* spine bones bent by the idle aim: the blend target must be the UNBENT
                 * base -- snapshotting the bent pose made the moving aim re-apply the
                 * offsets ON TOP (additive look-down that never reset) */
                if (g_idleaim_owned && grp == 2)
                    for (int k2 = 0; k2 < 3; k2++)
                        if (g_slot_spine[k2] == i){ g_loco_acqpose[i] = g_idleaim_base[k2]; break; }
            } else
                g_loco_havew[i] = 0;
        }
        if (grp == 2 && !want) g_upper_handback = 3;   /* fresh handback window */
        if (grp == 1 && !want && g_ik_pospushed && g_oldnode_setpos && g_slot_pelvis >= 0
            && readable(g_slots[g_slot_pelvis].bone, 8)){
            /* releasing the core with a pelvis drop applied: restore the bind position
             * (nothing else ever writes bone positions) */
            g_oldnode_setpos(g_slots[g_slot_pelvis].bone, &g_pelvis_bindoff);
            g_oldnode_needupd(g_slots[g_slot_pelvis].bone, 1);
            g_ik_pospushed = 0; g_ik_drop = 0;
        }
        if (grp == 1 && g_loco_root){   /* root rides with the core group */
            g_oldbone_setmanual(g_loco_root, want);
            if (want){
                const Quat *rq = g_oldnode_getinitori(g_loco_root);
                g_root_bind = readable((void*)rq, 16) ? *rq : (Quat){1,0,0,0};
                const Quat *cl = g_oldnode_getori ? g_oldnode_getori(g_loco_root) : NULL;
                g_root_acq  = readable((void*)cl, 16) ? *cl : g_root_bind;
                /* written per-frame below: slerp(acq, bind, moveblend) */
            }
            if (g_disable_bone && readable(g_loco_skel, 8)){
                unsigned char nm[64];
                void *heap = make_mstr_long(nm, "Bip01");
                g_disable_bone(g_loco_skel, nm, want ? 1 : 0);
                if (heap) free(heap);
            }
        }
        if (want) g_loco_fade = 1.0f;
        *ownedPtr[grp] = want;
    }
    if (g_loco_fade >= 1.0f && g_loco_have_out){
        /* bones we already owned keep their current output through the fade */
        for (int i = 0; i < g_kfa.numBones; i++)
            if (*ownedPtr[g_kfa.bones[i].group] && g_loco_havew[i])
                g_loco_prevpose[i] = g_loco_outpose[i];
    }

    /* ---- move angle (0 = fwd, + = right), eased with reversal latch. The commanded
     * facing (facing lock) is the authoritative reference; calibrated root yaw is the
     * fallback when facing lock is off. ---- */
    float angT = 0.0f;
    if (moving){
        if (g_loco_in_havebody)                 angT = loco_wrap_pi(g_loco_in_heading - g_loco_in_bodyyaw);
        else if (haveYaw && g_loco_have_fwdref) angT = loco_wrap_pi(g_loco_in_heading - bodyYaw);
    }
    float dAng = loco_wrap_pi(angT - g_loco_angle);
    if (fabsf(dAng) > LOCO_REVERSAL && g_loco_have_out){
        /* reversal: snapshot the current pose, snap the angle, crossfade (spec §D latch) */
        memcpy(g_loco_prevpose, g_loco_outpose, sizeof(Quat) * g_kfa.numBones);
        g_loco_fade = 1.0f;
        g_loco_angle = angT;
    } else {
        /* direction ease: snappier at walk (low gait), heavier at sprint */
        float cap = (LOCO_TURN_RATE + (1.0f - g_loco_gait) * 4.0f) * dt;
        g_loco_angle = loco_wrap_pi(g_loco_angle + loco_clampf(dAng, -cap, cap));
    }

    /* ---- phase advance (§A): shared normalized phase, effLen blends walk->jog ---- */
    int singleClip = (g_cfg_loco_clip >= 0 && g_cfg_loco_clip < g_kfa.numClips) || !g_loco_bs_ok;
    /* eased sneak weight: drives the clip MIX in the pose composer and the
     * stride length below -- entering/leaving sneak morphs continuously (the
     * air-tuck pattern) instead of hard-switching clip sets through a frozen
     * snapshot crossfade (the old transition hitch). */
    {
        float sk = dt * 5.0f; if (sk > 1) sk = 1;
        float st = (g_loco_in_sneak && g_loco_crouch_ok) ? 1.0f : 0.0f;
        g_sneak_w += (st - g_sneak_w) * sk;
    }
    float snw = g_sneak_w * g_sneak_w * (3.0f - 2.0f * g_sneak_w);
    {
        float smk = dt * 6.0f; if (smk > 1) smk = 1;
        int trans = (g_sneak_cool > 0.0f)
                 || (g_sneak_w > 0.02f && g_sneak_w < 0.98f);
        static int prevTrans;
        if (prevTrans && !trans && g_loco_have_out)
            /* transition finished: refresh the idle acquire base to the CURRENT
             * output so the mix eases out as a no-op and the eventual release
             * happens from the exact pose being shown */
            for (int i = 0; i < g_kfa.numBones; i++)
                g_loco_acqpose[i] = g_loco_outpose[i];
        prevTrans = trans;
        g_stancemix_w += ((trans ? 1.0f : 0.0f) - g_stancemix_w) * smk;
    }
    if (singleClip){
        int ci = (g_cfg_loco_clip >= 0 && g_cfg_loco_clip < g_kfa.numClips) ? g_cfg_loco_clip : 0;
        float len = g_kfa.clips[ci].length > 0.05f ? g_kfa.clips[ci].length : 1.0f;
        g_loco_phase += dtA / len;
    } else {
        float wlen = g_kfa.clips[g_loco_walkclip[0]].length;
        float jlen = g_kfa.clips[g_loco_jogclip[0]].length;
        float effLen = wlen + (jlen - wlen) * g_loco_gait;
        if (g_loco_crouch_ok && snw > 0.001f)
            effLen += (g_kfa.clips[g_loco_crouchclip[0]].length - effLen) * snw;
        if (effLen < 0.05f) effLen = 1.0f;
        /* stride-match: play faster/slower so feet track the actual ground speed */
        float ref = g_cfg_loco_walkref + (g_cfg_loco_jogref - g_cfg_loco_walkref) * g_loco_gait;
        float rate = (moving && ref > 1.0f) ? loco_clampf(g_loco_in_speed / ref, 0.5f, 2.0f) : 1.0f;
        g_loco_phase += dtA * rate / effLen;
        float ilen = g_kfa.clips[g_loco_idleclip].length;
        g_loco_idlephase += dtA / (ilen > 0.05f ? ilen : 1.0f);
    }
    g_loco_phase     -= (float)((int)g_loco_phase);
    g_loco_idlephase -= (float)((int)g_loco_idlephase);

    /* ---- compose the pose ---- */
    Quat pose[128];
    if (singleClip){
        int ci = (g_cfg_loco_clip >= 0 && g_cfg_loco_clip < g_kfa.numClips) ? g_cfg_loco_clip : 0;
        for (int i = 0; i < g_kfa.numBones; i++) pose[i] = loco_sample(ci, i, g_loco_phase);
    } else {
        /* sneak: the crouch set is MIXED with the stand set by the EASED weight
         * (snw) -- entering/leaving sneak mid-stride morphs continuously, the
         * way the air tuck hands over, instead of crossfading through a frozen
         * snapshot (the old hitch). Extra samples only while 0<snw<1. */
        int useC = g_loco_crouch_ok && snw > 0.001f;
        int useS = snw < 0.999f;
        /* 8-way directional pick: two adjacent sectors (spec §D) */
        float tau = 6.28318531f, step = tau / 8.0f;
        float a = g_loco_angle; while (a < 0) a += tau; while (a >= tau) a -= tau;
        float sIdx = a / step;
        int i0 = ((int)sIdx) & 7, i1 = (i0 + 1) & 7;
        float fdir = sIdx - (float)((int)sIdx);
        for (int i = 0; i < g_kfa.numBones; i++){
            Quat q;
            Quat qs = {1,0,0,0}, qc = {1,0,0,0};
            if (useS){
                Quat w0 = loco_sample(g_loco_walkclip[i0], i, g_loco_phase);
                Quat j0 = loco_sample(g_loco_jogclip[i0], i, g_loco_phase);
                qs = quat_slerp(w0, j0, g_loco_gait);           /* SampleDir(i0) */
                if (fdir > 1e-3f){
                    Quat w1 = loco_sample(g_loco_walkclip[i1], i, g_loco_phase);
                    Quat j1 = loco_sample(g_loco_jogclip[i1], i, g_loco_phase);
                    qs = quat_slerp(qs, quat_slerp(w1, j1, g_loco_gait), fdir);
                }
            }
            if (useC){
                qc = loco_sample(g_loco_crouchclip[i0], i, g_loco_phase);
                if (fdir > 1e-3f)
                    qc = quat_slerp(qc, loco_sample(g_loco_crouchclip[i1], i, g_loco_phase),
                                    fdir);
            }
            q = !useC ? qs : (!useS ? qc : quat_slerp(qs, qc, snw));
            if (g_loco_moveblend < 0.999f){
                /* idle-side blend base = the game pose captured at acquire: both handoff
                 * directions land exactly on what the game shows (incl. hurt idles).
                 * Smoothstepped so the fade starts and ends without a velocity kink
                 * (the linear ramp's hard edges read as a hitch). */
                float mw = g_loco_moveblend * g_loco_moveblend * (3.0f - 2.0f * g_loco_moveblend);
                Quat base = g_loco_acqpose[i];
                if (g_stancemix_w > 0.01f && g_loco_crouch_ok && g_loco_crouchidle >= 0){
                    /* stance change in flight: bridge with OUR OWN idle clips,
                     * mixed by the sneak weight.
                     * THE STAND END MUST BE THE STAND IDLE CLIP, NOT acqpose:
                     * acqpose is the game pose snapshotted when we CLAIMED the
                     * bones, i.e. the pose of the stance we are LEAVING. On an
                     * uncrouch it is the CROUCHED pose, so a snw->0 blend back
                     * to it left the body crouched forever -- and the stuck
                     * crouch then read as "feet floating" to the plant IK,
                     * which dove the pelvis (trace: drop -0.6) and kept the
                     * groups held via drop_unwind: a self-sustaining stuck
                     * state. Both idle clips carry full 20/20 tracks (verified
                     * against the .kfa), so sampling the stand idle is safe --
                     * the earlier T-pose was the async layer re-registration,
                     * fixed by the per-frame ownership re-assert. */
                    Quat sidle = loco_sample(g_loco_idleclip, i, g_loco_idlephase);
                    if (snw > 0.001f)
                        sidle = quat_slerp(sidle,
                            loco_sample(g_loco_crouchidle, i, g_loco_idlephase), snw);
                    float smw = g_stancemix_w * g_stancemix_w
                              * (3.0f - 2.0f * g_stancemix_w);
                    base = quat_slerp(base, sidle, smw);
                }
                q = quat_slerp(base, q, mw);
            }
            pose[i] = q;
        }
    }

    /* ---- turn-in-place (§E simplified): keep feet directionally planted, step past the
     * threshold. Legs counter-rotate about the vertical in the pelvis frame; a stepping leg
     * borrows the walk clip's swing pose for the lift. Engages only near-idle. ---- */
    int tipActive = (!singleClip && haveYaw && g_loco_moveblend < TIP_ENGAGE_MB
        && !g_loco_in_air   /* mid-air the feet have nothing to plant on: the
            * counter-rotation must not hold the legs at the old world yaw
            * while the body turns with the camera (the "legs don't rotate
            * with the jump turn" bug) -- fade out and re-track below */
        && g_slot_pelvis >= 0 && g_slot_leg[0][0] >= 0 && g_slot_leg[1][0] >= 0);
    if (g_loco_in_air){
        /* keep the locks glued to the current body yaw while airborne so the
         * fade-out unwinds toward ZERO error (not toward a stale lock), and
         * landing starts fresh with feet aligned to the new facing */
        g_tip_lock[0] = g_tip_lock[1] = bodyYaw;
        g_tip_stepping = -1;
    }
    {   /* eased engage/disengage (~0.12s): the modifiers fade instead of gating */
        float twk = dt * 8.0f; if (twk > 1) twk = 1;
        g_tip_w += ((tipActive ? 1.0f : 0.0f) - g_tip_w) * twk;
    }
    if ((tipActive || g_tip_w > 0.01f) && haveYaw && !singleClip
        && g_slot_pelvis >= 0 && g_slot_leg[0][0] >= 0 && g_slot_leg[1][0] >= 0
        && g_lower_owned){
        const Quat *rd = g_oldnode_getdori(g_loco_root);
        if (readable((void*)rd, 16)){
            /* pelvis frame: our written pose while we own the core; the LIVE game local
             * during TIP-only turns (core released, vanilla idle animates it) */
            Quat pelvisL = g_slots[g_slot_pelvis].park;
            if (g_core_owned){
                if (g_cfg_loco_hips) pelvisL = pose[g_slot_pelvis];
            } else if (g_oldnode_getori){
                const Quat *pl = g_oldnode_getori(g_slots[g_slot_pelvis].bone);
                if (readable((void*)pl, 16)) pelvisL = *pl;
            }
            Quat pelvisG = quat_norm(quat_mul(*rd, pelvisL));
            Vec3 upL = quat_rotvec(quat_conj(pelvisG), (Vec3){ 0, 1, 0 });
            for (int f = 0; f < 2; f++){
                if (!g_tip_have[f]){ g_tip_lock[f] = bodyYaw; g_tip_have[f] = 1; }
                if (g_tip_stepping == f){
                    g_tip_t[f] += dt / TIP_STEP_TIME;
                    float t = g_tip_t[f] > 1 ? 1 : g_tip_t[f];
                    float sm = t * t * (3 - 2 * t);   /* smoothstep */
                    g_tip_lock[f] = g_tip_lockstart[f]
                                  + loco_wrap_pi(bodyYaw - g_tip_lockstart[f]) * sm;
                    if (g_tip_t[f] >= 1){ g_tip_stepping = -1; g_tip_lock[f] = bodyYaw; }
                }
                float err = loco_wrap_pi(bodyYaw - g_tip_lock[f]);
                if (g_tip_stepping < 0 && fabsf(err) > TIP_STEP_ANGLE
                    && !g_loco_in_air){   /* no in-place stepping in mid-air */
                    g_tip_stepping = f; g_tip_t[f] = 0; g_tip_lockstart[f] = g_tip_lock[f];
                }
                if (fabsf(err) * g_tip_w > 1e-4f){
                    Quat R = loco_axis_angle(upL, -err * g_tip_w);   /* counter-rotate, eased */
                    pose[g_slot_leg[f][0]] = quat_norm(quat_mul(R, pose[g_slot_leg[f][0]]));
                }
                if (g_tip_stepping == f && g_loco_bs_ok){
                    /* borrow the walk clip's swing pose for a natural lift */
                    float w = sinf((g_tip_t[f] > 1 ? 1 : g_tip_t[f]) * 3.14159265f)
                            * TIP_STEP_BLEND * g_tip_w;
                    float sp = (f == 0) ? TIP_SWING_PH_L : TIP_SWING_PH_R;
                    for (int b = 0; b < 3; b++){
                        int si = g_slot_leg[f][b];
                        Quat sw = loco_sample(g_loco_walkclip[0], si, sp);
                        pose[si] = quat_slerp(pose[si], sw, w);
                    }
                }
            }
        }
    }
    if (!tipActive && g_tip_w <= 0.01f){
        /* fully faded out: locks may re-track (freezing them DURING the fade lets the
         * counter-rotation unwind visually instead of vanishing) */
        g_tip_lock[0] = g_tip_lock[1] = bodyYaw;
        g_tip_have[0] = g_tip_have[1] = haveYaw;
        g_tip_stepping = -1;
    }

    /* ---- torso ACCEL-LEAN SPRING (Destreza Player.cs port, web main.ts:7396-7424):
     * accel proxy = velocity minus its 8/s low-pass, split body-local; two damped
     * springs (1.8 Hz, zeta 0.8, clamp 0.2 rad) lean the torso INTO starts, stops and
     * strafes and ring down. Gain rescaled for Kenshi units (~0.09 m/unit). ---- */
    {
        float kv = 1.0f - expf(-8.0f * dt);
        g_lean_vsx += (g_loco_in_velx - g_lean_vsx) * kv;
        g_lean_vsz += (g_loco_in_velz - g_lean_vsz) * kv;
        float axl = g_loco_in_velx - g_lean_vsx, azl = g_loco_in_velz - g_lean_vsz;
        float fyl = g_loco_in_bodyyaw;
        float fwx = sinf(fyl), fwz = cosf(fyl);
        float rwx = -fwz, rwz = fwx;                       /* fwd x up (character right) */
        float gain = 0.005f * g_cfg_loco_lean;             /* 0.05 in Destreza meters */
        float tF = (axl * fwx + azl * fwz) * gain;
        float tR = (axl * rwx + azl * rwz) * gain;
        const float om = 6.2831853f * 1.8f, om2 = om * om, zc = 2.0f * 0.8f * om;
        g_lean_fv += (om2 * (tF - g_lean_f) - zc * g_lean_fv) * dt;
        g_lean_f   = loco_clampf(g_lean_f + g_lean_fv * dt, -0.2f, 0.2f);
        g_lean_rv += (om2 * (tR - g_lean_r) - zc * g_lean_rv) * dt;
        g_lean_r   = loco_clampf(g_lean_r + g_lean_rv * dt, -0.2f, 0.2f);
    }

    /* ---- IDLE aim offsets: same Destreza chain, but on-demand ownership of just the
     * spine trio, base = the LIVE game idle pose (hurt variants included), composed
     * under the live game root+pelvis. Deadzone-gated with hysteresis so the bones go
     * back to vanilla breathing whenever the camera settles level + aligned. ---- */
    /* ---- LANDING ABSORB envelope (Destreza landing port): quick dip (~0.12s),
     * eased recovery. The dip rides the SAME pelvis-position pathway as the
     * foot IK's hip drop, so when the IK is active the feet stay planted and
     * the knees bend to absorb; head-welded FP camera dips either way. ---- */
    if (g_land_amt > 0.005f){
        g_land_age += dt;
        float e = g_land_age < 0.06f ? (g_land_age / 0.06f)
                                     : expf(-(g_land_age - 0.06f) * 9.0f);
        g_land_dip = -0.75f * g_land_amt * e;
        if (g_land_age > 0.75f){ g_land_amt = 0.0f; g_land_dip = 0.0f; }
    } else g_land_dip = 0.0f;

    /* ---- FOOT-TO-GROUND IK: plant each ankle at (engine ground height + bind sole)
     * with an analytic two-bone solve. Active while we own the legs and near-idle
     * (TIP turns, stop-settle, idle slope-claim); the TIP stepping foot is exempt
     * (it is airborne by design). Rotation-only: thigh re-aimed, shin re-aimed,
     * foot keeps its world orientation (stays flat). ---- */
    int ikActive = g_cfg_loco_footik && g_lower_owned && g_loco_in_havebody
                && RVA_GROUND_AT && !singleClip
                && g_sneak_cool <= 0.0f   /* sneak toggle: stop solving NOW so
                    * the pelvis drop eases out through the IK-inactive path
                    * BEFORE the bones release -- re-solving against the
                    * half-changed stance was the frame-after correction */
                && (!g_loco_in_air || g_loco_in_airland > 0.01f)   /* airborne: the
                    * AIR TUCK replaces ground planting (Destreza: "Airborne: skip
                    * entirely") -- EXCEPT the landing approach: the anticipation
                    * ramp re-engages the plant early so the feet reach down and
                    * pre-shape to the surface (slope stance ready AT touchdown,
                    * g_ik_w already warm, no neutral-then-correct pop). The
                    * per-foot |ground - pos| < 4 guard naturally limits this to
                    * the final few units of the descent. */
                && (g_loco_moveblend < 0.5f || g_land_dip < -0.02f
                    || (g_loco_in_air && g_loco_in_airland > 0.01f))   /* LANDING ABSORB:
                    * hard-plant the feet at any gait so the knees BEND under the
                    * pelvis dip (Destreza plants both feet on a landing) -- without
                    * this a moving landing only dipped, legs riding the clip */
                && g_slot_pelvis >= 0 && g_slot_leg[0][0] >= 0 && g_slot_leg[1][0] >= 0
                && g_ik_a[0] > 0.1f && g_ik_b[0] > 0.1f;
    /* ---- CROUCH STANCE DROP: the .kfa bakes ROTATIONS ONLY, so a crouch
     * clip's pelvis TRANSLATION is lost -- the legs fold but the hips stay at
     * standing height and the feet ride up into the air ("feet float in
     * sneak"). Recover it from the posed skeleton: FK the ankles with the
     * pelvis at bind, and lower the pelvis until the LOWEST foot is back at
     * the bind sole height. Works for idle AND moving crouch (unlike the
     * plant IK, which is near-idle only), and the plant IK then solves ground
     * contact on top of this stance. ---- */
    if (g_slot_pelvis >= 0 && g_slot_leg[0][0] >= 0 && g_slot_leg[1][0] >= 0
        && g_ik_a[0] > 0.1f && snw > 0.001f && !g_loco_in_air && g_lower_owned){
        Quat pelvisL = (g_core_owned && g_cfg_loco_hips) ? pose[g_slot_pelvis]
                                                        : g_slots[g_slot_pelvis].park;
        Quat pelvisG = quat_norm(quat_mul(g_root_bind, pelvisL));
        Vec3 pP0 = v3_add(g_root_bindpos, quat_rotvec(g_root_bind, g_pelvis_bindoff));
        float lowest = 1e9f;
        for (int f = 0; f < 2; f++){
            int iT = g_slot_leg[f][0], iC = g_slot_leg[f][1];
            Vec3 hip   = v3_add(pP0, quat_rotvec(pelvisG, g_ik_thighoff[f]));
            Quat thighG = quat_norm(quat_mul(pelvisG, pose[iT]));
            Vec3 knee  = v3_add(hip, quat_rotvec(thighG, g_ik_calfoff[f]));
            Quat calfG = quat_norm(quat_mul(thighG, pose[iC]));
            Vec3 ankle = v3_add(knee, quat_rotvec(calfG, g_ik_footoff[f]));
            if (ankle.y < lowest) lowest = ankle.y;
        }
        float want = g_ik_ankle0 - lowest;                 /* negative = drop */
        float lim  = -0.45f * (g_ik_a[0] + g_ik_b[0]);     /* leg-length bound */
        want = loco_clampf(want * snw, lim, 0.0f);
        float sk3 = dt * 8.0f; if (sk3 > 1) sk3 = 1;
        g_stance_drop += (want - g_stance_drop) * sk3;
        {   static int sd; if (KFP_DEBUG_LOG && (++sd % 120) == 1)
                logline("[crouch] stance drop %.2f (want %.2f, lowest ank %.2f, sole %.2f)",
                        g_stance_drop, want, lowest, g_ik_ankle0); }
    } else {
        float sk3 = dt * 8.0f; if (sk3 > 1) sk3 = 1;
        g_stance_drop += (0.0f - g_stance_drop) * sk3;
    }
    ik_was_active = ikActive;   /* next frame's drop_unwind guard */
    {
        float ikk = dt * 10.0f; if (ikk > 1) ikk = 1;
        g_ik_w += ((ikActive ? 1.0f : 0.0f) - g_ik_w) * ikk;
    }
    if (g_ik_w > 0.01f && ikActive){
        /* skeleton-space chain from the bind root (positions are bind, rotations ours) */
        float rmwi = g_loco_moveblend * g_loco_moveblend * (3.0f - 2.0f * g_loco_moveblend);
        Quat rootQ = quat_slerp(g_root_acq, g_root_bind, rmwi);
        Quat pelvisL = (g_core_owned && g_cfg_loco_hips) ? pose[g_slot_pelvis]
                                                         : g_slots[g_slot_pelvis].park;
        if (!g_core_owned && g_oldnode_getori){
            const Quat *pl = g_oldnode_getori(g_slots[g_slot_pelvis].bone);
            if (readable((void*)pl, 16)) pelvisL = *pl;
        }
        Quat pelvisG = quat_norm(quat_mul(rootQ, pelvisL));
        float cyi = cosf(g_loco_in_bodyyaw), syi = sinf(g_loco_in_bodyyaw);
        /* ground reference UNDER THE CHARACTER: all foot targets are RELATIVE to it, so
         * the capsule-vs-ground offset (measured: constant 0.15) cancels out entirely */
        float gRef;
        {
            Vec3 pc0 = { g_loco_in_posx, g_loco_in_posy + 2.0f, g_loco_in_posz };
            gRef = loco_gnd_q(&pc0);
            if (!(gRef > -100000.0f && gRef < 100000.0f)
                || fabsf(gRef - g_loco_in_posy) > 4.0f) gRef = g_loco_in_posy;
        }
        {   /* one-shot chain diag: catch frame bugs from the log */
            static int cd;
            if (cd < 3){ cd++;
                logline("[ik] rootQ=(%.2f,%.2f,%.2f,%.2f) pelvL=(%.2f,%.2f,%.2f,%.2f) core=%d",
                        rootQ.w, rootQ.x, rootQ.y, rootQ.z,
                        pelvisL.w, pelvisL.x, pelvisL.y, pelvisL.z, g_core_owned);
            }
        }
        /* PASS 1: measure each foot's ground delta from the UNDROPPED pelvis. A floating
         * foot (dy < 0) cannot be reached by bending (rotation-only shortens the leg) --
         * the PELVIS DROPS by the worst floating delta instead, so the higher leg bends
         * at the knee and the lower foot reaches the surface. */
        float wantDrop = 0;
        {
            Vec3 pP0 = v3_add(g_root_bindpos, quat_rotvec(rootQ,
                v3_add(g_pelvis_bindoff, (Vec3){0, g_stance_drop, 0})));   /* the
                * crouch stance is the BASELINE the ground IK corrects from */
            for (int f = 0; f < 2; f++){
                if (g_tip_stepping == f) continue;
                int iT = g_slot_leg[f][0], iC = g_slot_leg[f][1];
                Vec3 hip   = v3_add(pP0, quat_rotvec(pelvisG, g_ik_thighoff[f]));
                Quat thighG = quat_norm(quat_mul(pelvisG, pose[iT]));
                Vec3 knee  = v3_add(hip, quat_rotvec(thighG, g_ik_calfoff[f]));
                Quat calfG = quat_norm(quat_mul(thighG, pose[iC]));
                Vec3 ankle = v3_add(knee, quat_rotvec(calfG, g_ik_footoff[f]));
                Vec3 probe = { g_loco_in_posx + cyi * ankle.x + syi * ankle.z,
                               g_loco_in_posy + ankle.y + 2.0f,
                               g_loco_in_posz - syi * ankle.x + cyi * ankle.z };
                float gy = loco_gnd_q(&probe);
                if (!(gy > -100000.0f && gy < 100000.0f)) continue;
                if (fabsf(gy - g_loco_in_posy) > 4.0f) continue;   /* bogus hit (own body /
                                                                    * wrong floor) -- skip */
                float dyf = ((gy - gRef) + g_ik_ankle0) - ankle.y;
                static int ikdiag;
                if (ikdiag < 10){ ikdiag++;
                    logline("[ik] f=%d gy=%.2f posY=%.2f ankleY=%.2f dy=%.2f", f, gy,
                            g_loco_in_posy, ankle.y, dyf); }
                if (dyf < wantDrop) wantDrop = dyf;   /* most-floating foot */
            }
            /* NATURAL STANCE BOUND: cap the hip drop at ~half a step. A larger drop
             * (measured -1.0 pinned on a stair straddle) collapses the whole body and
             * forces the uphill leg into a buried deep-squat -- a real stance lets the
             * downhill foot hang slightly instead. */
            wantDrop = loco_clampf(wantDrop, -0.85f, 0.0f);   /* deeper hip drop: the
                * uphill knee bends further and the downhill leg gains the reach */
            if (g_loco_in_air) wantDrop = 0.0f;   /* landing approach: the feet REACH
                * for the surface but the pelvis stays up -- both feet read as
                * floating mid-air and the full straddle drop would deep-squat the
                * body (and the welded camera) before contact. The squash comes at
                * touchdown: the impact dip (g_land_dip) plus the straddle drop
                * forming under it, over legs that are already planted. */
        }
        {   /* eased drop, applied to the pelvis LOCAL POSITION (root local Y = skeleton Y) */
            float dk = dt * 10.0f; if (dk > 1) dk = 1;
            g_ik_drop += (wantDrop * g_ik_w - g_ik_drop) * dk;
            if (g_core_owned && g_oldnode_setpos
                && readable(g_slots[g_slot_pelvis].bone, 8)){
                Vec3 pp = g_pelvis_bindoff;
                pp.y += g_ik_drop + g_land_dip + g_stance_drop;
                g_oldnode_setpos(g_slots[g_slot_pelvis].bone, &pp);
                g_oldnode_needupd(g_slots[g_slot_pelvis].bone, 1);
                g_ik_pospushed = 1;
            }
        }
        Vec3 pelvisP = v3_add(g_root_bindpos,
                              quat_rotvec(rootQ, v3_add(g_pelvis_bindoff,
                                  (Vec3){0, g_ik_drop + g_land_dip + g_stance_drop, 0})));
        for (int f = 0; f < 2; f++){
            if (g_tip_stepping == f) continue;              /* stepping foot is airborne */
            int iT = g_slot_leg[f][0], iC = g_slot_leg[f][1], iF = g_slot_leg[f][2];
            Vec3 hip   = v3_add(pelvisP, quat_rotvec(pelvisG, g_ik_thighoff[f]));
            Quat thighG = quat_norm(quat_mul(pelvisG, pose[iT]));
            Vec3 knee  = v3_add(hip, quat_rotvec(thighG, g_ik_calfoff[f]));
            Quat calfG = quat_norm(quat_mul(thighG, pose[iC]));
            Vec3 ankle = v3_add(knee, quat_rotvec(calfG, g_ik_footoff[f]));
            /* world ankle -> engine ground query (buildings + terrain) */
            Vec3 probe = { g_loco_in_posx + cyi * ankle.x + syi * ankle.z,
                           g_loco_in_posy + ankle.y + 2.0f,
                           g_loco_in_posz - syi * ankle.x + cyi * ankle.z };
            float gy = loco_gnd_q(&probe);
            if (!(gy > -100000.0f && gy < 100000.0f)) continue;   /* garbage guard */
            float targetY = (gy - gRef) + g_ik_ankle0;   /* relative to the char's ground */
            if (fabsf(gy - g_loco_in_posy) > 4.0f) continue;   /* bogus hit guard */
            /* TOE probe: the foot extends well forward of the ankle -- on an uphill
             * surface/step the ground under the TOES is higher, and an ankle-only
             * target lets the front of the foot phase into the slope */
            Quat footG0 = quat_norm(quat_mul(calfG, pose[iF]));
            Vec3 toeP = v3_add(ankle, quat_rotvec(footG0, g_ik_toeoff[f]));
            Vec3 probeT = { g_loco_in_posx + cyi * toeP.x + syi * toeP.z,
                            g_loco_in_posy + toeP.y + 2.0f,
                            g_loco_in_posz - syi * toeP.x + cyi * toeP.z };
            float gyT = loco_gnd_q(&probeT);
            float slopeAng = 0;
            if (gyT > -100000.0f && gyT < 100000.0f && fabsf(gyT - gRef) < 4.0f){
                float fromToe = (gyT - gRef) + (g_ik_ankle0 - g_ik_toey) + 0.02f;
                if (fromToe > targetY) targetY = fromToe;   /* highest contact wins */
                Vec3 flat = v3_sub(toeP, ankle); flat.y = 0;
                float hd = v3_len(flat);
                if (hd > 0.3f)
                    slopeAng = loco_clampf(atan2f((gyT - gRef) - ((gy - gRef)), hd),
                                           -0.6f, 0.6f);
            }
            float dyv = (targetY - ankle.y) * g_ik_w;
            {   /* solve diag: model-vs-render discrepancies show here */
                static int s2d;
                if (((++s2d) % 120) < 2)
                    logline("[ik2] f=%d ankY=%.2f tgtY=%.2f dyv=%.2f gyA=%.2f gyT=%.2f slope=%.2f drop=%.2f w=%.2f",
                            f, ankle.y, targetY, dyv, gy - gRef,
                            (gyT > -100000.0f && gyT < 100000.0f) ? gyT - gRef : -99.0f,
                            slopeAng, g_ik_drop, g_ik_w);
            }
            dyv -= 0.04f * g_ik_w;   /* stance settle: seat the feet INTO the surface a
                * touch -- an exact on-surface target reads as floating */
            if (dyv > 0.10f) dyv += g_cfg_ik_lift * g_ik_w;   /* lift pad for SIGNIFICANT
                * raises only (stairs); padding flat-ground micro-corrections hovered
                * the feet above the landscape */
            dyv = loco_clampf(dyv, -1.0f, 3.0f);   /* raise headroom scales with the hip
                * drop (deeper drop -> bigger uphill correction); the solve's own d'
                * bounds protect the leg geometry */   /* raise bound: the solve is exact
                * (verified: model == target), and real stair straddles need 1.3-2.0 --
                * the old 1.2 cap was truncating the plant (foot left in the step) */
            if (fabsf(dyv) < 0.02f && fabsf(slopeAng) < 0.03f) continue;
            Vec3 target = { ankle.x, ankle.y + dyv, ankle.z };
            /* two-bone solve: re-aim thigh, then shin, foot keeps world orientation */
            float a = g_ik_a[f], b = g_ik_b[f];
            Vec3 dv = v3_sub(target, hip);
            float d = v3_len(dv);
            float dmin = fabsf(a - b) * 1.05f + 0.01f, dmax = (a + b) * 0.995f;
            d = loco_clampf(d, dmin, dmax);
            Vec3 dirv = v3_norm(dv);
            /* hinge axis: current knee bend plane (fallback: pelvis lateral) */
            Vec3 tvec = v3_sub(knee, hip), svec = v3_sub(ankle, knee);
            Vec3 hinge = v3_cross(tvec, svec);
            if (v3_dot(hinge, hinge) < 1e-6f) hinge = (Vec3){1,0,0};   /* skeleton lateral:
                * knee-forward convention for a near-straight leg */
            hinge = v3_norm(hinge);
            float ca = (a*a + d*d - b*b) / (2.0f * a * d);
            ca = loco_clampf(ca, -1.0f, 1.0f);
            float alpha = acosf(ca);
            /* NEGATIVE alpha about thigh-cross-shin: deviates the thigh TOWARD the knee's
             * existing bend side (+alpha hyperextended -- the "knee never bends" bug) */
            Quat qa = loco_axis_angle(hinge, -alpha);
            Vec3 thighDirNew = quat_rotvec(qa, dirv);
            Vec3 thighDirCur = v3_norm(tvec);
            Quat qT = quat_arc(thighDirCur, thighDirNew);
            Quat thighGn = quat_norm(quat_mul(qT, thighG));
            pose[iT] = quat_norm(quat_mul(quat_conj(pelvisG), thighGn));
            Vec3 kneeNew = v3_add(hip, v3_scale(thighDirNew, a));
            Vec3 calfDirNew = v3_norm(v3_sub(target, kneeNew));
            Vec3 calfDirCur = quat_rotvec(qT, v3_norm(svec));
            Quat qC = quat_arc(calfDirCur, calfDirNew);
            Quat calfGn = quat_norm(quat_mul(qC, quat_norm(quat_mul(qT, calfG))));
            pose[iC] = quat_norm(quat_mul(quat_conj(thighGn), calfGn));
            {   /* verify: applied rotation magnitudes + post-solve model ankle */
                static int s3d;
                if (((++s3d) % 120) < 2){
                    float qTa = 2.0f * acosf(loco_clampf(fabsf(qT.w), 0, 1)) * 57.3f;
                    float qCa = 2.0f * acosf(loco_clampf(fabsf(qC.w), 0, 1)) * 57.3f;
                    Vec3 k2 = v3_add(hip, quat_rotvec(thighGn, g_ik_calfoff[f]));
                    Vec3 a2 = v3_add(k2, quat_rotvec(calfGn, g_ik_footoff[f]));
                    logline("[ik3] f=%d qT=%.1fdeg qC=%.1fdeg newAnkY=%.2f (tgt %.2f)",
                            f, qTa, qCa, a2.y, target.y);
                }
            }
            /* foot: preserve its former world orientation, then pitch the sole onto the
             * surface gradient (toes up on uphill ground) */
            Quat footGold = quat_norm(quat_mul(calfG, pose[iF]));
            if (fabsf(slopeAng) > 0.02f)
                footGold = quat_norm(quat_mul(
                    loco_axis_angle((Vec3){1,0,0}, -slopeAng * g_ik_w), footGold));
            pose[iF] = quat_norm(quat_mul(quat_conj(calfGn), footGold));
        }
    }

    /* ---- AIRBORNE LEG TUCK (Destreza AirPose port, EliteAnimator.cs AirPose /
     * web characterAnim.ts:240): while the fall/jump arc owns the body, ground
     * planting is meaningless -- instead each foot lifts toward the body (knees
     * bend up) by the client-fed envelope: zero at takeoff, peak at the apex,
     * zero again as fall speed builds, so the legs EXTEND to meet the landing
     * and the landing absorb takes over on touchdown. Same two-bone solve as
     * the plant IK, no ground queries; the raise is scaled by leg length
     * (Destreza: 0.34m tuck on a ~0.85m leg -> 0.40 * (thigh+calf)). ---- */
    static float g_air_w;
    int airActive = g_loco_in_air && g_cfg_loco_footik && g_lower_owned
                 && g_loco_in_havebody && !singleClip
                 && g_loco_in_airland < 0.5f   /* landing approach: hand the legs to
                     * the pre-engaged plant IK (which reaches for the surface) --
                     * running both would have the tuck clobber the plant. The raise
                     * fade below plus g_air_w's own 10/s ease keep it smooth. */
                 && g_slot_pelvis >= 0 && g_slot_leg[0][0] >= 0 && g_slot_leg[1][0] >= 0
                 && g_ik_a[0] > 0.1f && g_ik_b[0] > 0.1f;
    {
        float ak = dt * 10.0f; if (ak > 1) ak = 1;
        g_air_w += ((airActive ? 1.0f : 0.0f) - g_air_w) * ak;
    }
    if (g_air_w > 0.01f && airActive && g_loco_in_airtuck > 0.001f){
        float rmwi = g_loco_moveblend * g_loco_moveblend * (3.0f - 2.0f * g_loco_moveblend);
        Quat rootQ = quat_slerp(g_root_acq, g_root_bind, rmwi);
        Quat pelvisL = (g_core_owned && g_cfg_loco_hips) ? pose[g_slot_pelvis]
                                                         : g_slots[g_slot_pelvis].park;
        Quat pelvisG = quat_norm(quat_mul(rootQ, pelvisL));
        Vec3 pelvisP = v3_add(g_root_bindpos, quat_rotvec(rootQ, g_pelvis_bindoff));
        for (int f = 0; f < 2; f++){
            int iT = g_slot_leg[f][0], iC = g_slot_leg[f][1], iF = g_slot_leg[f][2];
            Vec3 hip   = v3_add(pelvisP, quat_rotvec(pelvisG, g_ik_thighoff[f]));
            Quat thighG = quat_norm(quat_mul(pelvisG, pose[iT]));
            Vec3 knee  = v3_add(hip, quat_rotvec(thighG, g_ik_calfoff[f]));
            Quat calfG = quat_norm(quat_mul(thighG, pose[iC]));
            Vec3 ankle = v3_add(knee, quat_rotvec(calfG, g_ik_footoff[f]));
            float a = g_ik_a[f], b = g_ik_b[f];
            float raise = g_air_w * g_loco_in_airtuck * 0.40f * (a + b)
                        * (1.0f - 2.0f * g_loco_in_airland);   /* fade the tuck out
                            * across the first half of the landing-anticipation ramp
                            * (the plant IK takes over at airland 0.5) */
            if (raise < 0.01f) continue;
            Vec3 target = { ankle.x, ankle.y + raise, ankle.z };
            /* two-bone solve, identical to the plant IK's (proven exact there) */
            Vec3 dv = v3_sub(target, hip);
            float d = v3_len(dv);
            float dmin = fabsf(a - b) * 1.05f + 0.01f, dmax = (a + b) * 0.995f;
            d = loco_clampf(d, dmin, dmax);
            Vec3 dirv = v3_norm(dv);
            Vec3 tvec = v3_sub(knee, hip), svec = v3_sub(ankle, knee);
            Vec3 hinge = v3_cross(tvec, svec);
            if (v3_dot(hinge, hinge) < 1e-6f) hinge = (Vec3){1,0,0};
            hinge = v3_norm(hinge);
            float ca = (a*a + d*d - b*b) / (2.0f * a * d);
            ca = loco_clampf(ca, -1.0f, 1.0f);
            float alpha = acosf(ca);
            Quat qa = loco_axis_angle(hinge, -alpha);
            Vec3 thighDirNew = quat_rotvec(qa, dirv);
            Quat qT = quat_arc(v3_norm(tvec), thighDirNew);
            Quat thighGn = quat_norm(quat_mul(qT, thighG));
            pose[iT] = quat_norm(quat_mul(quat_conj(pelvisG), thighGn));
            Vec3 kneeNew = v3_add(hip, v3_scale(thighDirNew, a));
            Vec3 calfDirNew = v3_norm(v3_sub(target, kneeNew));
            Vec3 calfDirCur = quat_rotvec(qT, v3_norm(svec));
            Quat qC = quat_arc(calfDirCur, calfDirNew);
            Quat calfGn = quat_norm(quat_mul(qC, quat_norm(quat_mul(qT, calfG))));
            pose[iC] = quat_norm(quat_mul(quat_conj(thighGn), calfGn));
            Quat footGold = quat_norm(quat_mul(calfG, pose[iF]));   /* foot keeps its
                * world orientation through the tuck (Destreza: stays flat) */
            pose[iF] = quat_norm(quat_mul(quat_conj(calfGn), footGold));
        }
        {   /* [air] engage diag, time-limited */
            static int ad;
            if (ad < 8){ ad++;
                logline("[air] tuck=%.2f w=%.2f raise=%.2f (leg %.2f)",
                        g_loco_in_airtuck, g_air_w,
                        g_air_w * g_loco_in_airtuck * 0.40f * (g_ik_a[0] + g_ik_b[0]),
                        g_ik_a[0] + g_ik_b[0]); }
        }
    }

    /* IK inactive: ease the pelvis drop back out and restore the exact bind position
     * once settled (positions are NEVER animation-written -- a stale drop would
     * persist). The landing dip also lands here when the plant IK is off (landing
     * at a run): the pelvis/camera still dips, feet ride the clip. */
    if ((!ikActive || g_ik_w <= 0.01f)
        && (g_ik_pospushed || g_land_dip < -0.005f || fabsf(g_stance_drop) > 0.005f)){
        float dk2 = dt * 8.0f; if (dk2 > 1) dk2 = 1;
        g_ik_drop += (0.0f - g_ik_drop) * dk2;
        if (g_core_owned && g_oldnode_setpos && g_slot_pelvis >= 0
            && readable(g_slots[g_slot_pelvis].bone, 8)){
            Vec3 pp = g_pelvis_bindoff;
            pp.y += g_ik_drop + g_land_dip + g_stance_drop;   /* crouch stance holds
                * the pelvis down even with the plant IK off (moving crouch) */
            if (fabsf(g_ik_drop) < 0.01f && g_land_dip > -0.005f
                && fabsf(g_stance_drop) < 0.005f){
                pp = g_pelvis_bindoff; g_ik_pospushed = 0; g_ik_drop = 0;
            } else g_ik_pospushed = 1;
            g_oldnode_setpos(g_slots[g_slot_pelvis].bone, &pp);
            g_oldnode_needupd(g_slots[g_slot_pelvis].bone, 1);
        } else { g_ik_drop = 0; g_ik_pospushed = 0; }   /* lost ownership: handled below */
    }

    /* SNEAK TOGGLE: the state change re-registers the game's animation layers and can
     * clear our per-bone disable flags -- the game's sneak anims then FIGHT our writes
     * (the classic pre-disableBone overwrite symptom). Re-assert ownership for every
     * group we hold on the toggle edge. */
    if (g_sneak_cool > 0) g_sneak_cool -= dt;
    {
        static int prevSneakRaw = -1;
        int stanceEdge = (g_loco_in_sneak != prevSneakRaw);
        if (stanceEdge){
            prevSneakRaw = g_loco_in_sneak;
            /* stance-change window: release the passive idle claims (slope-hold legs,
             * idle-aim spine) and hold them off briefly -- with those bones manual the
             * game CANNOT apply its crouch/stand transition, which intermittently left
             * the body stuck in the previous stance */
            g_sneak_cool = 0.6f;
            g_slope_hold = 0;
            g_tip_linger = 0;
            g_stance_dbg = 50;   /* [stance] trace: 50 frames after every toggle */
        }
        if (g_loco_reassert_t > 0.0f) g_loco_reassert_t -= dt;
        if (stanceEdge || g_loco_reassert_t > 0.0f || g_sneak_cool > 0.0f){
            /* re-assert EVERY frame of the stance window, not just the edge:
             * the game's layer re-registration lands ASYNC, a few frames after
             * the toggle -- a single edge re-assert left bones manual with
             * cleared disable flags and no animation = the BIND-POSE (T-pose)
             * flash, full-body now that the transition holds all groups */
            int ownedG[3] = { g_lower_owned, g_core_owned, g_upper_owned };
            for (int i = 0; i < g_kfa.numBones; i++){
                if (!ownedG[g_kfa.bones[i].group]) continue;
                g_oldbone_setmanual(g_slots[i].bone, 1);
                if (g_disable_bone && readable(g_loco_skel, 8)){
                    unsigned char nm[64];
                    void *heap = make_mstr_long(nm, g_kfa.bones[i].name);
                    g_disable_bone(g_loco_skel, nm, 1);
                    if (heap) free(heap);
                }
            }
            if (g_core_owned && g_loco_root){
                g_oldbone_setmanual(g_loco_root, 1);
                if (g_disable_bone && readable(g_loco_skel, 8)){
                    unsigned char nm[64];
                    void *heap = make_mstr_long(nm, "Bip01");
                    g_disable_bone(g_loco_skel, nm, 1);
                    if (heap) free(heap);
                }
            }
        }
    }

    if (g_upper_handback > 0) g_upper_handback--;
    int aimOn = g_cfg_loco_aim && g_cfg_aim_lean && g_sneak_cool <= 0;   /* F10 "Aim lean"
        * gates ALL aim offsets; the sneak-toggle cooldown forces the idle-aim claim to
        * release so the stance transition can play */
    if ((aimOn || g_idleaim_owned) && !g_upper_owned && g_loco_in_havebody && g_oldnode_getori
        && g_slot_pelvis >= 0 && g_slot_spine[0] >= 0 && g_slot_spine[1] >= 0
        && g_slot_spine[2] >= 0){
        float aP = g_loco_in_pitch * g_cfg_loco_aim_p;
        if (aP > 0) aP *= 0.72f;   /* look-DOWN bend eased ~28%% (playtested); up unchanged */
        float aY = loco_clampf(loco_wrap_pi(g_loco_in_camyaw - g_loco_in_bodyyaw),
                               -0.9f, 0.9f) * g_cfg_loco_aim_y;
        /* EASED gate: aimOn dropping (sneak toggle sets g_sneak_cool) used to
         * force mag=0 and release the spine bones THE SAME FRAME with the full
         * look-pitch bend still applied -- the game snapped the spine straight
         * in one frame and the head-welded camera popped ("sudden correction
         * the frame after sneak"). Ease the offsets to ~zero first; the
         * mag<0.02 release then fires from an already-straight spine. */
        static float aimw_e;
        {
            float ak2 = dt * 7.0f; if (ak2 > 1) ak2 = 1;
            aimw_e += ((aimOn ? 1.0f : 0.0f) - aimw_e) * ak2;
        }
        aP *= aimw_e;
        aY *= aimw_e;
        float mag = fabsf(aP) + fabsf(aY);
        if (!g_idleaim_owned && mag > 0.05f){
            for (int k = 0; k < 3; k++){
                int si = g_slot_spine[k];
                const Quat *cq = g_oldnode_getori(g_slots[si].bone);
                g_idleaim_base[k] = readable((void*)cq, 16) ? *cq : g_slots[si].park;
                if (g_upper_handback > 0)   /* taking over from the moving system: the
                                             * live local is still OUR bent settle pose */
                    g_idleaim_base[k] = g_loco_acqpose[si];
                g_oldbone_setmanual(g_slots[si].bone, 1);
                if (g_disable_bone && readable(g_loco_skel, 8)){
                    unsigned char nm[64];
                    void *heap = make_mstr_long(nm, g_kfa.bones[si].name);
                    g_disable_bone(g_loco_skel, nm, 1);
                    if (heap) free(heap);
                }
            }
            g_idleaim_owned = 1;
        } else if (g_idleaim_owned && mag < 0.02f){
            for (int k = 0; k < 3; k++){
                int si = g_slot_spine[k];
                g_oldbone_setmanual(g_slots[si].bone, 0);
                if (g_disable_bone && readable(g_loco_skel, 8)){
                    unsigned char nm[64];
                    void *heap = make_mstr_long(nm, g_kfa.bones[si].name);
                    g_disable_bone(g_loco_skel, nm, 0);
                    if (heap) free(heap);
                }
            }
            g_idleaim_owned = 0;
        }
        if (g_idleaim_owned){
            /* base eases to BIND: the moving path bends a near-neutral spine, and the
             * game idle's own curvature made the same pitch delta read differently --
             * converging the base unifies the idle and moving pitch feel. (Captured
             * live at claim so the takeover itself stays continuous.) */
            float bk2 = dt * 4.0f; if (bk2 > 1) bk2 = 1;
            for (int k = 0; k < 3; k++)
                g_idleaim_base[k] = quat_slerp(g_idleaim_base[k],
                                               g_slots[g_slot_spine[k]].park, bk2);
            static const float AIMW[3]  = { 0.12f, 0.15f, 0.16f };
            static const float AIMWY[3] = { 0.28f, 0.35f, 0.37f };   /* yaw/roll: full weight
                over the spine trio -- Destreza puts 57%% of the yaw on neck+head, which we
                don't drive, so their lower-chain weights left the twist invisible in FP */
            /* chain under the LIVE (game-animated) root + pelvis */
            Quat G = g_root_bind;
            if (g_loco_root){
                const Quat *rl = g_oldnode_getori(g_loco_root);
                if (readable((void*)rl, 16)) G = *rl;
            }
            const Quat *pl = g_oldnode_getori(g_slots[g_slot_pelvis].bone);
            G = quat_norm(quat_mul(G, readable((void*)pl, 16) ? *pl
                                                              : g_slots[g_slot_pelvis].park));
            for (int k = 0; k < 3; k++){
                int si = g_slot_spine[k];
                Quat dq = quat_norm(quat_mul(quat_mul(
                    loco_axis_angle((Vec3){1,0,0},  aP * AIMW[k]),
                    loco_axis_angle((Vec3){0,1,0},  aY * AIMWY[k])),   /* sign: playtested */
                    loco_axis_angle((Vec3){0,0,1}, -aY * g_cfg_loco_aim_r * AIMWY[k])));
                Quat bg = quat_norm(quat_mul(G, g_idleaim_base[k]));
                Quat ng = quat_norm(quat_mul(dq, bg));
                Quat lq = quat_norm(quat_mul(quat_conj(G), ng));
                g_oldnode_setori(g_slots[si].bone, &lq);
                g_oldnode_needupd(g_slots[si].bone, 1);
                G = ng;
            }
        }
    } else if (g_idleaim_owned && g_upper_owned)
        g_idleaim_owned = 0;   /* the moving upper group took the bones over */

    if (KFP_DEBUG_LOG && g_stance_dbg > 0){   /* [stance] per-frame toggle trace: which subsystem
                              * moves on the pop frame? */
        g_stance_dbg--;
        logline("[stance] sw=%.2f ikw=%.2f drop=%.3f dip=%.3f own=%d%d%d ia=%d tip=%d mb=%.2f cool=%.2f",
                g_sneak_w, g_ik_w, g_ik_drop, g_land_dip,
                g_lower_owned, g_core_owned, g_upper_owned,
                g_idleaim_owned, g_tip_stepping, g_loco_moveblend, g_sneak_cool);
    }

    /* ---- aim offsets (Destreza ApplyAimOffset, spec §F): weighted skeleton-space
     * deltas up the spine chain -- pitch about the character's lateral axis follows
     * the camera pitch; a yaw-lead (camera yaw vs the lagged body yaw) turns the
     * upper body ahead of the body. Kenshi skeleton space: up=+Y fwd=+Z left=+X;
     * pitch-down = +rot about +X, yaw-right = -rot about +Y. ---- */
    if (g_cfg_loco_aim && g_cfg_aim_lean && g_upper_owned && !singleClip
        && g_slot_pelvis >= 0 && g_slot_spine[0] >= 0 && g_slot_spine[1] >= 0
        && g_slot_spine[2] >= 0){
        /* NOT scaled by moveblend: the offsets are CAMERA state, not locomotion state --
         * scaling them made the look-down bend visibly reset through every idle<->moving
         * transition. Constant strength means the idle-aim and moving-aim hand over at
         * identical bend, and the stop-settle lands exactly where the idle-aim re-claims. */
        float aimP = g_loco_in_pitch * g_cfg_loco_aim_p;
        if (aimP > 0) aimP *= 0.72f;   /* look-DOWN bend eased ~28%% (playtested); up unchanged */
        float aimY = 0.0f;   /* NO yaw twist while moving: the body faces the camera; the
                              * yaw/roll offsets are an IDLE look-around behavior only */
        float leanF = g_lean_f, leanR = g_lean_r;   /* accel-lean self-zeroes at rest */
        float mw2 = g_loco_moveblend;               /* root-chain base only (matches the root write) */
        if (fabsf(aimP) > 1e-4f || fabsf(aimY) > 1e-4f
         || fabsf(leanF) > 1e-3f || fabsf(leanR) > 1e-3f){
            static const float AIMW[3]  = { 0.12f, 0.15f, 0.16f };   /* pitch: Destreza lower chain */
            static const float AIMWY[3] = { 0.28f, 0.35f, 0.37f };   /* yaw/roll: renormalized (see idle block) */
            /* chain FK in bind-skeleton space: root -> pelvis -> spine bones */
            float rmw = mw2 * mw2 * (3.0f - 2.0f * mw2);
            Quat G = quat_slerp(g_root_acq, g_root_bind, rmw);      /* root pose (as written) */
            Quat pelvisL = g_cfg_loco_hips ? pose[g_slot_pelvis] : g_slots[g_slot_pelvis].park;
            G = quat_norm(quat_mul(G, pelvisL));                    /* pelvis global */
            for (int k = 0; k < 3; k++){
                int si = g_slot_spine[k];
                Quat dq = quat_norm(quat_mul(quat_mul(
                    loco_axis_angle((Vec3){1,0,0},  aimP * AIMW[k]),
                    loco_axis_angle((Vec3){0,1,0},  aimY * AIMWY[k])),   /* sign: playtested */
                    loco_axis_angle((Vec3){0,0,1}, -aimY * g_cfg_loco_aim_r * AIMWY[k])));
                if (k == 0)
                    /* accel-lean rides the LUMBAR (Destreza ApplyLeans on spine.001):
                     * forward accel tips fwd (+rot about +X), rightward tips right
                     * (+rot about +Z fwd axis) -- axes constant in skeleton space */
                    dq = quat_norm(quat_mul(quat_mul(
                        loco_axis_angle((Vec3){1,0,0}, leanF),
                        loco_axis_angle((Vec3){0,0,1}, leanR)), dq));
                Quat bg = quat_norm(quat_mul(G, pose[si]));         /* bone global */
                Quat ng = quat_norm(quat_mul(dq, bg));              /* delta in skel space */
                pose[si] = quat_norm(quat_mul(quat_conj(G), ng));   /* back to local */
                G = ng;                                             /* parent for the next */
            }
        }
    }

    /* ---- acquire/reversal pose crossfade (smoothstepped) ---- */
    if (g_loco_fade > 0){
        g_loco_fade -= dt / LOCO_FADE_T;
        if (g_loco_fade < 0) g_loco_fade = 0;
        float w = g_loco_fade * g_loco_fade * (3.0f - 2.0f * g_loco_fade);
        for (int i = 0; i < g_kfa.numBones; i++)
            pose[i] = quat_slerp(pose[i], g_loco_prevpose[i], w);
    }

    /* ---- diagnostics: writes from last frame should be untouched now ---- */
    if (g_loco_diag > 0 && g_oldnode_getori){
        g_loco_diag--;
        for (int i = 0; i < g_kfa.numBones; i++){
            if (!g_loco_havew[i]) continue;
            const Quat *cur = g_oldnode_getori(g_slots[i].bone);
            if (!readable((void*)cur,16)) continue;
            float d = cur->w*g_loco_lastw[i].w + cur->x*g_loco_lastw[i].x
                    + cur->y*g_loco_lastw[i].y + cur->z*g_loco_lastw[i].z;
            if (d < 0) d = -d;
            if (d < 0.9998f)
                logline("[loco:diag] OVERWRITTEN %-18s now=(%.3f,%.3f,%.3f,%.3f) wrote=(%.3f,%.3f,%.3f,%.3f)",
                        g_kfa.bones[i].name, cur->w, cur->x, cur->y, cur->z,
                        g_loco_lastw[i].w, g_loco_lastw[i].x, g_loco_lastw[i].y, g_loco_lastw[i].z);
        }
    }

    /* ---- write ---- */
    int ownedNow[3] = { g_lower_owned, g_core_owned, g_upper_owned };
    for (int i = 0; i < g_kfa.numBones; i++){
        kfa_bone *b = &g_kfa.bones[i];
        if (!ownedNow[b->group]){ g_loco_outpose[i] = g_slots[i].park; continue; }  /* game-owned */
        if (b->flags == 1 || (b->flags == 2 && !g_cfg_loco_hips)){
            /* holds (clavicles/toes) + undriven pelvis: bind during locomotion (the
             * baked chain assumes it), the acquire-time game pose at the idle end */
            float mw = g_loco_moveblend * g_loco_moveblend * (3.0f - 2.0f * g_loco_moveblend);
            pose[i] = quat_slerp(g_loco_acqpose[i], g_slots[i].park, mw);
        }
        Quat q = quat_norm(pose[i]);
        g_oldnode_setori(g_slots[i].bone, &q);
        g_oldnode_needupd(g_slots[i].bone, 1);
        g_loco_lastw[i] = q; g_loco_havew[i] = 1;
        g_loco_outpose[i] = q;
    }
    /* root: bind while locomoting (the baked chain assumes it), captured game pose at
     * the idle ends -- blended with the same smoothstepped weight as everything else */
    if (g_core_owned && g_loco_root){
        float mw = g_loco_moveblend * g_loco_moveblend * (3.0f - 2.0f * g_loco_moveblend);
        Quat rq = quat_slerp(g_root_acq, g_root_bind, mw);
        g_oldnode_setori(g_loco_root, &rq);
        g_oldnode_needupd(g_loco_root, 1);
    }
    g_loco_have_out = 1;
}

#endif /* KFP_LOCOMOTION_H */
