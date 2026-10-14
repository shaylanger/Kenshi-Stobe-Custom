#ifndef KFP_TOGGLE_KEY_POLICY_H
#define KFP_TOGGLE_KEY_POLICY_H

/* Pure key-edge and focus policy shared with the focused regression tests. */
static int kfp_toggle_key_rebase(int key, int *previous_key, int down,
                                 int *was_down)
{
    if (key == *previous_key) return 0;
    *previous_key = key;
    *was_down = down;
    return 1;
}

static int kfp_toggle_key_pressed_edge(int down, int *was_down)
{
    int edge = down && !*was_down;
    *was_down = down;
    return edge;
}

static int kfp_toggle_physical_press_allowed(int edge_pending,
                                             int game_focused,
                                             int settings_open,
                                             int keyboard_focus,
                                             int controls_enabled)
{
    return edge_pending && game_focused && !settings_open &&
           !keyboard_focus && controls_enabled;
}

#endif /* KFP_TOGGLE_KEY_POLICY_H */
