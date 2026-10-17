#!/usr/bin/env python
"""replay-run.py - runner for the offline coordinator replay (Haiku High arm vs Sonnet High arm).

MECHANISM (no API client, no keys): the proven one from docs/MODEL_TEST.md - the COORDINATOR makes Agent calls tagged
[case:bench] [model:..] [effort:high]; there is no script that starts agents. This tool only
  plan     writes the batch plan (ready-to-use Agent calls) for N points x arms,
  collect  after the agents finished: finds each run's transcript by the marker 'replay-run: <rid>' in its prompt
           (no agent ids to copy by hand), parses the decision JSON (file written by the agent, else its final message),
           reads tokens and API-equivalent cost from the transcript (pilot-rowcmp.py / cost-audit.py / prices.json logic),
           and appends runs.tsv,
  status   shows which runs are missing.
Run with Windows python:  python -I replay-run.py <cmd> ...

Run ids: P001-ra (arm H = Haiku High) and P001-rb (arm S = Sonnet High). The prompts never name the model.
"""
import argparse, csv, glob, importlib.util, json, os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPLAY = r'C:\KenshiTestRuns\shadow\replay'
POINTS = os.path.join(REPLAY, 'points')
RUNS = os.path.join(REPLAY, 'runs')
ROOT = r'C:\Users\Shay\.claude\projects\C--KenshiModding'
ARMS = {'H': dict(model='haiku', effort='high', dir='ra'), 'S': dict(model='sonnet', effort='high', dir='rb')}
DIR2ARM = {v['dir']: k for k, v in ARMS.items()}
TYPES = {'ack', 'spawn', 'message-agent', 'message-shay', 'hold-lane', 'release-lane', 'restart-waker', 'ignore',
         'mark-row', 'edit-file', 'commit', 'wait', 'stop-agent', 'run'}
CLASSES = {'relay', 'setup-fail', 'lane-alert', 'waker-digest', 'shay-message', 'stop-hook', 'agent-stopped',
           'build-compose', 'other'}

PROMPT = ('replay-run: {rid}\n'
          'Read the file {inp} - it describes one moment of a past coordinator session and the decision to take. '
          'Follow its instructions exactly. Then use the Write tool to write ONLY the decision JSON object (no prose, no code fence) '
          'to {out} and reply with the single word OK. Use no other tools than that one Read and that one Write.')


def load_mod(name, fn):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, '..', fn))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def point_ids():
    return sorted(f[:-len('.input.md')] for f in os.listdir(POINTS) if f.endswith('.input.md'))


def rid_of(pid, arm):
    return '%s-%s' % (pid, ARMS[arm]['dir'])


def out_path(pid, arm):
    return os.path.join(RUNS, ARMS[arm]['dir'], pid + '.json')


def cmd_plan(a):
    ids = [x for x in a.ids.split(',')] if a.ids else point_ids()
    if a.first:
        ids = ids[:a.first]
    arms = a.arms.split(',')
    calls = []
    for pid in ids:
        for arm in arms:
            if not a.redo and os.path.exists(out_path(pid, arm)):
                continue
            os.makedirs(os.path.dirname(out_path(pid, arm)), exist_ok=True)
            rid = rid_of(pid, arm)
            calls.append({'rid': rid, 'point': pid, 'arm': arm,
                          'description': '[case:bench] [ticket:REPLAY-%s] [model:%s] [effort:%s] replay %s' % (rid, ARMS[arm]['model'], ARMS[arm]['effort'], rid),
                          'prompt': PROMPT.format(rid=rid, inp=os.path.join(POINTS, pid + '.input.md'), out=out_path(pid, arm)),
                          'run_in_background': True})
    os.makedirs(os.path.join(REPLAY, 'plan'), exist_ok=True)
    nb = 0
    for i in range(0, len(calls), a.batch):
        nb += 1
        p = os.path.join(REPLAY, 'plan', 'batch-%02d.json' % nb)
        json.dump(calls[i:i + a.batch], open(p, 'w', encoding='utf-8'), indent=0)
    print('planned %d runs in %d batches of <=%d -> %s\\plan\\batch-NN.json' % (len(calls), nb, a.batch, REPLAY))
    if calls:
        c = calls[0]
        print('EXAMPLE Agent call (model/effort tags decide the model; the prompt never names it):')
        print('  description: ' + c['description']); print('  prompt: ' + c['prompt'].replace('\n', ' | '))
        print('  run_in_background: true  (results come back as one-word notifications; then run: replay-run.py collect)')


def first_user_text(path):
    with open(path, encoding='utf-8', errors='ignore') as f:
        for n, line in enumerate(f):
            if n > 6:
                break
            if '"user"' not in line[:60] and '"type":"user"' not in line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if o.get('type') != 'user':
                continue
            c = o['message']['content']
            if isinstance(c, list):
                c = ' '.join(b.get('text', '') for b in c if isinstance(b, dict))
            return c
    return ''


def find_transcripts(hours):
    now = time.time(); found = {}
    for p in glob.glob(os.path.join(ROOT, '*', 'subagents', 'agent-*.jsonl')):
        try:
            if now - os.path.getmtime(p) > hours * 3600:
                continue
        except OSError:
            continue
        m = re.search(r'replay-run: (P\d+-r[ab])', first_user_text(p)[:3000])
        if m:
            found.setdefault(m.group(1), []).append(p)
    return found


def final_text(path):
    last = ''
    with open(path, encoding='utf-8', errors='ignore') as f:
        for line in f:
            if '"assistant"' not in line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if o.get('type') != 'assistant':
                continue
            for b in (o['message'].get('content') or []):
                if isinstance(b, dict) and b.get('type') == 'text' and b.get('text', '').strip():
                    last = b['text']
    return last


def tool_calls(path):
    n = 0; t0 = t1 = None; model = ''; wrote = None
    with open(path, encoding='utf-8', errors='ignore') as f:
        for line in f:
            try:
                o = json.loads(line)
            except ValueError:
                continue
            ts = o.get('timestamp')
            if ts:
                t0 = t0 or ts; t1 = ts
            if o.get('type') == 'assistant':
                model = o['message'].get('model') or model
                for b in (o['message'].get('content') or []):
                    if isinstance(b, dict) and b.get('type') == 'tool_use':
                        n += 1
                        if b.get('name') == 'Write':
                            wrote = (b.get('input') or {}).get('content')
    return n, t0, t1, model, wrote


def parse_decision(txt):
    if not txt:
        return None, 'empty'
    s = txt.strip()
    s = re.sub(r'^```(?:json)?\s*|\s*```$', '', s)
    try:
        return json.loads(s), 'ok'
    except ValueError:
        m = re.search(r'\{.*\}', s, re.S)
        if m:
            try:
                return json.loads(m.group(0)), 'ok-extracted'
            except ValueError:
                pass
    return None, 'bad_json'


def check_schema(d):
    probs = []
    if not isinstance(d, dict) or not isinstance(d.get('decision'), list):
        return ['no decision list']
    if d.get('event_class') not in CLASSES:
        probs.append('event_class %r' % d.get('event_class'))
    for i, a in enumerate(d['decision']):
        if not isinstance(a, dict):
            probs.append('action %d not an object' % i); continue
        if a.get('type') not in TYPES:
            probs.append('action %d type %r' % (i, a.get('type')))
        if 'exact_command_or_message' not in a:
            probs.append('action %d missing exact_command_or_message' % i)
    return probs


def iso_epoch(s):
    import datetime
    return datetime.datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()


def cmd_collect(a):
    rp = load_mod('rowcmp', 'pilot-rowcmp.py'); ca = rp.load_ca(); prices = ca.load_prices()
    found = find_transcripts(a.hours)
    tsv = os.path.join(REPLAY, 'runs.tsv')
    have = {}
    if os.path.exists(tsv):
        for r in csv.DictReader(open(tsv, encoding='utf-8'), delimiter='\t'):
            have[r['rid']] = r
    cols = ['rid', 'point', 'arm', 'agent_id', 'status', 'schema_problems', 'wall_s', 'tool_calls', 'model', 'in', 'out', 'cache_w', 'cache_r', 'tokens', 'usd']
    new = 0
    for rid, paths in sorted(found.items()):
        if rid in have and not a.redo:
            continue
        pid, d = rid.split('-')
        arm = DIR2ARM[d]
        p = sorted(paths, key=os.path.getmtime)[-1]
        aid = re.search(r'agent-(\w+)\.jsonl', p).group(1)
        n, t0, t1, model, wrote = tool_calls(p)
        txt = None
        op = out_path(pid, arm)
        if os.path.exists(op):
            txt = open(op, encoding='utf-8', errors='replace').read()
        elif wrote:
            txt = wrote
        else:
            txt = final_text(p)
        dec, st = parse_decision(txt)
        probs = check_schema(dec) if dec is not None else ['unparsed']
        if dec is not None:
            os.makedirs(os.path.dirname(op), exist_ok=True)
            json.dump(dec, open(op, 'w', encoding='utf-8'), indent=1)
        status = st if not probs else st + '+schema'
        cost = rp.window_cost([p], 0, 4e9, ca, prices)
        exp = ARMS[arm]['model']
        if exp not in (model or '').lower():
            status += '+MODEL?' + (model or '')
        wall = round(iso_epoch(t1) - iso_epoch(t0), 1) if t0 and t1 else ''
        have[rid] = dict(rid=rid, point=pid, arm=arm, agent_id=aid, status=status, schema_problems=';'.join(probs)[:200], wall_s=wall,
                         tool_calls=n, model=model, **{'in': cost['in'], 'out': cost['out'], 'cache_w': cost['cw'], 'cache_r': cost['cr'],
                                                      'tokens': cost['tokens'], 'usd': round(cost['usd'], 5)})
        new += 1
    with open(tsv, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols, delimiter='\t'); w.writeheader()
        for r in sorted(have.values(), key=lambda r: r['rid']):
            w.writerow({k: r.get(k, '') for k in cols})
    print('collected %d new (total %d) -> %s' % (new, len(have), tsv))
    print('bad:', [r['rid'] for r in have.values() if not str(r['status']).startswith('ok') or 'MODEL?' in str(r['status'])][:30])


def cmd_retry(a):
    """Delete outputs of invalid runs (runs.tsv status not ok* or schema problems) then re-plan only the missing runs."""
    tsv = os.path.join(REPLAY, 'runs.tsv'); bad = []
    if os.path.exists(tsv):
        for r in csv.DictReader(open(tsv, encoding='utf-8'), delimiter='	'):
            if not str(r['status']).startswith('ok') or r['schema_problems'] or 'MODEL?' in r['status']:
                op = out_path(r['point'], r['arm'])
                if os.path.exists(op):
                    os.remove(op)
                bad.append(r['rid'])
    print('invalid runs cleared:', bad)
    a.ids = None; a.first = None; a.arms = 'H,S'; a.redo = False
    cmd_plan(a)


def cmd_status(a):
    ids = point_ids()
    miss = [rid_of(p, arm) for p in ids for arm in a.arms.split(',') if not os.path.exists(out_path(p, arm))]
    print('points %d, missing runs %d' % (len(ids), len(miss)))
    if miss:
        print(' '.join(miss[:40]))


def main():
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('plan'); p.add_argument('--arms', default='H,S'); p.add_argument('--ids'); p.add_argument('--first', type=int)
    p.add_argument('--batch', type=int, default=20); p.add_argument('--redo', action='store_true'); p.set_defaults(f=cmd_plan)
    p = sp.add_parser('collect'); p.add_argument('--hours', type=float, default=24); p.add_argument('--redo', action='store_true'); p.set_defaults(f=cmd_collect)
    p = sp.add_parser('retry'); p.add_argument('--batch', type=int, default=20); p.set_defaults(f=cmd_retry)
    p = sp.add_parser('status'); p.add_argument('--arms', default='H,S'); p.set_defaults(f=cmd_status)
    a = ap.parse_args(); a.f(a)


if __name__ == '__main__':
    main()
