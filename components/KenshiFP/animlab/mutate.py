#!/usr/bin/env python3
"""mutate.py -- mutation tests for the animation lab's checks (run by gate.sh on every build; WSL).

Every mutation takes known-good corpus material (the target check PASSES on it), injects one synthetic flaw and runs
the check(s) that should catch it: the check must PASS the base and FAIL the mutant. A check that misses its own
mutation is a lab bug: it is reported as MISSED (gate FAIL) unless the mutation is listed in the corpus file
mutations-known.tsv (id <TAB> Misses row date <TAB> note) = a known lab gap with a Misses row (reported KNOWN, gate
passes; a KNOWN mutation that is now caught is reported FIXED: delete its line).
Exploratory mutations (no designated check: `checks` = every check of that material) are caught when ANY check FAILs.

Recordings (fp_vm rec dump, recfmt.py): group 0 `n t dt st ti cls on w swing swu ...`, group 1 `out_p out_f out_u oc
mp mf mu Lsh Lel Lwr Rsh Rel Rwr` (camera numbers: x right, y up, z forward), group 4 `wb ...`.
Usage: mutate.py --work <dir with the corpus synced (gate.sh work dir)> [--out DIR] [--only id,id] [-v]
Prints one `MUT <id> CAUGHT|MISSED|KNOWN|FIXED|BASEFAIL <check> <detail>` line per mutation and
`RESULT MUTATIONS PASS|FAIL <caught>/<n> missed=<ids> known=<ids>`.
"""
import argparse, math, os, shutil, subprocess, sys

L = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab'
CORPUS = os.environ.get('ANIMLAB_CORPUS', '/mnt/c/KenshiTestRuns/corpus')
RULES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'take-rules.txt')


# ---------------- recording edits ----------------
def read_rec(p):
    return open(p).read().split('\n')


def frames(lines):
    """yield (line index, groups list, g0 tokens) for data lines"""
    for i, l in enumerate(lines):
        if not l.strip() or l.startswith('#'):
            continue
        g = l.split(' | ')
        yield i, g, g[0].split()


def setvec(g, gi, k, v):
    t = g[gi].split(); t[k] = '%.4f,%.4f,%.4f' % v; g[gi] = ' '.join(t)


def getvec(g, gi, k):
    return tuple(float(x) for x in g[gi].split()[k].split(','))


def rot(v, axis, deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a); x, y, z = axis
    d = v[0] * x + v[1] * y + v[2] * z
    cr = (y * v[2] - z * v[1], z * v[0] - x * v[2], x * v[1] - y * v[0])
    return tuple(v[i] * c + cr[i] * s + (x, y, z)[i] * d * (1 - c) for i in range(3))


MP, MF, MU = 4, 5, 6   # group 1 indices (measured grip pos / blade forward / edge up)


def stroke_of(g):
    for x in g:
        t = x.split()
        if t and t[0] == 'H' and len(t) > 3: return t[3]
    return None


def swing_frames(lines, lo, hi, stroke='1'):
    """frames of the FIRST swing of the given E6 stroke (None = any) with swu in [lo, hi]"""
    out, sw = [], None
    for i, g, t in frames(lines):
        if len(t) > 9 and t[3].startswith('swing') and lo <= float(t[9]) <= hi and (stroke is None or stroke_of(g) == stroke):
            if sw is None: sw = t[8]
            if t[8] == sw: out.append(i)
    return out


def m_wrist(lines):        # wrist bend over the limit through one swing's stroke
    sw = None
    for i, g, t in frames(lines):
        if len(t) > 9 and t[3].startswith('swing') and 0.3 <= float(t[9]) <= 0.9:
            if sw is None: sw = t[8]
            if t[8] != sw: continue
            g4 = g[4].split(); g4[0] = '80.0'; g[4] = ' '.join(g4); lines[i] = ' | '.join(g)
    return lines


def m_hanging(lines):      # blade hanging straight down in every block frame (Kenshi's native hanging guard)
    for i, g, t in frames(lines):
        if len(t) > 4 and t[4] == '3':
            for k, v in ((0 + 1, (0.0, -1.0, 0.0)), (MF, (0.0, -1.0, 0.0)), (MU, (0.0, 0.0, 1.0))):
                setvec(g, 1, k, v)
            lines[i] = ' | '.join(g)
    return lines


def m_endon(lines):        # one stroke frame with the blade pointing straight into the scene (hairline)
    idx = swing_frames(lines, 0.62, 0.75)
    if idx:
        i = idx[len(idx) // 2]; g = lines[i].split(' | ')
        setvec(g, 1, MF, (0.0, 0.0, 1.0)); setvec(g, 1, MU, (0.0, 1.0, 0.0)); lines[i] = ' | '.join(g)
    return lines


def m_snap(lines):         # one-frame 45 deg blade roll mid-stroke (wind-up snap / flick)
    idx = swing_frames(lines, 0.45, 0.60)
    if idx:
        i = idx[len(idx) // 2]; g = lines[i].split(' | ')
        f = getvec(g, 1, MF); u = getvec(g, 1, MU)
        setvec(g, 1, MF, rot(f, (0.0, 0.0, 1.0), 45)); setvec(g, 1, MU, rot(u, (0.0, 0.0, 1.0), 45)); lines[i] = ' | '.join(g)
    return lines


def m_jump(lines):         # one-frame 1.5 dm jump of weapon + right arm in ready (exploratory)
    rd = [i for i, g, t in frames(lines) if len(t) > 3 and t[3] == 'ready']
    if rd:
        i = rd[len(rd) // 2]; g = lines[i].split(' | ')
        for k in (0, MP, 10, 11, 12):
            p = getvec(g, 1, k); setvec(g, 1, k, (p[0] + 1.5, p[1], p[2]))
        lines[i] = ' | '.join(g)
    return lines


# ---------------- video / take edits ----------------
ARROW = '/tmp/al-mut-arrow.png'


def arrow_png():
    if os.path.exists(ARROW): return
    from PIL import Image, ImageDraw
    im = Image.new('RGBA', (24, 36), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    pts = [(1, 1), (1, 28), (8, 21), (13, 33), (17, 31), (12, 20), (21, 20)]
    d.polygon(pts, fill=(255, 255, 255, 255), outline=(0, 0, 0, 255)); im.save(ARROW)


def ff(args):
    subprocess.run(['ffmpeg', '-v', 'error', '-y'] + args, check=True)


def v_cursor(src, dst):
    arrow_png()
    ff(['-i', src, '-i', ARROW, '-filter_complex', "[0][1]overlay=820:430:enable='between(t,3,6)'", '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def v_dark(src, dst):
    ff(['-i', src, '-vf', 'eq=brightness=-0.45:saturation=0.4,colorchannelmixer=rr=0.3:gg=0.3:bb=0.45', '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def v_black(src, dst):
    ff(['-i', src, '-vf', "drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill:enable='between(t,2,6)'", '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def v_popup(src, dst):
    ff(['-i', src, '-vf', "drawbox=x=iw*0.3:y=ih*0.3:w=iw*0.4:h=ih*0.35:color=0x404040:t=fill:enable='between(t,2,8)',"
        "drawbox=x=iw*0.3:y=ih*0.3:w=iw*0.4:h=ih*0.05:color=0xc8c8c8:t=fill:enable='between(t,2,8)'", '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def t_label(d):     # label says block guard while the game shows the katana ready
    p = os.path.join(d, 'labels.txt'); s = open(p).read(); open(p, 'w').write(s.replace('Katana ready, zoom 0', 'Block guard (RMB held: block)', 1))


def t_end(d):       # video runs 6 s past the end label
    p = os.path.join(d, 'video-len.txt'); v = float(open(p).read().split()[0]); open(p, 'w').write('%.2f\n' % (v + 6))


def t_near(d):      # a bystander walks into the take
    open(os.path.join(d, 'ev.txt'), 'a').write('12.00 world near=1 nearest=Hungry_Bandit down=0 msgs=0\n')


def t_msgs(d):      # combat message during the take
    open(os.path.join(d, 'ev.txt'), 'a').write('12.00 world near=0 nearest=none down=0 msgs=1\n')


# ---------------- checks ----------------
def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return r.stdout


def al(*a):
    return ['python3', os.path.join(L, 'animlab.py')] + list(a)


def chk_line(prefix):
    def f(out):
        for l in out.splitlines():
            if l.startswith(prefix): return ('FAIL' if ' FAIL' in l.split(':')[0] or l.startswith(prefix + 'FAIL') else 'PASS'), l
        return 'NONE', out.strip().splitlines()[-1] if out.strip() else ''
    return f


def verdict_word(out, first):
    for l in out.splitlines():
        if l.startswith(first):
            return ('FAIL' if 'FAIL' in l.split()[:3] else 'PASS'), l
    return 'NONE', (out.strip().splitlines() or [''])[-1]


REC_CHECKS = {
    'arc': lambda p: verdict_word(run(al('metrics', p)), 'arc '),
    'guard': lambda p: verdict_word(run(al('guard', p)), 'guard '),
    'blade1': lambda p: verdict_word(run(al('--only-stroke', '1', 'blade', p)), 'blade '),
    'churn': lambda p: verdict_word(run(al('churn', p)), 'churn '),
    'churn-stroke1': lambda p: verdict_word(run(al('--only-stroke', '1', 'churn', '--stroke', p)), 'churn '),
    'stroke': lambda p: verdict_word(run(al('stroke', '--overhead', '2', p)), 'stroke '),
    'metrics-any': lambda p: (('FAIL' if any(' FAIL' in l[:40] for l in run(al('metrics', p)).splitlines()) else 'PASS'), 'metrics'),
}
VID_CHECKS = {
    'cursor': lambda p: verdict_word(run(['python3', os.path.join(L, 'frames.py'), 'cursor', p, '--name', 'mut']), 'RESULT '),
    'openground': lambda p: verdict_word(run(['python3', os.path.join(L, 'frames.py'), 'openground', p, '--name', 'mut']), 'RESULT '),
}


def take_check(d):
    vl = open(os.path.join(d, 'video-len.txt')).read().split()[0]
    return verdict_word(run(['python3', os.path.join(L, 'takecheck.py'), '--labels', os.path.join(d, 'labels.txt'), '--ev',
                             os.path.join(d, 'ev.txt'), '--rules', RULES, '--video-len', vl, '--name', 'mut']), 'RESULT ')


# id, kind, base (relative to the work dir), edit, checks (designated; 'ALL' = exploratory over every check of the kind)
MUTS = [
    ('rec-wrist-over-limit', 'rec', 'f23-sword-z0d.txt', m_wrist, ['arc']),
    ('rec-hanging-blade', 'rec', 'f28-sword-z0c.txt', m_hanging, ['guard']),
    ('rec-endon-blade-frame', 'rec', 'e6-anim-b2.txt', m_endon, ['blade1']),
    ('rec-one-frame-snap', 'rec', 'e6-anim-b2.txt', m_snap, ['blade1', 'churn-stroke1']),
    ('rec-one-frame-jump', 'rec', 'f28-sword-z0c.txt', m_jump, 'ALL'),
    ('vid-cursor-overlay', 'vid', 'takes/videos/anim-sword-e6.mp4', v_cursor, ['cursor']),
    ('vid-dark-night', 'vid', 'takes/videos/anim-sword-e6.mp4', v_dark, ['openground']),
    ('vid-black-frames', 'vid', 'takes/videos/anim-sword-e6.mp4', v_black, 'ALL'),
    ('vid-popup-overlay', 'vid', 'takes/videos/anim-sword-e6.mp4', v_popup, 'ALL'),
    ('take-label-state-mismatch', 'take', 'takes/ok-e6fix', t_label, ['takecheck']),
    ('take-video-past-end', 'take', 'takes/ok-e6fix', t_end, ['takecheck']),
    ('take-bystander', 'take', 'takes/ok-e6fix', t_near, ['takecheck']),
    ('take-combat-message', 'take', 'takes/ok-e6fix', t_msgs, ['takecheck']),
]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--work', required=True); ap.add_argument('--out', default='/tmp/al-mut')
    ap.add_argument('--only'); ap.add_argument('-v', action='store_true'); a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    known = {}
    kp = os.path.join(CORPUS, 'mutations-known.tsv')
    if os.path.exists(kp):
        for l in open(kp):
            if l.strip() and not l.startswith('#'): known[l.split('\t')[0].strip()] = l.strip()
    only = set(a.only.split(',')) if a.only else None
    res = {}
    for mid, kind, base, edit, checks in MUTS:
        if only and mid not in only: continue
        src = os.path.join(a.work, base)
        if not os.path.exists(src):
            res[mid] = 'BASEFAIL'; print('MUT %s BASEFAIL - base %s missing' % (mid, base)); continue
        if kind == 'rec':
            pool = REC_CHECKS; dst = os.path.join(a.out, mid + '.txt')
            open(dst, 'w').write('\n'.join(edit(read_rec(src))))
            names = list(pool) if checks == 'ALL' else checks
            runc = lambda n, p: pool[n](p)
        elif kind == 'vid':
            pool = VID_CHECKS; dst = os.path.join(a.out, mid + '.mp4'); edit(src, dst)
            names = list(pool) if checks == 'ALL' else checks
            runc = lambda n, p: pool[n](p)
        else:
            dst = os.path.join(a.out, mid); shutil.rmtree(dst, ignore_errors=True); shutil.copytree(src, dst); edit(dst)
            names = checks; runc = lambda n, p: take_check(p)
        caught, base_bad, det = [], [], []
        for n in names:
            bv, bl = runc(n, src)
            if bv != 'PASS':
                base_bad.append(n); det.append('%s base=%s' % (n, bv)); continue
            mv, ml = runc(n, dst)
            det.append('%s=%s' % (n, mv))
            if mv == 'FAIL': caught.append(n)
            if a.v: print('   %s %s: base %s | mutant %s' % (mid, n, bl[:110], ml[:160]))
        if len(base_bad) == len(names): st = 'BASEFAIL'
        elif caught: st = 'FIXED' if mid in known else 'CAUGHT'
        else: st = 'KNOWN' if mid in known else 'MISSED'
        res[mid] = st
        print('MUT %s %s %s %s' % (mid, st, ','.join(caught) or ('/'.join(names) if checks != 'ALL' else 'any'), ' '.join(det)))
    n = len(res); c = sum(1 for v in res.values() if v in ('CAUGHT', 'FIXED'))
    missed = [k for k, v in res.items() if v in ('MISSED', 'BASEFAIL')]; kn = [k for k, v in res.items() if v == 'KNOWN']
    print('RESULT MUTATIONS %s %d/%d missed=%s known=%s' % ('PASS' if not missed else 'FAIL', c, n, ','.join(missed) or 'none', ','.join(kn) or 'none'))
    return 0 if not missed else 1


if __name__ == '__main__':
    sys.exit(main())
