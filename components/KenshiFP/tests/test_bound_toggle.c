#include <assert.h>
#include <stdio.h>
#include "../client/kfp_bound_toggle.h"

int main(void)
{
    /* the CS05 case: FP on, freecam 0->1 right after a swallowed bound key */
    assert(kfp_bound_toggle_revert(1, 0, 1, 1, 1000, 950));
    /* deliberate free-cam on an unbound key: no swallow seen -> keep it */
    assert(!kfp_bound_toggle_revert(1, 0, 1, 0, 1000, 0));
    /* swallow long ago -> keep */
    assert(!kfp_bound_toggle_revert(1, 0, 1, 1, 5000, 1000));
    assert(!kfp_bound_toggle_revert(1, 0, 1, 1, 1000 + KFP_BOUND_TOGGLE_MS, 1000));
    assert(kfp_bound_toggle_revert(1, 0, 1, 1, 1000 + KFP_BOUND_TOGGLE_MS - 1, 1000));
    /* already free last frame (not an edge) -> keep, never clear every frame */
    assert(!kfp_bound_toggle_revert(1, 1, 1, 1, 1000, 990));
    /* FP off -> vanilla owns the camera */
    assert(!kfp_bound_toggle_revert(0, 0, 1, 1, 1000, 990));
    /* no toggle */
    assert(!kfp_bound_toggle_revert(1, 0, 0, 1, 1000, 990));
    /* GetTickCount wrap */
    assert(kfp_bound_toggle_revert(1, 0, 1, 1, 50u, 0xFFFFFFF0u));
    puts("RESULT bound_toggle PASS 9 cases");
    return 0;
}
