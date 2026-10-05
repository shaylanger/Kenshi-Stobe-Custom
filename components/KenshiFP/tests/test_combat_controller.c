#include <assert.h>
#include <stdio.h>
#include "../client/kfp_combat_controller.h"
static KfpCombatObservation base(int kind) {
    KfpCombatObservation o={0};
    o.actor=11;o.weapon=22;o.enabled=o.allowed=o.running=1;o.kind=kind;
    o.aim_ready=o.shot_ready=o.swing_ready=o.block_ready=1;
    o.ammo=1;o.reload_allowed=1;o.dt=.016f;return o;
}
static unsigned step(KfpCombatController *c,KfpCombatObservation *o,int aim,int fire,int reload) {
    KfpCombatInput in={aim,fire,reload};return kfp_combat_step(c,o,in,1,.12f);
}
static void arm(KfpCombatController *c,KfpCombatObservation *o) {
    step(c,o,0,0,0);step(c,o,0,0,0);assert(c->armed);
}
int main(void) {
    KfpCombatController c={0};KfpCombatObservation o=base(KFP_WEAPON_RANGED);
    assert(!step(&c,&o,1,1,0));assert(!step(&c,&o,1,1,0));
    arm(&c,&o);
    assert(step(&c,&o,1,0,0)==KFP_ACT_RAISE);
    assert(step(&c,&o,1,1,0)==KFP_ACT_SHOOT);
    for(int i=0;i<60;++i)assert(!step(&c,&o,1,1,0));
    step(&c,&o,1,0,0);o.shot_ready=0;assert(!step(&c,&o,1,1,0));
    o.shot_ready=1;assert(!step(&c,&o,1,1,0)); /* rejected click never deferred */
    step(&c,&o,1,0,0);assert(step(&c,&o,1,1,0)==KFP_ACT_SHOOT);
    o.reloading=1;o.ammo=0;step(&c,&o,1,0,0);
    assert(!step(&c,&o,1,1,1));
    o.reloading=0;assert(step(&c,&o,1,0,0)==KFP_ACT_RELOAD);
    o.reload_allowed=0;assert(!step(&c,&o,1,0,0));
    o.allowed=0;assert(step(&c,&o,1,1,0)==KFP_ACT_LOWER);
    o.allowed=1;o.ammo=1;assert(!step(&c,&o,1,1,0));
    arm(&c,&o);step(&c,&o,1,0,0);o.weapon=99;
    assert(step(&c,&o,1,1,0)==KFP_ACT_LOWER);
    assert(!step(&c,&o,1,1,0));arm(&c,&o);
    step(&c,&o,1,0,0);o.running=0;assert(step(&c,&o,1,1,0)==KFP_ACT_LOWER);
    o.running=1;assert(!step(&c,&o,1,1,0));arm(&c,&o);
    o.dt=NAN;assert(!step(&c,&o,0,1,0));o.dt=.016f;arm(&c,&o);
    memset(&c,0,sizeof(c));o=base(KFP_WEAPON_MELEE);arm(&c,&o);
    assert(step(&c,&o,0,1,0)==KFP_ACT_SWING);
    o.committed=1;o.swing_ready=o.block_ready=0;
    for(int i=0;i<10;++i) {step(&c,&o,1,0,0);assert(!step(&c,&o,1,1,0));}
    assert(!c.buffer);o.committed=0;o.recovery=1;o.recovery_left=.10f;
    step(&c,&o,0,0,0);assert(!step(&c,&o,0,1,0));assert(c.buffer);
    step(&c,&o,0,0,0);assert(!step(&c,&o,0,1,0)); /* cannot refresh existing buffer */
    o.recovery=0;o.swing_ready=1;
    assert(step(&c,&o,0,1,0)==KFP_ACT_SWING);assert(!c.buffer);
    assert(!step(&c,&o,0,1,0));
    o.recovery=1;o.swing_ready=0;o.recovery_left=.10f;
    step(&c,&o,0,0,0);step(&c,&o,0,1,0);assert(c.buffer);
    for(int i=0;i<10;++i)step(&c,&o,0,1,0);
    assert(!c.buffer);o.recovery=0;o.swing_ready=1;assert(!step(&c,&o,0,1,0));
    o.block_ready=1;assert(step(&c,&o,1,0,0)==KFP_ACT_BLOCK);
    assert(!step(&c,&o,1,0,0));o.block_ready=0;assert(!step(&c,&o,1,0,0));
    o.block_ready=1;assert(step(&c,&o,1,0,0)==KFP_ACT_BLOCK);
    assert(!step(&c,&o,1,1,0)); /* defence wins simultaneous input */
    o.actor=77;assert(!step(&c,&o,1,1,0));assert(!c.buffer&&!c.armed);
    puts("RESULT B10 PASS native-gated action decisions, click edges/no deferred AI queue, interruption rearming, own-recovery buffer expiry/no refresh, block commitment");
}
