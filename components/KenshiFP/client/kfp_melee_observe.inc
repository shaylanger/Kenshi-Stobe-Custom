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
    char b[760];
    /* hand = 0x20 bytes: index +0x14, serial +0x18 (printed #serial/index like the harness). */
    const int ai=readable(cc,0x2e8);
    snprintf(b,sizeof(b),
      "actor=%llx combat=%llx active=%u state=%d next=%d attacking=%.6f dead=%u dead_left=%.6f state_left=%.6f technique=%llx finished=%u movement=%llx target=%llx blocking_target=%llx threats=%u frame_dt=%.6f target_h=#%u/%u blocking_h=#%u/%u zone_targets=%u focused_h=#%u/%u",
      (unsigned long long)(uintptr_t)pc,(unsigned long long)(uintptr_t)cc,
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
    g_guard_armed=0;r->append(r,b);return KAH_OK;
}
static void fp_melee_observe_init(void) {
    /* Verified leaf: Character::body(+0x648)->combatClass(+8). Avoid
     * trusting an SDK table from a different executable revision. */
    g_melee_get_combat=(melee_get_combat_t)combat_unique_signature(
        "48 8B 81 48 06 00 00 48 8B 40 08 C3");
    logline("[melee] uniquely scanned read-only getter %s",g_melee_get_combat?"available":"unavailable");
}
