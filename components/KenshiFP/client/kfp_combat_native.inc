/* Native ranged ownership. Feature is opt-in until coordinator acceptance.
 * Native lifecycle and physics use verified unique executable signatures.
 * No SDK address-table dependency or fixed native function RVAs. */
#include "kfp_combat_controller.h"
#include "kfp_aim_geometry.h"
#include "kfp_shot_geometry.h"
#include "kfp_ready_latch.h"
static KfpCombatController g_combat_control;
static KfpCombatObservation g_combat_observed;
static KfpCombatInput g_combat_injected;
static int g_combat_injection, g_combat_enabled, g_combat_native_ready;
/* `fp_combat input` commands received (all / with aim=1): a wrapper compares them with the inputs it sent itself, so
 * a second harness client on the rig (4080 b24+b25: two runners at once) shows up as foreign input. */
static unsigned g_combat_inj_cmds, g_combat_inj_aim_cmds;
static int g_combat_fault, g_combat_dispatch;
static DWORD g_combat_dispatch_tid;
static uint32_t g_combat_actor_ids[5];
static void *g_combat_pc, *g_combat_rc, *g_combat_weapon, *g_combat_gun;
static unsigned g_combat_actual_shots, g_combat_suppressed, g_combat_reload_starts;
static unsigned g_combat_anim_suppressed;   /* AI animationUpdate calls skipped on the owned ranged rc */
static int g_combat_anim_drive;             /* the adapter's last owned tick drove the aim/reload anim */
/* Character::+0x1A9 = on-screen flag, recomputed per frame from camera distance/frustum/bounds
 * (1.0.65 0x5C9580). RangedCombatClass::animationUpdate (1.0.65 0x51DA50, 1.0.68 0x51E4E0, same
 * code) first clears GunClass ready-to-shoot (vt 0x40), then returns early when the character
 * is off screen, so ready only comes back on frames the actor counts as visible. In FP the
 * camera sits inside the actor's own head and the flag flickers: isAnimationReadyToShoot
 * flickered 1/0 and fire edges landed on 0 frames (R12-SWAP last_reject aim_ready=0,
 * closeness 1, anim_suppressed=0). The adapter's own call treats its actor as on screen. */
#define CHAR_ONSCREEN 0x1A9
#define KFP_READY_BRIDGE_S 0.25f   /* game s a native ready dip is bridged (kfp_ready_latch.h) */
static KfpReadyLatch g_combat_ready_latch;
static int g_combat_ready_native=-1;
static unsigned g_combat_vis_forced;        /* adapter animationUpdate calls made with the flag forced */
/* Native reload timer (rc+0x78) read the frame a reload starts: R04/R05 evidence. */
static float g_combat_last_reload_timer=-1;
typedef void (*combat_rc_t)(void *,float,const void *,const void *);
typedef void (*combat_mt_t)(void *,float);
typedef void (*combat_end_t)(void *);
typedef void (*combat_setup_t)(void *,void *,int);
typedef char (*combat_reload_t)(void *);
static combat_rc_t g_combat_rc_orig;
static combat_mt_t g_combat_mt_orig;
static combat_end_t g_combat_end_orig, g_combat_end;
static combat_setup_t g_combat_setup;
static combat_reload_t g_combat_reload;
static combat_end_t g_combat_reset_timer;
static int combat_owned_rc(void *rc) {
    return g_combat_enabled && g_combat_native_ready && !g_combat_fault &&
           g_fp_mode && rc && rc==g_combat_rc && char_valid(g_combat_pc) &&
           g_combat_pc==g_fp_control_actor &&
           readable((void *)((uintptr_t)g_combat_pc+CHAR_HANDLE+HAND_IDS),20) &&
           !memcmp(g_combat_actor_ids,(void *)((uintptr_t)g_combat_pc+CHAR_HANDLE+HAND_IDS),20);
}
static uintptr_t combat_unique_signature(const char *sig);
#include "kfp_combat_trace.inc"
#include "kfp_combat_target.inc"
#include "kfp_combat_body.inc"
#include "kfp_combat_input.inc"
#include "kfp_combat_wound.inc"
static void combat_rc_hook(void *rc,float dt,const void *a,const void *b) {
    if (!combat_owned_rc(rc)) g_combat_rc_orig(rc,dt,a,b);
}
static void combat_mt_hook(void *rc,float dt) {
    if (!combat_owned_rc(rc)) g_combat_mt_orig(rc,dt);
}
static void combat_end_hook(void *rc) {
    if (!combat_owned_rc(rc)) g_combat_end_orig(rc);
}
/* R12: the AI ranged task calls RangedCombatClass::animationUpdate directly (target
 * NULL stops the aim anim, or its own aimpos), so isAnimationReadyToShoot flickered
 * on the owned actor. While the adapter drives the aim/reload anim itself (its last
 * tick called animationUpdate: aimed or reloading, allowed, aim point valid) those
 * calls are skipped; the adapter calls g_ranged_animupd_orig
 * directly, never through the hook. Only the owned RangedCombatClass is affected:
 * other characters and the melee path (no RangedCombatClass) stay native, and when
 * the adapter isn't driving it the AI call runs as before. */
static int fp_combat_own_animupd(void *rc) {
    if (!combat_owned_rc(rc)) return 0;
    if (!g_combat_anim_drive) return 0;
    ++g_combat_anim_suppressed;return 1;
}
static int fp_combat_suppress_shot(void *gun,void *pc) {
    if (combat_owned_rc(g_combat_rc) && pc==g_combat_pc) {
        if (!g_combat_dispatch || GetCurrentThreadId()!=g_combat_dispatch_tid || gun!=g_combat_gun) {++g_combat_suppressed;return 1;}
    }
    return 0;
}
static void *combat_virtual(void *object,size_t slot) {
    if (!readable(object,8)) return NULL;
    void **table=*(void ***)object;
    if (!readable((void *)((uintptr_t)table+slot),8)) return NULL;
    void *fn=*(void **)((uintptr_t)table+slot);
    MEMORY_BASIC_INFORMATION mi;
    return fn && VirtualQuery(fn,&mi,sizeof(mi)) && mi.State==MEM_COMMIT &&
        (mi.Protect&(PAGE_EXECUTE|PAGE_EXECUTE_READ|PAGE_EXECUTE_READWRITE|PAGE_EXECUTE_WRITECOPY))?fn:NULL;
}
/* World units are decimetres (B14). The aim ray must reach past any weapon range (crossbow 860 = 86 m):
 * with 80 (8 m) every farther target was aimed at a point 8 m ahead, so the bolt crossed the camera line
 * there and diverged (4080 batch 2: R08 chest/legs 0/6 at 30 m). Mesh-triangle refine stays near-field. */
#define KFP_AIM_RANGE 2000.0f
#define KFP_AIM_MESH_RANGE 80.0f
/* Mesh skin may sit this far in front of the physics shape of the same body (dm). */
#define KFP_SHOT_SAME_BODY 8.0f
/* Camera ray of the last aim query (shot muzzle fallback) and attribution telemetry. */
static Vec3 g_combat_aim_origin,g_combat_aim_dir;
static int g_combat_aim_have_ray;
static unsigned g_combat_aim_attr_kept,g_combat_aim_attr_dropped;
/* No target/limb grant: native projectile still resolves its physical hit.
 * Camera scene position uses the established floating-origin translation.
 * Called under the owning main-loop crash guard, never nests a guard. */
static int combat_camera_aim(Vec3 *out) {
    memset(&g_combat_camera_hit,0,sizeof(g_combat_camera_hit));
    g_combat_aim_have_ray=0;
    if (!g_have_t || !g_have_eye || !g_view_have_anchor || !g_ogre_ready || !g_node_get_dpos)
        return 0;
    void *cam=readable((void *)(g_base+RVA_CAM_INSTANCE),8)?*(void **)(g_base+RVA_CAM_INSTANCE):NULL;
    void *node=readable(cam,CC_NODE+8)?*(void **)((uintptr_t)cam+CC_NODE):NULL;
    if (!readable(node,8))return 0;
    Vec3 scene;
    /* forced update: the cached derived position lags the FP eye write (child of the center node) */
    const Vec3 *actual=g_node_getdpos_upd?g_node_getdpos_upd(node,&scene):g_node_get_dpos(node,&scene);
    if (!readable((void *)actual,sizeof(scene)))return 0;
    scene=*actual;
    float scene_xyz[3]={scene.x,scene.y,scene.z},origin_xyz[3],dir_xyz[3],end_xyz[3];
    if (!kfp_aim_geometry(scene_xyz,g_tx,g_tz,g_yaw,g_pitch,KFP_AIM_RANGE,
                          origin_xyz,dir_xyz,end_xyz))return 0;
    Vec3 origin={origin_xyz[0],origin_xyz[1],origin_xyz[2]};
    Vec3 dir={dir_xyz[0],dir_xyz[1],dir_xyz[2]};
    g_combat_aim_origin=origin;g_combat_aim_dir=dir;g_combat_aim_have_ray=1;
    Vec3 best={end_xyz[0],end_xyz[1],end_xyz[2]},hit;
    CombatRayHit physical={0};
    memset(&g_combat_camera_hit,0,sizeof(g_combat_camera_hit));
    int traced=combat_trace_ray(&origin,&dir,KFP_AIM_RANGE,&physical);
    if (traced<0)return 0;
    float nearest=KFP_AIM_RANGE;
    if (traced>0) {best=physical.position;nearest=physical.distance;g_combat_camera_hit=physical;}
    void *saved_node=g_mr_perch_node;mr_cache_t *saved_cache=g_mr_perch_cache;
    for(int visual=0;visual<2;++visual) {
        int got=visual?meshray_refine(&origin,&dir,KFP_AIM_MESH_RANGE,&hit):fall_ray(&origin,&dir,&hit);
        if (!got)continue;
        float distance=(hit.x-origin.x)*dir.x+(hit.y-origin.y)*dir.y+(hit.z-origin.z)*dir.z;
        if (isfinite(distance)&&distance>=0 && distance<nearest) {
            best=hit;nearest=distance;
            /* The mesh skin of the body the physics ray hit is nearer than its physics shape:
             * keep that character as the intended target (dropping it made every manual bolt
             * a non-target for the flight's friendly-fire/Precision pass-through roll). */
            if (g_combat_camera_hit.shape && kfp_shot_keep_attribution(physical.ids[0]==1,
                    physical.distance,distance,KFP_SHOT_SAME_BODY)) ++g_combat_aim_attr_kept;
            else {
                if (g_combat_camera_hit.shape) ++g_combat_aim_attr_dropped;
                memset(&g_combat_camera_hit,0,sizeof(g_combat_camera_hit));
            }
        }
    }
    g_mr_perch_node=saved_node;g_mr_perch_cache=saved_cache;
    *out=best;return 1;
}
/* R12-KO (4080 batch 14): the game's own unconscious flags. MedicalSystem (character+0x458) bytes +0x161/+0x164
 * are what Character::isUnconcious (exe 0x5c9380) and MedicalSystem::isUnconcious (0x28dd60) test first (Steam 1.0.65,
 * RVA db slot map). knockoutForceTimer (0x5c6b40) only writes medical+0xA0; the medical update turns that into these
 * flags later (>3 s on the 4080), and the ragdoll/prone state follows after them. Gate on the flags too. */
#define COMBAT_CHAR_MEDICAL 0x458
static void *g_combat_state_pc;   /* controlled char of the last step, for the state fields */
static int combat_char_unconscious(void *pc) {
    unsigned char *m=pc?(unsigned char *)pc+COMBAT_CHAR_MEDICAL:NULL;
    return m && readable(m+0x161,4) && (m[0x161]||m[0x164]);
}
static float combat_char_ko_timer(void *pc) {
    unsigned char *m=pc?(unsigned char *)pc+COMBAT_CHAR_MEDICAL:NULL;
    return m && readable(m+0xA0,4)?*(float *)(m+0xA0):-1.0f;
}
static int combat_truce_pending(void) {
    /* Conservative interim policy: with any active protected NPC, reject new
     * manual shots everywhere, including potential spread into that NPC.
     * Scoped first-victim truce routing replaces this only after validation. */
    return stobe_fight_truce_active();
}
static void *g_combat_gw;   /* this tick's GameWorld (combat_release liveness check) */
static void combat_release(void) {
    void *rc=g_combat_rc,*pc=g_combat_pc;
    g_combat_rc=NULL;g_combat_pc=NULL;g_combat_gun=NULL;g_combat_weapon=NULL;g_aim_mode=0;
    g_combat_dispatch=0;g_combat_dispatch_tid=0;
    /* only a live squad member gets the native end call: after a load g_combat_pc/rc are freed (b27b) */
    int same_actor=pc && fp_char_in_squad(g_combat_gw,pc) && char_valid(pc) && readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20) &&
        !memcmp(g_combat_actor_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20);
    memset(g_combat_actor_ids,0,sizeof(g_combat_actor_ids));
    memset(&g_combat_control,0,sizeof(g_combat_control));
    kfp_ready_latch_reset(&g_combat_ready_latch);
    if (rc && same_actor && readable(rc,0x88) &&
        *(void **)((uintptr_t)pc+CHAR_RANGEDCOMBAT)==rc &&
        *(void **)((uintptr_t)rc+RC_ME)==pc && g_combat_end_orig) g_combat_end_orig(rc);
}
/* GunClass::createPhysical (vt+0x18) sets harpoonMaterial (+0x70) =
 * MaterialManager::getByName(material). GunClass::shoot decrements ammo and then
 * returns before spawning the bolt when +0x70 is NULL (1.0.68 0x43A84F; 1.0.65
 * 0x43A4AF). The old "" material therefore gave ammo-only shots with no projectile
 * (4080 batch 5: 15 shots, 0 spawns). The native setup (1.0.68 0x436A50) passes the
 * body entity's material name from the helper below: we do the same. */
#define KFP_GUN_HARPOON_MAT 0x70
typedef void *(*combat_matname_t)(void *out_str,void *movable);
static combat_matname_t g_combat_matname;
static unsigned g_combat_gun_creates,g_combat_gun_repairs,g_combat_gun_matless;
static int combat_gun_has_material(void *gun) {
    return readable((void *)((uintptr_t)gun+KFP_GUN_HARPOON_MAT),8) &&
        *(void **)((uintptr_t)gun+KFP_GUN_HARPOON_MAT)!=NULL;
}
/* ---- Manual shot preparation (R07/R09/R14). Native contract: kfp_shot_geometry.h. ---- */
#define KFP_GUN_POSITION 0xE4      /* GunClass::position (GunClass::update writes the node's derived pos here) */
#define KFP_SHOT_EYE_AHEAD 1.0f    /* dm in front of the camera for the eye-muzzle fallback */
typedef Vec3 *(*combat_gun_vec_t)(void *,Vec3 *);
typedef Vec3 *(*combat_gun_aimdir_t)(void *,Vec3 *,const Vec3 *);
static int g_combat_eye_muzzle=1;  /* fp_combat muzzle 0|1 */
static Vec3 g_shot_aim,g_shot_barrel0,g_shot_barrel,g_shot_dir;
static float g_shot_angle=NAN,g_shot_clear_dist=NAN;
static int g_shot_intended,g_shot_phys_point,g_shot_mat=-1;
static unsigned g_shot_nospawn;
static const char *g_shot_clear="none";
static unsigned g_shot_count,g_shot_muzzle_moves;
/* Stale native barrel (local offset, see kfp_shot_barrel_check): count + how it was fixed. */
static unsigned g_shot_barrel_bad,g_shot_barrel_fixes;
static const char *g_shot_barrel_fix="none";
static int g_shot_barrel_why;
static float g_shot_barrel_raw_dist=NAN;
static Vec3 g_shot_gunpos0;
static const float g_shot_fix_ahead[3]={KFP_SHOT_EYE_AHEAD,3.0f,6.0f};
static int combat_char_ids_match(void *ch,const uint32_t ids[5]) {
    return ch && readable((void *)((uintptr_t)ch+CHAR_HANDLE+HAND_IDS),20) &&
        !memcmp((void *)((uintptr_t)ch+CHAR_HANDLE+HAND_IDS),ids,20);
}
static int combat_gun_barrel(void *gun,Vec3 *out) {
    void *fn=combat_virtual(gun,0x48);   /* GunClass::getBarrelPos */
    if (!fn) return 0;
    Vec3 tmp;Vec3 *r=((combat_gun_vec_t)fn)(gun,&tmp);
    if (!r || !isfinite(r->x) || !isfinite(r->y) || !isfinite(r->z)) return 0;
    *out=*r;return 1;
}
/* First thing the bolt tracer would meet on the barrel-to-aim line. */
static int combat_shot_trace(const Vec3 *from,const Vec3 *aim,CombatRayHit *h) {
    float f[3]={from->x,from->y,from->z},a[3]={aim->x,aim->y,aim->z},d[3];
    if (!kfp_shot_dir(a,f,d)) return -1;
    Vec3 dv={d[0],d[1],d[2]};
    float len=sqrtf((a[0]-f[0])*(a[0]-f[0])+(a[1]-f[1])*(a[1]-f[1])+(a[2]-f[2])*(a[2]-f[2]));
    memset(h,0,sizeof(*h));
    return combat_trace_ray_mask(from,&dv,len+KFP_SHOT_SAME_BODY,h,KFP_BOLT_TRACE_MASK);
}
/* Records the shot telemetry and, when the barrel-to-aim line starts inside the shooter's
 * own physics shape (the bolt tracer skips the shooter and loses that segment, at close
 * range the whole flight), moves the muzzle onto the camera ray. Returns 1 if the gun
 * position was moved (caller restores *saved after shoot). */
static int combat_shot_prepare(void *gun,void *pc,void *intended,const Vec3 *aim,Vec3 *saved) {
    ++g_shot_count;g_shot_aim=*aim;g_shot_intended=intended!=NULL;
    g_shot_clear="no_barrel";g_shot_clear_dist=NAN;g_shot_angle=NAN;
    memset(&g_shot_dir,0,sizeof(g_shot_dir));
    g_wound_next_dir[0]=g_wound_next_dir[1]=g_wound_next_dir[2]=NAN;
    Vec3 b;int moved=0;
    Vec3 *gpos=(Vec3 *)((uintptr_t)gun+KFP_GUN_POSITION);
    int gpos_ok=readable(gpos,sizeof(Vec3));
    if (gpos_ok) g_shot_gunpos0=*gpos;
    int have_b=combat_gun_barrel(gun,&b);
    if (!have_b) b.x=b.y=b.z=NAN;
    g_shot_barrel0=b;g_shot_barrel=b;
    /* Validate the native barrel against the shooter (4080 batch 12: barrel stayed the
     * local offset -1,5.9,0 after a gun create, every bolt flew from the world origin). */
    {Vec3 sp={NAN,NAN,NAN};int have_sp=char_position(pc,&sp);
     float bf[3]={b.x,b.y,b.z},sf[3]={sp.x,sp.y,sp.z};
     g_shot_barrel_raw_dist=have_sp&&have_b?sqrtf((b.x-sp.x)*(b.x-sp.x)+(b.y-sp.y)*(b.y-sp.y)+(b.z-sp.z)*(b.z-sp.z)):NAN;
     g_shot_barrel_why=kfp_shot_barrel_check(bf,sf,have_sp,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN);
     g_shot_barrel_fix="none";
     if (g_shot_barrel_why!=KFP_BARREL_OK) {
        ++g_shot_barrel_bad;g_shot_barrel_fix="unfixed";
        if (have_b && gpos_ok && g_combat_aim_have_ray) {
            /* Put the muzzle on the camera ray (the crosshair line); further ahead while
             * that point is still inside the shooter's own shape. */
            float o[3]={g_combat_aim_origin.x,g_combat_aim_origin.y,g_combat_aim_origin.z};
            float cd[3]={g_combat_aim_dir.x,g_combat_aim_dir.y,g_combat_aim_dir.z},m[3],first[3];
            int chosen=-1;
            for (int k=0;k<3;++k) {
                kfp_shot_eye_muzzle(o,cd,g_shot_fix_ahead[k],m);
                if (!k) {first[0]=m[0];first[1]=m[1];first[2]=m[2];}
                Vec3 mv={m[0],m[1],m[2]};CombatRayHit h2;int t2=combat_shot_trace(&mv,aim,&h2);
                if (t2>=0 && !(t2>0 && h2.ids[0]==1 && combat_char_ids_match(pc,h2.ids))) {chosen=k;break;}
            }
            if (chosen<0) {m[0]=first[0];m[1]=first[1];m[2]=first[2];}
            float p[3]={gpos->x,gpos->y,gpos->z},np[3];
            kfp_shot_muzzle_shift(p,bf,m,np);
            *saved=*gpos;gpos->x=np[0];gpos->y=np[1];gpos->z=np[2];moved=1;
            Vec3 nb;
            if (combat_gun_barrel(gun,&nb)) {
                float nf[3]={nb.x,nb.y,nb.z};
                if (kfp_shot_barrel_check(nf,sf,have_sp,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_OK) {
                    b=nb;++g_shot_barrel_fixes;
                    g_shot_barrel_fix=chosen==0?"eye":chosen>0?"eye_far":"eye_self";
                } else {*gpos=*saved;moved=0;g_shot_barrel_fix="shift_failed";}
            } else {*gpos=*saved;moved=0;g_shot_barrel_fix="shift_failed";}
        }
        if (!moved) {g_shot_clear="bad_barrel";return 0;}   /* old behaviour, but counted in shot_barrel_bad */
        g_shot_barrel=b;
     }
    }
    CombatRayHit h;int t=combat_shot_trace(&b,aim,&h);
    int self=t>0 && h.ids[0]==1 && combat_char_ids_match(pc,h.ids);
    g_shot_clear=t<0?"fail":t==0?"clear":self?"self":
        (h.ids[0]==1 && intended && combat_char_ids_match(intended,h.ids))?"target":h.ids[0]==1?"char":"world";
    g_shot_clear_dist=t>0?h.distance:NAN;
    if (!moved && self && g_combat_eye_muzzle && g_combat_aim_have_ray && readable(gpos,sizeof(Vec3))) {
        float o[3]={g_combat_aim_origin.x,g_combat_aim_origin.y,g_combat_aim_origin.z};
        float cd[3]={g_combat_aim_dir.x,g_combat_aim_dir.y,g_combat_aim_dir.z},m[3];
        kfp_shot_eye_muzzle(o,cd,KFP_SHOT_EYE_AHEAD,m);
        Vec3 mv={m[0],m[1],m[2]};CombatRayHit h2;int t2=combat_shot_trace(&mv,aim,&h2);
        if (t2>=0 && !(t2>0 && h2.ids[0]==1 && combat_char_ids_match(pc,h2.ids))) {
            float p[3]={gpos->x,gpos->y,gpos->z},bf[3]={b.x,b.y,b.z},np[3];
            kfp_shot_muzzle_shift(p,bf,m,np);
            *saved=*gpos;gpos->x=np[0];gpos->y=np[1];gpos->z=np[2];moved=1;++g_shot_muzzle_moves;
            g_shot_clear="self_eye";
            if (!combat_gun_barrel(gun,&g_shot_barrel)) g_shot_barrel=mv;
        } else g_shot_clear="self_eye_blocked";
    }
    /* Exactly the pre-spread direction GunClass::shoot will use: getAimDir(aimpos). */
    void *fn=combat_virtual(gun,0x60);
    if (fn) {Vec3 tmp;Vec3 *r=((combat_gun_aimdir_t)fn)(gun,&tmp,aim);if (r) g_shot_dir=*r;}
    if (g_shot_dir.x||g_shot_dir.y||g_shot_dir.z) {
        g_wound_next_dir[0]=g_shot_dir.x;g_wound_next_dir[1]=g_shot_dir.y;g_wound_next_dir[2]=g_shot_dir.z;
    }
    if (g_combat_aim_have_ray) {
        float sd[3]={g_shot_dir.x,g_shot_dir.y,g_shot_dir.z};
        float ea[3]={aim->x-g_combat_aim_origin.x,aim->y-g_combat_aim_origin.y,aim->z-g_combat_aim_origin.z};
        g_shot_angle=kfp_shot_angle_deg(sd,ea);
    }
    return moved;
}
static size_t combat_shot_state(char *b,size_t n) {
    int w0=snprintf(b,n," shot_spawns=%u spawn_any=%u shot_nospawn=%u shot_mat=%d gun_mat=%d gun_creates=%u gun_repairs=%u gun_matless=%u matname=%d",
        g_wound_spawn_dispatch,g_wound_spawn_any,g_shot_nospawn,g_shot_mat,
        g_combat_gun?combat_gun_has_material(g_combat_gun):-1,g_combat_gun_creates,g_combat_gun_repairs,g_combat_gun_matless,g_combat_matname!=NULL);
    if (w0<0) w0=0;
    if ((size_t)w0>=n) return n?n-1:0;
    b+=w0;n-=(size_t)w0;
    int w=snprintf(b,n," shot_n=%u shot_intended=%d shot_phys_point=%d shot_clear=%s shot_clear_dist=%.2f shot_muzzle=%d shot_muzzle_moves=%u"
        " shot_aim=%.2f,%.2f,%.2f shot_barrel0=%.2f,%.2f,%.2f shot_barrel=%.2f,%.2f,%.2f shot_dir=%.4f,%.4f,%.4f shot_angle=%.3f aim_attr_kept=%u aim_attr_dropped=%u",
        g_shot_count,g_shot_intended,g_shot_phys_point,g_shot_clear,g_shot_clear_dist,g_combat_eye_muzzle,g_shot_muzzle_moves,
        g_shot_aim.x,g_shot_aim.y,g_shot_aim.z,g_shot_barrel0.x,g_shot_barrel0.y,g_shot_barrel0.z,
        g_shot_barrel.x,g_shot_barrel.y,g_shot_barrel.z,g_shot_dir.x,g_shot_dir.y,g_shot_dir.z,g_shot_angle,
        g_combat_aim_attr_kept,g_combat_aim_attr_dropped);
    if (w<0) w=0;
    if ((size_t)w>=n) return (size_t)w0+(n?n-1:0);
    b+=w;n-=(size_t)w;
    int w2=snprintf(b,n," shot_barrel_bad=%u shot_barrel_fixes=%u shot_barrel_fix=%s shot_barrel_why=%d shot_barrel_raw_dist=%.2f shot_gunpos0=%.2f,%.2f,%.2f",
        g_shot_barrel_bad,g_shot_barrel_fixes,g_shot_barrel_fix,g_shot_barrel_why,g_shot_barrel_raw_dist,
        g_shot_gunpos0.x,g_shot_gunpos0.y,g_shot_gunpos0.z);
    return (size_t)w0+(size_t)w+(w2<0?0:(size_t)w2<n?(size_t)w2:n-1);
}
static int combat_gun_create(void *pc,void *gun) {
    void *an=*(void **)((uintptr_t)pc+CHAR_ANIM);
    void *entity=an?combat_cached_body_entity(an):NULL;
    void *parent=entity&&g_get_parent_scenenode?g_get_parent_scenenode(entity):NULL;
    void *create=combat_virtual(gun,0x18);
    if (!parent || !create || !g_combat_matname) return 0;
    /* std::string filled by the game (a long name stays on the game heap: one small
     * leak per (re)create, only on draw/repair). */
    unsigned char material[32];make_mstr(material,"");
    g_combat_matname(material,entity);
    ++g_combat_gun_creates;
    return ((char (*)(void *,void *,void *))create)(gun,parent,material)!=0;
}
static int combat_weapon_pose(void *pc,void *gun,const Vec3 *aim) {
    void *fn=combat_virtual(gun,0x10),*vis=combat_virtual(gun,0x08);
    if (!fn || !vis || !readable(gun,0x121)) return 0;
    if (*(unsigned char *)((uintptr_t)gun+0x60) && !combat_gun_has_material(gun)) {
        /* Physical made without a material (older build or another path): bolts would
         * never spawn. Rebuild it the native way (destroyPhysical vt+0x20 clears +0x60). */
        void *destroy=combat_virtual(gun,0x20);
        if (destroy && g_combat_matname) {((void (*)(void *))destroy)(gun);++g_combat_gun_repairs;}
    }
    if (!*(unsigned char *)((uintptr_t)gun+0x60)) {
        if (!combat_gun_create(pc,gun)) return 0;
    }
    if (!combat_gun_has_material(gun)) ++g_combat_gun_matless;
    /* loadingEntitiesLeft is an async asset counter; never force it to zero. */
    ((void (*)(void *,char))vis)(gun,1);
    ((void (*)(void *,const Vec3 *))fn)(gun,aim);
    return 1;
}
/* Why the adapter holds no actor (fp_combat state why=): first failed gate this frame. */
static const char *g_combat_why="init";
static unsigned g_combat_draws; /* weapon draws started by a manual raise while holstered */
static unsigned g_combat_sheathes; /* wrong weapons sheathed before the crossbow draw */
static float g_combat_draw_cd;     /* real seconds until the next sheathe/draw attempt */
/* CharacterHuman::drawWeapon (vt 0x3D8) guard: while the manual-owned actor holds
 * ranged aim, the AI's close-range melee pick may not swap the crossbow out
 * (4080 fp-4080-2: crossbow drawn, AI redrew the melee weapon, endless swap).
 * Hooked lazily from the first live vtable (no static signature yet). */
typedef char (*combat_draw_weapon_t)(void *,void *,void *);
static combat_draw_weapon_t g_combat_draw_orig;
static int g_combat_draw_hook; /* 0 not tried, 1 installed, -1 failed */
static unsigned g_combat_draw_refused;
static char combat_draw_weapon_hook(void *pc,void *item,void *str) {
    if (pc && pc==g_combat_pc && g_combat_enabled && g_fp_mode && g_combat_control.aimed &&
        g_combat_weapon && item!=g_combat_weapon) {++g_combat_draw_refused;return 0;}
    return g_combat_draw_orig(pc,item,str);
}
static void combat_draw_hook_install(void *pc) {
    if (g_combat_draw_hook) return;
    unsigned char *fn=(unsigned char *)combat_virtual(pc,0x3d8);
    if (fn && readable(fn,5) && fn[0]==0xE9) fn=fn+5+*(int *)(fn+1);   /* follow an incremental-link thunk */
    g_combat_draw_hook=fn&&install_hook(fn,(void *)combat_draw_weapon_hook,(void **)&g_combat_draw_orig)?1:-1;
    logline("[combat] drawWeapon guard %s at %p",g_combat_draw_hook>0?"installed":"FAILED",(void *)fn);
}
/* Holstered diagnostics: weaponInHands, getGun's me->vt[0x3C0] weapon, rc state/combatMode. */
static void *g_combat_wih,*g_combat_cur;static int g_combat_rcstate=-1,g_combat_rcmode=-1;
/* Native side of the last rejected ranged fire edge (closeness/timer/have_aim are not in the observation). */
static float g_combat_rej_close=NAN,g_combat_rej_timer=NAN;
static int g_combat_rej_have_aim=-1,g_combat_rej_truce=-1;
static const char *g_combat_rej_why="none";
/* The fire frame's readiness inputs (set by the tick before the controller step) and, for the last
 * rejected edge, the first gate that failed in plain words (last_reject_gate) plus the ready-latch
 * detail: native flag, latch before the step, dip time so far, frame game dt, hold intact. */
static int g_combat_fr_native,g_combat_fr_latched,g_combat_fr_hold,g_combat_fr_readyfn;
static float g_combat_fr_since,g_combat_fr_dt;
static const char *g_combat_rej_gate="none";
static int g_combat_rej_native=-1,g_combat_rej_latched=-1,g_combat_rej_hold=-1;
static float g_combat_rej_since=NAN,g_combat_rej_dt=NAN;
static const char *combat_reject_gate(const KfpCombatObservation *o,int aim,float closeness,float timer,int have_aim,const char *why) {
    if (strcmp(why,"ok")) return why;                 /* holstered etc.: the tick's own reason */
    if (!aim) return "aim_not_held";
    if (!o->aim_ready) {
        if (!have_aim) return "no_aim_ray";
        if (!g_combat_fr_readyfn) return "no_ready_fn";
        if (!(isfinite(closeness) && closeness<=1.0f)) return "closeness";
        if (!g_combat_fr_hold) return "hold_broken";
        if (!g_combat_fr_native) return g_combat_fr_latched?"pose_dip_past_window":"pose_not_ready";
        return "aim_ready_other";
    }
    if (!(isfinite(timer) && timer<=0)) return "aim_timer";
    if (combat_truce_pending()) return "truce";
    if (o->reloading) return "reloading";
    if (o->ammo<=0) return "no_ammo";
    return "shot_ready_other";
}
static void combat_note_reject(unsigned before,float closeness,float timer,int have_aim,const char *why) {
    if (g_combat_control.rejected==before) return;
    g_combat_rej_close=closeness;g_combat_rej_timer=timer;g_combat_rej_have_aim=have_aim;
    g_combat_rej_truce=combat_truce_pending();g_combat_rej_why=why;
    g_combat_rej_gate=combat_reject_gate(&g_combat_control.last_reject,g_combat_control.last_reject_aim,closeness,timer,have_aim,why);
    g_combat_rej_native=g_combat_fr_native;g_combat_rej_latched=g_combat_fr_latched;g_combat_rej_hold=g_combat_fr_hold;
    g_combat_rej_since=g_combat_fr_since;g_combat_rej_dt=g_combat_fr_dt;
    logline("[combat] trigger refused: gate=%s native_ready=%d latched=%d dip_s=%.3f dt=%.3f hold=%d closeness=%.3f timer=%.3f ammo=%d",
            g_combat_rej_gate,g_combat_fr_native,g_combat_fr_latched,g_combat_fr_since,g_combat_fr_dt,g_combat_fr_hold,
            closeness,timer,g_combat_control.last_reject.ammo);
}
static void fp_manual_combat_tick(void *gw,float dt) {
    g_combat_gw=gw;
    g_combat_anim_drive=0;   /* set again below only when this tick drives the anim */
    KfpCombatInput input={0};
    if (g_combat_injection) input=g_combat_injected;
    else if (game_has_focus()) {
        input.aim=(GetAsyncKeyState(VK_RBUTTON)&0x8000)!=0;
        input.fire=(GetAsyncKeyState(VK_LBUTTON)&0x8000)!=0;
        /* R alone = FP draw/holster (kfp_controls.inc); R with RMB (aim) held = reload */
        input.reload=input.aim&&(GetAsyncKeyState(0x52)&0x8000)!=0;
    }
    fp_melee_observe_swing(gw,dt);   /* native swing timer (M04-SPEED control), any owner */
    if (!g_combat_enabled || !g_combat_native_ready || g_combat_fault || !g_fp_mode) {
        if (g_combat_rc) {
            if (setjmp(g_guard_jb)) {g_guard_armed=0;g_combat_fault=1;return;}
            guard_arm();combat_release();g_guard_armed=0;
        }
        fp_melee_release();
        g_combat_why=!g_combat_enabled?"off":!g_combat_native_ready?"native_unready":g_combat_fault?"fault":"fp_off";
        memset(&g_combat_observed,0,sizeof(g_combat_observed));return;
    }
    combat_prepare_body_entity(); /* owns its guard; must precede our setjmp */
    void *saved_perch_node=g_mr_perch_node;
    mr_cache_t *saved_perch_cache=g_mr_perch_cache;
    if (setjmp(g_guard_jb)) {
        g_mr_perch_node=saved_perch_node;g_mr_perch_cache=saved_perch_cache;
        g_guard_armed=0;g_combat_fault=1;g_combat_dispatch=0;g_combat_dispatch_tid=0;g_aim_mode=0;
        g_combat_pc=NULL;g_combat_rc=NULL;g_combat_gun=NULL;
        logline("[combat] native call fault; manual ownership disabled");return;
    }
    guard_arm();
    void *pc=fp_controlled_char(gw);
    g_combat_state_pc=pc;
    void *rc=char_valid(pc)&&readable((void *)((uintptr_t)pc+CHAR_RANGEDCOMBAT),8)?
        *(void **)((uintptr_t)pc+CHAR_RANGEDCOMBAT):NULL;
    void *ranged=combat_virtual(pc,0x3d0);
    void *weapon=ranged?((void *(*)(void *))ranged)(pc):NULL;
    if (char_valid(pc) && !weapon) {
        /* No ranged weapon: the melee adapter owns this actor's native swings. */
        combat_release();memset(&g_combat_observed,0,sizeof(g_combat_observed));
        g_combat_why="melee";fp_melee_manual_tick(gw,pc,input.aim,input.fire,dt);
        g_guard_armed=0;return;
    }
    fp_melee_release();
    if (!char_valid(pc) || !readable(rc,0x88) || *(void **)((uintptr_t)rc+RC_ME)!=pc || !weapon) {
        g_combat_why=!char_valid(pc)?"no_actor":!readable(rc,0x88)?"no_ranged_combat":
            *(void **)((uintptr_t)rc+RC_ME)!=pc?"ranged_owner":"no_ranged_weapon";
        combat_release();memset(&g_combat_observed,0,sizeof(g_combat_observed));g_guard_armed=0;return;
    }
    if (g_combat_pc!=pc || g_combat_rc!=rc || g_combat_weapon!=weapon ||
        !readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20) ||
        memcmp(g_combat_actor_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20)) {
        combat_release();
        if (!readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20)) {g_guard_armed=0;return;}
        g_combat_pc=pc;g_combat_rc=rc;g_combat_weapon=weapon;
        memcpy(g_combat_actor_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20);
    }
    void *gun=((void *(*)(void *))(g_base+RVA_RC_GETGUN))(rc);
    {void *cur=combat_virtual(pc,0x3c0);g_combat_cur=cur?((void *(*)(void *))cur)(pc):NULL;}
    g_combat_wih=readable((void *)((uintptr_t)pc+CHAR_WEAPON_IN_HANDS),8)?*(void **)((uintptr_t)pc+CHAR_WEAPON_IN_HANDS):NULL;
    g_combat_rcstate=*(int *)((uintptr_t)rc+RC_STATE_OFF);g_combat_rcmode=*(unsigned char *)((uintptr_t)rc+RC_COMBATMODE);
    int holstered=!readable(gun,0x121);
    if (!holstered && g_combat_gun && g_combat_gun!=gun) {
        g_combat_why="gun_changed";combat_release();memset(&g_combat_observed,0,sizeof(g_combat_observed));g_guard_armed=0;return;
    }
    if (!holstered) {g_combat_gun=gun;*(void **)((uintptr_t)rc+RC_GUN)=gun;}
    float speed=readable((void *)((uintptr_t)gw+GW_FRAMESPEED),4)?
        *(float *)((uintptr_t)gw+GW_FRAMESPEED):0;
    KfpCombatObservation o={0};o.actor=(uint64_t)(uintptr_t)pc;o.weapon=(uint64_t)(uintptr_t)weapon;
    o.enabled=1;o.allowed=!g_ui_open&&!g_is_down&&!combat_char_unconscious(pc)&&!char_prone_state(pc)&&(g_combat_injection||game_has_focus());
    if (!g_combat_injection && o.allowed) {
        void *gui=g_combat_gui_instance?g_combat_gui_instance():NULL;
        int modifier=(GetAsyncKeyState(VK_MENU)|GetAsyncKeyState(VK_CONTROL)|GetAsyncKeyState(VK_SHIFT))&0x8000;
        o.allowed=gui && g_combat_gui_focus && !g_combat_gui_focus(gui) && !modifier;
    }
    o.running=isfinite(speed)&&speed>0&&isfinite(dt)&&dt>0;o.dt=dt*speed;o.kind=KFP_WEAPON_RANGED;
    /* Yield the real native task on focus/UI/KO interruption. Leaving owned
     * update hooks suppressed would otherwise strand an unfinished reload. */
    if (!o.allowed) {
        g_combat_why=g_ui_open?"ui_open":(g_is_down||combat_char_unconscious(pc))?"down":char_prone_state(pc)?"prone":"no_focus";combat_release();g_combat_observed=o;g_guard_armed=0;return;
    }
    if (holstered) {
        /* Outside native ranged combat the crossbow is holstered and getGun is
         * empty until the crossbow itself is in hands. The controller still arms;
         * while aimed: a different weapon in hands (the AI's melee pick at close
         * range) is sheathed through the unhooked call (the aim-mode sheathe
         * suppressor would swallow it and the draw then keeps the melee weapon),
         * then the crossbow is drawn the game's way; retries on a cooldown.
         * Native ranged-combat mode is held meanwhile. No shot/reload while holstered. */
        unsigned rej0=g_combat_control.rejected;
        unsigned action=kfp_combat_step(&g_combat_control,&o,input,0,0);
        g_combat_why="holstered";combat_note_reject(rej0,NAN,NAN,-1,"holstered");
        if (g_combat_draw_cd>0) g_combat_draw_cd-=dt;
        if (g_combat_control.aimed || (action&KFP_ACT_RAISE)) {
            combat_draw_hook_install(pc);
            *(unsigned char *)((uintptr_t)rc+RC_COMBATMODE)=1;*(int *)((uintptr_t)rc+RC_STATE_OFF)=3;
            if (g_combat_wih && g_combat_wih!=weapon) {
                g_combat_why="wrong_weapon";
                if (g_combat_draw_cd<=0 && g_sheathe_orig) {g_sheathe_orig(pc);++g_combat_sheathes;g_combat_draw_cd=0.5f;}
            } else if (g_combat_wih) {
                g_combat_why="drawn_no_gun";
            } else if (g_combat_draw_cd<=0) {
                unsigned char str[32];make_mstr(str,"");
                void *draw=combat_virtual(pc,0x3d8);
                int keep=g_aim_mode;g_aim_mode=0;   /* the draw may sheathe internally */
                char ok=draw?((char (*)(void *,void *,void *))draw)(pc,weapon,str):0;
                g_aim_mode=keep;
                if (ok) {
                    g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
                    ++g_combat_draws;g_aim_mode=1;g_combat_why="drawing";g_combat_draw_cd=1.0f;
                } else {g_combat_control.aimed=0;g_combat_why="draw_failed";}
            } else g_combat_why="drawing";
        }
        g_combat_observed=o;g_guard_armed=0;return;
    }
    g_combat_why="ok";
    o.ammo=*(int *)((uintptr_t)gun+GUN_AMMO);o.reloading=*(unsigned char *)((uintptr_t)rc+0x80);
    Vec3 aim;int have_aim=combat_camera_aim(&aim);
    g_combat_anim_drive=0;
    if (o.allowed && o.running && have_aim && (g_combat_control.aimed||o.reloading)) {
        if (combat_weapon_pose(pc,gun,&aim)) {
            g_combat_anim_drive=1;
            *(Vec3 *)((uintptr_t)rc+RC_AIMPOS)=aim;
            int before=o.reloading;
            /* Native timer/ammo/XP path exactly once per owned game frame. */
            if (o.reloading || (g_cfg_combat_auto_reload && input.aim && o.ammo==0))
                g_combat_reload(rc);
            if (!before && *(unsigned char *)((uintptr_t)rc+0x80)) {++g_combat_reload_starts;g_combat_last_reload_timer=*(float *)((uintptr_t)rc+0x78);}
            o.reloading=*(unsigned char *)((uintptr_t)rc+0x80);o.ammo=*(int *)((uintptr_t)gun+GUN_AMMO);
            {unsigned char *vis=(unsigned char *)((uintptr_t)pc+CHAR_ONSCREEN),vis0=*vis;
             if (!vis0) {*vis=1;++g_combat_vis_forced;}
             g_ranged_animupd_orig(rc,o.dt,&aim,(input.aim||o.reloading)?pc:NULL);
             *vis=vis0;}
            fp_combat_probe_animation(rc,(input.aim||o.reloading)?pc:NULL);
            float *timer=(float *)((uintptr_t)rc+0x70);
            if (input.aim && !o.reloading && isfinite(*timer) && *timer>0) {
                *timer-=o.dt;if (*timer<0)*timer=0;
            }
        }
    }
    void *ready=combat_virtual(gun,0x38),*close=combat_virtual(gun,0x68);
    float closeness=close?((float (*)(void *))close)(gun):NAN;
    float timer=*(float *)((uintptr_t)rc+0x70);
    g_combat_ready_native=ready?((char (*)(void *))ready)(gun)!=0:0;
    {   /* R12-SWAP: bridge one-frame dips of the native aimH-weight flag while the hold is intact */
        int hold_ok=have_aim && input.aim && g_combat_control.aimed && o.allowed && !o.reloading && o.ammo>0 &&
                    !combat_truce_pending();
        uint64_t ident=((uint64_t)(uintptr_t)pc*31u)^(uint64_t)(uintptr_t)gun^((uint64_t)(uintptr_t)weapon<<1);
        g_combat_fr_native=g_combat_ready_native;g_combat_fr_latched=g_combat_ready_latch.latched;
        g_combat_fr_since=g_combat_ready_latch.since;g_combat_fr_dt=o.dt;g_combat_fr_hold=hold_ok;g_combat_fr_readyfn=ready!=NULL;
        int r=kfp_ready_latch_step(&g_combat_ready_latch,g_combat_ready_native,hold_ok,ident,
                                   isfinite(o.dt)&&o.dt>=0?o.dt:-1.0f,KFP_READY_BRIDGE_S);
        o.aim_ready=have_aim && ready && r && isfinite(closeness) && closeness<=1.0f;
    }
    /* Reported readiness = what the controller fires on (it also needs ammo and no reload): a shot_ready=1
     * during reload sent test triggers into a refused window (4080 batch 3 R13). */
    o.shot_ready=o.aim_ready && isfinite(timer)&&timer<=0 && !combat_truce_pending() && o.ammo>0 && !o.reloading;
    o.reload_allowed=have_aim;o.committed=o.reloading;
    unsigned rej0=g_combat_control.rejected;
    unsigned action=kfp_combat_step(&g_combat_control,&o,input,g_cfg_combat_auto_reload,0);
    combat_note_reject(rej0,closeness,timer,have_aim,"ok");
    g_combat_observed=o;
    if (action&KFP_ACT_RAISE) {
        unsigned char str[32];make_mstr(str,"");
        void *draw=combat_virtual(pc,0x3d8);
        if (draw && ((char (*)(void *,void *,void *))draw)(pc,weapon,str)) {
            g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
            *(void **)((uintptr_t)rc+RC_GUN)=gun;
            g_aim_mode=1;
        } else {g_combat_control.aimed=0;}
    }
    /* A release during reload clears controller aim before native reload ends.
     * Reconcile the owned pose afterward even without a second LOWER edge. */
    if (g_aim_mode && !g_combat_control.aimed && !o.reloading) {
        g_combat_end_orig(rc);g_aim_mode=0;
    }
    if ((action&KFP_ACT_RELOAD) && !*(unsigned char *)((uintptr_t)rc+0x80)) {
        int before=*(unsigned char *)((uintptr_t)rc+0x80);
        g_combat_reload(rc);
        if (!before && *(unsigned char *)((uintptr_t)rc+0x80)) {++g_combat_reload_starts;g_combat_last_reload_timer=*(float *)((uintptr_t)rc+0x78);}
    }
    if ((action&KFP_ACT_SHOOT) && have_aim) {
        int before=*(int *)((uintptr_t)gun+GUN_AMMO);
        int stat=*(int *)((uintptr_t)rc+RC_STAT);
        void *intended=combat_ray_target(&g_combat_camera_hit,pc);
        /* With an intended target aim at its physics surface point: the bolt collides with
         * physics shapes only, the visual mesh point can sit outside them at the silhouette. */
        Vec3 shot_aim=aim;g_shot_phys_point=0;
        if (intended && g_combat_camera_hit.shape) {shot_aim=g_combat_camera_hit.position;g_shot_phys_point=1;}
        Vec3 saved_pos;int moved=combat_shot_prepare(gun,pc,intended,&shot_aim,&saved_pos);
        g_shot_mat=combat_gun_has_material(gun);unsigned spawns0=g_wound_spawn_dispatch;
        g_combat_dispatch_tid=GetCurrentThreadId();g_combat_dispatch=1;
        hooked_gun_shoot(gun,pc,intended,stat,&shot_aim);
        g_combat_dispatch=0;g_combat_dispatch_tid=0;
        if (moved) *(Vec3 *)((uintptr_t)gun+KFP_GUN_POSITION)=saved_pos;
        if (g_wound_spawn_dispatch==spawns0 && *(int *)((uintptr_t)gun+GUN_AMMO)==before-1) ++g_shot_nospawn;
        int after=*(int *)((uintptr_t)gun+GUN_AMMO);
        if (before>0&&after==before-1)++g_combat_actual_shots;
        kfp_ready_latch_reset(&g_combat_ready_latch);   /* a shot ends the hold's readiness */
        g_combat_reset_timer(rc); /* native minimum aim-cycle reset */
    }
    g_guard_armed=0;
}

static int kah_fp_combat(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id;(void)u;
    if (argc>=2 && !_stricmp(argv[1],"wound")) return kah_fp_combat_wound(argc,argv,r);
    if (argc==2 && !_stricmp(argv[1],"aim")) {
        if (g_guard_armed) {r->append(r,"aim query busy");return KAH_ERROR;}
        void *saved_node=g_mr_perch_node;mr_cache_t *saved_cache=g_mr_perch_cache;
        if (setjmp(g_guard_jb)) {
            g_mr_perch_node=saved_node;g_mr_perch_cache=saved_cache;
            g_guard_armed=0;r->append(r,"aim query fault");return KAH_ERROR;
        }
        guard_arm();Vec3 aim;
        int valid=combat_camera_aim(&aim);
        /* R08: bone heights (dm above the feet) of the character under the crosshair */
        float bh[KFP_WH_COUNT];void *victim=NULL;
        for(int i=0;i<KFP_WH_COUNT;++i) bh[i]=NAN;
        if (valid && g_combat_camera_hit.shape) victim=combat_ray_target(&g_combat_camera_hit,g_fp_control_actor);
        if (victim) wound_victim_heights(victim,bh);
        /* World points of the victim's key bones: lets a test aim at a fallen/crawling
         * body (R11-LIMB after the leg sever), where heights above the feet mean nothing. */
        float bw[KFP_WB_COUNT][3];int have_bw=0,prone=-1;
        for(int i=0;i<KFP_WB_COUNT;++i) bw[i][0]=bw[i][1]=bw[i][2]=NAN;
        if (victim && char_valid(victim)) {Vec3 ft;
            if (char_position(victim,&ft)) {wound_read_bones(victim,&ft,bw);have_bw=1;}
            prone=char_prone_state(victim);}
        g_guard_armed=0;
        if (!valid) {r->append(r,"aim query unavailable");return KAH_ERROR;}
        char b[2048];
        snprintf(b,sizeof(b),"x=%.6f y=%.6f z=%.6f physical=%u distance=%.6f shape=%llx group=%u id0=%u id1=%u id2=%u id3=%u id4=%u",
          aim.x,aim.y,aim.z,!!g_combat_camera_hit.shape,g_combat_camera_hit.distance,
          (unsigned long long)g_combat_camera_hit.shape,g_combat_camera_hit.group,
          g_combat_camera_hit.ids[0],g_combat_camera_hit.ids[1],g_combat_camera_hit.ids[2],
          g_combat_camera_hit.ids[3],g_combat_camera_hit.ids[4]);
        {size_t l=strlen(b);snprintf(b+l,sizeof(b)-l," victim=%llx ",(unsigned long long)(uintptr_t)victim);
         l=strlen(b);kfp_wound_heights_str(bh,"",b+l,sizeof(b)-l);}
        if (have_bw) {
            static const struct {int b;const char *n;} pts[]={{KFP_WB_HEAD,"head"},{KFP_WB_NECK,"neck"},{KFP_WB_PELVIS,"pelvis"},
                {KFP_WB_L_THIGH,"lthigh"},{KFP_WB_L_CALF,"lcalf"},{KFP_WB_L_FOOT,"lfoot"},
                {KFP_WB_R_THIGH,"rthigh"},{KFP_WB_R_CALF,"rcalf"}};
            size_t l=strlen(b);snprintf(b+l,sizeof(b)-l," prone=%d",prone);
            for(size_t i=0;i<sizeof(pts)/sizeof(pts[0]);++i) {
                l=strlen(b);const float *q=bw[pts[i].b];
                snprintf(b+l,sizeof(b)-l," bw_%s=%.2f,%.2f,%.2f",pts[i].n,q[0],q[1],q[2]);
            }
            /* R08: the part the spatial wound would pick for a bolt along the camera ray at
             * the crosshair contact (pick=, pick_core_s=, pick_seg=, pick_bw_* incl. arms), so
             * a test can tell "crosshair on the head" from "on an arm raised beside it". */
            KfpWoundPick k={KFP_WG_NONE,NAN,NAN,KFP_WG_NONE,NAN,-1};
            float hp[3]={g_combat_camera_hit.position.x,g_combat_camera_hit.position.y,g_combat_camera_hit.position.z};
            float hd[3]={g_combat_aim_dir.x,g_combat_aim_dir.y,g_combat_aim_dir.z};
            int ok=kfp_wound_from_bones(hp,(const float (*)[3])bw,g_combat_aim_have_ray?hd:NULL,&k);
            l=strlen(b);snprintf(b+l,sizeof(b)-l," pick=%s",ok?kfp_wound_group_name(k.group):"none");
            l=strlen(b);kfp_wound_pick_str(&k,(const float (*)[3])bw,"pick_",b+l,sizeof(b)-l);
        }
        r->append(r,b);return KAH_OK;
    }
    /* Test hook (read-only): native physics ray from an arbitrary world point, same trace as aim.
     * Measures the vertical frame of the eye anchor against `where` and body shapes (R08/R10). */
    if (argc==7 && !_stricmp(argv[1],"ray")) {
        float v[5];
        for(int i=0;i<5;++i) {char *e;v[i]=strtof(argv[2+i],&e);if(e==argv[2+i]||*e||!isfinite(v[i])){r->append(r,"usage: fp_combat ray <x> <y> <z> <yaw> <pitch>");return KAH_ERROR;}}
        if (g_guard_armed) {r->append(r,"ray query busy");return KAH_ERROR;}
        if (setjmp(g_guard_jb)) {g_guard_armed=0;r->append(r,"ray query fault");return KAH_ERROR;}
        guard_arm();
        Vec3 o={v[0],v[1],v[2]},d={sinf(v[3])*cosf(v[4]),-sinf(v[4]),cosf(v[3])*cosf(v[4])};
        CombatRayHit h={0};int t=combat_trace_ray(&o,&d,KFP_AIM_RANGE,&h);
        g_guard_armed=0;
        if (t<0) {r->append(r,"ray query unavailable");return KAH_ERROR;}
        char b[320];
        snprintf(b,sizeof(b),"hit=%d x=%.4f y=%.4f z=%.4f distance=%.4f shape=%llx group=%u id0=%u id1=%u id2=%u id3=%u id4=%u",
          t,h.position.x,h.position.y,h.position.z,h.distance,(unsigned long long)h.shape,h.group,
          h.ids[0],h.ids[1],h.ids[2],h.ids[3],h.ids[4]);
        r->append(r,b);return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"off")) {
        g_combat_enabled=0;g_combat_injection=0;r->append(r,"manual ownership release requested");return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"on")) {
        if (!g_combat_native_ready || g_combat_fault) {r->append(r,"native bindings/hooks unavailable or faulted");return KAH_ERROR;}
        g_combat_enabled=1;r->append(r,"manual ownership requested; release all combat buttons to arm");return KAH_OK;
    }
    if (argc==3 && !_stricmp(argv[1],"autoreload")) {
        if (strcmp(argv[2],"0")&&strcmp(argv[2],"1")) {r->append(r,"autoreload must be 0 or 1");return KAH_ERROR;}
        g_cfg_combat_auto_reload=atoi(argv[2]);
        r->append(r,g_cfg_combat_auto_reload?"auto_reload=1":"auto_reload=0");return KAH_OK;
    }
    if (argc==3 && !_stricmp(argv[1],"muzzle")) {
        if (strcmp(argv[2],"0")&&strcmp(argv[2],"1")) {r->append(r,"muzzle must be 0 or 1");return KAH_ERROR;}
        g_combat_eye_muzzle=atoi(argv[2]);
        r->append(r,g_combat_eye_muzzle?"eye_muzzle=1":"eye_muzzle=0");return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"physical")) {
        g_combat_injection=0;r->append(r,"physical combat input restored");return KAH_OK;
    }
    if (argc==5 && !_stricmp(argv[1],"input")) {
        for(int i=2;i<5;++i) if(strcmp(argv[i],"0")&&strcmp(argv[i],"1")) {
            r->append(r,"input values must be 0 or 1");return KAH_ERROR;
        }
        g_combat_injected.aim=atoi(argv[2]);g_combat_injected.fire=atoi(argv[3]);g_combat_injected.reload=atoi(argv[4]);
        ++g_combat_inj_cmds;if (g_combat_injected.aim) ++g_combat_inj_aim_cmds;
        g_combat_injection=1;r->append(r,"combat input published; same controller/native gates as physical input");return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"state")) {
        char b[4096];
        snprintf(b,sizeof(b),"enabled=%d native_ready=%d fault=%d armed=%d kind=%d actor=%llx weapon=%llx gun=%llx aimed=%d anim_ready=%d shot_ready=%d ammo=%d reloading=%d reload_left=%.4f aim_left=%.4f actual_shots=%u suppressed=%u anim_suppressed=%u vis_forced=%u reload_starts=%u last_reload_timer=%.4f draws=%u sheathes=%u draw_refused=%u draw_hook=%d rejected=%u injected=%d auto_reload=%d why=%s wih=%llx cur=%llx rc_state=%d rc_mode=%d",
          g_combat_enabled,g_combat_native_ready,g_combat_fault,g_combat_control.armed,g_combat_observed.kind,
          (unsigned long long)(uintptr_t)g_combat_pc,(unsigned long long)(uintptr_t)g_combat_weapon,
          (unsigned long long)(uintptr_t)g_combat_gun,g_combat_control.aimed,
          g_combat_observed.aim_ready,g_combat_observed.shot_ready,g_combat_observed.ammo,g_combat_observed.reloading,
          readable(g_combat_rc,0x88)?*(float *)((uintptr_t)g_combat_rc+0x78):-1,
          readable(g_combat_rc,0x88)?*(float *)((uintptr_t)g_combat_rc+0x70):-1,
          g_combat_actual_shots,g_combat_suppressed,g_combat_anim_suppressed,g_combat_vis_forced,g_combat_reload_starts,g_combat_last_reload_timer,g_combat_draws,g_combat_sheathes,g_combat_draw_refused,g_combat_draw_hook,g_combat_control.rejected,g_combat_injection,g_cfg_combat_auto_reload,g_combat_why,
          (unsigned long long)(uintptr_t)g_combat_wih,(unsigned long long)(uintptr_t)g_combat_cur,g_combat_rcstate,g_combat_rcmode);
        {size_t l=strlen(b);fp_combat_wound_state(b+l,sizeof(b)-l);}
        {size_t l=strlen(b);combat_shot_state(b+l,sizeof(b)-l);}
        {size_t l=strlen(b);snprintf(b+l,sizeof(b)-l," fp_ui_state=%s",g_fpc_ui_state?g_fpc_ui_state:"off");}
        {size_t l=strlen(b);const KfpCombatObservation *j=&g_combat_control.last_reject;
         snprintf(b+l,sizeof(b)-l," inj_cmds=%u inj_aim_cmds=%u last_reject=%d/%d/%d/%d/%d/%.4f/%.4f last_reject_why=%s last_reject_gate=%s last_reject_native=%d last_reject_latched=%d last_reject_dip_s=%.3f last_reject_dt=%.3f last_reject_hold=%d last_reject_have_aim=%d last_reject_truce=%d last_reject_allowed=%d ready_native=%d ready_bridged=%u ready_latched=%d unconscious=%d ko_timer=%.2f",
           g_combat_inj_cmds,g_combat_inj_aim_cmds,g_combat_control.last_reject_aim,j->aim_ready,j->shot_ready,j->ammo,j->reloading,g_combat_rej_close,g_combat_rej_timer,
           g_combat_rej_why,g_combat_rej_gate,g_combat_rej_native,g_combat_rej_latched,g_combat_rej_since,g_combat_rej_dt,g_combat_rej_hold,g_combat_rej_have_aim,g_combat_rej_truce,j->allowed,
           g_combat_ready_native,g_combat_ready_latch.bridged,g_combat_ready_latch.latched,
           combat_char_unconscious(g_combat_state_pc),combat_char_ko_timer(g_combat_state_pc));}
        r->append(r,b);return KAH_OK;
    }
    r->append(r,"usage: fp_combat on|off|state|aim|ray <x> <y> <z> <yaw> <pitch>|physical|autoreload <0|1>|muzzle <0|1>|input <aim 0|1> <fire 0|1> <reload 0|1>|wound [on|off|reset]");return KAH_ERROR;
}
static uintptr_t combat_unique_signature(const char *sig) {
#ifdef KFP_RE_PLUGIN
    uintptr_t p=kfp_scan(sig,0);
    return p&&!kfp_scan(sig,1)?p:0;
#else
    (void)sig;return 0; /* standalone binding path unavailable: remain native */
#endif
}
static void fp_combat_native_init(void) {
    /* SDK export-table versions can disagree with the running executable.
       Bind only independently verified, unique native function bodies. */
    g_combat_setup=(combat_setup_t)combat_unique_signature("48 85 D2 75 09 48 8D 15 ?? ?? ?? ?? EB 04 48 83 C2 58 8B 42 08 89 41 10 8B 42 0C 89 41 14");
    g_combat_reload=(combat_reload_t)combat_unique_signature("48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 30 48 8B 41 68 8B 51 30 48 8B F9 0F 29 74 24 20 48 8B");
    g_combat_reset_timer=(combat_end_t)combat_unique_signature("C7 41 70 CD CC CC 3E C3 CC CC CC CC CC CC CC CC");
    /* MovableObject material-name helper (1.0.65 0x54A940, 1.0.68 0x54B3D0; unique in both). */
    g_combat_matname=(combat_matname_t)combat_unique_signature("48 89 6C 24 18 48 89 74 24 20 57 48 83 EC 20 33 ED 48 8B F2 48 8B F9 89 6C 24 38 48 85 D2 74 70 48 8B 02 48 8B CA 48 89 5C 24 30 48 8B 1D ?? ?? ?? ?? FF 50 20 48 8B D3 48 8B C8 E8");
    uintptr_t t=combat_unique_signature("48 89 5C 24 18 55 56 57 48 8D 6C 24 B9 48 81 EC 00 01 00 00 80 79 36 00 44 0F 29 84 24 E0 00 00 00");
    uintptr_t mt=combat_unique_signature("40 57 48 83 EC 40 80 79 36 00 48 8B F9 0F 84 ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 89 47 28 48 85 C0");
    uintptr_t end=combat_unique_signature("40 53 48 83 EC 20 33 D2 48 8B D9 C6 41 36 00 E8 ?? ?? ?? ?? 48 8B 4B 68 B2 01 48 8B 89 48 04 00 00");
    g_combat_end=(combat_end_t)end;
    int trace_ready=fp_combat_trace_init();
    int target_ready=fp_combat_target_init();
    fp_combat_wound_init(); /* R08 spatial part; independent of native_ready */
    int bindings=trace_ready&&target_ready&&g_combat_setup&&g_combat_reload&&g_combat_end&&g_combat_reset_timer&&
                 g_ranged_animupd_orig&&g_gun_shoot_orig&&RVA_RC_GETGUN;
    if (bindings && t && mt && end) {
        int a=install_hook((void *)t,(void *)combat_rc_hook,(void **)&g_combat_rc_orig);
        int b=install_hook((void *)mt,(void *)combat_mt_hook,(void **)&g_combat_mt_orig);
        int c=install_hook((void *)end,(void *)combat_end_hook,(void **)&g_combat_end_orig);
        int input=fp_combat_input_init();
        g_combat_native_ready=a&&b&&c&&input; /* partial install stays transparent */
    }
    logline("[combat] native ranged bindings=%d signatures=%p/%p/%p ready=%d; manual default OFF",
        !!bindings,(void *)t,(void *)mt,(void *)end,g_combat_native_ready);
}
