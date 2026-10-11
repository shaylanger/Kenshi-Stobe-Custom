#!/usr/bin/env python3
"""live-watch.py -- the judge behind live-watch.sh (read that header first): looks at one game frame every few seconds
while a batch runs and writes one line per flagged frame, so a broken take (black screen, frozen frame, stuck menu /
load, overlay, cursor, window gone) is seen minutes before the row's RESULT line.

  live-watch.py watch  <out-dir> [--every 5] [--checks C] [--name N] [--max-hours 12]
      live: grabs the game window (ffmpeg gdigrab, window title $WIN_TITLE, -draw_mouse 0: a GDI read of the window,
      never focuses it, never sends input) until <out>/GAMEDONE, <out>/DONE or <out>/live-watch.stop exists.
      ffmpeg.exe from $LW_FFMPEG (live-watch.sh sets it from rig-env.sh $FFX). LW_FAKE_VIDEO=<video> = take the frame
      at the watcher's own clock from that video instead (selftest / dry runs: the whole loop without a game).
  live-watch.py replay <video> <out-dir> [--every 5] [--checks C] [--name N]
      the same judge on a recording sampled every --every s (t = video time): tuning and tests.

Checks (--checks, comma list, default all):
  nowindow  the grab returned no frame (window title not found: Kenshi gone / relaunching)
  black     mean luma < 8 (crash to black, minimised / locked 4080 session; the rig_preflight threshold)
  frozen    picture unchanged (mean |diff| of a 160x90 grey copy < 0.6, stamp corner blanked) for >= FROZEN_S (60 s):
            hung game, stuck load screen, game paused mid-row
  menu      harness `status` phase (live-watch.sh polls it every 30 s into <out>/live-watch.phase, read-only) is
            menu/chargen for >= 90 s or loading for >= 180 s
  overlay   frames.py overlay cells on this frame: a text line (>= 3 cells) or a flat UI panel (>= 12 cells) outside the
            expected zones (label band, bottom UI panel, KenshiFP HUD box); panels seen in >= 80% of the last 24 samples
            are the game's own HUD (rolling baseline); text has no baseline (name tags, speech bars, popups, hint lists)
  cursor    frames.py find_cursor (Windows arrow) / find_kcursor off the screen centre (Kenshi target cursor)
Output in <out>: live-watch.txt (one line per flagged frame; a flag that stays on repeats once a minute, `still`; a
long one also gets a `cleared` line), live-watch/<check>-<HHMMSS>.jpg (800x450, the first frame of each flag run,
at most 200), live-watch.state (current open flag runs: `<check> <since-epoch> <row>`, for batch-health.sh), and the
last line of live-watch.txt + stdout: `LIVE-WATCH SUMMARY <name> samples=.. flagged=.. <check>=<runs>/<s> ... list=..`.
CPU only (ANIMLAB_GPU=0; /etc/kah-no-gpu after the 2026-10-11 BSOD): ~0.5-1 s CPU per sample.
"""
import argparse, collections, os, subprocess, sys, time

os.environ['ANIMLAB_GPU'] = '0'
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'Kenshi-Automation-Harness', 'tools', 'animlab'))
import numpy as np  # noqa: E402
import frames as FR  # noqa: E402

ALL = ('nowindow', 'black', 'frozen', 'menu', 'overlay', 'cursor')
OW, OH = FR.OW, FR.OH
BLACK_LUMA = 8.0
FROZEN_DL, FROZEN_S = 0.6, 60.0
MENU_S, LOADING_S = 90.0, 180.0
REPEAT_S = 60.0
BASE_N, BASE_MIN = 24, 6
MAX_IMGS = 200


class Judge:
    def __init__(self, checks, every):
        self.checks, self.every = set(checks), every
        self.prev, self.still_since = None, None
        self.pbase = collections.deque(maxlen=BASE_N)
        self.Z = FR.zone_mask(FR.OV_ZONES)
        self.Zs = FR.zone_mask([FR.STAMP_ZONE])

    def judge(self, t, f, phase=None):
        """list of (check, what) for frame f (OHxOWx3 int, or None = no frame) at t s; phase = (name, since_s) or None"""
        out = []
        if phase and 'menu' in self.checks:
            name, dur = phase
            if (name in ('menu', 'chargen') and dur >= MENU_S) or (name == 'loading' and dur >= LOADING_S):
                out.append(('menu', 'phase=%s for %ds' % (name, dur)))
        if f is None:
            if 'nowindow' in self.checks:
                out.append(('nowindow', 'no frame from the game window'))
            self.prev = self.still_since = None
            return out
        if FR.is_flash(f):   # harness sync_flash marker frame
            return out
        FR.blank_stamp(f)    # frame stamp corner changes every frame
        g = f.mean(-1)
        luma = float(g.mean())
        if luma < BLACK_LUMA:
            if 'black' in self.checks:
                out.append(('black', 'luma=%.1f' % luma))
            self.prev = self.still_since = None
            return out
        small = g.reshape(OH // 10, 10, OW // 10, 10).mean((1, 3))
        if self.prev is not None and float(np.abs(small - self.prev).mean()) < FROZEN_DL:
            if self.still_since is None:
                self.still_since = t - self.every
            if 'frozen' in self.checks and t - self.still_since >= FROZEN_S:
                out.append(('frozen', 'picture unchanged for %ds (luma=%.0f)' % (t - self.still_since, luma)))
        else:
            self.still_since = None
        self.prev = small
        if 'overlay' in self.checks:
            T, A, _ = FR.text_cells(f)
            P = np.zeros_like(T)
            for x0, y0, x1, y1 in FR.panel_rects(*FR.flat_cells(f)):
                P[y0:y1, x0:x1] = True
            T, A, P = T & ~self.Zs, A & ~self.Zs, P & ~self.Zs
            bp = (np.mean(self.pbase, 0) >= FR.OV_BASE_PANEL) if len(self.pbase) >= BASE_MIN else np.zeros_like(P)
            self.pbase.append(P)
            fo = T & ~self.Z
            ln = fo[:, :-2] & fo[:, 1:-1] & fo[:, 2:]
            pa = P & ~bp & ~self.Z
            if ln.any():
                ys, xs = np.nonzero(ln)
                kind = 'text-panel' if (A & ~self.Z)[ys, xs + 1].any() else 'text'
                out.append(('overlay', '%s x%d,y%d (%d cells)' % (kind, xs.min() * FR.CW, ys.min() * FR.CH, int(fo.sum()))))
            elif pa.sum() >= 12:
                ys, xs = np.nonzero(pa)
                out.append(('overlay', 'panel x%d,y%d (%d cells)' % (xs.min() * FR.CW, ys.min() * FR.CH, int(pa.sum()))))
        if 'cursor' in self.checks:
            c = FR.find_cursor(f)
            if c:
                out.append(('cursor', 'arrow x%d,y%d' % (c[0][0], c[0][1])))
            else:
                k = [(x, y) for x, y in FR.find_kcursor(f) if abs(x - OW / 2) > FR.KC_CENTRE or abs(y - OH / 2) > FR.KC_CENTRE]
                if k:
                    out.append(('cursor', 'kenshi cursor x%d,y%d' % k[0]))
        return out


class Log:
    """flag runs -> live-watch.txt lines, images, state file, summary"""
    def __init__(self, out, name, live):
        self.out, self.name, self.live = out, name, live
        self.txt = os.path.join(out, 'live-watch.txt')
        self.imgdir = os.path.join(out, 'live-watch')
        self.open = {}      # check -> [start_t, last_line_t, row, start_epoch]
        self.runs = collections.Counter(); self.secs = collections.Counter()
        self.samples = self.flagged = self.imgs = 0
        os.makedirs(out, exist_ok=True)
        with open(self.txt, 'w') as fh:
            fh.write('# live-watch %s started %s (%s)\n' % (name, time.strftime('%F %T'), 'live' if live else 'replay'))

    def _w(self, line):
        with open(self.txt, 'a') as fh:
            fh.write(line + '\n')

    def _stamp(self, t):
        return time.strftime('%H:%M:%S') if self.live else '%8.1fs' % t

    def _img(self, f, check, t):
        if f is None or self.imgs >= MAX_IMGS:
            return ''
        try:
            from PIL import Image
            os.makedirs(self.imgdir, exist_ok=True)
            p = os.path.join(self.imgdir, '%s-%s.jpg' % (check, time.strftime('%H%M%S') if self.live else '%07.1f' % t))
            Image.fromarray(np.clip(f, 0, 255).astype(np.uint8)).resize((800, 450)).save(p, quality=80)
            self.imgs += 1
            return ' img=' + p
        except Exception as e:   # no PIL on this python: lines only
            return ' img=none(%s)' % type(e).__name__

    def sample(self, t, f, flags, row):
        self.samples += 1
        if flags:
            self.flagged += 1
        now = {c: w for c, w in flags}
        for c, w in now.items():
            o = self.open.get(c)
            if o is None:
                self.open[c] = [t, t, row, time.time()]
                self.runs[c] += 1
                self._w('%s t=%ds row=%s %s %s%s' % (self._stamp(t), t, row, c, w, self._img(f, c, t)))
            elif t - o[1] >= REPEAT_S:
                o[1] = t
                self._w('%s t=%ds row=%s %s still (%ds): %s' % (self._stamp(t), t, row, c, t - o[0], w))
        for c in [c for c in self.open if c not in now]:
            self._close(c, t)
        self._state()

    def _close(self, c, t):
        o = self.open.pop(c)
        self.secs[c] += max(t - o[0], 0)
        if t - o[0] >= REPEAT_S:
            self._w('%s t=%ds row=%s %s cleared after %ds' % (self._stamp(t), t, o[2], c, t - o[0]))

    def _state(self):
        p = os.path.join(self.out, 'live-watch.state')
        with open(p + '.tmp', 'w') as fh:
            for c, o in self.open.items():
                fh.write('%s %d %s\n' % (c, o[3], o[2]))
        os.replace(p + '.tmp', p)

    def finish(self, t, why):
        for c in list(self.open):
            self._close(c, t)
        self._state()
        per = ' '.join('%s=%d/%ds' % (c, self.runs[c], self.secs[c]) for c in ALL if self.runs[c])
        s = 'LIVE-WATCH SUMMARY %s samples=%d flagged=%d %s stop=%s list=%s' % (
            self.name, self.samples, self.flagged, per or 'clean', why, self.txt)
        self._w(s)
        print(s)
        return s


def current_row(out):
    try:
        with open(os.path.join(out, 'step.pid')) as fh:
            p = fh.read().split()
        return p[1] if len(p) > 1 else '-'
    except OSError:
        return '-'


class Phase:
    """<out>/live-watch.phase (one word per poll, rewritten by live-watch.sh) -> (phase, seconds in it)"""
    def __init__(self, out):
        self.p, self.cur, self.since = os.path.join(out, 'live-watch.phase'), None, None

    def get(self):
        try:
            if time.time() - os.path.getmtime(self.p) > 120:   # poller gone / harness not answering: no menu verdict
                return None
            with open(self.p) as fh:
                ph = fh.read().strip()
        except OSError:
            return None
        if not ph:
            return None
        if ph != self.cur:
            self.cur, self.since = ph, time.time()
        return ph, int(time.time() - self.since)


def grab_gdi(ffx, title):
    cmd = [ffx, '-hide_banner', '-loglevel', 'error', '-f', 'gdigrab', '-draw_mouse', '0', '-i', 'title=' + title,
           '-frames:v', '1', '-vf', 'scale=%d:%d' % (OW, OH), '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-']
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=20, stdin=subprocess.DEVNULL)
    except (subprocess.TimeoutExpired, OSError):
        return None
    if len(r.stdout) != OW * OH * 3:
        return None
    return np.frombuffer(r.stdout, np.uint8).reshape(OH, OW, 3).astype(int)


def grab_fake(video, t):
    r = subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-ss', '%.2f' % t, '-i', video, '-frames:v', '1',
                        '-vf', 'scale=%d:%d' % (OW, OH), '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                       capture_output=True, stdin=subprocess.DEVNULL)
    if len(r.stdout) != OW * OH * 3:
        return None
    return np.frombuffer(r.stdout, np.uint8).reshape(OH, OW, 3).astype(int)


def watch(a):
    out = a.out
    J, L, P = Judge(a.checks.split(','), a.every), Log(out, a.name, True), Phase(out)
    ffx = os.environ.get('LW_FFMPEG', 'ffmpeg.exe')
    title = os.environ.get('WIN_TITLE', 'Kenshi 1.0.65 - x64 (Newland)')
    fake = os.environ.get('LW_FAKE_VIDEO')
    t0 = time.time()
    why = 'max-hours'
    while time.time() - t0 < a.max_hours * 3600:
        stop = [s for s in ('GAMEDONE', 'DONE', 'live-watch.stop') if os.path.exists(os.path.join(out, s))]
        if stop:
            why = stop[0]
            break
        ts = time.time()
        t = ts - t0
        f = grab_fake(fake, t) if fake else grab_gdi(ffx, title)
        L.sample(t, f, J.judge(t, f, P.get()), current_row(out))
        time.sleep(max(0.5, a.every - (time.time() - ts)))
    L.finish(time.time() - t0, why)


def replay(a):
    J, L = Judge(a.checks.split(','), a.every), Log(a.out, a.name, False)
    t = 0.0
    for t, f in FR.iter_frames_full(a.video, 1.0 / a.every, size=(OW, OH)):
        L.sample(t, f, J.judge(t, f), '-')
    L.finish(t, 'end-of-video')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('watch'); p.add_argument('out')
    p.add_argument('--max-hours', type=float, default=12.0)
    p = sp.add_parser('replay'); p.add_argument('video'); p.add_argument('out')
    for p in sp.choices.values():
        p.add_argument('--every', type=float, default=5.0); p.add_argument('--checks', default=','.join(ALL))
        p.add_argument('--name', default='batch')
    a = ap.parse_args()
    bad = set(a.checks.split(',')) - set(ALL)
    if bad:
        ap.error('unknown checks: %s' % ','.join(sorted(bad)))
    (watch if a.cmd == 'watch' else replay)(a)


if __name__ == '__main__':
    main()
