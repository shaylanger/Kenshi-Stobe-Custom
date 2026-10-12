#!/usr/bin/env python3
"""pa-opt.py -- 2H/polearm table optimizer on the one evaluator interface (gpu-wire 2026-10-11, Shay's order: lab
evaluation on the GPU, compare GPU vs CPU, CPU re-check of the winner). WSL python3 (root); run via labnice.sh.

  pa-opt.py <weapon> <rec> [--eval cpu|gpu|gpu-stub] [--method cma|nm|cf] [--maxevals N] [--target S] [--strokes 2]
            [--adapter A] [--outdir D] [--seed N] [-j N] <param> ...
  param   name=x0:step[:lo:hi]   searched (e.g. tworP_x=13.4:4:-40:40)
          name=value             fixed (e.g. twospP=4)
Objective = the pasweep PA line score (gpu-agree.score = /root/pa-work/score.py), maximised; a variant failing the
hard gate scores score-10. Each CMA population is ONE evaluator batch (all variants x strokes -> one GPU call with
--eval gpu); the judge runs in a fork pool (-j, default LABNICE_J or 6).
End: the winner's replays are re-run on the CPU without cache (gpueval confirm: raw replay diff + judge line equal)
whatever --eval was; a disagreement prints `PAOPT FAIL cpu-recheck ...` (exit 3): never take a GPU-only winner to the game.
Output: `eval <n> f=<score> x=...` lines, `PAOPT DONE eval=<mode> score=<s> hard=<0|1> evals=<n> reason=<r> wall=<s>
cpu_recheck=PASS sets=<k=v ...>` + the winner's PA line in <outdir>/winner.txt.
"""
import sys, os, time, json, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
import gpueval as G
import optim

_s = importlib.util.spec_from_file_location('gpu_agree', os.path.join(HERE, 'gpu-agree.py'))
GA = importlib.util.module_from_spec(_s); _s.loader.exec_module(GA)


def parse(argv):
    o = dict(eval=None, method='cma', maxevals=120, target=None, strokes='2', adapter=None,
             outdir='/root/pa-work/pa-opt', seed=1, j=int(os.environ.get('LABNICE_J') or 6))
    pos, free, fixed = [], [], []
    a = list(argv)
    while a:
        x = a.pop(0)
        if x.startswith('--') or x == '-j':
            k = x.lstrip('-'); v = a.pop(0)
            o[k] = v if k in ('eval', 'method', 'strokes', 'adapter', 'outdir') else (float(v) if k == 'target' else int(v))
        elif '=' in x:
            n, v = x.split('=', 1)
            if ':' in v:
                p = [float(t) for t in v.split(':')]
                free.append((n, p[0], p[1], (p[2], p[3]) if len(p) >= 4 else None))
            else:
                fixed.append(x)
        else:
            pos.append(x)
    if len(pos) != 2 or not free:
        print(__doc__); sys.exit(2)
    return o, pos[0], pos[1], free, fixed


def fmt(n, v):
    return '%s=%g' % (n, round(v, 3))


def main(argv):
    o, wname, rec, free, fixed = parse(argv)
    ev = G.Evaluator(o['eval'], log=lambda s: print(s, flush=True))
    adapter = o['adapter'] or os.environ.get('PA_ADAPTER', '/root/animlab-build/kfpvm_b17')
    od = os.path.join(o['outdir'], ev.mode); os.makedirs(od, exist_ok=True)
    names = [f[0] for f in free]
    bounds = [f[3] or (-1e9, 1e9) for f in free]
    w = G.weapon(wname)
    cache = {}

    def sets_of(x):
        return fixed + [fmt(n, v) for n, v in zip(names, x)]

    def judge_variant(item):
        jobs, outs, tip = item
        return G.pa_text(w, tip, jobs, outs)

    from concurrent.futures import ProcessPoolExecutor
    import multiprocessing as mp
    pool = ProcessPoolExecutor(o['j'], mp_context=mp.get_context('fork'))
    G._judge_item = judge_variant   # fork-inherited

    def batch(xs):
        per = []
        for i, x in enumerate(xs):
            _, tip, jobs = G.pa_jobs(wname, rec, sets_of(x), adapter, od, o['strokes'], jid='v%d' % (len(cache) + i))
            per.append((jobs, tip))
        alljobs = [j for jobs, _ in per for j in jobs]
        res = {r['id']: r for r in ev.replay_batch(alljobs)}
        items = [(jobs, [res[j['id']]['out'] for j in jobs], tip) for jobs, tip in per]
        lines = list(pool.map(_judge_top, items))
        vals = []
        for x, (jobs, _), line in zip(xs, per, lines):
            hard, s = GA.score(line)
            v = s if hard else s - 10
            cache[tuple(round(t, 3) for t in x)] = (v, hard, line, jobs)
            vals.append(v)
        return vals

    t0 = time.time()
    r = optim.minimize(x0=[f[1] for f in free], step=[f[2] for f in free], method=o['method'], target=o['target'],
                       maxevals=o['maxevals'], bounds=bounds, batch=batch, maximize=True, seed=o['seed'],
                       round_to=1e-3, log=lambda s: print(s, flush=True))
    wall = time.time() - t0
    pool.shutdown()
    v, hard, line, jobs = cache[tuple(round(t, 3) for t in r.x)]
    # CPU re-check of the winner (always, also for --eval cpu: the cache-free run proves the cached replay)
    rc, msgs, tip = 'PASS', [], G.pa_jobs(wname, rec, [], adapter, od)[1]
    for j in jobs:
        try:
            msgs.append(ev.confirm(j, j['out'], judge=lambda p: G.judge_line(w, p, tip)))
        except G.GpuCpuDisagree as e:
            rc = 'FAIL'; msgs.append(str(e))
    sets = ' '.join(sets_of(r.x))
    with open(os.path.join(o['outdir'], 'winner.txt'), 'w') as f:
        f.write('PA [%s] %s\n' % (sets, line))
        f.write('\n'.join(msgs) + '\n')
    for m in msgs:
        print(m)
    print('PAOPT %s eval=%s score=%.3f hard=%d evals=%d reason=%s wall=%.1fs batches=%d cpu_recheck=%s sets=%s' % (
        'DONE' if rc == 'PASS' else 'FAIL cpu-recheck', ev.mode, v + (0 if hard else 10), int(hard), r.evals, r.reason,
        wall, ev.batches, rc, sets), flush=True)
    return 0 if rc == 'PASS' else 3


def _judge_top(item):
    return G._judge_item(item)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
