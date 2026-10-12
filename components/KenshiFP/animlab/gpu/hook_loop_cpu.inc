/* hook_loop_cpu.inc -- gpugen --cpu-tail: the frame loop of kfpvm_replay.c main (al_frame) runs on the GPU
 * (build.sh --preprocess defines AL_LOOP_HOOK(n) = al_gpu_loop(n); without the env switches below this is the plain replay).
 *   AL_GPU_SNAP=<file>  write the state at frame-loop start (every global + heap block, KSN1) + trailer "KSNX" u32 n; exit 0
 *   AL_GPU_LOAD=<list>  list lines "<after-state snap> <out.txt>": load each state the GPU left after the loop, write
 *                       <out.txt> with the game's own vm_rec_dump and print main's summary line; exit 0 (1 if any failed)
 *   AL_GPU_CPURUN=1     (with AL_GPU_LOAD) run the frame loop on the CPU from each loaded state first: kfpgpu.py selftest
 *                       (pack -> relocate -> unpack round trip, no GPU) must then give the plain replay's output */
static int al_gpu_loop(int n)
{
    const char *sp = getenv("AL_GPU_SNAP"), *lp = getenv("AL_GPU_LOAD");
    if (sp) {
        FILE *f = fopen(sp, "wb"); if (!f) { fprintf(stderr, "al_gpu_loop: cannot write %s\n", sp); exit(3); }
        al_snap_noheap = 0; al_snap_write(f); fwrite("KSNX", 4, 1, f); fwrite(&n, 4, 1, f); fclose(f); exit(0);
    }
    if (lp) {
        FILE *l = fopen(lp, "r"); char ln[2048], snap[1024], out[1024]; int bad = 0;
        if (!l) { fprintf(stderr, "al_gpu_loop: cannot read %s\n", lp); exit(3); }
        while (fgets(ln, sizeof ln, l)) {
            if (sscanf(ln, "%1023s %1023s", snap, out) != 2) continue;
            FILE *f = fopen(snap, "rb"); int ok = f && !al_snap_read(f); if (f) fclose(f);
            if (!ok) { fprintf(stderr, "al_gpu_loop: bad state %s\n", snap); bad = 1; continue; }
            if (getenv("AL_GPU_CPURUN")) for (int i = 0; i < n; i++) al_frame(i);   /* selftest: the loaded state runs the loop on the CPU */
            int w = vm_rec_dump(out);
            printf("%s: frames %d written %d skipped_applies %d native_applies %d roll_applies %d l1_applies %d hs_applies %d rec_sets %d\n",
                   out, n, w, g_skipped, g_nat_used, g_roll_used, g_l1_used, g_hs_used, g_nrsets);
            if (w <= 0) bad = 1;
        }
        fclose(l); fflush(stdout); exit(bad);
    }
    return 0;
}
