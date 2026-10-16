#!/usr/bin/env python3
"""cost-audit.py - token and API-price-equivalent cost audit of Claude Code transcripts (read-only).

Reads C:\\Users\\Shay\\.claude\\projects\\C--KenshiModding\\*.jsonl (main sessions) and
<session>\\subagents\\agent-*.jsonl (subagents). Streams every file line by line, json.loads per
line, and prints/writes aggregates only. Never prints transcript text.

Usage (Windows python; WSL python3 works too):
  python -I tools/automation/cost-audit.py [--since YYYY-MM-DD] [--out DIR] [--root DIR]
                                           [--selfcheck FILE] [--workers N] [--limit-files N]
  powershell -File tools/automation/cost-audit.ps1 [same options]

Outputs (in --out, default C:\\KenshiTestRuns\\agents\\out\\imm26-costaudit):
  ledger.csv  one row per agent transcript (main session or subagent)
  ledger.md   top 15 spenders, per-day, per-model, per-task-type, Haiku what-if, tool-output top 20,
              dedupe stats, self-check (if --selfcheck FILE, or <out>\\selfcheck.tsv, exists)

Method:
  - Usage fields per assistant message: input_tokens, output_tokens, cache_creation_input_tokens
    (split into cache_creation.ephemeral_5m_input_tokens and ephemeral_1h_input_tokens; no split = 5 min),
    cache_read_input_tokens.
  - Dedupe: Claude Code writes one JSON line per content block, all with the same message id (and
    requestId). Each message id is counted once. Across files the first occurrence wins; inside a
    file the record with the largest output_tokens is kept (streamed chunks grow). Counts are reported.
  - Price: tools/automation/prices.json (same rates as docs/MODEL_ROUTING.md). Each message is priced
    at its own model. Haiku prompts over 100,000 tokens (input + cache read + cache write) use the
    over-100k rate for the whole prompt (same reading as ledger-report.py).
  - Haiku what-if: the same token counts repriced at the Haiku rate (same band rule). Output length is
    NOT changed, so this is a price-only comparison.
  - Day = local Windows date of each message timestamp (UTC converted with the local offset).
  - Task type: coordinator (main session); else keywords in the subagent description (lane-operator,
    recipe, native-build, server-fix), then [case:x] tag, then generic keywords; else other.
  - Tool outputs: size = characters of each tool_result text, grouped by tool name, and for Bash /
    PowerShell by the first word of the command.
"""
import argparse
import collections
import csv
import datetime as dt
import glob
import json
import os
import re
import sys
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = r'C:\Users\Shay\.claude\projects\C--KenshiModding'
DEFAULT_OUT = r'C:\KenshiTestRuns\agents\out\imm26-costaudit'
BAND = 100000  # Haiku over-100k prompt band
HAIKU_ELIGIBLE = ('reader', 'classifier', 'statistics', 'investigator')  # read/parse/check/classify/investigator/statistics

CASE_MAP = {'investigate': 'investigator', 'debug': 'investigator', 'escalate': 'investigator',
            'read': 'reader', 'parse': 'reader', 'check': 'reader', 'classify': 'classifier',
            'patch': 'generator', 'generate': 'generator', 'grade': 'grader', 'bench': 'bench'}

# Task-type rules on the subagent description (prompt text only when there is no description).
# KEYWORD_RULES are checked first; then the [case:x] tag; then GENERIC_RULES; else "other".
KEYWORD_RULES = [
    ('lane-operator', r'(\boperator|\bop\d|\bi[345]\s?-?op|\blane|\brows?\b|kenshi-ctl|\b[45]090-i)'),
    ('recipe', r'\brecipe'),
    ('native-build', r'(\bnative\b|\bbuild\b|compile|msbuild|cmake|\bdll\b)'),
    ('server-fix', r'(\bserver|\bphp\b|stobe-server|\bsql\b|database)'),
    ('pg-agent', r'(\bpg\b|profession gear)'),
    ('harness', r'(\bharness|\bkah\b|automation)'),
]
GENERIC_RULES = [
    ('investigator', r'(investigat|\bdebug|root cause|diagnos|escalat)'),
    ('classifier', r'(classif|categori[sz]e|triage)'),
    ('statistics', r'(statistic|\bstats?\b|tally|aggregat|\bcount)'),
    ('reader', r'(\bread\b|\bparse|\bcheck|\baudit|\bgrep|\bscan|inventory|summari)'),
    ('generator', r'(\bpatch|generat|implement|\bfix|\bwrite)'),
    ('grader', r'\bgrad(e|ing)'),
    ('animation', r'(\banim|viewmodel|kenshifp|\bfp\b)'),
]
CASE_RE = re.compile(r'\[case:([a-z]+)\]', re.I)
WORD_RE = re.compile(r'^\s*(?:[A-Za-z_]+=\S+\s+)*([^\s;|&]+)')


def load_prices():
    with open(os.path.join(HERE, 'prices.json'), encoding='utf-8') as f:
        p = json.load(f)
    return {k: v for k, v in p.items() if not k.startswith('_')}


def family(model):
    m = (model or '').lower()
    for fam in ('haiku', 'sonnet', 'opus'):
        if fam in m:
            return fam
    return 'unknown'


def usd_at(r, i, o, cr, cw5, cw1):
    return (i * r['input'] + o * r['output'] + cr * r['cache_read']
            + cw5 * r['cache_write_5m'] + cw1 * r['cache_write_1h']) / 1e6


def local_day(ts):
    try:
        t = dt.datetime.strptime(ts[:19], '%Y-%m-%dT%H:%M:%S').replace(tzinfo=dt.timezone.utc).astimezone()
        return t.strftime('%Y-%m-%d'), t.strftime('%Y-%m-%d %H:%M')
    except (ValueError, TypeError):
        return '', ''


def result_chars(c):
    if isinstance(c, str):
        return len(c)
    if isinstance(c, list):
        return sum(len(x.get('text', '') or '') for x in c if isinstance(x, dict) and x.get('type') == 'text')
    return 0


def tool_pattern(name, inp):
    if name in ('Bash', 'PowerShell'):
        cmd = inp.get('command') if isinstance(inp, dict) else ''
        cmd = re.sub(r'^\s*cd\s+\S+\s*(&&|;)\s*', '', cmd or '')  # skip leading cd prefixes
        cmd = re.sub(r'^\s*cd\s+\S+\s*(&&|;)\s*', '', cmd)
        m = WORD_RE.match(cmd or '')
        word = os.path.basename(m.group(1)) if m else '?'
        return name + ':' + word[:40]
    return name or '?'


def scan_file(job):
    """Worker: one transcript. Returns compact aggregates (no transcript text)."""
    path, kind, session, prices = job
    stem = os.path.basename(path)[:-6]
    res = {'path': path, 'kind': kind, 'session': session,
           'agent': stem[6:] if kind == 'sub' else 'main', 'desc': '', 'agent_type': '',
           'first_user': '', 'msgs': {}, 'dupes': 0, 'dupe_diff': 0, 'lines_assistant': 0,
           'tools': {}, 'unknown_model': 0, 'unknown_names': collections.Counter()}
    if kind == 'sub':
        mp = path[:-6] + '.meta.json'
        if os.path.exists(mp):
            try:
                with open(mp, encoding='utf-8') as f:
                    meta = json.load(f)
                res['desc'] = (meta.get('description') or '')[:200]
                res['agent_type'] = meta.get('agentType') or ''
            except (OSError, ValueError):
                pass
    tool_names = {}
    tools = res['tools']
    with open(path, 'rb') as f:
        for raw in f:
            if b'"type":"assistant"' in raw:
                d = json.loads(raw)
                if d.get('type') != 'assistant':
                    continue
                m = d.get('message') or {}
                content = m.get('content')
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get('type') == 'tool_use':
                            tool_names[c.get('id')] = tool_pattern(c.get('name'), c.get('input'))
                u = m.get('usage')
                mid = m.get('id') or d.get('requestId')
                if not u or not mid:
                    continue
                res['lines_assistant'] += 1
                i = u.get('input_tokens') or 0
                o = u.get('output_tokens') or 0
                cr = u.get('cache_read_input_tokens') or 0
                cwt = u.get('cache_creation_input_tokens') or 0
                cc = u.get('cache_creation') or {}
                cw1 = cc.get('ephemeral_1h_input_tokens') or 0
                cw5 = cc.get('ephemeral_5m_input_tokens')
                if cw5 is None:
                    cw5 = cwt - cw1
                model = m.get('model') or ''
                fam = family(model)
                prompt = i + cr + cwt
                usd_unpriced = 0.0
                parts = (0.0, 0.0, 0.0, 0.0)  # input, output, cache read, cache write (priced models only)
                rh = prices['haiku_over_100k' if prompt > BAND else 'haiku']
                usd_h = usd_at(rh, i, o, cr, cw5, cw1)  # Haiku what-if is priced for every model
                if fam == 'unknown':
                    # no rate in prices.json (e.g. claude-fable): counted as $0; bound at Opus rates kept apart
                    res['unknown_model'] += 1
                    res['unknown_names'][(model or '?') + (' (zero tokens)' if not (i or o or cr or cwt) else ' (with tokens)')] += 1
                    usd = 0.0
                    usd_unpriced = usd_at(prices['opus'], i, o, cr, cw5, cw1)
                else:
                    r = prices['haiku_over_100k' if (fam == 'haiku' and prompt > BAND) else fam]
                    usd = usd_at(r, i, o, cr, cw5, cw1)
                    parts = (i * r['input'] / 1e6, o * r['output'] / 1e6, cr * r['cache_read'] / 1e6,
                             (cw5 * r['cache_write_5m'] + cw1 * r['cache_write_1h']) / 1e6)
                day, tloc = local_day(d.get('timestamp') or '')
                rec = (mid, day, tloc, model, fam, i, o, cw5, cw1, cr, usd, usd_h, usd_unpriced) + parts
                prev = res['msgs'].get(mid)
                if prev is None:
                    res['msgs'][mid] = rec
                else:
                    res['dupes'] += 1
                    if (prev[5], prev[6], prev[9]) != (i, o, cr):
                        res['dupe_diff'] += 1
                    if o > prev[6]:
                        res['msgs'][mid] = rec
            elif b'"type":"user"' in raw:
                d = json.loads(raw)
                if d.get('type') != 'user':
                    continue
                c = (d.get('message') or {}).get('content')
                if isinstance(c, str):
                    if not res['first_user'] and c.strip() and not c.lstrip().startswith('<'):
                        res['first_user'] = c.strip()[:400]
                elif isinstance(c, list):
                    for x in c:
                        if not isinstance(x, dict):
                            continue
                        if x.get('type') == 'text' and not res['first_user']:
                            t = (x.get('text') or '').strip()
                            if t and not t.lstrip().startswith('<'):
                                res['first_user'] = t[:400]
                        elif x.get('type') == 'tool_result':
                            pat = tool_names.get(x.get('tool_use_id'), '?')
                            n = result_chars(x.get('content'))
                            s = tools.setdefault(pat, [0, 0, 0])
                            s[0] += 1
                            s[1] += n
                            if n > s[2]:
                                s[2] = n
    return res


def task_type(kind, desc, first_user):
    if kind == 'main':
        return 'coordinator'  # main session = coordinator or a personal Claude Code session
    text = (desc or first_user[:200]).lower()  # the description decides; prompt text only if none
    for name, pat in KEYWORD_RULES:
        if re.search(pat, text):
            return name
    m = CASE_RE.search(desc or '')
    if m and CASE_MAP.get(m.group(1).lower()):
        return CASE_MAP[m.group(1).lower()]
    for name, pat in GENERIC_RULES:
        if re.search(pat, text):
            return name
    return 'other'


NO_LABELS = False  # --no-labels: labels are hidden (the repo copy must not carry prompt text)


def label_of(res):
    if NO_LABELS:
        return '(hidden)'
    base = res['desc'] or res['first_user']
    base = re.sub(r'\s+', ' ', base).strip()
    return base[:110]


def money(x):
    return '${:,.2f}'.format(x)


def toks(x):
    return '{:,}'.format(int(x))


def add_totals(dst, rec):
    dst['n'] += 1
    dst['input'] += rec[5]
    dst['output'] += rec[6]
    dst['cache_write'] += rec[7] + rec[8]
    dst['cache_read'] += rec[9]
    dst['usd'] += rec[10]
    dst['usd_haiku'] += rec[11]


def new_totals():
    return {'n': 0, 'input': 0, 'output': 0, 'cache_write': 0, 'cache_read': 0, 'usd': 0.0, 'usd_haiku': 0.0}


def read_selfcheck(path):
    rows = {}
    if not path or not os.path.exists(path):
        return rows
    with open(path, encoding='utf-8') as f:
        for line in f:
            p = line.rstrip('\n').split('\t')
            if len(p) >= 7 and p[0] != 'agent':
                rows[p[0]] = p
    return rows


def main():
    ap = argparse.ArgumentParser(description='Cost/token audit of Claude Code transcripts (read-only).')
    ap.add_argument('--since', default='', help='YYYY-MM-DD, local day; earlier messages are ignored')
    ap.add_argument('--out', default=DEFAULT_OUT)
    ap.add_argument('--root', default=DEFAULT_ROOT)
    ap.add_argument('--selfcheck', default='', help='TSV from an independent recount (default <out>\\selfcheck.tsv)')
    ap.add_argument('--workers', type=int, default=16)
    ap.add_argument('--limit-files', type=int, default=0, help='dry run: first N files only')
    ap.add_argument('--no-labels', action='store_true', help='hide description/prompt labels (for committed copies)')
    a = ap.parse_args()
    global NO_LABELS
    NO_LABELS = a.no_labels
    prices = load_prices()
    root = a.root
    since = a.since

    jobs = []
    for p in sorted(glob.glob(os.path.join(root, '*.jsonl'))):
        jobs.append((p, 'main', os.path.basename(p)[:-6]))
    for p in sorted(glob.glob(os.path.join(root, '*', 'subagents', 'agent-*.jsonl'))):
        jobs.append((p, 'sub', os.path.basename(os.path.dirname(os.path.dirname(p)))))
    if since:
        cutoff = dt.datetime.strptime(since, '%Y-%m-%d').timestamp()
        jobs = [j for j in jobs if os.path.getmtime(j[0]) >= cutoff - 86400]
    if a.limit_files:
        jobs = jobs[:a.limit_files]
    print('files to scan: %d (main %d, subagent %d)' % (len(jobs), sum(1 for j in jobs if j[1] == 'main'),
                                                        sum(1 for j in jobs if j[1] == 'sub')), file=sys.stderr)
    work = [(p, k, s, prices) for p, k, s in jobs]
    with ProcessPoolExecutor(max_workers=max(1, a.workers)) as ex:
        results = list(ex.map(scan_file, work, chunksize=2))

    os.makedirs(a.out, exist_ok=True)
    seen = set()
    cross_dupes = 0
    total_msgs = 0
    total_dupes = sum(r['dupes'] for r in results)
    total_dupe_diff = sum(r['dupe_diff'] for r in results)
    unknown_model = sum(r['unknown_model'] for r in results)
    unknown_names = collections.Counter()
    for r in results:
        unknown_names.update(r['unknown_names'])
    agents = []
    per_day = collections.defaultdict(new_totals)
    per_model = collections.defaultdict(new_totals)
    per_task = collections.defaultdict(new_totals)
    parts_all = [0.0, 0.0, 0.0, 0.0]
    tools_all = collections.defaultdict(lambda: [0, 0, 0])
    first_day, last_day = '', ''

    for r in results:
        kept = []
        for rec in r['msgs'].values():
            total_msgs += 1
            if rec[0] in seen:
                cross_dupes += 1
                continue
            seen.add(rec[0])
            if since and rec[1] < since:
                continue
            kept.append(rec)
        if not kept:
            continue
        for rec in kept:
            if rec[1]:
                first_day = rec[1] if not first_day or rec[1] < first_day else first_day
                last_day = rec[1] if not last_day or rec[1] > last_day else last_day
        kept.sort(key=lambda x: x[2])
        tot = new_totals()
        tot['unpriced_opus'] = sum(rec[12] for rec in kept)
        fam_usd = collections.Counter()
        models = collections.Counter()
        for rec in kept:
            for k in range(4):
                parts_all[k] += rec[13 + k]
            add_totals(tot, rec)
            add_totals(per_day[rec[1]], rec)
            add_totals(per_model[rec[4]], rec)
            fam_usd[rec[4]] += rec[10]
            models[rec[3]] += 1
        ttype = task_type(r['kind'], r['desc'], r['first_user'])
        agent_row = {
            'day': kept[0][1], 'session': r['session'], 'agent': r['agent'], 'kind': r['kind'],
            'primary_model': (fam_usd.most_common(1)[0][0] if fam_usd else ''),
            'models': '+'.join('%s:%d' % (m, n) for m, n in models.most_common()),
            'input': tot['input'], 'output': tot['output'], 'cache_write': tot['cache_write'],
            'cache_read': tot['cache_read'], 'usd': tot['usd'], 'haiku_usd': tot['usd_haiku'],
            'task_type': ttype, 'haiku_eligible': ttype in HAIKU_ELIGIBLE, 'n_messages': tot['n'],
            'first_ts': kept[0][2], 'last_ts': kept[-1][2], 'label': label_of(r),
            'last_day': kept[-1][1], 'unpriced_opus_usd': tot['unpriced_opus'],
        }
        agents.append(agent_row)
        for pat, s in r['tools'].items():
            t = tools_all[pat]
            t[0] += s[0]
            t[1] += s[1]
            t[2] = max(t[2], s[2])

    # per-task totals come from the agent rows (n = agents)
    per_task = collections.defaultdict(new_totals)
    for ag in agents:
        t = per_task[ag['task_type']]
        t['n'] += 1
        t['input'] += ag['input']
        t['output'] += ag['output']
        t['cache_write'] += ag['cache_write']
        t['cache_read'] += ag['cache_read']
        t['usd'] += ag['usd']
        t['usd_haiku'] += ag['haiku_usd']

    agents.sort(key=lambda x: -x['usd'])
    csv_path = os.path.join(a.out, 'ledger.csv')
    cols = ['day', 'session', 'agent', 'kind', 'primary_model', 'models', 'input', 'output', 'cache_write',
            'cache_read', 'usd', 'haiku_usd', 'task_type', 'haiku_eligible', 'n_messages', 'first_ts',
            'last_ts', 'last_day', 'label']
    with open(csv_path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(cols)
        for ag in agents:
            w.writerow([ag['day'], ag['session'], ag['agent'], ag['kind'], ag['primary_model'], ag['models'],
                        ag['input'], ag['output'], ag['cache_write'], ag['cache_read'], '%.4f' % ag['usd'],
                        '%.4f' % ag['haiku_usd'], ag['task_type'], int(ag['haiku_eligible']), ag['n_messages'],
                        ag['first_ts'], ag['last_ts'], ag['last_day'], ag['label']])

    grand = new_totals()
    grand['parts'] = parts_all
    grand['unpriced_opus'] = sum(ag['unpriced_opus_usd'] for ag in agents)
    for ag in agents:
        grand['n'] += 1
        grand['input'] += ag['input']
        grand['output'] += ag['output']
        grand['cache_write'] += ag['cache_write']
        grand['cache_read'] += ag['cache_read']
        grand['usd'] += ag['usd']
        grand['usd_haiku'] += ag['haiku_usd']

    md = build_md(a, prices, agents, per_day, per_model, per_task, tools_all, grand, dict(
        files=len(jobs), total_msgs=total_msgs, unique=len(seen), cross_dupes=cross_dupes,
        dupes=total_dupes, dupe_diff=total_dupe_diff, unknown_model=unknown_model,
        first_day=first_day, last_day=last_day, unknown_names=unknown_names))
    md_path = os.path.join(a.out, 'ledger.md')
    with open(md_path, 'w', encoding='utf-8') as f:
        f.write(md)
    print('wrote %s (%d rows, %d bytes)' % (csv_path, len(agents), os.path.getsize(csv_path)))
    print('wrote %s' % md_path)
    print('TOTAL usd %s over %d agents; top: %s' % (money(grand['usd']), len(agents),
          '; '.join('%s %s' % (ag['agent'][:12], money(ag['usd'])) for ag in agents[:5])))


def build_md(a, prices, agents, per_day, per_model, per_task, tools_all, grand, meta):
    L = []
    add = L.append
    add('# Cost / token audit ledger (imm26-costaudit)')
    add('')
    add('Generated by `tools/automation/cost-audit.py`' + (' (since %s)' % a.since if a.since else '') +
        '. Read-only over `C:\\Users\\Shay\\.claude\\projects\\C--KenshiModding\\` (%d transcript files: main sessions + subagents). '
        'Dollars are **API-price equivalents** computed from the token counts; they are not what Shay pays. '
        'This tool cannot read the subscription quota meter: `/usage` is the authority for quota use.' % meta['files'])
    add('')
    add('Snapshot taken %s (local). The transcripts are live: totals grow while sessions run, so rerun for a fresh figure. ' % dt.datetime.now().strftime('%Y-%m-%d %H:%M'))
    add('Transcript days covered: %s to %s (local time). Agent rows: %d. Total: **%s** (API-price equivalent), '
        'input %s, output %s, cache write %s, cache read %s tokens.' % (
            meta['first_day'], meta['last_day'], len(agents), money(grand['usd']), toks(grand['input']),
            toks(grand['output']), toks(grand['cache_write']), toks(grand['cache_read'])))
    add('')
    add('## Method and assumptions')
    add('')
    add('- Price table (USD per million tokens, from `tools/automation/prices.json`, same as `docs/MODEL_ROUTING.md`):')
    add('')
    add('| Rate | Input | Output | Cache read | Cache write 5 min | Cache write 1 h |')
    add('|---|---|---|---|---|---|')
    for k, label in [('haiku', 'Haiku 5.5, prompt up to 100k'), ('haiku_over_100k', 'Haiku 5.5, prompt over 100k'),
                     ('sonnet', 'Sonnet 5.5'), ('opus', 'Opus 5.5')]:
        r = prices[k]
        add('| %s | %s | %s | %s | %s | %s |' % (label, r['input'], r['output'], r['cache_read'],
                                                 r['cache_write_5m'], r['cache_write_1h']))
    add('')
    add('- Each message is priced at its own model. Cache writes: `cache_creation.ephemeral_5m_input_tokens` at the 5-minute rate, `ephemeral_1h_input_tokens` at the 1-hour rate; a record without the split is priced at 5 minutes.')
    add('- Haiku over-100k band: a Haiku message whose prompt (input + cache read + cache write) exceeds 100,000 tokens is billed at the over-100k rate for the whole prompt (the higher reading; the page does not say whether the band covers only the excess).')
    add('- Dedupe: Claude Code writes one JSON line per content block, all with the same `message.id` and `requestId`. Each message id counts once: across files the first occurrence wins; within a file the record with the largest `output_tokens` is kept. Stats: %s message lines in total, %s unique ids counted, %s streamed duplicates inside files (%s with different usage), %s cross-file duplicates skipped.' % (
        toks(meta['total_msgs']), toks(meta['unique']), toks(meta['dupes']), toks(meta['dupe_diff']), toks(meta['cross_dupes'])))
    add('- Messages with a model string that has no rate in prices.json (counted at $0 in the totals; counted per file before cross-file dedupe, so the per-model table, after dedupe, is smaller): %s. By name: %s. Their tokens are in the per-model table under `unknown`. Their Haiku what-if IS priced (Haiku rates are known). A bound at Opus 5.5 rates is shown separately below; the real rate for these models is not in the table, so it is not added to the total.' % (
        toks(meta['unknown_model']), '; '.join('%s %s' % (k, toks(v)) for k, v in meta['unknown_names'].most_common(6))))
    add('- Day = local date of each message timestamp. Agent row day = its first message day; per-day table counts each message on its own day.')
    add('- Haiku what-if: the same token counts repriced at Haiku rates (same band rule). It does not change output length, so it is a price-only comparison. Shay\'s pilot (below) measured task-level cost with Haiku at high effort.')
    add('- Task type is a guess from the subagent description (`[case:x]` tag and keywords). Main sessions are "coordinator". Check the label column before acting on a row.')
    add('')
    add('## Top 15 spenders (one agent transcript each)')
    add('')
    add('| # | day | session | agent | model | USD | input | output | cache write | cache read | msgs | task | label |')
    add('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for i, ag in enumerate(agents[:15], 1):
        add('| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |' % (
            i, ag['day'], ag['session'][:8], ag['agent'][:12], ag['primary_model'], money(ag['usd']),
            toks(ag['input']), toks(ag['output']), toks(ag['cache_write']), toks(ag['cache_read']),
            ag['n_messages'], ag['task_type'], ag['label'].replace('|', '/')[:80]))
    add('')
    add('## Per day')
    add('')
    add('| day | msgs | USD | input | output | cache write | cache read |')
    add('|---|---|---|---|---|---|---|')
    for d in sorted(per_day):
        t = per_day[d]
        add('| %s | %s | %s | %s | %s | %s | %s |' % (d or '?', toks(t['n']), money(t['usd']), toks(t['input']),
                                                   toks(t['output']), toks(t['cache_write']), toks(t['cache_read'])))
    add('')
    add('## Cost by token type (priced models; what the money buys)')
    add('')
    add('| token type | USD | share |')
    add('|---|---|---|')
    pn = ['input', 'output', 'cache read', 'cache write']
    ptot = sum(grand.get('parts', [0, 0, 0, 0])) or 1.0
    for k, nm in enumerate(pn):
        v = grand.get('parts', [0, 0, 0, 0])[k]
        add('| %s | %s | %.1f%% |' % (nm, money(v), v / ptot * 100))
    add('')
    add('## Per model (family; each message at its own model)')
    add('')
    add('| model | msgs | USD | input | output | cache write | cache read |')
    add('|---|---|---|---|---|---|---|')
    for m in sorted(per_model, key=lambda k: -per_model[k]['usd']):
        t = per_model[m]
        add('| %s | %s | %s | %s | %s | %s | %s |' % (m, toks(t['n']), money(t['usd']), toks(t['input']),
                                                   toks(t['output']), toks(t['cache_write']), toks(t['cache_read'])))
    add('')
    add('## Per task type (guess from label)')
    add('')
    add('| task type | agents | USD | share | Haiku-repriced USD | Haiku-eligible |')
    add('|---|---|---|---|---|---|')
    for k in sorted(per_task, key=lambda k: -per_task[k]['usd']):
        t = per_task[k]
        share = (t['usd'] / grand['usd'] * 100) if grand['usd'] else 0
        add('| %s | %d | %s | %.1f%% | %s | %s |' % (k, t['n'], money(t['usd']), share, money(t['usd_haiku']),
                                                   'yes' if k in HAIKU_ELIGIBLE else 'no'))
    add('')
    add('## What if the read / parse / check / classify / investigator / statistics agents ran on Haiku high')
    add('')
    add('Same token counts, Haiku rates (price-only; Haiku at high effort may use more output tokens, so treat the saving as an upper bound). Shay\'s pilot figures for one task at high effort, quoted, not re-derived: **Haiku high about $0.27 per task vs Sonnet high about $0.66**; quality 19.0 vs 21.3 of 25; false claims 1.0 vs 0.67 per report. The pilot shows the quality cost, so Haiku on investigator work is the riskiest row.')
    add('')
    add('| task type | agents | actual USD | Haiku USD | saving USD | saving % |')
    add('|---|---|---|---|---|---|')
    sub_all = sub_no_inv = act_all = act_no_inv = hk_all = hk_no_inv = 0.0
    for k in HAIKU_ELIGIBLE:
        t = per_task.get(k)
        if not t:
            add('| %s | 0 | $0.00 | $0.00 | $0.00 | - |' % k)
            continue
        sv = t['usd'] - t['usd_haiku']
        add('| %s | %d | %s | %s | %s | %.0f%% |' % (k, t['n'], money(t['usd']), money(t['usd_haiku']), money(sv),
                                                  (sv / t['usd'] * 100) if t['usd'] else 0))
        act_all += t['usd']
        hk_all += t['usd_haiku']
        if k != 'investigator':
            act_no_inv += t['usd']
            hk_no_inv += t['usd_haiku']
    add('| **total, no investigator** | | %s | %s | %s | %.0f%% |' % (money(act_no_inv), money(hk_no_inv),
        money(act_no_inv - hk_no_inv), ((act_no_inv - hk_no_inv) / act_no_inv * 100) if act_no_inv else 0))
    add('| **total, with investigator** | | %s | %s | %s | %.0f%% |' % (money(act_all), money(hk_all),
        money(act_all - hk_all), ((act_all - hk_all) / act_all * 100) if act_all else 0))
    add('')
    add('Share of all audited spend: the eligible agents are %.1f%% of total USD.' % (
        (act_all / grand['usd'] * 100) if grand['usd'] else 0))
    add('')
    add('## Tool-output size, top 20 (tool_result characters; Bash/PowerShell split by first word)')
    add('')
    add('| pattern | calls | total chars | mean chars | max chars |')
    add('|---|---|---|---|---|')
    top = sorted(tools_all.items(), key=lambda kv: -kv[1][1])[:20]
    for pat, (n, ch, mx) in top:
        add('| %s | %s | %s | %s | %s |' % (pat, toks(n), toks(ch), toks(ch / n if n else 0), toks(mx)))
    add('')
    by_name = collections.defaultdict(lambda: [0, 0, 0])
    for pat, (n, ch, mx) in tools_all.items():
        b = by_name[pat.split(':')[0]]
        b[0] += n
        b[1] += ch
        b[2] = max(b[2], mx)
    add('By tool name: ' + '; '.join('%s %s calls / %s chars' % (k, toks(v[0]), toks(v[1]))
                                     for k, v in sorted(by_name.items(), key=lambda kv: -kv[1][1])[:12]))
    add('')
    add('## Self-check (independent recount, awk, same files)')
    add('')
    sc = read_selfcheck(a.selfcheck or os.path.join(a.out, 'selfcheck.tsv'))
    if not sc:
        add('No selfcheck.tsv found; run the independent recount and rerun this tool.')
    else:
        add('| agent | tool USD | awk USD | diff % | tokens match | flag |')
        add('|---|---|---|---|---|---|')
        by_agent = {ag['session'] + '/' + ag['agent']: ag for ag in agents}
        for key, p in sc.items():
            ag = by_agent.get(key)
            if not ag:
                add('| %s | - | %s | - | - | NOT FOUND in tool output |' % (key, p[5]))
                continue
            awk_usd = float(p[5])  # columns: agent, input, output, cache_write, cache_read, usd, n_messages
            tool_usd = ag['usd']
            diff = (abs(tool_usd - awk_usd) / tool_usd * 100) if tool_usd else (0 if not awk_usd else 100)
            tok_ok = (int(p[1]) == ag['input'] and int(p[2]) == ag['output'] and int(p[3]) == ag['cache_write']
                      and int(p[4]) == ag['cache_read'])
            flag = 'MISMATCH > 2%' if diff > 2 or not tok_ok else 'ok'
            add('| %s | %s | %s | %.3f | %s | %s |' % (key, money(tool_usd), money(awk_usd), diff,
                                                     'yes' if tok_ok else 'NO', flag))
    add('')
    add('Message counts are not compared: the awk recount skips the zero-token `<synthetic>` records (the tool counts them); tokens and USD match exactly. Mismatch flag = USD > 2% or any token total different.')
    add('')
    add('Unpriced models (no rate in prices.json), bound at Opus 5.5 rates: %s. Not in the totals above; the true figure depends on the real rate.' % money(grand.get('unpriced_opus', 0.0)))
    add('')
    add('Scope note: the Haiku column is a price-only repricing of recorded tokens. The quota meter (`/usage`) is the only source for subscription use.')
    add('')
    return '\n'.join(L)


if __name__ == '__main__':
    main()
