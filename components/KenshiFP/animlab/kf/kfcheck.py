#!/usr/bin/env python3
"""kfcheck.py: every swing check of one sword stroke variant over the sword-swing pool (keyframe-player 2026-10-11).

  kfcheck.py --stroke N [--tables F] [--set k=v].. [--adapter BIN] [--trav lo:hi] [--keep DIR] [--json OUT] [-j 10]

Replays every pool recording (corpus/pools/sword-swing/pool-all.list) through the adapter with `--no-rec-sets --set
stroke=N` + the variant (tables file / sets), judges every full swing of stroke N with the lab's swing checks
(metrics.swing_verdicts: arc edge + wrist, blade snap/seen, stroke length, churn, inline; metrics.path_metrics: straight
path dev/late, angle, end band, centre, fast share, travel; swing_rules: sweep/wexit) and the pool take rates
(metrics.pool_predict over arc blade stroke churn inline path). Score = the same objective as stroke-fix's obj.py
(copied, so the keyframe and table methods are judged by one yardstick): 0 = every swing inside every limit with margin.
Prints the per-check pool rates, the mean path metrics and `RESULT KFCHECK-s<N> PASS|FAIL score=..`.
Game-take gate (kf-lab 2026-10-11, Misses kf-s0b): kftake.py replays the corpus single-stroke E6 GAME takes
(pools/sword-take/take.list, shipped sword weapon sets kept) with the variant and runs the take judge's exact lab
commands; PASS needs the pool AND every take line; the take replays' swing penalties are added to the score
(`kftake:take=.. pen=..` in the RESULT). --no-take = pool only.
Replays go through labcache (result cache) and run at the caller's nice level (use labnice / nice 15)."""
import sys, os, re, tempfile, shlex, json, argparse, shutil
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
import recfmt, metrics as M, labcache

POOL = '/mnt/c/KenshiTestRuns/corpus/pools/sword-swing'
num = lambda pat, s, d=None: (lambda m: float(m.group(1)) if m else d)(re.search(pat, s))


def pool_recs():
    return [os.path.join(POOL, l.strip()) for l in open(os.path.join(POOL, 'pool-all.list')) if l.strip() and not l.startswith('#')]


def replays(adapter, stroke, tables, sets, j, keep=None):
    d = keep or tempfile.mkdtemp(prefix='kfchk-', dir='/tmp')
    os.makedirs(d, exist_ok=True)
    args = ['--no-rec-sets', '--set', 'stroke=%d' % stroke]
    if tables:
        args += ['--tables', tables]
    for kv in sets:
        args += ['--set', kv]

    def one(rec):
        out = os.path.join(d, os.path.basename(rec))
        rc, so, se = labcache.replay(shlex.split(adapter), rec, out, args)
        return out if rc == 0 and os.path.exists(out) else None
    with ThreadPoolExecutor(max_workers=j) as ex:
        return d, list(ex.map(one, pool_recs()))


def span_pen(m, b=M.PATH_BAND - 0.03, be=M.PATH_END_BAND - 0.025):
    W, H = M.W_PX, M.H_PX
    def out(q, side, bb):
        x, y = q[0] / W, q[1] / H
        return {'L': max(0, x - bb), 'R': max(0, (1 - bb) - x), 'T': max(0, y - bb), 'B': max(0, (1 - bb) - y)}[side]
    opp = {'L': 'R', 'R': 'L', 'T': 'B', 'B': 'T'}
    return min(out(m['start'], a, b) + out(m['end'], opp[a], be) for a in 'LRTB')


def pen_swing(v, pm, stroke, trav):
    p = {}
    p['arc'] = max(0, 0.88 - v['arc_good'] / max(1, v['arc_n'])) / 0.05 + max(0, v['wb_max'] - 46) / 3
    bt = ' '.join(v['btxt'])
    p['snap'] = max(0, num(r'snap=([\d.]+)', bt, 99) - 19) / 3
    p['seen'] = max(0, 0.065 - num(r'seen=([\d.]+)', bt, 0)) / 0.015
    st = ' '.join(v['stxt'])
    p['len'] = max(0, 260 - num(r'len=([\d.]+)', st, 0)) / 30
    # stroke_check overhead tilt + blade-middle path (stroke 2) were BAD in the verdict but unscored, so optimizers drifted
    # into them (kf-author 2026-10-11: CMA s2 reached tilt 82/35 with score 5.7); score them with a margin
    for lab, sc in ((('overhead tilt', 3.0), ('path', 2.0)) if stroke == 2 else ()):
        m = re.search(r'(?<![a-z])' + lab + r'=([\d.]+)/([\d.]+)', st)
        if m:
            p['len'] += max(0, float(m.group(1)) - 0.9 * float(m.group(2))) / sc
    ct = v['ctxt']
    p['roll'] = max(0, num(r'windup_roll=([\d.]+)', ct, 0) - 13) / 2 + max(0, num(r'stroke_roll=([\d.]+)', ct, 0) - 41) / 4 + max(0, num(r'step([\d.]+)', ct, 0) - 10.5) / 1.5
    it = ' '.join(v.get('itxt', []))
    q = 0
    for ph in ('windup', 'stroke'):
        m = re.search(ph + r':fb=([\d.]+)/([\d.]+),sc=([\d.]+)/([\d.]+),wr=([\d.]+)', it)
        if m:
            fm, fx, sm, sx, wr = map(float, m.groups())
            q += max(0, fm - 31) / 2 + max(0, fx - 37) / 2 + max(0, sx - 37) / 2 + (max(0, wr - 0.55) / 0.05 if ph == 'stroke' else 0)
    if not v['ok'].get('inline', True):
        q += 1
    p['inl'] = q
    if pm:
        p['path'] = max(0, pm['dev'] - 0.06) / 0.02 + max(0, pm['late'] - 0.035) / 0.015 + max(0, pm['edge'] - 0.075) / 0.02 + \
            (max(0, 38 - pm['ang']) / 2 + max(0, pm['ang'] - 47) / 2 if stroke in (0, 3) else 0) + \
            max(0, pm['ctr'] - 0.09) / 0.02 + span_pen(pm) / 0.03 + \
            (5 if pm['fast'] is None else max(0, 0.32 - pm['fast']) / 0.04 + max(0, pm['fast'] - 0.68) / 0.04)
        if trav:
            p['path'] += max(0, trav[0] - pm['trav']) / 0.01 + max(0, pm['trav'] - trav[1]) / 0.01
    else:
        p['path'] = 5
    pt = ' '.join(v.get('ptxt', []))
    sw = num(r'sweep=([\d.]+)', pt, None)
    p['rule'] = (max(0, 74 - sw) / 3 if sw is not None else 0) + 2 * len([t for t in re.findall(r'(\w+)=[^,]*:BAD', pt)
                                                                       if t not in ('dev', 'late', 'ang', 'edge', 'span', 'ctr', 'fast')])
    return p


def swings_of(out, stroke, trav, V, P_, PM):
    """every full stroke-N swing of one replay -> appended to V (verdicts), P_ (penalties), PM (path metrics)"""
    r = recfmt.parse(out)
    Pm = M.frame_metrics(r)
    ps = {k: S for k, (stk, S) in enumerate(M.path_series(r.frames, Pm))}
    for v in M.swing_verdicts(r.frames, Pm, (2,), inline=True):
        if v['stroke'] not in (None, -1, stroke) or not v['full']:
            continue
        v['rec'] = os.path.basename(out)
        S = ps.get(v['k'])
        pm = M.path_metrics([x[2] for x in S], us=[x[0] for x in S]) if S and len(S) >= M.PATH_MIN_N else None
        V.append(v); P_.append(pen_swing(v, pm, stroke, trav)); PM.append(pm)


def take_part(adapter, stroke, tables, sets, trav, j):
    """kf-lab 2026-10-11 (Misses kf-s0b): the GAME TAKE judge (kftake.py: corpus single-stroke E6 game takes replayed with
    their weapon/condition sets + the variant, judged by fp-e6-strokes.sh's lab commands) gates the verdict, and the same
    swing penalties computed on those replays join the score so a fit steers by the take conditions too (the pool
    replays carry no weapon geometry: k5sl scored 1.53 on the pool, wrist 82.7 in the game)."""
    import kftake
    td = tempfile.mkdtemp(prefix='kfchk-take-', dir='/tmp')
    try:
        tk = kftake.evaluate(adapter, stroke, tables, list(sets), None, j, keep=td)
        M.STROKE_ONLY = stroke
        V, P_, PM = [], [], []
        for f in sorted(os.listdir(td)):
            if f.endswith('.txt'):
                swings_of(os.path.join(td, f), stroke, trav, V, P_, PM)
    finally:
        shutil.rmtree(td, ignore_errors=True)
    tk['pen'] = 0.0
    if P_:
        keys = list(P_[0].keys())
        tk['pen'] = sum(sum(p[k] for p in P_) / len(P_) for k in keys) + 0.3 * sum(max(p[k] for p in P_) for k in keys)
    if not tk['ok']:
        tk['pen'] += 2.0   # a failing game-take line always costs more than the PASS margin
    return tk


def evaluate(adapter, stroke, tables=None, sets=(), trav=None, j=10, keep=None, take=True):
    M.STROKE_ONLY = stroke
    d, outs = replays(adapter, stroke, tables, list(sets), j, keep)
    V, P_, PM = [], [], []
    for out in outs:
        if not out:
            return dict(score=1e3, ok=False, txt='adapter fail', dir=d)
        swings_of(out, stroke, trav, V, P_, PM)
    if not keep:
        shutil.rmtree(d, ignore_errors=True)
    if not V:
        return dict(score=1e3, ok=False, txt='no swings', dir=d)
    keys = list(P_[0].keys())
    tot = {k: sum(p[k] for p in P_) / len(P_) for k in keys}
    worst = {k: max(p[k] for p in P_) for k in keys}
    ok, txt = M.pool_predict(V, ('arc', 'blade', 'stroke', 'churn', 'inline', 'path'))
    score = sum(tot.values()) + 0.3 * sum(worst.values())
    rates = re.sub(r',worst=\S+', '', ' '.join(t for t in txt if 'take=' in t))
    tk = None
    if take:
        tk = take_part(adapter, stroke, tables, sets, trav, j)
        score += tk['pen']
        ok = ok and tk['ok']
        rates += ' kftake:%s pen=%.2f' % (tk['txt'], tk['pen'])
    pms = [p for p in PM if p]
    mean = {}
    for k in ('ang', 'dev', 'late', 'edge', 'ctr', 'fast', 'trav'):
        xs = [p[k] for p in pms if p.get(k) is not None]
        mean[k] = sum(xs) / len(xs) if xs else None
    sw = [num(r'sweep=([\d.]+)', ' '.join(v.get('ptxt', [])), None) for v in V]
    sw = [x for x in sw if x is not None]
    mean['sweep'] = sum(sw) / len(sw) if sw else None
    mean['wb_max'] = max(v['wb_max'] for v in V)
    mean['arc_good'] = sum(v['arc_good'] / max(1, v['arc_n']) for v in V) / len(V)
    return dict(score=score, ok=ok, n=len(V), pen=tot, rates=rates, mean=mean, dir=d, take=tk,
                txt='score=%.3f %s n=%d | mean %s | %s' % (score, 'PASS' if ok else 'FAIL', len(V),
                                                       ' '.join('%s=%.2f' % (k, tot[k]) for k in keys), rates))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stroke', type=int, required=True)
    ap.add_argument('--tables')
    ap.add_argument('--set', action='append', default=[])
    ap.add_argument('--adapter', default='/root/animlab-build/kfpvm_kf')
    ap.add_argument('--trav')
    ap.add_argument('--keep')
    ap.add_argument('--json')
    ap.add_argument('-j', type=int, default=10)
    ap.add_argument('--tag', default='')
    ap.add_argument('--no-take', action='store_true', help='skip the game-take judge (kftake.py); pool only (old behaviour)')
    a = ap.parse_args()
    trav = tuple(map(float, a.trav.split(':'))) if a.trav else None
    r = evaluate(a.adapter, a.stroke, a.tables, a.set, trav, a.j, a.keep, take=not a.no_take)
    print(r['txt'])
    for l in (r.get('take') or {}).get('lines', []):
        if ' FAIL' in l and '(info)' not in l:
            print(l[:260])
    if 'mean' in r:
        print('path mean ' + ' '.join('%s=%s' % (k, 'n/a' if v is None else '%.3f' % v) for k, v in r['mean'].items()))
    if a.json:
        json.dump({k: v for k, v in r.items()}, open(a.json, 'w'), indent=1, default=str)
    print('RESULT KFCHECK-s%d%s %s score=%.3f %s' % (a.stroke, a.tag, 'PASS' if r['ok'] else 'FAIL', r['score'], r.get('rates', r['txt'])))
    return 0 if r['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
