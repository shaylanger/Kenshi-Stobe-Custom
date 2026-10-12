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
import argparse, json, math, os, shutil, subprocess, sys

L = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab'
CORPUS = os.environ.get('ANIMLAB_CORPUS', '/mnt/c/KenshiTestRuns/corpus')
FTC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fist-take-check.py')
FPC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fist-punch-check.py')
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


def m_s3_windup_off(lines):   # E6 stroke 3 wind-up: blade turned 25 deg off the forearm line (in their plane) in every wind-up frame of the first stroke-3 swing
    for i in swing_frames(lines, 0.0, 0.29, stroke='3'):
        g = lines[i].split(' | ')
        el, wr, f, u = getvec(g, 1, 11), getvec(g, 1, 12), getvec(g, 1, MF), getvec(g, 1, MU)
        fa = tuple(wr[k] - el[k] for k in range(3))
        ax = (fa[1] * f[2] - fa[2] * f[1], fa[2] * f[0] - fa[0] * f[2], fa[0] * f[1] - fa[1] * f[0])
        n = math.sqrt(sum(x * x for x in ax))
        if n < 1e-6: continue
        ax = tuple(x / n for x in ax)
        setvec(g, 1, MF, rot(f, ax, 25.0)); setvec(g, 1, MU, rot(u, ax, 25.0)); lines[i] = ' | '.join(g)
    return lines


def m_path_drift(lines):   # PT17 "/|": in the last part of every stroke-1 swing (u .58-.78) the blade slides sideways without rotating, ramping to 30 % of the path extent perpendicular to the stroke
    W, H, TX, TY = 1600.0, 900.0, 1.245, 0.70
    scr = lambda g: (lambda c: (W / 2 + W / 2 * (c[0] / c[2]) / TX, H / 2 - H / 2 * (c[1] / c[2]) / TY))(
        tuple(getvec(g, 1, MP)[k] + 8.0 * getvec(g, 1, MF)[k] for k in range(3)))
    sw, cur = [], None
    for i, g, t in frames(lines):   # every stroke-1 swing (by swing counter t[8])
        if len(t) > 9 and t[3].startswith('swing') and stroke_of(g) == '1' and 0.28 <= float(t[9]) <= 0.78:
            if cur is None or cur[0] != t[8]:
                cur = (t[8], []); sw.append(cur)
            cur[1].append((i, float(t[9])))
    for _, fr in sw:
        a, b = scr(lines[fr[0][0]].split(' | ')), scr(lines[fr[-1][0]].split(' | '))
        dx, dy = b[0] - a[0], b[1] - a[1]; n = math.hypot(dx, dy) or 1.0
        px, py = -dy / n * 0.30 * n, dx / n * 0.30 * n   # perpendicular, px at full ramp
        for i, u in fr:
            r = min(1.0, max(0.0, (u - 0.58) / 0.20))
            if r <= 0: continue
            g = lines[i].split(' | '); mp = getvec(g, 1, MP); z = mp[2] + 8.0 * getvec(g, 1, MF)[2]
            setvec(g, 1, MP, (mp[0] + r * px / (W / 2) * TX * z, mp[1] - r * py / (H / 2) * TY * z, mp[2])); lines[i] = ' | '.join(g)
    return lines



def m_windup_popin(lines):   # Shay 17:25 "no pop-in": the first stroke-3 swing's wind-up frames (u < .28) show the stroke-start pose (blade off screen) -> the blade jumps out of mid-screen in one frame instead of being carried off
    wind = swing_frames(lines, 0.0, 0.279, stroke='3')
    st = swing_frames(lines, 0.28, 0.40, stroke='3')
    assert wind and st, 'm_windup_popin: no stroke-3 swing'
    src = lines[st[0]].split(' | ')
    for i in wind:
        g = lines[i].split(' | ')
        for k in (MP, MF, MU):
            setvec(g, 1, k, getvec(src, 1, k))
        lines[i] = ' | '.join(g)
    return lines


def m_sweep_frozen(lines):   # Shay 17:05 minimum angular sweep: the first stroke-1 swing's blade keeps one direction through the stroke (u .28-.78; grip path unchanged) -> the tip slides, the blade does not turn
    fr = swing_frames(lines, 0.25, 0.85, stroke='1')   # P[i] shows frame i+1's pose: cover one frame either side
    assert fr, 'm_sweep_frozen: no stroke-1 swing'
    src = lines[fr[len(fr) // 2]].split(' | ')
    for i in fr:
        g = lines[i].split(' | ')
        setvec(g, 1, MF, getvec(src, 1, MF)); setvec(g, 1, MU, getvec(src, 1, MU))
        lines[i] = ' | '.join(g)
    return lines

# ---------------- source edits (kind 'src': base = a corpus source snapshot tarball, edit(client dir)) ----------------
def s_2hl_stroke0(d):   # E6 default stroke cycle: the light-2H class drops out of the cycle (kfp-e6-default-mask v1 + kfp-2h-light = 6E7C0363)
    p = os.path.join(d, 'kfp_viewmodel.inc'); t = open(p).read()
    old = 'g_vm_2h && !g_vm_2hl && g_vm_stroke_force < 0'
    assert t.count(old) == 1, 's_2hl_stroke0: anchor'
    open(p, 'w').write(t.replace(old, 'g_vm_2h && g_vm_stroke_force < 0'))


# ---------------- video / take edits ----------------
ARROW = '/tmp/al-mut-arrow.png'


def m_cross_unseen(lines):   # SR17 framed swing: every swing's stroke proper (u .28-.58) carried out of view (grip, wrists, elbows 30 dm below the camera, blade pointing back): the mid-stroke crossing is never seen
    for i, g, t in frames(lines):
        if len(t) > 9 and t[3].startswith('swing') and 0.26 <= float(t[9]) <= 0.60:
            for k in (MP, 8, 9, 11, 12):
                p = getvec(g, 1, k); setvec(g, 1, k, (p[0], p[1] - 30.0, p[2]))
            setvec(g, 1, MF, (0.0, -0.2, -0.98)); lines[i] = ' | '.join(g)
    return lines


def m_fist_hand(lines):     # U25: the right hand flips 90 deg (rec group F axes) for 0.25 s mid-take, wrist in place
    fr = [(i, g, t) for i, g, t in frames(lines) if any(x.split()[:1] == ['F'] for x in g)]
    t0 = float(fr[len(fr) // 2][2][1])
    for i, g, t in fr:
        if t0 <= float(t[1]) <= t0 + 0.25:
            k = [j for j, x in enumerate(g) if x.split()[:1] == ['F']][0]
            tk = g[k].split()
            for c in (3, 4):
                tk[c] = '%.4f,%.4f,%.4f' % rot(tuple(float(v) for v in tk[c].split(',')), (1.0, 0.0, 0.0), 90.0)
            g[k] = ' '.join(tk)
            lines[i] = ' | '.join(g)
    return lines


# ---- fist "punch reads" (fist-punch-check.py C1-C9, Misses 2026-10-11 "fist punch read" NA1); base = the synthetic PASS
#      rec/fist-punch-synth-pass-v3.txt (fist-punch-synth.py from fq0) until a game take passes
def _punch_peaks(lines):
    import tempfile
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as f:
        f.write('\n'.join(lines)); p = f.name
    out = run(['python3', FPC, p, '--peaks']); os.unlink(p)
    return [(l.split()[1], float(l.split()[2]), float(l.split()[3]), tuple(float(x) for x in l.split()[4].split(',')))
            for l in out.splitlines() if l.startswith('PEAK ')]


def _paired(lines):
    """(line index, groups, time of the frame its measured joints show = the previous record's clock)"""
    prev = None
    for i, g, t in frames(lines):
        tr = float(t[1]); yield i, g, (prev if prev is not None else tr); prev = tr


WRI = {'L': 9, 'R': 12}; SHI = {'L': 7, 'R': 10}


def m_punch_small(lines):     # C1-C3: every punch's striking-wrist excursion from the guard scaled x0.3 (fq0's "moved a little bit")
    for s, tp, t20, g in _punch_peaks(lines):
        for i, gr, t in list(_paired(lines)):
            if t20 - .3 <= t <= tp + .4:
                w = getvec(gr, 1, WRI[s]); setvec(gr, 1, WRI[s], tuple(g[k] + .3 * (w[k] - g[k]) for k in range(3)))
                lines[i] = ' | '.join(gr)
    return lines


def m_punch_reverse(lines):   # C5: the strike curve time-reversed around the peak (slow strike, snap back)
    for s, tp, t20, g in _punch_peaks(lines):
        P = [(i, gr, t) for i, gr, t in _paired(lines)]
        W = [(t, getvec(gr, 1, WRI[s])) for i, gr, t in P]
        for i, gr, t in P:
            if tp - .35 <= t <= tp + .35:
                tm = 2 * tp - t; w = min(W, key=lambda x: abs(x[0] - tm))[1]
                setvec(gr, 1, WRI[s], w); lines[i] = ' | '.join(gr)
    return lines


def m_punch_nowindup(lines):  # C6: no wind-up: the pull toward the shoulder before every strike removed (frozen guard)
    for s, tp, t20, g in _punch_peaks(lines):
        for i, gr, t in list(_paired(lines)):
            if t20 - .3 <= t <= t20:
                w = getvec(gr, 1, WRI[s]); sh = getvec(gr, 1, SHI[s])
                u = tuple(sh[k] - g[k] for k in range(3)); n = math.sqrt(sum(x * x for x in u)); u = tuple(x / n for x in u)
                d = sum((w[k] - g[k]) * u[k] for k in range(3))
                if d > 0:
                    setvec(gr, 1, WRI[s], tuple(w[k] - d * u[k] for k in range(3))); lines[i] = ' | '.join(gr)
    return lines


def m_punch_hand90(lines):    # C7: the striking hand turned 90 deg (rec group F axes about camera x) around every strike
    for s, tp, t20, g in _punch_peaks(lines):
        j = 1 if s == 'L' else 3
        for i, gr, t in list(_paired(lines)):
            if t20 - .1 <= t <= tp + .2:
                for k, x in enumerate(gr):
                    tk = x.split()
                    if tk[:1] == ['F']:
                        for c in (j, j + 1):
                            tk[c] = '%.4f,%.4f,%.4f' % rot(tuple(float(v) for v in tk[c].split(',')), (1.0, 0.0, 0.0), 90.0)
                        gr[k] = ' '.join(tk)
                lines[i] = ' | '.join(gr)
    return lines


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
    ff(['-i', src, '-i', ARROW, '-filter_complex', "[0][1]overlay=x=main_w*41/80:y=main_h*43/90:enable='between(t,3,6)'", '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def v_dark(src, dst):
    ff(['-i', src, '-vf', 'eq=brightness=-0.45:saturation=0.4,colorchannelmixer=rr=0.3:gg=0.3:bb=0.45', '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def v_black(src, dst):
    ff(['-i', src, '-vf', "drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill:enable='between(t,2,6)'", '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def v_popup(src, dst):
    ff(['-i', src, '-vf', "drawbox=x=iw*0.3:y=ih*0.3:w=iw*0.4:h=ih*0.35:color=0x404040:t=fill:enable='between(t,2,8)',"
        "drawbox=x=iw*0.3:y=ih*0.3:w=iw*0.4:h=ih*0.05:color=0xc8c8c8:t=fill:enable='between(t,2,8)'", '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def v_hintbox(src, dst):   # Misses 2026-10-10 tutorial hint popups: 4 stacked dark boxes, flat fill, dim text, left edge
    vf = []
    for k in range(4):
        y = 350 + 28 * k
        vf += ['drawbox=x=0:y=%d:w=200:h=24:color=0x121212:t=fill' % y, 'drawbox=x=0:y=%d:w=198:h=20:color=0x2a2a2a:t=fill' % (y + 2),
               'drawbox=x=30:y=%d:w=110:h=4:color=0x616161:t=fill' % (y + 9)]
    ff(['-i', src, '-vf', ','.join(vf), '-c:v', 'libx264', '-preset', 'ultrafast', dst])


def v_toast(src, dst):     # steam-popup 2026-10-11: blue-grey toast with white text, bottom right (HUD band), 2-8 s
    en = ":enable='between(t,2,8)'"
    vf = ['drawbox=x=iw-330:y=ih-110:w=300:h=70:color=0x141821:t=fill' + en]
    vf += ['drawbox=x=iw-290:y=ih-%d:w=220:h=5:color=0xe6e6e6:t=fill%s' % (95 - 18 * k, en) for k in range(3)]
    ff(['-i', src, '-vf', ','.join(vf), '-c:v', 'libx264', '-preset', 'ultrafast', dst])


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
    'spike': lambda p: verdict_word(run(al('spike', p)), 'spike '),
    'fist-hand': lambda p: verdict_word(run(['python3', FTC, p, '-']), 'hand '),
    'punch-C1': lambda p: verdict_word(run(['python3', FPC, p]), 'C1 '),
    'punch-C2': lambda p: verdict_word(run(['python3', FPC, p]), 'C2 '),
    'punch-C3': lambda p: verdict_word(run(['python3', FPC, p]), 'C3 '),
    'punch-C5': lambda p: verdict_word(run(['python3', FPC, p]), 'C5 '),
    'punch-C6': lambda p: verdict_word(run(['python3', FPC, p]), 'C6 '),
    'punch-C7': lambda p: verdict_word(run(['python3', FPC, p]), 'C7 '),
    'framed': lambda p: verdict_word(run(['python3', os.path.join(L, 'spec.py'), 'framed', p]), 'framed '),
    'metrics-any': lambda p: (('FAIL' if any(' FAIL' in l[:40] for l in run(al('metrics', p)).splitlines()) else 'PASS'), 'metrics'),
}
def _pool_inline_s3(p):   # the gate pool's per-swing inline path (metrics.swing_verdicts inline + pool_predict) on the rec as recorded
    code = ('import sys; sys.path.insert(0, %r); import recfmt, metrics as M; r = recfmt.parse(sys.argv[1]); '
            'V = [v for v in M.swing_verdicts(r.frames, M.frame_metrics(r), (), inline=True) if v["stroke"] == 3]; '
            'ok, t = M.pool_predict(V, ("inline",), take=min(2, max(1, len([v for v in V if v["full"]])))); '
            'print("poolinl", "PASS" if ok else "FAIL", " ".join(t))') % L
    return verdict_word(run(['python3', '-c', code, p]), 'poolinl ')


REC_CHECKS['path-stroke1'] = lambda p: _path_rule('1', 'late')(p)   # the late-drift rule of stroke 1 (gated for the mutation); was the whole path verdict: BASEFAIL once span/ctr (Shay 17:05) fail the accepted s1
def _path_rule(stroke, rule):   # one swing rule of `animlab.py path` (sweep= / wexit=) on one stroke (gated for the mutation)
    def f(p):
        out = run(al('path', '--stroke', stroke, '--gate-info', p))
        segs = [(l, (lambda r: r if rule == 'wexit' else r.split(',')[0])(l.split(',' + rule + '=', 1)[1] if (',' + rule + '=') in l else l.split(' ' + rule + '=', 1)[1]))
                for l in out.splitlines() if l.startswith('pathsw') and (rule + '=') in l]   # wexit: its tokens run to the line end
        bad = [l for l, sg in segs if ':BAD' in sg]
        n = sum(1 for l in out.splitlines() if l.startswith('pathsw'))
        return ('FAIL' if bad or not n else 'PASS'), (bad[0] if bad else 'pathsw n=%d %s ok' % (n, rule))
    return f


REC_CHECKS['path-sweep-stroke1'] = _path_rule('1', 'sweep')
REC_CHECKS['path-wexit-stroke3'] = _path_rule('3', 'wexit')
REC_CHECKS['inline-stroke3'] = lambda p: verdict_word(run(al('--only-stroke', '3', 'inline', p)), 'inline ')
REC_CHECKS['pool-inline-stroke3'] = _pool_inline_s3
SC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'stroke-cycle.py')
BUILD = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build.sh')


def _stroke_cycle(d):   # d = a client dir: build its replay adapter (build cache), run the E6 default stroke cycle check
    out = os.path.join(os.path.dirname(d), 'kfpvm_' + os.path.basename(os.path.dirname(d)))
    b = run(['bash', BUILD, '--src', d, '--out', out])
    if not os.path.exists(out):
        return 'NONE', 'build failed: ' + b.strip()[-150:]
    return verdict_word(run(['python3', SC, '--adapter', out, '--src', d]), 'RESULT ')


SRC_CHECKS = {'stroke-cycle': _stroke_cycle}
VID_CHECKS = {
    'cursor': lambda p: verdict_word(run(['python3', os.path.join(L, 'frames.py'), 'cursor', p, '--name', 'mut']), 'RESULT '),
    'openground': lambda p: verdict_word(run(['python3', os.path.join(L, 'frames.py'), 'openground', p, '--name', 'mut']), 'RESULT '),
    'overlay': lambda p: verdict_word(run(['python3', os.path.join(L, 'frames.py'), 'overlay', p, '--name', 'mut']), 'RESULT '),
}


def _take_check(d):
    vl = open(os.path.join(d, 'video-len.txt')).read().split()[0]
    return verdict_word(run(['python3', os.path.join(L, 'takecheck.py'), '--labels', os.path.join(d, 'labels.txt'), '--ev',
                             os.path.join(d, 'ev.txt'), '--rules', RULES, '--video-len', vl, '--name', 'mut']), 'RESULT ')


def take_check(d):
    # PASS-REC (speed-takes 2026-10-10: only recording checks failed, judged on what was recorded) still FLAGS the
    # recording fault (rec-warn=<check>): counts as caught, like FAIL. A clean base take must stay plain PASS.
    v, l = _take_check(d)
    return ('FAIL' if 'PASS-REC' in l.split()[:3] else v), l


# id, kind, base (relative to the work dir), edit, checks (designated; 'ALL' = exploratory over every check of the kind)
MUTS = [
    ('rec-wrist-over-limit', 'rec', 'f23-sword-z0d.txt', m_wrist, ['arc']),
    ('rec-hanging-blade', 'rec', 'f28-sword-z0c.txt', m_hanging, ['guard']),
    ('rec-endon-blade-frame', 'rec', 'e6-anim-b2.txt', m_endon, ['blade1']),
    ('rec-one-frame-snap', 'rec', 'e6-anim-b2.txt', m_snap, ['blade1', 'churn-stroke1', 'spike']),
    ('rec-one-frame-jump', 'rec', 'f28-sword-z0c.txt', m_jump, 'ALL'),
    ('rec-fist-hand-flip', 'rec', 'fist-u25-pass-replay-C2-kq025.rec', m_fist_hand, ['fist-hand']),
    ('rec-fist-punch-small-C1', 'rec', 'rec/fist-punch-synth-pass-v3.txt', m_punch_small, ['punch-C1']),
    ('rec-fist-punch-small-C2', 'rec', 'rec/fist-punch-synth-pass-v3.txt', m_punch_small, ['punch-C2']),
    ('rec-fist-punch-small-C3', 'rec', 'rec/fist-punch-synth-pass-v3.txt', m_punch_small, ['punch-C3']),
    ('rec-fist-punch-reverse', 'rec', 'rec/fist-punch-synth-pass-v3.txt', m_punch_reverse, ['punch-C5']),
    ('rec-fist-punch-nowindup', 'rec', 'rec/fist-punch-synth-pass-v3.txt', m_punch_nowindup, ['punch-C6']),
    ('rec-fist-punch-hand90', 'rec', 'rec/fist-punch-synth-pass-v3.txt', m_punch_hand90, ['punch-C7']),
    ('vid-cursor-overlay', 'vid', 'takes/videos/anim-sword-e6.mp4', v_cursor, ['cursor']),
    ('vid-dark-night', 'vid', 'takes/videos/anim-sword-e6.mp4', v_dark, ['openground']),
    ('vid-black-frames', 'vid', 'takes/videos/anim-sword-e6.mp4', v_black, 'ALL'),
    ('vid-popup-overlay', 'vid', 'kept/kfx-b2_e6_e6fix.mp4', v_popup, ['overlay']),   # anim-sword-e6 shows NPC chatter text
    ('vid-hint-popups', 'vid', 'kept/kfx-b2_e6_e6fix.mp4', v_hintbox, ['overlay']),   # frames.py ui_boxes
    ('vid-steam-toast', 'vid', 'kept/kfx-b2_e6_e6fix.mp4', v_toast, ['overlay']),   # frames.py toast_cells
    ('take-label-state-mismatch', 'take', 'takes/ok-e6fix', t_label, ['takecheck']),
    ('take-video-past-end', 'take', 'takes/ok-e6fix', t_end, ['takecheck']),
    ('take-bystander', 'take', 'takes/ok-e6fix', t_near, ['takecheck']),
    ('take-combat-message', 'take', 'takes/ok-e6fix', t_msgs, ['takecheck']),
    ('rec-s3-windup-blade-off', 'rec', 'rec/e6s3-3f1a-5090.txt', m_s3_windup_off, ['inline-stroke3', 'pool-inline-stroke3']),
    ('rec-path-late-drift', 'rec', 'rec/ab2h-5090.txt', m_path_drift, ['path-stroke1']),
    ('rec-windup-popin', 'rec', 'rec/ab2h-5090.txt', m_windup_popin, ['path-wexit-stroke3']),
    ('rec-sweep-frozen', 'rec', 'rec/ab2h-5090.txt', m_sweep_frozen, ['path-sweep-stroke1']),
    ('rec-framed-cross-unseen', 'rec', 'rec/ab2h-5090.txt', m_cross_unseen, ['framed']),
    ('src-2hl-stroke0', 'src', 'src/KenshiFP-e6mask3-c4ee493.client.tar.gz', s_2hl_stroke0, ['stroke-cycle']),
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
        if not os.path.exists(src):   # corpus files the regress sync does not copy (kept/...): read them in place
            src = os.path.join(CORPUS, base)
        if not os.path.exists(src):
            res[mid] = 'BASEFAIL'; print('MUT %s BASEFAIL - base %s missing' % (mid, base)); continue
        key = mut_key(mid, kind, base, checks, src)
        hit = cache_get(key)
        if hit is not None:   # same mutation code, same base material, same check code: the stored verdict (labcache)
            caught, base_bad, det, names = hit['caught'], hit['base_bad'], hit['det'], hit['names']
            for vl in hit.get('vlines', []) if a.v else []:
                print(vl)
            n_cached[0] += 1
        else:
            caught, base_bad, det, names, vlines = run_mut(a, mid, kind, src, edit, checks)
            cache_put(key, dict(caught=caught, base_bad=base_bad, det=det, names=names, vlines=vlines))
        if len(base_bad) == len(names): st = 'BASEFAIL'
        elif caught: st = 'FIXED' if mid in known else 'CAUGHT'
        else: st = 'KNOWN' if mid in known else 'MISSED'
        res[mid] = st
        print('MUT %s %s %s %s' % (mid, st, ','.join(caught) or ('/'.join(names) if checks != 'ALL' else 'any'), ' '.join(det)))
    n = len(res); c = sum(1 for v in res.values() if v in ('CAUGHT', 'FIXED'))
    missed = [k for k, v in res.items() if v in ('MISSED', 'BASEFAIL')]; kn = [k for k, v in res.items() if v == 'KNOWN']
    print('RESULT MUTATIONS %s %d/%d missed=%s known=%s cached=%d' % ('PASS' if not missed else 'FAIL', c, n, ','.join(missed) or 'none', ','.join(kn) or 'none', n_cached[0]))
    return 0 if not missed else 1


def run_mut(a, mid, kind, src, edit, checks):
    vlines = []
    if True:
        if kind == 'rec':
            pool = REC_CHECKS; dst = os.path.join(a.out, mid + '.txt')
            open(dst, 'w').write('\n'.join(edit(read_rec(src))))
            names = list(pool) if checks == 'ALL' else checks
            runc = lambda n, p: pool[n](p)
        elif kind == 'vid':
            pool = VID_CHECKS; dst = os.path.join(a.out, mid + '.mp4'); edit(src, dst)
            names = list(pool) if checks == 'ALL' else checks
            runc = lambda n, p: pool[n](p)
        elif kind == 'src':   # base and mutant source trees extracted side by side, each built + checked (build/replay caches)
            trees = []
            for t in ('base', 'mut'):
                d = os.path.join(a.out, mid + '-' + t); shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
                subprocess.run(['tar', 'xzf', src, '-C', d], check=True); trees.append(os.path.join(d, 'client'))
            edit(trees[1]); src, dst = trees
            names = checks; runc = lambda n, p: SRC_CHECKS[n](p)
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
            vl = '   %s %s: base %s | mutant %s' % (mid, n, bl[:110], ml[:160]); vlines.append(vl)
            if a.v: print(vl)
    return caught, base_bad, det, list(names), vlines


# ---------------- result cache (labcache.py; Shay 2026-10-10 CPU cut) ----------------
# A mutation's verdict depends only on this file (edits + check wiring), its base material and the code of the checks it
# runs: rec -> animlab.py/metrics.py/recfmt.py, vid -> frames.py/framecache.py, take -> takecheck.py/frames.py/framecache.py
# (+ take-rules.txt, ffmpeg version). So a gate reruns only the mutations whose check code or material changed; the KenshiFP
# source under test plays no part. ANIMLAB_CACHE=0 recomputes all, =verify recomputes and compares.
sys.path.insert(0, L)
try:
    import labcache
except ImportError:
    labcache = None
DEPS = {'rec': ('animlab.py', 'metrics.py', 'recfmt.py', 'labcache.py'), 'vid': ('frames.py', 'framecache.py'),
        'take': ('takecheck.py', 'frames.py', 'framecache.py'), 'src': ('labcache.py',)}
n_cached = [0]
_ffv = []


def mut_key(mid, kind, base, checks, src):
    if labcache is None:
        return None
    if not _ffv:
        try:
            _ffv.append(subprocess.run(['ffmpeg', '-version'], stdout=subprocess.PIPE, universal_newlines=True).stdout.split(chr(10))[0])
        except OSError:
            _ffv.append('')
    mat = []
    if os.path.isdir(src):
        for root, dirs, files in os.walk(src):
            dirs.sort()
            mat += [[os.path.relpath(os.path.join(root, f), src), labcache.fhash(os.path.join(root, f))] for f in sorted(files)]
    else:
        mat = [labcache.fhash(src)]
    code = [[d, labcache.fhash(os.path.join(L, d))] for d in DEPS[kind] if os.path.exists(os.path.join(L, d))]
    if kind == 'rec':
        code.append(['fist-take-check.py', labcache.fhash(FTC)])
        code.append(['fist-punch-check.py', labcache.fhash(FPC)])
    if kind == 'src':   # the check builds the adapter and replays: its main, headers, build script and the check script
        H = os.path.dirname(os.path.abspath(__file__))
        code += [[f, labcache.fhash(os.path.join(H, f))] for f in sorted(os.listdir(H)) if f.endswith(('.c', '.h')) or f in ('build.sh', 'stroke-cycle.py')]
        code += [[f, labcache.fhash(os.path.join(H, 'patches', f))] for f in sorted(os.listdir(os.path.join(H, 'patches')))]
        code.append(['stroke-cycle-table', labcache.fhash(os.path.join(CORPUS, 'pools/stroke-cycle/classes.tsv'))])
    return labcache.make_key('mutation', [mid, kind, base, checks, labcache.fhash(os.path.abspath(__file__)), code,
                                          labcache.fhash(RULES) if os.path.exists(RULES) else '', _ffv[0], mat, labcache.env_part()])


def cache_get(key):
    if key is None or labcache.mode() != '1':
        return None
    m = labcache._load(key)
    if m is None:
        return None
    try:
        return json.loads(m['stdout'])
    except (KeyError, ValueError):
        return None


def cache_put(key, val):
    if key is None or labcache.mode() == '0':
        return
    if labcache.mode() == 'verify':
        m = labcache._load(key)
        if m is not None:
            labcache._verify(key, m, 0, json.dumps(val, sort_keys=True), '', {})
        return
    labcache._store(key, dict(rc=0, stdout=json.dumps(val, sort_keys=True), stderr='', outs=[], what='mutation'), {})


if __name__ == '__main__':
    sys.exit(main())
