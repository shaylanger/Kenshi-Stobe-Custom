/* hook_elb_cpu.inc -- gpugen --cpu-tail: capture every vm_elb_pref call of a CPU replay as (state before, state after)
 * snapshot pairs: AL_ELB_CAP=<file> [AL_ELB_CAP_MAX=n] [AL_ELB_CAP_EVERY=k (every k-th call)]. Without AL_ELB_CAP the
 * binary is the plain replay (same output). */
static FILE *al_capf; static int al_cap_n, al_cap_calls, al_cap_max = -1, al_cap_every = 1;
static int vm_elb_pref(void *ua, void *fa, void *ha, Vec3 Ph, Vec3 *d0o)
{
    if (al_cap_max < 0) { const char *p = getenv("AL_ELB_CAP"), *m = getenv("AL_ELB_CAP_MAX"), *e = getenv("AL_ELB_CAP_EVERY");
        al_cap_max = m ? atoi(m) : 1000000; if (e && atoi(e) > 0) al_cap_every = atoi(e);
        if (p) { al_capf = fopen(p, "wb"); al_snap_noheap = 1; } }
    if (!al_capf || al_cap_n >= al_cap_max || (al_cap_calls++ % al_cap_every)) return vm_elb_pref__orig(ua, fa, ha, Ph, d0o);
    al_elb_args.ua = ua; al_elb_args.fa = fa; al_elb_args.ha = ha; al_elb_args.Ph = Ph;
    al_snap_write(al_capf); al_elb_run(); al_snap_write(al_capf); al_cap_n++;
    *d0o = al_elb_args.d0; return al_elb_args.ret;
}
