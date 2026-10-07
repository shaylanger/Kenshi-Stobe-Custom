#include <assert.h>
#include <stdio.h>
#include "../client/kfp_ready_latch.h"
int main(void) {
    KfpReadyLatch l={0};const float W=0.25f,dt=1.0f/60;
    /* never ready natively -> never ready */
    for(int i=0;i<10;++i) assert(!kfp_ready_latch_step(&l,0,1,7,dt,W));
    /* ready, then one-frame dips (the R12 flicker) are bridged */
    assert(kfp_ready_latch_step(&l,1,1,7,dt,W));
    assert(kfp_ready_latch_step(&l,0,1,7,dt,W));
    assert(kfp_ready_latch_step(&l,0,1,7,dt,W));
    assert(kfp_ready_latch_step(&l,1,1,7,dt,W));
    assert(l.bridged==2);
    /* a real pose break (longer than the window) drops readiness */
    int r=1,n=0;for(n=0;n<40&&r;++n) r=kfp_ready_latch_step(&l,0,1,7,dt,W);
    assert(!r && n>=15 && n<=17);
    assert(!kfp_ready_latch_step(&l,0,1,7,dt,W));      /* stays 0 until native ready again */
    /* hold broken (aim release / reload / ammo 0 / UI / truce) clears at once */
    assert(kfp_ready_latch_step(&l,1,1,7,dt,W));
    assert(!kfp_ready_latch_step(&l,0,0,7,dt,W));
    assert(!kfp_ready_latch_step(&l,0,1,7,dt,W));      /* not re-latched by restoring the hold */
    assert(!kfp_ready_latch_step(&l,1,0,7,dt,W));      /* native ready without the hold = not ready */
    /* identity change (actor/weapon swap) clears */
    assert(kfp_ready_latch_step(&l,1,1,7,dt,W));
    assert(!kfp_ready_latch_step(&l,0,1,8,dt,W));
    assert(!kfp_ready_latch_step(&l,0,1,8,dt,W));
    /* a shot resets: the next 0 frame is not ready */
    assert(kfp_ready_latch_step(&l,1,1,8,dt,W));
    kfp_ready_latch_reset(&l);
    assert(!kfp_ready_latch_step(&l,0,1,8,dt,W));
    /* paused frames (dt 0) keep a latch without using the window; bad dt/window clear */
    assert(kfp_ready_latch_step(&l,1,1,8,dt,W));
    for(int i=0;i<100;++i) assert(kfp_ready_latch_step(&l,0,1,8,0.0f,W));
    assert(!kfp_ready_latch_step(&l,0,1,8,-1.0f,W));
    assert(kfp_ready_latch_step(&l,1,1,8,dt,W));
    assert(!kfp_ready_latch_step(&l,0,1,8,dt,0.0f));
    /* a dip that starts on a hitch frame (dt over the window) is still bridged on that frame
     * (4080 b29/b30: the trigger landed on it and was refused); the next dip frame is not */
    {KfpReadyLatch h={0};
     assert(kfp_ready_latch_step(&h,1,1,9,dt,W));      /* identity adopted */
     assert(kfp_ready_latch_step(&h,1,1,9,dt,W));      /* latched */
     assert(kfp_ready_latch_step(&h,0,1,9,0.30f,W));
     assert(h.bridged==1);
     assert(!kfp_ready_latch_step(&h,0,1,9,dt,W));
     assert(kfp_ready_latch_step(&h,1,1,9,dt,W));
     assert(kfp_ready_latch_step(&h,0,1,9,0.30f,W));   /* each new dip gets its first frame */
    }
    puts("ready latch ok");
    return 0;
}
