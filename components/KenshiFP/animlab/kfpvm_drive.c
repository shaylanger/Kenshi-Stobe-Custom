/* kfpvm_drive.c -- animation lab phase 2 (METRICS LAB): drive KenshiFP's real viewmodel solver with AUTHORED targets.
 *
 * Usage: kfpvm_drive <body_rec.txt> <frames.txt> <out.txt> [--body-frame N] [--side R|L] [--calib L1R,L2R,L1L,L2L,K]
 *                    [--set key=value]... [--no-lookahead] [--quiet]
 *   body_rec.txt  a game recording (`fp_vm rec dump`); record N gives the body: camera (eye, yaw, pitch), torso, shoulders,
 *                 the native arm pose and (from the whole recording, as in the replay) the arm lengths + prop scale.
 *   frames.txt    authored per-frame targets (written by tools/animlab/metricslab.py from a motion file), lines:
 *                   t cls px,py,pz fx,fy,fz ux,uy,uz ox,oy,oz      (camera numbers: x right, y up, z forward, dm)
 *                 p/f/u = the weapon prop pose of the solved side (f toward the tip, u = edge / up axis),
 *                 o = off-hand position target ("nan,nan,nan" = the solver's rest point, mirrored for --side L).
 *   --side L      solve the LEFT hand as the weapon hand (`fp_vm set hand_m 0`, Prop1) with the prop local mirrored
 *                 (biped mirror: position z and quaternion x,y negated) and the grip roll mirrored (groll -> 180 - groll for
 *                 the sword; --set groll takes the RIGHT-hand value); see docs/animlab/USAGE.md phase 2.
 *   out.txt       one line per frame, camera numbers of the body frame, after the apply (what the frame renders):
 *                   i t | Lsh Lel Lwr LhandX LpropP LpropF LpropU | Rsh Rel Rwr RhandX RpropP RpropF RpropU |
 *                   stL stR ikfail eclamp | eye rt up fw (world)
 * The solver runs unchanged (kfp_viewmodel.inc via the phase-1 replay harness, included below): each frame the authored
 * pose goes in through the plugin's own "commanded pose" path (fp_vm replay N t: g_vm_rp / g_vm_rp_t), so targets ->
 * vm_targets -> vm_apply (IK, elbow pick with look-ahead over the authored future, wrist roll, edge clamp, stretch) are
 * the game's code. Dual wielding = one run per side (metricslab.py merges the two arms). */
#define main kfpvm_replay_main
#include "kfpvm_replay.c"
#undef main

typedef struct { float t; int cls; Vec3 p, f, u, o; int rest; } Drv;
static Drv *D; static int DN;
static int load_frames(const char *path)
{
    FILE *f = fopen(path, "r"); if (!f) return -1;
    char line[1024]; int cap = 1024; D = malloc(sizeof(Drv) * cap); DN = 0;
    while (fgets(line, sizeof line, f)) {
        if (line[0] == '#' || line[0] == '\n') continue;
        if (DN == cap) { cap *= 2; D = realloc(D, sizeof(Drv) * cap); }
        Drv *d = &D[DN]; char so[128];
        if (sscanf(line, "%f %d %f,%f,%f %f,%f,%f %f,%f,%f %127s", &d->t, &d->cls, &d->p.x, &d->p.y, &d->p.z, &d->f.x, &d->f.y, &d->f.z,
                   &d->u.x, &d->u.y, &d->u.z, so) != 12) continue;
        d->rest = sscanf(so, "%f,%f,%f", &d->o.x, &d->o.y, &d->o.z) != 3 || d->o.x != d->o.x;
        DN++;
    }
    fclose(f); return DN;
}
static Vec3 w2c(const Rin *r, Vec3 w, int pos)
{
    if (pos) w = vm_sub(w, f3(r->v[13]));
    return vm_v(vm_dot(w, f3(r->v[14])), vm_dot(w, f3(r->v[15])), vm_dot(w, f3(r->v[16])));
}
static void pv(FILE *o, Vec3 v) { fprintf(o, " %.5f,%.5f,%.5f", v.x, v.y, v.z); }

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: kfpvm_drive <body_rec.txt> <frames.txt> <out.txt> [--body-frame N] [--side R|L] [--calib ...] [--set k=v]... [--no-lookahead] [--quiet]\n"); return 2; }
    if (load_rec(argv[1]) < 2) { fprintf(stderr, "kfpvm_drive: no frames in %s\n", argv[1]); return 1; }
    if (load_frames(argv[2]) < 1) { fprintf(stderr, "kfpvm_drive: no frames in %s\n", argv[2]); return 1; }
    g_get_bone_world = fk_bone_world; g_skel_getbone = fk_getbone; g_oldnode_getdori = fk_getdori; g_oldnode_getdpos = fk_getdpos;
    g_oldnode_getori = fk_getori; g_oldnode_setori = fk_setori; g_oldnode_needupd = fk_needupd; g_oldnode_getparent = fk_getparent;
    g_oldnode_setpos = fk_setpos; g_oldnode_getpos = fk_getpos; g_oldnode_getdscale = fk_getdscale;
    g_vm_setanim_orig = fk_native; g_vm_hooked = 1;
    for (int i = 0; i < B_N; i++) { g_b[i].lq = QI; g_b[i].ls = vm_v(1, 1, 1); }
    *(void **)g_pc = g_vt; g_vt[0x3D0 / 8] = (void *)fk_rw;
    *(void **)(g_pc + CHAR_ANIM) = g_anim; *(void **)(g_anim + ANIM_SKELETON) = (void *)g_b;
    g_anim_ent_off = 0x10; *(void **)(g_anim + 0x10) = g_ent;
    g_get_parent_scenenode = fk_parent_node; g_node_getdori_v = fk_node_ori; g_node_getdpos_v = fk_node_pos; g_node_getdscale_v = fk_node_scale;
    int bf = -1, left = 0, la = 1; const char *cl_set[256]; int ncl = 0;
    for (int a = 4; a < argc; a++) {
        if (!strcmp(argv[a], "--quiet")) g_al_quiet = 1;
        else if (!strcmp(argv[a], "--no-lookahead")) la = 0;
        else if (!strcmp(argv[a], "--body-frame") && a + 1 < argc) bf = atoi(argv[++a]);
        else if (!strcmp(argv[a], "--side") && a + 1 < argc) left = argv[++a][0] == 'L';
        else if (!strcmp(argv[a], "--set") && a + 1 < argc) { if (ncl < 256) cl_set[ncl++] = argv[++a]; }
        else if (!strcmp(argv[a], "--calib") && a + 1 < argc) {
            if (sscanf(argv[++a], "%f,%f,%f,%f,%f", &C_L1[1], &C_L2[1], &C_L1[0], &C_L2[0], &C_K) != 5) { fprintf(stderr, "bad --calib\n"); return 2; }
            g_have_calib = 1; }
        else { fprintf(stderr, "kfpvm_drive: unknown arg %s\n", argv[a]); return 2; }
    }
    if (bf < 0 || bf >= RN - 1) { fprintf(stderr, "kfpvm_drive: --body-frame must be 0..%d\n", RN - 2); return 2; }
    for (int s = 0; s < g_nrsets; s++) if (g_rsets[s].f < 0) do_set(g_rsets[s].kv);   /* the body recording's settings */
    if (!g_have_calib) calibrate();
    int cls = D[0].cls ? 1 : 0;
    if (left) {
        char kv[32]; snprintf(kv, sizeof kv, "%s=0", cls ? "hand_r" : "hand_m"); do_set(kv);
        g_vm_pldp[cls].z = -g_vm_pldp[cls].z; g_vm_pldq[cls].x = -g_vm_pldq[cls].x; g_vm_pldq[cls].y = -g_vm_pldq[cls].y;
    }
    for (int s = 0; s < ncl; s++) if (!do_set(cl_set[s])) return 2;
    if (left) {   /* grip roll: mirrored (f,u) targets flip the prop axis perpendicular to both (t), the bone mirror flips z: the
                     * left local = Sz.(local.roll(g)).St = mirrored local . roll(180 - g) (t != z) or roll(-g) (t == z) about f */
        int a0 = abs(g_vm_ax[cls][0]), t = 6 - a0 - abs(g_vm_ax[cls][1]);
        if (a0 == 3) fprintf(stderr, "kfpvm_drive: --side L with the blade on prop z: grip mirror not exact\n");
        else g_vm_groll[cls] = (t == 3 ? 0.0f : 180.0f) - g_vm_groll[cls];
    }
    printf("calib %.4f,%.4f,%.4f,%.4f,%.4f\n", C_L1[1], C_L2[1], C_L1[0], C_L2[0], C_K);
    const Rin *r = &R[bf];
    g_nat = bf + 1; g_cls_fill[0] = cls; g_vm_class = cls;
    set_native(g_nat);
    /* commanded-pose slot (the plugin's `fp_vm replay N t` path) */
    g_vm_rec = calloc(2, sizeof(VmRec)); g_vm_rn = 1; g_vm_rec_on = 0; g_vm_rp = 0; g_vm_rp_t = 1;
    Vec3 rest = g_vm_rest; if (left) rest.x = -rest.x;
    FILE *o = fopen(argv[3], "w"); if (!o) { perror(argv[3]); return 1; }
    fprintf(o, "# kfpvm_drive side=%c body_frame=%d cls=%d calib=%.4f,%.4f,%.4f,%.4f,%.4f\n", left ? 'L' : 'R', bf, cls, C_L1[1], C_L2[1], C_L1[0], C_L2[0], C_K);
    #ifndef AL_HAVE_ECLAMP
    unsigned long g_vm_eclamp_n = 0;   /* older solver sources have no edge-clamp counter */
#endif
    unsigned long ik0 = g_vm_ikfail, ec0 = g_vm_eclamp_n;
    g_al_clock = 0;
    for (int i = 0; i < DN; i++) {
        const Drv *d = &D[i];
        if (i) g_al_clock += d->t - D[i - 1].t;
        g_fpc_ui_state = "ready"; g_fpc_fs_prog = 0; g_view.applied = r->zoom; g_view.target = r->zoom;
        g_yaw = r->yaw * 0.017453293f; g_pitch = r->pitch * 0.017453293f;
        g_last_eye = f3(r->v[13]); g_view_have_anchor = 0; g_tx = g_tz = 0; g_fpc_holster_pending = 0;
        *(void **)(g_pc + CHAR_WEAPON_IN_HANDS) = cls ? (void *)&g_wep_ranged : (void *)&g_wep_melee;
        VmRec *q = &g_vm_rec[0];
        q->cls = (unsigned char)cls; q->ti = VM_READY; q->omode = 0;
        q->out = (VmPose){ d->p, d->f, d->u }; q->oc = d->rest ? rest : d->o;
        vm_frame(g_pc, 0);
        g_vm_fid++; g_vm_fut_n = 0;
        if (la && g_vm_elb_la) {   /* look-ahead: the authored future at the solver's prediction step */
            float pdt = fminf(fmaxf(g_vm_dt, 0.008f), 0.033f), tt = d->t; int j = i;
            for (int k = 0; k < g_vm_elb_lah && k < VM_LAH; k++) {
                tt += pdt; while (j + 1 < DN && D[j + 1].t <= tt) j++;
                const Drv *e = &D[j]; g_vm_fut[k] = vm_pose_norm((VmPose){ e->p, e->f, e->u }); g_vm_fut_n = k + 1;
            }
        }
        hooked_vm_setanim(g_b, NULL, 1.0f, NULL);
        fk_update();
        fprintf(o, "%d %.5f |", i, d->t);
        for (int s = 0; s < 2; s++) {
            pv(o, w2c(r, g_b[B_UA_L + s].dp, 1)); pv(o, w2c(r, g_b[B_FA_L + s].dp, 1)); pv(o, w2c(r, g_b[B_HA_L + s].dp, 1));
            pv(o, w2c(r, quat_rotvec(g_b[B_HA_L + s].dq, vm_v(1, 0, 0)), 0));
            Bone *pb = &g_b[B_PROP1 + s];
            pv(o, w2c(r, pb->dp, 1));
            pv(o, w2c(r, quat_rotvec(pb->dq, vm_axis(g_vm_ax[cls][0])), 0)); pv(o, w2c(r, quat_rotvec(pb->dq, vm_axis(g_vm_ax[cls][1])), 0));
            fprintf(o, " |");
        }
        fprintf(o, " %.4f %.4f %lu %lu |", g_vm_st_last[0], g_vm_st_last[1], g_vm_ikfail - ik0, g_vm_eclamp_n - ec0);
        for (int k = 13; k < 17; k++) pv(o, f3(r->v[k]));
        fputc('\n', o);
    }
    fclose(o);
    printf("frames %d side %c body_frame %d ikfail %lu\n", DN, left ? 'L' : 'R', bf, g_vm_ikfail - ik0);
    return 0;
}
