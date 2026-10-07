/* FP control scheme (Shay, approved 2026-10-06; memory fp-controls-scheme):
 *   WASD = the only movement in FP (native RMB walk orders swallowed)
 *   MMB click = select whoever is under the crosshair (native MMB camera rotate swallowed)
 *   RMB holstered = context menu for the crosshair target; RMB drawn = block (melee) / aim (ranged), held
 *   LMB drawn = attack the crosshair target (unprovoked if not hostile, vanilla consequences);
 *       no target: free swing (native attack animation, no damage); ranged free fire = adapter path
 *   R = draw / holster (reload moves to R while RMB is held)
 * HUD: one label under the crosshair driven by the real native state (fp_ui_state).
 * Native input: PlayerInterface::playerControl(InputHandler&) reads the static InputHandler's
 * mouse flags; the hook clears the right-button flags (always) and the left-button flags (drawn)
 * while FP owns the cursor, restores them after the call, and latches a swallowed press until release.
 * Everything else here runs on the game thread from fp_controls_tick under the main-loop crash guard. */
#define FPC_IH_MLEFT 0xF3      /* InputHandler: mLeft mRight lastMLeft lastMRight mLDown mRDown mLUp mRUp */
#define FPC_PI_CTXMENU 0x48    /* PlayerInterface::contextMenu (embedded ContextMenu) */
#define FPC_MENU_CLICK_MS 400  /* RMB held shorter than this (holstered) = context-menu click */
#define FPC_TASK_MELEE 5       /* TaskType FOCUSED_MELEE_ATTACK */
#define FPC_TASK_MELEE_UNPROVOKED 61
#define FPC_TASK_RANGED 263    /* RANGED_ATTACK_FOCUSED */
#define FPC_TASK_RANGED_UNPROVOKED 266
#define FPC_KLIB_REAL "?GetRealAddress@KenshiLib@@YA_JPEAX@Z"
#define FPC_SYM_PLAYERCONTROL "?playerControl@PlayerInterface@@QEAAXAEAVInputHandler@@@Z"
#define FPC_SYM_SELECT "?selectObject@PlayerInterface@@QEAAXPEAVRootObject@@_N@Z"
#define FPC_SYM_CTXMENU "?showContextMenu@ContextMenu@@QEAAX_NPEAVRootObject@@@Z"
#define FPC_SYM_ADDORDER "?addOrder@Character@@QEAAXPEAVBuilding@@W4TaskType@@PEAVRootObject@@_N3AEBVVector3@Ogre@@@Z"
#define FPC_SYM_ATTACK "?attackTarget@Character@@QEAAXPEAV1@@Z"
#define FPC_SYM_ISENEMY "?isEnemy@PlayerInterface@@QEAA_NPEAVCharacter@@@Z"
#define FPC_SYM_GETANIM "?getAnimationClass@Character@@QEAAPEAVAnimationClass@@XZ"
#define FPC_SYM_CHOOSE "?chooseAttack@CharStats@@QEAAPEAVCombatTechniqueData@@MMPEAV2@_N@Z"
#define FPC_SYM_PROGRESS "?getAnimationProgress@AnimationClassBase@@QEAAMPEAVCombatTechniqueData@@@Z"
#define FPC_SYM_ENDANIM "?endCombatAnimation@AnimationClass@@QEAAXXZ"
typedef void (*fpc_playercontrol_t)(void *pi,void *ih);
typedef void (*fpc_select_t)(void *pi,void *obj,unsigned char add);
typedef void (*fpc_ctxmenu_t)(void *menu,unsigned char flag,void *obj);
typedef void (*fpc_addorder_t)(void *pc,void *bld,int task,void *target,unsigned char shift,unsigned char clear,const Vec3 *pos);
typedef void (*fpc_attack_t)(void *pc,void *target);
typedef unsigned char (*fpc_isenemy_t)(void *pi,void *pc);
typedef void *(*fpc_getanim_t)(void *pc);
typedef void *(*fpc_choose_t)(void *stats,float range,float reach,void *last,unsigned char stationary);
typedef float (*fpc_progress_t)(void *anim,void *tech);
typedef void (*fpc_endanim_t)(void *anim);
typedef void (*fpc_startanim_t)(void *anim,void *tech,float speed,void *str);
static fpc_playercontrol_t g_fpc_pc_orig;
static fpc_select_t g_fpc_select;
static fpc_ctxmenu_t g_fpc_ctxmenu;
static fpc_addorder_t g_fpc_addorder;
static fpc_attack_t g_fpc_attack;
static fpc_isenemy_t g_fpc_isenemy;
static fpc_getanim_t g_fpc_getanim;
static fpc_choose_t g_fpc_choose;
static fpc_progress_t g_fpc_progress;
static fpc_endanim_t g_fpc_endanim;
static fpc_startanim_t g_fpc_startanim;
static int g_fpc_hook_ok, g_fpc_fault, g_fpc_fs_dead;
static int g_fpc_swallow=1;             /* test switch: fp_keys swallow off = native mouse flags pass (control rows) */
/* buttons: 0 lmb 1 rmb 2 mmb 3 r */
enum {FPC_LMB,FPC_RMB,FPC_MMB,FPC_R,FPC_NBTN};
static const char *const g_fpc_btn_names[FPC_NBTN]={"lmb","rmb","mmb","r"};
static double g_fpc_inj_until[FPC_NBTN];    /* harness press: held until this QPC ms */
static int g_fpc_prev[FPC_NBTN];
static double g_fpc_down_ms[FPC_NBTN];
static int g_fpc_native_frames[2], g_fpc_native_total[2];   /* fp_keys native: synthetic native flags (lmb, rmb) */
static int g_fpc_latch[2];                  /* swallowing a native press until its release */
static int g_fpc_fists;                     /* R toggled with nothing to draw: unarmed ready stance */
static void *g_fpc_hold_actor;
static int g_fpc_own_sheathe;
static int g_fpc_ctx_freed, g_fpc_ctx_relock;   /* context menu freed the cursor; relock countdown */
static double g_fpc_ctx_ms;
/* free swing (no target, not fighting): native attack animation only */
static void *g_fpc_fs_anim,*g_fpc_fs_tech;
static double g_fpc_fs_start_ms, g_fpc_recover_until_ms;
/* evidence counters */
static unsigned g_fpc_mmb_selects,g_fpc_mmb_none,g_fpc_ctx_opens,g_fpc_ctx_none,g_fpc_rmb_swallowed,g_fpc_lmb_swallowed,
    g_fpc_mmb_cam_frames,g_fpc_r_draws,g_fpc_r_holsters,g_fpc_r_draw_fail,g_fpc_engages,g_fpc_free_swings,g_fpc_fs_faults,
    g_fpc_fs_notech,g_fpc_fs_ends,g_fpc_free_block_frames,g_fpc_block_checks,g_fpc_native_injected,g_fpc_sheathe_kept,
    g_fpc_lmb_clicks,g_fpc_r_keys_swallowed,g_fpc_ticks;
static float g_fpc_fs_prog, g_fpc_fs_prog_max;
static int g_fpc_last_task=-1;
static char g_fpc_last_select[48]="none", g_fpc_last_target[48]="none";
static const char *g_fpc_ui_state="off";
static int g_fpc_drawn, g_fpc_ranged, g_fpc_input[FPC_NBTN];

static double fpc_now_ms(void) {
    LARGE_INTEGER f,c;QueryPerformanceFrequency(&f);QueryPerformanceCounter(&c);
    return f.QuadPart?(double)c.QuadPart*1000.0/(double)f.QuadPart:0.0;
}
static void *fpc_klib(const char *sym) {
    HMODULE k=GetModuleHandleA("KenshiLib.dll");
    return k?(void *)GetProcAddress(k,sym):NULL;
}
/* KenshiLib exports are thunks; hooks need the real game address. */
static void *fpc_klib_real(const char *sym) {
    void *stub=fpc_klib(sym);
    intptr_t (*real)(void *)=(intptr_t (*)(void *))fpc_klib(FPC_KLIB_REAL);
    if (!stub || !real) return NULL;
    intptr_t a=real(stub);
    return a?(void *)a:NULL;
}
static unsigned char *fpc_input_handler(void) {
    unsigned char *ih=(unsigned char *)(g_base+RVA_INPUT_CONTROLENABLED-0xD0);
    return readable(ih+FPC_IH_MLEFT,8)?ih:NULL;
}
/* FP owns the cursor this frame (look mode, no UI): the native mouse orders must not fire. */
static int fpc_owns_mouse(void) {
    return g_fp_mode && g_cursor_hidden && !g_ui_open;
}
/* RootObjectBase::getName returns std::string by value (hidden result pointer); a heap name (>=16 chars)
 * is leaked (clicks only, a few bytes). Caller holds the crash guard. */
static void fpc_name(void *pc,char *out,size_t n) {
    snprintf(out,n,"%p",pc);
    static void *(*getname)(void *,void *);
    if (!getname) getname=(void *(*)(void *,void *))fpc_klib("?getName@RootObjectBase@@UEBA?AV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@XZ");
    if (!pc || !getname) return;
    unsigned char str[32]={0};
    getname(pc,str);
    const char *s=*(size_t *)(str+0x18)>=16?*(const char **)str:(const char *)str;
    if (!readable(s,1)) return;
    size_t i=0;for(;i+1<n && readable(s+i,1) && s[i];++i){char c=s[i];out[i]=(c==' '||c=='='||c<32)?'_':c;}
    out[i]=0;
}
/* PlayerInterface::playerControl detour (game thread, inside the frame). */
static void fpc_playercontrol_hook(void *pi,void *ihp) {
    unsigned char *ih=fpc_input_handler();
    if (!ih || (unsigned char *)ihp!=ih) {g_fpc_pc_orig(pi,ihp);return;}
    unsigned char *f=ih+FPC_IH_MLEFT;   /* [0]mLeft [1]mRight [2]lastL [3]lastR [4]LDown [5]RDown [6]LUp [7]RUp */
    for (int b=0;b<2;++b) if (g_fpc_native_frames[b]>0) {        /* fp_keys native: synthetic native press */
        int first=g_fpc_native_frames[b]==g_fpc_native_total[b], last=g_fpc_native_frames[b]==1;
        f[b]=!last;f[4+b]=first;f[6+b]=last;f[2+b]=!first;
        --g_fpc_native_frames[b];++g_fpc_native_injected;
    }
    unsigned char saved[8];memcpy(saved,f,8);
    int own=fpc_owns_mouse() && g_fpc_swallow;
    int clear[2];
    clear[1]=own;                                   /* RMB: never a native walk/menu in FP */
    clear[0]=own && g_fpc_drawn;                    /* LMB: native select only while holstered */
    for (int b=0;b<2;++b) {
        int any=f[b]||f[2+b]||f[4+b]||f[6+b];
        if (clear[b] && (f[b]||f[4+b])) g_fpc_latch[b]=1;
        if ((clear[b]||g_fpc_latch[b]) && any) {
            f[b]=f[2+b]=f[4+b]=f[6+b]=0;
            if (b) ++g_fpc_rmb_swallowed; else ++g_fpc_lmb_swallowed;
        }
        if (!saved[b] && !saved[4+b]) g_fpc_latch[b]=0;
    }
    g_fpc_pc_orig(pi,ihp);
    memcpy(f,saved,8);                              /* other consumers see the real state */
}
/* CameraClass::update: FP swallows the native MMB rotate (yaw/pitch restored after the call). */
static int fpc_cam_pre(void *cam,float *yaw,float *pitch) {
    if (!fpc_owns_mouse() || !g_fpc_swallow || !readable(cam,0x20)) return 0;
    if (!(GetAsyncKeyState(VK_MBUTTON)&0x8000) && !g_fpc_input[FPC_MMB]) return 0;
    *yaw=*(float *)((uintptr_t)cam+0x18);*pitch=*(float *)((uintptr_t)cam+0x1C);
    ++g_fpc_mmb_cam_frames;return 1;
}
static void fpc_cam_post(void *cam,float yaw,float pitch) {
    *(float *)((uintptr_t)cam+0x18)=yaw;*(float *)((uintptr_t)cam+0x1C)=pitch;
    *(unsigned char *)cam=0;                        /* isRotating */
}
/* keyPressed: R belongs to draw/holster in FP (OIS DIK_R = 0x13). */
static int fpc_key_swallow(unsigned dik) {
    if (dik!=0x13 || !g_fp_mode || g_ui_open || !g_fpc_hook_ok) return 0;
    ++g_fpc_r_keys_swallowed;return 1;
}
static int fpc_in_fight(void *pc) {
    void *cc=g_melee_get_combat&&char_valid(pc)?g_melee_get_combat(pc):NULL;
    return readable(cc,0x2b8) && *(unsigned char *)((uintptr_t)cc+CC_ACTIVE);
}
/* sheatheWeapon: keep an R-drawn weapon out while not fighting (the idle AI re-sheathes it). */
static int fpc_suppress_sheathe(void *pc) {
    if (!g_fpc_hold_actor || g_fpc_own_sheathe || pc!=g_fpc_hold_actor || !g_fp_mode) return 0;
    if (fpc_in_fight(pc)) return 0;                 /* native weapon switching in a fight stays free */
    ++g_fpc_sheathe_kept;return 1;
}
/* Character under the crosshair (physics ray, mesh refine), without disturbing the shot telemetry. */
static void *fpc_crosshair_char(void *pc) {
    CombatRayHit saved_hit=g_combat_camera_hit;
    Vec3 so=g_combat_aim_origin,sd=g_combat_aim_dir;int sh=g_combat_aim_have_ray;
    unsigned sk=g_combat_aim_attr_kept,sdr=g_combat_aim_attr_dropped;
    void *saved_node=g_mr_perch_node;mr_cache_t *saved_cache=g_mr_perch_cache;
    Vec3 aim;void *t=NULL;
    if (combat_camera_aim(&aim) && g_combat_camera_hit.shape) t=combat_ray_target(&g_combat_camera_hit,pc);
    g_mr_perch_node=saved_node;g_mr_perch_cache=saved_cache;
    g_combat_camera_hit=saved_hit;g_combat_aim_origin=so;g_combat_aim_dir=sd;g_combat_aim_have_ray=sh;
    g_combat_aim_attr_kept=sk;g_combat_aim_attr_dropped=sdr;
    return t;
}
static void *fpc_player_interface(void *gw) {
    return readable((void *)((uintptr_t)gw+GW_PLAYER),8)?*(void **)((uintptr_t)gw+GW_PLAYER):NULL;
}
static void fpc_draw_toggle(void *pc) {
    void **vt=readable(pc,8)?*(void ***)pc:NULL;
    if (!readable((void *)((uintptr_t)vt+0x3D8),8)) {++g_fpc_r_draw_fail;return;}
    void *wih=readable((void *)((uintptr_t)pc+CHAR_WEAPON_IN_HANDS),8)?*(void **)((uintptr_t)pc+CHAR_WEAPON_IN_HANDS):NULL;
    if (wih || g_fpc_fists) {
        g_fpc_hold_actor=NULL;g_fpc_fists=0;
        if (wih) {g_fpc_own_sheathe=1;((void (*)(void *))vt[0x2D0/8])(pc);g_fpc_own_sheathe=0;}
        ++g_fpc_r_holsters;logline("[controls] R holster");return;
    }
    void *w=((void *(*)(void *))vt[0x3C8/8])(pc);
    if (!w) {g_fpc_fists=1;g_fpc_hold_actor=pc;++g_fpc_r_draws;logline("[controls] R ready (unarmed)");return;}
    unsigned char empty[32];make_mstr(empty,"");
    ((char (*)(void *,void *,void *))vt[0x3D8/8])(pc,w,empty);
    g_fpc_hold_actor=pc;++g_fpc_r_draws;logline("[controls] R draw weapon %p",w);
}
/* LMB drawn on a character: start (or retarget) the attack with the game's own order. */
static void fpc_engage(void *gw,void *pc,void *t,int ranged) {
    void *pi=fpc_player_interface(gw);
    if (!g_fpc_addorder || !g_fpc_attack || !pi) return;
    void *cc=g_melee_get_combat?g_melee_get_combat(pc):NULL;
    if (readable(cc,0x2b8) && *(unsigned char *)((uintptr_t)cc+CC_ACTIVE) && *(void **)((uintptr_t)cc+CC_TARGET)==t) return;
    int hostile=g_fpc_isenemy?g_fpc_isenemy(pi,t)!=0:0;
    int task=ranged?(hostile?FPC_TASK_RANGED:FPC_TASK_RANGED_UNPROVOKED):(hostile?FPC_TASK_MELEE:FPC_TASK_MELEE_UNPROVOKED);
    Vec3 pos={0,0,0};char_position(t,&pos);
    g_fpc_addorder(pc,NULL,task,t,0,1,&pos);
    g_fpc_attack(pc,t);
    g_fpc_last_task=task;++g_fpc_engages;fpc_name(t,g_fpc_last_target,sizeof g_fpc_last_target);
    if (!ranged && g_combat_enabled) fp_melee_click_legal_start(1500);   /* manual melee: the click becomes the first swing */
    logline("[controls] LMB engage %s task=%d hostile=%d",g_fpc_last_target,task,hostile);
}
static void fpc_free_swing(void *pc) {
    if (g_fpc_fs_dead || g_fpc_fs_tech || !g_fpc_getanim || !g_fpc_choose || !g_fpc_startanim || !g_fpc_progress) return;
    void *cc=g_melee_get_combat?g_melee_get_combat(pc):NULL;
    void *stats=readable(cc,0x2b8)?*(void **)((uintptr_t)cc+CC_STATS):NULL;
    void *anim=g_fpc_getanim(pc);
    if (!readable(stats,STATS_ATTACK_SPEED+4) || !readable(anim,8)) {++g_fpc_fs_notech;return;}
    void *tech=g_fpc_choose(stats,5.0f,30.0f,NULL,1);
    if (!readable(tech,TECH_ANIM_SPEED+4)) {++g_fpc_fs_notech;return;}
    float spd=*(float *)((uintptr_t)stats+STATS_ATTACK_SPEED);
    if (!(isfinite(spd)&&spd>0.2f&&spd<4.0f)) spd=1.0f;
    unsigned char empty[32];make_mstr(empty,"");
    g_fpc_startanim(anim,tech,spd,empty);
    g_fpc_fs_anim=anim;g_fpc_fs_tech=tech;g_fpc_fs_start_ms=fpc_now_ms();g_fpc_fs_prog=0;
    ++g_fpc_free_swings;
}
static void fpc_free_swing_step(void *pc) {
    if (!g_fpc_fs_tech) return;
    void *anim=char_valid(pc)?g_fpc_getanim(pc):NULL;
    double el=fpc_now_ms()-g_fpc_fs_start_ms;
    float p=anim==g_fpc_fs_anim?g_fpc_progress(anim,g_fpc_fs_tech):1.0f;
    if (isfinite(p)) {g_fpc_fs_prog=p;if (p>g_fpc_fs_prog_max) g_fpc_fs_prog_max=p;}
    if (anim!=g_fpc_fs_anim || !isfinite(p) || p>=0.999f || el>3000.0) {
        if (anim==g_fpc_fs_anim && g_fpc_endanim) g_fpc_endanim(anim);
        g_fpc_fs_tech=NULL;g_fpc_fs_anim=NULL;++g_fpc_fs_ends;g_fpc_recover_until_ms=fpc_now_ms()+300.0;
    }
}
/* RMB drawn melee: block request whenever held (fighting: the native reactive block check;
 * the manual adapter does the same for its owned fighter). */
static void fpc_free_block(void *pc) {
    ++g_fpc_free_block_frames;
    void *cc=g_melee_get_combat?g_melee_get_combat(pc):NULL;
    if (!readable(cc,0x2b8) || cc==g_melee_owned_cc) return;
    *(unsigned char *)((uintptr_t)cc+CC_WANTS_BLOCK)=1;
    int state=*(int *)((uintptr_t)cc+CC_STATE),dead=*(unsigned char *)((uintptr_t)cc+CC_DEADTIME);
    if (*(unsigned char *)((uintptr_t)cc+CC_ACTIVE) && g_melee_check_block && state!=MELEE_CHOP && state!=MELEE_BLOCK &&
        state!=MELEE_STUMBLE && !dead && g_melee_check_block(cc,0.5f,0.5f)) ++g_fpc_block_checks;
}
/* HUD / harness state from the real native state. */
static const char *fpc_ui_state(void *pc,int rmb) {
    if (!g_fp_mode) return "off";
    if (!char_valid(pc)) return "none";
    if (g_is_down || combat_char_unconscious(pc) || char_prone_state(pc)) return "down";
    if (!g_fpc_drawn) return "holstered";
    if (g_fpc_ranged) {
        void *rc=readable((void *)((uintptr_t)pc+CHAR_RANGEDCOMBAT),8)?*(void **)((uintptr_t)pc+CHAR_RANGEDCOMBAT):NULL;
        if (readable(rc,0x88) && *(float *)((uintptr_t)rc+0x78)>0.0f) return "reloading";
        if (g_combat_observed.reloading) return "reloading";
        return rmb?"aiming":"ready";
    }
    if (g_fpc_fs_tech) return "swinging";
    void *cc=g_melee_get_combat?g_melee_get_combat(pc):NULL;
    if (readable(cc,0x2b8) && *(unsigned char *)((uintptr_t)cc+CC_ACTIVE)) {
        int s=*(int *)((uintptr_t)cc+CC_STATE);
        if (s==MELEE_STUMBLE) return "staggered";
        if (s==MELEE_CHOP) return "swinging";
        if (*(unsigned char *)((uintptr_t)cc+CC_DEADTIME)) return "recovering";
        if (s==MELEE_BLOCK || s==2 || rmb) return "blocking";
        return "ready";
    }
    if (fpc_now_ms()<g_fpc_recover_until_ms) return "recovering";
    return rmb?"blocking":"ready";
}
static int fpc_button(int b,int phys_ok) {
    static const int vk[FPC_NBTN]={VK_LBUTTON,VK_RBUTTON,VK_MBUTTON,0x52};
    int phys=phys_ok && (GetAsyncKeyState(vk[b])&0x8000)!=0;
    return phys || fpc_now_ms()<g_fpc_inj_until[b];
}
static void fpc_release_all(void) {
    if (g_fpc_ctx_freed) {g_free_toggle=0;g_fpc_ctx_freed=0;}
    g_fpc_hold_actor=NULL;g_fpc_fists=0;g_fpc_fs_tech=NULL;g_fpc_fs_anim=NULL;
    for (int b=0;b<FPC_NBTN;++b) {g_fpc_prev[b]=0;g_fpc_input[b]=0;}
}
/* Context menu freed the cursor: relock on the next click release (option picked / dismissed) or Esc. */
static void fpc_ctx_relock_step(void) {
    if (!g_fpc_ctx_freed) return;
    if (g_fpc_ctx_relock>0) {if (--g_fpc_ctx_relock==0) {g_free_toggle=0;g_fpc_ctx_freed=0;}return;}
    static int lp,rp;
    int l=(GetAsyncKeyState(VK_LBUTTON)&0x8000)!=0,r=(GetAsyncKeyState(VK_RBUTTON)&0x8000)!=0,esc=(GetAsyncKeyState(VK_ESCAPE)&0x8000)!=0;
    if (fpc_now_ms()-g_fpc_ctx_ms>250.0 && ((lp&&!l)||(rp&&!r)||esc)) g_fpc_ctx_relock=3;
    if (!g_free_toggle) g_fpc_ctx_freed=0;          /* the player relocked (free-cursor key) */
    lp=l;rp=r;
}
static void fp_controls_tick(void *gw,float dt) {
    (void)dt;++g_fpc_ticks;
    static void *last_actor;
    if (!g_fp_mode || g_fpc_fault) {
        if (last_actor) fpc_release_all();
        last_actor=NULL;g_fpc_ui_state="off";g_fpc_drawn=0;return;
    }
    static volatile int phase;   /* 1 = free swing native calls: a fault there only disables the free swing */
    phase=0;
    if (setjmp(g_guard_jb)) {
        g_guard_armed=0;
        if (phase==1) {g_fpc_fs_dead=1;++g_fpc_fs_faults;g_fpc_fs_tech=NULL;g_fpc_fs_anim=NULL;logline("[controls] free swing FAULTED; disabled");return;}
        g_fpc_fault=1;fpc_release_all();logline("[controls] native call fault; FP controls disabled");return;
    }
    guard_arm();
    void *pc=fp_controlled_char(gw);
    if (pc!=last_actor) {fpc_release_all();last_actor=pc;}
    if (!char_valid(pc)) {g_guard_armed=0;g_fpc_ui_state="none";return;}
    if (g_is_down && g_fpc_hold_actor) {g_fpc_hold_actor=NULL;g_fpc_fists=0;}
    fpc_ctx_relock_step();
    void *wih=readable((void *)((uintptr_t)pc+CHAR_WEAPON_IN_HANDS),8)?*(void **)((uintptr_t)pc+CHAR_WEAPON_IN_HANDS):NULL;
    void *ranged=combat_virtual(pc,0x3d0);
    g_fpc_ranged=ranged&&((void *(*)(void *))ranged)(pc)!=NULL;
    g_fpc_drawn=wih!=NULL||g_fpc_fists;
    int phys_ok=g_cursor_hidden && !g_ui_open && game_has_focus();
    int in[FPC_NBTN],edge[FPC_NBTN],rel[FPC_NBTN];
    double now=fpc_now_ms();
    for (int b=0;b<FPC_NBTN;++b) {
        in[b]=!g_ui_open && fpc_button(b,phys_ok);
        edge[b]=in[b]&&!g_fpc_prev[b];rel[b]=!in[b]&&g_fpc_prev[b];
        if (edge[b]) g_fpc_down_ms[b]=now;
        g_fpc_prev[b]=in[b];g_fpc_input[b]=in[b];
    }
    if (!g_is_down && g_fpc_hook_ok) {
        if (edge[FPC_R] && !in[FPC_RMB]) fpc_draw_toggle(pc);   /* R with RMB held = reload (adapter) */
        if (edge[FPC_MMB] && g_fpc_select) {
            void *t=fpc_crosshair_char(pc);
            if (t) {g_fpc_select(fpc_player_interface(gw),t,0);++g_fpc_mmb_selects;fpc_name(t,g_fpc_last_select,sizeof g_fpc_last_select);
                    logline("[controls] MMB select %s",g_fpc_last_select);}
            else ++g_fpc_mmb_none;
        }
        if (rel[FPC_RMB] && !g_fpc_drawn && now-g_fpc_down_ms[FPC_RMB]<FPC_MENU_CLICK_MS && g_fpc_ctxmenu) {
            void *t=fpc_crosshair_char(pc);
            void *pi=fpc_player_interface(gw);
            if (t && readable(pi,FPC_PI_CTXMENU+8)) {
                g_fpc_ctxmenu((void *)((uintptr_t)pi+FPC_PI_CTXMENU),1,t);++g_fpc_ctx_opens;
                g_free_toggle=1;g_fpc_ctx_freed=1;g_fpc_ctx_relock=0;g_fpc_ctx_ms=now;
                fpc_name(t,g_fpc_last_target,sizeof g_fpc_last_target);
                logline("[controls] RMB context menu %s",g_fpc_last_target);
            } else ++g_fpc_ctx_none;
        }
        if (g_fpc_drawn && edge[FPC_LMB] && !in[FPC_RMB]) {
            ++g_fpc_lmb_clicks;
            void *t=fpc_crosshair_char(pc);
            if (t) fpc_engage(gw,pc,t,g_fpc_ranged);
            else if (!g_fpc_ranged && !fpc_in_fight(pc)) {phase=1;fpc_free_swing(pc);phase=0;}
        }
        if (g_fpc_fs_tech) {phase=1;fpc_free_swing_step(pc);phase=0;}
        if (g_fpc_drawn && !g_fpc_ranged && in[FPC_RMB]) fpc_free_block(pc);
    }
    g_fpc_ui_state=fpc_ui_state(pc,in[FPC_RMB]);
    g_guard_armed=0;
}
static void *g_fpc_hud;static const char *g_fpc_hud_text;static int g_fpc_hud_shown;static unsigned g_fpc_hud_changes;
static size_t fpc_state(char *b,size_t n) {
    return (size_t)snprintf(b,n,"hook=%d fault=%d swallow=%d fp=%d drawn=%d ranged=%d fists=%d hold=%d ui_state=%s in=%d%d%d%d "
        "mmb_selects=%u mmb_none=%u last_select=%s ctx_opens=%u ctx_none=%u ctx_freed=%d rmb_swallowed=%u lmb_swallowed=%u "
        "mmb_cam_frames=%u r_keys=%u r_draws=%u r_holsters=%u r_draw_fail=%u sheathe_kept=%u lmb_clicks=%u engages=%u last_task=%d last_target=%s "
        "free_swings=%u fs_active=%d fs_prog=%.3f fs_prog_max=%.3f fs_ends=%u fs_notech=%u fs_faults=%u fs_dead=%d "
        "free_block_frames=%u block_checks=%u native_injected=%u ticks=%u hud=%d hud_shown=%d hud_text=%s hud_changes=%u",
        g_fpc_hook_ok,g_fpc_fault,g_fpc_swallow,g_fp_mode,g_fpc_drawn,g_fpc_ranged,g_fpc_fists,g_fpc_hold_actor!=NULL,g_fpc_ui_state,
        g_fpc_input[0],g_fpc_input[1],g_fpc_input[2],g_fpc_input[3],
        g_fpc_mmb_selects,g_fpc_mmb_none,g_fpc_last_select,g_fpc_ctx_opens,g_fpc_ctx_none,g_fpc_ctx_freed,g_fpc_rmb_swallowed,g_fpc_lmb_swallowed,
        g_fpc_mmb_cam_frames,g_fpc_r_keys_swallowed,g_fpc_r_draws,g_fpc_r_holsters,g_fpc_r_draw_fail,g_fpc_sheathe_kept,g_fpc_lmb_clicks,g_fpc_engages,g_fpc_last_task,g_fpc_last_target,
        g_fpc_free_swings,g_fpc_fs_tech!=NULL,g_fpc_fs_prog,g_fpc_fs_prog_max,g_fpc_fs_ends,g_fpc_fs_notech,g_fpc_fs_faults,g_fpc_fs_dead,
        g_fpc_free_block_frames,g_fpc_block_checks,g_fpc_native_injected,g_fpc_ticks,
        g_fpc_hud!=NULL,g_fpc_hud_shown,g_fpc_hud_text?g_fpc_hud_text:"none",g_fpc_hud_changes);
}
static int fpc_btn_index(const char *s) {
    for (int b=0;b<FPC_NBTN;++b) if (!_stricmp(s,g_fpc_btn_names[b])) return b;
    return -1;
}
static int kah_fp_keys(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id;(void)u;
    if (argc==2 && !_stricmp(argv[1],"state")) {char b[1400];fpc_state(b,sizeof b);r->append(r,b);return KAH_OK;}
    if ((argc==3||argc==4) && !_stricmp(argv[1],"press")) {
        int b=fpc_btn_index(argv[2]);int ms=argc==4?atoi(argv[3]):80;
        if (b<0 || ms<20 || ms>20000) {r->append(r,"press <lmb|rmb|mmb|r> [hold_ms 20..20000]");return KAH_ERROR;}
        g_fpc_inj_until[b]=fpc_now_ms()+ms;r->append(r,"press published");return KAH_OK;
    }
    if (argc==3 && !_stricmp(argv[1],"release")) {
        int b=fpc_btn_index(argv[2]);if (b<0) {r->append(r,"release <lmb|rmb|mmb|r>");return KAH_ERROR;}
        g_fpc_inj_until[b]=0;r->append(r,"released");return KAH_OK;
    }
    if ((argc==3||argc==4) && !_stricmp(argv[1],"native")) {
        int b=fpc_btn_index(argv[2]);int fr=argc==4?atoi(argv[3]):6;
        if (b<0 || b>1 || fr<2 || fr>600) {r->append(r,"native <lmb|rmb> [frames 2..600]");return KAH_ERROR;}
        g_fpc_native_total[b]=g_fpc_native_frames[b]=fr;r->append(r,"native flags queued (playerControl input)");return KAH_OK;
    }
    if (argc==3 && !_stricmp(argv[1],"swallow")) {
        g_fpc_swallow=!_stricmp(argv[2],"on");r->append(r,g_fpc_swallow?"swallow=1":"swallow=0");return KAH_OK;
    }
    if (argc==3 && !_stricmp(argv[1],"focus")) {
        g_test_focus=!_stricmp(argv[2],"on");r->append(r,g_test_focus?"test_focus=1":"test_focus=0");return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"reset")) {
        g_fpc_mmb_selects=g_fpc_mmb_none=g_fpc_ctx_opens=g_fpc_ctx_none=g_fpc_rmb_swallowed=g_fpc_lmb_swallowed=g_fpc_mmb_cam_frames=0;
        g_fpc_r_draws=g_fpc_r_holsters=g_fpc_r_draw_fail=g_fpc_engages=g_fpc_free_swings=g_fpc_fs_faults=g_fpc_fs_notech=g_fpc_fs_ends=0;
        g_fpc_free_block_frames=g_fpc_block_checks=g_fpc_native_injected=g_fpc_sheathe_kept=g_fpc_lmb_clicks=g_fpc_r_keys_swallowed=0;
        g_fpc_fs_prog_max=0;g_fpc_last_task=-1;strcpy(g_fpc_last_select,"none");strcpy(g_fpc_last_target,"none");
        g_fpc_swallow=1;for (int b=0;b<FPC_NBTN;++b) g_fpc_inj_until[b]=0;
        r->append(r,"counters reset, swallow=1");return KAH_OK;
    }
    r->append(r,"usage: fp_keys state|press <lmb|rmb|mmb|r> [hold_ms]|release <btn>|native <lmb|rmb> [frames]|swallow on|off|focus on|off|reset");
    return KAH_ERROR;
}
/* AnimationClass::startCombatAnimation(tech, speed, std::string) is not exported: it sits at a fixed
 * distance after AnimationClassBase::getAnimationProgress (1.0.65: 0x5B4120 -> 0x5B6D70); the prologue
 * is verified before use (two .text matches for the bare prologue, so the anchor is needed). */
static void fpc_resolve_startanim(void) {
    static const unsigned char pro[30]={0x40,0x53,0x55,0x57,0x41,0x54,0x48,0x81,0xEC,0xC8,0x00,0x00,0x00,0x48,0xC7,0x44,
        0x24,0x70,0xFE,0xFF,0xFF,0xFF,0x0F,0x29,0xB4,0x24,0xB0,0x00,0x00,0x00};
    unsigned char *p=(unsigned char *)fpc_klib_real(FPC_SYM_PROGRESS);
    if (p && readable(p+0x2C50,sizeof pro) && !memcmp(p+0x2C50,pro,sizeof pro)) g_fpc_startanim=(fpc_startanim_t)(p+0x2C50);
}
static void fp_controls_init(void) {
    g_fpc_select=(fpc_select_t)fpc_klib(FPC_SYM_SELECT);
    g_fpc_ctxmenu=(fpc_ctxmenu_t)fpc_klib(FPC_SYM_CTXMENU);
    g_fpc_addorder=(fpc_addorder_t)fpc_klib(FPC_SYM_ADDORDER);
    g_fpc_attack=(fpc_attack_t)fpc_klib(FPC_SYM_ATTACK);
    g_fpc_isenemy=(fpc_isenemy_t)fpc_klib(FPC_SYM_ISENEMY);
    g_fpc_getanim=(fpc_getanim_t)fpc_klib(FPC_SYM_GETANIM);
    g_fpc_choose=(fpc_choose_t)fpc_klib(FPC_SYM_CHOOSE);
    g_fpc_progress=(fpc_progress_t)fpc_klib(FPC_SYM_PROGRESS);
    g_fpc_endanim=(fpc_endanim_t)fpc_klib(FPC_SYM_ENDANIM);
    fpc_resolve_startanim();
    void *pcf=fpc_klib_real(FPC_SYM_PLAYERCONTROL);
    g_fpc_hook_ok=pcf && fpc_input_handler() && install_hook(pcf,(void *)fpc_playercontrol_hook,(void **)&g_fpc_pc_orig);
    if (!g_fpc_startanim) g_fpc_fs_dead=1;
    logline("[controls] playerControl=%p hook=%d select=%p ctxmenu=%p addOrder=%p attack=%p isEnemy=%p anim=%p choose=%p progress=%p end=%p startanim=%p",
        pcf,g_fpc_hook_ok,(void *)g_fpc_select,(void *)g_fpc_ctxmenu,(void *)g_fpc_addorder,(void *)g_fpc_attack,(void *)g_fpc_isenemy,
        (void *)g_fpc_getanim,(void *)g_fpc_choose,(void *)g_fpc_progress,(void *)g_fpc_endanim,(void *)g_fpc_startanim);
}
/* HUD: one label under the crosshair with fp_ui_state (MyGUI TextBox on the Pointer layer, centred,
 * tinted per state). Post-frame from fp_gui_update; a faulting MyGUI call disables only the label. */
#define FPC_SYM_TEXTALIGN "?setTextAlign@TextBox@MyGUI@@UEAAXAEBUAlign@2@@Z"
#define FPC_SYM_TEXTCOLOUR "?setTextColour@TextBox@MyGUI@@UEAAXAEBVColour@2@@Z"
static int g_fpc_hud_dead;
static void fpc_hud_update(int show) {
    if (g_fpc_hud_dead || !g_widget_setvisible) return;
    if (!show) {if (g_fpc_hud && g_fpc_hud_shown) {g_widget_setvisible(g_fpc_hud,0);g_fpc_hud_shown=0;}return;}
    if (g_guard_armed) return;
    if (setjmp(g_guard_jb)) {g_guard_armed=0;g_fpc_hud_dead=1;logline("[controls] state HUD FAULTED; disabled");return;}
    guard_arm();
    if (!g_fpc_hud && g_gui_getinstance && g_gui_createwidget) {
        void *gui=g_gui_getinstance();
        int cx=GetSystemMetrics(SM_CXSCREEN),cy=GetSystemMetrics(SM_CYSCREEN);
        if (cx<=0) cx=1920;
        if (cy<=0) cy=1080;
        unsigned char t[32],sk[32],l[32],n[32];
        make_mstr(t,"TextBox");make_mstr(l,"Pointer");make_mstr(n,"FPUiState");
        void *skh=make_mstr_long(sk,"Kenshi_GenericTextBoxFlat");
        void *w=readable(gui,8)?g_gui_createwidget(gui,t,sk,cx/2-90,cy/2+20,180,24,0,l,n):NULL;
        if (skh) free(skh);
        if (readable(w,8)) {
            HMODULE mg=GetModuleHandleA(MYGUI_DLL);
            void (*align)(void *,const int *)=mg?(void (*)(void *,const int *))GetProcAddress(mg,FPC_SYM_TEXTALIGN):NULL;
            int centre=0;   /* MyGUI Align::Center (HCenter|VCenter) */
            if (align) align(w,&centre);
            g_fpc_hud=w;g_fpc_hud_text=NULL;
            logline("[controls] state HUD widget %p",w);
        }
    }
    if (g_fpc_hud) {
        const char *st=g_fpc_ui_state?g_fpc_ui_state:"off";
        if (st!=g_fpc_hud_text) {
            char up[24];size_t i=0;for(;st[i]&&i+1<sizeof up;++i) up[i]=(char)toupper((unsigned char)st[i]);up[i]=0;
            caption_set(g_fpc_hud,up,g_textbox_setcap);
            static void (*colour)(void *,const float *);static int cres;
            if (!cres) {HMODULE mg=GetModuleHandleA(MYGUI_DLL);cres=1;
                colour=mg?(void (*)(void *,const float *))GetProcAddress(mg,FPC_SYM_TEXTCOLOUR):NULL;}
            float c[4]={1,1,1,0.9f};
            if (!strcmp(st,"holstered")) {c[0]=c[1]=c[2]=0.7f;c[3]=0.6f;}
            else if (!strcmp(st,"swinging")) {c[0]=1;c[1]=0.6f;c[2]=0.2f;}
            else if (!strcmp(st,"recovering")||!strcmp(st,"reloading")) {c[0]=1;c[1]=0.9f;c[2]=0.3f;}
            else if (!strcmp(st,"blocking")) {c[0]=0.4f;c[1]=0.7f;c[2]=1;}
            else if (!strcmp(st,"aiming")) {c[0]=0.4f;c[1]=1;c[2]=0.5f;}
            else if (!strcmp(st,"staggered")||!strcmp(st,"down")) {c[0]=1;c[1]=0.3f;c[2]=0.3f;}
            if (colour) colour(g_fpc_hud,c);
            g_fpc_hud_text=st;++g_fpc_hud_changes;
        }
        if (!g_fpc_hud_shown) {g_widget_setvisible(g_fpc_hud,1);g_fpc_hud_shown=1;}
    }
    g_guard_armed=0;
}
/* Camera pull-back collision (kfp_view.inc): the aim physics trace (0x087f9e07) from the eye backwards;
 * character hits (our own head/body first, squad mates behind us) are re-cast past, at most 3 times.
 * Caller (fp_view_apply / probe) holds the crash guard. Returns the wall distance along dir or -1. */
static float fp_view_trace_wall(const Vec3 *from,const Vec3 *dir,float range) {
    if (!g_combat_physics_trace || !g_combat_hit_ctor) return -1.0f;
    Vec3 o=*from;float done=0;
    for (int i=0;i<4 && done<range;++i) {
        CombatRayHit h;
        int t=combat_trace_ray(&o,dir,range-done,&h);
        if (t<=0 || !isfinite(h.distance)) return -1.0f;
        if (h.ids[0]!=1) return done+h.distance;
        float step=h.distance+0.3f;     /* past this body's surface */
        done+=step;o.x+=dir->x*step;o.y+=dir->y*step;o.z+=dir->z*step;
    }
    return -1.0f;
}
