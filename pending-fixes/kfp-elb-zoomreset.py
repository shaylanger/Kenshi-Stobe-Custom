#!/usr/bin/env python3
"""kfp-elb-zoomreset.py <KenshiFP root | client dir>: the arm IK starts fresh when the camera comes back into first person
(cleaver-fix 2026-10-11, STATUS.md Misses "ready pose after zoom-out": 139-wc-clv, REEL-Long_Cleaver).

Why: the smoothed elbow target (g_vm_elbe with keep/rate/hysteresis g_vm_elb_cb) and the roll jerk-limit state (g_vm_rs)
keep running while the camera is zoomed out (zoom fade weight g_vm_zf = 0: the native third-person animation shows).
When the camera comes back to first person (fp_camera distance 0, scroll-in), the solver starts from that zoomed-out
elbow and settles in a second steady ready pose: elbow ~4 dm off, arm stretched 3.37 (normal ready 2.08), blade rolled
~95 deg (flat to the camera); it stays until a swing re-seeds the elbow. Game rec 139-wc-clv (4080, B17B98D5) frames
0-196 (take started right after the sweep's camera reset from zoom 25) and frames 1772-1802 (distance 25 -> 0) show it,
and the lab replay of the same recording reproduces it exactly at 1772 (zoom 25 -> 0) -> it is solver state, not a
mesh/roll-table problem. Lab: forcing have_elbe = 0 at that frame (`# set 1770 wfix 1`) lands on the normal ready pose
(stretch 2.085, hinge = fresh replay).
Change: vm_zf_update tracks the previous weight; on the frame the camera distance reaches first person (<= 0.05 dm after > 0.05) the
elbow target, its hysteresis winner and the roll jerk-limit state are dropped, so the first FP frame picks them fresh (same
as a fresh start / the lab's first frame). Nothing changes while the camera stays in first person.
Amended (fix-build 2026-10-11, pt30-fix finding, polearm ticket 2: Naginata ready elbow ~4 dm off, game pa-192-i3): the
first version reset when the weight rose above 0.01 = mid zoom-in (camera still ~8 dm out); the fresh pick was made in the
zoomed view and the elbow keep/hysteresis held it at zoom 0 (stretch 2.93 vs 1.73). Now the reset fires at camera
distance ~0. Lab (/root/fixbuild): the zpre.py ramp replay (zoom 25 -> ramp 10/30/60 -> 0) still lands on the stretched
pose with this reset (elbow 5.2 dm off, same as the old trigger); a forced have_elbe reset at original frame 60 fixes it,
at frame 50 it does not -> the Naginata case has a second cause (open, polearm ticket 2); the cleaver case should hold (its proof was a have_elbe reset at zoom 0, not re-run).
Asserts its anchors; idempotent."""
import sys, os
root = sys.argv[1]
cdir = root if os.path.exists(os.path.join(root, 'kfp_viewmodel.inc')) else os.path.join(root, 'client')
TAG = '/* kfp-elb-zoomreset */'
p = os.path.join(cdir, 'kfp_viewmodel.inc')
s = open(p).read()
if TAG in s:
    print('kfp-elb-zoomreset: already applied'); sys.exit(0)
OLD = '''static void vm_zf_update(void)
{   float a = g_vm_zf1 > g_vm_zf0 ? (g_view.applied - g_vm_zf0) / (g_vm_zf1 - g_vm_zf0) : 0.0f;
    a = a < 0 ? 0 : a > 1 ? 1 : a; g_vm_zf = g_vm_zfade ? 1.0f - a * a * (3.0f - 2.0f * a) : 1.0f; }
'''
NEW = '''static float g_vm_zf_prev = 0.0f; static unsigned g_vm_zf_resets;   /* g_vm_zf_prev = last applied camera distance, dm */   ''' + TAG + '''
static void vm_zf_update(void)
{   float a = g_vm_zf1 > g_vm_zf0 ? (g_view.applied - g_vm_zf0) / (g_vm_zf1 - g_vm_zf0) : 0.0f;
    a = a < 0 ? 0 : a > 1 ? 1 : a; g_vm_zf = g_vm_zfade ? 1.0f - a * a * (3.0f - 2.0f * a) : 1.0f;
    /* back into first person after a zoom-out: the elbow target / hysteresis winner / roll state of the zoomed-out frames
     * would hold a second, over-stretched ready pose (blade ~95 deg rolled) until a swing: pick them fresh */
    if (g_view.applied <= 0.05f && g_vm_zf_prev > 0.05f) { g_vm_have_elbe = 0; g_vm_have_cb = 0; g_vm_have_rs = 0; g_vm_zf_resets++; }
    g_vm_zf_prev = g_view.applied; }
'''
n = s.count(OLD)
assert n == 1, 'kfp-elb-zoomreset: anchor count %d (vm_zf_update)' % n
# g_vm_have_cb is declared further down (elbow pick): needs a forward declaration above vm_zf_update
DOLD = 'static Vec3 g_vm_elb_cb; static int g_vm_have_cb;'
assert s.count(DOLD) == 1, 'kfp-elb-zoomreset: anchor count %d (g_vm_have_cb decl)' % s.count(DOLD)
if s.index(DOLD) > s.index(OLD):   # C tentative definition (no initializer) is fine twice at file scope
    NEW = 'static int g_vm_have_cb;\n' + NEW
s = s.replace(OLD, NEW)
open(p, 'w').write(s)
print('kfp-elb-zoomreset: patched kfp_viewmodel.inc')
