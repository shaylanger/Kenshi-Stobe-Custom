/* Bounded, allocation-free native combat trace. No engine dependencies. */
#ifndef KFP_COMBAT_TRACE_H
#define KFP_COMBAT_TRACE_H
#include <stdint.h>
#include <string.h>
#define KFP_TRACE_CAPACITY 512
typedef struct {
    uint64_t seq, ms, frame;
    uintptr_t actor, ranged, gun, target;
    int kind, state, mode, ammo, stat;
    float dt;
} KfpCombatEvent;
enum { KFP_EV_FRAME=1, KFP_EV_ANIMATION=2, KFP_EV_SHOT_BEFORE=3,
       KFP_EV_SHOT_AFTER=4 };
typedef struct {
    KfpCombatEvent rows[KFP_TRACE_CAPACITY];
    uint64_t next;
    unsigned count;
} KfpCombatTrace;
static void kfp_trace_reset(KfpCombatTrace *t) {
    memset(t, 0, sizeof(*t)); t->next=1;
}
static void kfp_trace_push(KfpCombatTrace *t, KfpCombatEvent e) {
    e.seq=t->next++;
    t->rows[(e.seq-1)%KFP_TRACE_CAPACITY]=e;
    if (t->count<KFP_TRACE_CAPACITY) ++t->count;
}
static uint64_t kfp_trace_oldest(const KfpCombatTrace *t) {
    return t->next-t->count;
}
static uint64_t kfp_trace_lost(const KfpCombatTrace *t, uint64_t after) {
    uint64_t oldest=kfp_trace_oldest(t);
    if (after>=oldest-1) return 0;
    return oldest-1-after;
}
static const KfpCombatEvent *kfp_trace_get(const KfpCombatTrace *t, uint64_t seq) {
    if (seq<kfp_trace_oldest(t) || seq>=t->next) return 0;
    return &t->rows[(seq-1)%KFP_TRACE_CAPACITY];
}
#endif
