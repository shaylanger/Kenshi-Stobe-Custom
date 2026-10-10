/* Swing hits all (setting swing_hits_all, F10 "Swing hits all", default OFF; Shay 2026-10-10).
 * A manual FP melee swing hits every valid character inside the NATIVE swing area, own squad and neutrals too, not
 * only enemies + the current target. Everything after the target list stays native: impact/defence/damage/injury,
 * the per-technique hit cap (technique+0x54), aggro of a hit neutral.
 * RE (installed exe, KenshiLib names):
 *  - CombatClass::attackState (0x609B00) at the hit point: calculateTargetsInAttackZone (0x607D10) then
 *    attackImpactCheck (0x609860, only caller), which hits up to technique+0x54 entries of targetsInAttackZone
 *    (+0x1D8 lektor<hand>: count +0x1E0, data +0x1E8; computed once per frame, flag +0x1D4).
 *  - calculateTargetsInAttackZone keeps, from a spatial query around the swing: buildings, and characters that are
 *    NOT me->isAlly(c,0) (Character vt+0x3F0), NOT c->isLiterallyUnconcious (vt+0x358) and either me->isEnemy(c,1)
 *    (vt+0x3E8) or c == the target (+0x290) (or a 0x8805 special case). me = cc+0x188.
 * Hook: attackImpactCheck. Setting on + cc == the FP-owned fighter (g_melee_owned_cc): clear +0x1D4, recompute the
 * list with isAlly(me,c)=false and isEnemy(me,c)=true for c != me (only while this thread runs that call), then the
 * native impact check. Unconscious/dead stay skipped (native). The isAlly/isEnemy hooks pass straight through
 * otherwise (one compare). */
typedef void (*sha_cc_t)(void *cc);
typedef char (*sha_rel_t)(void *self,void *who,char disguise);
static sha_cc_t g_sha_impact_orig,g_sha_calc;
static sha_rel_t g_sha_isally_orig,g_sha_isenemy_orig;
static void *volatile g_sha_me;          /* attacker while the widened list is computed, else NULL */
static void *g_sha_tgt;
static DWORD g_sha_tid;
static int g_sha_ready;
static unsigned g_sha_swings,g_sha_widened,g_sha_cur_extra,g_sha_last_n,g_sha_last_extra,g_sha_skipped_off,g_sha_skipped_unowned;
#define SHA_CC_ME 0x188
#define SHA_CC_TARGET 0x290
#define SHA_CC_ZONE_DONE 0x1D4
#define SHA_CC_ZONE_N 0x1E0
static int sha_scoped(void *self,void *who) {
    return g_sha_me && self==g_sha_me && who && who!=self && GetCurrentThreadId()==g_sha_tid;
}
static char sha_isally_hook(void *self,void *who,char d) {
    if (sha_scoped(self,who)) return 0;
    return g_sha_isally_orig(self,who,d);
}
static char sha_isenemy_hook(void *self,void *who,char d) {
    if (sha_scoped(self,who)) {
        if (who!=g_sha_tgt && !g_sha_isenemy_orig(self,who,d)) g_sha_cur_extra++;   /* ally/neutral the native list drops */
        return 1;
    }
    return g_sha_isenemy_orig(self,who,d);
}
static void sha_impact_hook(void *cc) {
    if (cc && g_sha_ready) {
        if (!g_cfg_swing_hits_all) g_sha_skipped_off++;
        else if (cc!=g_melee_owned_cc) g_sha_skipped_unowned++;
        else {
            void *me=*(void **)((uintptr_t)cc+SHA_CC_ME);
            if (me) {
                g_sha_tgt=*(void **)((uintptr_t)cc+SHA_CC_TARGET);
                g_sha_cur_extra=0;g_sha_tid=GetCurrentThreadId();
                *(unsigned char *)((uintptr_t)cc+SHA_CC_ZONE_DONE)=0;
                g_sha_me=me;
                g_sha_calc(cc);
                g_sha_me=NULL;
                g_sha_swings++;g_sha_last_n=*(unsigned *)((uintptr_t)cc+SHA_CC_ZONE_N);g_sha_last_extra=g_sha_cur_extra;
                if (g_sha_cur_extra) {g_sha_widened++;logline("[melee] swing_all: zone=%u extra=%u (allies/neutrals in the swing area)",g_sha_last_n,g_sha_cur_extra);}
            }
        }
    }
    g_sha_impact_orig(cc);
}
/* the KenshiLib address must be the function the RE above describes: look for its +0x1D4 / +0x1E0 field use */
static int sha_has(const void *fn,const unsigned char *pat,int n,int span) {
    const unsigned char *p=(const unsigned char *)fn;
    if (!fn) return 0;
    for (int i=0;i+n<=span;i++) if (!memcmp(p+i,pat,n)) return 1;
    return 0;
}
static void fp_swing_all_init(void) {
    void *calc=fpc_klib_real("?calculateTargetsInAttackZone@CombatClass@@QEAAXXZ");
    void *imp=fpc_klib_real("?attackImpactCheck@CombatClass@@QEAAXXZ");
    void *ally=fpc_klib_real("?isAlly@Character@@UEAA_NPEAV1@_N@Z");
    void *enemy=fpc_klib_real("?isEnemy@Character@@UEAA_NPEAV1@_N@Z");
    static const unsigned char calc_pat[]={0x80,0xB9,0xD4,0x01,0x00,0x00,0x00};   /* cmp byte [rcx+0x1D4],0 */
    static const unsigned char imp_pat[]={0xE0,0x01,0x00,0x00};                     /* [rcx+0x1E0] count */
    int sane=sha_has(calc,calc_pat,(int)sizeof calc_pat,0x60) && sha_has(imp,imp_pat,(int)sizeof imp_pat,0x60);
    g_sha_calc=(sha_cc_t)calc;
    if (calc && imp && ally && enemy && sane)
        g_sha_ready=install_hook(ally,(void *)sha_isally_hook,(void **)&g_sha_isally_orig) &&
                    install_hook(enemy,(void *)sha_isenemy_hook,(void **)&g_sha_isenemy_orig) &&
                    install_hook(imp,(void *)sha_impact_hook,(void **)&g_sha_impact_orig);
    logline("[melee] swing_all calc=%p impact=%p isAlly=%p isEnemy=%p sane=%d ready=%d setting=%d",
        calc,imp,ally,enemy,sane,g_sha_ready,g_cfg_swing_hits_all);
}
/* fp_melee swing_all [reset]: setting, hook state and counters */
static int fp_swing_all_cmd(int argc,const char *const *argv,KAH_Reply *r) {
    if (argc==3) {
        if (_stricmp(argv[2],"reset")) {r->append(r,"usage: fp_melee swing_all [reset]");return KAH_ERROR;}
        g_sha_swings=g_sha_widened=g_sha_last_n=g_sha_last_extra=g_sha_skipped_off=g_sha_skipped_unowned=0;
    }
    char b[256];
    snprintf(b,sizeof b,"swing_all setting=%d ready=%d swings=%u widened=%u last_zone=%u last_extra=%u skipped_off=%u skipped_unowned=%u owned=%d",
        g_cfg_swing_hits_all,g_sha_ready,g_sha_swings,g_sha_widened,g_sha_last_n,g_sha_last_extra,g_sha_skipped_off,g_sha_skipped_unowned,g_melee_owned_cc!=NULL);
    r->append(r,b);return KAH_OK;
}
