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
    /* R12-UI: a press refused only for readiness stays pending while fire+aim are held */
    step(&c,&o,1,0,0);o.shot_ready=0;assert(!step(&c,&o,1,1,0));assert(c.fire_pending&&c.rejected==0);
    assert(!step(&c,&o,1,1,0));
    o.shot_ready=1;assert(step(&c,&o,1,1,0)==KFP_ACT_SHOOT);assert(!c.fire_pending&&c.pending_shots==1);
    for(int i=0;i<40;++i)assert(!step(&c,&o,1,1,0)); /* one press, one shot */
    /* fire release drops the pending press: counted as rejected, with its gates */
    step(&c,&o,1,0,0);o.shot_ready=0;assert(!step(&c,&o,1,1,0));assert(!step(&c,&o,1,0,0));
    assert(!c.fire_pending&&c.rejected==1);
    assert(c.last_reject_aim==1&&c.last_reject.shot_ready==0&&c.last_reject.aim_ready==1&&c.last_reject.ammo==o.ammo); /* R12 last_reject= */
    o.shot_ready=1;assert(!step(&c,&o,1,0,0));
    /* expiry: never fires late (0.5 game s = ~31 frames at .016) */
    o.shot_ready=0;assert(!step(&c,&o,1,1,0));for(int i=0;i<40;++i)assert(!step(&c,&o,1,1,0));
    assert(!c.fire_pending&&c.rejected==2);
    o.shot_ready=1;assert(!step(&c,&o,1,1,0)); /* expired click never deferred */
    /* aim release drops it */
    step(&c,&o,1,0,0);o.shot_ready=0;assert(!step(&c,&o,1,1,0));assert(c.fire_pending);
    assert(step(&c,&o,0,1,0)==KFP_ACT_LOWER);assert(!c.fire_pending&&c.rejected==3);
    o.shot_ready=1;assert(step(&c,&o,1,1,0)==KFP_ACT_RAISE); /* no edge: no shot */
    /* a reload starting drops it; no ammo is refused at once */
    step(&c,&o,1,0,0);o.shot_ready=0;step(&c,&o,1,1,0);assert(c.fire_pending);
    o.reloading=1;assert(!step(&c,&o,1,1,0));assert(!c.fire_pending&&c.rejected==4);
    o.reloading=0;o.ammo=0;step(&c,&o,1,0,0);assert(!(step(&c,&o,1,1,0)&KFP_ACT_SHOOT));assert(!c.fire_pending&&c.rejected==5);
    o.ammo=1;o.shot_ready=1;step(&c,&o,1,0,0);
    /* identity reset (weapon swap / UI / KO -> unusable) drops it */
    o.shot_ready=0;step(&c,&o,1,1,0);assert(c.fire_pending);
    o.allowed=0;assert(step(&c,&o,1,1,0)==KFP_ACT_LOWER);assert(!c.fire_pending&&c.rejected==6);
    o.allowed=1;o.shot_ready=1;assert(!step(&c,&o,1,1,0));arm(&c,&o);step(&c,&o,1,0,0);
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
    puts("RESULT B10 PASS native-gated action decisions, click edges/readiness-pending press (held, 0.5 s, one shot)/no deferred AI queue, interruption rearming, own-recovery buffer expiry/no refresh, block commitment");
}
