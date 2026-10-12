/* dev_kst.h -- one struct KSt (every mutable global of the adapter TU) per GPU thread; gpugen rewrote each use of a
 * global in a function body to (KST->name). Thread t of a 1-D launch owns g_kst_base[t] (set by the host). */
struct KSt *g_kst_base;
#define KST (g_kst_base + (int)(__nvvm_read_ptx_sreg_ctaid_x() * __nvvm_read_ptx_sreg_ntid_x() + __nvvm_read_ptx_sreg_tid_x()))
