#ifndef KFP_READY_LATCH_H
#define KFP_READY_LATCH_H
#include <stdint.h>
/* R12-SWAP: aim readiness hysteresis for the manual ranged adapter (pure, offline-tested).
 *
 * Native contract (static RE, RE_Kenshi kenshi_x64.exe 1.0.65 RangedCombatClass::animationUpdate 0x51DA50):
 * the call first clears GunClass ready-to-shoot (gun vt+0x40(0)), then (target != NULL, not reloading,
 * actor on screen) plays the "aimH" animation with target weight 1.0 and sets ready = weight("aimH")
 * (AnimationState +0x44) > 0.9. The weight itself only moves in the AnimationClass update, which runs on
 * the character's own update cadence, not in lockstep with the adapter's per-frame call; on frames where
 * it ran without a fresh play request the weight dips under 0.9 for a frame and isAnimationReadyToShoot
 * reads 0 while the aim is held steadily (5090 b6 / 4080 b14: shot_ready 1,0,0,1; R12-SWAP last_reject
 * aim_ready=0 closeness 1 timer 0, vis_forced=0, anim_suppressed=0).
 *
 * The latch keeps the pose "ready" across such dips: once the native flag was 1, a 0 is bridged for at
 * most `window` game seconds while the hold stays intact (aim held, identity unchanged, not reloading,
 * ammo > 0, input allowed). Anything that breaks the hold clears it, and so does a shot (the caller
 * resets after firing). It never buffers or replays a fire edge: the edge is still judged on its frame.
 *
 * The window is measured on the dip time BEFORE this frame: the first dip frame is always bridged,
 * whatever its dt. A hitch frame (a game-thread stall, at 3x a 100 ms stall is 0.3 game s) is exactly
 * when the native anim update runs without our play request and the flag dips; judging it by its own
 * dt (old `since+dt<=window`) dropped the latch on that one frame, and a trigger landing there was
 * refused with everything else ready (4080 b29 R12-UI/SPEED, b30 R10/R12-SWAP: last_reject
 * 1/0/0/1/0/1.0/0.0, ready_bridged unchanged, native ready 1 again on the next poll). */
typedef struct { int latched; float since; uint64_t identity; unsigned bridged; } KfpReadyLatch;
static void kfp_ready_latch_reset(KfpReadyLatch *l) { l->latched=0; l->since=0; }
/* Returns the readiness to use this frame. */
static int kfp_ready_latch_step(KfpReadyLatch *l,int native_ready,int hold_ok,uint64_t identity,
                                float dt,float window) {
    if (!hold_ok || identity!=l->identity || !(dt>=0) || !(window>0)) {
        l->identity=identity; kfp_ready_latch_reset(l);
        return hold_ok && native_ready;
    }
    if (native_ready) { l->latched=1; l->since=0; return 1; }
    if (l->latched && l->since<window) { l->since+=dt; ++l->bridged; return 1; }
    kfp_ready_latch_reset(l);
    return 0;
}
#endif
