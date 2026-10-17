#!/usr/bin/env python3
"""run_point.py - feed replay points to ANY model through a shell command (Python 3 stdlib only; Windows or Linux).

You supply a command that reads the prompt on stdin and writes the model's answer on stdout. Examples (all yours to adapt):
  --cmd "claude -p --model <id>"                      (any CLI that takes the prompt on stdin)
  --cmd "codex exec -m <id> -c model_reasoning_effort=high -"
  --cmd "python my_api_call.py"                       (your own script that calls a vendor API and prints the text)
  --cmd "cat {PROMPT_FILE} | some-cli"                (the literal text {PROMPT_FILE} is replaced by the prompt file path)

What it does, per point (P001 .. P120), in fixed order (--parallel only changes how many run at once):
  1. builds the prompt = [optional context file] + the point's .input.md   (see --context; the baseline gave the model the project's CLAUDE.md)
  2. runs your command once (one run per cell, NO retries; failures are recorded, never re-run unless you pass --redo)
  3. saves raw stdout, a per-run record (start/end time, exit code, durations, token usage if your command reports it) and,
     when the answer parses as the decision JSON, the decision file.
Output layout under --out:
  raw/P###.txt        exact stdout (stderr in raw/P###.err.txt)
  prompts/P###.txt    exact prompt sent
  runs/P###.run.json  record: pid, start, end, wall_s, exit_code, timed_out, status, schema_problems, usage, model/effort labels
  decisions/P###.json parsed decision (only when status = ok)  <- feed this directory to score.py as --arm LABEL=<out>
  results.csv         one row per point: pid,status,exit_code,start,end,wall_s,in,out,cache_r,cache_w,tokens_estimated,schema_problems

Token usage: if your command prints a line `USAGE {"in": N, "out": N, "cache_r": N, "cache_w": N}` on STDERR (last such line wins) it is
recorded exactly. Otherwise the prompt/answer sizes are estimated as characters/3.5 and marked tokens_estimated=1; replace them from
the vendor's usage page / API response if you need exact cost (see ../05-runbook-new-model.md).

Usage:
  python run_point.py --points ../data/replay/points --cmd "<command>" --parallel 4 --out runs/mymodel-high \\
         --context ../data/context/CLAUDE.md --model-label "<exact model id>" --effort-label high [--first 3] [--ids P001,P002] [--timeout 600]
"""
import argparse, csv, concurrent.futures, datetime, json, os, re, subprocess, sys, tempfile, time

TYPES = {'ack', 'spawn', 'message-agent', 'message-shay', 'hold-lane', 'release-lane', 'restart-waker', 'ignore',
         'mark-row', 'edit-file', 'commit', 'wait', 'stop-agent', 'run'}
CLASSES = {'relay', 'setup-fail', 'lane-alert', 'waker-digest', 'shay-message', 'stop-hook', 'agent-stopped',
           'build-compose', 'other'}

CONTEXT_HEAD = ("STANDING PROJECT RULES (the CLAUDE.md file of the project; the replay task below says you already know these rules - this is them).\n"
                "Treat it as background knowledge, not as the task.\n\n")
CONTEXT_TAIL = "\n\n======================================================================\nEND OF STANDING PROJECT RULES. THE REPLAY TASK FOLLOWS.\n======================================================================\n\n"
FOOTER = ("\n\nANSWER FORMAT REMINDER: reply with ONLY the single JSON object described above - no prose before or after, no code fence. "
          "You cannot run commands or read files in this task; everything you need is in this message.\n")


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')


def check_schema(c):
    pr = []
    if not isinstance(c, dict):
        return ['not an object']
    if c.get('event_class') not in CLASSES:
        pr.append('bad event_class')
    d = c.get('decision')
    if not isinstance(d, list) or not d:
        pr.append('decision missing/empty')
    else:
        for i, a in enumerate(d):
            if not isinstance(a, dict) or a.get('type') not in TYPES:
                pr.append('action %d bad type' % i)
            elif not isinstance(a.get('exact_command_or_message', ''), str):
                pr.append('action %d bad text' % i)
    if 'checks' in c and not isinstance(c['checks'], list):
        pr.append('checks not a list')
    return pr


def parse_decision(text):
    """Strict-ish: whole text, or text inside one code fence, or the first balanced {...} object. Returns (obj or None, note)."""
    t = text.strip()
    cands = [t]
    m = re.search(r'```(?:json)?\s*(\{.*\})\s*```', t, re.S)
    if m:
        cands.append(m.group(1))
    i = t.find('{')
    while i != -1:
        depth = 0; instr = False; esc = False
        for j in range(i, len(t)):
            ch = t[j]
            if instr:
                if esc:
                    esc = False
                elif ch == '\\':
                    esc = True
                elif ch == '"':
                    instr = False
            elif ch == '"':
                instr = True
            elif ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    cands.append(t[i:j + 1]); break
        i = t.find('{', i + 1) if len(cands) < 6 else -1
    for k, c in enumerate(cands):
        try:
            o = json.loads(c)
        except ValueError:
            continue
        if isinstance(o, dict) and 'decision' in o:
            return o, ('clean' if k == 0 else 'extracted-from-prose')
    return None, 'no decision JSON found'


def build_prompt(args, pid):
    with open(os.path.join(args.points, pid + '.input.md'), encoding='utf-8') as f:
        body = f.read()
    ctx = ''
    if args.context and os.path.exists(args.context):
        with open(args.context, encoding='utf-8') as f:
            ctx = CONTEXT_HEAD + f.read() + CONTEXT_TAIL
    return ctx + body + (FOOTER if not args.no_footer else '')


def run_one(args, pid):
    out = args.out
    rec_path = os.path.join(out, 'runs', pid + '.run.json')
    prompt = build_prompt(args, pid)
    with open(os.path.join(out, 'prompts', pid + '.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(prompt)
    pf = os.path.abspath(os.path.join(out, 'prompts', pid + '.txt'))
    cmd = args.cmd.replace('{PROMPT_FILE}', pf)
    env = dict(os.environ); env['PYTHONIOENCODING'] = 'utf-8'
    t0 = time.time(); start = now(); timed_out = False; code = None; so = se = ''
    try:
        r = subprocess.run(cmd, shell=True, input=prompt.encode('utf-8'), capture_output=True, timeout=args.timeout, env=env)
        code = r.returncode; so = r.stdout.decode('utf-8', 'replace'); se = r.stderr.decode('utf-8', 'replace')
    except subprocess.TimeoutExpired as e:
        timed_out = True; so = (e.stdout or b'').decode('utf-8', 'replace'); se = (e.stderr or b'').decode('utf-8', 'replace')
    except Exception as e:
        se = 'runner exception: %r' % e
    wall = time.time() - t0
    with open(os.path.join(out, 'raw', pid + '.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(so)
    with open(os.path.join(out, 'raw', pid + '.err.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(se)
    usage = None
    for line in se.splitlines():
        m = re.match(r'\s*USAGE\s+(\{.*\})\s*$', line)
        if m:
            try:
                usage = json.loads(m.group(1))
            except ValueError:
                pass
    est = False
    if usage is None:
        est = True
        usage = {'in': int(len(prompt) / 3.5), 'out': int(len(so) / 3.5), 'cache_r': 0, 'cache_w': 0}
    dec, note = parse_decision(so) if so.strip() else (None, 'empty output')
    problems = [] if dec is None else check_schema(dec)
    if timed_out:
        status = 'timeout'
    elif code not in (0, None) and dec is None:
        status = 'cmd-failed'
    elif dec is None:
        status = 'unparsable'
    elif problems:
        status = 'schema-invalid'
    else:
        status = 'ok'
    if status == 'ok':
        with open(os.path.join(out, 'decisions', pid + '.json'), 'w', encoding='utf-8') as f:
            json.dump(dec, f, indent=1)
    rec = {'pid': pid, 'start': start, 'end': now(), 'wall_s': round(wall, 2), 'exit_code': code, 'timed_out': timed_out, 'status': status,
           'parse_note': note, 'schema_problems': problems, 'usage': usage, 'tokens_estimated': est,
           'model_label': args.model_label, 'effort_label': args.effort_label, 'cmd': args.cmd, 'stdout_chars': len(so)}
    with open(rec_path, 'w', encoding='utf-8') as f:
        json.dump(rec, f, indent=1)
    return rec


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--points', required=True, help='directory with P###.input.md files (data/replay/points)')
    ap.add_argument('--cmd', required=True, help='shell command: prompt on stdin, answer on stdout')
    ap.add_argument('--out', required=True)
    ap.add_argument('--parallel', type=int, default=1)
    ap.add_argument('--timeout', type=int, default=900, help='seconds per run')
    ap.add_argument('--context', help='file shown before every point (the project rules, data/context/CLAUDE.md)')
    ap.add_argument('--no-footer', action='store_true', help='do not append the answer-format reminder')
    ap.add_argument('--model-label', default='', help='EXACT model id, recorded only')
    ap.add_argument('--effort-label', default='', help='effort / thinking setting, recorded only')
    ap.add_argument('--first', type=int, help='only the first N points')
    ap.add_argument('--ids', help='comma list of point ids')
    ap.add_argument('--redo', action='store_true', help='re-run points that already have a record (the old record is overwritten)')
    a = ap.parse_args()
    ids = sorted(f[:-len('.input.md')] for f in os.listdir(a.points) if f.endswith('.input.md'))
    if a.ids:
        want = a.ids.split(','); ids = [x for x in ids if x in want]
    if a.first:
        ids = ids[:a.first]
    for sub in ('raw', 'prompts', 'runs', 'decisions'):
        os.makedirs(os.path.join(a.out, sub), exist_ok=True)
    todo = [x for x in ids if a.redo or not os.path.exists(os.path.join(a.out, 'runs', x + '.run.json'))]
    print('run_point: %d points, %d to run, parallel %d, out %s' % (len(ids), len(todo), a.parallel, a.out), flush=True)
    t0 = time.time()
    done = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.parallel)) as ex:
        futs = {ex.submit(run_one, a, x): x for x in todo}
        for fu in concurrent.futures.as_completed(futs):
            r = fu.result(); done[r['pid']] = r
            print('  %s %-14s %.1fs' % (r['pid'], r['status'], r['wall_s']), flush=True)
    rows = []
    for x in ids:
        p = os.path.join(a.out, 'runs', x + '.run.json')
        if os.path.exists(p):
            with open(p, encoding='utf-8') as f:
                rows.append(json.load(f))
    with open(os.path.join(a.out, 'results.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['point', 'status', 'exit_code', 'start', 'end', 'wall_s', 'in', 'out', 'cache_r', 'cache_w', 'tokens_estimated', 'schema_problems'])
        for r in rows:
            u = r['usage']
            w.writerow([r['pid'], r['status'], r['exit_code'], r['start'], r['end'], r['wall_s'], u.get('in', 0), u.get('out', 0), u.get('cache_r', 0), u.get('cache_w', 0),
                        1 if r['tokens_estimated'] else 0, ';'.join(r['schema_problems'])])
    bad = [r for r in rows if r['status'] != 'ok']
    print('run_point: finished %d runs in %.1fs; ok %d, not ok %d -> %s' % (len(todo), time.time() - t0, len(rows) - len(bad), len(bad), os.path.join(a.out, 'results.csv')))
    if bad:
        print('NOT OK (record them as failures, do not retry silently): ' + ', '.join('%s=%s' % (r['pid'], r['status']) for r in bad))


if __name__ == '__main__':
    main()
