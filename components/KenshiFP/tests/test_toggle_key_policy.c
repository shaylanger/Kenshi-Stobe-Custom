#include "../client/fp_toggle_key_policy.h"

#include <stdio.h>

static int checks;
static int check(int ok, const char *message)
{
    ++checks;
    if (ok) return 1;
    fprintf(stderr, "FAIL fp_toggle_key_policy: %s\n", message);
    return 0;
}

int main(void)
{
    int previous_key = 0xA5;
    int was_down = 0;

    if (!check(kfp_toggle_key_rebase(0x41, &previous_key, 1, &was_down),
               "changed binding is rebased")) return 1;
    if (!check(previous_key == 0x41 && was_down == 1,
               "held capture gesture is latched down")) return 1;
    if (!check(!kfp_toggle_key_pressed_edge(1, &was_down),
               "capture gesture cannot toggle after closing settings")) return 1;
    if (!check(!kfp_toggle_key_pressed_edge(1, &was_down),
               "held key cannot repeat toggle")) return 1;
    if (!check(!kfp_toggle_key_pressed_edge(0, &was_down),
               "release only clears the edge latch")) return 1;
    if (!check(kfp_toggle_key_pressed_edge(1, &was_down),
               "new press after release toggles once")) return 1;

    if (!check(kfp_toggle_physical_press_allowed(1, 1, 0, 0, 1),
               "focused game accepts an unguarded physical press")) return 1;
    if (!check(!kfp_toggle_physical_press_allowed(1, 0, 0, 0, 1),
               "background key press is ignored")) return 1;
    if (!check(!kfp_toggle_physical_press_allowed(1, 1, 1, 0, 1),
               "settings capture press is ignored")) return 1;
    if (!check(!kfp_toggle_physical_press_allowed(1, 1, 0, 1, 1),
               "focused text field owns the rebound key")) return 1;
    if (!check(!kfp_toggle_physical_press_allowed(1, 1, 0, 0, 0),
               "disabled game controls ignore the press")) return 1;
    if (!check(!kfp_toggle_physical_press_allowed(0, 1, 0, 0, 1),
               "rejected edge is discarded instead of deferred")) return 1;

    printf("PASS fp_toggle_key_policy (%d checks)\n", checks);
    return 0;
}
