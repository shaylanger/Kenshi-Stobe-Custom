#!/usr/bin/env python3
# ledger-report.py (WSL python3): what a test cost, from the run ledger and the transcripts (Shay 2026-10-14).
# Subagent runs: each row of C:\KenshiTestRuns\ledger\agent-runs.tsv (written by agent-ledger-post.ps1) is summed from its transcript
# (the output_file in the row, or the subagents folder found by agentId): calls = one per model message, each message id once.
# Coordinator: with --main and a window, the main session's own model messages in that window (its turns wake up for each subagent).
# Windows clock: the ledger's times and --window-start/--window-end are the Windows clock. WSL runs in another zone (America/Chicago here),
#   so transcript times (UTC) are converted with the Windows UTC offset: asked from powershell.exe, or given as --utc-offset=-06:00.
# Costs:
#   token_$ = each message's tokens at the official per-million-token prices in tools/automation/prices.json. Each message is priced
#             by its own model and prompt size (a Haiku prompt over 100,000 tokens uses haiku_over_100k), and cache writes by TTL (5m, 1h).
#   table_$ = calls x the per-call price in Shay's table (docs/MODEL_ROUTING.md). A guess per call, kept for comparison.
# Usage: python3 tools/automation/ledger-report.py [--runs F] [--verdicts D] [--projects D] [--prices F|none]
#          [--main T --window-start 'YYYY-MM-DD HH:MM:SS' --window-end 'YYYY-MM-DD HH:MM:SS' [--utc-offset=-06:00] --coord-effort medium]
import argparse
import collections
import datetime
import glob
import json
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
LONG_PROMPT = 100000  # tokens; Haiku 5.5 prices change above this (see prices.json)

TABLE = {  # $ per call, Shay's table (2026-10-14)
    'haiku':  {'low': 0.015, 'medium': 0.020, 'high': 0.0275, 'xhigh': 0.0375, 'max': 0.050},
    'sonnet': {'low': 0.30,  'medium': 0.40,  'high': 0.55,   'xhigh': 0.75,   'max': 1.00},
    'opus':   {'low': 0.60,  'medium': 0.80,  'high': 1.10,   'xhigh': 1.50,   'max': 2.00},
}


def alias(name):
    for a in ('haiku', 'sonnet', 'opus'):
        if a in (name or '').lower():
            return a
    return name or '-'


def to_posix(p):
    m = re.match(r'^([A-Za-z]):[\\/](.*)$', p.strip())
    if m:
        return '/mnt/%s/%s' % (m.group(1).lower(), m.group(2).replace('\\', '/'))
    return p.strip()


def parse_local(s):
    return datetime.datetime.strptime(s.strip(), '%Y-%m-%d %H:%M:%S')


def parse_offset(s):
    m = re.match(r'^([+-])(\d{2}):?(\d{2})$', s.strip())
    if not m:
        raise SystemExit('bad UTC offset %r (use like -06:00)' % s)
    d = datetime.timedelta(hours=int(m.group(2)), minutes=int(m.group(3)))
    return -d if m.group(1) == '-' else d


def windows_offset():
    """UTC offset of the Windows clock, which the ledger and the windows are in. Asked from powershell.exe: WSL's own zone differs."""
    try:
        r = subprocess.run(['powershell.exe', '-NoProfile', '-Command', "(Get-Date).ToString('zzz')"],
                           capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e:
        raise SystemExit('cannot read the Windows clock offset (%s); pass --utc-offset=-06:00' % e)
    return parse_offset(r.stdout.strip())


def fmt_offset(td):
    m = int(td.total_seconds() // 60)
    return '%s%02d:%02d' % ('-' if m < 0 else '+', abs(m) // 60, abs(m) % 60)


def load_prices(path):
    if not path or path == 'none' or not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as fh:
        return {k: v for k, v in json.load(fh).items() if not k.startswith('_')}


def message_usd(prices, alias_name, prompt, u, cw5, cw1):
    key = alias_name
    if alias_name == 'haiku' and prompt > LONG_PROMPT and 'haiku_over_100k' in prices:
        key = 'haiku_over_100k'
    p = prices.get(key)
    if p is None:
        return 0.0
    return (u.get('input_tokens', 0) * p['input'] + u.get('output_tokens', 0) * p['output']
            + u.get('cache_read_input_tokens', 0) * p['cache_read']
            + cw5 * p['cache_write_5m'] + cw1 * p['cache_write_1h']) / 1e6


def transcript_usage(path, window=None, prices=None, tz=None):
    """Model messages of a transcript, each message id once: (counts, model aliases, dollars at prices).
    None when the file is missing. window = (start, end) as naive Windows-clock times, and tz = that clock's timezone, so the
    transcript's UTC times are compared on the same clock; other messages are skipped (the coordinator)."""
    tot, models, seen, usd = collections.Counter(), collections.Counter(), set(), 0.0
    try:
        fh = open(path, encoding='utf-8', errors='ignore')
    except OSError:
        return None
    with fh:
        for line in fh:
            if '"usage"' not in line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            m = o.get('message') if isinstance(o.get('message'), dict) else {}
            u = m.get('usage') or {}
            mid = m.get('id') or o.get('uuid')
            if not u or mid in seen:
                continue
            if window is not None:
                try:
                    t = datetime.datetime.fromisoformat(str(o.get('timestamp', '')).replace('Z', '+00:00'))
                    t = t.astimezone(tz).replace(tzinfo=None)
                except ValueError:
                    continue
                if not (window[0] <= t <= window[1]):
                    continue
            seen.add(mid)
            cc = u.get('cache_creation') or {}
            cw5 = cc.get('ephemeral_5m_input_tokens', 0) or 0
            cw1 = cc.get('ephemeral_1h_input_tokens', 0) or 0
            if not cw5 and not cw1:
                cw5 = u.get('cache_creation_input_tokens', 0) or 0   # no TTL split in the record: 5-minute rate
            prompt = (u.get('input_tokens', 0) or 0) + (u.get('cache_read_input_tokens', 0) or 0) + (u.get('cache_creation_input_tokens', 0) or 0)
            alias_name = alias(m.get('model'))
            tot['calls'] += 1
            tot['input'] += u.get('input_tokens', 0) or 0
            tot['output'] += u.get('output_tokens', 0) or 0
            tot['cache_read'] += u.get('cache_read_input_tokens', 0) or 0
            tot['cache_create'] += u.get('cache_creation_input_tokens', 0) or 0
            models[alias_name] += 1
            if prices:
                usd += message_usd(prices, alias_name, prompt, u, cw5, cw1)
    return tot, models, usd


def load_rows(path):
    rows = []
    if os.path.exists(path):
        with open(path, encoding='utf-8-sig', errors='ignore') as fh:
            for line in fh:
                f = line.rstrip('\r\n').split('\t')
                if len(f) >= 8:
                    rows.append(f[:8])
    return rows


def line(label, model, effort, runs, tok, table_usd, token_usd, prices):
    s = '%-12s %-7s %-7s %5s %6d %10d %9d %13d %12d %10.4f' % (
        label, model, effort, runs, tok['calls'], tok['input'], tok['output'], tok['cache_read'], tok['cache_create'], table_usd)
    if prices is not None:
        s += ' %10.4f' % (token_usd or 0.0)
    return s


def main():
    ap = argparse.ArgumentParser(description='Calls, tokens and cost of a test, from the run ledger and the transcripts.')
    ap.add_argument('--runs', default='/mnt/c/KenshiTestRuns/ledger/agent-runs.tsv')
    ap.add_argument('--verdicts', default='/mnt/c/KenshiTestRuns/verdicts')
    ap.add_argument('--projects', default='/mnt/c/Users/Shay/.claude/projects', help='Claude projects folder: finds a run by agentId when its row has no path')
    ap.add_argument('--main', default='', help='the coordinator transcript, for its turns inside the window')
    ap.add_argument('--window-start', default='')
    ap.add_argument('--window-end', default='')
    ap.add_argument('--utc-offset', default='', help='Windows clock offset like -06:00; default: asked from powershell.exe when a window is given')
    ap.add_argument('--coord-effort', default='medium', help='effort to price the coordinator turns at in the table')
    ap.add_argument('--prices', default=os.path.join(HERE, 'prices.json'), help="official prices JSON, or 'none'")
    a = ap.parse_args()
    window = (parse_local(a.window_start), parse_local(a.window_end)) if a.window_start and a.window_end else None
    tz = None
    if window is not None:
        off = parse_offset(a.utc_offset) if a.utc_offset else windows_offset()
        tz = datetime.timezone(off)
        print('window: %s to %s on the Windows clock (UTC%s)' % (a.window_start, a.window_end, fmt_offset(off)))
    prices = load_prices(a.prices)

    agg = collections.defaultdict(collections.Counter)   # (case, model, effort) -> counts
    table = collections.defaultdict(float)
    token = collections.defaultdict(float)
    missing = 0
    ticket_cases = collections.defaultdict(set)
    for ts, aid, out, case, ticket, stype, model, effort in load_rows(a.runs):
        if window is not None:
            try:
                if not (window[0] <= parse_local(ts) <= window[1]):
                    continue
            except ValueError:
                continue
        key = (case or '-', model or '-', effort or '-')
        agg[key]['runs'] += 1
        path = to_posix(out) if out else ''
        if not path:
            hits = glob.glob(os.path.join(a.projects, '*', '*', 'subagents', 'agent-%s.jsonl' % aid))
            path = hits[0] if hits else ''
        res = transcript_usage(path, None, prices) if path else None
        if res is None:
            missing += 1
            continue
        tok, _, usd = res
        agg[key].update(tok)
        table[key] += tok['calls'] * TABLE.get(model or '-', {}).get(effort or '-', 0.0)
        token[key] += usd
        if ticket:
            ticket_cases[ticket].add(case or '-')

    coord = None
    if a.main and window is not None:
        res = transcript_usage(to_posix(a.main), window, prices, tz)
        if res is not None and res[0]['calls']:
            tok, models, usd = res
            table_usd = tok['calls'] * TABLE.get(models.most_common(1)[0][0], {}).get(a.coord_effort, 0.0)
            coord = (tok, table_usd, usd)

    head = '%-12s %-7s %-7s %5s %6s %10s %9s %13s %12s %10s' % (
        'case', 'model', 'effort', 'runs', 'calls', 'input', 'output', 'cache_read', 'cache_create', 'table_$')
    if prices is not None:
        head += ' %10s' % 'token_$'
    print(head)
    for key in sorted(agg):
        c = agg[key]
        print(line(key[0], key[1], key[2], c['runs'], c, table[key], token.get(key), prices))
    if missing:
        print('runs whose transcript is missing or not written yet: %d' % missing)

    cases = collections.defaultdict(collections.Counter)
    ct = collections.defaultdict(float)
    cp = collections.defaultdict(float)
    for key in agg:
        cases[key[0]].update(agg[key])
        ct[key[0]] += table[key]
        cp[key[0]] += token.get(key, 0.0)
    print()
    print('totals by case:')
    for case in sorted(cases):
        print(line(case, '-', '-', cases[case]['runs'], cases[case], ct[case], cp[case], prices))
    if coord:
        tok, table_usd, usd = coord
        print(line('coordinator', '-', a.coord_effort, '-', tok, table_usd, usd, prices))

    print()
    print('verdict per ticket:')
    for ticket in sorted(ticket_cases):
        p = os.path.join(a.verdicts, ticket + '.txt')
        word = 'none'
        if os.path.exists(p):
            with open(p, encoding='utf-8-sig', errors='ignore') as fh:
                first = fh.readline().strip().split()
                word = first[0] if first else 'empty'
        print('  %-30s %-8s cases: %s' % (ticket, word, ','.join(sorted(ticket_cases[ticket]))))


if __name__ == '__main__':
    main()
