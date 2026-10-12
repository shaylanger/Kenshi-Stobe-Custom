/* hook_elb_dev.inc -- gpugen --dev-tail: device side of hook_elb.inc. elb_kernel: thread t runs the elbow search on
 * state t (g_kst_base[t], filled from a captured "before" snapshot); the state then holds the "after" snapshot. */
static int vm_elb_pref(void *ua, void *fa, void *ha, Vec3 Ph, Vec3 *d0o) { return vm_elb_pref__orig(ua, fa, ha, Ph, d0o); }
__attribute__((nvptx_kernel)) void elb_kernel(int n)
{
    int t = (int)(__nvvm_read_ptx_sreg_ctaid_x() * __nvvm_read_ptx_sreg_ntid_x() + __nvvm_read_ptx_sreg_tid_x());
    if (t < n) al_elb_run();
}
