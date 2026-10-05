/* Native ranged ownership. Feature is opt-in until coordinator acceptance.
 * setup/end/reload/reset use KenshiLib's version-aware exported bindings.
 * T/MT/end intercepts use unique executable signatures, never fixed RVAs. */
#include "kfp_combat_controller.h"
static KfpCombatController g_combat_control;
static KfpCombatObservation g_combat_observed;
static KfpCombatInput g_combat_injected;
static int g_combat_injection, g_combat_enabled, g_combat_native_ready;
static int g_combat_fault, g_combat_dispatch, g_combat_auto_reload=1;
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
           g_combat_pc==g_fp_control_actor;
}
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
        if (!g_combat_dispatch || gun!=g_combat_gun) {++g_combat_suppressed;return 1;}
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
static void combat_release(void) {
    void *rc=g_combat_rc,*pc=g_combat_pc;
    g_combat_rc=NULL;g_combat_pc=NULL;g_combat_gun=NULL;g_combat_weapon=NULL;g_aim_mode=0;
    g_combat_dispatch=0;memset(&g_combat_control,0,sizeof(g_combat_control));
    if (rc && char_valid(pc) && readable(rc,0x88) &&
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
    if (g_combat_pc!=pc || g_combat_rc!=rc || g_combat_weapon!=weapon) {
        combat_release();g_combat_pc=pc;g_combat_rc=rc;g_combat_weapon=weapon;
    }
    void *gun=((void *(*)(void *))(g_base+RVA_RC_GETGUN))(rc);
    if (!readable(gun,0x121)) {g_guard_armed=0;return;}
    g_combat_gun=gun;*(void **)((uintptr_t)rc+RC_GUN)=gun;
    float speed=readable((void *)((uintptr_t)gw+GW_FRAMESPEED),4)?
        *(float *)((uintptr_t)gw+GW_FRAMESPEED):0;
    KfpCombatObservation o={0};o.actor=(uint64_t)(uintptr_t)pc;o.weapon=(uint64_t)(uintptr_t)weapon;
    o.enabled=1;o.allowed=!g_ui_open&&!g_is_down&&!char_prone_state(pc)&&(g_combat_injection||game_has_focus());
    o.running=isfinite(speed)&&speed>0&&isfinite(dt)&&dt>0;o.dt=dt*speed;o.kind=KFP_WEAPON_RANGED;
    o.ammo=*(int *)((uintptr_t)gun+GUN_AMMO);o.reloading=*(unsigned char *)((uintptr_t)rc+0x80);
    Vec3 aim;int have_aim=fp_aim_point(&aim);
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
    o.shot_ready=o.aim_ready && isfinite(timer)&&timer<=0;
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
    if ((action&KFP_ACT_LOWER) && !o.reloading) {
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
        g_combat_dispatch=1;hooked_gun_shoot(gun,pc,NULL,stat,&aim);g_combat_dispatch=0;
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
    HMODULE lib=GetModuleHandleA("KenshiLib.dll");
    if (!lib)return;
    g_combat_setup=(combat_setup_t)GetProcAddress(lib,"?setup@RangedCombatClass@@QEAAXPEAVTurretBuilding@@W4StatsEnumerated@@@Z");
    g_combat_reload=(combat_reload_t)GetProcAddress(lib,"?reloadCheck@RangedCombatClass@@QEAA_NXZ");
    g_combat_end=(combat_end_t)GetProcAddress(lib,"?end@RangedCombatClass@@QEAAXXZ");
    g_combat_reset_timer=(combat_end_t)GetProcAddress(lib,"?resetShotTimer@RangedCombatClass@@QEAAXXZ");
    uintptr_t t=combat_unique_signature("48 89 5C 24 18 55 56 57 48 8D 6C 24 B9 48 81 EC 00 01 00 00 80 79 36 00 44 0F 29 84 24 E0 00 00 00");
    uintptr_t mt=combat_unique_signature("40 57 48 83 EC 40 80 79 36 00 48 8B F9 0F 84 ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 89 47 28 48 85 C0");
    uintptr_t end=combat_unique_signature("40 53 48 83 EC 20 33 D2 48 8B D9 C6 41 36 00 E8 ?? ?? ?? ?? 48 8B 4B 68 B2 01 48 8B 89 48 04 00 00");
    int bindings=g_combat_setup&&g_combat_reload&&g_combat_end&&g_combat_reset_timer&&
                 g_ranged_animupd_orig&&g_gun_shoot_orig&&RVA_RC_GETGUN;
    if (bindings && t && mt && end) {
        int a=install_hook((void *)t,(void *)combat_rc_hook,(void **)&g_combat_rc_orig);
        int b=install_hook((void *)mt,(void *)combat_mt_hook,(void **)&g_combat_mt_orig);
        int c=install_hook((void *)end,(void *)combat_end_hook,(void **)&g_combat_end_orig);
        g_combat_native_ready=a&&b&&c; /* partial install stays transparent */
    }
    logline("[combat] native ranged bindings=%d signatures=%p/%p/%p ready=%d; manual default OFF",
        !!bindings,(void *)t,(void *)mt,(void *)end,g_combat_native_ready);
}
