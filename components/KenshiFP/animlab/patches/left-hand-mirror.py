"""left-hand-mirror.py -- animlab variant patch (build.sh --patch): make the melee elbow pick side-aware for a LEFT weapon hand
(hand_m 0, dual wield). kfp_viewmodel.inc has three right-hand-only camera-space rules: the preferred wrist->elbow
direction g_vm_elbd (lower right), the coarse-search bound e.x < -0.25 (no elbow left of the wrist) and the
swing-ready elbow branch g_vm_rbe (its f x u term flips under a mirror). With this patch + the adapter grip mirror,
motions/dualwield-sync-mirror.json on a symmetric body gives L == R per segment (regress.sh step 9).
Not for the game as is: upstream into KenshiFP only if dual wielding goes ahead."""
import sys, os
f = os.path.join(sys.argv[1], 'kfp_viewmodel.inc'); s = open(f).read()
def rep(a, b, n):
    global s
    assert s.count(a) == n, (a, s.count(a)); s = s.replace(a, b)
rep('/* melee wrist fix: preferred wrist -> elbow direction',
    '/* left weapon hand (hand_m/hand_r 0): the camera-space elbow preferences mirror in x */\n'
    'static Vec3 vm_elbd_side(void) { Vec3 d = g_vm_elbd; if (!g_vm_whand[g_vm_class]) d.x = -d.x; return d; }\n'
    '/* melee wrist fix: preferred wrist -> elbow direction', 1)
rep('d0 = vm_norm(g_vm_elbd);', 'd0 = vm_norm(vm_elbd_side());', 2)
rep('if (e.x < -0.25f || e.z > 0.35f) continue;', 'if ((g_vm_whand[g_vm_class] ? e.x : -e.x) < -0.25f || e.z > 0.35f) continue;', 1)
rep('vm_mul(os, g_vm_rbe.z)', 'vm_mul(os, g_vm_whand[g_vm_class] ? g_vm_rbe.z : -g_vm_rbe.z)', 1)
open(f, 'w').write(s)
