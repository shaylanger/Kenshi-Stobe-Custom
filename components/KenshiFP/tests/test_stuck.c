/* Offline: WASD pinned counter restarts on every stand-down (C01/C02/C05, 4080 b30/b31). Mirrors the client call order:
 * driving frames -> kfp_stuck_step; KO/down/fall branch, key release (any), control take/release -> kfp_stuck_idle. */
#include <assert.h>
#include <stdio.h>
#include "../client/kfp_stuck.h"
int main(void){
    int f=0,i,p=0;
    for(i=0;i<10;i++) p=kfp_stuck_step(&f,1,0.0f);
    assert(!p);                                            /* short stall: not pinned yet */
    for(i=0;i<10;i++) p=kfp_stuck_step(&f,1,0.0f);
    assert(p);                                             /* seated body under direct drive: pinned */
    assert(!kfp_stuck_step(&f,1,26.0f));                   /* walking again: clears */
    for(i=0;i<30;i++) kfp_stuck_step(&f,1,0.5f);           /* KO mid-hold: body stops, pinned */
    kfp_stuck_idle(&f);                                    /* KO stand-down (g_was_moving=0, no release branch) */
    for(i=0;i<5;i++) kfp_stuck_idle(&f);                   /* keys released while g_was_moving=0 */
    assert(!kfp_stuck_step(&f,0,0.0f));                    /* next W hold, first frame (speed 0): NOT pinned */
    assert(!kfp_stuck_step(&f,1,0.0f));                    /* first direct frame: NOT pinned */
    for(i=0;i<30;i++) kfp_stuck_step(&f,1,0.0f);
    kfp_stuck_idle(&f);                                    /* control released / another actor taken */
    assert(!kfp_stuck_step(&f,0,3.0f));                    /* new actor first hold starts clean */
    for(i=0;i<1000;i++) kfp_stuck_step(&f,1,0.0f);
    assert(f==600);                                        /* bounded */
    puts("RESULT C05-STUCK PASS pinned counter restarts on KO/down stand-down, key release and control take/release");
    return 0;
}
