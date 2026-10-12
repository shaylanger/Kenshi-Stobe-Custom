/* hook_loop_dev.inc -- gpugen --dev-tail: device side of hook_loop_cpu.inc. Thread t replays frames [i0, i1) of its own
 * state g_kst_base[t] (filled from an AL_GPU_SNAP capture); the host launches the loop in chunks (Windows display
 * watchdog) and reads the state back for vm_rec_dump. */
__attribute__((nvptx_kernel)) void loop_kernel(int nthreads, int i0, int i1)
{
    int t = (int)(__nvvm_read_ptx_sreg_ctaid_x() * __nvvm_read_ptx_sreg_ntid_x() + __nvvm_read_ptx_sreg_tid_x());
    if (t < nthreads) for (int i = i0; i < i1; i++) al_frame(i);
}
