#ifndef KFP_COMBAT_CONTROLLER_H
#define KFP_COMBAT_CONTROLLER_H
#include <stdint.h>
#include <string.h>
#include <math.h>
/* Decisions never fabricate readiness, damage, ammo or animation time.
 * Engine adapter supplies observed native gates and performs native actions. */
enum { KFP_WEAPON_NONE, KFP_WEAPON_RANGED, KFP_WEAPON_MELEE };
/* R12-UI (4080 b33): a ranged fire press refused only for readiness (aim held, ammo, no reload; the
 * pose/aim timer not ready yet, e.g. a native ready dip past the latch window) stays pending while
 * fire AND aim stay held, for at most this many game seconds, and fires on the first ready frame.
 * Release, a reload, no ammo, expiry, or any identity/usable reset (UI open, KO, weapon swap) drop it;
 * only then is the edge counted as rejected. No AI queue: one press -> at most one shot. */
#define KFP_FIRE_PENDING_S 0.5f
enum { KFP_ACT_RAISE=1, KFP_ACT_LOWER=2, KFP_ACT_SHOOT=4,
       KFP_ACT_RELOAD=8, KFP_ACT_SWING=16, KFP_ACT_BLOCK=32 };
typedef struct {
    uint64_t actor, weapon;
    int enabled, allowed, running, kind, aim_ready, shot_ready;
    int ammo, reloading, reload_allowed, swing_ready, block_ready;
    int committed, recovery;
    float recovery_left, dt;
} KfpCombatObservation;
typedef struct { int aim, fire, reload; } KfpCombatInput;
typedef struct {
    uint64_t actor, weapon;
    int kind, armed, aimed, fire_prev, reload_prev, block_prev;
    int buffer, block_ready_prev;
    float buffer_left;
    int fire_pending; float fire_pending_left;
    unsigned rejected, shots, swings, blocks, reloads, pending_shots;
    /* Gates seen by the last rejected fire edge (R12 diagnostics: fp_combat state last_reject=). */
    KfpCombatObservation last_reject;
    int last_reject_aim;
} KfpCombatController;
static void kfp_combat_reject(KfpCombatController *c,const KfpCombatObservation *o,int aim) {
    ++c->rejected;c->last_reject=*o;c->last_reject_aim=aim;
}
static unsigned kfp_combat_step(KfpCombatController *c,
        const KfpCombatObservation *o, KfpCombatInput in, int automatic_reload, float buffer_window) {
    unsigned actions=0;
    int fire=!!in.fire,reload=!!in.reload,aim=!!in.aim;
    int identity=c->actor!=o->actor || c->weapon!=o->weapon || c->kind!=o->kind;
    int usable=o->enabled && o->allowed && o->running && o->actor && o->weapon &&
               o->kind!=KFP_WEAPON_NONE && isfinite(o->dt) && o->dt>0;
    if (identity || !usable) {
        if (c->aimed) actions|=KFP_ACT_LOWER;
        c->actor=o->actor; c->weapon=o->weapon; c->kind=o->kind;
        c->armed=0; c->aimed=0; c->buffer=0; c->buffer_left=0;
        if (c->fire_pending) kfp_combat_reject(c,o,aim);
        c->fire_pending=0; c->fire_pending_left=0;
        c->fire_prev=fire; c->reload_prev=reload; c->block_prev=aim;
        c->block_ready_prev=0;
        /* Changing actor/weapon, resuming or closing UI cannot inherit a click. */
        return actions;
    }
    if (!c->armed) {
        c->fire_prev=fire;c->reload_prev=reload;c->block_prev=aim;
        if (!fire && !reload && !aim) c->armed=1;
        return actions;
    }
    int fire_edge=fire&&!c->fire_prev, reload_edge=reload&&!c->reload_prev;
    c->fire_prev=fire;c->reload_prev=reload;
    if (o->kind==KFP_WEAPON_RANGED) {
        c->buffer=0;
        if (aim&&!c->aimed) {c->aimed=1;actions|=KFP_ACT_RAISE;}
        if (!aim&&c->aimed) {c->aimed=0;actions|=KFP_ACT_LOWER;}
        int ready=aim && o->aim_ready && o->shot_ready && o->ammo>0 && !o->reloading;
        if (c->fire_pending) {
            c->fire_pending_left-=o->dt;
            if (ready) {
                c->fire_pending=0;actions|=KFP_ACT_SHOOT;++c->shots;++c->pending_shots;
            } else if (!fire || !aim || o->ammo<=0 || o->reloading || c->fire_pending_left<=0) {
                c->fire_pending=0;kfp_combat_reject(c,o,aim);
            }
        }
        if (fire_edge && !(actions&KFP_ACT_SHOOT)) {
            if (ready) {
                c->fire_pending=0;actions|=KFP_ACT_SHOOT;++c->shots;
            } else if (aim && o->ammo>0 && !o->reloading) {
                c->fire_pending=1;c->fire_pending_left=KFP_FIRE_PENDING_S;   /* readiness only: wait */
            } else kfp_combat_reject(c,o,aim);
        }
        if ((reload_edge || (automatic_reload && aim && o->ammo==0)) &&
            o->reload_allowed && !o->reloading && o->ammo==0) {
            actions|=KFP_ACT_RELOAD;++c->reloads;
        }
    } else {
        if (c->aimed) {c->aimed=0;actions|=KFP_ACT_LOWER;}
        if (!isfinite(buffer_window)||buffer_window<0) buffer_window=0;
        if (buffer_window>.20f) buffer_window=.20f;
        if (c->buffer) {
            c->buffer_left-=o->dt;
            if (c->buffer_left<=0 || aim || o->committed) c->buffer=0;
        }
        if (fire_edge) {
            if (!aim && o->swing_ready && !o->committed && !o->recovery) {
                actions|=KFP_ACT_SWING; c->buffer=0; ++c->swings;
            } else if (!aim && !o->committed && o->recovery && buffer_window>0 &&
                       isfinite(o->recovery_left) && o->recovery_left>=0 &&
                       o->recovery_left<=buffer_window && !c->buffer) {
                c->buffer=1;c->buffer_left=buffer_window;
            } else kfp_combat_reject(c,o,aim);
        }
        if (c->buffer && o->swing_ready && !o->committed && !o->recovery && !aim &&
            !(actions&KFP_ACT_SWING)) {
            c->buffer=0;actions|=KFP_ACT_SWING;++c->swings;
        }
        if (aim && o->block_ready && !o->committed && !(actions&KFP_ACT_SWING) &&
            (!c->block_prev || !c->block_ready_prev)) {
            c->buffer=0;actions|=KFP_ACT_BLOCK;++c->blocks;
        }
        c->block_prev=aim;c->block_ready_prev=o->block_ready;
    }
    return actions;
}
#endif
