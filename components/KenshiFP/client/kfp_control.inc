static void fp_control_release_actor(void *pc);
/* Controlled actor identity is independent of inspected vanilla selection.
 * Shared first_player_char/g_player_pc retain their existing semantics. */
static uint32_t g_fp_control_ids[5];
static int g_fp_control_pinned, g_fp_world_seen, g_fp_take_key_prev;
static void *g_fp_control_actor;
static volatile LONG g_fp_take_request;
static int fp_control_pin(void *pc) {
    if (!char_valid(pc) || !readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20)) return 0;
    if (g_fp_control_pinned && memcmp(g_fp_control_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20))
        fp_control_release_actor(g_fp_control_actor);
    memcpy(g_fp_control_ids,(void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),20);
    g_fp_control_pinned=1; g_fp_control_actor=pc;
    return 1;
}
static void *fp_controlled_char(void *gw) {
    if (!g_fp_mode) return first_player_char(gw);
    if (!g_fp_control_pinned) {
        void *pc=first_player_char(gw);
        return fp_control_pin(pc)?pc:NULL;
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
    return fp_control_pin(pc);
}
static void fp_control_tick(void *gw) {
    void *selected=first_player_char(gw);
    if (!selected) {
        fp_control_release_actor(g_fp_control_actor);
        g_fp_mode=0; g_fp_world_seen=0; g_fp_control_pinned=0; g_fp_control_actor=NULL;
        return;
    }
    if (!g_fp_mode) fp_control_release_actor(g_fp_control_actor);
    if (!g_fp_world_seen) {
        g_fp_world_seen=1;
        if (g_cfg_direct_default && !g_fp_mode) {
            fp_control_pin(selected); g_fp_mode=1;
            logline("[control] direct controls enabled for loaded squad");
        }
    }
    int key=(GetAsyncKeyState(g_cfg_key_take_control)&0x8000)!=0;
    int take=(key && !g_fp_take_key_prev && game_has_focus() && !g_ui_open);
    g_fp_take_key_prev=key;
    take |= InterlockedExchange(&g_fp_take_request,0)!=0;
    if (take && fp_control_take_selected(gw))
        logline("[control] transferred to explicitly selected squad member");
    if (g_fp_mode && !fp_controlled_char(gw)) {
        fp_control_release_actor(g_fp_control_actor);
        g_fp_mode=0;
        logline("[control] actor unavailable; direct ownership released");
    }
}
static int kah_fp_control(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id; (void)u;
    if (argc!=2 || (_stricmp(argv[1],"state") && _stricmp(argv[1],"take"))) {
        r->append(r,"usage: fp_control state|take"); return KAH_ERROR;
    }
    if (!_stricmp(argv[1],"take")) {
        if (!fp_control_take_selected(g_gw_cache)) {
            r->append(r,"select a valid squad member first"); return KAH_ERROR;
        }
        r->append(r,"controlled actor transferred; inspected selection unchanged");
        return KAH_OK;
    }
    void *pc=g_fp_mode?fp_controlled_char(g_gw_cache):g_fp_control_actor;
    char b[220];
    snprintf(b,sizeof(b),"direct=%d pinned=%d controlled=%llx inspected=%llx control_ids=%u/%u/%u/%u/%u",
        !!g_fp_mode,g_fp_control_pinned,(unsigned long long)(uintptr_t)pc,
        (unsigned long long)(uintptr_t)first_player_char(g_gw_cache),
        g_fp_control_ids[0],g_fp_control_ids[1],g_fp_control_ids[2],g_fp_control_ids[3],g_fp_control_ids[4]);
    r->append(r,b); return KAH_OK;
}
