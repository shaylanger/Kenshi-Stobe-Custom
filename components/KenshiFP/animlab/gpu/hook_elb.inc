/* hook_elb.inc -- gpugen --inject (both TUs): the elbow search (vm_elb_pref, the adapter's hot spot) as a unit that a
 * GPU thread can run from a captured state. With --rename-def vm_elb_pref=vm_elb_pref__orig the game's function keeps
 * its body under the new name; hook_elb_cpu.inc / hook_elb_dev.inc define vm_elb_pref (the game's callers) again. */
static struct { void *ua, *fa, *ha; Vec3 Ph; Vec3 d0; int ret; } al_elb_args;
static void al_elb_run(void)
{
    al_elb_args.ret = vm_elb_pref__orig(al_elb_args.ua, al_elb_args.fa, al_elb_args.ha, al_elb_args.Ph, &al_elb_args.d0);
}
