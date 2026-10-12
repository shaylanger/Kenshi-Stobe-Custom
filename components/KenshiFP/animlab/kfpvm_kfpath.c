/* kfpvm_kfpath.c -- sample a sword stroke's commanded weapon path offline (no recording, no IK): the plugin's own
 * vm_swing_atl (key arc / screen line / keyframe dispatch + E1 edge lead) from the sword ready pose back to it.
 * keyframe-player 2026-10-11: input of kf/kfstroke.py (fit keys to an accepted stroke, quick screen-path preview).
 * Usage (build: build.sh --main kfpvm_kfpath.c --out /root/animlab-build/kfpvm_kfpath [--patch ..]):
 *   kfpvm_kfpath --stroke N [--tables <file>] [--set k=v].. [--steps 101] [--cls 0|1|2]
 * Prints `u lead px py pz fx fy fz ux uy uz | raw px..uz` per step (raw = vm_swing_at before the E1 lead), camera
 * numbers (x right, y up, z forward, dm). Needs kfp_tables.inc for --tables. */
#include "prelude.h"
#include "gen_helpers.h"
#include "kfp_viewmodel.inc"

int main(int argc, char **argv)
{
    g_al_quiet = 1; int stroke = 0, steps = 101, cls = 0; const char *tables = NULL;
    for (int a = 1; a < argc; a++) {
        if (!strcmp(argv[a], "--stroke") && a + 1 < argc) stroke = atoi(argv[++a]);
        else if (!strcmp(argv[a], "--steps") && a + 1 < argc) steps = atoi(argv[++a]);
        else if (!strcmp(argv[a], "--cls") && a + 1 < argc) cls = atoi(argv[++a]);
        else if (!strcmp(argv[a], "--tables") && a + 1 < argc) tables = argv[++a];
        else if (!strcmp(argv[a], "--set") && a + 1 < argc) { char k[128]; const char *kv = argv[++a], *e = strchr(kv, '=');
            if (!e || (size_t)(e - kv) >= sizeof k) { fprintf(stderr, "bad --set %s\n", kv); return 2; }
            memcpy(k, kv, (size_t)(e - kv)); k[e - kv] = 0;
            if (!vm_set(k, (float)atof(e + 1))) { fprintf(stderr, "unknown key %s\n", k); return 2; } }
        else { fprintf(stderr, "usage: kfpvm_kfpath --stroke N [--tables f] [--set k=v].. [--steps n] [--cls c]\n"); return 2; }
    }
#ifdef KFP_TABLES
    if (tables) { int bad = kt_load(tables, 0); if (bad) { fprintf(stderr, "--tables %s: %s\n", tables, g_kt_err); return 2; } }
#else
    if (tables) { fprintf(stderr, "--tables needs kfp_tables.inc\n"); return 2; }
#endif
    g_vm_2h = cls > 0; g_vm_2hk = cls > 1;
    g_vm_stroke = stroke; g_vm_swkp = vm_stroke_keys(stroke); g_vm_swing = 1;
    VmPose rdy = vm_pose_norm(g_vm_pose[0][0]);
    if (steps < 2) steps = 2;
    for (int i = 0; i < steps; i++) {
        float u = (float)i / (float)(steps - 1), w = 0.0f; g_vm_swu = u;
        VmPose q = vm_swing_atl(rdy, rdy, u, &w), r = vm_swing_at(rdy, rdy, u);
        printf("%.4f %.3f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f | %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f\n", u, w,
               q.p.x, q.p.y, q.p.z, q.f.x, q.f.y, q.f.z, q.u.x, q.u.y, q.u.z,
               r.p.x, r.p.y, r.p.z, r.f.x, r.f.y, r.f.z, r.u.x, r.u.y, r.u.z);
    }
    return 0;
}
