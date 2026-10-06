/* Free-cursor key (default Left Alt) tap detector. Pure, offline-tested (tests/test_free_key.c).
 * The toggle fires on RELEASE, and only for a clean tap: Kenshi kept focus for the whole hold and no switch-away
 * combo key (Tab/Esc/F4/Win) was pressed meanwhile. Alt+Tab / Alt+F4 / Alt+Esc out of the game starts with Kenshi focused, so a press-edge toggle
 * flipped the cursor free and froze FP combat (why=ui_open, 5090 S04 soak). */
#ifndef KFP_FREE_KEY_H
#define KFP_FREE_KEY_H
typedef struct { int down, dirty; } KfpFreeKey;
/* One frame: key = free key held, focus = Kenshi foreground, other = a switch-away combo key held. Returns 1 = toggle now. */
static int kfp_free_key_step(KfpFreeKey *s,int key,int focus,int other) {
    if (key) {
        if (!s->down) { s->down=1; s->dirty=!focus || other; }
        else if (!focus || other) s->dirty=1;
        return 0;
    }
    if (!s->down) return 0;
    s->down=0;
    return !s->dirty && focus;
}
#endif
