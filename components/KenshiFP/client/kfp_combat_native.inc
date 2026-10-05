/* Native ranged ownership. Feature is opt-in until coordinator acceptance.
 * setup/end/reload/reset use KenshiLib's version-aware exported bindings.
 * T/MT/end intercepts use unique executable signatures, never fixed RVAs. */
#include "kfp_combat_controller.h"
#include "kfp_aim_geometry.h"
static KfpCombatController g_combat_control;
static KfpCombatObservation g_combat_observed;
static KfpCombatInput g_combat_injected;
static int g_combat_injection, g_combat_enabled, g_combat_native_ready;
static int g_combat_fault, g_combat_dispatch, g_combat_auto_reload=1;
static DWORD g_combat_dispatch_tid;
static uint32_t g_combat_actor_ids[5];
static void *g_combat_pc, *g_combat_rc, *g_combat_weapon, *g_combat_gun;
static unsigned g_combat_actual_shots, g_combat_suppressed, g_combat_reload_starts;
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
#include "kfp_combat_input.inc"
static void combat_rc_hook(void *rc,float dt,const void *a,const void *b) {
    if (!combat_owned_rc(rc)) g_combat_rc_orig(rc,dt,a,b);
}
static void combat_mt_hook(void *rc,float dt) {
    if (!combat_owned_rc(rc)) g_combat_mt_orig(rc,dt);
}
static void combat_end_hook(void *rc) {
    if (!combat_owned_rc(rc)) g_combat_end_orig(rc);
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
/* No target/limb grant: native projectile still resolves its physical hit.
 * Camera scene position uses the established floating-origin translation.
 * Called under the owning main-loop crash guard, never nests a guard. */
static int combat_camera_aim(Vec3 *out) {
    if (!g_have_t || !g_have_eye || !g_view_have_anchor || !g_ogre_ready || !g_node_get_dpos)
        return 0;
    void *cam=readable((void *)(g_base+RVA_CAM_INSTANCE),8)?*(void **)(g_base+RVA_CAM_INSTANCE):NULL;
    void *node=readable(cam,CC_NODE+8)?*(void **)((uintptr_t)cam+CC_NODE):NULL;
    if (!readable(node,8))return 0;
    Vec3 scene;
    const Vec3 *actual=g_node_get_dpos(node,&scene);
    if (!readable((void *)actual,sizeof(scene)))return 0;
    scene=*actual;
    float scene_xyz[3]={scene.x,scene.y,scene.z},origin_xyz[3],dir_xyz[3],end_xyz[3];
    if (!kfp_aim_geometry(scene_xyz,g_tx,g_tz,g_yaw,g_pitch,80.0f,
                          origin_xyz,dir_xyz,end_xyz))return 0;
    Vec3 origin={origin_xyz[0],origin_xyz[1],origin_xyz[2]};
    Vec3 dir={dir_xyz[0],dir_xyz[1],dir_xyz[2]};
    Vec3 best={end_xyz[0],end_xyz[1],end_xyz[2]},hit;
    float nearest=80.0f;
    void *saved_node=g_mr_perch_node;mr_cache_t *saved_cache=g_mr_perch_cache;
    for(int visual=0;visual<2;++visual) {
        int got=visual?meshray_refine(&origin,&dir,80.0f,&hit):fall_ray(&origin,&dir,&hit);
        if (!got)continue;
        float distance=(hit.x-origin.x)*dir.x+(hit.y-origin.y)*dir.y+(hit.z-origin.z)*dir.z;
        if (isfinite(distance)&&distance>=0 && distance<nearest) {best=hit;nearest=distance;}
    }
    g_mr_perch_node=saved_node;g_mr_perch_cache=saved_cache;
    *out=best;return 1;
}
static int combat_truce_pending(void) {
    /* Conservative interim policy: with any active protected NPC, reject new
     * manual shots everywhere, including potential spread into that NPC.
     * Scoped first-victim truce routing replaces this only after validation. */
    for(int i=0;i<STOBE_FIGHT_TRUCE_SLOTS;++i)
        if(g_stobe_fight_truce[i].serial)return 1;
    return 0;
}
static void combat_release(void) {
    void *rc=g_combat_rc,*pc=g_combat_pc;
    g_combat_rc=NULL;g_combat_pc=NULL;g_combat_gun=NULL;g_combat_weapon=NULL;g_aim_mode=0;
    g_combat_dispatch=0;g_combat_dispatch_tid=0;
    int same_actor=char_valid(pc) && readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20) &&
        !memcmp(g_combat_actor_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20);
    memset(g_combat_actor_ids,0,sizeof(g_combat_actor_ids));
    memset(&g_combat_control,0,sizeof(g_combat_control));
    if (rc && same_actor && readable(rc,0x88) &&
        *(void **)((uintptr_t)pc+CHAR_RANGEDCOMBAT)==rc &&
        *(void **)((uintptr_t)rc+RC_ME)==pc && g_combat_end_orig) g_combat_end_orig(rc);
}
static int combat_weapon_pose(void *pc,void *gun,const Vec3 *aim) {
    void *fn=combat_virtual(gun,0x10),*vis=combat_virtual(gun,0x08);
    if (!fn || !vis || !readable(gun,0x121)) return 0;
    if (!*(unsigned char *)((uintptr_t)gun+0x60)) {
        void *an=*(void **)((uintptr_t)pc+CHAR_ANIM);
        void *entity=an?find_body_entity(an):NULL;
        void *parent=entity&&g_get_parent_scenenode?g_get_parent_scenenode(entity):NULL;
        void *create=combat_virtual(gun,0x18);
        if (!parent || !create) return 0;
        unsigned char material[32];make_mstr(material,"");
        if (!((char (*)(void *,void *,void *))create)(gun,parent,material)) return 0;
    }
    /* loadingEntitiesLeft is an async asset counter; never force it to zero. */
    ((void (*)(void *,char))vis)(gun,1);
    ((void (*)(void *,const Vec3 *))fn)(gun,aim);
    return 1;
}
static void fp_manual_combat_tick(void *gw,float dt) {
    KfpCombatInput input={0};
    if (g_combat_injection) input=g_combat_injected;
    else if (game_has_focus()) {
        input.aim=(GetAsyncKeyState(VK_RBUTTON)&0x8000)!=0;
        input.fire=(GetAsyncKeyState(VK_LBUTTON)&0x8000)!=0;
        input.reload=(GetAsyncKeyState(0x52)&0x8000)!=0;
    }
    if (!g_combat_enabled || !g_combat_native_ready || g_combat_fault || !g_fp_mode) {
        if (g_combat_rc) {
            if (setjmp(g_guard_jb)) {g_guard_armed=0;g_combat_fault=1;return;}
            guard_arm();combat_release();g_guard_armed=0;
        }
        memset(&g_combat_observed,0,sizeof(g_combat_observed));return;
    }
    if (setjmp(g_guard_jb)) {
        g_guard_armed=0;g_combat_fault=1;g_combat_dispatch=0;g_aim_mode=0;
        g_combat_pc=NULL;g_combat_rc=NULL;g_combat_gun=NULL;
        logline("[combat] native call fault; manual ownership disabled");return;
    }
    guard_arm();
    void *pc=fp_controlled_char(gw);
    void *rc=char_valid(pc)&&readable((void *)((uintptr_t)pc+CHAR_RANGEDCOMBAT),8)?
        *(void **)((uintptr_t)pc+CHAR_RANGEDCOMBAT):NULL;
    void *ranged=combat_virtual(pc,0x3d0);
    void *weapon=ranged?((void *(*)(void *))ranged)(pc):NULL;
    if (!char_valid(pc) || !readable(rc,0x88) || *(void **)((uintptr_t)rc+RC_ME)!=pc || !weapon) {
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
    if (!readable(gun,0x121)) {
        combat_release();memset(&g_combat_observed,0,sizeof(g_combat_observed));g_guard_armed=0;return;
    }
    if (g_combat_gun && g_combat_gun!=gun) {
        combat_release();memset(&g_combat_observed,0,sizeof(g_combat_observed));g_guard_armed=0;return;
    }
    g_combat_gun=gun;*(void **)((uintptr_t)rc+RC_GUN)=gun;
    float speed=readable((void *)((uintptr_t)gw+GW_FRAMESPEED),4)?
        *(float *)((uintptr_t)gw+GW_FRAMESPEED):0;
    KfpCombatObservation o={0};o.actor=(uint64_t)(uintptr_t)pc;o.weapon=(uint64_t)(uintptr_t)weapon;
    o.enabled=1;o.allowed=!g_ui_open&&!g_is_down&&!char_prone_state(pc)&&(g_combat_injection||game_has_focus());
    if (!g_combat_injection && o.allowed) {
        void *gui=g_combat_gui_instance?g_combat_gui_instance():NULL;
        int modifier=(GetAsyncKeyState(VK_MENU)|GetAsyncKeyState(VK_CONTROL)|GetAsyncKeyState(VK_SHIFT))&0x8000;
        o.allowed=gui && g_combat_gui_focus && !g_combat_gui_focus(gui) && !modifier;
    }
    o.running=isfinite(speed)&&speed>0&&isfinite(dt)&&dt>0;o.dt=dt*speed;o.kind=KFP_WEAPON_RANGED;
    /* Yield the real native task on focus/UI/KO interruption. Leaving owned
     * update hooks suppressed would otherwise strand an unfinished reload. */
    if (!o.allowed) {
        combat_release();g_combat_observed=o;g_guard_armed=0;return;
    }
    o.ammo=*(int *)((uintptr_t)gun+GUN_AMMO);o.reloading=*(unsigned char *)((uintptr_t)rc+0x80);
    Vec3 aim;int have_aim=combat_camera_aim(&aim);
    if (o.allowed && o.running && have_aim && (g_combat_control.aimed||o.reloading)) {
        if (combat_weapon_pose(pc,gun,&aim)) {
            *(Vec3 *)((uintptr_t)rc+RC_AIMPOS)=aim;
            int before=o.reloading;
            /* Native timer/ammo/XP path exactly once per owned game frame. */
            if (o.reloading || (g_combat_auto_reload && input.aim && o.ammo==0))
                g_combat_reload(rc);
            if (!before && *(unsigned char *)((uintptr_t)rc+0x80)) ++g_combat_reload_starts;
            o.reloading=*(unsigned char *)((uintptr_t)rc+0x80);o.ammo=*(int *)((uintptr_t)gun+GUN_AMMO);
            g_ranged_animupd_orig(rc,o.dt,&aim,(input.aim||o.reloading)?pc:NULL);
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
    o.aim_ready=have_aim && ready && ((char (*)(void *))ready)(gun) &&
                isfinite(closeness) && closeness<=1.0f;
    o.shot_ready=o.aim_ready && isfinite(timer)&&timer<=0 && !combat_truce_pending();
    o.reload_allowed=have_aim;o.committed=o.reloading;
    unsigned action=kfp_combat_step(&g_combat_control,&o,input,g_combat_auto_reload,0);
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
        if (!before && *(unsigned char *)((uintptr_t)rc+0x80)) ++g_combat_reload_starts;
    }
    if ((action&KFP_ACT_SHOOT) && have_aim) {
        int before=*(int *)((uintptr_t)gun+GUN_AMMO);
        int stat=*(int *)((uintptr_t)rc+RC_STAT);
        g_combat_dispatch_tid=GetCurrentThreadId();g_combat_dispatch=1;
        hooked_gun_shoot(gun,pc,NULL,stat,&aim);
        g_combat_dispatch=0;g_combat_dispatch_tid=0;
        int after=*(int *)((uintptr_t)gun+GUN_AMMO);
        if (before>0&&after==before-1)++g_combat_actual_shots;
        g_combat_reset_timer(rc); /* native minimum aim-cycle reset */
    }
    g_guard_armed=0;
}

static int kah_fp_combat(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id;(void)u;
    if (argc==2 && !_stricmp(argv[1],"off")) {
        g_combat_enabled=0;g_combat_injection=0;r->append(r,"manual ownership release requested");return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"on")) {
        if (!g_combat_native_ready || g_combat_fault) {r->append(r,"native bindings/hooks unavailable or faulted");return KAH_ERROR;}
        g_combat_enabled=1;r->append(r,"manual ownership requested; release all combat buttons to arm");return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"physical")) {
        g_combat_injection=0;r->append(r,"physical combat input restored");return KAH_OK;
    }
    if (argc==5 && !_stricmp(argv[1],"input")) {
        for(int i=2;i<5;++i) if(strcmp(argv[i],"0")&&strcmp(argv[i],"1")) {
            r->append(r,"input values must be 0 or 1");return KAH_ERROR;
        }
        g_combat_injected.aim=atoi(argv[2]);g_combat_injected.fire=atoi(argv[3]);g_combat_injected.reload=atoi(argv[4]);
        g_combat_injection=1;r->append(r,"combat input published; same controller/native gates as physical input");return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"state")) {
        char b[512];
        snprintf(b,sizeof(b),"enabled=%d native_ready=%d fault=%d armed=%d kind=%d actor=%llx weapon=%llx gun=%llx aimed=%d anim_ready=%d shot_ready=%d ammo=%d reloading=%d reload_left=%.4f aim_left=%.4f actual_shots=%u suppressed=%u reload_starts=%u rejected=%u injected=%d",
          g_combat_enabled,g_combat_native_ready,g_combat_fault,g_combat_control.armed,g_combat_observed.kind,
          (unsigned long long)(uintptr_t)g_combat_pc,(unsigned long long)(uintptr_t)g_combat_weapon,
          (unsigned long long)(uintptr_t)g_combat_gun,g_combat_control.aimed,
          g_combat_observed.aim_ready,g_combat_observed.shot_ready,g_combat_observed.ammo,g_combat_observed.reloading,
          readable(g_combat_rc,0x88)?*(float *)((uintptr_t)g_combat_rc+0x78):-1,
          readable(g_combat_rc,0x88)?*(float *)((uintptr_t)g_combat_rc+0x70):-1,
          g_combat_actual_shots,g_combat_suppressed,g_combat_reload_starts,g_combat_control.rejected,g_combat_injection);
        r->append(r,b);return KAH_OK;
    }
    r->append(r,"usage: fp_combat on|off|state|physical|input <aim 0|1> <fire 0|1> <reload 0|1>");return KAH_ERROR;
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
    uintptr_t t=combat_unique_signature("48 89 5C 24 18 55 56 57 48 8D 6C 24 B9 48 81 EC 00 01 00 00 80 79 36 00 44 0F 29 84 24 E0 00 00 00");
    uintptr_t mt=combat_unique_signature("40 57 48 83 EC 40 80 79 36 00 48 8B F9 0F 84 ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 89 47 28 48 85 C0");
    uintptr_t end=combat_unique_signature("40 53 48 83 EC 20 33 D2 48 8B D9 C6 41 36 00 E8 ?? ?? ?? ?? 48 8B 4B 68 B2 01 48 8B 89 48 04 00 00");
    g_combat_end=(combat_end_t)end;
    int bindings=g_combat_setup&&g_combat_reload&&g_combat_end&&g_combat_reset_timer&&
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
