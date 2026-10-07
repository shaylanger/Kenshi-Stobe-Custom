/* kfp_fling.h: C05-KO fling guard (4080 b36b numbers). */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../client/kfp_fling.h"
int main(void)
{
    KfpFling f; memset(&f, 0, sizeof f);
    unsigned t = 1000;
    /* standing direct-drive walk at 55 u/s, 16 ms samples: never a fling */
    for (int i = 0; i < 20; ++i, t += 16) assert(kfp_fling_step(&f, 0, -54064.3f, 645.0f, 6790.0f - i * 0.9f, t) == 0);
    /* KO edge: ragdoll lifts the root 10 units, then rolls a little */
    assert(kfp_fling_step(&f, 1, -54063.9f, 654.1f, 6783.5f, t) == 0); t += 25;
    assert(kfp_fling_step(&f, 1, -54063.9f, 654.0f, 6783.0f, t) == 0); t += 25;
    /* b36b: one-sample jump of 1234 units while down -> detected, anchor frozen at the pre-jump point */
    assert(kfp_fling_step(&f, 1, -55240.2f, 928.8f, 6931.4f, t) == KFP_FLING_DETECTED); t += 25;
    assert(f.detections == 1 && f.ax == -54063.9f && f.az == 6783.0f);
    for (int i = 0; i < 10; ++i, t += 30) assert(kfp_fling_step(&f, 1, -55240.2f, 928.8f, 6931.4f, t) == 0);
    assert(f.ax == -54063.9f);   /* no re-anchor at the flung spot */
    /* wake edge -> restore to the anchor */
    assert(kfp_fling_step(&f, 0, -55240.2f, 928.8f, 6931.4f, t) == KFP_FLING_RESTORE); t += 16;
    assert(f.restored == 1);
    /* next sample is at the anchor (teleported): not a jump */
    assert(kfp_fling_step(&f, 0, -54063.9f, 654.0f, 6783.0f, t) == 0); t += 16;
    /* post-wake drift (b36b: kilometres in seconds) inside the watch window -> restored again */
    assert(kfp_fling_step(&f, 0, -54163.9f, 660.0f, 6800.0f, t) == KFP_FLING_RESTORE); t += 16;
    assert(f.ax == -54063.9f && f.restored == 2);
    /* normal walking after the restore re-anchors */
    assert(kfp_fling_step(&f, 0, -54063.9f, 654.0f, 6783.0f, t) == 0); t += 16;
    assert(kfp_fling_step(&f, 0, -54063.9f, 654.0f, 6782.1f, t) == 0); t += 16;
    assert(f.az == 6782.1f);
    /* after the watch window a big move (harness teleport) is NOT reverted */
    t += KFP_FLING_WATCH_MS + 10;
    assert(kfp_fling_step(&f, 0, -54063.9f, 654.0f, 6782.0f, t) == 0); t += 16;
    assert(kfp_fling_step(&f, 0, -40000.0f, 700.0f, 1000.0f, t) == 0); t += 16;
    /* stationary KO without a fling: wake restores nothing */
    assert(kfp_fling_step(&f, 1, -40000.0f, 710.0f, 1000.0f, t) == 0); t += 30;
    assert(kfp_fling_step(&f, 0, -40000.0f, 700.0f, 1000.0f, t) == 0); t += 30;
    /* a big gap (FP off / load) is never compared */
    assert(kfp_fling_step(&f, 0, 0.0f, 0.0f, 0.0f, t + 5000) == 0);
    /* a legit fast fall (775 u/s, 16 ms) is not a fling */
    assert(!kfp_fling_is_jump(0, -12.4f, 0, 16));
    /* restore budget: a body that keeps flinging is restored at most MAX times per episode */
    memset(&f, 0, sizeof f); t = 100;
    kfp_fling_step(&f, 0, 0, 0, 0, t); t += 16;
    kfp_fling_step(&f, 1, 0, 10, 0, t); t += 16;
    kfp_fling_step(&f, 0, 0, 0, 0, t); t += 16;   /* wake: watch on */
    int restores = 0;
    for (int i = 0; i < 20; ++i, t += 16) if (kfp_fling_step(&f, 0, 5000.0f, 0, 0, t) == KFP_FLING_RESTORE) ++restores;
    assert(restores == KFP_FLING_MAX_RESTORES);
    kfp_fling_reset(&f); assert(f.restored == KFP_FLING_MAX_RESTORES && !f.have_prev);
    printf("test_fling OK\n");
    return 0;
}
