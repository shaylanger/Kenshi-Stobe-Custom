/* C05-KO fling guard. Pure, offline-tested (tests/test_fling.c).
 * 4080 b36b: a KO during a direct-drive walk moved the downed body 1234 units in ONE sample with every FP writer
 * off (dm/face/fall/ragdoll-driver all 0), then ~10 km more in the seconds after the wake; a reload afterwards hung.
 * No KO/ragdoll can do that legitimately: the game clamps the ragdoll launch velocity to 100 u/s (AnimationClass
 * ragdoll enable, 1.0.65 0x5b8f80: y zeroed, |v|>100 -> zero) and a 2000-unit fall at fall_gravity 150 is ~775 u/s.
 * So: a sample-to-sample speed over KFP_FLING_SPEED is a fling. While the body is down the anchor (last trusted
 * position) is frozen at the pre-fling point; on the wake edge the caller teleports the body back to it, and for
 * KFP_FLING_WATCH_MS after any wake every further fling is undone the same way (bounded by KFP_FLING_MAX_RESTORES).
 * Outside a down episode + watch window nothing is ever reverted (harness/game teleports stay where they land). */
#ifndef KFP_FLING_H
#define KFP_FLING_H
#include <math.h>
#include <string.h>
#define KFP_FLING_MIN_STEP     60.0f    /* units in one sample */
#define KFP_FLING_SPEED        2500.0f  /* units/s */
#define KFP_FLING_GAP_MS       1000u    /* samples further apart than this are not compared (FP off, load, hitch) */
#define KFP_FLING_WATCH_MS     4000u
#define KFP_FLING_MAX_RESTORES 6
enum { KFP_FLING_NONE = 0, KFP_FLING_DETECTED = 1, KFP_FLING_RESTORE = 2 };
typedef struct {
    float ax, ay, az; int have_anchor;   /* last trusted position (restore target) */
    float px, py, pz; unsigned pms; int have_prev;
    int was_down, flung, restores;
    unsigned watch_until;                /* post-wake watch end (ms), 0 = off */
    unsigned episodes, detections, restored;
    float last_jump;                     /* size of the last detected jump (log) */
} KfpFling;
static int kfp_fling_is_jump(float dx, float dy, float dz, unsigned dms)
{
    float d = sqrtf(dx * dx + dy * dy + dz * dz);
    if (d < KFP_FLING_MIN_STEP || dms > KFP_FLING_GAP_MS) return 0;
    float dt = (float)(dms < 10u ? 10u : dms) / 1000.0f;
    return d / dt > KFP_FLING_SPEED;
}
/* One sample of the controlled body. Returns NONE, DETECTED (fling while down: anchor frozen, caller logs) or
 * RESTORE (caller teleports the body to ax/ay/az; the next sample is measured from the anchor). */
static int kfp_fling_step(KfpFling *f, int down, float x, float y, float z, unsigned ms)
{
    int r = KFP_FLING_NONE;
    int jump = f->have_prev && kfp_fling_is_jump(x - f->px, y - f->py, z - f->pz, ms - f->pms);
    if (jump) {
        float dx = x - f->px, dy = y - f->py, dz = z - f->pz;
        f->last_jump = sqrtf(dx * dx + dy * dy + dz * dz);
    }
    if (down) {
        if (!f->was_down) { ++f->episodes; f->flung = 0; f->restores = 0; }
        if (jump && f->have_anchor) { ++f->detections; f->flung = 1; r = KFP_FLING_DETECTED; }
        else if (!f->flung) { f->ax = x; f->ay = y; f->az = z; f->have_anchor = 1; }  /* legit ragdoll roll */
    } else {
        if (f->was_down) f->watch_until = ms + KFP_FLING_WATCH_MS;
        int watching = f->watch_until && (int)(f->watch_until - ms) > 0;
        if (!watching) f->watch_until = 0;
        if (f->have_anchor && f->was_down && f->flung) r = KFP_FLING_RESTORE;
        else if (f->have_anchor && watching && jump) { ++f->detections; f->flung = 1; r = KFP_FLING_RESTORE; }
        if (r == KFP_FLING_RESTORE) {
            if (f->restores >= KFP_FLING_MAX_RESTORES) r = KFP_FLING_DETECTED;
            else { ++f->restores; ++f->restored; }
        }
        if (r == KFP_FLING_NONE) { f->ax = x; f->ay = y; f->az = z; f->have_anchor = 1; }
    }
    if (r == KFP_FLING_RESTORE) { f->px = f->ax; f->py = f->ay; f->pz = f->az; }
    else { f->px = x; f->py = y; f->pz = z; }
    f->pms = ms; f->have_prev = 1; f->was_down = down;
    return r;
}
static void kfp_fling_reset(KfpFling *f) { unsigned e = f->episodes, d = f->detections, s = f->restored;
    memset(f, 0, sizeof *f); f->episodes = e; f->detections = d; f->restored = s; }
#endif
