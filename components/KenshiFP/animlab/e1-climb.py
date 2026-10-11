"""e1-climb.py (lab, E1 2026-10-09; run in WSL from /root/animlab-work, env REC A WBL EH REG GEN POP SEED FZ PS START METHOD TARGET): climb (CMA-ES default, optim.py): strike key blade dirs (sw2..sw4 f) + E1 roll cap; objective arc_ok (stroke) with swing wb_max <= WBL."""
import sys, random, subprocess, json, os
AL = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab/animlab.py'
REC = os.environ.get('REC', '/root/animlab-work/f14-e0.txt'); A = os.environ.get('A', '/root/animlab-build/kfpvm_e1c')
WBL = float(os.environ.get('WBL', '45')); GEN = int(os.environ.get('GEN', '6')); POP = int(os.environ.get('POP', '24'))
FZ = float(os.environ.get('FZ', '0.25')); PS = float(os.environ.get('PS', '2'))
random.seed(int(os.environ.get('SEED', '2')))
best = json.loads(os.environ.get('START', '{}')) or dict(f1=(-0.55, 0.45, 0.70), f2=(-0.92, 0.02, 0.38), f3=(-0.90, -0.18, 0.40), cap=45.0, p1=(1.3, -0.45, 4.8), p2=(0.4, -0.6, 4.8), p3=(-0.6, -0.9, 4.6))
def args(p):
    a = ['--set e1elb=0', '--set e1cap=%.0f' % p['cap']]
    for k in ('p1', 'p2', 'p3'):
        if k in p: a += ['--set sw%d_p%s=%.3f' % (int(k[1]) + 1, c, v) for c, v in zip('xyz', p[k])]
    for k in ('f1', 'f2', 'f3'):
        a += ['--set sw%d_f%s=%.3f' % (int(k[1]) + 1, c, v) for c, v in zip('xyz', p[k])]
    return ' '.join(a)
EH = float(os.environ.get('EH', '2.1')); REG = float(os.environ.get('REG', '0.02'))
P0 = dict(p1=(1.3, -0.45, 4.8), p2=(0.4, -0.6, 4.8), p3=(-0.6, -0.9, 4.6))
def score(m, p=None):
    arc, wb, eh, ed = m
    s = arc - (0 if wb <= WBL else 0.02 * (wb - WBL)) - (0 if eh <= EH else 0.2 * (eh - EH)) - (0 if ed >= 0.2 else 0.5 * (0.2 - ed))
    if p: s -= REG * sum(sum((a - b) ** 2 for a, b in zip(p[k], P0[k])) ** 0.5 for k in P0 if k in p)
    return s
def run(ps):
    cmd = ['python3', AL, 'sweep', REC, '--adapter', A, '--args=--quiet', '--metrics', 'arc_ok,wb_max,elb_h_max,edge_mean'] + sum((['--variant', 'v%d: %s' % (i, args(p))] for i, p in enumerate(ps)), [])
    out = subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout.splitlines()
    hdr = [l for l in out if l.startswith('state ')][0].split()[2:]
    d = {l.split()[1]: l.split()[2:] for l in out if l.startswith('swing ')}
    return [tuple(float(d[m][hdr.index('v%d' % i)]) for m in ('arc_ok', 'wb_max', 'elb_h_max', 'edge_mean')) for i in range(len(ps))]
# search (Shay 2026-10-10 CPU cut): CMA-ES / Nelder-Mead / coarse-to-fine via harness tools/animlab/optim.py instead of
# GEN x POP random mutations; same objective (score), same budget cap (GEN*POP+1 evaluations), stops early at TARGET
# (env, score) or when converged. Each population is one `animlab.py sweep` (parallel replays, labcache-memoised).
# METHOD=random keeps the old mutation climb for comparison.
sys.path.insert(0, os.path.dirname(AL))
import optim
KEYS = [k for k in ('f1', 'f2', 'f3', 'p1', 'p2', 'p3') if k in best]
def pack(p): return [v for k in KEYS for v in p[k]] + [p['cap']]
def unpack(x):
    q = {k: tuple(round(v, 3) for v in x[3 * i:3 * i + 3]) for i, k in enumerate(KEYS)}
    for k in ('f1', 'f2', 'f3'): q[k] = q[k][:2] + (max(q[k][2], FZ),)
    q['cap'] = min(120.0, max(0.0, x[-1])); return q
step = [0.25 if k[0] == 'f' else 0.25 * PS for k in KEYS for _ in range(3)] + [15 * 0.25 / 0.2]
METHOD = os.environ.get('METHOD', 'cma'); TARGET = os.environ.get('TARGET')
def batch(xs):
    ps = [unpack(x) for x in xs]; return [score(m, p) for p, m in zip(ps, run(ps))]
if METHOD != 'random':
    r = optim.minimize(None, pack(best), step, method=METHOD, batch=batch, maximize=True, maxevals=GEN * POP + 1,
                       target=float(TARGET) if TARGET else None, tol=0.02, log=lambda l: print(l, flush=True))
    best = unpack(r.x); bm, = run([best])
    print('%s %s evals=%d m %s %s' % (METHOD, r.reason, r.evals, ','.join('%.2f' % x for x in bm), json.dumps(best)), flush=True)
    sys.exit(0)
def mut(p, s):
    q = dict(p)
    for k in ('f1', 'f2', 'f3'):
        v = [round(x + random.gauss(0, s), 3) for x in p[k]]; v[2] = max(v[2], FZ); q[k] = tuple(v)
    for k in ('p1', 'p2', 'p3'):
        if k in p: q[k] = tuple(round(x + random.gauss(0, s * PS), 3) for x in p[k])
    q['cap'] = min(120.0, max(0.0, p['cap'] + random.gauss(0, 15 * s / 0.2)))
    return q
bm, = run([best]); bs = score(bm, best); print('start', bm, flush=True)
for g in range(GEN):
    s = 0.25 if g < GEN // 2 else 0.1
    ps = [mut(best, s) for _ in range(POP)]
    for p, m in zip(ps, run(ps)):
        if score(m, p) > bs: best, bs, bm = p, score(m, p), m
    print('gen', g, 'm', ','.join('%.2f' % x for x in bm), json.dumps(best), flush=True)
