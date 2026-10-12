#!/usr/bin/env python3
"""kfpgpu.py -- Windows-native GPU runner for the gpugen device TU (gpu-lab 2026-10-11). Windows python + CuPy.

Moves KSN1 state snapshots (written by the CPU build of the same TU, gpu/snap_cpu.c) into one `struct KSt` per GPU
thread, relocates every pointer (globals -> the thread's KSt field, heap blocks -> the thread's heap arena, functions ->
device function addresses, read-only strings -> a device copy), runs a kernel, reads the states back and writes them as
KSN1 snapshots again (pointers mapped back), which the CPU build loads (al_snap_read) to write its normal outputs.

  kfpgpu.py loop --mod <dev.cubin|dev.ptx> --globals <globals.tsv> --funcs <funcs.tsv> --list <jobs.tsv> [--chunk-ms 150]
      jobs.tsv lines "<before.snap> <after.snap>"; each before.snap = AL_GPU_SNAP capture (state at frame-loop start +
      "KSNX" n trailer); runs loop_kernel over frames [0, n) in chunks (Windows display watchdog), writes after.snap.
  kfpgpu.py elb --mod .. --globals .. --funcs .. --cap <AL_ELB_CAP file> [--max N]
      runs elb_kernel on every captured "before" state and compares the result with the captured "after" (bytes).
Prints one JSON line with timings (upload, kernel, download, convert) and counts.

GPU SAFETY RULE (Shay/coordinator 2026-10-11 ~19:45, after the 19:33:09 5090 TDR (nvlddmkm 153) that followed this
tool's first elb_kernel run, cudaErrorIllegalAddress; both rigs drive Kenshi game lanes on the same GPU and a faulting
kernel resets the driver under them):
 (1) any GPU program (kernel, CuPy judge, loader change, new gpugen/prelude) that has not passed yet runs FIRST only on the
     4080, at a list boundary of its two lanes: hold both lanes (rig-runner.ps1 -Stop -Rig 4080, incl. lane 2), run once
     with small N (N=1 first) under compute-sanitizer --tool memcheck (4080: CUDA v13.0 bin/compute-sanitizer.bat), then
     resume the lanes (rig-runner.ps1 -Start -Rig 4080) within 2 minutes;
 (2) never on the 5090 until it has passed on the 4080; once passed it may run beside games on both rigs;
 (3) the host-side pointer check (check_raw, before every launch; `selftest` mode uses no GPU) must pass first: a state
     word that looks like a host pointer with no relocation stops the run (the 19:33 cause: heap pointers left raw by a
     no-heap capture).
"""

import sys, os, json, time, struct, argparse
import numpy as np
cp = None   # CuPy is imported only by the modes that touch a GPU (selftest / check run without one)


def need_gpu():
    global cp
    import cupy
    cp = cupy

MAGIC = b'KSN1'


class Snap:
    """one KSN1 state: segs [(kind, id, bytes)], rels int array (seg, kind, off, tgt, toff), strs [bytes]"""
    __slots__ = ('segs', 'rels', 'strs', 'ng', 'nf', 'n')


def read_snap(buf, pos):
    if buf[pos:pos + 4] != MAGIC: raise ValueError('bad snapshot magic at %d' % pos)
    ns, ng, nf = struct.unpack_from('<3I', buf, pos + 4); pos += 16
    s = Snap(); s.ng, s.nf, s.segs, s.n = ng, nf, [], None
    for _ in range(ns):
        k, i, n = struct.unpack_from('<IIQ', buf, pos); pos += 16
        s.segs.append((k, i, buf[pos:pos + n])); pos += n
    nrel, = struct.unpack_from('<I', buf, pos); pos += 4
    r = np.frombuffer(buf, dtype=np.dtype([('seg', '<u4'), ('kind', '<u4'), ('off', '<u8'), ('tgt', '<u4'), ('pad', '<u4'), ('toff', '<u8')]),
                      count=nrel, offset=pos)
    s.rels = r; pos += 32 * nrel
    nstr, = struct.unpack_from('<I', buf, pos); pos += 4; s.strs = []
    for _ in range(nstr):
        n, = struct.unpack_from('<I', buf, pos); pos += 4; s.strs.append(buf[pos:pos + n]); pos += n
    if buf[pos:pos + 4] == b'KSNX': s.n, = struct.unpack_from('<I', buf, pos + 4); pos += 8
    return s, pos


def write_snap(f, segs, rels, strs, ng, nf):
    f.write(MAGIC + struct.pack('<3I', len(segs), ng, nf))
    for (k, i, b) in segs: f.write(struct.pack('<IIQ', k, i, len(b))); f.write(b)
    f.write(struct.pack('<I', len(rels)))
    if len(rels):
        a = np.zeros(len(rels), dtype=np.dtype([('seg', '<u4'), ('kind', '<u4'), ('off', '<u8'), ('tgt', '<u4'), ('pad', '<u4'), ('toff', '<u8')]))
        r = np.asarray(rels, dtype=np.uint64)
        a['seg'], a['kind'], a['off'], a['tgt'], a['toff'] = r[:, 0], r[:, 1], r[:, 2], r[:, 3], r[:, 4]
        f.write(a.tobytes())
    f.write(struct.pack('<I', len(strs)))
    for s in strs: f.write(struct.pack('<I', len(s))); f.write(s)


def ptx_table(ptx, name):
    import re
    m = re.search(r'\.b8 %s\[(\d+)\] = \{([^}]*)\}' % name, ptx)
    if not m: raise ValueError('no table %s in the PTX' % name)
    b = bytes(int(x) for x in m.group(2).split(',')); n = int(m.group(1))
    return np.frombuffer(b + bytes(n - len(b)), dtype='<u8')   # trailing zero bytes may be left out of the initializer


class FakeDev:
    """device layout read from the PTX (kst_off/kst_size tables), fake function addresses: no GPU (selftest, check)"""
    def __init__(s, ptxpath, gpath, fpath):
        ptx = open(ptxpath).read()
        s.names = [l.split('	')[1] for l in open(gpath).read().splitlines() if l]
        s.fnames = [l.split('	')[1] for l in open(fpath).read().splitlines() if l]
        s.off = ptx_table(ptx, 'kst_off').astype(np.int64); s.size = ptx_table(ptx, 'kst_size').astype(np.int64)
        assert len(s.off) == len(s.names), 'PTX has %d globals, globals.tsv %d' % (len(s.off), len(s.names))
        s.S = (int((s.off + s.size).max()) + 255) & ~255
        s.faddr = np.array([0x700000000000 + 64 * k for k in range(len(s.fnames))], dtype=np.uint64)


class Dev:
    def __init__(s, modpath, gpath, fpath):
        need_gpu()
        s.mod = cp.RawModule(path=modpath)
        s.names = [l.split('\t')[1] for l in open(gpath).read().splitlines() if l]
        s.fnames = [l.split('\t')[1] for l in open(fpath).read().splitlines() if l]
        ng = len(s.names)
        o = cp.zeros(2 + 2 * ng, dtype=cp.uint64)
        s.mod.get_function('kst_layout')((1,), (1,), (o,)); o = cp.asnumpy(o)
        s.S = int(o[0]); assert int(o[1]) == ng, 'layout: %d globals on the device, %d in globals.tsv' % (o[1], ng)
        s.off = o[2::2].astype(np.int64); s.size = o[3::2].astype(np.int64)
        fo = cp.zeros(max(1, len(s.fnames)), dtype=cp.uint64)
        s.mod.get_function('kst_funcs')((1,), (1,), (fo,)); s.faddr = cp.asnumpy(fo)
        s.S = (s.S + 255) & ~255

    def set_base(s, ptr):
        g = s.mod.get_global('g_kst_base')
        cp.cuda.runtime.memcpy(g.ptr, np.array([ptr], dtype=np.uint64).ctypes.data, 8, cp.cuda.runtime.memcpyHostToDevice)


def pack(dev, snaps):
    """host images for N threads: kst (N, S), heap (N, H), str (N, Z) + per-thread heap offsets; pointers filled in after
    the device buffers exist (needs their addresses): returns a closure"""
    N = len(snaps); S = dev.S; ng = len(dev.names)
    hoffs = []; H = 16
    for sn in snaps:
        ho = {}; h = 0
        for si, (k, i, b) in enumerate(sn.segs):
            if k == 1: ho[si] = h; h += (len(b) + 15) & ~15
        hoffs.append(ho); H = max(H, h)
    soffs = []; Z = 16
    for sn in snaps:
        so = []; z = 0
        for st in sn.strs: so.append(z); z += (len(st) + 15) & ~15
        soffs.append(so); Z = max(Z, z)
    for t, sn in enumerate(snaps): check_raw(dev, sn, t)
    kst = np.zeros((N, S), dtype=np.uint8); heap = np.zeros((N, H), dtype=np.uint8); strs = np.zeros((N, Z), dtype=np.uint8)
    for t, sn in enumerate(snaps):
        if sn.ng != ng: raise ValueError('snapshot has %d globals, device %d' % (sn.ng, ng))
        for si, (k, i, b) in enumerate(sn.segs):
            if k == 0:
                if len(b) != dev.size[i]: raise ValueError('global %s: %d bytes on the CPU, %d on the device' % (dev.names[i], len(b), dev.size[i]))
                kst[t, dev.off[i]:dev.off[i] + len(b)] = np.frombuffer(b, dtype=np.uint8)
            else:
                o = hoffs[t][si]; heap[t, o:o + len(b)] = np.frombuffer(b, dtype=np.uint8)
        for j, st in enumerate(sn.strs): strs[t, soffs[t][j]:soffs[t][j] + len(st)] = np.frombuffer(st, dtype=np.uint8)
    return kst, heap, strs, hoffs, soffs, S, H, Z


def relocate(dev, snaps, kst, heap, hoffs, soffs, bk, bh, bz, S, H, Z):
    for t, sn in enumerate(snaps):
        segbase = []
        for si, (k, i, b) in enumerate(sn.segs):
            segbase.append((0, t * S + int(dev.off[i])) if k == 0 else (1, t * H + hoffs[t][si]))
        for r in sn.rels:
            seg, kind, off, tgt, toff = int(r['seg']), int(r['kind']), int(r['off']), int(r['tgt']), int(r['toff'])
            if kind == 1:
                a, o = segbase[tgt]; v = (bk if a == 0 else bh) + o + toff
            elif kind == 2: v = int(dev.faddr[tgt])
            elif kind == 3: v = bz + t * Z + soffs[t][tgt]
            else: continue
            a, o = segbase[seg]; arr, base = (kst, t * S) if a == 0 else (heap, t * H)
            row = arr[t]; p = o - base + off
            row[p:p + 8] = np.frombuffer(np.uint64(v).tobytes(), dtype=np.uint8)


def unpack(dev, snaps, kst, heap, hoffs, soffs, bk, bh, bz, S, H, Z):
    """device images -> KSN1 snapshots (segment bytes + relocations recomputed by scanning every 8-byte word)"""
    out = []; unknown = 0
    fa = {int(a): k for k, a in enumerate(dev.faddr)}
    for t, sn in enumerate(snaps):
        rng = []   # (lo, hi, seg index) in device address space
        for si, (k, i, b) in enumerate(sn.segs):
            lo = (bk + t * S + int(dev.off[i])) if k == 0 else (bh + t * H + hoffs[t][si]); rng.append((lo, lo + len(b), si))
        rng.sort(); los = np.array([x[0] for x in rng], dtype=np.uint64); his = np.array([x[1] for x in rng], dtype=np.uint64)
        sidx = np.array([x[2] for x in rng]); zlo, zhi = bz + t * Z, bz + (t + 1) * Z
        sb = {zlo + o: j for j, o in enumerate(soffs[t])}
        segs = []; rels = []
        for si, (k, i, b) in enumerate(sn.segs):
            src = kst[t, int(dev.off[i]):int(dev.off[i]) + len(b)] if k == 0 else heap[t, hoffs[t][si]:hoffs[t][si] + len(b)]
            nb = src.tobytes(); segs.append((k, i, nb))
            nw = len(nb) // 8
            if not nw: continue
            w = np.frombuffer(nb, dtype=np.uint64, count=nw)
            cand = np.nonzero(w >= np.uint64(1 << 32))[0]
            if not len(cand): continue
            v = w[cand]; j = np.searchsorted(los, v, side='right') - 1
            ok = (j >= 0) & (v < his[np.maximum(j, 0)])
            for c, vv, jj, o_ in zip(cand, v, j, ok):
                vv = int(vv)
                if o_: rels.append((si, 1, int(c) * 8, int(sidx[jj]), vv - int(los[jj])))
                elif vv in fa: rels.append((si, 2, int(c) * 8, fa[vv], 0))
                elif zlo <= vv < zhi and vv in sb: rels.append((si, 3, int(c) * 8, sb[vv], 0))
                elif bk <= vv < bk + len(snaps) * S or bh <= vv < bh + len(snaps) * H or bz <= vv < bz + len(snaps) * Z: unknown += 1
        out.append((segs, rels))
    return out, unknown


# words a kernel may hold without a relocation: never dereferenced in the frame loop / elbow search (setjmp buffer of the
# plugin's crash guard; main's --set-at array, only read when --set-at was given: those jobs stay on the CPU)
RAW_OK = {'g_guard_jb', 'g_al_sets_at', 'g_rsets', 'g_vm_setlog', '__ls_load_rec_line'}


def check_raw(dev, sn, t):
    """refuse a state that holds a host pointer with no relocation (the 19:33 fault): any word in a typical x86-64 user
    address range (heap 0x5xxx.., mmap/stack 0x7xxx..) that al_snap_write could not map. Text tables (g_rsets etc.) are
    exempt: their bytes are characters."""
    rel = set(zip(sn.rels['seg'].tolist(), sn.rels['off'].tolist())) if len(sn.rels) else set()
    bad = []
    for si, (k, i, b) in enumerate(sn.segs):
        nm = dev.names[i] if k == 0 else 'heap%d' % i
        if k == 0 and nm in RAW_OK: continue
        nw = len(b) // 8
        if not nw: continue
        w = np.frombuffer(b, dtype='<u8', count=nw)
        hit = np.nonzero((w >= np.uint64(0x500000000000)) & (w < np.uint64(0x800000000000)))[0]
        for c in hit.tolist():
            if (si, c * 8) not in rel: bad.append('%s+%d=%#x' % (nm, c * 8, int(w[c])))
    if bad: raise SystemExit('kfpgpu: state %d holds %d unrelocated host pointer(s): %s (fix the capture; no launch)' % (t, len(bad), ' '.join(bad[:8])))


def stack_limit(n):
    cp.cuda.runtime.deviceSetLimit(0x00, n)   # cudaLimitStackSize


def run_loop(a):
    t0 = time.time()
    dev = Dev(a.mod, a.globals, a.funcs)
    jobs = [l.split() for l in open(a.list).read().splitlines() if l.strip()]
    snaps = []
    for (bp, _) in jobs:
        buf = open(bp, 'rb').read(); sn, _ = read_snap(buf, 0); snaps.append(sn)
    nfr = snaps[0].n; assert all(s.n == nfr for s in snaps), 'jobs must share the frame count (same recording)'
    t1 = time.time()
    kst, heap, strs, hoffs, soffs, S, H, Z = pack(dev, snaps)
    N = len(snaps)
    dk = cp.empty(kst.size, dtype=cp.uint8); dh = cp.empty(heap.size, dtype=cp.uint8); dz = cp.asarray(strs.reshape(-1))
    bk, bh, bz = dk.data.ptr, dh.data.ptr, dz.data.ptr
    relocate(dev, snaps, kst, heap, hoffs, soffs, bk, bh, bz, S, H, Z)
    dk.set(kst.reshape(-1)); dh.set(heap.reshape(-1)); dev.set_base(bk)
    stack_limit(a.stack)
    t2 = time.time()
    k = dev.mod.get_function('loop_kernel'); bs = a.block; grid = ((N + bs - 1) // bs,)
    i = 0; step = a.first_chunk; chunks = 0; kt = 0.0
    while i < nfr:
        j = min(nfr, i + step); e0 = cp.cuda.Event(); e1 = cp.cuda.Event(); e0.record()
        k(grid, (bs,), (np.int32(N), np.int32(i), np.int32(j))); e1.record(); e1.synchronize()
        ms = cp.cuda.get_elapsed_time(e0, e1); kt += ms / 1000; chunks += 1
        rate = (j - i) / max(ms, 0.01)
        i = j; step = max(1, min(nfr, int(rate * a.chunk_ms)))
    t3 = time.time()
    kst = dk.get().reshape(N, S); heap = dh.get().reshape(N, H)
    t4 = time.time()
    res, unknown = unpack(dev, snaps, kst, heap, hoffs, soffs, bk, bh, bz, S, H, Z)
    for (bp, ap), sn, (segs, rels) in zip(jobs, snaps, res):
        with open(ap, 'wb') as f: write_snap(f, segs, rels, sn.strs, sn.ng, sn.nf)
    t5 = time.time()
    print(json.dumps({'mode': 'loop', 'jobs': N, 'frames': nfr, 'kst_bytes': S, 'heap_bytes': H, 'chunks': chunks,
                      'read_s': round(t1 - t0, 3), 'pack_upload_s': round(t2 - t1, 3), 'kernel_s': round(kt, 3),
                      'loop_wall_s': round(t3 - t2, 3), 'download_s': round(t4 - t3, 3), 'unpack_write_s': round(t5 - t4, 3),
                      'unknown_ptrs': unknown, 'total_s': round(t5 - t0, 3)}))


def run_selftest(a):
    """the host half of `loop` with no GPU: layout from the PTX, fake device addresses, the kernel = identity. The written
    after.snap files hold the BEFORE state; the CPU build then runs the loop itself (AL_GPU_LOAD + AL_GPU_CPURUN=1) and
    must give the plain replay's output byte for byte: proves capture + pack + relocate + unpack lose nothing."""
    t0 = time.time()
    dev = FakeDev(a.mod, a.globals, a.funcs)
    jobs = [l.split() for l in open(a.list).read().splitlines() if l.strip()]
    snaps = [read_snap(open(bp, 'rb').read(), 0)[0] for (bp, _) in jobs]
    kst, heap, strs, hoffs, soffs, S, H, Z = pack(dev, snaps)
    N = len(snaps); bk, bh, bz = 0x100000000000, 0x200000000000, 0x300000000000
    relocate(dev, snaps, kst, heap, hoffs, soffs, bk, bh, bz, S, H, Z)
    res, unknown = unpack(dev, snaps, kst, heap, hoffs, soffs, bk, bh, bz, S, H, Z)
    nrel_in = sum(len(sn.rels) for sn in snaps); nrel_out = sum(len(r) for _, r in res)
    for (bp, ap), sn, (segs, rels) in zip(jobs, snaps, res):
        with open(ap, 'wb') as f: write_snap(f, segs, rels, sn.strs, sn.ng, sn.nf)
    print(json.dumps({'mode': 'selftest', 'jobs': N, 'kst_bytes': S, 'heap_bytes': H, 'rels_in': nrel_in, 'rels_out': nrel_out,
                      'unknown_ptrs': unknown, 'total_s': round(time.time() - t0, 3)}))


def run_elb(a):
    t0 = time.time()
    dev = Dev(a.mod, a.globals, a.funcs)
    buf = open(a.cap, 'rb').read(); pos = 0; bef = []; aft = []
    while pos < len(buf) and len(bef) < a.max:
        s1, pos = read_snap(buf, pos); s2, pos = read_snap(buf, pos); bef.append(s1); aft.append(s2)
    N = len(bef); t1 = time.time()
    kst, heap, strs, hoffs, soffs, S, H, Z = pack(dev, bef)
    dk = cp.empty(kst.size, dtype=cp.uint8); dh = cp.empty(heap.size, dtype=cp.uint8); dz = cp.asarray(strs.reshape(-1))
    bk, bh, bz = dk.data.ptr, dh.data.ptr, dz.data.ptr
    relocate(dev, bef, kst, heap, hoffs, soffs, bk, bh, bz, S, H, Z)
    exp, _, _, _, _, _, _, _ = pack(dev, aft)
    relocate(dev, aft, exp, np.zeros_like(heap), hoffs, soffs, bk, bh, bz, S, H, Z)
    dk.set(kst.reshape(-1)); dh.set(heap.reshape(-1)); dev.set_base(bk); stack_limit(a.stack)
    t2 = time.time()
    k = dev.mod.get_function('elb_kernel'); bs = a.block
    e0 = cp.cuda.Event(); e1 = cp.cuda.Event(); e0.record()
    k(((N + bs - 1) // bs,), (bs,), (np.int32(N),)); e1.record(); e1.synchronize()
    ms = cp.cuda.get_elapsed_time(e0, e1)
    got = dk.get().reshape(N, S); t3 = time.time()
    # compare per global: bytes equal; for differing globals, report the first few names
    same = 0; diffn = {}
    for t in range(N):
        d = np.nonzero(got[t] != exp[t])[0]
        if not len(d): same += 1; continue
        gi = np.searchsorted(dev.off, d, side='right') - 1
        for g in set(gi.tolist()): diffn[dev.names[g]] = diffn.get(dev.names[g], 0) + 1
    print(json.dumps({'mode': 'elb', 'calls': N, 'identical': same, 'kernel_ms': round(ms, 3), 'kernel_us_per_call': round(1000 * ms / max(N, 1), 3),
                      'read_s': round(t1 - t0, 3), 'pack_upload_s': round(t2 - t1, 3), 'total_s': round(t3 - t0, 3),
                      'diff_globals': dict(sorted(diffn.items(), key=lambda x: -x[1])[:12])}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['loop', 'elb', 'selftest'])
    ap.add_argument('--mod', required=True); ap.add_argument('--globals', required=True); ap.add_argument('--funcs', required=True)
    ap.add_argument('--list'); ap.add_argument('--cap'); ap.add_argument('--max', type=int, default=1 << 30)
    ap.add_argument('--chunk-ms', type=float, default=150.0); ap.add_argument('--first-chunk', type=int, default=4)
    ap.add_argument('--block', type=int, default=64); ap.add_argument('--stack', type=int, default=16384)
    a = ap.parse_args()
    {'loop': run_loop, 'elb': run_elb, 'selftest': run_selftest}[a.mode](a)


if __name__ == '__main__':
    main()
