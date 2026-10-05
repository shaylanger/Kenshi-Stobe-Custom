/* Read-only native melee snapshot. No interpretation of raw readiness values
 * until coordinator traces prove animation/recovery timing on this executable. */
typedef void *(*melee_get_combat_t)(void *);
static melee_get_combat_t g_melee_get_combat;
static int kah_fp_melee(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id;(void)u;
    if(argc!=2 || _stricmp(argv[1],"state")) {
        r->append(r,"usage: fp_melee state (observational)");return KAH_ERROR;
    }
    if(!g_melee_get_combat) {r->append(r,"native combat binding unavailable");return KAH_ERROR;}
    void *pc=fp_controlled_char(g_gw_cache);
    if(!char_valid(pc)) {r->append(r,"controlled actor unavailable");return KAH_ERROR;}
    if(setjmp(g_guard_jb)) {g_guard_armed=0;r->append(r,"melee state read fault");return KAH_ERROR;}
    guard_arm();
    void *cc=g_melee_get_combat(pc);
    if(!readable(cc,0x2b8) || *(void **)((uintptr_t)cc+0x188)!=pc) {
        g_guard_armed=0;r->append(r,"native combat object unavailable or owner mismatch");return KAH_ERROR;
    }
    char b[520];
    snprintf(b,sizeof(b),
      "actor=%llx combat=%llx active=%u state=%d next=%d attacking=%.6f dead=%u dead_left=%.6f state_left=%.6f technique=%llx finished=%u movement=%llx target=%llx blocking_target=%llx threats=%u frame_dt=%.6f",
      (unsigned long long)(uintptr_t)pc,(unsigned long long)(uintptr_t)cc,
      *(unsigned char *)((uintptr_t)cc+0x130),*(int *)((uintptr_t)cc+0x1f0),*(int *)((uintptr_t)cc+0x1f4),
      *(float *)((uintptr_t)cc+0x140),*(unsigned char *)((uintptr_t)cc+0x144),
      *(float *)((uintptr_t)cc+0x148),*(float *)((uintptr_t)cc+0x14c),
      *(unsigned long long *)((uintptr_t)cc+0x150),*(unsigned char *)((uintptr_t)cc+0x158),
      *(unsigned long long *)((uintptr_t)cc+0x170),*(unsigned long long *)((uintptr_t)cc+0x290),
      *(unsigned long long *)((uintptr_t)cc+0x1a8),*(unsigned *)((uintptr_t)cc+0x228),
      *(float *)((uintptr_t)cc+0x168));
    g_guard_armed=0;r->append(r,b);return KAH_OK;
}
static void fp_melee_observe_init(void) {
    HMODULE lib=GetModuleHandleA("KenshiLib.dll");
    if(lib) g_melee_get_combat=(melee_get_combat_t)GetProcAddress(lib,"?getCombatClass@Character@@QEBAPEAVCombatClass@@XZ");
    logline("[melee] read-only combat binding %s",g_melee_get_combat?"available":"unavailable");
}
