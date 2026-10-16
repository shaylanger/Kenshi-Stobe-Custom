"""shadow-wait <arm> [--timeout S]: block until the feed has a batch newer than this arm's cursor, print it, advance the cursor.
Prints 'NO NEW EVENTS' after the timeout (default 90 s, max 100) and 'END' when the feeder ended and everything was printed.
Cursor: <shadow dir>\\cursor-<arm>.txt (last printed batch_id), advanced only when batches are printed."""
import os, sys, time
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shadow_lib import shadow_dir, read_jsonl, check_arm, now_iso

MAX_BATCHES_PER_CALL = 4


def fmt_batch(b):
    lines = ['=== BATCH %s ts=%s events=%d ===' % (b['batch_id'], b.get('ts'), len(b.get('events', [])))]
    for e in b.get('events', []):
        ts = (e.get('ts') or '')[11:19]
        lines.append('[%s %s %sZ] %s' % (e['id'], e['kind'], ts, e['text']))
    return '\n'.join(lines)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    timeout = 90.0
    if '--timeout' in sys.argv:
        timeout = float(sys.argv[sys.argv.index('--timeout') + 1])
        args = [a for a in args if a != sys.argv[sys.argv.index('--timeout') + 1]]
    timeout = min(timeout, 100.0)
    if not args:
        raise SystemExit('usage: shadow-wait.sh <H|S> [--timeout S]')
    arm = check_arm(args[0])
    d = shadow_dir()
    cur_f = os.path.join(d, 'cursor-%s.txt' % arm)
    try:
        cur = int(open(cur_f).read().strip() or 0)
    except (OSError, ValueError):
        cur = 0
    feed = os.path.join(d, 'feed.jsonl')
    t0 = time.time()
    while True:
        recs = read_jsonl(feed)
        batches = [r for r in recs if 'batch_id' in r and r['batch_id'] > cur]
        batches.sort(key=lambda r: r['batch_id'])
        ended = any(r.get('end') for r in recs)
        if batches:
            out = batches[:MAX_BATCHES_PER_CALL]
            print('\n\n'.join(fmt_batch(b) for b in out))
            if len(batches) > len(out):
                print('\n[%d more batch(es) already waiting: call shadow-wait again right away]' % (len(batches) - len(out)))
            with open(cur_f, 'w') as f:
                f.write(str(out[-1]['batch_id']))
            return
        if ended:
            print('END')
            return
        if time.time() - t0 >= timeout:
            print('NO NEW EVENTS (cursor=%d, %s)' % (cur, now_iso()))
            return
        time.sleep(2.0)


if __name__ == '__main__':
    main()
