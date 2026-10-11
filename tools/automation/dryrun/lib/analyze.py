#!/usr/bin/env python3
"""analyze.py <row out dir> <name> <rig> <command> [--norec]
Verdict of one dry-run row from what the sandbox left in <row out dir> (out.txt, rc.txt, flags.log, calls.log,
recordings.jsonl, labels/*). Prints exactly one line:  DRYRUN <name> PASS|FAIL <reasons> (...) log=<dir>
FAIL reasons, in order: stub/tool flags (unknown command, bad args, missing files, POSIX path to a Windows exe, 4080
fifo/wslpath/python path, focus, no -draw_mouse 0, ...); shell errors in the output; RESULT lines (none, more than one
per row, or a FAIL: in the fake game every setup check passes, so a FAIL is a script bug); no recording call at all
(steps never ran); recordings with chatter on or the cursor not parked (bark text / hover name tag in frame), filmed at night, or with
hostiles / a combat popup near the spot (bug-replay fixtures, dryrun.sh --fixture); label
files out of order, negative or past the end of the recording; unquoted path variables (4080: KDIR has spaces)."""
import json, os, re, sys

d, name, rig, cmd = sys.argv[1:5]
norec = '--norec' in sys.argv
R = lambda f: os.path.join(d, f)


def read(f):
    try:
        return open(R(f), errors='replace').read()
    except OSError:
        return ''


fails, notes = [], []
for l in read('flags.log').splitlines():
    sev, _, t = l.partition(' ')
    (fails if sev == 'FAIL' else notes).append(t)
outp = read('out.txt')
ERR = re.compile(r'No such file or directory|command not found|ambiguous redirect|syntax error|unbound variable|'
                 r'binary operator expected|integer expression expected|unary operator expected|too many arguments|'
                 r'Permission denied|Broken pipe|Traceback \(most recent call last\)|bad substitution|cannot execute|'
                 r'Is a directory|No such process')
for l in outp.splitlines():
    if ERR.search(l) and not l.startswith('RESULT '):
        fails.append('shell error: ' + l.strip()[:160])
rc = read('rc.txt').strip()
if rc == '124':
    fails.append('row timed out in the dry run (a wait loop that never ends?)')
# run-batch.sh splits the row command on spaces with no quote handling (read -r -a): FIST_SPOT="-54190 633 4380" became
# FIST_SPOT="-54190 + a command "633" (fist4080c, 2026-10-10), while the sandbox ran it through a shell and passed
# since 2026-10-10 run-batch.sh row_split handles quotes (dryrun.sh + row.sh split the same way): no quote check here
# RESULT lines
res =[l for l in outp.splitlines() if l.startswith('RESULT ')]
rows = {}
for l in res:
    p = l.split()
    rows.setdefault(p[1] if len(p) > 1 else '?', []).append(l)
if not res:
    fails.append('no RESULT line (exit %s): %s' % (rc, (outp.strip().splitlines() or [''])[-1][:120]))
# every row a ROWS=<a,b,...> selector asks for must end in its own RESULT line (op-pt1 2026-10-10: a skipped row printed
# nothing; "no RESULT line" is a script bug)
m = re.search(r'(?:^|\s)ROWS=(?:"([^"]*)"|\'([^\']*)\'|(\S+))', cmd)
if m and res:
    want = next(g for g in m.groups() if g is not None)
    for r in [x for x in re.split(r'[,\s]+', want) if x]:
        if r not in rows:
            fails.append('no RESULT line for requested row %s (ROWS=%s)' % (r, want))
for r, ls in rows.items():
    if len(ls) > 1:
        fails.append('%d RESULT lines for %s' % (len(ls), r))
for l in res:
    if re.match(r'^RESULT \S+ FAIL', l):
        fails.append('script reported: ' + l[:200])
# recordings
recs = []
for l in read('recordings.jsonl').splitlines():
    try:
        recs.append(json.loads(l))
    except ValueError:
        pass
vids = [r for r in recs if r.get('kind') == 'video']
if not recs and not norec:
    fails.append('no recording call (no gdigrab video, screenshot or fp_vm rec dump): the take steps never ran')
for v in vids:
    if v.get('len', 0) > 3:
        if v.get('chatter') != 'off':
            fails.append('recording %s with chatter on (NPC bark text in frame): `stobe-auto chatter off` first' % os.path.basename(v['file']))
        f = os.path.basename(v['file'])
        if v.get('night'):
            fails.append('recording %s filmed at night (game hour %.1f): pf_day before the recorder starts' % (f, v.get('hour', -1)))
        if v.get('hostiles'):
            fails.append('recording %s with hostiles within 30 m of the take spot (%s)%s: pf_clean + pf_area before filming' % (
                f, ', '.join(v['hostiles'][:3]), ' and popup "%s" in frame' % v['popup'] if v.get('popup') else ''))
        rw, rh = int(os.environ.get('RES_W') or 1600), int(os.environ.get('RES_H') or 900)   # render size (rig-env.sh)
        c = v.get('cursor') or [rw // 2, rh // 2]
        if not (c[1] <= 40 or c[0] <= 20 or c[0] >= rw - 20 or c[1] >= rh - 20):
            fails.append('recording %s without the cursor parked at the edge (hover name tag): mouse_inject at %d 4 / pf_open' % (os.path.basename(v['file']), rw - 5))
# labels
vmax = max([v['len'] for v in vids] or [0])
ld = R('labels')
for f in sorted(os.listdir(ld)) if os.path.isdir(ld) else []:
    prev, issues = None, []
    for i, l in enumerate(open(os.path.join(ld, f), errors='replace').read().splitlines(), 1):
        m = re.match(r'^\s*(-?\d+(?:\.\d+)?)\s+(.*)$', l)
        if not m:
            continue
        t = float(m.group(1))
        if t < 0:
            issues.append('negative time at line %d' % i)
        if prev is not None and t < prev - 1e-6:
            issues.append('out of order at line %d (%.2f after %.2f)' % (i, t, prev))
        if vids and t > vmax + 1.0:
            issues.append('"%s" at %.2f s is after the recording ended (%.1f s)' % (m.group(2)[:40], t, vmax))
        prev = t
    if issues:
        fails.append('labels %s: %s' % (f.split('_')[-1], '; '.join(issues[:2])))
# static: unquoted path variables in the row's script(s)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint  # noqa: E402
for sev, t in lint.lint_cmd(cmd, rig):
    (fails if sev == 'FAIL' else notes).append(t)
seen, uniq = set(), []
for f in fails:
    k = re.sub(r'\d+(\.\d+)?', '#', f)
    if k not in seen:
        seen.add(k); uniq.append(f)
calls = len(read('calls.log').splitlines())
tail = '(rig %s, %d calls, %d videos, %d recs, %d notes) log=%s' % (rig, calls, len(vids), len(recs), len(notes), d)
print('DRYRUN %s %s %s %s' % (name, 'FAIL' if uniq else 'PASS', ' | '.join(uniq[:4]) + (' | +%d more' % (len(uniq) - 4) if len(uniq) > 4 else ''), tail))
with open(R('verdict.txt'), 'w') as f:
    f.write('\n'.join(['FAIL ' + x for x in uniq] + ['NOTE ' + x for x in notes]) + '\n')
