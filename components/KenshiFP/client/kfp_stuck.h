/* WASD "pinned" detector. Pure, offline-tested (tests/test_stuck.c).
 * MOVE_DIRECTION only drives a STANDING body: a seated/bedded/get-up body under direct drive just spins in place.
 * Direct drive commanding a move while the body makes < 2 u/s for more than 15 frames (~0.25 s) = pinned, and the
 * client routes the hold to the point-click ORDER path (cancels the holding job, runs the get-up).
 * The counter belongs to ONE hold: it restarts on key release, on a KO/down/fall stand-down and when control of an
 * actor is taken or released. 4080 b30/b31 (C01/C02/C05): the KO stand-down cleared g_was_moving but not the counter,
 * so the release branch (gated on g_was_moving) never reset it and the next W hold started "pinned" -> order path
 * (fresh_walk 16 u/s in b30, no walk at all in b31) instead of direct drive. */
#ifndef KFP_STUCK_H
#define KFP_STUCK_H
#define KFP_STUCK_PINNED_FRAMES 15
/* One driving frame: direct = this hold is direct-driving, speed = body speed (u/s). Returns 1 = pinned. */
static int kfp_stuck_step(int *frames, int direct, float speed) {
    if (direct && speed < 2.0f) { if (*frames < 600) ++*frames; }
    else if (speed >= 4.0f) *frames = 0;
    return *frames > KFP_STUCK_PINNED_FRAMES;
}
/* Frame with no drive (keys released, UI move block) or a stand-down (KO/down/fall, control taken/released). */
static void kfp_stuck_idle(int *frames) { *frames = 0; }
#endif
