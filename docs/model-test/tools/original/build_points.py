"""Phase 2: select ~120 stratified decision points from cands.jsonl and render <id>.input.md / <id>.truth.json / INDEX.csv.

Usage: python build_points.py [--n 120] [--seed 26] [--only-ids ids.txt] [--out DIR]
"""
import sys, json, re, os, csv, random, subprocess, bisect, collections, argparse
from common import *
from extract import classify, find_event_read, outcome_for

QUOTA = {'relay': 14, 'setup-fail': 14, 'lane-alert': 14, 'waker-digest': 12, 'shay-message': 14, 'stop-hook': 14,
         'agent-stopped': 14, 'build-compose': 12, 'other': 12}
MAX_PER_SESSION_PER_CLASS = 3
CAP_SESSION = {'5270be03': 6}   # mostly a design chat, not a pure coordinator run

SCHEMA_TEXT = """\
You are the COORDINATOR of Shay's Kenshi modding workspace in a REPLAY: you see the situation exactly as it was at one
moment of a past coordinator session. You cannot run commands or tools in this replay. Decide what the coordinator
should do NEXT about the EVENT BATCH at the bottom, using only this file plus the standing project rules you already
know (CLAUDE.md). Do not wait for more data and do not ask questions: commit to the actions you would take now,
assuming read-only checks you list come back as expected.

OUTPUT: ONLY one JSON object, no prose, no code fence:
{"event_class": "<relay | setup-fail | lane-alert | waker-digest | shay-message | stop-hook | agent-stopped | build-compose | other>",
 "decision": [ {"type": "<type>", "exact_command_or_message": "<exact command, or exact message/brief text, or file path + intent>", "why": "<one sentence>"} ],
 "checks": ["<read-only command you would run first, if any>"]}
type is one of: ack, spawn, message-agent, message-shay, hold-lane, release-lane, restart-waker, ignore, mark-row,
edit-file, commit, wait, stop-agent, run.
 - ack = alert-ack.ps1 / tail-ack.ps1 / agent-abandon.ps1 style closure; spawn = Agent call (put agent name, [case:...] tag, and the brief text);
 - message-agent = SendMessage to an agent or peer coordinator; message-shay = text for Shay / his relay session;
 - run = any other mutating command; ignore = deliberately do nothing (say why); wait = nothing yet, name what you wait for.
Ordered list, only the actions the coordinator would take in response to this event batch (an empty-effect case is a single ignore/wait).
Never invent paths or ids that are not in this file; if something is unknown say so in why."""


def git_index(path='testing/HANDOFF.md'):
    out = subprocess.run(['git', '-C', REPO, 'log', '--format=%H %ct', '--', path], capture_output=True, text=True).stdout
    items = sorted((int(l.split()[1]), l.split()[0]) for l in out.strip().splitlines())
    return items


_hcache = {}


def handoff_excerpt(ts_iso, idx):
    import datetime
    t = datetime.datetime.fromisoformat(ts_iso.replace('Z', '+00:00')).timestamp()
    times = [x[0] for x in idx]
    k = bisect.bisect_right(times, t) - 1
    if k < 0:
        k = 0
    h = idx[k][1]
    if h not in _hcache:
        raw = subprocess.run(['git', '-C', REPO, 'show', h + ':testing/HANDOFF.md'], capture_output=True).stdout
        txt = raw.decode('utf-8', errors='replace')
        m = re.search(r'^## Right now.*$', txt, re.M)
        start = m.start() if m else 0
        _hcache[h] = (txt[start:start + 6000], h)
    return _hcache[h]


def render_entry(e, tu_names):
    k = e[0]
    if k == 'U':
        return '[INBOUND/USER] ' + redact(trunc(e[2], 1500))
    if k == 'R':
        return '[tool result] ' + redact(trunc(e[3], 1500))
    if k == 'H':
        return '[hook note] ' + redact(trunc(e[2], 400))
    parts = []
    for b in e[2]:
        if b.get('type') == 'text' and b.get('text', '').strip():
            parts.append(redact(trunc(b['text'], 1200)))
        elif b.get('type') == 'tool_use':
            inp = b.get('input') or {}
            if b['name'] in ('Bash', 'PowerShell'):
                parts.append('-> %s: %s' % (b['name'], redact(trunc(inp.get('command', ''), 700))))
            elif b['name'] in ('Agent', 'Task'):
                parts.append('-> Agent: %s | %s' % (inp.get('description', ''), redact(trunc(inp.get('prompt', ''), 800))))
            else:
                parts.append('-> %s: %s' % (b['name'], redact(trunc(json.dumps(inp), 500))))
    return '[coordinator] ' + '\n'.join(parts)


def build_truth(pid, c, entries, lo, hi, read_id):
    actions = []; reads = []; narr = []
    last_text = ''
    for k in range(lo + 1, hi):
        e = entries[k]
        if e[0] != 'A':
            continue
        for b in e[2]:
            if b.get('type') == 'text' and b.get('text', '').strip():
                last_text = b['text'].strip()
                narr.append(redact(trunc(last_text, 500)))
            elif b.get('type') == 'tool_use':
                if b.get('id') == read_id:
                    continue
                a = action_of(b)
                if not a:
                    continue
                if a[0] == 'investigate':
                    reads.append(redact(trunc(a[1], 200)))
                else:
                    actions.append({'type': a[0], 'exact_command_or_message': redact(a[1]), 'why': redact(trunc(last_text, 300))})
    # Shay message answered in plain text => message-shay
    if c['cls'] == 'shay-message' and narr:
        actions.append({'type': 'message-shay', 'exact_command_or_message': narr[-1], 'why': 'reply to Shay'})
    if not actions:
        actions = [{'type': 'ignore', 'exact_command_or_message': '', 'why': (narr[0] if narr else 'coordinator took no mutating action before the next event')}]
    trunc_n = max(0, len(actions) - 15)
    return {'id': pid, 'session': c['session'], 'ts': c['ts'], 'class': c['cls'],
            'outcome': {'label': c['outcome'], 'why': c['outcome_why']},
            'actions': actions[:15], 'actions_truncated': trunc_n, 'reads': reads[:10], 'narration': narr[:6]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--n', type=int, default=120)
    ap.add_argument('--seed', type=int, default=26)
    ap.add_argument('--out', default=POINTS)
    ap.add_argument('--ids')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cands = [json.loads(l) for l in open(os.path.join(REPLAY, 'cands.jsonl'), encoding='utf-8')]
    rnd = random.Random(a.seed)
    chosen = []
    scale = a.n / float(sum(QUOTA.values()))
    for cls, q in QUOTA.items():
        q = max(1, round(q * scale))
        pool = [c for c in cands if c['cls'] == cls and c['pi'] > 0 and c['trig_len'] > 20 and c['has_a']]
        rnd.shuffle(pool)
        want_bad = int(round(q * 0.35))
        picked = []; per = collections.Counter()

        def take(sub, cnt):
            for c in sub:
                if len([p for p in picked]) >= q or cnt <= 0:
                    break
                if per[c['session']] >= MAX_PER_SESSION_PER_CLASS or (c['session'] in CAP_SESSION and sum(1 for p in chosen + picked if p['session'] == c['session']) >= CAP_SESSION[c['session']]):
                    continue
                if c in picked:
                    continue
                picked.append(c); per[c['session']] += 1; cnt -= 1
        take([c for c in pool if c['outcome'] != 'good'], want_bad)
        take([c for c in pool if c['outcome'] == 'good' and c['n_actions'] > 0], q)
        take(pool, q)
        chosen += picked
    chosen.sort(key=lambda c: (c['ts']))
    idx = git_index()
    bysess = collections.defaultdict(list)
    for c in chosen:
        bysess[c['session']].append(c)
    rows = []
    n = 0
    order = {}
    for i, c in enumerate(chosen, 1):
        order[(c['session'], c['pi'])] = 'P%03d' % i
    for sess, lst in bysess.items():
        entries = load_stream(session_path(sess))
        for c in lst:
            pid = order[(c['session'], c['pi'])]
            lo, hi = c['lo'], c['hi']
            trig = entries[lo][2]
            ev_text, read_id = (find_event_read(entries, lo + 1, hi, trig) if trig.lstrip().startswith('<task-notification') else ('', None))
            ctx = [e for e in entries[:lo] if e[0] in ('U', 'A', 'R', 'H')]
            ctx = ctx[-22:]
            hand, hh = handoff_excerpt(c['ts'], idx)
            lines = [SCHEMA_TEXT, '', '=' * 70, '## HANDOFF "Right now" text at that time (git %s, first 6000 chars)' % hh[:8], '', redact(hand), '',
                     '=' * 70, '## Preceding conversation (last %d entries, tool output truncated to 1500 chars)' % len(ctx), '']
            for e in ctx:
                lines.append(render_entry(e, None)); lines.append('')
            lines += ['=' * 70, '## EVENT BATCH (arrived at %s UTC)' % c['ts'][11:19], '', '[INBOUND] ' + redact(trunc(trig, 3500))]
            if ev_text:
                lines += ['', '[output of the background task named above, as read by the coordinator]', redact(trunc(ev_text, 3500))]
            lines += ['', '## Now output the decision JSON only.']
            text = '\n'.join(lines)
            with open(os.path.join(a.out, pid + '.input.md'), 'w', encoding='utf-8', newline='\n') as f:
                f.write(text)
            tr = build_truth(pid, c, entries, lo, hi, read_id)
            tr['event_text_chars'] = len(trig) + len(ev_text)
            with open(os.path.join(a.out, pid + '.truth.json'), 'w', encoding='utf-8') as f:
                json.dump(tr, f, indent=1)
            rows.append([pid, c['session'], c['cls'], int(len(text) / 3.6), c['outcome'], c['ts'], len(tr['actions']), '/'.join(c['types'])])
    rows.sort()
    with open(os.path.join(a.out, '..', 'INDEX.csv') if a.out == POINTS else os.path.join(a.out, 'INDEX.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f); w.writerow(['id', 'session', 'class', 'tokens_est', 'outcome', 'ts', 'n_actions', 'action_types']); w.writerows(rows)
    cc = collections.Counter(r[2] for r in rows); oo = collections.Counter(r[4] for r in rows)
    print('points', len(rows), dict(cc), dict(oo), 'tokens_est total', sum(r[3] for r in rows))


if __name__ == '__main__':
    main()
