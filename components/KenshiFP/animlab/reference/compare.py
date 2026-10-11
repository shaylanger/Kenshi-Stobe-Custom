#!/usr/bin/env python3
"""compare.py -- KenshiFP live tables vs openly licensed human motion capture (reference, not a source of keys).

Measures every reference clip (sources.tsv, fetched by fetch.sh into its own data dir) with the harness converter
(tools/animlab/mocapref.py), measures the KenshiFP tables (compiled defaults or any fp_tables variant file) the same way
after solving them through the real viewmodel solver (drive adapter), and lists where ours fall outside the human range.

  python3 -I compare.py --data /root/anim-reference --tables defaults.txt --out DIR
         [--adapter /root/animlab-build/kfpvm_drive_ref] [--fist-adapter ...] [--body REC] [--fist-body REC]
  defaults.txt: `kfpvm_tables defaults <file>` (compiled) or `fp_tables dump <file>` from the game (a variant).
Outputs: DIR/results.json (every row + speed curves), DIR/REFERENCE.md (per family: reference p10/median/p90, ours,
verdict), one `REF <family> <metric> ours=.. ref=p10..p90 OK|DEVIATES` line per comparison on stdout.
Run through tools/automation/labnice.sh (offline lab job). Data is parsed, never executed (python3 -I).
"""
import argparse, json, math, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LAB = os.path.normpath(os.path.join(HERE, '../../../../Kenshi-Automation-Harness/tools/animlab'))
sys.path.insert(0, LAB)
import numpy as np
import mocapref as MR
import native as NT
import metricslab as ML

FPS = 60.0
FIST_SETS = ['wroll=0', 'edgeclamp=0', 'wfix=0', 'hroll=0', 'e1inl=0', 'hinge=0', 'elb=0']   # native.py FIST_DEFAULTS


def read_tables(path):
    T = {}
    for line in open(path):
        line = line.split('#')[0].strip()
        if '=' not in line:
            continue
        k, v = line.split('=', 1)
        try:
            T[k.strip()] = [float(x) for x in v.split()]
        except ValueError:
            pass
    return T


def pose(T, key):
    v = T[key]; return (np.array(v[0:3]), np.array(v[3:6]), np.array(v[6:9]))


def sources(path):
    out = []
    for line in open(path):
        if line.startswith('#') or not line.strip():
            continue
        c = line.rstrip('\n').split('\t')
        out.append(dict(family=c[0], clip=c[1], kind=c[2], sides=c[3], note=c[4] if len(c) > 4 else ''))
    return out


# ---------------- ours: keyed path -> solver -> view dict ----------------
def solve(adapter, body, frame, rows, side, extra=()):
    """rows [(t, cls, p, f, u)] -> solved rows (metricslab.parse_solved)."""
    d = tempfile.mkdtemp(prefix='animref-')
    fr, out = os.path.join(d, 'frames.txt'), os.path.join(d, 'solved.txt')
    V = lambda v: '%.5f,%.5f,%.5f' % tuple(v)
    with open(fr, 'w') as f:
        f.write('# t cls p f u o\n')
        for t, cls, p, fw, u in rows:
            f.write('%.5f %d %s %s %s nan,nan,nan\n' % (t, cls, V(p), V(fw), V(u)))
    subprocess.run([adapter, body, fr, out, '--body-frame', str(frame), '--side', side, '--quiet'] + list(extra),
                   check=True, stdout=subprocess.DEVNULL)
    S, _ = ML.parse_solved(out)
    for x in (fr, out):
        os.remove(x)
    os.rmdir(d)
    return S


def view(S, side, n0):
    S = S[n0:]
    g = lambda k: np.array([r[side][k] for r in S])
    return {side + 'sh': g('sh'), side + 'el': g('el'), side + 'wr': g('wr'), side + 'hx': g('hx'), side + 'hand': g('pp'),
            side + 'lat': g('pu')}   # hand-fixed lateral: the prop up/edge axis


def keyed_rows(start, keys, end, ku, dur, cls, pre=0.5, post=0.3):
    rows = []
    n = int(round((pre + dur + post) * FPS))
    for i in range(n):
        t = i / FPS - pre
        u = min(max(t / dur, 0.0), 1.0)
        p, f, uu = NT.keyed_at(start, keys, end, ku, u)
        rows.append((t, cls, p, f, uu))
    return rows, int(round(pre * FPS))


def ours_sword(T, a, L):
    out = []
    ready = pose(T, 'pose.m_ready')
    dur = T['sw_dur'][0]
    ku = T['swk_u'][1:6]
    for s in range(4):
        keys = [pose(T, 'swk.k%d' % k) for k in range(1, 6)] if s == 0 else \
               [pose(T, 'swk_alt.s%d_k%d' % (s, k)) for k in range(1, 6)]
        kus = list(ku)
        ul = T['swk_ul'][s] if s < len(T['swk_ul']) else 0.0
        if ul > 0:
            kus[4] = max(kus[3] + 0.02, min(0.97, ul))
        rows, n0 = keyed_rows(ready, keys, ready, kus, dur, 0)
        S = solve(a.adapter, a.body, a.body_frame, rows, 'R')
        V = view(S, 'R', n0)
        ev, sp = MR.strike_rows(V, None, FPS, 'R', L, 3.0)
        if not ev:
            continue
        r = max(ev, key=lambda e: e['path_dm'])
        r.update(name='stroke%d' % s, keyed_windup=kus[0] * dur, keyed_strike=(kus[3] - kus[0]) * dur,
                 keyed_follow=(1.0 - kus[3]) * dur, sw_dur=dur)
        out.append(r)
    return out


def ours_fists(T, a, L):
    out = []
    techs = sorted({k.split('.')[0][5:] for k in T if k.startswith('fist_') and '.' in k and k.split('.')[0] != 'fist_guard'})
    for tech in techs:
        ku = T.get('fist_%s_u' % tech)
        if not ku:
            continue
        for side in 'LR':
            # kfp_tables.inc names row 0 'L' (KT_RLR / KT_RLRN) but the C arrays hold R first (native.py writes R, L;
            # kfp_viewmodel.inc g_vm_fist_guard comment /* R */): the dump's 'L' rows are the RIGHT hand
            tr = 'L' if side == 'R' else 'R'
            keys = [pose(T, 'fist_%s.%s%d' % (tech, tr, i)) for i in range(len(ku) - 2)]
            g = pose(T, 'fist_guard.' + tr)
            rows, n0 = keyed_rows(g, keys, g, ku[1:-1], 1.0, 0)
            S = solve(a.fist_adapter, a.fist_body, a.body_frame, rows, side, sum([['--set', x] for x in FIST_SETS], []))
            V = view(S, side, n0)
            ev, sp = MR.strike_rows(V, None, FPS, side, L, 1.0)
            if not ev:
                continue
            r = max(ev, key=lambda e: e['path_dm'])
            if r['path_armlen'] < 0.3:   # this hand does not strike in the technique
                continue
            r.update(name='%s.%s' % (tech, side), note='duration = 1 s nominal (fists run on the native clip clock)')
            out.append(r)
    return out


def ours_crossbow(T, a, L):
    out = {}
    for st in ('r_ready', 'r_aim', 'r_reload', 'r_block'):
        p = pose(T, 'pose.' + st)
        rows = [(i / FPS - 0.5, 1, *p) for i in range(int(1.0 * FPS))]
        S = solve(a.adapter, a.body, a.body_frame, rows, 'R')
        r = S[-1]['R']
        sh, el, wr = (np.array(r[k]) for k in ('sh', 'el', 'wr'))
        out[st] = dict(reach=float(np.linalg.norm(wr - sh) / L), elbow=MR.angle(sh - el, wr - el),
                       wrist_eye_arm=float(np.linalg.norm(wr) / L), wrist_vs_shoulder_arm=float((wr[1] - sh[1]) / L))
    tau = T['tau'][0]
    out['raise_s_95'] = 3.0 * tau
    out['fire_kick'] = dict(rise=T['kickrise'][0], ret=T['kickdur'][0], climb_dm=T['kick_p'][1], up=T['kick_up'][0])
    return out


# ---------------- reference ----------------
def measure_ref(src, data, body, fist_body):
    clip = os.path.join(data, src['clip'])
    c = MR.load(clip)
    rows = []
    for side in src['sides']:
        if src['kind'] == 'strike':
            b = dict(body); b['L'] = body[side + 'L']
            ev = MR.strike_metrics(c, side, b, min_peak=3.0 * b['L'])[0]
            for e in ev:
                if e['path_armlen'] >= 0.5:
                    e['side'] = side; rows.append(e)
        elif src['kind'] == 'kick':
            for e in MR.kick_metrics(c, side, body, min_peak=20.0):
                e['side'] = side; rows.append(e)
        elif src['kind'] == 'twohand':
            for e in MR.twohand_metrics(c, body, side, min_peak=3.0 * body['L']):
                if e['path_armlen'] >= 0.5:
                    e['side'] = side; rows.append(e)
        elif src['kind'] == 'hold':
            rows += MR.hold_metrics(c, body, side)
    # capture glitches (CMU marker swaps / hand-twist flips): a wrist faster than 25 arm lengths/s is not a human strike,
    # a forearm roll above 120 deg per 33 ms is a hand-axis flip (the strike stays, its roll is dropped)
    rows = [r for r in rows if r.get('peak_armlen_s', 0) <= 25.0]
    for r in rows:
        if r.get('roll33', 0) > 120.0:
            r['roll33'] = float('nan')
    if src['kind'] == 'strike' and src['family'] in ('fists', 'dualwield'):
        alt = alternation(rows, c.fps)
        if alt:
            rows.append(dict(alternation=alt))
    for r in rows:
        r['clip'] = src['clip']
    return rows


def alternation(rows, fps):
    """dual-wield proxy (boxing): consecutive strikes by opposite hands: interval peak-to-peak, overlap (next starts
    before the previous ends), share of strikes that alternate."""
    ev = sorted((r['t_peak'], r['side'], r['t_top'], r['t_top'] + r['stroke']) for r in rows if 't_peak' in r)
    iv, ov, alt = [], [], 0
    for x, y in zip(ev, ev[1:]):
        if x[1] != y[1]:
            alt += 1
            if y[0] - x[0] < 1.5:
                iv.append(y[0] - x[0]); ov.append(max(0.0, x[3] - y[2]))
    if not iv:
        return None
    return dict(n=len(ev), alt_share=alt / max(1, len(ev) - 1), interval=iv, overlap=ov)


def stat(v):
    v = np.array([x for x in v if x is not None and not (isinstance(x, float) and math.isnan(x))], float)
    if len(v) == 0:
        return None
    return dict(n=int(len(v)), p10=float(np.percentile(v, 10)), med=float(np.median(v)), p90=float(np.percentile(v, 90)),
                lo=float(v.min()), hi=float(v.max()))


# metric -> (tolerance outside p10..p90, unit, description)
TOL = dict(frac_windup=(0.05, '', 'wind-up share of the motion'), frac_stroke=(0.05, '', 'stroke (top -> fast end) share'),
           frac_follow=(0.05, '', 'follow-through/settle share'), total=(0.1, 's', 'whole motion (rest -> settled)'),
           stroke=(0.05, 's', 'stroke duration top -> end of the fast part'), windup=(0.05, 's', 'wind-up duration'),
           peak_armlen_s=(0.5, 'arm/s', 'peak wrist speed'), path_armlen=(0.15, 'arm', 'wrist path in the stroke'),
           elbow_top=(10.0, 'deg', 'elbow angle at the top'), elbow_min=(10.0, 'deg', 'smallest elbow angle in the stroke'),
           elbow_end=(10.0, 'deg', 'elbow angle at the end of the stroke'), reach_end=(0.08, 'arm', 'shoulder-wrist at the end'),
           wb_max_stroke=(10.0, 'deg', 'max wrist bend in the stroke'), wshare=(0.05, '', 'wrist share of hand motion (U10)'),
           roll33=(5.0, 'deg/33ms', 'max forearm-roll rate'), torso_share=(0.1, '', 'share of wrist travel from torso turn'),
           chest_yaw_deg=(10.0, 'deg', 'chest yaw in the stroke'), elbow_ext=(10.0, 'deg', 'elbow opening in the stroke (end - min)'),
           wb_start=(10.0, 'deg', 'wrist bend at the start (rest/guard)'), wb_delta=(10.0, 'deg', 'wrist bend added in the stroke'), guard_out_x=(1.0, 'dm', 'start wrist x, outward +'),
           guard_y=(1.0, 'dm', 'start wrist height (eye = 0)'), guard_z=(1.0, 'dm', 'start wrist depth'))


def compare_family(fam, ref_rows, ours, keys, out_lines, md):
    md.append('\n### %s\n' % fam)
    md.append('| metric | unit | reference p10 / median / p90 (n) | ours | verdict |')
    md.append('|---|---|---|---|---|')
    dev = []
    for k in keys:
        s = stat([r.get(k) for r in ref_rows if k in r])
        if s is None:
            continue
        tol, unit, desc = TOL.get(k, (0.0, '', k))
        ov = [o.get(k) for o in ours if o.get(k) is not None]
        bad = [(o['name'], o[k]) for o in ours if o.get(k) is not None and not (s['p10'] - tol <= o[k] <= s['p90'] + tol)]
        verdict = 'DEVIATES ' + ', '.join('%s %.2f' % b for b in bad) if bad else ('OK' if ov else 'n/a (no FP motion)')
        if bad:
            dev.append((k, desc, bad, s))
        md.append('| %s (%s) | %s | %.2f / %.2f / %.2f (%d) | %s | %s |' % (k, desc, unit, s['p10'], s['med'], s['p90'], s['n'],
                  ' '.join('%.2f' % x for x in ov) or '-', verdict))
        out_lines.append('REF %s %s ours=%s ref=%.2f..%.2f %s' % (fam, k, ','.join('%.2f' % x for x in ov) or '-', s['p10'], s['p90'],
                         'DEVIATES' if bad else 'OK' if ov else 'n/a'))
    return dev


def mean_curve(rows):
    C = [r['curve'] for r in rows if 'curve' in r]
    return np.mean(np.array(C), axis=0).round(3).tolist() if C else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True); ap.add_argument('--tables', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--sources', default=os.path.join(HERE, 'sources.tsv'))
    ap.add_argument('--adapter', default='/root/animlab-build/kfpvm_drive_ref')
    ap.add_argument('--fist-adapter', default='/root/animlab-build/kfpvm_drive_fistl1')
    ap.add_argument('--body', default='/root/animlab-work/vmrec-q-sword-z0-a.txt')
    ap.add_argument('--fist-body', default='/root/animlab-work/vmrec-fist-z0-a.txt')
    ap.add_argument('--body-frame', type=int, default=100)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    T = read_tables(a.tables)
    body = MR.body_from_rec(a.body, a.body_frame)
    fbody = MR.body_from_rec(a.fist_body, a.body_frame)
    L = body['L']
    ref = {}
    for src in sources(a.sources):
        try:
            rows = measure_ref(src, a.data, body if src['family'] not in ('fists', 'dualwield') else fbody, fbody)
        except FileNotFoundError:
            print('missing %s (run fetch.sh)' % src['clip']); continue
        ref.setdefault(src['family'], []).extend(rows)
    ours = dict(sword=ours_sword(T, a, L), fists=ours_fists(T, a, fbody['L']), crossbow=ours_crossbow(T, a, L))
    lines, md, dev = [], [], {}
    SK = ['frac_windup', 'frac_stroke', 'frac_follow', 'total', 'windup', 'stroke', 'peak_armlen_s', 'path_armlen', 'elbow_top',
          'elbow_min', 'elbow_end', 'elbow_ext', 'reach_end', 'wb_start', 'wb_max_stroke', 'wb_delta', 'wshare', 'roll33', 'torso_share', 'chest_yaw_deg']
    dev['sword'] = compare_family('sword', [r for r in ref.get('sword', []) if 'curve' in r], ours['sword'], SK, lines, md)
    FK = [k for k in SK if k not in ('total', 'windup', 'stroke', 'peak_armlen_s')] + ['guard_out_x', 'guard_y', 'guard_z']
    dev['fists'] = compare_family('fists', [r for r in ref.get('fists', []) if 'curve' in r], ours['fists'], FK, lines, md)
    dev['twohand'] = compare_family('twohand', [r for r in ref.get('twohand', []) if 'curve' in r], ours['sword'],
                                    ['frac_windup', 'frac_stroke', 'total', 'stroke', 'peak_armlen_s', 'path_armlen', 'elbow_min',
                                     'torso_share'], lines, md)
    th = ref.get('twohand', [])
    s2 = {k: stat([r.get(k) for r in th]) for k in ('hands_dm_top', 'hands_dm_end', 'hands_dm_med')}
    md.append('\nTwo-hand spacing (FP dm, wrist to wrist): ' + ', '.join('%s %.1f / %.1f / %.1f' % (k, v['p10'], v['med'], v['p90'])
              for k, v in s2.items() if v) + ' (KenshiFP R25: heavy 0.5-3.5 dm, polearm 3-7.5 dm; native guard6 2.3)')
    # crossbow / aim holds
    H = ref.get('crossbow', [])
    md.append('\n### crossbow / aim (holds)\n')
    md.append('| metric | reference p10 / median / p90 (n) | ours (r_aim) | verdict |'); md.append('|---|---|---|---|')
    ca = ours['crossbow']['r_aim']
    for k, ok, tol in (('rear_elbow', ca['elbow'], 10.0), ('rear_head_arm', ca['wrist_eye_arm'], 0.08)):
        s = stat([r[k] for r in H if r.get('front_reach', 0) < 1.2])   # rifle-style holds (bow draws are wider)
        if s:
            v = 'OK' if s['p10'] - tol <= ok <= s['p90'] + tol else 'DEVIATES'
            md.append('| %s | %.2f / %.2f / %.2f (%d) | %.2f | %s |' % (k, s['p10'], s['med'], s['p90'], s['n'], ok, v))
            lines.append('REF crossbow %s ours=%.2f ref=%.2f..%.2f %s' % (k, ok, s['p10'], s['p90'], v))
            if v == 'DEVIATES':
                dev.setdefault('crossbow', []).append((k, k, [('r_aim', ok)], s))
    s = stat([r['raise_s'] for r in H])
    if s:
        md.append('| raise_s (rest -> aim held) | %.2f / %.2f / %.2f (%d) | %.2f (3 x tau) | %s |' % (
            s['p10'], s['med'], s['p90'], s['n'], ours['crossbow']['raise_s_95'], 'faster than every reference raise'
            if ours['crossbow']['raise_s_95'] < s['lo'] else 'OK'))
    s = stat([max(r['jitter_mm'].values()) for r in H])
    if s:
        md.append('| aim jitter rms (mm, worst wrist) | %.1f / %.1f / %.1f (%d) | (R12: still poses must not shake) | info |' % (
            s['p10'], s['med'], s['p90'], s['n']))
    # kicks
    K = ref.get('kicks', [])
    md.append('\n### kicks (no FP kick yet: reference for U14)\n')
    for k in ('chamber', 'extend', 'retract', 'total', 'toe_height_leg', 'head_travel_dm', 'head_drop_dm', 'head_back_dm'):
        s = stat([r.get(k) for r in K])
        if s:
            md.append('- %s: %.2f / %.2f / %.2f (n %d)' % (k, s['p10'], s['med'], s['p90'], s['n']))
    s = stat([max(r['wrist_travel_dm'].values()) for r in K])
    if s:
        md.append('- wrist travel vs the chest (FP dm, larger hand): %.1f / %.1f / %.1f (native U14: 6.4-9.5 dm)' % (s['p10'], s['med'], s['p90']))
    # dual-wield proxy
    alts = [r['alternation'] for fam in ('fists', 'dualwield') for r in ref.get(fam, []) if 'alternation' in r]
    iv = stat(sum([x['interval'] for x in alts], [])); ovl = stat(sum([x['overlap'] for x in alts], []))
    md.append('\n### dual-wield proxy (alternating L/R strikes, boxing)\n')
    if iv:
        md.append('- interval between alternating strikes (peak to peak, s): %.2f / %.2f / %.2f (n %d); motions/dualwield-alternate.json: 0.85'
                  % (iv['p10'], iv['med'], iv['p90'], iv['n']))
    if ovl:
        md.append('- overlap (next stroke starts before the previous ends, s): %.2f / %.2f / %.2f' % (ovl['p10'], ovl['med'], ovl['p90']))
    curves = {f: mean_curve(ref.get(f, [])) for f in ('sword', 'fists', 'twohand')}
    curves['ours_sword'] = mean_curve(ours['sword']); curves['ours_fists'] = mean_curve(ours['fists'])
    md.append('\n### speed curves (wrist speed / peak, 21 samples rest -> settled)\n')
    for k, v in curves.items():
        if v:
            md.append('- %s: %s' % (k, ' '.join('%.2f' % x for x in v)))
    with open(os.path.join(a.out, 'results.json'), 'w') as f:
        json.dump(dict(ref=ref, ours=ours, curves=curves,
                       deviations={k: [(m, d, b, s) for m, d, b, s in v] for k, v in dev.items()}), f, indent=1, default=float)
    with open(os.path.join(a.out, 'REFERENCE.md'), 'w') as f:
        f.write('# KenshiFP tables vs human motion capture (generated by compare.py; tables %s)\n' % os.path.basename(a.tables))
        f.write('\n'.join(md) + '\n')
    print('\n'.join(lines))
    nd = sum(len(v) for v in dev.values())
    print('RESULT animref %s deviations=%d (%s) out=%s' % ('PASS' if nd == 0 else 'INFO', nd,
          ' '.join('%s:%d' % (k, len(v)) for k, v in dev.items() if v), a.out))
    return 0


if __name__ == '__main__':
    sys.exit(main())
