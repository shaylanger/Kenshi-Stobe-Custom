#!/usr/bin/env python3
"""grade_chunks.py - run the blind grading packets (score.py packets output) through ANY grader model.
Python 3 stdlib only; Windows or Linux.

You supply a command that reads the packet text on stdin and writes the grader's answer on stdout (same idea as run_point.py).
For each DIR/chunk-NN.md it
  1. builds the prompt = [optional rules file] + the packet text + a short reminder to reply with ONLY the JSON array
  2. runs your command once (a FRESH session per chunk: no memory across chunks; use a model that is neither arm under test)
  3. finds the JSON array in the answer, checks every object (id, A, B with a valid class, truth_ok) and writes OUT/chunk-NN.json
Anything wrong is reported on the console and in OUT/grade-status.csv; a bad chunk is simply re-run with --redo (graders vary, so a re-run
may give different grades: record that you did it).

  python grade_chunks.py --packets runs/mymodel-vs-S/packets --cmd "claude -p --model <id>" --out runs/mymodel-vs-S/grades \
         --context ../data/context/CLAUDE.md --parallel 3 [--first 1] [--redo] [--timeout 1800]

The packet tells the grader it may read the full input of a point from a path; a grader without file access just uses the abridged
situation in the packet (that is how this suite is meant to be usable with any model). The blind key (key.json) is never read here.
Output files are named chunk-NN.json, which is what `score.py aggregate --grades OUT` expects.
"""
import argparse, concurrent.futures, csv, glob, json, os, re, subprocess, sys, time

CLASSES = {'equivalent', 'acceptable-different', 'worse', 'harmful'}
TAIL = ("\n\n======================================================================\n"
        "REMINDER: reply with ONLY the JSON array described under OUTPUT (no prose, no code fence). You cannot run commands in this task.\n")
HEAD = ("STANDING PROJECT RULES (the project's CLAUDE.md that the packet below refers to).\n\n")


def find_array(text):
    """Return the first top-level JSON array in text that parses, else None."""
    t = text.strip()
    try:
        v = json.loads(t)
        if isinstance(v, list):
            return v
    except ValueError:
        pass
    dec = json.JSONDecoder()
    for m in re.finditer(r'\[', text):
        try:
            v, _ = dec.raw_decode(text[m.start():])
        except ValueError:
            continue
        if isinstance(v, list) and v and isinstance(v[0], dict) and 'id' in v[0]:
            return v
    return None


def check(arr, expect_ids):
    pr = []
    seen = set()
    for g in arr:
        if not isinstance(g, dict) or 'id' not in g:
            pr.append('entry without id'); continue
        seen.add(g['id'])
        for lab in ('A', 'B'):
            x = g.get(lab)
            if not isinstance(x, dict) or x.get('class') not in CLASSES:
                pr.append('%s %s: bad or missing class' % (g['id'], lab))
            elif x.get('class') == 'harmful' and not x.get('clause'):
                pr.append('%s %s: harmful without clause letter' % (g['id'], lab))
        if g.get('truth_ok') not in (True, False):
            pr.append('%s: truth_ok missing' % g['id'])
    miss = sorted(set(expect_ids) - seen)
    if miss:
        pr.append('missing points: ' + ','.join(miss))
    return pr


def one(args, f):
    name = os.path.splitext(os.path.basename(f))[0]
    outf = os.path.join(args.out, name + '.json')
    if os.path.exists(outf) and not args.redo:
        return name, 'skipped (exists)', 0.0
    text = open(f, encoding='utf-8').read()
    ids = re.findall(r'^### POINT (P\d+|L\d+)', text, re.M)
    prompt = (HEAD + open(args.context, encoding='utf-8').read() + "\n\n=== END OF RULES ===\n\n" if args.context else '') + text + TAIL
    # the packet may tell the grader to write a file; tell it where, so a grader WITH file tools also works
    prompt = prompt.replace('{outfile}', outf)
    cmd = args.cmd.replace('{PROMPT_FILE}', f)
    t0 = time.time()
    try:
        r = subprocess.run(cmd, shell=True, input=prompt.encode('utf-8'), capture_output=True, timeout=args.timeout)
        so = r.stdout.decode('utf-8', 'replace'); se = r.stderr.decode('utf-8', 'replace')
    except subprocess.TimeoutExpired:
        return name, 'timeout', time.time() - t0
    wall = time.time() - t0
    open(os.path.join(args.out, 'raw', name + '.txt'), 'w', encoding='utf-8').write(so)
    open(os.path.join(args.out, 'raw', name + '.err.txt'), 'w', encoding='utf-8').write(se)
    arr = None
    # a grader with file tools may have written outf itself; otherwise take stdout
    arr = find_array(so)
    if arr is None and os.path.exists(outf):
        try:
            arr = json.load(open(outf, encoding='utf-8'))
        except ValueError:
            arr = None
    if arr is None:
        return name, 'no JSON array in answer', wall
    pr = check(arr, ids)
    with open(outf, 'w', encoding='utf-8') as fo:
        json.dump(arr, fo, indent=1)
    return name, ('ok' if not pr else 'PROBLEMS: ' + '; '.join(pr[:6])), wall


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--packets', required=True, help='directory with chunk-NN.md (score.py packets --out)')
    ap.add_argument('--cmd', required=True, help='shell command: packet on stdin, answer on stdout; {PROMPT_FILE} = path of the chunk file')
    ap.add_argument('--out', required=True, help='directory for chunk-NN.json (score.py aggregate --grades)')
    ap.add_argument('--context', help='rules file shown before every packet (data/context/CLAUDE.md)')
    ap.add_argument('--parallel', type=int, default=1)
    ap.add_argument('--timeout', type=int, default=1800)
    ap.add_argument('--first', type=int, help='only the first N chunks')
    ap.add_argument('--redo', action='store_true', help='re-grade chunks that already have an output file')
    args = ap.parse_args()
    os.makedirs(os.path.join(args.out, 'raw'), exist_ok=True)
    files = sorted(glob.glob(os.path.join(args.packets, 'chunk-*.md')))
    if args.first:
        files = files[:args.first]
    if not files:
        sys.exit('no chunk-*.md in ' + args.packets)
    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.parallel)) as ex:
        for name, st, wall in ex.map(lambda f: one(args, f), files):
            print('%s %s (%.0f s)' % (name, st, wall)); rows.append((name, st, '%.1f' % wall))
    with open(os.path.join(args.out, 'grade-status.csv'), 'a', newline='', encoding='utf-8') as f:
        csv.writer(f).writerows(rows)
    bad = [r for r in rows if not (r[1] == 'ok' or r[1].startswith('skipped'))]
    print('%d chunks, %d need attention' % (len(rows), len(bad)))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
