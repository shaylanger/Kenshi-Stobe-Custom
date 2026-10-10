/* T2-T5 (Shay 2026-10-09: turrets must work in FP): the FP-controlled character manning a turret.
 * Native: the operator's RangedCombatClass is setup(turret, STAT_TURRETS) on mount, but updateT/updateMT
 * return at once while combatMode (+0x36) is 0, so out of combat nothing aims, reloads or fires the turret,
 * and in combat the AI picks its own targets. While the FP char mans a turret this module owns it:
 *   T2 aim: the camera aim point -> TurretBuilding::aimTargetPos (+0x4A8) every frame; the turret's own
 *      update turns the gun toward it at its native turn speed (aimAt() is exactly that store).
 *   T3 reload: an empty gun reloads on the native reload time (GunClass::calculateReloadTime(userSkill01)),
 *      gun reloadState (+0xE0) runs 0..1, then GunClass::reloadAmmo (ammo + harpoon/string visuals).
 *   T4 fire: an LMB press while loaded fires GunClass::shoot(gun, me, NULL, STAT_TURRETS, aim point) through
 *      the shoot hook; the AI's own updateT/updateMT and shots for this char are suppressed meanwhile.
 *   T5 R is ignored while seated (kfp_controls.inc fpc_draw_toggle); W/A/S/D leaves (native, FP movement).
 * Leaving the turret (or FP off) drops the ownership; the turret keeps its ammo. */
#define TUR_CHAR_USING   0x258   /* Character::isUsingTurret (hand) */
#define TUR_GUN          0x440   /* TurretBuilding::gunClass */
#define TUR_AIM_TARGET   0x4A8   /* TurretBuilding::aimTargetPos (aimAt() stores here) */
#define TUR_CUR_DIR      0x44C   /* TurretBuilding::currentAimDir */
#define TUR_GUN_BACK     0x128   /* GunClassTurret::turretBuilding */
#define TUR_GUN_MAX      0x1C    /* GunClass::numShotsMax */
#define TUR_GUN_RLMIN    0x24
#define TUR_GUN_RLMAX    0x28
#define TUR_GUN_SKILL    0x2C    /* GunClass::userSkill01 */
#define TUR_GUN_RLSTATE  0xE0    /* GunClass::reloadState */
#define TUR_STAT         11      /* STAT_TURRETS */

static void *g_tur_bld;
static float g_tur_rl_left=-1.0f,g_tur_rl_max;
static int g_tur_prev_fire=1,g_tur_aim_valid;
static unsigned g_tur_harp_char,g_tur_harp_world,g_tur_harp_target;static int g_tur_harp_state;static unsigned long long g_tur_harp_t;
static unsigned g_tur_enters,g_tur_leaves,g_tur_frames,g_tur_shots,g_tur_shot_refused,g_tur_reloads,g_tur_r_ignored,
                g_tur_native_suppressed,g_tur_updt_suppressed,g_tur_aim_writes;
static const char *g_tur_why="none",*g_tur_refuse_why="none";
static Vec3 g_tur_aim;
static void *g_tur_last_target;
static char g_tur_name[64];
static int g_tur_cfg_drive=0;          /* T2: call TurretBuilding::update ourselves when the game does not (fp_turret drive 0|1) */
static unsigned g_tur_drive_calls,g_tur_native_updates;
static void (*g_tur_update_real)(void *);
static int g_tur_cfg_gunaim=1;static unsigned g_tur_gunaim_calls;
static int g_tur_cfg_operate=1;       /* T2: call TurretBuilding::operate(me,dt) each frame (sets currentAimSpeed; the native caller is the AI turret job) */
static unsigned g_tur_operate_calls;

static void *fp_turret_of(void *pc) {
    static void *(*getbld)(void *);static int res;
    if (!res) {res=1;getbld=(void *(*)(void *))fpc_klib("?getBuilding@hand@@QEBAPEAVBuilding@@XZ");
               logline("[turret] hand::getBuilding %s",getbld?"bound":"MISSING (turret control off)");}
    if (!getbld || !readable((void *)((uintptr_t)pc+TUR_CHAR_USING),0x20)) return NULL;
    void *b=getbld((void *)((uintptr_t)pc+TUR_CHAR_USING));
    if (!readable(b,0x4B8)) return NULL;
    void *gun=*(void **)((uintptr_t)b+TUR_GUN);
    if (!readable(gun,0x130) || *(void **)((uintptr_t)gun+TUR_GUN_BACK)!=b) return NULL;
    return b;
}
static void fp_turret_drop(const char *why) {
    if (g_tur_pc) {++g_tur_leaves;logline("[turret] FP turret control ends (%s)",why);}
    g_tur_pc=g_tur_rc=NULL;g_tur_bld=NULL;g_tur_rl_left=-1.0f;g_tur_why=why;g_tur_aim_valid=0;
}
/* Returns 1 while the FP-controlled char mans a turret (the caller then skips the hand-weapon adapters). */
static int fp_turret_tick(void *gw,void *pc,void *rc,float dt) {
    void *b=char_valid(pc)?fp_turret_of(pc):NULL;
    if (!b) {if (g_tur_pc) fp_turret_drop("left the turret"); else g_tur_why="not_on_turret";return 0;}
    void *gun=*(void **)((uintptr_t)b+TUR_GUN);
    if (g_tur_pc!=pc || g_tur_bld!=b) {
        if (g_tur_pc) fp_turret_drop("switched");
        ++g_tur_enters;g_tur_rl_left=-1.0f;g_tur_prev_fire=1;   /* a button already down does not fire */
        fpc_name(b,g_tur_name,sizeof g_tur_name);
        logline("[turret] FP turret control starts: %s gun=%p ammo=%d/%d skill01=%.3f",g_tur_name,gun,
                *(int *)((uintptr_t)gun+GUN_AMMO),*(int *)((uintptr_t)gun+TUR_GUN_MAX),*(float *)((uintptr_t)gun+TUR_GUN_SKILL));
    }
    g_tur_pc=pc;g_tur_bld=b;g_tur_gun=gun;
    g_tur_rc=readable(rc,0x88)&&*(void **)((uintptr_t)rc+RC_ME)==pc?rc:NULL;
    g_tur_why="manning";++g_tur_frames;
    float speed=readable((void *)((uintptr_t)gw+GW_FRAMESPEED),4)?*(float *)((uintptr_t)gw+GW_FRAMESPEED):0;
    float gdt=(isfinite(speed)&&speed>0&&isfinite(dt)&&dt>0)?dt*speed:0.0f;
    /* T2 aim */
    if (!g_tur_update_real) {static int res;if (!res) {res=1;g_tur_update_real=(void (*)(void *))fpc_klib_real("?update@TurretBuilding@@UEAAXXZ");
                             logline("[turret] TurretBuilding::update %p",(void *)g_tur_update_real);}}
    Vec3 aim;g_tur_aim_valid=combat_camera_aim(&aim);
    if (g_tur_aim_valid) {
        /* GunClass::aimAt (vtable +0x28): for GunClassTurret it aims the building AND stores the gun's lastTarget
         * (+0x118), which getAimDir (used by shoot) pitches the shot toward; a bare +0x4A8 store left lastTarget
         * stale and every FP harpoon flew into the ground ~150 ms out. */
        void **vt=readable(gun,8)?*(void ***)gun:NULL;
        if (g_tur_cfg_gunaim && readable(vt,0x30)) {((void (*)(void *,const Vec3 *))vt[0x28/8])(gun,&aim);++g_tur_gunaim_calls;}
        else *(Vec3 *)((uintptr_t)b+TUR_AIM_TARGET)=aim;
        g_tur_aim=aim;++g_tur_aim_writes;}
    if (g_tur_cfg_operate && gdt>0.0f) {
        static void (*op)(void *,void *,float);static int res;
        if (!res) {res=1;op=(void (*)(void *,void *,float))fpc_klib("?operate@TurretBuilding@@UEAAXPEAVCharacter@@M@Z");
                   logline("[turret] TurretBuilding::operate %s",op?"bound":"MISSING");}
        if (op) {op(b,pc,gdt);++g_tur_operate_calls;}
    }
    if (g_tur_cfg_drive && g_tur_update_real && gdt>0.0f) {++g_tur_drive_calls;g_tur_update_real(b);}
    /* T3 reload */
    int *am=(int *)((uintptr_t)gun+GUN_AMMO);
    float *rls=(float *)((uintptr_t)gun+TUR_GUN_RLSTATE);
    if (*am<=0 && g_tur_rl_left<0.0f) {
        static float (*rltime)(void *,float);static int res;
        if (!res) {res=1;rltime=(float (*)(void *,float))fpc_klib("?calculateReloadTime@GunClass@@QEAAMM@Z");}
        float s01=*(float *)((uintptr_t)gun+TUR_GUN_SKILL),lo=*(float *)((uintptr_t)gun+TUR_GUN_RLMIN),hi=*(float *)((uintptr_t)gun+TUR_GUN_RLMAX);
        float t=rltime?rltime(gun,s01):hi+(lo-hi)*s01;
        if (!isfinite(t) || t<0.1f) t=isfinite(hi)&&hi>0.1f?hi:5.0f;
        g_tur_rl_max=g_tur_rl_left=t;*rls=0.0f;
        logline("[turret] reload starts: %.2f s (skill01 %.3f, native %s, min %.2f max %.2f)",t,s01,rltime?"calculateReloadTime":"lerp",lo,hi);
    }
    if (g_tur_rl_left>=0.0f) {
        g_tur_rl_left-=gdt;
        *rls=g_tur_rl_max>0?fminf(1.0f,fmaxf(0.0f,1.0f-g_tur_rl_left/g_tur_rl_max)):1.0f;
        if (g_tur_rl_left<=0.0f) {
            ((void (*)(void *))(g_base+RVA_GUN_RELOAD))(gun);*rls=1.0f;g_tur_rl_left=-1.0f;++g_tur_reloads;
            logline("[turret] reloaded: ammo %d/%d",*am,*(int *)((uintptr_t)gun+TUR_GUN_MAX));
        }
    }
    /* T4 evidence: follow the last shot's harpoon (state +0x70: 1 flying, 2 character hit victim +0x78, 3 world) */
    if (g_tur_harp && readable((void *)((uintptr_t)g_tur_harp+0x70),0x10)) {
        int st=*(int *)((uintptr_t)g_tur_harp+0x70);
        if (st!=g_tur_harp_state && (st==2||st==3)) {
            void *v=st==2?*(void **)((uintptr_t)g_tur_harp+0x78):NULL;
            {   void *tr=*(void **)((uintptr_t)g_tur_harp+0x68);unsigned char *ph=readable(tr,0x10)?(unsigned char *)tr+8:NULL;
                if (ph && readable(ph,0x60)) {const float *hp=(const float *)(ph+8);
                    logline("[turret] harpoon PhysHit hit=%d pos=%.1f,%.1f,%.1f group=%d",ph[7],hp[0],hp[1],hp[2],*(int *)(ph+0x50));}
                else logline("[turret] harpoon PhysHit unreadable (tracer %p)",tr);
                if (readable(g_tur_harp,0x100)) {char d[1200];int n=0;const float *f=(const float *)g_tur_harp;
                    for (int i=0;i<64 && n<(int)sizeof d-24;++i) {float x=f[i];if (isfinite(x)&&fabsf(x)>100.0f&&fabsf(x)<1e6f) n+=snprintf(d+n,sizeof d-n," %x:%.1f",i*4,x);}
                    d[n]=0;logline("[turret] harpoon dump%s",d);}
            }
            if (st==2) {++g_tur_harp_char;if (v && v==g_tur_last_target) ++g_tur_harp_target;} else ++g_tur_harp_world;
            logline("[turret] harpoon %s victim=%p (target=%p) %.0f ms after the shot",st==2?"hit a character":"hit the world",v,g_tur_last_target,
                    (double)(GetTickCount64()-g_tur_harp_t));
            g_tur_harp=NULL;
        }
        g_tur_harp_state=st;
        if (g_tur_harp && GetTickCount64()-g_tur_harp_t>5000) {logline("[turret] harpoon still state %d after 5 s",st);g_tur_harp=NULL;}
    }
    /* T4 fire */
    int fire=g_combat_injection?g_combat_injected.fire:g_tur_ui_fire;
    if (fire && !g_tur_prev_fire) {
        const char *why=*am<=0||g_tur_rl_left>=0.0f?"reloading":!g_tur_aim_valid?"no_aim":gdt<=0.0f?"paused":NULL;
        if (why) {++g_tur_shot_refused;g_tur_refuse_why=why;logline("[turret] LMB refused: %s",why);}
        else {
            int before=*am;
            /* A non-target projectile gets the flight's Precision pass-through roll (see the hand crossbow
             * path): pass the crosshair character as the target and aim at its physics surface point. */
            void *intended=combat_ray_target(&g_combat_camera_hit,pc);Vec3 shot=aim;
            if (intended && g_combat_camera_hit.shape) shot=g_combat_camera_hit.position;
            g_tur_last_target=intended;
            g_tur_harp=NULL;g_tur_harp_state=0;g_tur_harp_t=GetTickCount64();
            g_tur_dispatch=1;hooked_gun_shoot(gun,pc,intended,TUR_STAT,&shot);g_tur_dispatch=0;
            logline("[turret] shot harpoon=%p",g_tur_harp);
            if (*am==before-1) {++g_tur_shots;logline("[turret] fired at %.1f,%.1f,%.1f (ammo %d) target=%p",aim.x,aim.y,aim.z,*am,g_tur_last_target);}
            else {++g_tur_shot_refused;g_tur_refuse_why="shoot_no_effect";logline("[turret] shoot had no effect (ammo %d)",*am);}
        }
    }
    g_tur_prev_fire=fire;
    return 1;
}
static int fp_turret_suppress_shot(void *pc) {
    if (g_tur_pc && pc==g_tur_pc && !g_tur_dispatch) {++g_tur_native_suppressed;return 1;}
    return 0;
}
static int kah_fp_turret(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id;(void)u;
    if (argc>=3 && !_stricmp(argv[1],"gunaim")) {g_tur_cfg_gunaim=atoi(argv[2])!=0;r->append(r,g_tur_cfg_gunaim?"turret gunaim 1":"turret gunaim 0");return KAH_OK;}
    if (argc>=3 && !_stricmp(argv[1],"operate")) {g_tur_cfg_operate=atoi(argv[2])!=0;r->append(r,g_tur_cfg_operate?"turret operate 1":"turret operate 0");return KAH_OK;}
    if (argc>=3 && !_stricmp(argv[1],"drive")) {g_tur_cfg_drive=atoi(argv[2])!=0;r->append(r,g_tur_cfg_drive?"turret drive 1":"turret drive 0");return KAH_OK;}
    char b[1400];void *gun=g_tur_pc?g_tur_gun:NULL;
    if (gun && !readable(gun,0x130)) gun=NULL;
    void *bld=g_tur_bld&&readable(g_tur_bld,0x4B8)?g_tur_bld:NULL;
    float rd=NAN;
    if (bld && readable(bld,0x4B8)) {
        const Vec3 *d=(const Vec3 *)((uintptr_t)bld+TUR_CUR_DIR);
        if (g_tur_aim_valid && gun) {   /* angle between the gun's current aim dir and the turret->aim point line */
            Vec3 p=*(const Vec3 *)((uintptr_t)gun+0xE4);
            float vx=g_tur_aim.x-p.x,vy=g_tur_aim.y-p.y,vz=g_tur_aim.z-p.z,vl=sqrtf(vx*vx+vy*vy+vz*vz),dl=sqrtf(d->x*d->x+d->y*d->y+d->z*d->z);
            if (vl>1e-3f&&dl>1e-3f) rd=acosf(fminf(1.0f,fmaxf(-1.0f,(vx*d->x+vy*d->y+vz*d->z)/(vl*dl))))*57.29578f;
        }
    }
    snprintf(b,sizeof b,"turret on=%d why=%s name=%s ammo=%d/%d reload_left=%.2f reload_max=%.2f rl_state=%.2f aim_valid=%d aim=%.1f,%.1f,%.1f "
             "cur_dir=%.3f,%.3f,%.3f aim_err_deg=%.1f enters=%u leaves=%u frames=%u shots=%u refused=%u refuse_why=%s reloads=%u "
             "r_ignored=%u native_shots_suppressed=%u ai_updates_suppressed=%u last_target=%d gun_pos=%.1f,%.1f,%.1f harp_char=%u harp_target=%u harp_world=%u gunaim=%d last_target_pos=%.1f,%.1f,%.1f",
             g_tur_pc!=NULL,g_tur_why,g_tur_pc?g_tur_name:"-",
             gun?*(int *)((uintptr_t)gun+GUN_AMMO):-1,gun?*(int *)((uintptr_t)gun+TUR_GUN_MAX):-1,
             g_tur_rl_left,g_tur_rl_max,gun?*(float *)((uintptr_t)gun+TUR_GUN_RLSTATE):-1.0f,g_tur_aim_valid,g_tur_aim.x,g_tur_aim.y,g_tur_aim.z,
             bld?((Vec3 *)((uintptr_t)bld+TUR_CUR_DIR))->x:0,bld?((Vec3 *)((uintptr_t)bld+TUR_CUR_DIR))->y:0,
             bld?((Vec3 *)((uintptr_t)bld+TUR_CUR_DIR))->z:0,rd,
             g_tur_enters,g_tur_leaves,g_tur_frames,g_tur_shots,g_tur_shot_refused,g_tur_refuse_why,g_tur_reloads,
             g_tur_r_ignored,g_tur_native_suppressed,g_tur_updt_suppressed,g_tur_last_target!=NULL,gun?((Vec3 *)((uintptr_t)gun+0xE4))->x:0,gun?((Vec3 *)((uintptr_t)gun+0xE4))->y:0,gun?((Vec3 *)((uintptr_t)gun+0xE4))->z:0,g_tur_harp_char,g_tur_harp_target,g_tur_harp_world,g_tur_cfg_gunaim,gun?((Vec3 *)((uintptr_t)gun+0x118))->x:0,gun?((Vec3 *)((uintptr_t)gun+0x118))->y:0,gun?((Vec3 *)((uintptr_t)gun+0x118))->z:0);
    if (bld) {
        void *h=*(void **)((uintptr_t)bld+0x498);
        size_t n=strlen(b);
        void **vt=readable(bld,8)?*(void ***)bld:NULL;
        float v368=NAN,v3c0=NAN,asp=gun?*(float *)((uintptr_t)gun+0x14):NAN;
        if (readable(vt,0x3c8)) {v368=((float (*)(void *))vt[0x368/8])(bld);v3c0=((float (*)(void *))vt[0x3c0/8])(bld);}
        n=strlen(b);snprintf(b+n,sizeof b-n," gun_aimspeed=%.3f v368=%.3f v3c0=%.3f",asp,v368,v3c0);n=strlen(b);
        snprintf(b+n,sizeof b-n," dbg160=%d dbg228=%p speed464=%.3f hinge=%p hinge8=%p aimdist448=%.2f rot4b4=%d drive=%d drive_calls=%u operate=%d operate_calls=%u",
                 *(unsigned char *)((uintptr_t)bld+0x160),*(void **)((uintptr_t)bld+0x228),*(float *)((uintptr_t)bld+0x464),h,
                 readable(h,0x10)?*(void **)((uintptr_t)h+8):NULL,*(float *)((uintptr_t)bld+0x448),*(int *)((uintptr_t)bld+0x4B4),
                 g_tur_cfg_drive,g_tur_drive_calls,g_tur_cfg_operate,g_tur_operate_calls);
    }
    r->append(r,b);return KAH_OK;
}
