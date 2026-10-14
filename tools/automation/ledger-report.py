#!/usr/bin/env python3
# ledger-report.py (WSL python3): what each tier cost in tokens, from the run ledger (Shay 2026-10-14).
# Reads C:\KenshiTestRuns\ledger\agent-runs.tsv (written by agent-ledger-post.ps1: one row per Agent call that ran) and adds up
# each run's usage from its transcript (the output_file in the row), each message id counted once. Prints the totals per case,
# model and effort, then the verdict per ticket from C:\KenshiTestRuns\verdicts. Cache reads are shown as their own column.
# Usage: python3 tools/automation/ledger-report.py [runs.tsv] [verdicts-dir]
import collections
import json
import os
import re
import sys

RUNS = sys.argv[1] if len(sys.argv) > 1 else '/mnt/c/KenshiTestRuns/ledger/agent-runs.tsv'
VERD = sys.argv[2] if len(sys.argv) > 2 else '/mnt/c/KenshiTestRuns/verdicts'


def to_posix(p):
    m = re.match(r'^([A-Za-z]):[\\/](.*)$', p.strip())
    if m:
        return '/mnt/%s/%s' % (m.group(1).lower(), m.group(2).replace('\\', '/'))
    return p.strip()


def usage(path):
    """Sum the usage of a transcript's assistant messages; None when the transcript is not there."""
    seen, tot = set(), collections.Counter()
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
            seen.add(mid)
            tot['input'] += u.get('input_tokens', 0) or 0
            tot['output'] += u.get('output_tokens', 0) or 0
            tot['cache_read'] += u.get('cache_read_input_tokens', 0) or 0
            tot['cache_create'] += u.get('cache_creation_input_tokens', 0) or 0
    return tot


rows = []
if os.path.exists(RUNS):
    with open(RUNS, encoding='utf-8-sig', errors='ignore') as fh:
        for line in fh:
            f = line.rstrip('\r\n').split('\t')
            if len(f) >= 8:
                rows.append(f)

agg = collections.defaultdict(collections.Counter)
missing = 0
ticket_cases = collections.defaultdict(set)
for f in rows:
    ts, aid, out, case, ticket, stype, model, effort = f[:8]
    key = (case or '-', model or '-', effort or '-')
    agg[key]['runs'] += 1
    t = usage(to_posix(out)) if out else None
    if t is None:
        missing += 1
        continue
    agg[key].update(t)
    if ticket:
        ticket_cases[ticket].add(case or '-')

print('%-10s %-7s %-7s %5s %12s %10s %14s %12s' % ('case', 'model', 'effort', 'runs', 'input', 'output', 'cache_read', 'cache_create'))
for key in sorted(agg):
    c = agg[key]
    print('%-10s %-7s %-7s %5d %12d %10d %14d %12d' % (key[0], key[1], key[2], c['runs'], c['input'], c['output'], c['cache_read'], c['cache_create']))
if missing:
    print('runs whose transcript is missing or not written yet: %d' % missing)

print()
print('verdict per ticket:')
for ticket in sorted(ticket_cases):
    p = os.path.join(VERD, ticket + '.txt')
    word = 'none'
    if os.path.exists(p):
        with open(p, encoding='utf-8-sig', errors='ignore') as fh:
            first = fh.readline().strip().split()
            word = first[0] if first else 'empty'
    print('  %-30s %-8s cases: %s' % (ticket, word, ','.join(sorted(ticket_cases[ticket]))))
