/* Floating-origin weld: decide what a per-frame jump of raw = centre(ogre) - feet(game) means.
 * Pure (no game calls), so tests/test_weld.c checks it offline. */
#ifndef KFP_WELD_H
#define KFP_WELD_H
#include <math.h>

#define KFP_WELD_JUMP2    2500.0f            /* > 50 u in one frame: something jumped */
#define KFP_WELD_ON2      2500.0f            /* within 50 u of the calibrated T: on the weld */
#define KFP_WELD_BIG2     (1000.0f*1000.0f)  /* > 1000 u (100 m): world-scale, must hold first */
#define KFP_WELD_CONFIRM  4                  /* frames a world-scale jump must hold before it counts */

typedef struct { int n; float x, z; } KfpWeldPend;
typedef enum { KFP_WELD_NONE, KFP_WELD_SHIFT, KFP_WELD_PENDING, KFP_WELD_RETURNED } KfpWeldStep;

/* raw: this frame; prev: last accepted raw; t: calibrated T. SHIFT = shift T by (raw - prev). */
static KfpWeldStep kfp_weld_step(KfpWeldPend *p, float rawx, float rawz,
                                 float prevx, float prevz, float tx, float tz)
{
    if (!isfinite(rawx) || !isfinite(rawz)) { p->n = 0; return KFP_WELD_PENDING; }   /* never accepted */
    float dx = rawx - prevx, dz = rawz - prevz, d2 = dx*dx + dz*dz;
    if (!(d2 > KFP_WELD_JUMP2)) { p->n = 0; return KFP_WELD_NONE; }
    float ex = rawx - tx, ez = rawz - tz;
    if (ex*ex + ez*ez <= KFP_WELD_ON2) { p->n = 0; return KFP_WELD_RETURNED; }
    if (d2 > KFP_WELD_BIG2) {
        float qx = rawx - p->x, qz = rawz - p->z;
        if (p->n > 0 && qx*qx + qz*qz <= KFP_WELD_ON2) p->n++;
        else { p->n = 1; p->x = rawx; p->z = rawz; }
        if (p->n >= KFP_WELD_CONFIRM) { p->n = 0; return KFP_WELD_SHIFT; }
        return KFP_WELD_PENDING;
    }
    p->n = 0;
    return KFP_WELD_SHIFT;
}
#endif
