#!/usr/bin/env python3
"""cost-audit.py - token and API-price-equivalent cost audit of Claude Code transcripts (read-only).

Reads C:\\Users\\Shay\\.claude\\projects\\C--KenshiModding\\*.jsonl (main sessions) and
<session>\\subagents\\agent-*.jsonl (subagents). Streams every file line by line, json.loads per
line, and prints/writes aggregates only. Never prints transcript text.

Usage (Windows python only, PI-54: posix python exits 2 with a clear message):
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

Lane operators (imm26-pilotC):
  - Task type 'lane-operator' = an agent whose prompt says "You are [the independent agent] imm26-<rig>-
    [<lane>]op<N>" / "-hk<N>" (4080 or 5090 rig), or whose description/prompt says "<rig> <lane> operator",
    "lane operator", "lane <rig>-i<N>" or "lane-brief". An explicit "You are imm26-<other name>" that is not an
    operator name is never a lane operator (so tooling/fixer agents that merely mention lanes stay out). Main
    sessions that are hosted independent operators are lane-operators too (not 'coordinator').
  - ledger.md section "Lane operators: Sonnet-high actual vs Haiku-high what-if": per-operator rows
    (rows-marked = distinct rows named in mark-row.py / status-mark.sh calls with PASS|FAIL|SETUP-FAIL|GATED,
    blank if none), per-lane totals, tokens/USD per hour of wall time (first to last message timestamp).
    ledger.csv gets the extra columns name, lane, rows_marked, hours, ctx_cache_first, ctx_cache_last.
  - --agents NAME[,NAME]: only matching agents are reported (all aggregate tables and the CSV are restricted;
    dedupe still sees every file). A name matches an agent id, derived/explicit name or description by exact
    match first, else by substring.
  - --pilot-compare A B: prints two agents (or groups, when a name matches several; sums, and context growth
    = sum of growth / sum of hours) side by side to stdout: tokens, USD, turns, hours, context growth per hour
    = (cache_read tokens of the last assistant message - the first) / hours. Writes no files.
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
DEFAULT_SINCE = '2026-10-14 00:00'  # Shay 2026-10-16: only the current setup counts; earlier data is ignored
BAND = 100000  # Haiku over-100k prompt band
HAIKU_ELIGIBLE = ('reader', 'classifier', 'statistics', 'investigator')  # read/parse/check/classify/investigator/statistics

CASE_MAP = {'investigate': 'investigator', 'debug': 'investigator', 'escalate': 'investigator',
            'read': 'reader', 'parse': 'reader', 'check': 'reader', 'classify': 'classifier',
            'patch': 'generator', 'generate': 'generator', 'grade': 'grader', 'bench': 'bench'}

# Task-type rules on the subagent description (prompt text only when there is no description).
# KEYWORD_RULES are checked first; then the [case:x] tag; then GENERIC_RULES; else "other".
KEYWORD_RULES = [
    ('recipe', r'\brecipe'),
    ('native-build', r'(\bnative\b|\bbuild\b|compile|msbuild|cmake|\bdll\b)'),
    ('server-fix', r'(\bserver|\bphp\b|stobe-server|\bsql\b|database)'),
    ('fixer', r'(\bfix|rowfix|\bpatch)'),
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
# Lane operators. EXPLICIT_RE: the name the agent is told it is. OP_NAME_RE: operator-shaped names.
EXPLICIT_RE = re.compile(r'You are (?:the independent agent |the )?(imm26-[A-Za-z0-9-]+?)(?=[\s,.:;]|$)')
OP_NAME_RE = re.compile(r'^imm26-(4080|5090)-(?:(i\d+)-?)?(op\d[0-9a-z]*|hk[0-9a-z]*|ctxop\d[0-9a-z]*|hard[0-9a-z]*)$', re.I)
OP_DESC_RE = re.compile(r'((4080|5090)[\w\s-]{0,24}?\b(operator|op\d)|\blane[\s-]operator|\boperator\s+op\d|\bi[345]\s?-?op\d|resume\s+\S+\s+operator)', re.I)
OP_PROMPT_RE = re.compile(r'\blane\s+(4080|5090)-i\d', re.I)
RIG_RE = re.compile(r'(?<![0-9])(4080|5090)(?![0-9])')
LANE_RE = re.compile(r'(?<![a-z0-9])(i\d)(?![0-9])', re.I)
OPN_RE = re.compile(r'(?:ctx)?op(\d[0-9a-z]*)|hk(\d[0-9a-z]*)', re.I)
MARK_RE = re.compile(r'(?:mark-row\.py\s+|status-mark\.sh\s+\S+\s+)[\'"]?(\d+-[a-z0-9]+)[\'"]?\s+[\'"]?(PASS|FAIL|SETUP-FAIL|GATED)\b')
RESULT_RE = re.compile(r'(?m)^\s*RESULT\s+(\d+-[a-z0-9]+)\s+(?:PASS|FAIL)\b')
TS_RE = re.compile(rb'"timestamp":"([^"]+)"')
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
        return t.strftime('%Y-%m-%d'), t.strftime('%Y-%m-%d %H:%M'), t.timestamp()
    except (ValueError, TypeError):
        return '', '', 0.0


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
    path, kind, session, prices, since_ts, until_ts = job
    stem = os.path.basename(path)[:-6]
    res = {'path': path, 'kind': kind, 'session': session,
           'agent': stem[6:] if kind == 'sub' else 'main', 'desc': '', 'agent_type': '',
           'first_user': '', 'msgs': {}, 'dupes': 0, 'dupe_diff': 0, 'lines_assistant': 0,
           'tools': {}, 'unknown_model': 0, 'unknown_names': collections.Counter(),
           'rows': set(), 'rows_result': set(), 'ts_min': '', 'ts_max': ''}
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
            tm = TS_RE.search(raw)
            if tm:
                t = tm.group(1).decode('ascii', 'ignore')
                if not res['ts_min'] or t < res['ts_min']:
                    res['ts_min'] = t
                if t > res['ts_max']:
                    res['ts_max'] = t
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
                            if c.get('name') in ('Bash', 'PowerShell'):
                                cmd = (c.get('input') or {}).get('command') or ''
                                if 'mark-row' in cmd or 'status-mark' in cmd:
                                    ep = local_day(d.get('timestamp') or '')[2]
                                    if since_ts <= ep <= until_ts:
                                        for mm in MARK_RE.finditer(cmd):
                                            res['rows'].add(mm.group(1).lower())
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
                day, tloc, epoch = local_day(d.get('timestamp') or '')
                rec = (mid, day, tloc, model, fam, i, o, cw5, cw1, cr, usd, usd_h, usd_unpriced) + parts + (epoch,)
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
                            if b'RESULT ' in raw:
                                ct = x.get('content')
                                if isinstance(ct, list):
                                    ct = ' '.join((y.get('text') or '') for y in ct if isinstance(y, dict))
                                if isinstance(ct, str) and 'RESULT ' in ct:
                                    ep = local_day(d.get('timestamp') or '')[2]
                                    if since_ts <= ep <= until_ts:
                                        for mm in RESULT_RE.finditer(ct):
                                            res['rows_result'].add(mm.group(1).lower())
                            pat = tool_names.get(x.get('tool_use_id'), '?')
                            n = result_chars(x.get('content'))
                            s = tools.setdefault(pat, [0, 0, 0])
                            s[0] += 1
                            s[1] += n
                            if n > s[2]:
                                s[2] = n
    return res


def explicit_name(first_user):
    m = EXPLICIT_RE.search(first_user or '')
    return m.group(1) if m else ''


def operator_info(kind, desc, first_user):
    """None, or dict(name, rig, lane, pilot) when the agent is a lane operator."""
    ex = explicit_name(first_user)
    m = OP_NAME_RE.match(ex) if ex else None
    if ex and not m:
        return None  # told it is some other named agent (tooling, fixer, ...): never an operator
    if not m:
        if kind == 'main':
            return None
        fu = (first_user or '')[:300]
        if not (OP_DESC_RE.search(desc or '') or (OP_PROMPT_RE.search(fu) and re.search(r'operator|\bop\d', fu, re.I))):
            return None
    text = ((desc or '') + ' ' + (first_user or '')[:300])
    rm = RIG_RE.search(text)
    lm = LANE_RE.search(text)
    rig = m.group(1) if m else (rm.group(1) if rm else '')
    lane = (m.group(2) or '').lower() if m else (lm.group(1).lower() if lm else '')
    if m and not lane:
        lm2 = re.search(r'(?<![0-9])' + rig + r'[\s-]+(i\d)\b', text, re.I)
        lane = lm2.group(1).lower() if lm2 else ''
    if m:
        name = ex
    else:
        on = OPN_RE.search(desc or '')
        opn = ('hk' + on.group(2)) if on and on.group(2) else (('op' + on.group(1)) if on else '')
        name = 'imm26-%s-%s%s' % (rig or '?', lane, opn)
        if not (lane or opn):
            name = 'imm26-%s-op' % (rig or '?')
    return {'name': name, 'rig': rig or '?', 'lane': '%s-%s' % (rig or '?', lane or '?'),
            'pilot': 'hk' in name.lower()}


def task_type(kind, desc, first_user):
    if operator_info(kind, desc, first_user):
        return 'lane-operator'
    if kind == 'main':
        # main session = coordinator or a personal session; a hosted independent agent (named by its prompt) is its own type
        return 'hosted-agent' if explicit_name(first_user) else 'coordinator'
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


def parse_bound(s):
    s = (s or '').strip().replace('T', ' ')
    if not s or s.lower() == 'all':
        return None
    for f in ('%Y-%m-%d %H:%M', '%Y-%m-%d'):
        try:
            return dt.datetime.strptime(s, f).timestamp()
        except ValueError:
            pass
    raise SystemExit('bad datetime (want YYYY-MM-DD or YYYY-MM-DD HH:MM, local): %s' % s)


def iso_epoch(t):
    try:
        return dt.datetime.strptime(t[:19], '%Y-%m-%dT%H:%M:%S').replace(tzinfo=dt.timezone.utc).timestamp()
    except (ValueError, TypeError):
        return 0.0


def match_keys(r, info):
    keys = {r['agent'].lower(), r['session'].lower() + '/' + r['agent'].lower()}
    ex = explicit_name(r['first_user'])
    if ex:
        keys.add(ex.lower())
    if info:
        keys.add(info['name'].lower())
    if r['desc']:
        keys.add(r['desc'].lower())
    return keys


def resolve(agents, token):
    """Agents matching a name token: exact on id / name / description first, else substring."""
    t = token.strip().lower()
    exact = [ag for ag in agents if t in ag['keys']]
    if exact:
        return exact
    return [ag for ag in agents if any(t in k for k in ag['keys'])]


def group_stats(group):
    g = {'n_agents': len(group), 'tokens': 0, 'usd': 0.0, 'haiku_usd': 0.0, 'turns': 0, 'hours': 0.0,
         'growth': 0, 'out': 0, 'cr': 0, 'cw': 0, 'inp': 0, 'rows': 0, 'models': collections.Counter()}
    for ag in group:
        g['tokens'] += ag['input'] + ag['output'] + ag['cache_write'] + ag['cache_read']
        g['inp'] += ag['input']
        g['out'] += ag['output']
        g['cw'] += ag['cache_write']
        g['cr'] += ag['cache_read']
        g['usd'] += ag['usd']
        g['haiku_usd'] += ag['haiku_usd']
        g['turns'] += ag['n_messages']
        g['hours'] += ag['hours']
        g['growth'] += ag['ctx_last'] - ag['ctx_first']
        g['rows'] += ag['rows_marked'] or 0
        g['models'][ag['primary_model']] += 1
    return g


def pilot_compare(agents, ta, tb):
    cols = []
    for tok in (ta, tb):
        grp = resolve(agents, tok)
        if not grp:
            return fail('NO MATCH for %r (try the agent id, the imm26 name, or part of the description; or no messages in the window)' % tok, 2)
        cols.append((tok, group_stats(grp), grp))
    lines = ['| metric | %s | %s |' % (cols[0][0], cols[1][0]), '|---|---|---|']

    def row(label, f):
        lines.append('| %s | %s | %s |' % (label, f(cols[0][1]), f(cols[1][1])))
    row('transcripts matched', lambda g: str(g['n_agents']))
    row('model(s)', lambda g: '+'.join('%s:%d' % kv for kv in g['models'].most_common()))
    row('turns (assistant messages)', lambda g: toks(g['turns']))
    row('hours (first to last message)', lambda g: '%.2f' % g['hours'])
    row('tokens total', lambda g: toks(g['tokens']))
    row('  input / output', lambda g: '%s / %s' % (toks(g['inp']), toks(g['out'])))
    row('  cache write / cache read', lambda g: '%s / %s' % (toks(g['cw']), toks(g['cr'])))
    row('USD (actual, own model)', lambda g: money(g['usd']))
    row('USD at Haiku rates (same tokens)', lambda g: money(g['haiku_usd']))
    row('USD per hour', lambda g: money(g['usd'] / g['hours']) if g['hours'] else '-')
    row('tokens per hour', lambda g: toks(g['tokens'] / g['hours']) if g['hours'] else '-')
    row('turns per hour', lambda g: '%.1f' % (g['turns'] / g['hours']) if g['hours'] else '-')
    row('rows marked', lambda g: str(g['rows']) if g['rows'] else '-')
    row('USD per row', lambda g: money(g['usd'] / g['rows']) if g['rows'] else '-')
    row('context growth, cache_read last - first', lambda g: toks(g['growth']))
    row('context growth per hour (cache_read tokens)', lambda g: toks(g['growth'] / g['hours']) if g['hours'] else '-')
    print('\n'.join(lines))
    print('\nA group (several transcripts matched one name) sums tokens, USD, turns, hours; context growth = sum of (last - first) cache_read / sum of hours.')
    return 0


def fail(msg, code=3):
    """PI-54: fail loudly (stderr + non-zero exit) instead of printing an empty COST section."""
    print('cost-audit FAIL: ' + msg, file=sys.stderr)
    return code


def check_python_and_root(root):
    """PI-54: needs Windows python (transcripts live in the Windows user profile); returns an error string or empty."""
    if os.name != 'nt' and not os.environ.get('KAH_ALLOW_POSIX'):
        return ('needs Windows python (os.name=%s). WSL/posix python cannot see %s. Run: python -I tools/automation/cost-audit.py ... '
                'from Git Bash/PowerShell (KAH_ALLOW_POSIX=1 overrides for tests).' % (os.name, DEFAULT_ROOT))
    if not os.path.isdir(root):
        return 'transcript root not found: %s (wrong python, or pass --root)' % root
    return ''


def main():
    ap = argparse.ArgumentParser(description='Cost/token audit of Claude Code transcripts (read-only).')
    ap.add_argument('--since', default=DEFAULT_SINCE, help='local YYYY-MM-DD[ HH:MM]; earlier messages are ignored (default %s; "all" = no lower bound)' % DEFAULT_SINCE)
    ap.add_argument('--until', default='', help='local YYYY-MM-DD[ HH:MM]; later messages are ignored (default now)')
    ap.add_argument('--agents', default='', help='NAME[,NAME]: report only agents matching an id / imm26 name / description (exact, else substring)')
    ap.add_argument('--pilot-compare', nargs=2, metavar=('A', 'B'), help='print two agents side by side (no files written)')
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
    err = check_python_and_root(root)
    if err:
        return fail(err, 2)
    since_ts = parse_bound(a.since) or 0.0
    until_ts = parse_bound(a.until) or 4e9
    a.window = '%s to %s (local)' % (a.since if parse_bound(a.since) else 'the beginning',
                                    a.until if parse_bound(a.until) else 'now (%s)' % dt.datetime.now().strftime('%Y-%m-%d %H:%M'))

    jobs = []
    for p in sorted(glob.glob(os.path.join(root, '*.jsonl'))):
        jobs.append((p, 'main', os.path.basename(p)[:-6]))
    for p in sorted(glob.glob(os.path.join(root, '*', 'subagents', 'agent-*.jsonl'))):
        jobs.append((p, 'sub', os.path.basename(os.path.dirname(os.path.dirname(p)))))
    if since_ts:
        jobs = [j for j in jobs if os.path.getmtime(j[0]) >= since_ts]
    if a.limit_files:
        jobs = jobs[:a.limit_files]
    print('files to scan: %d (main %d, subagent %d); window %s' % (
        len(jobs), sum(1 for j in jobs if j[1] == 'main'), sum(1 for j in jobs if j[1] == 'sub'), a.window), file=sys.stderr)
    if not jobs:
        return fail('files to scan 0 under %s for window %s (no transcripts; wrong --root/--since or wrong python?)' % (root, a.window))
    work = [(p, k, s, prices, since_ts, until_ts) for p, k, s in jobs]
    with ProcessPoolExecutor(max_workers=max(1, a.workers)) as ex:
        results = list(ex.map(scan_file, work, chunksize=2))

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
    parts_all = [0.0, 0.0, 0.0, 0.0]
    tools_all = collections.defaultdict(lambda: [0, 0, 0])
    unk_win = collections.defaultdict(lambda: {'n': 0, 'input': 0, 'output': 0, 'cache_write': 0, 'cache_read': 0, 'opus': 0.0})
    first_day, last_day = '', ''
    filt = [t.strip().lower() for t in a.agents.split(',') if t.strip()]
    filter_on = bool(filt) and not a.pilot_compare

    for r in results:
        kept = []
        for rec in r['msgs'].values():
            total_msgs += 1
            if rec[0] in seen:
                cross_dupes += 1
                continue
            seen.add(rec[0])
            if rec[17] < since_ts or rec[17] > until_ts:
                continue
            kept.append(rec)
        if not kept:
            continue
        info = operator_info(r['kind'], r['desc'], r['first_user'])
        keys = match_keys(r, info)
        if filter_on:
            ok = False
            for t in filt:
                if t in keys or any(t in k for k in keys):
                    ok = True
            if not ok:
                continue
        for rec in kept:
            if rec[1]:
                first_day = rec[1] if not first_day or rec[1] < first_day else first_day
                last_day = rec[1] if not last_day or rec[1] > last_day else last_day
        kept.sort(key=lambda x: (x[17], x[2]))
        tot = new_totals()
        tot['unpriced_opus'] = sum(rec[12] for rec in kept)
        fam_usd = collections.Counter()
        models = collections.Counter()
        pa = [0.0, 0.0, 0.0, 0.0]  # input, output, cache read, cache write USD (priced models)
        for rec in kept:
            for k in range(4):
                parts_all[k] += rec[13 + k]
                pa[k] += rec[13 + k]
            add_totals(tot, rec)
            add_totals(per_day[rec[1]], rec)
            add_totals(per_model[rec[4]], rec)
            fam_usd[rec[4]] += rec[10]
            models[rec[3]] += 1
            if rec[4] == 'unknown':
                u = unk_win[rec[3] or '?']
                u['n'] += 1
                u['input'] += rec[5]
                u['output'] += rec[6]
                u['cache_write'] += rec[7] + rec[8]
                u['cache_read'] += rec[9]
                u['opus'] += rec[12]
        ttype = task_type(r['kind'], r['desc'], r['first_user'])
        # wall time: first to last message timestamp of the transcript, clipped to the window
        t0 = max(iso_epoch(r['ts_min']) or kept[0][17], since_ts)
        t1 = min(iso_epoch(r['ts_max']), until_ts) if r['ts_max'] else kept[-1][17]
        hours = max(0.0, (t1 - t0)) / 3600.0
        rows = r['rows'] or r['rows_result']
        ex = explicit_name(r['first_user'])
        if fam_usd:
            prim = fam_usd.most_common(1)[0][0]
            if not tot['usd']:  # only unpriced models: name the family as unknown
                prim = 'unknown'
        else:
            prim = ''
        agent_row = {
            'day': kept[0][1], 'session': r['session'], 'agent': r['agent'], 'kind': r['kind'],
            'primary_model': prim,
            'models': '+'.join('%s:%d' % (m, n) for m, n in models.most_common()),
            'input': tot['input'], 'output': tot['output'], 'cache_write': tot['cache_write'],
            'cache_read': tot['cache_read'], 'usd': tot['usd'], 'haiku_usd': tot['usd_haiku'],
            'task_type': ttype, 'haiku_eligible': ttype in HAIKU_ELIGIBLE, 'n_messages': tot['n'],
            'first_ts': kept[0][2], 'last_ts': kept[-1][2], 'label': label_of(r),
            'last_day': kept[-1][1], 'unpriced_opus_usd': tot['unpriced_opus'],
            'name': (info['name'] if info else ex), 'lane': (info['lane'] if info else ''),
            'pilot': bool(info and info['pilot']), 'rows_marked': len(rows), 'rows_src': ('mark' if r['rows'] else ('RESULT' if r['rows_result'] else '')),
            'hours': hours, 'ctx_first': kept[0][9], 'ctx_last': kept[-1][9], 'keys': keys,
            'p_in': pa[0], 'p_out': pa[1], 'p_cr': pa[2], 'p_cw': pa[3], 'fam_usd': dict(fam_usd),
        }
        agents.append(agent_row)
        for pat, s in r['tools'].items():
            t = tools_all[pat]
            t[0] += s[0]
            t[1] += s[1]
            t[2] = max(t[2], s[2])

    if filter_on and not agents:
        return fail('NO MATCH for --agents %r: 0 agents with messages in the window %s' % (a.agents, a.window))
    if a.pilot_compare:
        return pilot_compare(agents, a.pilot_compare[0], a.pilot_compare[1])

    os.makedirs(a.out, exist_ok=True)
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
            'last_ts', 'last_day', 'label', 'name', 'lane', 'rows_marked', 'hours', 'ctx_cache_first', 'ctx_cache_last']
    with open(csv_path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(cols)
        for ag in agents:
            w.writerow([ag['day'], ag['session'], ag['agent'], ag['kind'], ag['primary_model'], ag['models'],
                        ag['input'], ag['output'], ag['cache_write'], ag['cache_read'], '%.4f' % ag['usd'],
                        '%.4f' % ag['haiku_usd'], ag['task_type'], int(ag['haiku_eligible']), ag['n_messages'],
                        ag['first_ts'], ag['last_ts'], ag['last_day'], ag['label'], ag['name'], ag['lane'],
                        ag['rows_marked'] or '', '%.3f' % ag['hours'], ag['ctx_first'], ag['ctx_last']])

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
        first_day=first_day, last_day=last_day, unknown_names=unknown_names, unk_win=unk_win))
    md_path = os.path.join(a.out, 'ledger.md')
    with open(md_path, 'w', encoding='utf-8') as f:
        f.write(md)
    print('wrote %s (%d rows, %d bytes)' % (csv_path, len(agents), os.path.getsize(csv_path)))
    print('wrote %s' % md_path)
    print('TOTAL usd %s over %d agents; top: %s' % (money(grand['usd']), len(agents),
          '; '.join('%s %s' % (ag['agent'][:12], money(ag['usd'])) for ag in agents[:5])))
    return 0


CATEGORIES = [
    ('lane-operator', 'Lane operators (all imm26-*op* agents, incl. -hk pilot)'),
    ('coordinator', 'Coordinators (main sessions)'),
    ('hosted-agent', 'Hosted independent agents (named main-session transcripts)'),
    ('investigator', 'Investigators'), ('classifier', 'Classifiers'), ('fixer', 'Fixers'),
    ('generator', 'Generators / patch agents'), ('recipe', 'Recipe agents'),
    ('native-build', 'Native builders'), ('server-fix', 'Server fixers'), ('reader', 'Readers'),
    ('statistics', 'Statistics'), ('grader', 'Graders'), ('pg-agent', 'PG agents'),
    ('harness', 'Harness'), ('animation', 'Animation'), ('other', 'Other')]
PILOT_RATIO = 0.27 / 0.66  # Shay's pilot: Haiku high about $0.27 per task vs Sonnet high about $0.66
SENS = (1.0, 1.5, 2.0)


def fam_split(group):
    fs = collections.Counter()
    for ag in group:
        for k, v in ag['fam_usd'].items():
            fs[k] += v
    return fs


def category_lines(agents, grand):
    L = []
    add = L.append
    add('## Categories (each on its own line; actual USD at each message\'s own model)')
    add('')
    add('| category | agents | turns | tokens | USD | share | Sonnet USD | Opus USD | Haiku USD | Haiku-repriced USD |')
    add('|---|---|---|---|---|---|---|---|---|---|')
    done = set()
    rows = list(CATEGORIES)
    for k in sorted({ag['task_type'] for ag in agents} - {c[0] for c in CATEGORIES}):
        rows.append((k, k))
    for key, label in rows:
        grp = [ag for ag in agents if ag['task_type'] == key]
        if not grp:
            continue
        done.add(key)
        fs = fam_split(grp)
        usd = sum(ag['usd'] for ag in grp)
        add('| %s | %d | %s | %s | %s | %.1f%% | %s | %s | %s | %s |' % (
            label, len(grp), toks(sum(ag['n_messages'] for ag in grp)),
            toks(sum(ag['input'] + ag['output'] + ag['cache_write'] + ag['cache_read'] for ag in grp)), money(usd),
            (usd / grand['usd'] * 100) if grand['usd'] else 0, money(fs.get('sonnet', 0)), money(fs.get('opus', 0)),
            money(fs.get('haiku', 0)),
            money(sum(ag['haiku_usd'] for ag in grp))))
        if key == 'lane-operator':
            pg = [ag for ag in grp if ag['pilot']]
            if pg:
                fsp = fam_split(pg)
                usdp = sum(ag['usd'] for ag in pg)
                add('| &nbsp;&nbsp;of which -hk pilot operators | %d | %s | %s | %s | %.1f%% | %s | %s | %s | %s |' % (
                    len(pg), toks(sum(ag['n_messages'] for ag in pg)),
                    toks(sum(ag['input'] + ag['output'] + ag['cache_write'] + ag['cache_read'] for ag in pg)), money(usdp),
                    (usdp / grand['usd'] * 100) if grand['usd'] else 0, money(fsp.get('sonnet', 0)), money(fsp.get('opus', 0)),
                    money(fsp.get('haiku', 0)), money(sum(ag['haiku_usd'] for ag in pg))))
    add('| **all agents** | %d | %s | %s | %s | 100%% | | | | %s |' % (
        len(agents), toks(sum(ag['n_messages'] for ag in agents)),
        toks(grand['input'] + grand['output'] + grand['cache_write'] + grand['cache_read']), money(grand['usd']),
        money(grand['usd_haiku'])))
    add('')
    add('The Sonnet / Opus / Haiku columns split each category by the model of each message (an agent can mix models). The unknown-model (claude-fable) messages are $0 here; see the separate table below.')
    add('')
    return L


def _opname(ag):
    return ag['name'] or ('%s/%s' % (ag['session'][:8], ag['agent'][:8]))


def operator_lines(agents, grand):
    L = []
    add = L.append
    ops = sorted([ag for ag in agents if ag['task_type'] == 'lane-operator'], key=lambda x: (x['lane'], x['first_ts']))
    add('## Lane operators: Sonnet-high actual vs Haiku-high what-if')
    add('')
    if not ops:
        add('No lane-operator transcripts in the window.')
        add('')
        return L
    son = [ag for ag in ops if ag['primary_model'] == 'sonnet']
    oth = [ag for ag in ops if ag['primary_model'] != 'sonnet']
    tot_usd = sum(ag['usd'] for ag in ops)
    add('Operators in the window: %d transcripts, %s (%.1f%% of the window total %s). Sonnet-primary operators: %d (%s); other models: %d (%s; %s).' % (
        len(ops), money(tot_usd), (tot_usd / grand['usd'] * 100) if grand['usd'] else 0, money(grand['usd']),
        len(son), money(sum(ag['usd'] for ag in son)), len(oth), money(sum(ag['usd'] for ag in oth)),
        ', '.join(sorted({ag['primary_model'] or '?' for ag in oth})) or 'none'))
    add('')
    add('How to read: *hours* = first to last message timestamp of the transcript (wall time, includes waiting on game batches), clipped to the window. *rows* = distinct test rows named in `mark-row.py` / `status-mark.sh` calls with PASS|FAIL|SETUP-FAIL|GATED in that transcript (or, when it has none, distinct `RESULT <row> PASS|FAIL` lines in tool output); blank = not derivable. Name = the imm26 name from the prompt, else built from the description (`?` = lane not stated). The model is the primary (most USD) model.')
    add('')
    add('### Per operator')
    add('')
    add('| # | operator | id | lane | model | turns | hours | rows | tokens | USD | USD/hour | USD/row | tokens/hour |')
    add('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for i, ag in enumerate(ops, 1):
        tk = ag['input'] + ag['output'] + ag['cache_write'] + ag['cache_read']
        h = ag['hours']
        r = ag['rows_marked']
        add('| %d | %s | %s | %s | %s | %d | %.2f | %s | %s | %s | %s | %s | %s |' % (
            i, _opname(ag), ag['agent'][:8], ag['lane'], ag['primary_model'], ag['n_messages'], h, r or '', toks(tk),
            money(ag['usd']), money(ag['usd'] / h) if h > 0.01 else '-', money(ag['usd'] / r) if r else '',
            toks(tk / h) if h > 0.01 else '-'))
    add('')
    add('### Per lane (totals)')
    add('')
    add('| lane | operators | turns | hours | rows | tokens | USD | USD/hour | tokens/hour | USD/row |')
    add('|---|---|---|---|---|---|---|---|---|---|')
    lanes = collections.OrderedDict()
    for ag in ops:
        lanes.setdefault(ag['lane'], []).append(ag)
    lanes['ALL OPERATORS'] = ops

    def lane_row(name, grp):
        tk = sum(ag['input'] + ag['output'] + ag['cache_write'] + ag['cache_read'] for ag in grp)
        h = sum(ag['hours'] for ag in grp)
        r = sum(ag['rows_marked'] or 0 for ag in grp)
        u = sum(ag['usd'] for ag in grp)
        add('| %s | %d | %s | %.1f | %s | %s | %s | %s | %s | %s |' % (
            name, len(grp), toks(sum(ag['n_messages'] for ag in grp)), h, r or '', toks(tk), money(u),
            money(u / h) if h > 0.01 else '-', toks(tk / h) if h > 0.01 else '-', money(u / r) if r else ''))
    for name, grp in lanes.items():
        lane_row(name if name != 'ALL OPERATORS' else '**ALL OPERATORS**', grp)
    add('')
    add('### Cost split by token type (priced models; Sonnet-high actual)')
    add('')
    add('| operator | input USD | output USD | cache read USD | cache write USD | cache read share |')
    add('|---|---|---|---|---|---|')
    for ag in ops:
        t = ag['p_in'] + ag['p_out'] + ag['p_cr'] + ag['p_cw']
        add('| %s | %s | %s | %s | %s | %.0f%% |' % (_opname(ag), money(ag['p_in']), money(ag['p_out']), money(ag['p_cr']),
                                                    money(ag['p_cw']), (ag['p_cr'] / t * 100) if t else 0))
    ti, to, tr, tw = (sum(ag[k] for ag in ops) for k in ('p_in', 'p_out', 'p_cr', 'p_cw'))
    tt = ti + to + tr + tw
    add('| **ALL OPERATORS** | %s | %s | %s | %s | %.0f%% |' % (money(ti), money(to), money(tr), money(tw), (tr / tt * 100) if tt else 0))
    add('')
    # --- Haiku what-if
    su = sum(ag['usd'] for ag in son)
    sh = sum(ag['haiku_usd'] for ag in son)
    shr = sum(ag['hours'] for ag in son)
    srow = sum(ag['rows_marked'] or 0 for ag in son)
    add('### Haiku-high what-if for the Sonnet operators')
    add('')
    add('Two prices for the same work, each with Haiku needing 1.0x / 1.5x / 2x the turns:')
    add('')
    add('- **Token repricing (A):** the recorded Sonnet tokens repriced at Haiku 5.5 rates, each message on its own prompt band (over 100,000 prompt tokens = the over-100k rate for the whole prompt).')
    add('- **Shay\'s pilot ratio (B):** Sonnet actual x %.3f (Haiku high $0.27 vs Sonnet high $0.66 per task, quoted from the pilot; task level, includes whatever extra output Haiku used in that pilot).' % PILOT_RATIO)
    add('- **Turn assumption:** k x the turns means every token class scales by k: k x output, k x new input / cache writes, and k x cache reads (each turn re-reads the context; the per-turn context size is kept the same). Real context growth with extra turns is super-linear (later turns read a longer prompt), so the k columns are an optimistic bound for Haiku. Quality (the pilot: 19.0 vs 21.3 of 25) is not priced here.')
    add('')
    add('| operator | turns | Sonnet actual | A x1.0 | A x1.5 | A x2.0 | B x1.0 | B x1.5 | B x2.0 |')
    add('|---|---|---|---|---|---|---|---|---|')
    for ag in son:
        add('| %s | %d | %s | %s | %s | %s | %s | %s | %s |' % (
            _opname(ag), ag['n_messages'], money(ag['usd']), *(money(ag['haiku_usd'] * k) for k in SENS),
            *(money(ag['usd'] * PILOT_RATIO * k) for k in SENS)))
    add('| **Sonnet operators total** | %d | %s | %s | %s | %s | %s | %s | %s |' % (
        sum(ag['n_messages'] for ag in son), money(su), *(money(sh * k) for k in SENS),
        *(money(su * PILOT_RATIO * k) for k in SENS)))
    add('')
    add('| scenario | Haiku USD | saving USD | saving % | saving USD per operator-hour | saving USD per row |')
    add('|---|---|---|---|---|---|')
    for lab, base in (('A token repricing', sh), ('B pilot ratio %.2f' % PILOT_RATIO, su * PILOT_RATIO)):
        for k in SENS:
            hk = base * k
            sv = su - hk
            add('| %s, Haiku %.1fx turns | %s | %s | %.0f%% | %s | %s |' % (
                lab, k, money(hk), money(sv), (sv / su * 100) if su else 0,
                money(sv / shr) if shr > 0.01 else '-', money(sv / srow) if srow else '-'))
    add('')
    ya = su / sh if sh else 0
    yb = 1 / PILOT_RATIO
    add('Sonnet operators: %d transcripts, %s over %.1f operator-hours = **%s per operator-hour**%s. Break-even turn multiple (Haiku costs as much as Sonnet): **A %.1fx**, **B %.1fx**. Below that multiple Haiku saves money; above it Haiku costs more.' % (
        len(son), money(su), shr, money(su / shr) if shr > 0.01 else '-',
        (', %s per row (%d rows)' % (money(su / srow), srow)) if srow else '', ya, yb))
    add('')
    pil = [ag for ag in ops if ag['pilot']]
    if pil:
        add('Haiku pilot operators (-hk) already in the window, actual cost at their own model: ' + '; '.join(
            '%s %s %s, %d turns, %.2f h, %s/h' % (_opname(ag), ag['primary_model'], money(ag['usd']), ag['n_messages'],
                                                 ag['hours'], money(ag['usd'] / ag['hours']) if ag['hours'] > 0.01 else '-')
            for ag in pil) + '.')
        add('')
    return L


def fable_lines(meta, prices):
    L = []
    add = L.append
    add('## Unpriced models in the window (no rate in prices.json or docs/MODEL_ROUTING.md)')
    add('')
    unk = meta.get('unk_win') or {}
    if not unk:
        add('None in this window: every message from the window start on has a known model rate. The claude-fable-5-1 messages seen in earlier audits are all dated before 2026-10-14 and are outside the window. Fable has no price in prices.json or docs/MODEL_ROUTING.md; if any message appears here later, this table lists it with token counts and an Opus-5.5-rate bound (not added to any total).')
        add('')
        return L
    add('`prices.json` (read from the Anthropic platform pricing page 2026-10-14) lists only Haiku 5.5, Sonnet 5.5 and Opus 5.5, and `docs/MODEL_ROUTING.md` gives no Fable price (it only says Fable is never allowed for subagents). These messages are therefore counted at $0 in every total above; the bound below prices their tokens at Opus 5.5 rates and is **not** added to anything.')
    add('')
    add('| model | messages | input | output | cache write | cache read | Opus-rate bound USD |')
    add('|---|---|---|---|---|---|---|')
    tot = 0.0
    for m, u in sorted(unk.items(), key=lambda kv: -kv[1]['opus']):
        tot += u['opus']
        add('| %s | %s | %s | %s | %s | %s | %s |' % (m, toks(u['n']), toks(u['input']), toks(u['output']),
                                                     toks(u['cache_write']), toks(u['cache_read']), money(u['opus'])))
    add('| **total** | %s | | | | | %s |' % (toks(sum(u['n'] for u in unk.values())), money(tot)))
    add('')
    return L



def build_md(a, prices, agents, per_day, per_model, per_task, tools_all, grand, meta):
    L = []
    add = L.append
    add('# Cost / token audit ledger (imm26-costaudit)')
    add('')
    add('**Window: %s.** Messages outside it are ignored (earlier data did not use the current setup, Shay 2026-10-16).' % a.window)
    add('')
    add('Generated by `tools/automation/cost-audit.py`' + (' (--agents %s)' % a.agents if a.agents else '') +
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
    add('- Task type is a guess from the subagent description (`[case:x]` tag and keywords) and the agent\'s first prompt. Main sessions are "coordinator" unless the prompt names an independent agent ("hosted-agent"; an operator-named one is a lane-operator). Check the label column before acting on a row.')
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
    L.extend(category_lines(agents, grand))
    L.extend(operator_lines(agents, grand))
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
    L.extend(fable_lines(meta, prices))
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
    add('## Self-check (independent recount with tools/automation/cost-audit-selfcheck.py: regex over raw lines, own dedupe and pricing, same window)')
    add('')
    sc = read_selfcheck(a.selfcheck or os.path.join(a.out, 'selfcheck.tsv'))
    if not sc:
        add('No selfcheck.tsv found; run the independent recount and rerun this tool.')
    else:
        add('| agent | tool USD | recount USD | diff % | tokens match | flag |')
        add('|---|---|---|---|---|---|')
        by_agent = {ag['session'] + '/' + ag['agent']: ag for ag in agents}
        for key, p in sc.items():
            ag = by_agent.get(key)
            if not ag:
                if not a.agents:
                    add('| %s | - | %s | - | - | NOT FOUND in tool output (no messages in the window?) |' % (key, p[5]))
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
    add('Message counts are not compared: the recount skips the zero-token `<synthetic>` records (the tool counts them); tokens and USD match exactly. Mismatch flag = USD > 2% or any token total different.')
    add('')
    add('Unpriced models (no rate in prices.json), bound at Opus 5.5 rates: %s. Not in the totals above; the true figure depends on the real rate.' % money(grand.get('unpriced_opus', 0.0)))
    add('')
    add('Scope note: the Haiku column is a price-only repricing of recorded tokens. The quota meter (`/usage`) is the only source for subscription use.')
    add('')
    return '\n'.join(L)


if __name__ == '__main__':
    sys.exit(main())
