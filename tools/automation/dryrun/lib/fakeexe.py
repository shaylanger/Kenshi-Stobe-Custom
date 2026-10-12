#!/usr/bin/env python3
"""fakeexe.py -- dry-run stand-ins for the external tools take scripts call, dispatched on the name they were run as
(tools/automation/dryrun/bin/* are symlinks/wrappers to this file):
  ffmpeg ffmpeg.exe ffprobe ffprobe.exe   recordings / grabs / probes (virtual time, canned frame + mp4, sidecar .drrec)
  powershell.exe quser.exe tasklist.exe cmd.exe taskkill.exe schtasks.exe   rig scripts (kenshi-ctl, display-keeper,
                                          C:\\KAH\\ctl.ps1 / itrun.ps1 / display-check.ps1 on the 4080 rig)
  stobe-say  wslpath (5090 only)  cygpath (4080 only)  sleep  date      virtual clock
Windows-exe path rules are enforced (dr.winexe_path): on the 5090 a POSIX path given to a Windows exe is a bug, on the
4080 (Git Bash) /mnt/... paths don't exist and a native ffmpeg never reads 'q' from an MSYS fifo."""
import json, os, re, select, shutil, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dr  # noqa: E402

WIN_TITLE = 'title=Kenshi 1.0.65 - x64 (Newland)'
# multi-instance lanes (rig-env.sh): instance n>=2 is retitled "<title> [i<n>]"; filming the base title there films lane A's
# game (138-wc-clv-any 2026-10-11: take-preflight.sh pf_open hardcoded the base title on lane 5090b)
if re.fullmatch(r'[2-9]', os.environ.get('KAH_INSTANCE', '1')):
    WIN_TITLE = WIN_TITLE + ' [i%s]' % os.environ['KAH_INSTANCE']
BOOL = {'-y', '-n', '-hide_banner', '-nostdin', '-an', '-sn', '-vn', '-dn', '-shortest', '-nostats', '-stats', '-re',
        '-show_format', '-show_streams', '-of', '-print_format'}
BOOL_PROBE = {'-show_format', '-show_streams', '-show_entries', '-v', '-of', '-select_streams'}


def out(s):
    sys.stdout.write(s + ('\n' if s and not s.endswith('\n') else ''))


# ---------------------------------------------------------------------------------------------------- ffmpeg
def parse_ff(a):
    opts, inputs, pos, i = {}, [], [], 0
    while i < len(a):
        x = a[i]
        if x == '-i' and i + 1 < len(a):
            inputs.append((dict(opts), a[i + 1])); opts = {k: v for k, v in opts.items() if k == '_global'}; i += 2; continue
        if x.startswith('-') and x != '-' and x not in BOOL and i + 1 < len(a):
            opts[x] = a[i + 1]; i += 2; continue
        if x.startswith('-') and x != '-':
            opts[x] = True; i += 1; continue
        pos.append(x); i += 1
    return opts, inputs, pos


def sidecar_len(p):
    try:
        return json.load(open(p + '.drrec'))['len']
    except (OSError, ValueError, KeyError):
        return None


def stdin_kind():
    try:
        l = os.readlink('/proc/self/fd/0')
    except OSError:
        return 'none'
    if l.startswith('pipe:'):
        return 'pipe'
    if l == '/dev/null':
        return 'null'
    try:
        import stat
        if stat.S_ISFIFO(os.stat('/proc/self/fd/0').st_mode):
            return 'fifo'
    except OSError:
        pass
    return 'other'


def now_world():
    try:
        import kahstub
        return kahstub.world(json.load(open(os.path.join(dr.ST, 'state.json'))), dr.vnow())
    except (OSError, ValueError, KeyError):
        return {}


def record(opts_in, outp, gopts):
    start = dr.vnow()
    try:
        st = json.load(open(os.path.join(dr.ST, 'state.json')))
        snap = dict(chatter=st.get('chatter'), cursor=st.get('cursor'), fpchar=st.get('fpchar'))
        import kahstub
        snap.update(kahstub.world(st, start))
    except (OSError, ValueError):
        snap = {}
    t = gopts.get('-t') or opts_in.get('-t')
    t = float(t) if t not in (None, True) else None
    kind = stdin_kind()
    win = True
    stop_how = 'time'
    if kind == 'fifo' and dr.RIG == '4080':
        dr.flag('FAIL', '4080 Git Bash: a native ffmpeg never reads "q" from an MSYS fifo: this recording runs the full -t %s '
                '(stop it through a plain pipe, see fp-zoom-sweep.sh ZS_PIPE)' % t)
        kind = 'ignored-fifo'
    if kind in ('pipe', 'fifo'):
        stop_how = 'q'
        buf = b''
        while True:
            if t is not None and dr.vnow() >= start + t:
                stop_how = 'time-cap'
                break
            r, _, _ = select.select([0], [], [], 0.05)
            if r:
                c = os.read(0, 64)
                if not c:
                    stop_how = 'eof'
                    break
                buf += c
                if b'q' in buf:
                    break
        end = dr.vnow()
        if stop_how == 'time-cap':
            end = start + t
    else:
        if t is None:
            dr.flag('FAIL', 'gdigrab recording %s has no -t and no q pipe: it never ends' % outp)
            t = 30.0
        dr.vwait(start + t - dr.vnow())   # a waiter like sleep: ends when the foreground has used the time
        end = start + t
    return start, end, stop_how, snap


def ffmpeg(name, a):
    win = name.endswith('.exe') or dr.RIG == '4080'
    opts, inputs, pos = parse_ff(a)
    cwd = os.getcwd()
    probe = name.startswith('ffprobe')

    def mp(p):
        if p in ('-', 'pipe:', 'pipe:1') or p.startswith('title=') or p.startswith('desktop'):
            return p
        if win:
            q, prob = dr.winexe_path(p, cwd)
            if prob:
                dr.flag('FAIL', '%s: %s' % (name, prob))
                return None
            return q
        return p if p.startswith('/') else os.path.join(cwd, p)
    if probe:
        f = mp(pos[-1]) if pos else None
        if f and not os.path.exists(f):
            dr.flag('FAIL', 'ffprobe: input %s missing' % pos[-1]); sys.stderr.write('%s: No such file or directory\n' % pos[-1]); return 1
        ln = sidecar_len(f) or 2.0
        out('%.3f' % ln if 'duration' in ' '.join(a) else 'duration=%.3f' % ln)
        return 0
    ins = []
    for o, p in inputs:
        if o.get('-f') == 'gdigrab':
            # a desktop REGION grab (-offset_x/-offset_y/-video_size all given) is deliberate: capture-proof.sh's control
            # films the screen area under its cover window; a bare 'desktop' (whole screen) still fails
            region = p == 'desktop' and all(k in o for k in ('-offset_x', '-offset_y', '-video_size'))
            if p != WIN_TITLE and not region:
                dr.flag('FAIL', 'gdigrab input "%s" is not the game window (%s)' % (p, WIN_TITLE))
            if str(o.get('-draw_mouse', '1')) != '0':
                dr.flag('FAIL', 'gdigrab without -draw_mouse 0: the mouse cursor gets into the recording')
            ins.append(('grab', p, o))
            continue
        q = mp(p)
        if q is None:
            return 1
        if not os.path.exists(q) and not re.match(r'^(color|testsrc|anullsrc|lavfi)', p):
            dr.flag('FAIL', '%s: input %s missing' % (name, p))
            sys.stderr.write('%s: No such file or directory\n' % p)
            return 1
        ins.append(('file', q, o))
    vf = str(opts.get('-vf', opts.get('-filter_complex', '')))
    dest = pos[-1] if pos else None
    if not ins:
        sys.stderr.write('ffmpeg: no input\n'); return 1
    if dest is None:   # probe: ffmpeg -i x.mp4
        ln = sidecar_len(ins[0][1]) or 2.0
        sys.stderr.write('Input #0, mov,mp4, from \'%s\':\n  Duration: %02d:%02d:%05.2f, start: 0.000000, bitrate: 2000 kb/s\n'
                         'At least one output file must be specified\n' % (ins[0][1], ln // 3600, (ln % 3600) // 60, ln % 60))
        return 1
    wd = now_world()
    if 'signalstats' in vf:
        for i in range(6):
            sys.stderr.write('frame:%d pts:%d\nlavfi.signalstats.YAVG=%.3f\n' % (i, i, (12.0 if wd.get('night') else 96.0) + i))
        return 0
    if dest in ('-', 'pipe:', 'pipe:1'):
        m = re.search(r'scale=(\d+):(\d+)', vf)
        w, h = (int(m.group(1)), int(m.group(2))) if m else dr.res()
        if 'crop=' in vf and not m:
            w, h = 1, 1
        gray = 'gray' in vf or opts.get('-pix_fmt') == 'gray'
        px = bytes([110]) if gray else bytes([78, 114, 131])
        if wd.get('night'):
            px = bytes([18]) if gray else bytes([20, 22, 30])
        sys.stdout.buffer.write(px * (w * h))
        if ins[0][0] == 'grab':
            dr.log('ffmpeg', 'grab 1 frame %dx%d %s' % (w, h, 'gray' if gray else 'rgb'))
        return 0
    dpath = mp(dest)
    if dpath is None:
        return 1
    if dest == '/dev/null' or opts.get('-f') == 'null':
        return 0
    if not os.path.isdir(os.path.dirname(os.path.abspath(dpath)) or '.'):
        dr.flag('FAIL', '%s: output dir of %s missing' % (name, dest))
        sys.stderr.write('%s: No such file or directory\n' % dest)
        return 1
    if ins[0][0] == 'grab':
        start, end, how, snap = record(ins[0][2], dpath, opts)
        shutil.copyfile(os.path.join(dr.CANNED, 'take.mp4'), dpath)
        json.dump(dict(start=start, end=end, len=end - start, how=how), open(dpath + '.drrec', 'w'))
        dr.jappend('recordings.jsonl', dict(kind='video', file=dpath, start=start, end=end, len=end - start, how=how, **snap))
        dr.log('ffmpeg', 'recorded %s %.1f s (stop: %s)' % (dest, end - start, how))
        return 0
    ext = os.path.splitext(dpath)[1].lower()
    src = 'frame.png' if ext in ('.png', '.jpg', '.jpeg', '.bmp') else 'take.mp4'
    shutil.copyfile(os.path.join(dr.CANNED, src), dpath)
    ln = sidecar_len(ins[0][1])
    if ln:   # cuts: input -ss / -t, output -t, a trim=<start>:<end> / trim=end=<e> filter (T6 render -t 56.5, zsv trim)
        def num(x):
            try:
                return float(x)
            except (TypeError, ValueError):
                return None
        io = ins[0][2]
        ss = num(io.get('-ss')) or num(opts.get('-ss')) or 0.0
        ln = max(0.0, ln - ss)
        for t in (num(io.get('-t')), num(opts.get('-t'))):
            if t is not None:
                ln = min(ln, t)
        m = re.search(r'trim=(?:end=)?([\d.]+)?:?([\d.]+)?', vf)
        if m:
            a0, b0 = num(m.group(1)), num(m.group(2))
            if 'trim=end=' in vf and a0 is not None:
                ln = min(ln, a0)
            elif b0 is not None:
                ln = min(ln, b0 - (a0 or 0.0))
    if ln and src == 'take.mp4':
        json.dump(dict(start=0, end=ln, len=ln, how='copy'), open(dpath + '.drrec', 'w'))
    dr.log('ffmpeg', 'convert %s -> %s' % (os.path.basename(ins[0][1]), dest))
    return 0


# ---------------------------------------------------------------------------------------------------- powershell
def itrun(cmd, logw):
    """C:\\KAH\\itrun.ps1: a fresh `bash -l` in Shay's session with rig-env.sh sourced: nothing of the caller's shell
    (functions, unexported vars, cwd) carries over; stdin /dev/null."""
    if dr.RIG != '4080':
        dr.flag('FAIL', 'itrun.ps1 is the 4080 rig runner; called on the 5090')
    logp, prob = dr.winexe_path(logw)
    if prob or not logp:
        dr.flag('FAIL', 'itrun.ps1 -Log %s: %s' % (logw, prob)); return 1
    env = {k: v for k, v in os.environ.items() if k.startswith('DR_') or k in ('PATH', 'HOME', 'TERM', 'LANG')}
    env['PATH'] = os.environ.get('DR_BASE_PATH', env.get('PATH', ''))
    env['RIG'] = '4080'
    body = '{ . /c/KenshiModding/tools/automation/rig-env.sh; %s ; } > \'%s\' 2>&1 < /dev/null' % (cmd, logp)
    p = subprocess.Popen(['/bin/bash', '-c', body], env=env, cwd=os.environ.get('HOME', '/root'),
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    dr.jappend('children.jsonl', dict(pid=p.pid, cmd=cmd, log=logp))
    out('started dr%d log=%s' % (p.pid, logw))
    return 0


def powershell(a):
    low = [x.lower() for x in a]
    if '-file' in low:
        i = low.index('-file')
        f = a[i + 1] if i + 1 < len(a) else ''
        rest = a[i + 2:]
        p, prob = dr.winexe_path(f)
        base = re.split(r'[\\/]', f)[-1].lower()
        if prob:
            dr.flag('FAIL', 'powershell -File %s: %s' % (f, prob)); return 1
        if not os.path.exists(p) and not (dr.RIG == '4080' and base in ('ctl.ps1', 'itrun.ps1', 'display-check.ps1', 'kcfg.ps1', 'kenshi-gfx.ps1')):
            dr.flag('FAIL', 'powershell -File %s: script missing' % f)
            sys.stderr.write('The argument \'%s\' to the -File parameter does not exist.\n' % f); return 1
        sub = next((x for x in rest if not x.startswith('-')), '')
        dr.log('powershell', '%s %s' % (base, ' '.join(rest)))
        if base == 'kfp-fastswap.ps1':   # fast restart (hotswap2 2026-10-11): the fake game is always "back in the world"
            out('   0.0 stopped (was running: True)'); out('FASTSWAP OK total=0.0 stop=0.0 install=0.0 menu=0.0 world=0.0 dll=FAKE save=kah-swap instance=1 (dryrun)'); return 0
        if base == 'kenshi-ctl.ps1':
            if sub == 'focus':
                dr.flag('FAIL', 'kenshi-ctl.ps1 focus: tests never focus the game (Shay\'s screen)')
            if sub == 'window':
                out('kenshi window: monitor=DISPLAY2 %dx%d foreground=explorer' % dr.res()); return 0
            if sub == 'ontop':   # take-preflight pf_ontop (capture-fix 2026-10-11)
                m = next((x for x in rest[rest.index(sub) + 1:] if not x.startswith('-')), 'check')
                out('ontop %s: topmost=True unoccluded' % m if m != 'off' else 'ontop off: topmost=False'); return 0
            if sub == 'idle':
                out('rig5090.idle written'); return 0
            out('kenshi-ctl %s ok (dryrun)' % sub); return 0
        if base == 'display-keeper.ps1':
            out('KEEPER RUNNING age=5' if '-status' in [x.lower() for x in rest] else 'keeper started'); return 0
        if base == 'display-check.ps1':
            out('--- gdigrab frame %dx%d luma=96 => LIVE' % dr.res()); return 0
        if base == 'itrun.ps1':
            kv = {rest[j].lower(): rest[j + 1] for j in range(len(rest) - 1) if rest[j].startswith('-')}
            return itrun(kv.get('-cmd', ''), kv.get('-log', ''))
        if base == 'gpu-tdr-check.ps1':
            out('TDR NONE'); return 0
        if base in ('kenshi-key.ps1', 'kenshi-click.ps1'):
            dr.flag('NOTE', '%s %s (injected input helper)' % (base, ' '.join(rest)))
            out('ok'); return 0
        if base in ('ctl.ps1', 'kcfg.ps1', 'install-dll.ps1', 'agent-status.ps1', 'review-verdict.ps1'):
            out('%s %s ok (dryrun)' % (base, sub)); return 0
        dr.flag('NOTE', 'powershell -File %s answered generically' % f)
        return 0
    if '-command' in low:
        c = ' '.join(a[low.index('-command') + 1:])
        dr.log('powershell', '-Command %s' % c[:100])
        if 'FreeVirtualMemory' in c:
            out('20.0 6.0'); return 0
        if 'Start-Process' in c:
            return 0
        dr.flag('NOTE', 'powershell -Command answered generically: %s' % c[:80])
        return 0
    dr.flag('NOTE', 'powershell %s' % ' '.join(a)[:80])
    return 0


# ---------------------------------------------------------------------------------------------------- misc
def dur(x):
    m = re.match(r'^([\d.]+)([smhd]?)$', x)
    if not m:
        return 0.0
    return float(m.group(1)) * {'': 1, 's': 1, 'm': 60, 'h': 3600, 'd': 86400}[m.group(2)]


def main():
    name = os.path.basename(sys.argv[0])
    a = sys.argv[1:]
    if a[:1] == ['--as']:
        name, a = a[1], a[2:]
    if name in ('ffmpeg', 'ffmpeg.exe', 'ffprobe', 'ffprobe.exe'):
        dr.log(name, ' '.join(a)[:300])
        return ffmpeg(name, a)
    if name == 'powershell.exe':
        return powershell(a)
    if name == 'sleep':
        d = sum(dur(x) for x in a)
        dr.vwait(d)
        return 0
    if name == 'date':
        if any(x.startswith(('-d', '--date', '-r', '--reference', '-s', '--set')) for x in a):
            os.execv('/bin/date', ['date'] + a)
        os.execv('/bin/date', ['date', '-d', '@%.6f' % dr.vnow()] + a)
    if name == 'quser.exe':
        out(' USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME\n>shay                  console             1  Active      none   10/10/2026 9:00 AM')
        return 0
    if name == 'tasklist.exe':
        out('kenshi_x64.exe               4242 Console                    1  6,100,000 K')
        return 0
    if name in ('cmd.exe', 'taskkill.exe', 'schtasks.exe', 'wsl.exe'):
        dr.flag('NOTE', '%s %s (not run in the dry run)' % (name, ' '.join(a)[:80]))
        return 0
    if name == 'stobe-say':
        dr.advance(0.3)
        dr.log('stobe-say', ' '.join(a))
        out('ok (dryrun)')
        return 0
    if name == 'wslpath':
        mode, args = '-u', []
        for x in a:
            if x in ('-w', '-m', '-u'):
                mode = x
            elif x != '-a':
                args.append(x)
        p = args[0] if args else ''
        if mode == '-u':
            q = dr.win_to_posix(p)
            out(q if q else p); return 0
        m = re.match(r'^/mnt/([a-z])(/.*)?$', p if p.startswith('/') else os.path.abspath(p))
        pp = p if p.startswith('/') else os.path.abspath(p)
        if m:
            w = '%s:%s' % (m.group(1).upper(), (m.group(2) or '/'))
        else:
            w = '//wsl.localhost/%s%s' % (dr.DISTRO, pp)
        out(w.replace('/', '\\') if mode == '-w' else w)
        return 0
    if name == 'cygpath':
        mode = '-u'
        rest = []
        for x in a:
            if x in ('-w', '-m', '-u', '-a'):
                mode = x if x != '-a' else mode
            else:
                rest.append(x)
        p = rest[0] if rest else ''
        if mode == '-u':
            q = dr.win_to_posix(p)
            out(q if q else p); return 0
        pp = p if p.startswith('/') else os.path.abspath(p)
        # the 4080's Git Bash fstab mounts
        pp = re.sub(r'^/mnt/d/Steam(?=/|$)', '/c/Program Files (x86)/Steam', pp)
        pp = re.sub(r'^/mnt/c(?=/|$)', '/c', pp)
        pp = re.sub(r'^/tmp(?=/|$)', '/c/Users/Shay/AppData/Local/Temp', pp)   # fstab: none /tmp usertemp
        m = re.match(r'^/([a-z])(/.*)?$', pp)
        if m and not pp.startswith('/mnt/'):
            w = '%s:%s' % (m.group(1).upper(), m.group(2) or '/')
        else:
            w = 'C:/Program Files/Git%s' % pp
        out(w.replace('/', '\\') if mode == '-w' else w)
        return 0
    sys.stderr.write('fakeexe: unknown tool %s\n' % name)
    return 127


if __name__ == '__main__':
    sys.exit(main())
