/* Read-only native melee snapshot. No interpretation of raw readiness values
 * until coordinator traces prove animation/recovery timing on this executable. */
typedef void *(*melee_get_combat_t)(void *);
static melee_get_combat_t g_melee_get_combat;
static int kah_fp_melee(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id;(void)u;
    if(argc==3 && !_stricmp(argv[1],"passive")) {
        if(!_stricmp(argv[2],"off")) {fp_melee_set_passive(0);r->append(r,"passive off");return KAH_OK;}
        char *e;unsigned long v=strtoul(argv[2],&e,10);
        if(e==argv[2]||*e||!v) {r->append(r,"usage: fp_melee passive <serial>|off");return KAH_ERROR;}
        fp_melee_set_passive((unsigned)v);r->append(r,"passive on: AI attacks aimed at that serial are refused");return KAH_OK;
    }
    if(argc>=3 && argc<=4 && !_stricmp(argv[1],"spam")) {
        if(argc==3 && !_stricmp(argv[2],"off")) {fp_melee_spam_start(0,0);r->append(r,"spam off");return KAH_OK;}
        char *e1,*e2=NULL;unsigned long n=strtoul(argv[2],&e1,10),p=argc==4?strtoul(argv[3],&e2,10):200;
        if(e1==argv[2]||*e1||!n||n>1000||(argc==4&&(e2==argv[3]||*e2||p<20||p>5000))) {
            r->append(r,"usage: fp_melee spam <clicks 1-1000> [period_ms 20-5000, default 200] | fp_melee spam off");return KAH_ERROR;
        }
        fp_melee_spam_start((unsigned)n,(unsigned)p);
        char b[96];snprintf(b,sizeof(b),"spam on: %lu clicks every %lu ms",n,p);r->append(r,b);return KAH_OK;
    }
    if(argc>=2 && argc<=3 && !_stricmp(argv[1],"click_legal")) {
        char *e=NULL;unsigned long ms=argc==3?strtoul(argv[2],&e,10):6000;
        if(argc==3&&(e==argv[2]||*e||ms<100||ms>30000)) {r->append(r,"usage: fp_melee click_legal [timeout_ms 100-30000, default 6000]");return KAH_ERROR;}
        fp_melee_click_legal_start((unsigned)ms);
        char b[96];snprintf(b,sizeof(b),"click_legal armed: one click at the first legal frame within %lu ms",ms);r->append(r,b);return KAH_OK;
    }
    if(argc==3 && !_stricmp(argv[1],"force_chase")) {
        int on=!_stricmp(argv[2],"on");
        if(!on && _stricmp(argv[2],"off")) {r->append(r,"usage: fp_melee force_chase on|off");return KAH_ERROR;}
        fp_melee_set_force_chase(on);r->append(r,on?"force_chase on: owned fighter forced into the native chase lock (state 11) each tick":"force_chase off");return KAH_OK;
    }
    if(argc>=2 && argc<=3 && !_stricmp(argv[1],"swingstat")) {
        if(argc==3 && _stricmp(argv[2],"reset")) {r->append(r,"usage: fp_melee swingstat [reset]");return KAH_ERROR;}
        if(argc==3) fp_melee_swingstat_reset();
        char b[768];fp_melee_swingstat_append(b,sizeof(b));r->append(r,b);return KAH_OK;
    }
    if((argc!=2 && argc!=3) || _stricmp(argv[1],"state")) {
        r->append(r,"usage: fp_melee state [<npc>] (default: the controlled actor) | fp_melee passive <serial>|off (test: refuse AI attacks aimed at that character) | fp_melee spam <n> [period_ms]|off (test: n LMB clicks on the game thread) | fp_melee click_legal [timeout_ms] (test: one click at the first legal frame) | fp_melee swingstat [reset] (applied attack speed, per-technique swing time) | fp_melee force_chase on|off (test: force the native chase lock, M09-CHASE)");return KAH_ERROR;
    }
    if(!g_melee_get_combat) {r->append(r,"native combat binding unavailable");return KAH_ERROR;}
    /* <npc> (harness name/#serial forms): read that character, e.g. the fighter after control moved away (M08-ACTOR) */
    void *ctl=fp_controlled_char(g_gw_cache),*pc=ctl;
    if(argc==3) {
        char err[160]="";
        if(!g_kah.findCharacter) {r->append(r,"fp_melee state <npc> needs a harness with findCharacter (2026-10-03+)");return KAH_ERROR;}
        pc=g_kah.findCharacter(argv[2],err,sizeof(err));
        if(!char_valid(pc)) {r->append(r,err[0]?err:"character not found");return KAH_ERROR;}
    }
    if(!char_valid(pc)) {r->append(r,"controlled actor unavailable");return KAH_ERROR;}
    if(setjmp(g_guard_jb)) {g_guard_armed=0;r->append(r,"melee state read fault");return KAH_ERROR;}
    guard_arm();
    void *cc=g_melee_get_combat(pc);
    if(!readable(cc,0x2b8) || *(void **)((uintptr_t)cc+0x188)!=pc) {
        g_guard_armed=0;r->append(r,"native combat object unavailable or owner mismatch");return KAH_ERROR;
    }
    char b[2048];
    /* hand = 0x20 bytes: index +0x14, serial +0x18 (printed #serial/index like the harness). */
    const int ai=readable(cc,0x2e8);
    snprintf(b,sizeof(b),
      "actor=%llx controlled=%d combat=%llx active=%u state=%d next=%d attacking=%.6f dead=%u dead_left=%.6f state_left=%.6f technique=%llx finished=%u movement=%llx target=%llx blocking_target=%llx threats=%u frame_dt=%.6f target_h=#%u/%u blocking_h=#%u/%u zone_targets=%u focused_h=#%u/%u",
      (unsigned long long)(uintptr_t)pc,pc==ctl,(unsigned long long)(uintptr_t)cc,
      *(unsigned char *)((uintptr_t)cc+0x130),*(int *)((uintptr_t)cc+0x1f0),*(int *)((uintptr_t)cc+0x1f4),
      *(float *)((uintptr_t)cc+0x140),*(unsigned char *)((uintptr_t)cc+0x144),
      *(float *)((uintptr_t)cc+0x148),*(float *)((uintptr_t)cc+0x14c),
      *(unsigned long long *)((uintptr_t)cc+0x150),*(unsigned char *)((uintptr_t)cc+0x158),
      *(unsigned long long *)((uintptr_t)cc+0x170),*(unsigned long long *)((uintptr_t)cc+0x290),
      *(unsigned long long *)((uintptr_t)cc+0x1a8),*(unsigned *)((uintptr_t)cc+0x228),
      *(float *)((uintptr_t)cc+0x168),
      *(unsigned *)((uintptr_t)cc+0x298+0x18),*(unsigned *)((uintptr_t)cc+0x298+0x14),
      *(unsigned *)((uintptr_t)cc+0x1b0+0x18),*(unsigned *)((uintptr_t)cc+0x1b0+0x14),
      *(unsigned *)((uintptr_t)cc+0x1d8+0x8),
      ai?*(unsigned *)((uintptr_t)cc+0x2c8+0x18):0u,ai?*(unsigned *)((uintptr_t)cc+0x2c8+0x14):0u);
    g_guard_armed=0;
    size_t l=strlen(b);fp_melee_state_append(b+l,sizeof(b)-l,cc);
    r->append(r,b);return KAH_OK;
}
static void fp_melee_observe_init(void) {
    /* Verified leaf: Character::body(+0x648)->combatClass(+8). Avoid
     * trusting an SDK table from a different executable revision. */
    g_melee_get_combat=(melee_get_combat_t)combat_unique_signature(
        "48 8B 81 48 06 00 00 48 8B 40 08 C3");
    logline("[melee] uniquely scanned read-only getter %s",g_melee_get_combat?"available":"unavailable");
}
