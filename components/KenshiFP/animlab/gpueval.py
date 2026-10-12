#!/usr/bin/env python3
"""gpueval.py -- one evaluator interface for lab optimizers: replay candidates on the CPU adapter or batch them to the
GPU evaluator (gpu-wire 2026-10-11, Shay: move lab evaluation to the GPU, compare GPU vs CPU, CPU re-check of the winner).

A "job" = one adapter replay, exactly the CPU call `<adapter> <rec> <out> <args...>`:
    {"id": str, "adapter": path, "rec": path, "args": [..], "out": path}
Modes (--eval / env ANIMLAB_EVAL, default cpu):
  cpu       adapter replays through labcache.replay (result cache), thread pool of LABNICE_J (default 6)
  gpu       writes the jobs to a JSONL file and runs the GPU batch command once per batch:
              <GPU_EVAL_CMD> <jobs.jsonl> <results.jsonl>
            results.jsonl = one {"id","out","rc","ms"} per job; every out file has the CPU adapter's text format.
            GPU_EVAL_CMD = env ANIMLAB_GPU_EVAL_CMD, else line 1 of C:\\KenshiTestRuns\\gpu-wire\\gpu-eval-cmd.txt
            (owned by gpu-lab). No command = GpuUnavailable (loud), never a silent CPU fallback.
  gpu-stub  the gpu protocol (jobs/results files, one batch call) served by `gpueval.py cpu-batch` = CPU adapter; tests
            the plumbing until the GPU kernel lands. Results are CPU results: never report them as GPU numbers.
Winner re-check: confirm(job, out) re-runs the job on the CPU and compares the replay text (rawdiff); any difference over
tolerance raises GpuCpuDisagree. Optimizers call it on the final winner before any game take.

API:
  ev = Evaluator('gpu'); res = ev.replay_batch(jobs)          # -> [{"id","out","rc","ms"}] in job order
  ev.confirm(job, res[i]['out'])                              # CPU re-check, raises on disagreement
  pa_line(weapon, rec, sets, ev, strokes='2')                 # pasweep.py's PA line through the evaluator
  rawdiff(cpu_path, other_path) -> dict(max_abs, p99, n_frames, bad_frames, state_mismatch, ...)
  judge_line(weapon_or_None, out_path, tip) -> pasweep judge text for one replay
CLI:
  gpueval.py cpu-batch <jobs.jsonl> <results.jsonl> [-j N]     CPU backend in the batch protocol (gpu-stub)
  gpueval.py batch <jobs.jsonl> <results.jsonl> [--eval M]    any backend (default ANIMLAB_EVAL) -> results (+backend=GPU|CPU)
GPU command styles: a command containing "kfpvm-gpu" (or ANIMLAB_GPU_STYLE=argv) gets gpu-lab's contract, one call per
  adapter: <cmd> --adapter A --jobs <list> (list = kfpvm_replay argv lines `<rec> <out> args...`; <list>.gpu.tsv job#/GPU|CPU/why);
  any other command gets <cmd> <jobs.jsonl> <results.jsonl>.
  gpueval.py pa <weapon> <rec> [k=v ...] [--eval M]            pasweep.py drop-in (same PA line), replays via the evaluator
  gpueval.py confirm <jobs.jsonl> <results.jsonl>              CPU re-check of every result (exit 3 on disagreement)
  gpueval.py selftest
"""
import sys, os, json, re, time, shlex, subprocess, tempfile, hashlib
from concurrent.futures import ThreadPoolExecutor

LAB = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab'
if LAB not in sys.path:
    sys.path.insert(0, LAB)
HERE = os.path.dirname(os.path.abspath(__file__))
CMD_FILE = '/mnt/c/KenshiTestRuns/gpu-wire/gpu-eval-cmd.txt'
RAW_TOL = float(os.environ.get('ANIMLAB_GPU_RAW_TOL', '0.02'))   # max abs diff per number in the replay text (4 decimals)


class GpuUnavailable(RuntimeError):
    pass


class GpuCpuDisagree(RuntimeError):
    pass


def gpu_cmd():
    c = os.environ.get('ANIMLAB_GPU_EVAL_CMD', '').strip()
    if not c and os.path.exists(CMD_FILE):
        c = (open(CMD_FILE).readline() or '').strip()
    return c


def _argv_style(cmd):
    """gpu-lab's batch entry takes --adapter/--jobs argv lists (kfpvm-gpu.sh); anything else gets jobs/results JSONL."""
    return os.environ.get('ANIMLAB_GPU_STYLE', '').lower() == 'argv' or 'kfpvm-gpu' in cmd


def _cpu_one(job, cache=True):
    import labcache
    t0 = time.time()
    if cache:
        rc, so, se = labcache.replay([job['adapter']], job['rec'], job['out'], list(job['args']))
    else:
        p = subprocess.run([job['adapter'], job['rec'], job['out']] + list(job['args']), stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, universal_newlines=True)
        rc = p.returncode
    return {'id': job['id'], 'out': job['out'], 'rc': rc, 'ms': round((time.time() - t0) * 1000, 1)}


class Evaluator:
    def __init__(self, mode=None, workers=None, cache=True, log=None):
        self.mode = (mode or os.environ.get('ANIMLAB_EVAL') or 'cpu').strip().lower()
        if self.mode not in ('cpu', 'gpu', 'gpu-stub'):
            raise ValueError('eval mode %r (cpu|gpu|gpu-stub)' % self.mode)
        self.workers = workers or int(os.environ.get('LABNICE_J') or 6)
        self.cache = cache
        self.log = log or (lambda s: None)
        self.batches = 0

    def replay_batch(self, jobs):
        jobs = list(jobs)
        if not jobs:
            return []
        self.batches += 1
        if self.mode == 'cpu':
            with ThreadPoolExecutor(self.workers) as ex:
                return list(ex.map(lambda j: _cpu_one(j, self.cache), jobs))
        if self.mode == 'gpu':
            cmd = gpu_cmd()
            if not cmd:
                raise GpuUnavailable('ANIMLAB_EVAL=gpu but no GPU evaluator command (env ANIMLAB_GPU_EVAL_CMD or %s)' % CMD_FILE)
            if _argv_style(cmd):
                return self._argv_batch(cmd, jobs)
        else:
            cmd = '%s %s cpu-batch -j %d' % (sys.executable, os.path.abspath(__file__), self.workers)
        d = tempfile.mkdtemp(prefix='gpueval-', dir='/dev/shm' if os.path.isdir('/dev/shm') else None)
        jf, rf = os.path.join(d, 'jobs.jsonl'), os.path.join(d, 'results.jsonl')
        with open(jf, 'w') as f:
            for j in jobs:
                f.write(json.dumps(j) + '\n')
        t0 = time.time()
        p = subprocess.run(shlex.split(cmd) + [jf, rf], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        self.log('gpueval %s batch %d jobs %.2fs rc=%d' % (self.mode, len(jobs), time.time() - t0, p.returncode))
        got = {}
        if os.path.exists(rf):
            for l in open(rf):
                if l.strip():
                    r = json.loads(l); got[r['id']] = r
        subprocess.run(['rm', '-rf', d])
        miss = [j['id'] for j in jobs if j['id'] not in got]
        if p.returncode != 0 or miss:
            raise RuntimeError('gpueval %s backend failed rc=%d missing=%d: %s' % (self.mode, p.returncode, len(miss), p.stdout[-800:]))
        return [got[j['id']] for j in jobs]

    def _argv_batch(self, cmd, jobs):
        """gpu-lab's kfpvm-gpu.sh contract: `<cmd> --adapter A --jobs <list>`, list = one kfpvm_replay argv per line
        (`<rec> <out> [args...]`, shell-quoted), one call per adapter; <list>.gpu.tsv = job# \\t GPU|CPU \\t reason
        (job# 1-based list line or 0-based: both accepted). Results get backend=GPU|CPU from the tsv."""
        d = tempfile.mkdtemp(prefix='gpueval-', dir='/dev/shm' if os.path.isdir('/dev/shm') else None)
        got = {}
        try:
            by = {}
            for j in jobs:
                by.setdefault(j['adapter'], []).append(j)
            for ai, (ad, js) in enumerate(by.items()):
                lf = os.path.join(d, 'jobs%d.txt' % ai)
                with open(lf, 'w') as f:
                    for j in js:
                        f.write(' '.join(shlex.quote(x) for x in [j['rec'], j['out']] + list(j['args'])) + '\n')
                t0 = time.time()
                p = subprocess.run(shlex.split(cmd) + ['--adapter', ad, '--jobs', lf], stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, universal_newlines=True)
                ms = (time.time() - t0) * 1000.0 / len(js)
                self.log('gpueval gpu(argv) batch %d jobs %.2fs rc=%d' % (len(js), time.time() - t0, p.returncode))
                if p.returncode != 0:
                    raise RuntimeError('gpueval gpu backend rc=%d: %s' % (p.returncode, p.stdout[-800:]))
                be = {}
                tsv = lf + '.gpu.tsv'
                if os.path.exists(tsv):
                    rows = [l.rstrip('\n').split('\t') for l in open(tsv) if l.strip()]
                    nums = [int(r[0]) for r in rows if r and r[0].isdigit()]
                    base = 1 if nums and min(nums) >= 1 and max(nums) == len(js) else 0
                    for r in rows:
                        if r and r[0].isdigit() and 0 <= int(r[0]) - base < len(js):
                            be[int(r[0]) - base] = (r[1] if len(r) > 1 else '?', r[2] if len(r) > 2 else '')
                for i, j in enumerate(js):
                    ok = os.path.exists(j['out']) and os.path.getsize(j['out']) > 0
                    b = be.get(i, ('?', 'no gpu.tsv row'))
                    got[j['id']] = {'id': j['id'], 'out': j['out'], 'rc': 0 if ok else 1, 'ms': round(ms, 1),
                                    'backend': b[0], 'why': b[1]}
        finally:
            subprocess.run(['rm', '-rf', d])
        bad = [i for i, r in got.items() if r['rc']]
        if bad:
            raise RuntimeError('gpueval gpu backend: %d jobs without output (%s ...)' % (len(bad), bad[:3]))
        return [got[j['id']] for j in jobs]

    def replay(self, adapter, rec, out, args, jid=None):
        j = {'id': jid or hashlib.sha1(('%s %s %s' % (adapter, rec, args)).encode()).hexdigest()[:12],
             'adapter': adapter, 'rec': rec, 'args': list(args), 'out': out}
        return self.replay_batch([j])[0]

    def confirm(self, job, out, tol=None, judge=None):
        """re-run job on the CPU (no cache) and compare with `out` (the GPU result). Raises GpuCpuDisagree."""
        tol = RAW_TOL if tol is None else tol
        d = tempfile.mkdtemp(prefix='gpueval-confirm-')
        cj = dict(job, out=os.path.join(d, 'cpu.txt'), id=job['id'] + '-cpu')
        r = _cpu_one(cj, cache=False)
        if r['rc'] != 0:
            raise GpuCpuDisagree('CPU re-check of %s failed rc=%d' % (job['id'], r['rc']))
        rd = rawdiff(cj['out'], out)
        msg = 'confirm %s: max_abs=%.4g bad_frames=%d state_mismatch=%d frames=%d/%d' % (
            job['id'], rd['max_abs'], rd['bad_frames'], rd['state_mismatch'], rd['n_other'], rd['n_cpu'])
        bad = rd['max_abs'] > tol or rd['state_mismatch'] or rd['n_other'] != rd['n_cpu']
        if judge and not bad:
            a, b = judge(cj['out']), judge(out)
            if a != b:
                bad = True; msg += ' judge differs: cpu=%s | gpu=%s' % (a[:200], b[:200])
        subprocess.run(['rm', '-rf', d])
        if bad:
            raise GpuCpuDisagree('GPU-CPU DISAGREE ' + msg)
        return msg


# ---------------------------------------------------------------- replay text diff
_num = re.compile(r'^-?\d+(\.\d+)?(e[-+]?\d+)?$')


def _frames(path):
    import gzip
    op = gzip.open if path.endswith('.gz') else open
    with op(path, 'rt') as f:
        return [l.split() for l in f if l.strip() and not l.startswith('#')]


def rawdiff(cpu_path, other_path, tol=None):
    """per-number comparison of two replay texts (non-# lines; tokens split on whitespace, ',' and '|')."""
    tol = RAW_TOL if tol is None else tol
    A, B = _frames(cpu_path), _frames(other_path)
    diffs, bad, smis, maxv, where = [], 0, 0, 0.0, None
    for i, (a, b) in enumerate(zip(A, B)):
        fa = ','.join(a).replace('|', ',').split(','); fb = ','.join(b).replace('|', ',').split(',')
        fbad = len(fa) != len(fb)
        for x, y in zip(fa, fb):
            if x == y:
                continue
            if _num.match(x) and _num.match(y):
                d = abs(float(x) - float(y)); diffs.append(d)
                if d > maxv:
                    maxv, where = d, i
                if d > tol:
                    fbad = True
            else:
                smis += 1; fbad = True
        bad += fbad
    diffs.sort()
    return {'max_abs': maxv, 'p99': diffs[int(0.99 * (len(diffs) - 1))] if diffs else 0.0, 'n_diff': len(diffs),
            'bad_frames': bad, 'state_mismatch': smis, 'n_cpu': len(A), 'n_other': len(B), 'worst_frame': where}


# ---------------------------------------------------------------- judge (pasweep.py one(), minus the replay)
_W = None


def weapon(name):
    global _W
    if _W is None:
        _W = json.load(open(os.path.join(HERE, 'weapons', 'weapons.json')))['weapons']
    return [x for x in _W if x['name'] == name][0]


def judge_line(w, out, tip):
    import weapon_matrix as WM, metrics as M, recfmt
    j = WM.judge(w, out) if w else {}
    R = recfmt.parse(out); F = R.frames
    M.BLADE[0] = tip
    P = M.frame_metrics(R)
    fok, ftxt = M.framed_check(F, P)
    ok, ptxt = M.path_check(F, P)
    T = M.state_table(P); aok, atxt = M.arc_gate(T, {'swing': M.ARC_SHARE})
    jt = ' '.join('%s=%s' % (k, 'ok' if v[0] else ('FAIL' if v[0] is False else '-')) for k, v in j.items() if k not in ('framed', 'arc'))
    if 'arc' in j: jt += ' wmarc=%s' % ('ok' if j['arc'][0] else 'FAIL')
    if 'twohand' in j: jt += ' twoh_share=%.2f' % (lambda a, b: a / max(b, 1))(*map(int, j['twohand'][1].split('/')))
    return '%s | %s | arc %s | path=%s %s' % (','.join(ftxt), jt, ' '.join(atxt), 'ok' if ok else 'FAIL', ' ; '.join(ptxt))


def pa_jobs(name, rec, sets, adapter, outdir, strokes='2', jid='pa'):
    """the jobs pasweep.py runs for one variant: stroke 0 as recorded + each forced stroke."""
    import weapon_matrix as WM
    w = weapon(name); pom, tip = WM.two_dims(w)
    base = ['wcat=%d' % w['cls'], 'wpom=%.3f' % pom, 'wtip=%.3f' % tip]
    jobs = []
    for lab, extra in [('', [])] + [('S' + s, ['stroke=' + s]) for s in strokes.split(',') if s]:
        args = sum([['--set', s] for s in base + list(sets) + extra], []) + ['--quiet']
        h = hashlib.sha1((' '.join(args) + rec + adapter).encode()).hexdigest()[:12]
        jobs.append({'id': '%s-%s' % (jid, lab or 's0'), 'adapter': adapter, 'rec': rec, 'args': args,
                     'out': os.path.join(outdir, h + '.txt'), 'label': lab})
    return w, tip, jobs


def pa_text(w, tip, jobs, outs):
    parts = []
    for j, o in zip(jobs, outs):
        t = judge_line(w, o, tip)
        parts.append((j['label'] + ' ' if j['label'] else '') + t)
    return ' || '.join(parts)


def pa_line(name, rec, sets, ev=None, strokes='2', adapter=None, outdir='/root/pa-work/rp-eval'):
    ev = ev or Evaluator()
    adapter = adapter or os.environ.get('PA_ADAPTER', '/root/animlab-build/kfpvm_b17')
    os.makedirs(outdir, exist_ok=True)
    w, tip, jobs = pa_jobs(name, rec, sets, adapter, os.path.join(outdir, ev.mode), strokes)
    os.makedirs(os.path.join(outdir, ev.mode), exist_ok=True)
    res = ev.replay_batch(jobs)
    return 'PA [%s] %s' % (' '.join(sets) or 'base', pa_text(w, tip, jobs, [r['out'] for r in res]))


# ---------------------------------------------------------------- CLI
def _read_jsonl(p):
    return [json.loads(l) for l in open(p) if l.strip()]


def main(argv):
    if not argv:
        print(__doc__); return 2
    c = argv[0]
    if c in ('cpu-batch', 'batch'):
        a = [x for x in argv[1:]]
        j = 6; mode = 'cpu' if c == 'cpu-batch' else None
        if '-j' in a:
            k = a.index('-j'); j = int(a[k + 1]); del a[k:k + 2]
        if '--eval' in a:
            k = a.index('--eval'); mode = a[k + 1]; del a[k:k + 2]
        jobs = _read_jsonl(a[0])
        for x in jobs:
            os.makedirs(os.path.dirname(x['out']) or '.', exist_ok=True)
        res = Evaluator(mode, workers=j, log=lambda s: print(s, file=sys.stderr)).replay_batch(jobs)
        with open(a[1], 'w') as f:
            for r in res:
                f.write(json.dumps(r) + '\n')
        return 0 if all(r['rc'] == 0 for r in res) else 1
    if c == 'pa':
        a = argv[1:]; mode = None
        if '--eval' in a:
            k = a.index('--eval'); mode = a[k + 1]; del a[k:k + 2]
        print(pa_line(a[0], a[1], a[2:], Evaluator(mode), os.environ.get('PA_STROKES', '2')))
        return 0
    if c == 'confirm':
        jobs = {j['id']: j for j in _read_jsonl(argv[1])}
        ev = Evaluator('cpu'); bad = 0
        for r in _read_jsonl(argv[2]):
            try:
                print(ev.confirm(jobs[r['id']], r['out']))
            except GpuCpuDisagree as e:
                bad += 1; print(e)
        print('CONFIRM %s %d disagree' % ('FAIL' if bad else 'PASS', bad))
        return 3 if bad else 0
    if c == 'selftest':
        return selftest()
    print(__doc__); return 2


def selftest():
    d = tempfile.mkdtemp(prefix='gpueval-st-')
    a, b = os.path.join(d, 'a.txt'), os.path.join(d, 'b.txt')
    open(a, 'w').write('# h\n0 0.0000 ready 1.0000,2.0000 | 3.0000\n1 0.1000 swing 1.5000,2.0000 | 3.0000\n')
    open(b, 'w').write('# x\n0 0.0000 ready 1.0000,2.0050 | 3.0000\n1 0.1000 swing 1.5000,2.0000 | 3.0000\n')
    r = rawdiff(a, b); assert abs(r['max_abs'] - 0.005) < 1e-9 and r['bad_frames'] == 0, r
    open(b, 'w').write('0 0.0000 ready 1.0000,2.5000 | 3.0000\n1 0.1000 block 1.5000,2.0000 | 3.0000\n')
    r = rawdiff(a, b); assert r['bad_frames'] == 2 and r['state_mismatch'] == 1, r
    try:
        os.environ['ANIMLAB_GPU_EVAL_CMD'] = ''
        if not os.path.exists(CMD_FILE):
            Evaluator('gpu').replay_batch([{'id': 'x', 'adapter': '/bin/true', 'rec': a, 'args': [], 'out': b}])
            raise AssertionError('gpu mode without a command must raise')
    except GpuUnavailable:
        pass
    # gpu-stub protocol with a fake adapter (cp rec -> out), and confirm() catches a corrupted "GPU" output
    fake = os.path.join(d, 'fake-adapter.sh')
    open(fake, 'w').write('#!/bin/sh\ncp "$1" "$2"\n'); os.chmod(fake, 0o755)
    jobs = [{'id': 'j%d' % i, 'adapter': fake, 'rec': a, 'args': ['--set', 'k=%d' % i], 'out': os.path.join(d, 'o%d.txt' % i)} for i in range(3)]
    res = Evaluator('gpu-stub', cache=False).replay_batch(jobs)
    assert [r['id'] for r in res] == ['j0', 'j1', 'j2'] and all(r['rc'] == 0 for r in res), res
    ev = Evaluator('cpu')
    ev.confirm(jobs[0], res[0]['out'])
    open(res[1]['out'], 'w').write(open(a).read().replace('1.5000', '1.9000'))
    try:
        ev.confirm(jobs[1], res[1]['out']); raise AssertionError('confirm missed a corrupted output')
    except GpuCpuDisagree:
        pass
    # gpu-lab argv contract (kfpvm-gpu.sh --adapter A --jobs list, list.gpu.tsv) with a fake batch entry
    fk = os.path.join(d, 'kfpvm-gpu.sh')
    open(fk, 'w').write('#!/bin/bash\nwhile [ $# -gt 0 ]; do case "$1" in --adapter) A="$2"; shift 2;; --jobs) L="$2"; shift 2;; *) shift;; esac; done\n'
                        'n=0; while IFS= read -r line; do n=$((n+1)); eval "set -- $line"; "$A" "$@"; '
                        'if [ $n = 2 ]; then printf "%d\\tCPU\\tset-at\\n" $n; else printf "%d\\tGPU\\t\\n" $n; fi; done < "$L" > "$L.gpu.tsv"\n')
    os.chmod(fk, 0o755)
    os.environ['ANIMLAB_GPU_EVAL_CMD'] = fk
    aj = [dict(x, out=os.path.join(d, 'g%d.txt' % i)) for i, x in enumerate(jobs)]
    res = Evaluator('gpu').replay_batch(aj)
    assert [r['backend'] for r in res] == ['GPU', 'CPU', 'GPU'] and all(os.path.exists(x['out']) for x in aj), res
    ev.confirm(aj[2], res[2]['out'])
    os.environ['ANIMLAB_GPU_EVAL_CMD'] = ''
    subprocess.run(['rm', '-rf', d])
    print('gpueval selftest PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
