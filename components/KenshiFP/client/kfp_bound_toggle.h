/* CS05: decide whether a vanilla FPS-camera toggle came from an FP-bound key.
 * Pure (no game state) so tests/test_bound_toggle.c can check it offline. */
#ifndef KFP_BOUND_TOGGLE_H
#define KFP_BOUND_TOGGLE_H
#define KFP_BOUND_TOGGLE_MS 400u   /* window after a swallowed bound key */
/* fp_mode: FP on; fc_prev/fc: cam free flag last/this frame; have_swallow: a bound key was
 * swallowed (swallow_ms valid); now_ms/swallow_ms: GetTickCount values (wrap-safe). */
static int kfp_bound_toggle_revert(int fp_mode, int fc_prev, int fc, int have_swallow,
                                   unsigned now_ms, unsigned swallow_ms)
{
    if (!fp_mode || fc_prev != 0 || !fc || !have_swallow) return 0;
    return (unsigned)(now_ms - swallow_ms) < KFP_BOUND_TOGGLE_MS;
}
#endif
