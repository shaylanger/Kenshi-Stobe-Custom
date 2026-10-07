static void fp_control_release_actor(void *pc,int live);
static int fp_char_in_squad(void *gw,void *pc);
/* release the controlled actor's WASD drive; writes only if it is still a live squad member */
#define FP_CONTROL_RELEASE(gw) fp_control_release_actor(g_fp_control_actor,fp_char_in_squad((gw),g_fp_control_actor))
/* Controlled actor identity is independent of inspected vanilla selection.
 * Shared first_player_char/g_player_pc retain their existing semantics. */
static uint32_t g_fp_control_ids[5];
static int g_fp_control_pinned, g_fp_world_seen, g_fp_take_key_prev;
static void *g_fp_control_actor;
static volatile LONG g_fp_take_request;
static unsigned g_fp_take_req_n, g_fp_take_req_done, g_fp_take_req_ui;
/* Harness fp_move (TEST ONLY): WASD held for a bounded time through the same
 * fp_movement path as the physical keys (bit0 W, bit1 S, bit2 A, bit3 D). */
static volatile LONG g_kah_move_keys, g_kah_move_until;
static DWORD g_kah_move_start;   /* C04-TAKE diag: when the current fp_move hold began */
static int kah_move_key(int bit) {
    LONG k=g_kah_move_keys;
    if (!(k&bit)) return 0;
    if ((LONG)(GetTickCount()-(DWORD)g_kah_move_until)>=0) {
        if (InterlockedExchange(&g_kah_move_keys,0))
            logline("[move] harness fp_move hold expired (keys=0x%lx held %lu ms)",
                    (long)k,(unsigned long)(GetTickCount()-g_kah_move_start));
        return 0;
    }
    return 1;
}
static int fp_control_pin(void *gw,void *pc) {
    if (!char_valid(pc) || !readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20)) return 0;
    if (g_fp_control_pinned && memcmp(g_fp_control_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20))
        FP_CONTROL_RELEASE(gw);
    if (!g_fp_control_pinned || memcmp(g_fp_control_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20))
        kfp_stuck_idle(&g_stuck_frames);   /* new actor: fresh pinned estimate */
    memcpy(g_fp_control_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20);
    g_fp_control_pinned=1; g_fp_control_actor=pc;
    return 1;
}
static void *fp_controlled_char(void *gw) {
    if (!g_fp_mode) return first_player_char(gw);
    if (!g_fp_control_pinned) {
        void *pc=first_player_char(gw);
        return fp_control_pin(gw,pc)?pc:NULL;
    }
    if (!readable((void *)((uintptr_t)gw+GW_PLAYER),8)) return NULL;
    void *pi=*(void **)((uintptr_t)gw+GW_PLAYER);
    if (!readable(pi,PI_PLAYERCHARS+LEK_STUFF+8)) return NULL;
    uint32_t count=*(uint32_t *)((uintptr_t)pi+PI_PLAYERCHARS+LEK_COUNT);
    void **chars=*(void ***)((uintptr_t)pi+PI_PLAYERCHARS+LEK_STUFF);
    if (!count || count>4096 || !readable(chars,(size_t)count*8)) return NULL;
    for (uint32_t i=0;i<count;++i) {
        void *pc=chars[i];
        if (!char_valid(pc) || !readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20)) continue;
        if (!memcmp(g_fp_control_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20)) {
            g_fp_control_actor=pc; return pc;
        }
    }
    g_fp_control_actor=NULL; return NULL; /* no silent transfer to another actor */
}
static int fp_control_take_selected(void *gw) {
    void *pc=first_player_char(gw);
    if (!pc || !readable((void *)((uintptr_t)gw+GW_PLAYER),8)) return 0;
    void *pi=*(void **)((uintptr_t)gw+GW_PLAYER);
    if (!readable((void *)((uintptr_t)pi+PI_SELECTED_CHAR+HAND_IDS),20) ||
        !readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20)) return 0;
    /* first_player_char falls back to slot 0 for a non-squad selection;
     * explicit take-control must refuse that fallback. */
    if (memcmp((void *)((uintptr_t)pi+PI_SELECTED_CHAR+HAND_IDS),
               (void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20)) return 0;
    return fp_control_pin(gw,pc);
}
/* 1 = pc is one of gw's live player characters. Pointer compare only: pc itself is
 * never dereferenced, so a stale (freed) character pointer is safe to ask about. */
static int fp_char_in_squad(void *gw,void *pc) {
    if (!pc || !readable((void *)((uintptr_t)gw+GW_PLAYER),8)) return 0;
    void *pi=*(void **)((uintptr_t)gw+GW_PLAYER);
    if (!readable(pi,PI_PLAYERCHARS+LEK_STUFF+8)) return 0;
    uint32_t count=*(uint32_t *)((uintptr_t)pi+PI_PLAYERCHARS+LEK_COUNT);
    void **chars=*(void ***)((uintptr_t)pi+PI_PLAYERCHARS+LEK_STUFF);
    if (!count || count>4096 || !readable(chars,(size_t)count*8)) return 0;
    for (uint32_t i=0;i<count;++i) if (chars[i]==pc) return 1;
    return 0;
}
/* World teardown (load / quit to menu): the old characters, their appearances and
 * worn-item entities are being freed. Drop every head-hide pointer WITHOUT touching
 * it. 4080 b27b crash (2026-10-06): an in-world reload with the head hidden made the
 * restore path run the game's updateHiddenParts on the torn-down character's
 * appearance 2.4 s into the load ("head-mask FAULTED"); Kenshi died in the D3D11
 * render ~40 s later. The new world rebuilds every appearance, so nothing to restore. */
static void fp_head_forget_world(void) {
    g_head_hidden=0; g_head_hidden_char=NULL; g_player_app=NULL;
    g_head_params=NULL; g_head_params_mat=NULL; g_gear_n=0;
}
/* C05-KO (2026-10-06): standing MOVE_DIRECTION drive is only valid on a character in
 * the normal prone state (0) who is not down. KO/crippled/play-dead route to the order
 * path; forcing direct motion into a KO hands our vector to the KO ragdoll. */
static int fp_direct_drive_allowed(int prone,int is_down) {
    return prone==0 && !is_down;
}
/* Clear our direct-drive state on a CharMovement: movementMode -> normal, desired
 * motion and (motion_off != 0) current motion -> zero. Offsets are parameters so the
 * offline test can use a plain buffer. Returns 1 if the mode was MOVE_DIRECTION (2). */
static int fp_mover_clear_direct(void *mv,size_t mode_off,size_t desired_off,size_t motion_off) {
    if (!mv || !readable((void *)((uintptr_t)mv+mode_off),4)) return 0;
    int was=*(int *)((uintptr_t)mv+mode_off)==2;
    if (readable((void *)((uintptr_t)mv+desired_off),12)) memset((void *)((uintptr_t)mv+desired_off),0,12);
    if (motion_off && readable((void *)((uintptr_t)mv+motion_off),12)) memset((void *)((uintptr_t)mv+motion_off),0,12);
    *(int *)((uintptr_t)mv+mode_off)=0;
    return was;
}
/* CharMovement::update down check, run before AND after the original update (a KO can
 * land inside it): keep driving only a standing character; otherwise stand the WASD drive
 * down and clear what we forced so nothing of ours is consumed by the KO ragdoll. */
static int fp_drive_gate(void *mv,int drive,int prone,int is_down,
                         size_t mode_off,size_t desired_off,size_t motion_off) {
    if (!drive) return 0;
    if (fp_direct_drive_allowed(prone,is_down)) return 1;
    InterlockedExchange(&g_dm_active,0);
    fp_mover_clear_direct(mv,mode_off,desired_off,motion_off);
    return 0;
}
static void fp_control_tick(void *gw) {
    void *selected=first_player_char(gw);
    if (!selected) {
        fp_head_forget_world();   /* before anything can "restore" a freed head */
        fp_control_release_actor(g_fp_control_actor,0);   /* teardown: forget, never write (b27b) */
        g_fp_mode=0; g_fp_world_seen=0; g_fp_control_pinned=0; g_fp_control_actor=NULL;
        g_freecam_clear_pending=1;   /* load: a vanilla FPS camera may carry over (m51-F) */
        return;
    }
    if (!g_fp_mode) FP_CONTROL_RELEASE(gw);
    if (!g_fp_world_seen) {
        g_fp_world_seen=1;
        if (g_cfg_direct_default && !g_fp_mode) {
            fp_control_pin(gw,selected); g_fp_mode=1;
            logline("[control] direct controls enabled for loaded squad");
        }
    }
    int key=(GetAsyncKeyState(g_cfg_key_take_control)&0x8000)!=0;
    int take=(key && !g_fp_take_key_prev && game_has_focus() && !g_ui_open);
    g_fp_take_key_prev=key;
    /* harness `fp_control press` = one key_take_control press: same UI gate, focus not required */
    int req=InterlockedExchange(&g_fp_take_request,0)!=0;
    if (req && g_ui_open) { ++g_fp_take_req_ui; logline("[control] take press ignored: UI open"); }
    take |= (req && !g_ui_open);
    if (take && fp_control_take_selected(gw)) {
        if (req && !g_ui_open) ++g_fp_take_req_done;
        {   LONG hk=g_kah_move_keys; LONG left=(LONG)((DWORD)g_kah_move_until-GetTickCount());
            if (!hk || left<0) { hk=0; left=0; }
            logline("[control] transferred to explicitly selected squad member (held: harness=0x%lx left_ms=%ld"
                    " phys_w=%d)", (long)hk,(long)left,(GetAsyncKeyState(0x57 /* W */)&0x8000)?1:0); }
    }
    if (g_fp_mode && !fp_controlled_char(gw)) {
        FP_CONTROL_RELEASE(gw);
        g_fp_mode=0;
        logline("[control] actor unavailable; direct ownership released");
    }
}
static int kah_fp_control(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id; (void)u;
    if (argc!=2 || (_stricmp(argv[1],"state") && _stricmp(argv[1],"take") && _stricmp(argv[1],"press"))) {
        r->append(r,"usage: fp_control state|take|press"); return KAH_ERROR;
    }
    if (!_stricmp(argv[1],"press")) {
        ++g_fp_take_req_n; InterlockedExchange(&g_fp_take_request,1);
        r->append(r,"take key press queued (key_take_control path, UI gate); verify with fp_control state");
        return KAH_OK;
    }
    if (!_stricmp(argv[1],"take")) {
        if (!fp_control_take_selected(g_gw_cache)) {
            r->append(r,"select a valid squad member first"); return KAH_ERROR;
        }
        r->append(r,"controlled actor transferred; inspected selection unchanged");
        return KAH_OK;
    }
    void *pc=g_fp_mode?fp_controlled_char(g_gw_cache):g_fp_control_actor;
    char b[300];
    snprintf(b,sizeof(b),"direct=%d pinned=%d controlled=%llx inspected=%llx control_ids=%u/%u/%u/%u/%u"
        " take_presses=%u take_done=%u take_ui_ignored=%u",
        !!g_fp_mode,g_fp_control_pinned,(unsigned long long)(uintptr_t)pc,
        (unsigned long long)(uintptr_t)first_player_char(g_gw_cache),
        g_fp_control_ids[0],g_fp_control_ids[1],g_fp_control_ids[2],g_fp_control_ids[3],g_fp_control_ids[4],
        g_fp_take_req_n,g_fp_take_req_done,g_fp_take_req_ui);
    r->append(r,b); return KAH_OK;
}
/* fp_move <keys wasd|none> [ms] | state: bounded harness WASD hold (TEST ONLY). */
static int kah_fp_move(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id; (void)u;
    char b[480];
    if (argc==2 && !_stricmp(argv[1],"state")) {
        LONG k=g_kah_move_keys; LONG left=(LONG)((DWORD)g_kah_move_until-GetTickCount());
        int rc_mode=-1,mv_mode=-1;   /* C05-KO diag: native ranged combat mode / CharMovement mode (0x378) */
        {void *pc=g_fp_mode?fp_controlled_char(g_gw_cache):NULL;
         void *rc=char_valid(pc)&&readable((void *)((uintptr_t)pc+CHAR_RANGEDCOMBAT),8)?*(void **)((uintptr_t)pc+CHAR_RANGEDCOMBAT):NULL;
         void *mv=char_valid(pc)&&readable((void *)((uintptr_t)pc+CHAR_MOVEMENT),8)?*(void **)((uintptr_t)pc+CHAR_MOVEMENT):NULL;
         if (readable((void *)((uintptr_t)rc+RC_COMBATMODE),1)) rc_mode=*(unsigned char *)((uintptr_t)rc+RC_COMBATMODE);
         if (readable((void *)((uintptr_t)mv+0x378),4)) mv_mode=*(int *)((uintptr_t)mv+0x378);}
        if (!k || left<0) { k=0; left=0; }
        snprintf(b,sizeof(b),"keys=%s%s%s%s left_ms=%ld moving=%d direct_drive=%d dm_active=%d move_speed=%.2f"
            " is_down=%d ui_moveblock=%d fp_mode=%d prone=%d in_bed=%d head_above=%.2f stuck_frames=%d pinned=%d"
            " downed=%d ko=%d rc_mode=%d mv_mode=%d stale_ends=%u",
            (k&1)?"w":"",(k&2)?"s":"",(k&4)?"a":"",(k&8)?"d":"",(long)left,g_was_moving,g_was_direct,
            (int)g_dm_active,g_move_speed,g_is_down,g_ui_moveblock,!!g_fp_mode,g_dbg_prone,g_dbg_in_bed,
            g_head_above,g_stuck_frames,g_stuck_frames>KFP_STUCK_PINNED_FRAMES,g_dbg_downed,g_dbg_ko,
            rc_mode,mv_mode,g_combat_stale_ends);
        r->append(r,b); return KAH_OK;
    }
    if (argc<2 || argc>3) {
        r->append(r,"usage: fp_move <wasd keys|none> [ms 1..30000, default 1000] | fp_move state"); return KAH_ERROR;
    }
    LONG k=0;
    if (_stricmp(argv[1],"none")) {
        for (const char *c=argv[1];*c;++c) {
            switch (*c|0x20) {
            case 'w': k|=1; break; case 's': k|=2; break; case 'a': k|=4; break; case 'd': k|=8; break;
            default: r->append(r,"keys: letters w a s d, or none"); return KAH_ERROR;
            }
        }
    }
    long ms=1000;
    if (argc==3) {
        char *e; ms=strtol(argv[2],&e,10);
        if (*e || ms<1 || ms>30000) { r->append(r,"ms must be 1..30000"); return KAH_ERROR; }
    }
    g_kah_move_start=GetTickCount();
    InterlockedExchange(&g_kah_move_until,(LONG)(GetTickCount()+(DWORD)ms));
    InterlockedExchange(&g_kah_move_keys,k);
    if (k) snprintf(b,sizeof(b),"keys held %ld ms through fp_movement; verify with where/fp_move state",ms);
    else snprintf(b,sizeof(b),"keys released");
    r->append(r,b); return KAH_OK;
}
