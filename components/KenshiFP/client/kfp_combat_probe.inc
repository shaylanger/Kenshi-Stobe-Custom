/* Observational prerequisite only. No combat, camera, actor or AI writes.
 * Include before KAH handlers; all callbacks and capture run on game thread.
 * Raw state integers are deliberately not translated into inferred readiness. */
#include "kfp_combat_trace.h"
#include <errno.h>
static KfpCombatTrace g_combat_trace = { .next=1 };
static int g_combat_probe_active;
static uint64_t g_combat_probe_capture;
static uint64_t g_combat_probe_frame;
static KfpCombatEvent g_combat_probe_previous;
static int g_combat_probe_have_previous;

static KfpCombatEvent fp_combat_snapshot(void *actor, void *rc, void *gun,
                                        void *target, int kind) {
    KfpCombatEvent e;
    memset(&e,0,sizeof(e));
    e.ms=GetTickCount64(); e.frame=g_combat_probe_frame; e.dt=g_frame_dt;
    e.kind=kind; e.actor=(uintptr_t)actor; e.target=(uintptr_t)target;
    e.state=e.mode=e.ammo=e.stat=-1;
    if (!rc && actor && readable((void *)((uintptr_t)actor+CHAR_RANGEDCOMBAT),8))
        rc=*(void **)((uintptr_t)actor+CHAR_RANGEDCOMBAT);
    e.ranged=(uintptr_t)rc;
    if (rc && readable((void *)((uintptr_t)rc+RC_STATE_OFF),4))
        e.state=*(int *)((uintptr_t)rc+RC_STATE_OFF);
    if (rc && readable((void *)((uintptr_t)rc+RC_COMBATMODE),1))
        e.mode=*(unsigned char *)((uintptr_t)rc+RC_COMBATMODE);
    if (rc && readable((void *)((uintptr_t)rc+RC_STAT),4))
        e.stat=*(int *)((uintptr_t)rc+RC_STAT);
    if (!gun && rc && readable((void *)((uintptr_t)rc+RC_GUN),8))
        gun=*(void **)((uintptr_t)rc+RC_GUN);
    e.gun=(uintptr_t)gun;
    if (gun && readable((void *)((uintptr_t)gun+GUN_AMMO),4))
        e.ammo=*(int *)((uintptr_t)gun+GUN_AMMO);
    return e;
}
static void fp_combat_tick(void *gw, float time) {
    (void)time;
    ++g_combat_probe_frame;
    if (!g_combat_probe_active) return;
    void *actor=fp_controlled_char(gw);
    KfpCombatEvent e=fp_combat_snapshot(actor,NULL,NULL,NULL,KFP_EV_FRAME);
    KfpCombatEvent *p=&g_combat_probe_previous;
    if (!g_combat_probe_have_previous || e.actor!=p->actor || e.ranged!=p->ranged
        || e.gun!=p->gun || e.state!=p->state || e.mode!=p->mode
        || e.ammo!=p->ammo || e.stat!=p->stat) {
        kfp_trace_push(&g_combat_trace,e);
        *p=e; g_combat_probe_have_previous=1;
    }
}
static void fp_combat_probe_animation(void *rc, void *target) {
    if (!g_combat_probe_active || !rc ||
        !readable((void *)((uintptr_t)rc+RC_ME),8)) return;
    void *actor=*(void **)((uintptr_t)rc+RC_ME);
    if (!g_combat_probe_have_previous || actor!=(void *)g_combat_probe_previous.actor) return;
    kfp_trace_push(&g_combat_trace,fp_combat_snapshot(actor,rc,NULL,target,KFP_EV_ANIMATION));
}
static void fp_combat_probe_shot(void *gun, void *actor, void *target, int stat, int kind) {
    if (!g_combat_probe_active || !g_combat_probe_have_previous ||
        actor!=(void *)g_combat_probe_previous.actor) return;
    KfpCombatEvent e=fp_combat_snapshot(actor,NULL,gun,target,kind);
    e.stat=stat; /* actual call argument, not a reconstructed skill */
    kfp_trace_push(&g_combat_trace,e);
}
static int kah_fp_combat_probe(const char *id,int argc,const char *const *argv,
                               KAH_Reply *r,void *u) {
    (void)id; (void)u;
    if (argc<2) { r->append(r,"usage: fp_combat_probe begin|end|state|events [after_sequence]|clear"); return KAH_ERROR; }
    if (_stricmp(argv[1],"events") && argc!=2) {
        r->append(r,"probe action takes no extra arguments"); return KAH_ERROR;
    }
    if (!_stricmp(argv[1],"begin")) {
        ++g_combat_probe_capture;
        kfp_trace_reset(&g_combat_trace); g_combat_probe_frame=0;
        g_combat_probe_have_previous=0; g_combat_probe_active=1;
        char b[100];
        snprintf(b,sizeof(b),"recording=1 manual_dispatch=0 capture=%llu",(unsigned long long)g_combat_probe_capture);
        r->append(r,b); return KAH_OK;
    }
    if (!_stricmp(argv[1],"end")) g_combat_probe_active=0;
    else if (!_stricmp(argv[1],"clear")) {
        ++g_combat_probe_capture;
        kfp_trace_reset(&g_combat_trace); g_combat_probe_have_previous=0;
    } else if (!_stricmp(argv[1],"events")) {
        uint64_t after=0;
        if (argc>3) { r->append(r,"usage: fp_combat_probe events [after_sequence]"); return KAH_ERROR; }
        if (argc==3) {
            if (!argv[2][0]) { r->append(r,"invalid sequence"); return KAH_ERROR; }
            for (const char *s=argv[2];*s;++s)
                if (*s<'0'||*s>'9') { r->append(r,"invalid sequence"); return KAH_ERROR; }
            char *end=NULL; errno=0; after=strtoull(argv[2],&end,10);
            if (errno || !end || *end) { r->append(r,"invalid sequence"); return KAH_ERROR; }
        }
        char b[384];
        if (after>=g_combat_trace.next && g_combat_trace.next) {
            r->append(r,"sequence beyond capture; begin/clear resets sequence"); return KAH_ERROR;
        }
        snprintf(b,sizeof(b),"capture=%llu next=%llu oldest=%llu lost=%llu count=%u\n",
                 (unsigned long long)g_combat_probe_capture,
                 (unsigned long long)g_combat_trace.next,
                 (unsigned long long)kfp_trace_oldest(&g_combat_trace),
                 (unsigned long long)kfp_trace_lost(&g_combat_trace,after),
                 g_combat_trace.count);
        r->append(r,b);
        uint64_t seq=after+1,oldest=kfp_trace_oldest(&g_combat_trace);
        if (seq<oldest) seq=oldest;
        unsigned emitted=0;
        for (;seq<g_combat_trace.next && emitted<64;++seq,++emitted) {
            const KfpCombatEvent *e=kfp_trace_get(&g_combat_trace,seq);
            snprintf(b,sizeof(b),"%llu,%llu,%llu,%d,%llx,%llx,%llx,%llx,%d,%d,%d,%d,%.6f\n",
              (unsigned long long)e->seq,(unsigned long long)e->ms,(unsigned long long)e->frame,e->kind,
              (unsigned long long)e->actor,(unsigned long long)e->ranged,(unsigned long long)e->gun,
              (unsigned long long)e->target,e->state,e->mode,e->ammo,e->stat,e->dt);
            r->append(r,b);
        }
        snprintf(b,sizeof(b),"through=%llu more=%d\n",(unsigned long long)(seq-1),seq<g_combat_trace.next);
        r->append(r,b);
        return KAH_OK;
    } else if (_stricmp(argv[1],"state")) {
        r->append(r,"unknown probe action"); return KAH_ERROR;
    }
    char b[160];
    snprintf(b,sizeof(b),"recording=%d frame=%llu next=%llu count=%u manual_dispatch=0 actor_observed=%d capture=%llu",
        g_combat_probe_active,(unsigned long long)g_combat_probe_frame,
        (unsigned long long)g_combat_trace.next,g_combat_trace.count,g_combat_probe_have_previous && g_combat_probe_previous.actor!=0,(unsigned long long)g_combat_probe_capture);
    r->append(r,b); return KAH_OK;
}
