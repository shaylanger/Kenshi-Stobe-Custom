#!/usr/bin/env python3
"""pyshim.py -- `python3` in the dry-run sandbox. Lab/harness tools a take script calls get dry-run behaviour, every
other script runs on the real python:
  kah.py                  -> the fake game (kahstub.py)
  take_sample.py          -> evidence samples from the fake game's state timeline (same line format)
  takecheck.py            -> the REAL takecheck on the script's labels + the synthetic samples (--video replaced by the
                             recording's virtual length, frame checks skipped): mistimed captions fail like in the game
  frames.py animlab.py fist-take-check.py review-pack.py -> canned PASS lines after checking their input files exist
On the 4080 rig python is Windows python behind Git Bash: POSIX paths written inside `-c` code or in env vars it reads
(KAH_CLIENT) are not converted and can't be opened (pf_rig 4080 bug, 9454eda)."""
import json, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dr  # noqa: E402

REAL = '/usr/bin/python3'
CANNED_TOOLS = ('frames.py', 'animlab.py', 'fist-take-check.py', 'review-pack.py', 'vmcheck.py')


def p(s):
    print(s, flush=True)


def check_files(tool, paths):
    bad = [x for x in paths if x and not os.path.exists(x)]
    for x in bad:
        dr.flag('FAIL', '%s: input file %s missing' % (tool, x))
    return not bad


def opt(a, name):
    return a[a.index(name) + 1] if name in a and a.index(name) + 1 < len(a) else None


def sampler(a):
    import kahstub
    pos = [x for i, x in enumerate(a) if not x.startswith('--') and (i == 0 or a[i - 1] not in ('--dt', '--r', '--run', '--count'))]
    ev, t0, me = pos[0], float(pos[1]), pos[2]
    dt = float(opt(a, '--dt') or os.environ.get('TAKE_DT', '0.6'))
    run, count = opt(a, '--run'), opt(a, '--count')
    if dr.RIG == '4080' and os.environ.get('KAH_CLIENT', '').startswith('/'):
        dr.flag('FAIL', 'take_sample.py on the 4080: KAH_CLIENT=%s is a POSIX path Windows python cannot import from' % os.environ['KAH_CLIENT'])
    start = dr.vnow()
    if count:
        n = int(count)
        dr.advance(n * dt)
        end = start + n * dt
    else:
        while run and os.path.exists(run):
            time.sleep(0.02)
        end = dr.vnow()
    with dr.Lock():
        s = kahstub.load_state()
        kahstub.settle(s, end)
        kahstub.save_state(s)
    hist = sorted(s['hist'], key=lambda e: e[0])
    w = kahstub.world(s, end)
    lines, t = [], start
    # fixture "stall": [offset s after the sampler start, length s]: the harness answered nothing (blkH 1.5 s hole)
    st = None
    try:
        st = json.load(open(os.environ['DR_FIXTURE_JSON'])).get('stall')
    except (KeyError, OSError, ValueError):
        pass
    while t <= end + 1e-6:
        if st and start + st[0] <= t < start + st[0] + st[1]:
            t += dt
            continue
        v = {}
        for e in hist:
            if e[0] > t:
                break
            v[e[1]] = e[2]
        lines.append('%.2f fp ui_state=%s hud_text=%s loaded=%s fp_ui_state=%s' % (
            t - t0, v.get('ui_state', '?'), v.get('hud_text', '?'), v.get('loaded', 0), v.get('ui_state', '?')))
        lines.append('%.2f world near=%d nearest=%s down=0 msgs=%d' % (t - t0 + 0.01, len(w['near']), (w['near'] or ['none'])[0].replace(' ', '_'), 1 if w['popup'] else 0))
        t += dt
    with open(ev, 'a') as f:
        f.write('\n'.join(lines) + '\n')
    dr.log('sampler', '%s %d samples %.1f..%.1f s' % (os.path.basename(ev), len(lines) // 2, start - t0, end - t0))
    return 0


def takecheck(script, a):
    a = list(a)
    labels = opt(a, '--labels')
    if labels:
        with open(os.path.join(dr.ST, 'labels.list'), 'a') as f:
            f.write(os.path.abspath(labels) + '\n')
    files = [labels, opt(a, '--rules')] + [a[i + 1] for i, x in enumerate(a) if x == '--ev' and i + 1 < len(a)]
    if not check_files('takecheck.py', files):
        p('RESULT take FAIL dryrun: takecheck input missing')
        return 1
    v = opt(a, '--video')
    if v:
        i = a.index('--video')
        ln = None
        try:
            ln = json.load(open(v + '.drrec'))['len']
        except (OSError, ValueError, KeyError):
            if not os.path.exists(v):
                dr.flag('FAIL', 'takecheck.py --video %s missing' % v)
        a[i:i + 2] = ['--video-len', '%.2f' % (ln or 2.0)]
    for o in ('--kfplog', '--log-t0'):
        while o in a:
            i = a.index(o); del a[i:i + 2]
    a += ['--no-cursor', '--no-overlay']
    r = subprocess.run([REAL, script] + a, capture_output=True, text=True)
    sys.stdout.write(r.stdout); sys.stderr.write(r.stderr)
    dr.log('takecheck', (r.stdout.strip().splitlines() or ['(no output)'])[-1][:200])
    return r.returncode


def canned(tool, a):
    name = opt(a, '--name') or 'take'
    if tool == 'frames.py':
        sub = a[0] if a else ''
        vid = a[1] if len(a) > 1 else ''
        if not check_files(tool, [vid]):
            p('RESULT %s FAIL %s: video missing' % (name, sub)); return 1
        import fakeexe
        w = fakeexe.now_world()
        if sub == 'overlay' and w.get('popup'):
            p('RESULT %s FAIL overlay frames=4 overlay_frames=4 text "%s" (dryrun fixture: fight near the spot)' % (name, w['popup'])); return 1
        if sub == 'openground' and w.get('night'):
            p('RESULT take FAIL openground open=0.10/0.90 frames=4 min_sky=0.02 sky_min=0.26 (dryrun fixture: night)'); return 1
        p({'openground': 'RESULT take PASS openground open=1.00/0.90 frames=4 min_sky=0.30 sky_min=0.26',
           'cursor': 'RESULT %s PASS cursor frames=10 cursor_frames=0' % name,
           'overlay': 'RESULT %s PASS overlay frames=4 overlay_frames=0' % name}.get(sub, 'RESULT %s PASS %s (dryrun canned)' % (name, sub)))
        return 0
    if tool == 'animlab.py':
        a = list(a)
        while a and a[0] == '--only-stroke':   # the one top-level option (animlab.py main): before the subcommand
            a = a[2:]
        sub = a[0] if a else ''
        if not check_files(tool, [x for x in a[1:2] if not x.startswith('-')]):
            p('%s FAIL input missing' % sub); return 1
        rec = a[1] if len(a) > 1 and not a[1].startswith('-') else ''
        try:   # kahstub's canned rec dump header: "# dryrun canned vm rec frames=<n> swings=<n> kicks=<n>"
            hdr = open(rec, errors='replace').readline() if rec else ''
        except OSError:
            hdr = ''
        sw = re.search(r'swings=(\d+)', hdr)
        if sub == 'weapons':   # weapon_matrix.py line format: WEAPON <sid> PASS <cls>/<anim cls> <name> [<source>] <checks>
            sid = (opt(a, '--only') or 'dryrun-weapon').replace(' ', '_')
            p('WEAPON %s PASS dryrun/dryrun %s [dryrun] recs=ok(canned)' % (sid, sid))
            return 0
        if sub == 'metrics':   # animlab.py cmd_metrics: state table, "moves PASS|FAIL <per state>", "arc ..." with swings
            p('state  n\nready  10 (dryrun canned)\nmoves PASS ready=ok(canned)')
            if sw and int(sw.group(1)) > 0:
                p('arc PASS swing=ok(canned)')
            return 0
        p('guard PASS presses=12 hanging=0 (dryrun canned)' if sub == 'guard' else '%s PASS (dryrun canned)' % sub)
        return 0
    if tool == 'vmcheck.py':   # fp-viewmodel.sh's every-frame check of an fp_vm rec dump (a lab verdict, canned here)
        if not check_files(tool, a[:1]):
            p('ok=0 no dump'); return 1
        m = re.search(r'frames=(\d+)', open(a[0], errors='replace').readline())
        n = int(m.group(1)) if m else 0
        if n == 0:
            p('ok=0 frames=0 (dryrun: empty rec dump: fp_vm rec on never sent?)'); return 0
        if len(a) > 1 and a[1] == 'zo':
            p('ok=1 zo_frames=%d zf_max=0.00 head_min=2.00 torso_min=2.00 vis_min=0.040 pts_min=21 wb_max=0.0 elb_max=0.00 bad=none (dryrun canned)' % n)
        else:
            p('ok=1 frames=%d vis=%d fps=60 cut=0 flags=0 errmax=0.10@0:ready (dryrun canned)' % (n, n))
        return 0
    if tool == 'fist-take-check.py':
        if not check_files(tool, a[:1]):
            p('RESULT fist FAIL vmrec missing'); return 1
        if len(a) > 1 and not check_files(tool, [os.path.join(a[1], 'pose.txt'), os.path.join(a[1], 'keys.json')]):
            p('fistgame FAIL lab candidate missing'); return 1
        p('fistgame PASS dryrun-canned swings=3')
        return 0
    if tool == 'review-pack.py':
        pos = [x for i, x in enumerate(a) if not x.startswith('--') and (i == 0 or not a[i - 1].startswith('--'))]
        if len(pos) < 2:
            dr.flag('FAIL', 'review-pack.py: needs <video> <out-dir>'); return 2
        fs = [pos[0], opt(a, '--ts'), opt(a, '--labels')]
        if '--lab' in a:
            i = a.index('--lab') + 1
            while i < len(a) and not a[i].startswith('--'):
                fs.append(a[i]); i += 1
        if not check_files(tool, fs):
            return 1
        lab = opt(a, '--labels')
        if lab:
            with open(os.path.join(dr.ST, 'labels.list'), 'a') as f:
                f.write(os.path.abspath(lab) + '\n')
        os.makedirs(pos[1], exist_ok=True)
        with open(os.path.join(pos[1], 'INDEX.txt'), 'w') as f:
            f.write('dryrun canned review pack of %s\n' % pos[0])
        p('INDEX %s' % os.path.join(pos[1], 'INDEX.txt'))
        return 0
    return 0


def main():
    a = sys.argv[1:]
    if a and a[0] == '-c' and len(a) > 1:
        if dr.RIG == '4080':
            m = re.search(r'''['"](/(?:c|mnt|tmp)/[^'"]*)['"]''', a[1])
            if m:
                dr.flag('FAIL', '4080 Windows python: POSIX path %s inside -c code is not converted by Git Bash (pass it in '
                                'C:/ form: cygpath -m)' % m.group(1))
                sys.stderr.write("FileNotFoundError: [Errno 2] No such file or directory: '%s'\n" % m.group(1))
                return 1
            # Windows python opens C:/... and C:\\... itself: map them to the sandbox's /c
            a = [a[0], re.sub(r'([A-Za-z]):[\\/]{1,2}', lambda m: '/%s/' % m.group(1).lower(), a[1])] + a[2:]
        os.execv(REAL, [REAL] + a)
    i = 0
    while i < len(a) and a[i].startswith('-') and a[i] not in ('-',):
        i += 2 if a[i] in ('-W', '-X', '-m') else 1
    if i >= len(a) or a[i] == '-':
        os.execv(REAL, [REAL] + a)
    script, rest = a[i], a[i + 1:]
    base = os.path.basename(script)
    if base == 'kah.py':
        import kahstub
        return kahstub.main(rest)
    if base == 'take_sample.py':
        return sampler(rest)
    if base == 'takecheck.py':
        dr.log('python', 'takecheck.py %s' % ' '.join(rest)[:200])
        return takecheck(script, rest)
    if base in CANNED_TOOLS:
        dr.log('python', '%s %s' % (base, ' '.join(rest)[:200]))
        if not os.path.exists(script):
            dr.flag('FAIL', 'python3 %s: script missing' % script)
            sys.stderr.write("python3: can't open file '%s': [Errno 2] No such file or directory\n" % script)
            return 2
        return canned(base, rest)
    dr.log('python', '%s %s' % (script, ' '.join(rest)[:200]))
    os.execv(REAL, [REAL] + a)


if __name__ == '__main__':
    sys.exit(main())
