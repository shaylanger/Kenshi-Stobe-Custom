"""dr.py -- shared bits of the take dry-run fake game (tools/automation/dryrun): virtual clock, call/flag logs, locking,
path forms. Everything lives in $DR_STATE (a tmpfs inside the row's sandbox, see sandbox.sh)."""
import fcntl, json, os, re, time

ST = os.environ.get('DR_STATE', '/tmp/dr-state')
RIG = os.environ.get('DR_RIG', '5090')
CR = '/c' if RIG == '4080' else '/mnt/c'
KDIR = os.environ.get('DR_KDIR', '/mnt/d/Steam/steamapps/common/Kenshi')
CANNED = os.environ.get('DR_CANNED', '/dryrun/canned')
DISTRO = os.environ.get('DR_DISTRO', 'DwemerAI4Skyrim3')


_depth = [0, None]


class Lock:
    """process-wide reentrant exclusive lock on $DR_STATE/lock"""
    def __enter__(self):
        if _depth[0] == 0:
            _depth[1] = open(os.path.join(ST, 'lock'), 'a+')
            fcntl.flock(_depth[1], fcntl.LOCK_EX)
        _depth[0] += 1
        return self

    def __exit__(self, *a):
        _depth[0] -= 1
        if _depth[0] == 0:
            fcntl.flock(_depth[1], fcntl.LOCK_UN)
            _depth[1].close()


def _offset():
    try:
        return float(open(os.path.join(ST, 'clock')).read().strip() or 0)
    except (OSError, ValueError):
        return 0.0


def vnow():
    """virtual epoch seconds: real time + the sleeps / harness latency the dry run skipped."""
    return time.time() + _offset()


def _write_offset(o):
    # atomic: readers (vnow, no lock) must never see an empty file (= offset 0 = time going back)
    p = os.path.join(ST, 'clock')
    with open(p + '.%d' % os.getpid(), 'w') as f:
        f.write('%.6f' % o)
    os.replace(p + '.%d' % os.getpid(), p)


def advance(d):
    if d <= 0:
        return
    with Lock():
        _write_offset(_offset() + d)


def advance_to(t):
    """move the virtual clock forward to t (never back)"""
    with Lock():
        d = t - vnow()
        if d > 0:
            _write_offset(_offset() + d)


def busy(samples=4):
    """True if another process in the sandbox (own pid namespace) is running: the foreground is between two waits
    (bash forking the next command, a tool starting). Sampled a few times: a fork/exec gap shows up as 'R'."""
    me = os.getpid()
    for i in range(samples):
        for p in os.listdir('/proc'):
            if not p.isdigit() or int(p) == me:
                continue
            try:
                st = open('/proc/%s/stat' % p).read()
            except OSError:
                continue
            if st[st.rindex(')') + 2] in 'RD':
                return True
        time.sleep(0.004)
    return False


def vwait(d, idle=0.06):
    """virtual sleep: a discrete-event wait. Every waiter (sleep, a time-limited recording) registers its wake time;
    the clock only jumps to the EARLIEST registered wake time, and only after the clock was idle for `idle` s of real time
    (nobody else made a harness call / slept meanwhile). So a background `( sleep 15; ... ) &` wakes when the foreground
    has used up 15 virtual seconds, not 15 s early (zoom-sweep's re-press), and concurrent loops interleave like in
    the game."""
    if d <= 0:
        return
    wake = vnow() + d
    sd = os.path.join(ST, 'sleepers')
    os.makedirs(sd, exist_ok=True)
    me = os.path.join(sd, '%d.%d' % (os.getpid(), int(time.time() * 1e6) % 1000000))
    with open(me, 'w') as f:
        f.write('%.6f' % wake)
    try:
        last, t_idle = clock_mtime(), time.time()
        while vnow() < wake:
            time.sleep(0.005)
            m = clock_mtime()
            if m != last:
                last, t_idle = m, time.time()
                continue
            if time.time() - t_idle < idle:
                continue
            mins = []
            for n in os.listdir(sd):
                pid = int(n.split('.')[0])
                if not os.path.exists('/proc/%d' % pid):
                    try:
                        os.remove(os.path.join(sd, n))
                    except OSError:
                        pass
                    continue
                try:
                    mins.append(float(open(os.path.join(sd, n)).read() or 'inf'))
                except (OSError, ValueError):
                    pass
            if (not mins or wake <= min(mins) + 1e-6) and not busy():
                advance_to(wake)
                break
    finally:
        try:
            os.remove(me)
        except OSError:
            pass


def clock_mtime():
    try:
        return os.path.getmtime(os.path.join(ST, 'clock'))
    except OSError:
        return 0.0


def log(kind, text):
    """one line per call: <virtual s since the row started> <kind> <text>"""
    t0 = float(os.environ.get('DR_T0', '0') or 0)
    with open(os.path.join(ST, 'calls.log'), 'a') as f:
        f.write('%.2f\t%s\t%s\n' % (vnow() - t0, kind, text.replace('\n', ' ')[:400]))


def flag(sev, text):
    """sev FAIL (the row fails dry-run) or NOTE (reported only)"""
    with open(os.path.join(ST, 'flags.log'), 'a') as f:
        f.write('%s %s\n' % (sev, text.replace('\n', ' ')[:300]))
    log('FLAG', '%s %s' % (sev, text))


def jappend(name, obj):
    with open(os.path.join(ST, name), 'a') as f:
        f.write(json.dumps(obj) + '\n')


def jread(name):
    p = os.path.join(ST, name)
    out = []
    if os.path.exists(p):
        for l in open(p):
            try:
                out.append(json.loads(l))
            except ValueError:
                pass
    return out


def win_to_posix(p):
    """a Windows path as a Windows tool sees it -> the sandbox path; None if it is not a Windows path."""
    m = re.match(r'^\\\\wsl(?:\.localhost|\$)\\[^\\]+(\\.*)?$', p)
    if m:
        return (m.group(1) or '\\').replace('\\', '/')
    m = re.match(r'^([A-Za-z]):[\\/](.*)$', p)
    if m:
        d, rest = m.group(1).lower(), m.group(2).replace('\\', '/')
        if RIG == '4080' and d == 'c' and rest.lower().startswith('users/shay/appdata/local/temp'):
            return '/tmp' + rest[len('users/shay/appdata/local/temp'):]   # Git Bash fstab: /tmp = the user temp dir
        return ('/%s/%s' % (d, rest)) if RIG == '4080' else ('/mnt/%s/%s' % (d, rest))
    return None


def winexe_path(arg, cwd=None):
    """resolve a path argument given to a Windows exe (ffmpeg.exe, powershell.exe -File, Windows python on the 4080).
    Returns (posix path or None, problem or None). 5090/WSL: args are passed unchanged, so a POSIX path is wrong.
    4080/Git Bash: MSYS converts /c/... args to C:\\..., and the fstab mounts /mnt/c, /mnt/d/Steam the same way."""
    w = win_to_posix(arg)
    if w is not None:
        return w, None
    if arg.startswith('/'):
        if RIG == '4080':
            # MSYS converts mounted POSIX paths (fstab: /mnt/c, /mnt/d/Steam; /c; /tmp) for native exes
            if arg.startswith('/mnt/') and not (arg.startswith('/mnt/c/') or arg.startswith('/mnt/d/Steam/')):
                return None, 'path %s does not exist on the 4080 (its Git Bash mounts only /mnt/c and /mnt/d/Steam)' % arg
            return arg, None
        return None, 'POSIX path %s handed to a Windows exe (WSL passes it unchanged: wslpath -w it)' % arg
    return os.path.join(cwd or os.getcwd(), arg), None
