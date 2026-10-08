/* FP control scheme (Shay, approved 2026-10-06; memory fp-controls-scheme):
 *   WASD = the only movement in FP (native RMB walk orders swallowed)
 *   MMB click = select whoever is under the crosshair (native MMB camera rotate swallowed)
 *   RMB holstered = context menu for the crosshair target; RMB drawn = block (melee) / aim (ranged), held
 *   LMB drawn = attack the crosshair target (unprovoked if not hostile, vanilla consequences);
 *       no target: free swing (native attack animation, no damage); ranged free fire = adapter path
 *   R = draw / holster only (PT18: never reloads; reload is automatic while aiming an empty crossbow)
 * HUD: one label under the crosshair driven by the real native state (fp_ui_state).
 * Native input: PlayerInterface::playerControl(InputHandler&) reads the static InputHandler's
 * mouse flags; the hook clears the right-button flags (always) and the left-button flags (drawn)
 * while FP owns the cursor, restores them after the call, and latches a swallowed press until release.
 * Everything else here runs on the game thread from fp_controls_tick under the main-loop crash guard. */
#define FPC_IH_MLEFT 0xF3      /* InputHandler: mLeft mRight lastMLeft lastMRight mLDown mRDown mLUp mRUp */
#define FPC_PI_CTXMENU 0x48    /* PlayerInterface::contextMenu (embedded ContextMenu) */
#define FPC_MENU_CLICK_MS 400  /* RMB held shorter than this (holstered) = context-menu click */
#define FPC_TASK_MELEE 5       /* TaskType FOCUSED_MELEE_ATTACK */
#define FPC_ENGAGE_REACH_DM 30.0f   /* PT10: LMB gives the native attack order only within this (dm, centre to centre) */
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
/* logical FP buttons; the physical key of each comes from the F10 binds (defaults LMB, RMB, MMB, R, RMB) */
enum {FPC_LMB,FPC_RMB,FPC_MMB,FPC_R,FPC_INT,FPC_NBTN};
static const char *const g_fpc_btn_names[FPC_NBTN]={"lmb","rmb","mmb","r","interact"};
static double g_fpc_inj_until[FPC_NBTN];    /* harness press: held until this QPC ms */
static int g_fpc_prev[FPC_NBTN];
static double g_fpc_down_ms[FPC_NBTN];
static int g_fpc_native_frames[2], g_fpc_native_total[2];   /* fp_keys native: synthetic native flags (lmb, rmb) */
static int g_fpc_latch[2];                  /* swallowing a native press until its release */
static int g_fpc_fists;                     /* R toggled with nothing to draw: unarmed ready stance */
static void *g_fpc_hold_actor;
static int g_fpc_own_sheathe;
static int g_fpc_ctx_freed, g_fpc_ctx_relock;   /* context menu freed the cursor; relock countdown */
static int g_fpc_ctx_skip_rrel, g_fpc_ctx_hold_done;   /* PT06: menu opened on an RMB hold (its own release must not relock) */
static unsigned g_fpc_ctx_hold_opens, g_fpc_ctx_tap_opens;
static double g_fpc_ctx_ms;
static unsigned g_fpc_ctx_keep_frames;   /* PT06/PT20: frames the FP menu was kept open (RMB fed as held) */
static unsigned char (*fpc_ctl_getvis(void))(void *);
/* PT06/PT20 (m54): the game's ContextMenu::update (called at the end of playerControl) keeps the menu only while the
 * button that opened it is held: ContextMenu+0 = "opened with RMB held" (showContextMenu copies InputHandler mRight);
 * set -> hidden once mRight reads 0, clear -> hidden once mLeft reads 0. Vanilla = hold RMB, release over an option.
 * FP menus must stay open after the release until an option / Control / Esc / a click elsewhere, so the FP menu is
 * marked "RMB-opened" and, while it is visible and FP holds the freed cursor for it, playerControl sees RMB held
 * (no press/release edges: the game's own last-RMB byte, written next to the visible cache byte, is kept in step). */
static int fpc_ctx_menu_visible(void *pi) {
    unsigned char (*getvis)(void *)=fpc_ctl_getvis();
    if (!getvis || !readable(pi,FPC_PI_CTXMENU+0x50)) return 0;
    void *m=*(void **)((uintptr_t)pi+FPC_PI_CTXMENU+0x48);          /* ContextMenu::menuGUI (what isVisible reads) */
    if (!readable(m,0x10)) return 0;
    void *mw=*(void **)((uintptr_t)m+8);
    return readable(mw,8) && getvis(mw);
}
/* PT06/PT20 (m55: menu gone 1-2 frames after the FP open, ctx_keep stuck at 2). ContextMenu::showContextMenu(true)
 * (1.0.65 0x7a6020) rebuilds the menu, copies the live mRight into ContextMenu+0 and, with no selected character,
 * requests a hide (+0x58, applied by ContextMenu::update); vanilla PlayerInterface also re-shows the menu for the
 * hovered object after its own RMB-hold timer (0x80029d). While the FP menu is up, a game re-show is swallowed (FP
 * already opened it); a game hide (option click / order handlers) goes through and its caller is recorded. */
static fpc_ctxmenu_t g_fpc_ctx_orig;
static int g_fpc_ctx_own,g_fpc_ctx_hook_ok;
static unsigned g_fpc_ctx_game_shows,g_fpc_ctx_game_hides,g_fpc_ctx_reshow_blocked,g_fpc_ctx_closes;
static unsigned long long g_fpc_ctx_hide_rva,g_fpc_ctx_reshow_rva;
static const char *g_fpc_ctx_close_where="none";
static void fpc_ctxmenu_hook(void *cm,unsigned char show,void *obj) {
    if (!g_fpc_ctx_own && g_fp_mode && g_fpc_ctx_freed) {
        unsigned long long ra=(unsigned long long)((uintptr_t)__builtin_return_address(0)-g_base);
        void *pi=(void *)((uintptr_t)cm-FPC_PI_CTXMENU);
        if (show) {
            ++g_fpc_ctx_game_shows;g_fpc_ctx_reshow_rva=ra;
            if (fpc_ctx_menu_visible(pi)) {
                ++g_fpc_ctx_reshow_blocked;logline("[controls] ctx menu: game re-show swallowed (caller +0x%llx)",ra);return;
            }
        } else {++g_fpc_ctx_game_hides;g_fpc_ctx_hide_rva=ra;logline("[controls] ctx menu: game hide (caller +0x%llx)",ra);}
    }
    g_fpc_ctx_orig(cm,show,obj);
}
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
static unsigned g_fpc_mmb_objects,g_fpc_mmb_self;   /* PT08 object selects, PT19 miss -> controlled char */
static const char *g_fpc_r_path="none";   /* PT02: which lookup found the weapon R drew */
static unsigned g_fpc_lmb_squad_refused,g_fpc_lmb_far_refused;static float g_fpc_lmb_dist=-1;static const char *g_fpc_lmb_why="none";
static char g_fpc_last_select[48]="none", g_fpc_last_target[48]="none";
static const char *g_fpc_ui_state="off";
/* K06 (4080 b39): the controlled char's live weaponInHands (pc+0x6D8), read every tick; fp_combat's wih only
 * updates inside the ranged adapter, so melee draw/holster evidence comes from here. */
static void *g_fpc_wih;
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
    int vis_in=g_fpc_ctx_freed && fpc_ctx_menu_visible(pi);
    int keep=vis_in && g_fpc_swallow;                 /* PT06/PT20: FP menu stays open */
    unsigned char *cmb=(unsigned char *)((uintptr_t)pi+FPC_PI_CTXMENU);
    int flag0=readable(cmb,0x60)?cmb[0]:-1,req58=readable(cmb,0x60)?cmb[0x58]:-1;
    static int vis_out_prev;
    if (g_fpc_ctx_freed && vis_out_prev && !vis_in) {   /* closed between two playerControl calls */
        ++g_fpc_ctx_closes;g_fpc_ctx_close_where="outside_pc";
        logline("[controls] ctx menu closed outside playerControl (keep_frames=%u last_game_hide=+0x%llx)",g_fpc_ctx_keep_frames,g_fpc_ctx_hide_rva);
    }
    int clear[2];
    clear[1]=own || (g_fpc_ctx_freed && g_fpc_swallow);   /* RMB: never a native walk/menu in FP (PT21: also under the FP menu) */
    clear[0]=own;                                   /* PT07: LMB never selects in FP (drawn or holstered) */
    for (int b=0;b<2;++b) {
        int any=f[b]||f[2+b]||f[4+b]||f[6+b];
        if (clear[b] && (f[b]||f[4+b])) g_fpc_latch[b]=1;
        if ((clear[b]||g_fpc_latch[b]) && any) {
            f[b]=f[2+b]=f[4+b]=f[6+b]=0;
            if (b) ++g_fpc_rmb_swallowed; else ++g_fpc_lmb_swallowed;
        }
        if (!saved[b] && !saved[4+b]) g_fpc_latch[b]=0;
    }
    if (keep) {f[1]=f[3]=1;f[5]=f[7]=0;++g_fpc_ctx_keep_frames;if (flag0==0) cmb[0]=1;}   /* +0: RMB-opened (a re-show copies mRight) */
    if (keep || clear[1] || g_fpc_latch[1]) {                       /* playerControl's own last-RMB byte: no edges */
        unsigned char *lastr=RVA_CTXMENU_VISIBLE?(unsigned char *)(g_base+RVA_CTXMENU_VISIBLE+1):NULL;
        if (lastr && readable(lastr,1)) *lastr=f[1];
    }
    g_fpc_pc_orig(pi,ihp);
    memcpy(f,saved,8);                              /* other consumers see the real state */
    int vis_out=g_fpc_ctx_freed && fpc_ctx_menu_visible(pi);
    if (vis_in && !vis_out) {                        /* ContextMenu::update hid it */
        ++g_fpc_ctx_closes;g_fpc_ctx_close_where=req58==1?"pc_hide_request":keep?"pc_kept":"pc_button";
        logline("[controls] ctx menu closed in playerControl (%s) flag0=%d req58=%d keep=%d mR=%d mL=%d keep_frames=%u last_game_hide=+0x%llx",
                g_fpc_ctx_close_where,flag0,req58,keep,saved[1],saved[0],g_fpc_ctx_keep_frames,g_fpc_ctx_hide_rva);
    }
    vis_out_prev=vis_out;
}
/* InputHandler::keyDownEvent mouse codes ((btn+1)<<12: 0x1000 mouse_select, 0x2000 mouse_command, 0x3000
 * mouse_rotate) feed the vanilla command queue next to playerControl's flags. PT07/PT21 (Shay 2026-10-07): with a
 * squad mate selected the RMB command still gave her a move order and LMB still selected; FP owns all three while
 * it owns the cursor, and RMB also while the FP context menu holds the freed cursor (a second RMB = no order). */
static unsigned g_fpc_mouse_keys_swallowed;
static int fpc_mouse_key_swallow(int key) {
    if (key!=0x1000 && key!=0x2000 && key!=0x3000) return 0;
    if (!g_fp_mode || !g_fpc_hook_ok || !g_fpc_swallow) return 0;
    if (fpc_owns_mouse() || (key==0x2000 && g_fpc_ctx_freed)) {++g_fpc_mouse_keys_swallowed;return 1;}
    return 0;
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
/* keyPressed: every keyboard-bound FP button (draw = R by default, plus any attack/block/select/
 * interact rebound to a key) belongs to FP while it owns input, so a vanilla bind on the same key
 * never fires too (CS06: interact on ';' also ran Kenshi's toggle_fps_camera and dropped FP).
 * Mouse binds (VK < 8) have no DIK. */
static int fpc_key_is_bound(int vk,unsigned dik) {
    return vk>=8 && dik==MapVirtualKeyA((UINT)vk,0 /* MAPVK_VK_TO_VSC */);
}
static int fpc_key_bound_any(unsigned dik) {
    return dik && (fpc_key_is_bound(g_cfg_key_draw,dik) || fpc_key_is_bound(g_cfg_key_attack,dik) ||
        fpc_key_is_bound(g_cfg_key_block,dik) || fpc_key_is_bound(g_cfg_key_select,dik) ||
        fpc_key_is_bound(g_cfg_key_interact,dik));
}
/* also under the free cursor / a game panel (m51-F: ';' with free=1 reached toggle_fps_camera);
 * a focused text field or the F10 bind capture gets every key */
static int fpc_key_owned(unsigned dik) {
    if (!dik || !g_fp_mode || !g_fpc_hook_ok || g_ui_c_keyfocus || g_kb_cap>=0) return 0;
    return fpc_key_bound_any(dik);
}
static void fpc_key_note_swallow(unsigned dik) {
    ++g_fp_keys_swallowed;g_fp_last_swallow_dik=dik;g_fp_swallow_ms=GetTickCount();g_fp_swallow_seen=1;
}
static int fpc_key_swallow(unsigned dik) {
    if (!fpc_key_owned(dik)) return 0;
    if (fpc_key_is_bound(g_cfg_key_draw,dik)) ++g_fpc_r_keys_swallowed;
    fpc_key_note_swallow(dik);return 1;
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
/* K02 (4080 b37): last crosshair pick, for `fp_keys pick` and the MMB-none log line. */
static struct { unsigned n; int aim_ok, have_t, have_eye, anchor, ogre, kept, dropped; CombatRayHit hit; Vec3 aim, origin, dir;
                char name[64]; double ms; } g_fpc_pick;
static int g_fpc_pick_req;
static size_t fpc_pick_text(char *b,size_t n) {
    return (size_t)snprintf(b,n,"pick n=%u age_ms=%.0f result=%s aim_ok=%d have_t=%d eye=%d anchor=%d ogre=%d shape=%p ids0=%u "
        "hit_dist=%.2f hit=%.1f,%.1f,%.1f aim=%.1f,%.1f,%.1f origin=%.1f,%.1f,%.1f dir=%.3f,%.3f,%.3f mesh_kept=%d mesh_dropped=%d self_skips=%u",
        g_fpc_pick.n,g_fpc_pick.n?fpc_now_ms()-g_fpc_pick.ms:-1.0,g_fpc_pick.name,g_fpc_pick.aim_ok,g_fpc_pick.have_t,g_fpc_pick.have_eye,
        g_fpc_pick.anchor,g_fpc_pick.ogre,(void *)g_fpc_pick.hit.shape,g_fpc_pick.hit.ids[0],g_fpc_pick.hit.distance,
        g_fpc_pick.hit.position.x,g_fpc_pick.hit.position.y,g_fpc_pick.hit.position.z,g_fpc_pick.aim.x,g_fpc_pick.aim.y,g_fpc_pick.aim.z,
        g_fpc_pick.origin.x,g_fpc_pick.origin.y,g_fpc_pick.origin.z,g_fpc_pick.dir.x,g_fpc_pick.dir.y,g_fpc_pick.dir.z,
        g_fpc_pick.kept,g_fpc_pick.dropped,g_combat_aim_self_skips);
}
/* Character under the crosshair (physics ray, mesh refine), without disturbing the shot telemetry. */
static void *fpc_player_interface(void *gw);
static void *fpc_crosshair_char(void *pc) {
    CombatRayHit saved_hit=g_combat_camera_hit;
    Vec3 so=g_combat_aim_origin,sd=g_combat_aim_dir;int sh=g_combat_aim_have_ray;
    unsigned sk=g_combat_aim_attr_kept,sdr=g_combat_aim_attr_dropped;
    void *saved_node=g_mr_perch_node;mr_cache_t *saved_cache=g_mr_perch_cache;
    Vec3 aim={0,0,0};void *t=NULL;
    int aim_ok=combat_camera_aim(&aim);
    if (aim_ok && g_combat_camera_hit.shape) t=combat_ray_target(&g_combat_camera_hit,pc);
    ++g_fpc_pick.n;g_fpc_pick.ms=fpc_now_ms();g_fpc_pick.aim_ok=aim_ok;g_fpc_pick.have_t=g_have_t;g_fpc_pick.have_eye=g_have_eye;
    g_fpc_pick.anchor=g_view_have_anchor;g_fpc_pick.ogre=g_ogre_ready;g_fpc_pick.hit=g_combat_camera_hit;g_fpc_pick.aim=aim;
    g_fpc_pick.origin=g_combat_aim_origin;g_fpc_pick.dir=g_combat_aim_dir;
    g_fpc_pick.kept=(int)(g_combat_aim_attr_kept-sk);g_fpc_pick.dropped=(int)(g_combat_aim_attr_dropped-sdr);
    if (t) fpc_name(t,g_fpc_pick.name,sizeof g_fpc_pick.name); else strcpy(g_fpc_pick.name,"none");
    g_mr_perch_node=saved_node;g_mr_perch_cache=saved_cache;
    g_combat_camera_hit=saved_hit;g_combat_aim_origin=so;g_combat_aim_dir=sd;g_combat_aim_have_ray=sh;
    g_combat_aim_attr_kept=sk;g_combat_aim_attr_dropped=sdr;
    return t;
}
/* PT08: the non-character object of the last pick (building, item), NULL if none. */
static void *fpc_pick_object(void) {
    return g_fpc_pick.aim_ok?combat_hit_root(&g_fpc_pick.hit):NULL;
}
static void *fpc_player_interface(void *gw) {
    return readable((void *)((uintptr_t)gw+GW_PLAYER),8)?*(void **)((uintptr_t)gw+GW_PLAYER):NULL;
}
/* fp_keys movers (C04-FALLBACK NATDIAG, 4080 b33/b40: native walk orders never started for the mate AND the player,
 * also with FP off): per squad member, the CharMovement state a native MOVE order needs (movementMode 0 normal /
 * 1 combat / 2 MOVE_DIRECTION, speedOrders, current speed/motion, desired motion, animationOverride) and whether
 * KenshiFP still holds that mover (dm = WASD drive mover g_dm_mv, dm_active, melee = manual-melee owned mover,
 * ctl = FP controlled actor). Built on the game thread (request -> next tick), shown by the command. */
static int g_fpc_movers_req;static unsigned g_fpc_movers_n;static char g_fpc_movers_txt[1400]="none";
static void fpc_movers_snapshot(void *gw) {
    size_t o=0;char *b=g_fpc_movers_txt;size_t n=sizeof g_fpc_movers_txt;b[0]=0;
    void *pi=fpc_player_interface(gw);
    if (!readable(pi,PI_PLAYERCHARS+LEK_STUFF+8)) {snprintf(b,n,"no player interface");return;}
    uint32_t count=*(uint32_t *)((uintptr_t)pi+PI_PLAYERCHARS+LEK_COUNT);
    void **chars=*(void ***)((uintptr_t)pi+PI_PLAYERCHARS+LEK_STUFF);
    if (!count || count>64 || !readable(chars,(size_t)count*8)) {snprintf(b,n,"no squad (count=%u)",count);return;}
    ++g_fpc_movers_n;
    o+=(size_t)snprintf(b+o,n-o,"movers n=%u fp=%d dm_active=%d",g_fpc_movers_n,!!g_fp_mode,(int)g_dm_active);
    for (uint32_t i=0;i<count && o+8<n;++i) {
        void *pc=chars[i];char nm[48];
        if (!char_valid(pc)) continue;
        fpc_name(pc,nm,sizeof nm);
        void *mv=readable((void *)((uintptr_t)pc+CHAR_MOVEMENT),8)?*(void **)((uintptr_t)pc+CHAR_MOVEMENT):NULL;
        if (!readable(mv,0x3B0)) {o+=(size_t)snprintf(b+o,n-o," | %s mv=none",nm);continue;}
        const Vec3 *cm=(const Vec3 *)((uintptr_t)mv+MV_CURRENT_MOTION),*dm=(const Vec3 *)((uintptr_t)mv+0x38C);
        o+=(size_t)snprintf(b+o,n-o," | %s mode=%d speed_orders=%d cur_speed=%.2f cur_motion=%.2f desired=%.2f anim_override=%d dm=%d melee=%d ctl=%d",
            nm,*(int *)((uintptr_t)mv+0x378),*(int *)((uintptr_t)mv+0x20),*(float *)((uintptr_t)mv+MV_CURRENT_SPEED),
            sqrtf(cm->x*cm->x+cm->z*cm->z),sqrtf(dm->x*dm->x+dm->z*dm->z),*(unsigned char *)((uintptr_t)mv+0x37C),
            mv==g_dm_mv,mv==g_melee_owned_mv,pc==g_fp_control_actor);
        if (o>=n) {o=n-1;break;}
    }
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
    /* PT02 (Shay 2026-10-07, Full-Base Beaks with a sword: "R ready (unarmed)"): getThePreferredWeapon can answer
     * NULL out of combat; fall back to the equipped primary/secondary weapon (Inventory, Character+0x2E8), then the
     * ranged weapon, before going unarmed. g_fpc_r_path names the path that found it. */
    static void *(*inv_primary)(void *),*(*inv_secondary)(void *);static int inv_res;
    if (!inv_res) {inv_res=1;
        inv_primary=(void *(*)(void *))fpc_klib("?getPrimaryWeapon@Inventory@@QEAAPEAVWeapon@@XZ");
        inv_secondary=(void *(*)(void *))fpc_klib("?getSecondaryWeapon@Inventory@@QEAAPEAVWeapon@@XZ");}
    const char *path="preferred";
    void *w=((void *(*)(void *))vt[0x3C8/8])(pc);
    void *inv=readable((void *)((uintptr_t)pc+0x2E8),8)?*(void **)((uintptr_t)pc+0x2E8):NULL;
    if (!w && inv_primary && readable(inv,8)) {w=inv_primary(inv);path="primary";}
    if (!w && inv_secondary && readable(inv,8)) {w=inv_secondary(inv);path="secondary";}
    if (!w && readable((void *)((uintptr_t)vt+0x3D0),8)) {w=((void *(*)(void *))vt[0x3D0/8])(pc);path="ranged";}
    if (!w) {g_fpc_fists=1;g_fpc_hold_actor=pc;++g_fpc_r_draws;g_fpc_r_path="unarmed";
             logline("[controls] R ready (unarmed) inv=%p primary=%d secondary=%d",inv,inv_primary!=NULL,inv_secondary!=NULL);return;}
    g_fpc_r_path=path;
    /* PT14 (4080 m53): drawWeapon(item, lastSection) with "" set weaponInHands but left the melee mesh on the
     * hip sheath (hand empty in FP and TP). Pass the item's own section (Item::inventorySection @0xE8, e.g.
     * "hip"/"back"), as the native draw does. */
    char sec[32]="";const unsigned char *ss=(const unsigned char *)((uintptr_t)w+0xE8);
    if (readable((void *)ss,32)) {size_t sl=*(size_t *)(ss+0x10),cap=*(size_t *)(ss+0x18);
        const char *sp=cap>15?(readable(*(void **)ss,1)?*(const char **)ss:NULL):(const char *)ss;
        if (sp && sl<sizeof sec) {memcpy(sec,sp,sl);sec[sl]=0;}}
    unsigned char secs[32];
    if (strlen(sec)>15) make_mstr_long(secs,sec); else make_mstr(secs,sec);
    char ok=((char (*)(void *,void *,void *))vt[0x3D8/8])(pc,w,secs);
    g_fpc_hold_actor=pc;++g_fpc_r_draws;logline("[controls] R draw weapon %p path=%s section='%s' ok=%d",w,path,sec,(int)ok);
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

/* FP stealth attack (Shay: stealth attacks right after the controls rework). Sneaking + LMB drawn (melee) on a
 * character that does not perceive the attacker (SensoryData::amIAwareOfThisGuy(attacker, needToSeeOrHear=1) == 0)
 * = the game's own sneak knockout: the same order the vanilla sneak-mode click gives (TaskType STEALTH_KNOCKOUT 228:
 * walk up, Character::getStealthKOChance roll, EV_ASSASSINATION_FAILED on a miss). Aware (or unreadable) target =
 * the normal LMB engage. Each sneak LMB logs `[controls] LMB sneak=1 target=.. target_aware=.. path=..`; the attempt
 * is watched until the target is KO/dead, fights back (failed) or FPC_SNEAK_WATCH_MS passes: `[controls] sneak result=..`. */
#define FPC_TASK_STEALTH_KO 228
#define FPC_SNEAK_WATCH_MS 25000.0
#define FPC_SYM_SENSORY "?_NV_getSensoryData@Character@@QEAAPEAVSensoryData@@XZ"
#define FPC_SYM_AWARE "?amIAwareOfThisGuy@SensoryData@@QEAA_NPEAVCharacter@@_N@Z"
#define FPC_SYM_KOCHANCE "?getStealthKOChance@Character@@QEAAMPEAV1@_N@Z"
#define FPC_SYM_UNCON "?_NV_isUnconcious@Character@@QEBA_NXZ"
#define FPC_SYM_DEAD "?isDead@Character@@QEBA_NXZ"
typedef void *(*fpc_sensory_t)(void *pc);
typedef unsigned char (*fpc_aware_t)(void *sd,void *who,unsigned char need);
typedef float (*fpc_kochance_t)(void *pc,void *victim,unsigned char factors);
typedef unsigned char (*fpc_cbool_t)(void *pc);
static fpc_sensory_t g_fpc_sensory;static fpc_aware_t g_fpc_aware;static fpc_kochance_t g_fpc_kochance;
static fpc_cbool_t g_fpc_uncon,g_fpc_dead;
static unsigned g_fpc_sneak_clicks,g_fpc_sneak_attacks,g_fpc_sneak_ko,g_fpc_sneak_failed,g_fpc_sneak_timeout;
static const char *g_fpc_sneak_path="none",*g_fpc_sneak_result="none";
static int g_fpc_sneak_now,g_fpc_sneak_aware=-1,g_fpc_sneak_aware_any=-1;
static float g_fpc_sneak_chance=-1.0f;
static char g_fpc_sneak_target[48]="none";
static void *g_fpc_sneak_pc,*g_fpc_sneak_t;static double g_fpc_sneak_ms,g_fpc_sneak_elapsed;
static int g_fpc_sneak_req;   /* fp_keys sneak: probe the crosshair target next tick */
/* hostile = PlayerInterface::isEnemy on the probed target, the same test fpc_engage uses to pick the attack task
 * (5090 m50 N ST02: an aware target answered task 5 instead of 61 -> the test checks hostile=0 before the click) */
/* enemy_tp / enemy_pt = Character::isEnemy (vt+0x3E8, factorInDisguises 0) target->player / player->target: which side
 * makes PlayerInterface::isEnemy say enemy (4080 b43: fresh Tech Hunters spawn hostile=1 at relation 20, faction enemy=0) */
static struct { unsigned n; int stealth,aware,aware_any,hostile,enemy_tp,enemy_pt; float chance; char name[48]; } g_fpc_sneak_probe;
static int fpc_char_isenemy(void *a,void *b) {
    void **vt=char_valid(a)&&char_valid(b)?*(void ***)a:NULL;
    if (!readable(vt,0x3F0)||!vt[0x3E8/8]) return -1;
    return ((unsigned char (*)(void *,void *,unsigned char))vt[0x3E8/8])(a,b,0)!=0;
}
static int fpc_is_sneaking(void *pc) {
    return readable((void *)((uintptr_t)pc+CHAR_STEALTH_MODE),1) && *(unsigned char *)((uintptr_t)pc+CHAR_STEALTH_MODE);
}
/* t perceives who: need=1 sees/hears him now, need=0 also aware from memory; -1 = not readable */
static int fpc_target_aware(void *t,void *who,int need) {
    void *sd=g_fpc_sensory&&g_fpc_aware&&char_valid(t)?g_fpc_sensory(t):NULL;
    if (!readable(sd,8)) return -1;
    return g_fpc_aware(sd,who,(unsigned char)need)!=0;
}
static void fpc_sneak_click(void *gw,void *pc,void *t) {
    int aware=fpc_target_aware(t,pc,1),any=fpc_target_aware(t,pc,0);
    float ch=g_fpc_kochance?g_fpc_kochance(pc,t,1):-1.0f;
    ++g_fpc_sneak_clicks;fpc_name(t,g_fpc_sneak_target,sizeof g_fpc_sneak_target);
    g_fpc_sneak_aware=aware;g_fpc_sneak_aware_any=any;g_fpc_sneak_chance=ch;
    int task=-1;
    if (aware==0 && g_fpc_addorder) {
        Vec3 pos={0,0,0};char_position(t,&pos);
        g_fpc_addorder(pc,NULL,FPC_TASK_STEALTH_KO,t,0,1,&pos);
        task=FPC_TASK_STEALTH_KO;g_fpc_last_task=task;strcpy(g_fpc_last_target,g_fpc_sneak_target);
        g_fpc_sneak_path="vanilla_sneak";g_fpc_sneak_result="pending";g_fpc_sneak_pc=pc;g_fpc_sneak_t=t;
        g_fpc_sneak_ms=fpc_now_ms();g_fpc_sneak_elapsed=0;++g_fpc_sneak_attacks;
    } else {
        g_fpc_sneak_path=aware<0?"engage_unread":"engage_aware";
        fpc_engage(gw,pc,t,0);task=g_fpc_last_task;
    }
    logline("[controls] LMB sneak=1 target=%s target_aware=%d aware_any=%d ko_chance=%.3f path=%s task=%d",
        g_fpc_sneak_target,aware,any,ch,g_fpc_sneak_path,task);
}
/* the pending sneak knockout: KO/dead target, a fight back on the attacker (failed) or the watch window */
static void fpc_sneak_watch(void) {
    void *t=g_fpc_sneak_t;const char *res=NULL;
    if (!t) return;
    g_fpc_sneak_elapsed=fpc_now_ms()-g_fpc_sneak_ms;
    if (!char_valid(t)) res="lost";
    else if (g_fpc_dead && g_fpc_dead(t)) res="dead";
    else if (g_fpc_uncon && g_fpc_uncon(t)) res="ko";
    else {
        void *cc=g_melee_get_combat?g_melee_get_combat(t):NULL;
        int fights=readable(cc,0x2b8) && *(unsigned char *)((uintptr_t)cc+CC_ACTIVE) && *(void **)((uintptr_t)cc+CC_TARGET)==g_fpc_sneak_pc;
        if (fights) res="failed";
        else if (g_fpc_sneak_elapsed>FPC_SNEAK_WATCH_MS) res="timeout";
    }
    if (!res) return;
    g_fpc_sneak_result=res;
    if (!strcmp(res,"ko")||!strcmp(res,"dead")) ++g_fpc_sneak_ko; else if (!strcmp(res,"failed")) ++g_fpc_sneak_failed; else ++g_fpc_sneak_timeout;
    logline("[controls] sneak result=%s target=%s elapsed_ms=%.0f target_aware_now=%d ko_chance=%.3f",
        res,g_fpc_sneak_target,g_fpc_sneak_elapsed,char_valid(t)?fpc_target_aware(t,g_fpc_sneak_pc,1):-1,g_fpc_sneak_chance);
    g_fpc_sneak_t=NULL;g_fpc_sneak_pc=NULL;
}
static void fpc_sneak_probe(void *pc) {
    void *t=fpc_crosshair_char(pc);
    ++g_fpc_sneak_probe.n;g_fpc_sneak_probe.stealth=fpc_is_sneaking(pc);
    g_fpc_sneak_probe.aware=t?fpc_target_aware(t,pc,1):-1;g_fpc_sneak_probe.aware_any=t?fpc_target_aware(t,pc,0):-1;
    g_fpc_sneak_probe.chance=t&&g_fpc_kochance?g_fpc_kochance(pc,t,1):-1.0f;
    {   void *pi=fpc_player_interface(g_gw_cache);
        g_fpc_sneak_probe.hostile=t&&pi&&g_fpc_isenemy?g_fpc_isenemy(pi,t)!=0:-1; }
    g_fpc_sneak_probe.enemy_tp=t?fpc_char_isenemy(t,pc):-1;g_fpc_sneak_probe.enemy_pt=t?fpc_char_isenemy(pc,t):-1;
    if (t) fpc_name(t,g_fpc_sneak_probe.name,sizeof g_fpc_sneak_probe.name); else strcpy(g_fpc_sneak_probe.name,"none");
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
        /* HUD01 (4080 b39): out of ranged combat with the adapter off nothing runs the native reload, so the
         * timer (rc+0x78) sits frozen above 0 (0.0712 for minutes) and the HUD said RELOADING while aiming.
         * Reloading = the timer is above 0 AND moved within the last 400 ms (or the adapter reloads). */
        static void *trc;static float tval=-1;static double tms;
        if (readable(rc,0x88)) {
            float t=*(float *)((uintptr_t)rc+0x78);double now=fpc_now_ms();
            if (rc!=trc || t!=tval) {if (rc==trc) tms=now; else tms=0;trc=rc;tval=t;}
            if (t>0.0f && now-tms<400.0) return "reloading";
        }
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
    const int vk[FPC_NBTN]={g_cfg_key_attack,g_cfg_key_block,g_cfg_key_select,g_cfg_key_draw,g_cfg_key_interact};
    int phys=phys_ok && (GetAsyncKeyState(vk[b])&0x8000)!=0;
    return phys || fpc_now_ms()<g_fpc_inj_until[b];
}
static void fpc_release_all(void) {
    if (g_fpc_ctx_freed) {g_free_toggle=0;g_fpc_ctx_freed=0;}
    g_fpc_ctx_skip_rrel=0;g_fpc_ctx_hold_done=0;
    g_fpc_hold_actor=NULL;g_fpc_fists=0;g_fpc_fs_tech=NULL;g_fpc_fs_anim=NULL;
    for (int b=0;b<FPC_NBTN;++b) {g_fpc_prev[b]=0;g_fpc_input[b]=0;}
}
/* Context menu freed the cursor: relock on the next click release (option picked / dismissed) or Esc. */
static void fpc_ctx_relock_step(void) {
    if (!g_fpc_ctx_freed) return;
    if (g_fpc_ctx_relock>0) {if (--g_fpc_ctx_relock==0) {g_free_toggle=0;g_fpc_ctx_freed=0;}return;}
    static int lp,rp;static double seen_ms;
    int l=(GetAsyncKeyState(VK_LBUTTON)&0x8000)!=0,r=(GetAsyncKeyState(VK_RBUTTON)&0x8000)!=0,esc=(GetAsyncKeyState(VK_ESCAPE)&0x8000)!=0;
    r=r||fpc_now_ms()<g_fpc_inj_until[FPC_RMB];      /* harness-held RMB counts as held */
    if (seen_ms!=g_fpc_ctx_ms) {seen_ms=g_fpc_ctx_ms;lp=l;rp=r;}   /* a new menu: no stale edges from before it */
    /* PT06: a menu opened on an RMB hold: that hold's own release only arms the relock for the next click */
    if (g_fpc_ctx_skip_rrel && !r) {g_fpc_ctx_skip_rrel=0;rp=0;}
    if (fpc_now_ms()-g_fpc_ctx_ms>250.0 && ((lp&&!l)||(rp&&!r&&!g_fpc_ctx_skip_rrel)||esc)) g_fpc_ctx_relock=3;
    if (!g_free_toggle) g_fpc_ctx_freed=0;          /* the player relocked (free-cursor key) */
    lp=l;rp=r;
}
static void fp_controls_tick(void *gw,float dt) {
    (void)dt;++g_fpc_ticks;
    static void *last_actor;
    if (g_fpc_movers_req) {g_fpc_movers_req=0;fpc_movers_snapshot(gw);}   /* fp_keys movers (test), also with FP off */
    if (!g_fp_mode || g_fpc_fault) {
        if (last_actor) fpc_release_all();
        last_actor=NULL;g_fpc_ui_state="off";g_fpc_drawn=0;g_fpc_wih=NULL;return;
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
    if (!char_valid(pc)) {g_guard_armed=0;g_fpc_ui_state="none";g_fpc_wih=NULL;return;}
    if (g_is_down && g_fpc_hold_actor) {g_fpc_hold_actor=NULL;g_fpc_fists=0;}
    fpc_ctx_relock_step();
    void *wih=readable((void *)((uintptr_t)pc+CHAR_WEAPON_IN_HANDS),8)?*(void **)((uintptr_t)pc+CHAR_WEAPON_IN_HANDS):NULL;
    void *ranged=combat_virtual(pc,0x3d0);
    /* PT11/PT12: "ranged" = the ranged weapon is the one in hands, not merely carried (a drawn sword with a
     * crossbow on the back is melee: LMB swings, RMB blocks) */
    void *rw=ranged?((void *(*)(void *))ranged)(pc):NULL;
    g_fpc_ranged=rw!=NULL && wih==rw;
    g_fpc_drawn=wih!=NULL||g_fpc_fists;g_fpc_wih=wih;
    int phys_ok=g_cursor_hidden && !g_ui_open && game_has_focus();
    int in[FPC_NBTN],edge[FPC_NBTN],rel[FPC_NBTN];
    double now=fpc_now_ms();
    for (int b=0;b<FPC_NBTN;++b) {
        in[b]=!g_ui_open && fpc_button(b,phys_ok);
        edge[b]=in[b]&&!g_fpc_prev[b];rel[b]=!in[b]&&g_fpc_prev[b];
        if (edge[b]) g_fpc_down_ms[b]=now;
        g_fpc_prev[b]=in[b];g_fpc_input[b]=in[b];
    }
    if (g_fpc_pick_req && pc) {g_fpc_pick_req=0;fpc_crosshair_char(pc);}   /* fp_keys pick (test) */
    g_fpc_sneak_now=fpc_is_sneaking(pc);
    if (g_fpc_sneak_req) {g_fpc_sneak_req=0;fpc_sneak_probe(pc);}           /* fp_keys sneak (test) */
    if (!g_is_down && g_fpc_hook_ok) {
        if (edge[FPC_R]) fpc_draw_toggle(pc);   /* PT18: R only draws/holsters, also with RMB held */
        /* MMB: the character under the crosshair, else (PT08) the building/object, else (PT19) the selection goes
         * back to the controlled char (ground/sky = clear an NPC selection) */
        if (edge[FPC_MMB] && g_fpc_select) {
            void *t=fpc_crosshair_char(pc);
            void *obj=t?NULL:fpc_pick_object();
            if (t) {g_fpc_select(fpc_player_interface(gw),t,0);++g_fpc_mmb_selects;fpc_name(t,g_fpc_last_select,sizeof g_fpc_last_select);
                    logline("[controls] MMB select %s",g_fpc_last_select);}
            else if (obj) {g_fpc_select(fpc_player_interface(gw),obj,0);++g_fpc_mmb_selects;++g_fpc_mmb_objects;
                    fpc_name(obj,g_fpc_last_select,sizeof g_fpc_last_select);
                    logline("[controls] MMB select object %s type=%u",g_fpc_last_select,g_fpc_pick.hit.ids[0]);}
            else {++g_fpc_mmb_none;++g_fpc_mmb_self;g_fpc_select(fpc_player_interface(gw),pc,0);
                  fpc_name(pc,g_fpc_last_select,sizeof g_fpc_last_select);
                  char pb[512];fpc_pick_text(pb,sizeof pb);
                  logline("[controls] MMB select: nothing under the crosshair -> selected the controlled char %s (%s)",g_fpc_last_select,pb);}
        }
        /* interact on the block key while holstered: a tap opens the menu on release, a hold opens it once
         * FPC_MENU_CLICK_MS in (PT06, Shay 2026-10-07: hold-RMB menu like vanilla; drawn = block); its own key = on press */
        int ctx=0,hold_open=0;
        if (g_cfg_key_interact==g_cfg_key_block) {
            if (edge[FPC_RMB]) g_fpc_ctx_hold_done=0;
            if (!g_fpc_drawn && !g_fpc_ctx_freed) {
                if (rel[FPC_RMB] && !g_fpc_ctx_hold_done && now-g_fpc_down_ms[FPC_RMB]<FPC_MENU_CLICK_MS) ctx=1;
                else if (in[FPC_RMB] && !g_fpc_ctx_hold_done && now-g_fpc_down_ms[FPC_RMB]>=FPC_MENU_CLICK_MS) {ctx=1;hold_open=1;}
            }
            if (in[FPC_RMB] && now-g_fpc_down_ms[FPC_RMB]>=FPC_MENU_CLICK_MS) g_fpc_ctx_hold_done=1;   /* one try per hold */
        } else ctx=edge[FPC_INT];
        if (ctx && g_fpc_ctxmenu) {
            void *t=fpc_crosshair_char(pc);
            if (!t) t=fpc_pick_object();                    /* PT08: buildings/objects get their menu too */
            void *pi=fpc_player_interface(gw);
            if (t && readable(pi,FPC_PI_CTXMENU+8)) {
                g_fpc_ctx_own=1;g_fpc_ctxmenu((void *)((uintptr_t)pi+FPC_PI_CTXMENU),1,t);g_fpc_ctx_own=0;++g_fpc_ctx_opens;
                *(unsigned char *)((uintptr_t)pi+FPC_PI_CTXMENU)=1;   /* PT06/PT20: RMB-opened (kept while fed held) */
                g_free_toggle=1;g_fpc_ctx_freed=1;g_fpc_ctx_relock=0;g_fpc_ctx_ms=now;g_fpc_ctx_skip_rrel=hold_open;
                if (hold_open) ++g_fpc_ctx_hold_opens; else ++g_fpc_ctx_tap_opens;
                fpc_name(t,g_fpc_last_target,sizeof g_fpc_last_target);
                logline("[controls] RMB context menu %s via=%s",g_fpc_last_target,hold_open?"hold":"tap");
            } else ++g_fpc_ctx_none;
        }
        /* PT10 (Shay 2026-10-07): LMB swings; it gives the native attack order only to a non-squad character within
         * melee reach (a far NPC facing away used to turn and fight; a squad mate under the crosshair started a
         * fight). Ranged in hands: the adapter's manual shot only, never a ranged attack order. */
        if (g_fpc_drawn && !g_fpc_ranged && edge[FPC_LMB] && !in[FPC_RMB]) {
            ++g_fpc_lmb_clicks;
            void *t=fpc_crosshair_char(pc);
            const char *why="engage";
            if (t && fp_char_in_squad(gw,t)) {t=NULL;why="squad";++g_fpc_lmb_squad_refused;}
            else if (t) {
                Vec3 a={0,0,0},b={0,0,0};
                if (!char_position(pc,&a) || !char_position(t,&b)) {t=NULL;why="no_pos";}
                else {float dx=a.x-b.x,dz=a.z-b.z;g_fpc_lmb_dist=sqrtf(dx*dx+dz*dz);
                      if (!(g_fpc_lmb_dist<=FPC_ENGAGE_REACH_DM)) {t=NULL;why="far";++g_fpc_lmb_far_refused;}}
            }
            g_fpc_lmb_why=why;
            if (t && g_fpc_sneak_now) fpc_sneak_click(gw,pc,t);   /* sneak: vanilla knockout if unaware */
            else if (t) fpc_engage(gw,pc,t,0);
            else if (!fpc_in_fight(pc)) {phase=1;fpc_free_swing(pc);phase=0;}
            if (strcmp(why,"engage")) logline("[controls] LMB no engage (%s dist=%.1f): free swing",why,g_fpc_lmb_dist);
        }
        if (g_fpc_fs_tech) {phase=1;fpc_free_swing_step(pc);phase=0;}
        if (g_fpc_drawn && !g_fpc_ranged && in[FPC_RMB]) fpc_free_block(pc);
    }
    fpc_sneak_watch();
    g_fpc_ui_state=fpc_ui_state(pc,in[FPC_RMB]);
    g_guard_armed=0;
}
static unsigned g_fpc_hud_flashes,g_fpc_hud_silent;   /* PT01/PT03 */
static void *g_fpc_hud;static const char *g_fpc_hud_text;static int g_fpc_hud_shown;static unsigned g_fpc_hud_changes;
/* HUD01 (4080 b41): a free swing (~0.5 s) ends between two harness polls (~0.6 s each), so the live hud_text
 * never read SWINGING. hud_hist = the last 8 captions the HUD widget was really set to, "<hud_changes>:<state>"
 * (sequence = g_fpc_hud_changes after that change), so a test can prove what the HUD showed after an input. */
#define FPC_HUD_HIST 8
static const char *g_fpc_hud_hist[FPC_HUD_HIST];static unsigned g_fpc_hud_hist_seq[FPC_HUD_HIST];
static void fpc_hud_hist_text(char *b,size_t n) {
    size_t o=0;b[0]=0;
    unsigned last=g_fpc_hud_changes,first=last>FPC_HUD_HIST?last-FPC_HUD_HIST+1:1;
    for (unsigned q=first;q && q<=last && o+1<n;++q) {
        unsigned i=q%FPC_HUD_HIST;if (g_fpc_hud_hist_seq[i]!=q || !g_fpc_hud_hist[i]) continue;
        int w=snprintf(b+o,n-o,"%s%u:%s",o?",":"",q,g_fpc_hud_hist[i]);if (w<0) break;o+=(size_t)w;
    }
    if (!b[0]) snprintf(b,n,"none");
}
static size_t fpc_state(char *b,size_t n) {
    char hh[200];fpc_hud_hist_text(hh,sizeof hh);
    return (size_t)snprintf(b,n,"hook=%d fault=%d swallow=%d fp=%d drawn=%d wih=%llx ranged=%d fists=%d hold=%d ui_state=%s in=%d%d%d%d "
        "mmb_selects=%u mmb_none=%u last_select=%s ctx_opens=%u ctx_none=%u ctx_freed=%d rmb_swallowed=%u lmb_swallowed=%u "
        "mmb_cam_frames=%u r_keys=%u r_draws=%u r_holsters=%u r_draw_fail=%u sheathe_kept=%u lmb_clicks=%u engages=%u last_task=%d last_target=%s "
        "free_swings=%u fs_active=%d fs_prog=%.3f fs_prog_max=%.3f fs_ends=%u fs_notech=%u fs_faults=%u fs_dead=%d "
        "free_block_frames=%u block_checks=%u native_injected=%u ticks=%u hud=%d hud_shown=%d hud_text=%s hud_changes=%u test_focus=%d "
        "sneak=%d sneak_clicks=%u sneak_attacks=%u sneak_ko=%u sneak_failed=%u sneak_timeout=%u sneak_path=%s sneak_target=%s "
        "sneak_aware=%d sneak_aware_any=%d sneak_chance=%.3f sneak_result=%s sneak_elapsed_ms=%.0f hud_hist=%s mouse_keys_swallowed=%u ctx_hold_opens=%u ctx_tap_opens=%u lmb_why=%s lmb_dist=%.1f lmb_squad_refused=%u lmb_far_refused=%u r_path=%s mmb_objects=%u mmb_self=%u hud_flashes=%u hud_silent=%u carried=%d down=%d speed_changes=%u speed_long_frames=%u speed_clicks=%u speed_peak_click=%.2f speed_now=%.2f ctx_keep=%u ctx_hook=%d ctx_game_shows=%u ctx_game_hides=%u ctx_reshow_blocked=%u ctx_closes=%u ctx_close_where=%s ctx_hide_rva=0x%llx ctx_reshow_rva=0x%llx",
        g_fpc_hook_ok,g_fpc_fault,g_fpc_swallow,g_fp_mode,g_fpc_drawn,(unsigned long long)(uintptr_t)g_fpc_wih,g_fpc_ranged,g_fpc_fists,g_fpc_hold_actor!=NULL,g_fpc_ui_state,
        g_fpc_input[0],g_fpc_input[1],g_fpc_input[2],g_fpc_input[3],
        g_fpc_mmb_selects,g_fpc_mmb_none,g_fpc_last_select,g_fpc_ctx_opens,g_fpc_ctx_none,g_fpc_ctx_freed,g_fpc_rmb_swallowed,g_fpc_lmb_swallowed,
        g_fpc_mmb_cam_frames,g_fpc_r_keys_swallowed,g_fpc_r_draws,g_fpc_r_holsters,g_fpc_r_draw_fail,g_fpc_sheathe_kept,g_fpc_lmb_clicks,g_fpc_engages,g_fpc_last_task,g_fpc_last_target,
        g_fpc_free_swings,g_fpc_fs_tech!=NULL,g_fpc_fs_prog,g_fpc_fs_prog_max,g_fpc_fs_ends,g_fpc_fs_notech,g_fpc_fs_faults,g_fpc_fs_dead,
        g_fpc_free_block_frames,g_fpc_block_checks,g_fpc_native_injected,g_fpc_ticks,
        g_fpc_hud!=NULL,g_fpc_hud_shown,g_fpc_hud_text?g_fpc_hud_text:"none",g_fpc_hud_changes,g_test_focus,
        g_fpc_sneak_now,g_fpc_sneak_clicks,g_fpc_sneak_attacks,g_fpc_sneak_ko,g_fpc_sneak_failed,g_fpc_sneak_timeout,g_fpc_sneak_path,
        g_fpc_sneak_target,g_fpc_sneak_aware,g_fpc_sneak_aware_any,g_fpc_sneak_chance,g_fpc_sneak_result,g_fpc_sneak_elapsed,hh,g_fpc_mouse_keys_swallowed,g_fpc_ctx_hold_opens,g_fpc_ctx_tap_opens,g_fpc_lmb_why,g_fpc_lmb_dist,g_fpc_lmb_squad_refused,g_fpc_lmb_far_refused,g_fpc_r_path,g_fpc_mmb_objects,g_fpc_mmb_self,g_fpc_hud_flashes,g_fpc_hud_silent,g_fp_carried,g_is_down,g_spd_changes,g_spd_long_frames,g_spd_clicks,g_spd_peak_click,g_spd_last,g_fpc_ctx_keep_frames,
        g_fpc_ctx_hook_ok,g_fpc_ctx_game_shows,g_fpc_ctx_game_hides,g_fpc_ctx_reshow_blocked,g_fpc_ctx_closes,g_fpc_ctx_close_where,
        g_fpc_ctx_hide_rva,g_fpc_ctx_reshow_rva);
}
static size_t fpc_ctl_text(char *b,size_t n);static void fpc_ctl_request(void);   /* PT20, end of file */
static int fpc_btn_index(const char *s) {
    for (int b=0;b<FPC_NBTN;++b) if (!_stricmp(s,g_fpc_btn_names[b])) return b;
    return -1;
}
static int kah_fp_keys(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id;(void)u;
    if (argc==2 && !_stricmp(argv[1],"state")) {char b[3600];fpc_state(b,sizeof b);r->append(r,b);return KAH_OK;}
    if (argc==2 && !_stricmp(argv[1],"binds")) {   /* F10 combat settings as applied (ini hot-reload included) */
        char b[200];snprintf(b,sizeof b,"manual_combat=%d enabled=%d attack=0x%02X block=0x%02X select=0x%02X interact=0x%02X draw=0x%02X",
            g_cfg_manual_combat,g_combat_enabled,g_cfg_key_attack,g_cfg_key_block,g_cfg_key_select,g_cfg_key_interact,g_cfg_key_draw);
        r->append(r,b);return KAH_OK;
    }
    if ((argc==3||argc==4) && !_stricmp(argv[1],"press")) {
        int b=fpc_btn_index(argv[2]);int ms=argc==4?atoi(argv[3]):80;
        if (b<0 || ms<20 || ms>20000) {r->append(r,"press <lmb|rmb|mmb|r|interact> [hold_ms 20..20000]");return KAH_ERROR;}
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
    if ((argc==2||argc==3) && !_stricmp(argv[1],"pick")) {   /* pick: request a fresh pick next frame + show the last; pick show: last only */
        if (argc==2) g_fpc_pick_req=1;
        else if (_stricmp(argv[2],"show")) {r->append(r,"pick [show]");return KAH_ERROR;}
        char b[640];fpc_pick_text(b,sizeof b);r->append(r,b);return KAH_OK;
    }
    if ((argc==2||argc==3) && !_stricmp(argv[1],"sneak")) {   /* sneak: probe the crosshair target next frame + show the last; sneak show: last only */
        if (argc==2) g_fpc_sneak_req=1;
        else if (_stricmp(argv[2],"show")) {r->append(r,"sneak [show]");return KAH_ERROR;}
        char b[256];snprintf(b,sizeof b,"sneak n=%u stealth=%d target=%s target_aware=%d aware_any=%d ko_chance=%.3f hostile=%d enemy_tp=%d enemy_pt=%d",
            g_fpc_sneak_probe.n,g_fpc_sneak_probe.stealth,g_fpc_sneak_probe.n?g_fpc_sneak_probe.name:"none",
            g_fpc_sneak_probe.aware,g_fpc_sneak_probe.aware_any,g_fpc_sneak_probe.chance,g_fpc_sneak_probe.hostile,
            g_fpc_sneak_probe.enemy_tp,g_fpc_sneak_probe.enemy_pt);
        r->append(r,b);return KAH_OK;
    }
    if ((argc==2||argc==3) && !_stricmp(argv[1],"movers")) {   /* movers: snapshot next frame + show the last; movers show: last only */
        if (argc==2) g_fpc_movers_req=1;
        else if (_stricmp(argv[2],"show")) {r->append(r,"movers [show]");return KAH_ERROR;}
        r->append(r,g_fpc_movers_txt);return KAH_OK;
    }
    if ((argc==2||argc==3) && !_stricmp(argv[1],"ctl")) {   /* PT20: ctl = Control button state; ctl click = queue its action */
        if (argc==3) {if (_stricmp(argv[2],"click")) {r->append(r,"ctl [click]");return KAH_ERROR;} fpc_ctl_request();}
        char b[300];fpc_ctl_text(b,sizeof b);r->append(r,b);return KAH_OK;
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
        g_fpc_free_block_frames=g_fpc_block_checks=g_fpc_native_injected=g_fpc_sheathe_kept=g_fpc_lmb_clicks=g_fpc_r_keys_swallowed=g_fpc_mouse_keys_swallowed=g_fpc_ctx_hold_opens=g_fpc_ctx_tap_opens=g_fpc_lmb_squad_refused=g_fpc_lmb_far_refused=g_fpc_mmb_objects=g_fpc_mmb_self=0;g_fpc_lmb_why="none";g_fpc_lmb_dist=-1;
        g_fpc_sneak_clicks=g_fpc_sneak_attacks=g_fpc_sneak_ko=g_fpc_sneak_failed=g_fpc_sneak_timeout=0;g_fpc_sneak_t=g_fpc_sneak_pc=NULL;
        g_fpc_sneak_path=g_fpc_sneak_result="none";strcpy(g_fpc_sneak_target,"none");g_fpc_sneak_aware=g_fpc_sneak_aware_any=-1;
        g_fpc_sneak_chance=-1.0f;g_fpc_sneak_elapsed=0;
        g_fpc_fs_prog_max=0;g_fpc_last_task=-1;strcpy(g_fpc_last_select,"none");strcpy(g_fpc_last_target,"none");
        g_fpc_swallow=1;for (int b=0;b<FPC_NBTN;++b) g_fpc_inj_until[b]=0;
        r->append(r,"counters reset, swallow=1");return KAH_OK;
    }
    r->append(r,"usage: fp_keys state|press <lmb|rmb|mmb|r> [hold_ms]|release <btn>|native <lmb|rmb> [frames]|pick [show]|sneak [show]|movers [show]|ctl [click]|swallow on|off|focus on|off|reset");
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
    g_fpc_sensory=(fpc_sensory_t)fpc_klib(FPC_SYM_SENSORY);g_fpc_aware=(fpc_aware_t)fpc_klib(FPC_SYM_AWARE);
    g_fpc_kochance=(fpc_kochance_t)fpc_klib(FPC_SYM_KOCHANCE);
    g_fpc_uncon=(fpc_cbool_t)fpc_klib(FPC_SYM_UNCON);g_fpc_dead=(fpc_cbool_t)fpc_klib(FPC_SYM_DEAD);
    logline("[controls] stealth: sensory=%p aware=%p kochance=%p uncon=%p dead=%p",(void *)g_fpc_sensory,(void *)g_fpc_aware,
        (void *)g_fpc_kochance,(void *)g_fpc_uncon,(void *)g_fpc_dead);
    void *pcf=fpc_klib_real(FPC_SYM_PLAYERCONTROL);
    g_fpc_hook_ok=pcf && fpc_input_handler() && install_hook(pcf,(void *)fpc_playercontrol_hook,(void **)&g_fpc_pc_orig);
    {void *cmf=fpc_klib_real(FPC_SYM_CTXMENU);
     g_fpc_ctx_hook_ok=cmf && install_hook(cmf,(void *)fpc_ctxmenu_hook,(void **)&g_fpc_ctx_orig);
     logline("[controls] showContextMenu=%p hook=%d",cmf,g_fpc_ctx_hook_ok);}
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
/* PT01/PT03 (Shay 2026-10-07): the label flashes for FPC_HUD_FLASH_MS after a state change only, and the combat
 * states (swinging/blocking/recovering/staggered/aiming) never show text: the animation and view carry them.
 * hud_hist still records every state change (evidence); hud_shown says whether the label is on screen now. */
#define FPC_HUD_FLASH_MS 1500.0
static int fpc_hud_texted(const char *st) {
    return !strcmp(st,"holstered")||!strcmp(st,"ready")||!strcmp(st,"reloading")||!strcmp(st,"down");
}
static void fpc_hud_update(int show) {
    static double change_ms;
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
            g_fpc_hud_text=st;++g_fpc_hud_changes;change_ms=fpc_now_ms();
            if (fpc_hud_texted(st)) ++g_fpc_hud_flashes; else ++g_fpc_hud_silent;
            g_fpc_hud_hist[g_fpc_hud_changes%FPC_HUD_HIST]=st;g_fpc_hud_hist_seq[g_fpc_hud_changes%FPC_HUD_HIST]=g_fpc_hud_changes;
        }
        int vis=fpc_hud_texted(st) && fpc_now_ms()-change_ms<FPC_HUD_FLASH_MS;
        if (vis!=g_fpc_hud_shown) {g_widget_setvisible(g_fpc_hud,vis);g_fpc_hud_shown=vis;}
    }
    g_guard_armed=0;
}
/* Camera pull-back collision (kfp_view.inc): the aim physics trace (0x087f9e07) from the eye backwards;
 * character hits (our own head/body first, squad mates behind us) are re-cast past, at most 3 times.
 * Caller (fp_view_apply / probe) holds the crash guard. Returns the wall distance along dir, -1 = no wall,
 * -2 = the native trace refused the query (unknown: the caller must not treat it as clear). */
static float fp_view_trace_wall(const Vec3 *from,const Vec3 *dir,float range) {
    if (!g_combat_physics_trace || !g_combat_hit_ctor) return -1.0f;
    Vec3 o=*from;float done=0;
    for (int i=0;i<4 && done<range;++i) {
        CombatRayHit h;
        int t=combat_trace_ray(&o,dir,range-done,&h);
        if (t<0) { ++g_view_trace_err; return -2.0f; }   /* C05-INTERIOR: native trace refused, not a miss */
        if (t==0 || !isfinite(h.distance)) return -1.0f;
        if (h.ids[0]!=1) return done+h.distance;
        float step=h.distance+0.3f;     /* past this body's surface */
        done+=step;o.x+=dir->x*step;o.y+=dir->y*step;o.z+=dir->z*step;
    }
    return -1.0f;
}
/* PT20 (Shay 2026-10-07): switch the FP-controlled squad member from the game's context menu. While the native
 * right-click menu is visible in FP (squad bar portrait or the FP RMB menu on a mate) and its target is a squad
 * member other than the controlled one, a "Control" button sits next to the menu; clicking it pins FP control to
 * that member (fp_control_pin, the same switch as the take-control key F6), selects her and closes the menu.
 * The native order list is untouched. Post-frame (fp_gui_update) only; a faulting call disables only this button.
 * Test: fp_keys ctl [click] (state / queue the button action; MyGUI clicks from the harness bypass the poll). */
#define FPC_SYM_HIDECTX "?hideContextMenu@GameWorld@@QEAAXXZ"
#define FPC_SYM_WGETVIS "?getVisible@Widget@MyGUI@@QEBA_NXZ"
static void *g_fpc_ctl_btn,*g_fpc_ctl_target;
static int g_fpc_ctl_shown,g_fpc_ctl_dead;
static volatile LONG g_fpc_ctl_click_req;
static unsigned g_fpc_ctl_offers,g_fpc_ctl_switches,g_fpc_ctl_menu_seen;
static char g_fpc_ctl_name[48]="none",g_fpc_ctl_last[48]="none";
static const char *g_fpc_ctl_via="none",*g_fpc_ctl_src="none";
static unsigned char (*fpc_ctl_getvis(void))(void *) {
    static unsigned char (*getvis)(void *);static int res;
    if (!res) {res=1;HMODULE mg=GetModuleHandleA(MYGUI_DLL);getvis=mg?(unsigned char (*)(void *))GetProcAddress(mg,FPC_SYM_WGETVIS):NULL;}
    return getvis;
}
/* PT06/PT20 diagnostics: the game's menu visibility as the Control button sees it (cache byte) and the menu widgets'
 * own flags (bit0 menu1, bit1 menu2; -1 unknown), refreshed every frame for `fp_keys ctl` */
static int g_fpc_ctl_vis=-1,g_fpc_ctl_mw=-1;
static int fpc_ctx_widget_bits(void *gw) {
    unsigned char (*getvis)(void *)=fpc_ctl_getvis();
    void *pi=fpc_player_interface(gw);
    if (!getvis || !readable(pi,0x200)) return -1;
    int bits=0;
    for (int i=0;i<2;++i) {
        void *m=*(void **)((uintptr_t)pi+FPC_PI_CTXMENU+0x48+8*i);
        if (!readable(m,0xC8)) continue;
        void *mw=*(void **)((uintptr_t)m+8);
        if (readable(mw,8) && getvis(mw)) bits|=1<<i;
    }
    return bits;
}
static void *fpc_ctl_menu_target(void *gw,void *ctl) {
    unsigned char (*getvis)(void *)=fpc_ctl_getvis();
    void *pi=fpc_player_interface(gw);
    if (!readable(pi,0x200)) return NULL;
    for (int i=0;i<2;++i) {
        void *m=*(void **)((uintptr_t)pi+FPC_PI_CTXMENU+0x48+8*i);    /* ContextMenu::menuGUI / menuGUI2 */
        if (!readable(m,0xC8)) continue;
        void *mw=*(void **)((uintptr_t)m+8);                           /* BaseLayout::mMainWidget */
        if (getvis && readable(mw,8) && !getvis(mw)) continue;
        if (*(int *)((uintptr_t)m+0xA8+HAND_IDS)!=1) continue;         /* contextMenuTarget: a character */
        void *c=g_combat_hand_character?g_combat_hand_character((void *)((uintptr_t)m+0xA8)):NULL;
        if (char_valid(c) && c!=ctl && fp_char_in_squad(gw,c)) {g_fpc_ctl_src=i?"menu2":"menu1";return c;}
    }
    void *rt=*(void **)((uintptr_t)pi+0x1F8);                          /* PlayerInterface::mouseRightTarget */
    if (char_valid(rt) && rt!=ctl && fp_char_in_squad(gw,rt)) {g_fpc_ctl_src="right_target";return rt;}
    return NULL;
}
static void fpc_ctl_menu_update(void *gw) {
    if (g_fpc_ctl_dead || !g_gui_getinstance || !g_gui_createwidget || !g_widget_setvisible || g_guard_armed) return;
    if (setjmp(g_guard_jb)) {g_guard_armed=0;g_fpc_ctl_dead=1;logline("[controls] Control button FAULTED; disabled");return;}
    guard_arm();
    int vis=g_fp_mode && gw && RVA_CTXMENU_VISIBLE && readable((void *)(g_base+RVA_CTXMENU_VISIBLE),1) &&
        *(unsigned char *)(g_base+RVA_CTXMENU_VISIBLE);
    g_fpc_ctl_vis=vis;g_fpc_ctl_mw=g_fp_mode&&gw?fpc_ctx_widget_bits(gw):-1;
    void *ctl=vis?fp_controlled_char(gw):NULL;
    void *t=vis&&ctl?fpc_ctl_menu_target(gw,ctl):NULL;
    static int lmb_prev;int lmb=(GetAsyncKeyState(VK_LBUTTON)&0x8000)!=0,released=lmb_prev&&!lmb;lmb_prev=lmb;
    if (!t) {
        if (g_fpc_ctl_shown) {g_widget_setvisible(g_fpc_ctl_btn,0);g_fpc_ctl_shown=0;}
        g_fpc_ctl_target=NULL;InterlockedExchange(&g_fpc_ctl_click_req,0);g_guard_armed=0;return;
    }
    if (!g_fpc_ctl_btn) {
        void *gui=g_gui_getinstance();
        unsigned char ty[32],sk[32],ly[32],nm[32];
        make_mstr(ty,"Button");make_mstr(ly,"Popup");make_mstr(nm,"KFPControlBtn");
        void *skh=make_mstr_long(sk,"Kenshi_Button1");
        g_fpc_ctl_btn=readable(gui,8)?g_gui_createwidget(gui,ty,sk,0,0,150,30,0,ly,nm):NULL;
        if (skh) free(skh);
        if (!g_fpc_ctl_btn) {g_fpc_ctl_dead=1;g_guard_armed=0;logline("[controls] Control button: create failed; disabled");return;}
        caption_set(g_fpc_ctl_btn,"Control",g_textbox_setcap);
        logline("[controls] Control button widget %p",g_fpc_ctl_btn);
    }
    if (t!=g_fpc_ctl_target) {   /* a new menu target: place the button left of the cursor (the menu opens to its right) */
        g_fpc_ctl_target=t;++g_fpc_ctl_offers;fpc_name(t,g_fpc_ctl_name,sizeof g_fpc_ctl_name);
        int x=GetSystemMetrics(SM_CXSCREEN)/2-160,y=GetSystemMetrics(SM_CYSCREEN)/2;
        POINT p;HWND fg=GetForegroundWindow();DWORD pid=0;
        if (fg) GetWindowThreadProcessId(fg,&pid);
        if (pid==GetCurrentProcessId() && GetCursorPos(&p) && ScreenToClient(fg,&p)) {x=p.x-160;y=p.y;}
        if (x<0) x=0;
        if (y<0) y=0;
        if (g_widget_setpos) g_widget_setpos(g_fpc_ctl_btn,x,y);
        logline("[controls] Control offered for %s (src=%s) at %d,%d",g_fpc_ctl_name,g_fpc_ctl_src,x,y);
    }
    if (!g_fpc_ctl_shown) {g_widget_setvisible(g_fpc_ctl_btn,1);g_fpc_ctl_shown=1;}
    int harness=InterlockedExchange(&g_fpc_ctl_click_req,0)!=0;
    if (harness || (released && widget_clicked(g_fpc_ctl_btn))) {
        void *pi=fpc_player_interface(gw);
        if (fp_control_pin(gw,t)) {
            if (g_fpc_select && pi) g_fpc_select(pi,t,0);
            static void (*hide)(void *);static int hres;
            if (!hres) {hres=1;hide=(void (*)(void *))fpc_klib(FPC_SYM_HIDECTX);}
            if (hide) hide(gw);
            ++g_fpc_ctl_switches;g_fpc_ctl_via=harness?"harness":"click";strcpy(g_fpc_ctl_last,g_fpc_ctl_name);
            g_widget_setvisible(g_fpc_ctl_btn,0);g_fpc_ctl_shown=0;g_fpc_ctl_target=NULL;
            if (g_fpc_ctx_freed) {g_free_toggle=0;g_fpc_ctx_freed=0;}   /* back to look mode on the new body */
            logline("[controls] Control -> %s via=%s",g_fpc_ctl_last,g_fpc_ctl_via);
        } else logline("[controls] Control -> %s refused (pin failed)",g_fpc_ctl_name);
    }
    g_guard_armed=0;
}
static void fpc_ctl_request(void) {InterlockedExchange(&g_fpc_ctl_click_req,1);}
static size_t fpc_ctl_text(char *b,size_t n) {
    return (size_t)snprintf(b,n,"ctl shown=%d dead=%d target=%s src=%s offers=%u switches=%u last=%s via=%s menu_vis=%d menu_widgets=%d",
        g_fpc_ctl_shown,g_fpc_ctl_dead,g_fpc_ctl_target?g_fpc_ctl_name:"none",g_fpc_ctl_src,g_fpc_ctl_offers,g_fpc_ctl_switches,
        g_fpc_ctl_last,g_fpc_ctl_via,g_fpc_ctl_vis,g_fpc_ctl_mw);
}
