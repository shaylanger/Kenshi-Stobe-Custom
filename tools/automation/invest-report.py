#!/usr/bin/env python3
# invest-report.py (WSL python3): one row per ticket for an investigation test (Shay 2026-10-14). Reads the router ledger
# (agent-calls.tsv: the first call of each ticket) and the run ledger (agent-runs.tsv: runs, their transcripts, the last run),
# and prints per ticket: runs, calls, tokens, table_$ (guess), token_$ (official prices), span (first call to last run, minutes),
# the verdict file and the cases used. Reuses the functions of ledger-report.py. Times are the Windows clock, like ledger-report.py.
# usage: python3 tools/automation/invest-report.py [--window-start 'YYYY-MM-DD HH:MM:SS'] [--window-end ...] [--tickets 'T1-*']
import argparse
import datetime
import fnmatch
import glob
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('ledger_report', os.path.join(HERE, 'ledger-report.py'))
lr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lr)


def verdict_word(path):
    if not os.path.exists(path):
        return 'none'
    with open(path, encoding='utf-8-sig', errors='ignore') as fh:
        first = fh.readline().strip().split()
    return first[0] if first else 'empty'


def main():
    ap = argparse.ArgumentParser(description='One row per ticket: tokens, cost, span, verdict.')
    ap.add_argument('--runs', default='/mnt/c/KenshiTestRuns/ledger/agent-runs.tsv')
    ap.add_argument('--calls', default='/mnt/c/KenshiTestRuns/ledger/agent-calls.tsv')
    ap.add_argument('--verdicts', default='/mnt/c/KenshiTestRuns/verdicts')
    ap.add_argument('--projects', default='/mnt/c/Users/Shay/.claude/projects', help='finds a run by agentId when its row has no path')
    ap.add_argument('--prices', default=os.path.join(HERE, 'prices.json'), help="official prices JSON, or 'none'")
    ap.add_argument('--window-start', default='')
    ap.add_argument('--window-end', default='')
    ap.add_argument('--tickets', default='*', help="glob over ticket ids, e.g. 'T1-*'")
    a = ap.parse_args()
    lo = lr.parse_local(a.window_start) if a.window_start else datetime.datetime.min
    hi = lr.parse_local(a.window_end) if a.window_end else datetime.datetime.max
    prices = lr.load_prices(a.prices)

    def inwin(ts):
        try:
            return lo <= lr.parse_local(ts) <= hi
        except ValueError:
            return False

    def wanted(ticket):
        return bool(ticket) and fnmatch.fnmatch(ticket, a.tickets)

    rows = {}

    def rec(ticket):
        return rows.setdefault(ticket, {'runs': 0, 'calls': 0, 'input': 0, 'output': 0, 'cache_read': 0,
                                        'cache_create': 0, 'table': 0.0, 'usd': 0.0, 'missing': 0,
                                        'cases': set(), 'first': None, 'last': None})

    for ts, aid, out, case, ticket, stype, model, effort in lr.load_rows(a.runs):
        if not wanted(ticket) or not inwin(ts):
            continue
        r = rec(ticket)
        r['runs'] += 1
        r['cases'].add(case or '-')
        r['last'] = max(r['last'] or ts, ts)
        path = lr.to_posix(out) if out else ''
        if not path:
            hits = glob.glob(os.path.join(a.projects, '*', '*', 'subagents', 'agent-%s.jsonl' % aid))
            path = hits[0] if hits else ''
        res = lr.transcript_usage(path, None, prices) if path else None
        if res is None:
            r['missing'] += 1
            continue
        tok, _, usd = res
        for k in ('calls', 'input', 'output', 'cache_read', 'cache_create'):
            r[k] += tok[k]
        r['table'] += tok['calls'] * lr.TABLE.get(model or '-', {}).get(effort or '-', 0.0)
        r['usd'] += usd

    for ts, case, ticket, stype, model, effort, action, desc in lr.load_rows(a.calls):
        if action not in ('allow', 'override') or not wanted(ticket) or not inwin(ts):
            continue
        r = rec(ticket)
        r['first'] = min(r['first'] or ts, ts)

    print('window: %s to %s (Windows clock); prices: %s' % (a.window_start or 'all', a.window_end or 'all', a.prices))
    print('%-14s %5s %6s %10s %9s %11s %12s %9s %9s %8s %-7s %s' % (
        'ticket', 'runs', 'calls', 'input', 'output', 'cache_read', 'cache_create', 'table_$', 'token_$', 'span_min', 'verdict', 'cases'))
    for ticket in sorted(rows):
        r = rows[ticket]
        span = '-'
        if r['first'] and r['last']:
            span = '%.1f' % ((lr.parse_local(r['last']) - lr.parse_local(r['first'])).total_seconds() / 60)
        verdict = verdict_word(os.path.join(a.verdicts, ticket + '.txt'))
        print('%-14s %5d %6d %10d %9d %11d %12d %9.4f %9.4f %8s %-7s %s%s' % (
            ticket, r['runs'], r['calls'], r['input'], r['output'], r['cache_read'], r['cache_create'],
            r['table'], r['usd'], span, verdict, ','.join(sorted(r['cases'])),
            '  (%d transcript(s) missing)' % r['missing'] if r['missing'] else ''))


if __name__ == '__main__':
    main()
