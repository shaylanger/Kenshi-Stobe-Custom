#!/usr/bin/env python3
"""live_tune.py: closed-loop pose tuning INSIDE the running game (Shay 2026-10-11: the offline lab disagrees with the game
by 3-5 dm on the sword forearm, so lab-tuned poses failed in game and every fix cost a refilm + review).

Per candidate parameter vector: write a live-tables variant (base = the game's tables at start + the candidate values),
let live-tune.sh --eval load it (`fp_tables load`), holster + draw + swing the forced stroke (input isolation, no focus),
dump `fp_vm rec`, and score the GAME recording with the lab's own metrics (animlab metrics.py / recfmt.py) plus the lab
gate checks (animlab.py inline/metrics/churn/blade --only-stroke) and the in-game PT30 vmcheck (fp-viewmodel.sh copy).
An optimizer (harness optim.py: CMA-ES / Nelder-Mead, early stop at score 0) proposes the next vector. No video.

  live_tune.py tune --out DIR --spec SPEC --eval-cmd "<bash> <live-tune.sh>" [--stroke 1] [--budget 30] [--method cma]
                    [--tools DIR] [--vmcheck FILE] [--confirm 2]
  live_tune.py score <rec> [--stroke 1] [--tools DIR] [--vmcheck FILE]     (offline: score one recording, prints SCORE)
  live_tune.py selftest                                                    (spec parsing + variant writing)

Spec lines (# comments): <lhs> [step|auto] [lo|auto] [hi|auto]   lhs = live-tables key (`wrl`, `swk_alt.s1_k2.ux`).
x0 = the value in the running game (live-tune.sh --get). auto step = max(0.05, 0.15 |x0|); auto bounds = x0 -+ 4 steps.
Score (0 = every gate passes, lower is better):
  s1    10 x sum over solver-posed frames of max(0, 0.02 - edge cos) per 2 swings (edge faces the camera, S1; +1 = away)
  flip  3 x elbow one-frame jumps (step > 0.6 dm and > 2.5 x both neighbours, per 1/30 s)   (PT30-FLIP)
        + 3 x vmcheck flags (PT30 du/df/tipd jumps)
  wb    (wrist bend over the vmcheck limit: 30 held / 50 swing) / 5     (PT17-W)
  roll  (max blade turn per 1/60 s at the stroke start - 12) / 4          (churn sroll step)
  arc   10 x max(0, 0.85 - share of fast stroke frames with edge-arc >= 0.7)   (E1 edge leads the arc)
  gate  1 per failing animlab gate check (inline, metrics, churn --stroke, blade)
  miss  1000 when the recording has no swing of the stroke (input/setup failure, not a pose score)
"""
import argparse, json, math, os, re, shlex, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
DEF_TOOLS = os.path.normpath(os.path.join(HERE, '..', '..', '..', '..', 'Kenshi-Automation-Harness', 'tools', 'animlab'))


def load_lab(tools):
    if tools not in sys.path:
        sys.path.insert(0, tools)
    import recfmt, metrics  # noqa
    return recfmt, metrics


# ---------------------------------------------------------------- scoring (game recording, lab code)
def score_rec(rec, stroke, tools, vmcheck=None, gate=True):
    with open(rec) as f:
        if f.readline().startswith('# dryrun canned'):   # dryrun.sh fake game: no frames; base 1, any candidate 0 (exercises the loop)
            return (1.0 if '-base' in os.path.basename(rec) else 0.0), dict(canned=1)
    recfmt, M = load_lab(tools)
    M.STROKE_ONLY = stroke
    R = recfmt.parse(rec)
    F = R.frames
    if len(F) < 20:
        return 1000.0, dict(miss='frames=%d' % len(F))
    P = M.frame_metrics(R)
    solver = [i for i, p in enumerate(P) if p['wih'] and p['state'] not in M.NATIVE_STATES and p['state'] != 'swing_x']
    sw = [i for i, p in enumerate(P) if p['state'] == 'swing' and p['wih']]
    d = dict(frames=len(P), solver=len(solver), swing=len(sw))
    if len(sw) < 8:
        d['miss'] = 'no stroke-%d swing frames (%d)' % (stroke, len(sw))
        return 1000.0, d
    # S1 (STATUS.md R7, Shay): the edge never faces the camera AT REST (ready/block/swing->block; spec.py restedge, threshold
    # REST_EDGE_P05 = 0). Swing frames are NOT S1: the stroke edge is E1 (arc term below), the follow-through may leave the
    # line (Shay). The 2026-10-11 runs scored swing frames here and chased a non-rule (all their S1 frames were swing u .5-.9).
    rest_states = ('ready', 'block', 'swing->block')
    ed = [(P[i]['edge'], i) for i in solver if P[i]['state'] in rest_states]
    nsw = max(1, len(M.swings(F, P)))   # per-swing (x2) so a 3-cycle confirm compares with a 1-cycle candidate
    d['swings'] = nsw
    s1 = sum(max(0.0, 0.0 - e) for e, _ in ed) * 2.0 / nsw
    if ed:
        d['edge_min'] = '%.3f@%d:%s' % (min(ed)[0], min(ed)[1], P[min(ed)[1]]['state'])
    d['edge_bad'] = sum(1 for e, _ in ed if e < 0.0)
    d['rest_n'] = len(ed)
    swe = [P[i]['edge'] for i in sw]   # diagnostic only (not scored)
    d['swing_edge_min'] = round(min(swe), 3) if swe else None
    # PT30-FLIP: elbow one-frame jumps (scaled to 1/30 s)
    def est(i):
        if i <= 0 or i >= len(P) or max(F[i]['dt'], F[i - 1]['dt']) > 0.07:
            return None
        if not (P[i]['wih'] and P[i - 1]['wih']):
            return None
        s = M.ln(M.sub(P[i]['elb'], P[i - 1]['elb']))
        return s * (1.0 / 30) / max(min(F[i]['dt'], 0.05), 1e-3)
    flips, fmax = [], 0.0
    sset = set(solver)
    for i in solver:
        e = est(i)
        if e is None or (i - 1) not in sset:
            continue
        nb = max([x for x in (est(i - 1), est(i + 1)) if x is not None] or [0.0])
        if e > 0.6 and e > 2.5 * nb:
            flips.append('%d:%.2f/%.2f' % (i, e, nb))
        fmax = max(fmax, e - max(0.6, 2.5 * nb))
    d['elb_jumps'] = len(flips)
    if flips:
        d['elb_at'] = ','.join(flips[:4])
    # wrist bend
    # vmcheck limits: 30 deg held, 50 deg in a swing (WB_MAX / WB_SWING); score = worst excess
    wbx = max((P[i]['wb'] - (50.0 if P[i]['state'] == 'swing' else 30.0) for i in solver if P[i]['wb'] is not None), default=-30.0)
    wbm = 30.0 + wbx
    d['wb_over'] = round(wbx, 1)
    # stroke-start roll step (deg per 1/60 s)
    rmax, rat = 0.0, -1
    for i in sw:
        if i == 0 or (i - 1) not in set(sw):
            continue
        u = F[i].get('swu', 1.0)
        if not (M.ARC_U0 <= u < M.ARC_U0 + M.SROLL_DU) or max(F[i]['dt'], F[i - 1]['dt']) > 0.07:
            continue
        r = M.blade_rot(P[i - 1], P[i]) * (1.0 / 60) / max(min(F[i]['dt'], 0.05), 1e-3)
        if r > rmax:
            rmax, rat = r, i
    d['roll_step'] = '%.1f@%d' % (rmax, rat)
    # edge leads the arc
    arcs = [P[i]['arc'] for i in sw if P[i]['arc'] is not None]
    share = (sum(1 for a in arcs if a >= 0.7) / len(arcs)) if arcs else 1.0
    d['arc_share'] = '%.2f/%d' % (share, len(arcs))
    sc = dict(s1=10 * s1, flip=3 * len(flips) + max(0.0, fmax), wb=max(0.0, wbm - 30) / 5,
              roll=max(0.0, rmax - M.SROLL_STEP) / 4, arc=10 * max(0.0, 0.85 - share), gate=0.0)
    if vmcheck and os.path.isfile(vmcheck):
        try:
            o = subprocess.run([sys.executable, vmcheck, rec, 'swing'], capture_output=True, text=True, timeout=120).stdout.strip().splitlines()
            o = o[-1] if o else ''
            m = re.search(r'flags=(\d+)', o)
            nf = int(m.group(1)) if m else 0
            d['vm_flags'] = nf
            fl = re.search(r'flags=\d+(\[[^\]]*\])?', o)
            if nf:
                d['vm_at'] = fl.group(0)[:80]
            sc['flip'] += 3 * nf
        except Exception as e:   # noqa
            d['vm_err'] = str(e)[:60]
    if gate:
        fails = []
        for c in ('inline', 'metrics', 'churn', 'blade'):
            cmd = [sys.executable, '-I', os.path.join(tools, 'animlab.py'), '--only-stroke', str(stroke), c] + (['--stroke'] if c == 'churn' else []) + [rec]
            try:
                o = subprocess.run(cmd, capture_output=True, text=True, timeout=180).stdout
            except Exception as e:   # noqa
                o = 'ERR %s' % e
            ln = [x for x in o.splitlines() if re.match(r'^(inline|arc|churn|blade) ', x)]
            if not ln or ' PASS' not in ln[0]:
                fails.append('%s:%s' % (c, (ln[0][:70] if ln else o.strip()[-60:]).replace(' ', '_')))
        sc['gate'] = float(len(fails))
        d['gate_fail'] = ';'.join(fails) if fails else '-'
    tot = sum(sc.values())
    d['parts'] = ' '.join('%s=%.2f' % (k, v) for k, v in sc.items() if v)
    return round(tot, 4), d


# ---------------------------------------------------------------- spec + variants
def parse_spec(path):
    out = []
    for line in open(path):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        t = line.split()
        def num(i):
            return None if len(t) <= i or t[i] == 'auto' else float(t[i])
        out.append(dict(lhs=t[0], step=num(1), lo=num(2), hi=num(3)))
    return out


def fill_spec(spec, x0):
    for s, v in zip(spec, x0):
        s['x0'] = v
        if s['step'] is None:
            s['step'] = max(0.05, 0.15 * abs(v))
        if s['lo'] is None:   # a positive scalar stays positive (the game rejects e.g. elbhyst < 0: bad=1)
            s['lo'] = v - 4 * s['step'] if ('.' in s['lhs'] or v <= 0) else max(v - 4 * s['step'], 0.0)
        if s['hi'] is None:
            s['hi'] = v + 4 * s['step']
        s['x0'] = min(max(v, s['lo']), s['hi'])
    return spec


def write_variant(path, base_lines, spec, x, note=''):
    with open(path, 'w') as f:
        f.write('# live_tune variant %s\n' % note)
        for l in base_lines:
            f.write(l if l.endswith('\n') else l + '\n')
        for s, v in zip(spec, x):
            f.write('%s = %.5g\n' % (s['lhs'], v))


def get_val(evalcmd, lhs):
    tb, _, key = lhs.partition('.')
    o = run_eval(evalcmd, ['--get', tb] + ([key] if key else []), 60)
    m = re.search(r'\]\s+(-?[0-9.eE+-]+)', o)
    if not m:
        raise RuntimeError('fp_tables get %s: %s' % (lhs, o.strip()[-160:]))
    return float(m.group(1))


def run_eval(evalcmd, args, timeout):
    p = subprocess.run(shlex.split(evalcmd) + args, capture_output=True, text=True, timeout=timeout)
    return p.stdout + p.stderr


# ---------------------------------------------------------------- tune
def tune(a):
    tools = a.tools
    sys.path.insert(0, tools)
    from optim import minimize
    os.makedirs(a.out, exist_ok=True)
    log = open(os.path.join(a.out, 'score-log.tsv'), 'a')
    log.write('# %s stroke=%d spec=%s\nid\tscore\tx\tdetail\n' % (time.strftime('%F %T'), a.stroke, a.spec))
    spec = parse_spec(a.spec)
    x0 = [get_val(a.eval_cmd, s['lhs']) for s in spec]
    fill_spec(spec, x0)
    json.dump(spec, open(os.path.join(a.out, 'spec-filled.json'), 'w'), indent=1)
    base_lines = []
    bf = os.path.join(a.out, 'base-diff.txt')
    if os.path.isfile(bf):   # the game's non-default values at start (fp_tables dump diff), kept under every candidate
        base_lines = [l for l in open(bf) if l.strip() and not l.startswith('#')]
    lhs = set(s['lhs'] for s in spec)
    base_lines = [l for l in base_lines if l.split('=')[0].strip() not in lhs]
    st = dict(n=0, miss=0, best=(math.inf, None, None), hist=[])

    def ev(x, cycles=None, tag=''):
        st['n'] += 1
        cid = '%03d%s' % (st['n'], tag)
        vf = os.path.join(a.out, 'cand-%s.txt' % cid)
        write_variant(vf, base_lines, spec, x, cid)
        o = run_eval(a.eval_cmd, ['--eval', vf, cid] + ([str(cycles)] if cycles else []), a.eval_timeout)
        m = re.search(r'^EVAL OK hash=(\S+) rec=(.+)$', o, re.M)
        if not m and 'EVAL FAIL load' in o:   # value out of the game's range: a bad point, not a setup failure
            sc, d = 500.0, dict(rejected=(o.strip().splitlines() or [''])[-1][:160])
        elif not m:
            sc, d = 1000.0, dict(miss='eval: ' + (o.strip().splitlines() or ['no output'])[-1][:160])
        else:
            sc, d = score_rec(m.group(2).strip(), a.stroke, tools, a.vmcheck)
            d['hash'] = m.group(1)
        st['miss'] = st['miss'] + 1 if 'miss' in d else 0
        xs = ','.join('%.4g' % v for v in x)
        log.write('%s\t%.4f\t%s\t%s\n' % (cid, sc, xs, ' '.join('%s=%s' % kv for kv in d.items())))
        log.flush()
        print('EVAL %s score=%.3f x=%s %s' % (cid, sc, xs, d.get('miss') or d.get('parts', '') or 'clean'), flush=True)
        st['hist'].append((sc, cid, list(x), d))
        if sc < st['best'][0]:
            st['best'] = (sc, cid, list(x))
        if st['miss'] >= 3:
            raise SystemExit('ABORT %s setup: 3 evaluations in a row had no stroke-%d swing (%s)' % (a.row, a.stroke, d.get('miss')))
        return sc

    base_sc = ev(x0, tag='-base')
    r = None
    if base_sc > 0:
        r = minimize(ev, [s['x0'] for s in spec], [s['step'] for s in spec], method=a.method, target=0.0,
                     maxevals=a.budget, bounds=[(s['lo'], s['hi']) for s in spec], workers=1, round_to=1e-4,
                     log=lambda *q: None)
    # confirm: the 2 best (and base) again with more cycles; winner = best worst-case
    ranked = sorted([h for h in st['hist'] if 'miss' not in h[3] and 'rejected' not in h[3]], key=lambda h: h[0])
    cands, seen = [], set()
    for h in ranked:
        k = tuple(round(v, 4) for v in h[2])
        if k not in seen:
            seen.add(k); cands.append(h)
        if len(cands) >= a.confirm:
            break
    conf = []
    for h in cands:
        sc2 = ev(h[2], cycles=a.confirm_cycles, tag='-conf')
        conf.append((max(h[0], sc2), h[0], sc2, h[2], h[1]))
    conf.sort(key=lambda c: c[0])
    win = conf[0] if conf else None
    res = dict(base_score=base_sc, evals=st['n'], optim=(r.reason if r else 'base already 0'),
               spec=[s['lhs'] for s in spec], x0=[s['x0'] for s in spec])
    if win:
        res.update(win_score=win[0], win_first=win[1], win_confirm=win[2], win_x=win[3], win_id=win[4])
        write_variant(os.path.join(a.out, 'winner.txt'), base_lines, spec, win[3], 'winner %s worst=%.3f' % (win[4], win[0]))
        with open(os.path.join(a.out, 'winner-values.txt'), 'w') as f:
            f.write('# live_tune winner %s score %.3f (base %.3f); only the tuned values\n' % (win[4], win[0], base_sc))
            for s, v in zip(spec, win[3]):
                f.write('%s = %.5g\n' % (s['lhs'], v))
    json.dump(res, open(os.path.join(a.out, 'result.json'), 'w'), indent=1)
    print('TUNE base=%.3f win=%s evals=%d optim=%s' % (base_sc, ('%.3f' % win[0]) if win else 'none', st['n'], res['optim']))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest='cmd')
    p = sp.add_parser('tune')
    p.add_argument('--out', required=True); p.add_argument('--spec', required=True); p.add_argument('--eval-cmd', required=True)
    p.add_argument('--stroke', type=int, default=1); p.add_argument('--budget', type=int, default=30)
    p.add_argument('--method', default='cma'); p.add_argument('--tools', default=DEF_TOOLS); p.add_argument('--vmcheck')
    p.add_argument('--confirm', type=int, default=2); p.add_argument('--confirm-cycles', type=int, default=3)
    p.add_argument('--eval-timeout', type=int, default=150); p.add_argument('--row', default='LIVETUNE')
    p = sp.add_parser('score'); p.add_argument('rec'); p.add_argument('--stroke', type=int, default=1)
    p.add_argument('--tools', default=DEF_TOOLS); p.add_argument('--vmcheck'); p.add_argument('--nogate', action='store_true')
    sp.add_parser('selftest')
    a = ap.parse_args()
    if a.cmd == 'tune':
        return tune(a)
    if a.cmd == 'score':
        sc, d = score_rec(a.rec, a.stroke, a.tools, a.vmcheck, gate=not a.nogate)
        print('SCORE %.3f %s' % (sc, ' '.join('%s=%s' % kv for kv in d.items())))
        return 0
    if a.cmd == 'selftest':
        import tempfile
        td = tempfile.mkdtemp()
        sf = os.path.join(td, 's.txt')
        open(sf, 'w').write('wrl\nswk_alt.s1_k2.ux 0.1 -1 1  # c\n')
        s = fill_spec(parse_spec(sf), [2.2, 0.5])
        assert abs(s[0]['step'] - 0.33) < 1e-9 and s[1]['lo'] == -1 and s[1]['x0'] == 0.5, s
        vf = os.path.join(td, 'v.txt')
        write_variant(vf, ['tau = 0.1\n'], s, [2.0, 0.4])
        t = open(vf).read()
        assert 'wrl = 2' in t and 'swk_alt.s1_k2.ux = 0.4' in t and 'tau = 0.1' in t, t
        print('SELFTEST PASS')
        return 0
    ap.print_help()
    return 2


if __name__ == '__main__':
    sys.exit(main())
