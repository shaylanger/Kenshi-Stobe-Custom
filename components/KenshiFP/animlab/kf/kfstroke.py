#!/usr/bin/env python3
"""kfstroke.py: author / fit / preview KenshiFP keyframe sword strokes (kfp-keyframe-stroke, keyframe-player 2026-10-11).

  kfstroke.py fit  --stroke N [--src-set k=v].. [--src-tables F] --times t1,t2,.. -o out.txt [--opt N] [--lead 1] [--rk .6]
        sample the stroke as it is now (key arc / screen line, the plugin's own vm_swing_at via kfpvm_kfpath), put a key
        at each time (hilt + tip screen points, edge roll measured against the key's lead direction), optionally refine
        (Nelder-Mead over every key value + segment easing, --opt evals) to the source path, write a tables file
        (`kf.N`, `kfh.N`, `kfmask`, + --keep-set lines) and print the path error vs the source
  kfstroke.py make --stroke N --keys "t hx hy hz tx ty r [ea eb]; ..." -o out.txt [--rk .6] [--lead 1] [--set k=v]..
        hand-authored keys -> tables file (ea eb default 0 0 = linear)
  kfstroke.py path --stroke N --tables F [--vs-set k=v | --vs-tables F2]
        commanded tip path on the screen (no IK, milliseconds): line angle, straightness, travel (screen-diagonal
        fraction), start/end band, centre distance; with --vs the max difference to another variant
  kfstroke.py preview --stroke N --tables F -o DIR [--trav lo:hi] [--every 2]
        every swing check over the pool (kfcheck.py) + a labelled contact strip (strip.png) and a short clip (clip.mp4,
        full + 1/2 speed) of one replayed swing (render.py; no game)
Binaries: /root/animlab-build/kfpvm_kfpath, kfpvm_kf (kf/build-kf.sh). Screen numbers: x, y in -1..1 (y up), zoom-0 FP
view, tan half-angles 1.245 / 0.70 (1600x900)."""
import sys, os, subprocess, argparse, math, json, tempfile, shutil, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
KFPATH = os.environ.get('KFPATH', '/root/animlab-build/kfpvm_kfpath')
TX, TY = 1.245, 0.70
NK, NC = 6, 9
L_C0, OFF_C0 = 8.0, (0.10, 0.0, 0.80)


def vadd(a, b): return tuple(x + y for x, y in zip(a, b))
def vsub(a, b): return tuple(x - y for x, y in zip(a, b))
def vmul(a, s): return tuple(x * s for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a):
    l = math.sqrt(dot(a, a)); return vmul(a, 1.0 / l) if l > 1e-9 else a
def scr(p): return (p[0] / (p[2] * TX), p[1] / (p[2] * TY)) if p[2] > 1e-3 else (float('nan'), float('nan'))
def px(s): return ((s[0] + 1) * 800.0, (1 - s[1]) * 450.0)


def sample(stroke, sets=(), tables=None, steps=201):
    cmd = [KFPATH, '--stroke', str(stroke), '--steps', str(steps)]
    if tables:
        cmd += ['--tables', tables]
    for s in sets:
        cmd += ['--set', s]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode:
        raise SystemExit('kfpath: ' + out.stderr.strip())
    rows = []
    for ln in out.stdout.split('\n'):
        if '|' not in ln:
            continue
        a, b = ln.split('|')
        a = list(map(float, a.split())); b = list(map(float, b.split()))
        rows.append(dict(u=a[0], w=a[1], p=tuple(a[2:5]), f=tuple(a[5:8]), e=tuple(a[8:11]),
                         rp=tuple(b[0:3]), rf=tuple(b[3:6]), re=tuple(b[6:9])))
    return rows


def tip_of(p, f, L=L_C0, off=OFF_C0):
    return vadd(vadd(p, vmul(f, L)), off)


def hilt_of(p, off=OFF_C0):
    return vadd(p, off)


def key_from_pose(t, p, f):
    H = hilt_of(p); T = tip_of(p, f)
    hx, hy = scr(H); tx, ty = scr(T)
    return [t, hx, hy, H[2], tx, ty, 0.0, 0.0, 0.0]


def kf_hilt(k): return (k[1] * TX * k[3], k[2] * TY * k[3], k[3])


def kf_tip(H, tx, ty, L=L_C0):
    r = norm((tx * TX, ty * TY, 1.0)); b = dot(r, H); q = b * b - (dot(H, H) - L * L)
    return vmul(r, max(b + math.sqrt(q) if q > 0 else b, 0.5))


def zero_roll_edge(keys, j):
    """the plugin's zero-roll edge of key j (vm_kf_key): tip lead direction (neighbour keys) made perpendicular to f"""
    n = len(keys); k = keys[j]
    H = kf_hilt(k); T = kf_tip(H, k[4], k[5]); f = norm(vsub(T, H))
    a, b = keys[max(0, j - 1)], keys[min(n - 1, j + 1)]
    Ta = kf_tip(kf_hilt(a), a[4], a[5]); Tb = kf_tip(kf_hilt(b), b[4], b[5])
    d = vsub(Tb, Ta); u = vsub(d, vmul(f, dot(d, f)))
    if math.sqrt(dot(u, u)) < 1e-5:
        u = vsub((0, 1, 0), vmul(f, f[1]))
    return f, norm(u)


def set_rolls(keys, edges):
    for j, e in enumerate(edges):
        f, u0 = zero_roll_edge(keys, j)
        e = norm(vsub(e, vmul(f, dot(e, f))))
        keys[j][6] = math.degrees(math.atan2(dot(f, cross(u0, e)), dot(u0, e)))


def write_tables(path, stroke, keys, rk=0.6, lead=1.0, extra=(), note=''):
    flat = []
    for k in keys:
        flat += list(k)
    flat += [0.0] * (NK * NC - len(flat))
    with open(path, 'w') as fh:
        fh.write('# keyframe stroke %d (kfstroke.py %s)\n' % (stroke, note))
        fh.write('# keys: t hx hy hz tx ty roll ea eb\n')
        for k in keys:
            fh.write('#   ' + ' '.join('%.4f' % v for v in k) + '\n')
        fh.write('kf.%d.k1t = %s\n' % (stroke, ' '.join('%.4f' % v for v in flat)))
        fh.write('kfh.%d.n = %d %.3f %.3f\n' % (stroke, len(keys), rk, lead))
        m = 1 << stroke
        for e in extra:
            k_, v_ = e.split('=')
            if k_.strip() in ('kfmask', 'vm.kfmask'):
                m |= int(float(v_))
                continue
            fh.write('%s = %s\n' % (k_.strip(), v_.strip()))
        fh.write('kfmask = %d\n' % m)


def path_err(A, B):
    """max differences between two sampled paths (same steps): tip screen px, grip dm, blade deg, edge deg"""
    dt = dg = db = de = 0.0
    for a, b in zip(A, B):
        ta, tb = px(scr(tip_of(a['rp'], a['rf']))), px(scr(tip_of(b['rp'], b['rf'])))
        if all(map(math.isfinite, ta + tb)):
            dt = max(dt, math.hypot(ta[0] - tb[0], ta[1] - tb[1]))
        dg = max(dg, math.sqrt(dot(vsub(a['rp'], b['rp']), vsub(a['rp'], b['rp']))))
        db = max(db, math.degrees(math.acos(max(-1, min(1, dot(norm(a['rf']), norm(b['rf'])))))))
        de = max(de, math.degrees(math.acos(max(-1, min(1, dot(norm(a['e']), norm(b['e'])))))))
    return dict(tip_px=dt, grip_dm=dg, blade_deg=db, edge_deg=de)


def path_summary(rows, u0=0.28, u1=0.78):
    pts = [px(scr(tip_of(r['p'], r['f']))) for r in rows if u0 <= r['u'] <= u1]
    pts = [p for p in pts if all(map(math.isfinite, p))]
    if len(pts) < 3:
        return {}
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    ang = math.degrees(math.atan2(abs(y1 - y0), abs(x1 - x0)))
    L = math.hypot(x1 - x0, y1 - y0) or 1
    dev = max(abs((p[0] - x0) * (y1 - y0) - (p[1] - y0) * (x1 - x0)) / L for p in pts) / math.hypot(1600, 900)
    trav = L / math.hypot(1600, 900)
    cx, cy = 800, 450
    ctr = abs((cx - x0) * (y1 - y0) - (cy - y0) * (x1 - x0)) / L / math.hypot(1600, 900)
    def band(p):
        x, y = p[0] / 1600, p[1] / 900
        return min(x, 1 - x, y, 1 - y)
    return dict(start=(round(pts[0][0]), round(pts[0][1])), end=(round(pts[-1][0]), round(pts[-1][1])), ang=ang, dev=dev,
                trav=trav, ctr=ctr, start_band=band(pts[0]), end_band=band(pts[-1]))


def cmd_fit(a):
    t0 = time.time()
    src = sample(a.stroke, a.src_set, a.src_tables)
    times = [float(x) for x in a.times.split(',')]
    keys, edges = [], []
    for t in times:
        r = min(src, key=lambda r: abs(r['u'] - t))
        keys.append(key_from_pose(t, r['rp'], r['rf'])); edges.append(r['re'])
    set_rolls(keys, edges)
    extra = list(a.keep_set)
    tmp = tempfile.mkdtemp(prefix='kffit-')
    tf = os.path.join(tmp, 't.txt')

    def err(keys_):
        write_tables(tf, a.stroke, keys_, a.rk, a.lead, extra)
        s = sample(a.stroke, a.keep_set_cli, tf)
        e = path_err(s, src)
        return e, s
    e0, _ = err(keys)
    print('fit: %d keys at %s (sampled) err %s' % (len(keys), a.times, ' '.join('%s=%.2f' % kv for kv in e0.items())))
    if a.opt:
        from optim import minimize
        # free values: per key hx hy hz tx ty roll, per segment ea eb (key times fixed)
        idx = [(j, c) for j in range(len(keys)) for c in (1, 2, 3, 4, 5, 6)] + [(j, c) for j in range(len(keys) - 1) for c in (7, 8)]
        x0 = [keys[j][c] if c < 7 else (1 / 3.0 if c == 7 else 2 / 3.0) for j, c in idx]
        st = [{1: 0.03, 2: 0.03, 3: 0.2, 4: 0.03, 5: 0.03, 6: 4.0, 7: 0.08, 8: 0.08}[c] for j, c in idx]

        def put(x):
            ks = [list(k) for k in keys]
            for (j, c), v in zip(idx, x):
                ks[j][c] = v
            return ks

        def f(x):
            e, _ = err(put(x))
            return e['tip_px'] / 10.0 + e['grip_dm'] + e['blade_deg'] / 5.0 + e['edge_deg'] / 10.0
        r = minimize(f, x0, st, method='nm', maxevals=a.opt, workers=1, log=None)
        keys = put(r.x)
        print('fit: optim %s f=%.3f evals=%d' % (r.reason, r.f, r.evals))
    e1, s1 = err(keys)
    write_tables(a.o, a.stroke, keys, a.rk, a.lead, extra, 'fit of stroke %d %s' % (a.stroke, ' '.join(a.src_set)))
    shutil.rmtree(tmp, ignore_errors=True)
    ps, pk = path_summary(src), path_summary(s1)
    print('fit: wrote %s err %s (%.1f s)' % (a.o, ' '.join('%s=%.2f' % kv for kv in e1.items()), time.time() - t0))
    print('fit: src  path ' + json.dumps(ps, default=lambda x: round(x, 3)))
    print('fit: kf   path ' + json.dumps(pk, default=lambda x: round(x, 3)))


def cmd_make(a):
    keys = []
    for part in a.keys.split(';'):
        v = [float(x) for x in part.split()]
        if not v:
            continue
        v += [0.0] * (NC - len(v))
        keys.append(v[:NC])
    write_tables(a.o, a.stroke, keys, a.rk, a.lead, a.set, 'make')
    s = sample(a.stroke, (), a.o)
    print('make: wrote %s path %s' % (a.o, json.dumps(path_summary(s), default=lambda x: round(x, 3))))


def cmd_path(a):
    s = sample(a.stroke, a.set, a.tables)
    print('path ' + json.dumps(path_summary(s), default=lambda x: round(x, 3)))
    if a.vs_set or a.vs_tables:
        v = sample(a.stroke, a.vs_set, a.vs_tables)
        print('vs   ' + json.dumps(path_summary(v), default=lambda x: round(x, 3)))
        print('diff ' + ' '.join('%s=%.2f' % kv for kv in path_err(s, v).items()))


def cmd_preview(a):
    import kfcheck_strip
    kfcheck_strip.preview(a)


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest='cmd', required=True)
    f = sp.add_parser('fit'); f.add_argument('--stroke', type=int, required=True); f.add_argument('--src-set', action='append', default=[])
    f.add_argument('--src-tables'); f.add_argument('--times', required=True); f.add_argument('-o', required=True)
    f.add_argument('--opt', type=int, default=0); f.add_argument('--rk', type=float, default=0.6); f.add_argument('--lead', type=float, default=1.0)
    f.add_argument('--keep-set', action='append', default=[], help='extra tables lines k=v written into the file (e.g. slmask=1)')
    m = sp.add_parser('make'); m.add_argument('--stroke', type=int, required=True); m.add_argument('--keys', required=True)
    m.add_argument('-o', required=True); m.add_argument('--rk', type=float, default=0.6); m.add_argument('--lead', type=float, default=1.0)
    m.add_argument('--set', action='append', default=[])
    p = sp.add_parser('path'); p.add_argument('--stroke', type=int, required=True); p.add_argument('--tables')
    p.add_argument('--set', action='append', default=[]); p.add_argument('--vs-set', action='append', default=[]); p.add_argument('--vs-tables')
    v = sp.add_parser('preview'); v.add_argument('--stroke', type=int, required=True); v.add_argument('--tables', required=True)
    v.add_argument('-o', required=True); v.add_argument('--trav'); v.add_argument('--every', type=int, default=2)
    v.add_argument('--adapter', default='/root/animlab-build/kfpvm_kf'); v.add_argument('--label', default='')
    a = ap.parse_args()
    if a.cmd == 'fit':
        a.keep_set_cli = []
    sys.path.insert(0, HERE)
    {'fit': cmd_fit, 'make': cmd_make, 'path': cmd_path, 'preview': cmd_preview}[a.cmd](a)


if __name__ == '__main__':
    main()
