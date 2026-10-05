#ifndef KFP_COMBAT_CONTROLLER_H
#define KFP_COMBAT_CONTROLLER_H
#include <stdint.h>
#include <string.h>
#include <math.h>
/* Decisions never fabricate readiness, damage, ammo or animation time.
 * Engine adapter supplies observed native gates and performs native actions. */
enum { KFP_WEAPON_NONE, KFP_WEAPON_RANGED, KFP_WEAPON_MELEE };
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
    unsigned rejected, shots, swings, blocks, reloads;
} KfpCombatController;
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
        if (fire_edge) {
            if (aim && o->aim_ready && o->shot_ready && o->ammo>0 && !o->reloading) {
                actions|=KFP_ACT_SHOOT;++c->shots;
            } else ++c->rejected;
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
            } else ++c->rejected;
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
