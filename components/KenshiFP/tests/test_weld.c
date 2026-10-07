/* kfp_weld.h: floating-origin rebase decisions (4080 b28 C04-FALLBACK "Loading..." stall). */
#include <assert.h>
#include <stdio.h>
#include "../client/kfp_weld.h"

int main(void)
{
    KfpWeldPend p = {0, 0, 0};
    const float tx = 300.0f, tz = -40.0f;          /* calibrated T */
    /* still on the weld: nothing */
    assert(kfp_weld_step(&p, 302, -41, 301, -40, tx, tz) == KFP_WELD_NONE);
    /* an ordinary rebase (< 100 m, away from T): shift at once, as before */
    assert(kfp_weld_step(&p, 301 + 400, -40, 301, -40, tx, tz) == KFP_WELD_SHIFT && p.n == 0);
    /* b28: one-frame world-scale outlier (-54047.5, +6810.6) then back: never a shift */
    assert(kfp_weld_step(&p, 301 - 54047.5f, -40 + 6810.6f, 301, -40, tx, tz) == KFP_WELD_PENDING && p.n == 1);
    /* caller keeps prev at the pre-jump raw; the next frame is back on the weld */
    assert(kfp_weld_step(&p, 302, -40, 301, -40, tx, tz) == KFP_WELD_NONE && p.n == 0);
    /* the return frame compared against an outlier that slipped into prev (gated frame): no shift either */
    assert(kfp_weld_step(&p, 301, -40, 301 - 54047.5f, -40 + 6810.6f, tx, tz) == KFP_WELD_RETURNED);
    /* a real world-scale rebase holds still: taken after KFP_WELD_CONFIRM frames */
    {
        float rx = 301 + 20000.0f, rz = -40;
        int i; KfpWeldStep s = KFP_WELD_NONE;
        for (i = 1; i <= KFP_WELD_CONFIRM; i++) {
            s = kfp_weld_step(&p, rx + (float)i, rz, 301, -40, tx, tz);
            if (i < KFP_WELD_CONFIRM) assert(s == KFP_WELD_PENDING && p.n == i);
        }
        assert(s == KFP_WELD_SHIFT && p.n == 0);
    }
    /* a jumping (not holding) outlier restarts the confirmation */
    assert(kfp_weld_step(&p, 301 + 5000, -40, 301, -40, tx, tz) == KFP_WELD_PENDING && p.n == 1);
    assert(kfp_weld_step(&p, 301 + 9000, -40, 301, -40, tx, tz) == KFP_WELD_PENDING && p.n == 1);
    /* non-finite centre: never accepted */
    {

        float nan = NAN;
        assert(kfp_weld_step(&p, nan, -40, 301, -40, tx, tz) == KFP_WELD_PENDING && p.n == 0);
    }
    puts("test_weld ok");
    return 0;
}
