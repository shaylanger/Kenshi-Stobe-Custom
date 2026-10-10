#!/usr/bin/env python3
"""take_sample.py -- evidence sampler for labelled KenshiFP video takes (started by take-sample.sh; judged by the
harness's tools/animlab/takecheck.py with take-rules.txt).

One harness round trip per sample: fp_keys state, fp_combat state, where <fp char>, chars, messages go into ONE inbox
write (kah.send_many), so a sample costs one 250 ms harness poll instead of five and leaves the other polls to the take
script (the 2026-10-10 first take: 5 separate stobe-auto calls per sample gave gaps up to 3.1 s and slowed the take).
Writes per sample (t = seconds since T0, midpoint of the round trip):
  <t> fp ui_state=.. hud_text=.. loaded=.. fp_ui_state=..
  <t> world near=<other chars within R m of the fp char> nearest=<m|none> down=<dead/KO among them> msgs=<new> [msg=..]
Squad members (the fp character's faction) and `allow` substrings ('|'-separated, e.g. the dummy's handle) never count.
Usage: take_sample.py <ev file> <T0 epoch s> <fp char> [allow] [--dt 0.6] [--r 20] [--run <file: sample while it exists>]
Default (2026-10-10): the harness `sampler` runs the queries on the game thread every min(dt, 0.3) s (immune to WSL load;
times mapped to the local clock by the estimated offset); falls back to client polling on a harness without it, with
--poll, or TAKE_SAMPLER=0.
"""
import argparse, os, re, sys, time

HARN_CLIENT = os.environ.get('KAH_CLIENT', '/mnt/c/KenshiModding/Kenshi-Automation-Harness/client')
sys.path.insert(0, HARN_CLIENT)
import kah  # noqa: E402

POS = re.compile(r'(#\d+/\d+) \[([^\]]*)\] pos=([-\d.]+),([-\d.]+),([-\d.]+)')


def grab(text, keys):
    return ' '.join(m.group(0) for k in keys for m in [re.search(r'(?:^| )%s=\S*' % k, text)] if m).replace('  ', ' ').strip()


def parse_where(text):
    m = POS.search(text)
    return (m.group(2), tuple(float(m.group(i)) for i in (3, 4, 5))) if m else (None, None)


def parse_chars(text, fac, me, r, allow):
    body = text.split(': ', 1)[1] if ': ' in text else ''
    n, down, best = 0, 0, None
    for e in body.split(' | ') if body.strip() else []:
        m = POS.search(e)
        if not m or (fac is not None and m.group(2) == fac) or any(a and a in e for a in allow):
            continue
        p = tuple(float(m.group(i)) for i in (3, 4, 5))
        d = sum((p[i] - me[i]) ** 2 for i in range(3)) ** 0.5
        if d > r:
            continue
        n += 1
        tail = e[m.end():]
        if re.search(r' (DEAD|KO)\b', tail):
            down += 1
        best = d if best is None or d < best else best
    return 'near=%d nearest=%s down=%d' % (n, 'none' if best is None else '%.1f' % best, down)


def parse_messages(text):
    """(count since launch, [last entries])"""
    m = re.match(r'(\d+) message\(s\) since launch', text)
    if not m:
        return None, []
    body = re.sub(r' \((hook: [^)]*|message hook not installed)\)$', '', text[m.end():])
    return int(m.group(1)), [x.strip() for x in body.split(' | ') if x.strip()]


def queries(me, r):
    return [('fp_keys', ['state']), ('fp_combat', ['state']), ('where', [me]), ('chars', [str(int(r) + 60)]),
            ('messages', ['20'])]


def sample(d, me, r, allow, prev):
    return lines_of([x[1] for x in kah.send_many(d, queries(me, r), timeout=5)], r, allow, prev)


def lines_of(R, r, allow, prev):
    """the 5 query replies (queries() order) -> (fp line, world line)"""
    fp = grab(R[0], ('ui_state', 'hud_text')) + ' ' + grab(R[1], ('loaded', 'fp_ui_state'))
    fac, pos = parse_where(R[2])
    world = parse_chars(R[3], fac, pos, r, allow) if pos else 'near=? nearest=? down=?'
    cnt, ent = parse_messages(R[4])
    if cnt is None:
        msgs = 'msgs=?'
    else:
        new = 0 if prev[0] is None else max(0, cnt - prev[0])
        prev[0] = cnt
        msgs = 'msgs=%d' % new + ''.join(' msg=' + re.sub(r'^\d\d:\d\d:\d\d ', '', x).replace(' ', '_') for x in ent[len(ent) - new:] if new)
    return fp.strip(), world + ' ' + msgs


EPOCH = re.compile(r'\bepoch=([\d.]+)')


def clock_offset(d):
    """harness clock - local clock (s) from the min-RTT of 3 `sampler status` calls, or None (old harness: no sampler).
    Only |offset| > 0.25 s is applied: the client sees a reply up to one 0.2 s outbox poll late."""
    best = None
    for _ in range(3):
        t1 = time.time()
        ok, txt = kah.send_many(d, [('sampler', ['status'])], timeout=5)[0]
        t2 = time.time()
        m = EPOCH.search(txt) if ok else None
        if not m:
            return None
        if best is None or t2 - t1 < best[0]:
            best = (t2 - t1, float(m.group(1)) - (t1 + t2) / 2)
    return best[1] if abs(best[1]) > 0.25 else 0.0


def sampler_mode(a, d, allow):
    """The harness runs the 5 queries on the game thread every <ms> (harness `sampler`, 2026-10-10): at WSL load 23-60
    the client polls came 1.0-1.7 s apart while the game ran smoothly, so takecheck's cover rule failed takes for the
    sampler's own lateness (op-blkK). A gap in the sampler file is a real game stall. Returns None to fall back to
    client polling (harness without `sampler`, or it would not start)."""
    off = clock_offset(d)
    if off is None:
        return None
    name = 'sampler-%d.txt' % os.getpid()
    path = os.path.join(d, name)
    ms = max(50, int(round(1000 * min(a.dt, 0.3))))
    qs = [' '.join([c] + args) for c, args in queries(a.me, a.r)]
    ok, txt = kah.send_many(d, [('sampler', ['start', str(ms), name] + qs)], timeout=5)[0]
    if not ok or not txt.startswith('sampler on'):
        sys.stderr.write('take_sample: sampler start failed (%s), polling instead\n' % txt)
        return None
    sys.stderr.write('take_sample: harness sampler %s offset=%.3f\n' % (txt, off))
    prev, pos, group, n = [None], 0, [None, {}], [0]

    def emit(out):
        t, R = group
        if t is not None and len(R) == 5:
            fp, world = lines_of([R[i] for i in range(5)], a.r, allow, prev)
            tt = t - off - a.t0
            out.write('%.2f fp %s\n%.2f world %s\n' % (tt, fp, tt, world)); n[0] += 1

    def drain(out):
        try:
            with open(path, 'rb') as f:
                f.seek(pos)
                data = f.read()
        except OSError:
            return pos
        end = data.rfind(b'\n') + 1
        for raw in data[:end].decode('utf-8', errors='replace').splitlines():
            p = raw.split('\t', 2)
            if len(p) != 3:
                continue
            try:
                t, i = float(p[0]), int(p[1])
            except ValueError:
                continue
            if t != group[0]:
                emit(out)
                group[0], group[1] = t, {}
            group[1][i] = p[2]
        return pos + end

    import signal
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    with open(a.ev, 'a', buffering=1) as out:
        try:
            while a.run is None or os.path.exists(a.run):
                pos = drain(out)
                time.sleep(0.3)
        finally:
            kah.send_many(d, [('sampler', ['stop'])], timeout=5)
            pos = drain(out)
            emit(out)
            try:
                os.remove(path)
            except OSError:
                pass
            sys.stderr.write('take_sample: harness sampler wrote %d samples\n' % n[0])
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('ev'); ap.add_argument('t0', type=float); ap.add_argument('me'); ap.add_argument('allow', nargs='?', default='')
    ap.add_argument('--dt', type=float, default=float(os.environ.get('TAKE_DT', 0.6)))
    ap.add_argument('--r', type=float, default=float(os.environ.get('TAKE_R', 20)))
    ap.add_argument('--run', help='sample while this file exists'); ap.add_argument('--count', type=int, help='stop after n samples (tests)')
    ap.add_argument('--poll', action='store_true', help='client polling only (no harness game-thread sampler)')
    a = ap.parse_args()
    d, _ = kah.harness_dir([])
    allow = [x for x in a.allow.split('|') if x]
    if not a.poll and os.environ.get('TAKE_SAMPLER', '1') != '0' and a.count is None:
        rc = sampler_mode(a, d, allow)
        if rc is not None:
            return rc
    prev, k = [None], 0
    with open(a.ev, 'a', buffering=1) as out:
        while (a.run is None or os.path.exists(a.run)) and (a.count is None or k < a.count):
            t1 = time.time()
            fp, world = sample(d, a.me, a.r, allow, prev)
            t2 = time.time(); t = (t1 + t2) / 2 - a.t0
            out.write('%.2f fp %s\n%.2f world %s\n' % (t, fp, t, world)); k += 1
            time.sleep(max(0.0, a.dt - (time.time() - t1)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
