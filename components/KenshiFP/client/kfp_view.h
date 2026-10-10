#ifndef KFP_VIEW_H
#define KFP_VIEW_H
#include <math.h>
typedef struct { float target, applied; int collision_known, blocked; } KfpView;
/* ~3-4 body lengths (a body is ~18 dm): Shay 2026-10-06, needs wall collision (C05-INTERIOR) */
#define KFP_VIEW_MAX 60.0f
#define KFP_VIEW_EYE_LIMIT 0.65f
static float kfp_view_clamp(float x) {
    if (!isfinite(x) || x<0.0f) return 0.0f;
    return x>KFP_VIEW_MAX?KFP_VIEW_MAX:x;
}
static void kfp_view_wheel(KfpView *v,int wheel) {
    /* nonlinear: 0.5 dm per notch at the eye, growing with distance (~17 notches eye -> max) */
    float t=kfp_view_clamp(v->target);
    v->target=kfp_view_clamp(t-(float)wheel*((0.5f+0.2f*t)/120.0f));
}
static float kfp_view_next(const KfpView *v,float dt) {
    float target=kfp_view_clamp(v->target);
    if (target<=v->applied) return target; /* fast zoom-in, never ease through a wall */
    if (!isfinite(dt) || dt<=0) dt=1.0f/60.0f;
    if (dt>0.1f) dt=0.1f;
    float next=v->applied+(target-v->applied)*(1.0f-expf(-dt/0.08f));
    return target-next<0.01f ? target : next; /* Z1: float easing stalls just below the target (15.999998 < head_show_dm 16) */
}
/* C05-INTERIOR: the native wall trace sometimes refuses a query (scene busy) instead of answering hit/miss.
 * A refused frame proves nothing about the wall, so it must not ease the camera outward through it (the
 * pull-back used to read "no hit" there: blocked=0, the camera popped through the wall for that frame).
 * On a refused frame: never go past the last applied distance and keep the last blocked flag. After `limit`
 * consecutive refused frames the trace counts as unavailable and the remaining rays decide alone. */
static float kfp_view_hold(const KfpView *prev,float allowed,int *blocked,int refused,unsigned *streak,unsigned limit) {
    if (!refused) { *streak=0; return allowed; }
    if (++*streak>limit) return allowed;
    if (allowed>prev->applied) { allowed=prev->applied; *blocked=prev->blocked; }
    return allowed;
}
static int kfp_view_is_eye(const KfpView *v) { return v->applied<KFP_VIEW_EYE_LIMIT; }
#endif
