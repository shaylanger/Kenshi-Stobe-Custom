/* kfpvm_fist.c -- dumps the game's NA1 fist path (kfp_viewmodel.inc with pending-fixes/kfp-fists-na1.py applied,
 * compiled as is): per technique table, per hand row (0 = R, 1 = L) the keyed prop target vm_fist_at(u) on a u grid.
 * Usage: kfpvm_fist [steps]   ->  stdout lines "<anim>|<row>|<u>|px,py,pz|fx,fy,fz|ux,uy,uz" + "guard|<row>|..." lines.
 * fist-equiv.sh compares them with the lab's keys.json (native.py keyed_at): the game plays the poses the lab solved. */
#include "prelude.h"
#include "gen_helpers.h"
#include "kfp_viewmodel.inc"

static void pp(const char *a, int s, float u, VmPose P)
{
    printf("%s|%d|%.4f|%.5f,%.5f,%.5f|%.5f,%.5f,%.5f|%.5f,%.5f,%.5f\n", a, s, u, P.p.x, P.p.y, P.p.z, P.f.x, P.f.y, P.f.z, P.u.x, P.u.y, P.u.z);
}
int main(int argc, char **argv)
{
    int n = argc > 1 ? atoi(argv[1]) : 200;
    for (int s = 0; s < 2; s++) pp("guard", s, 0.0f, vm_pose_norm(g_vm_fist_guard[s]));
    for (int t = 0; t < VM_NFIST; t++)
        for (int s = 0; s < 2; s++)
            for (int i = 0; i <= n; i++) { float u = (float)i / n; pp(g_vm_fist_tech[t].anim, s, u, vm_fist_at(&g_vm_fist_tech[t], s, u)); }
    return 0;
}
