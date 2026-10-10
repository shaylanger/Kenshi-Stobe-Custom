"""e1-climb.py (lab, E1 2026-10-09; run in WSL from /root/animlab-work, env REC A WBL EH REG GEN POP SEED FZ PS START): hill climb: strike key blade dirs (sw2..sw4 f) + E1 roll cap; objective arc_ok (stroke) with swing wb_max <= WBL."""
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
