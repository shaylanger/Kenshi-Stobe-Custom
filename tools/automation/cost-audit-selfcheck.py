#!/usr/bin/env python3
"""cost-audit-selfcheck.py - independent recount of a few transcripts for cost-audit.py (read-only).

Deliberately shares no code with cost-audit.py: no json parsing, only regular expressions over the raw lines,
its own dedupe (message id, largest output_tokens wins) and its own pricing arithmetic from prices.json.
Writes the TSV that cost-audit.py compares against (columns: agent input output cache_write cache_read usd n_messages).

  python -I tools/automation/cost-audit-selfcheck.py [--since 'YYYY-MM-DD[ HH:MM]'] [--until ...] [--out FILE]
         [--root DIR] SESSION/AGENTID [SESSION/AGENTID ...]      (AGENTID without the 'agent-' prefix; 'main' = the session file)
"""
import argparse
import datetime as dt
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = r'C:\Users\Shay\.claude\projects\C--KenshiModding'
OUT = r'C:\KenshiTestRuns\agents\out\imm26-costaudit\selfcheck.tsv'
ID = re.compile(rb'"message":\{[^{}]*?"id":"([^"]+)"')
ID2 = re.compile(rb'"id":"(msg_[A-Za-z0-9]+)"')
MODEL = re.compile(rb'"model":"([^"]*)"')
TS = re.compile(rb'"timestamp":"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)')


def num(raw, key):
    m = re.search(rb'"' + key + rb'":(\d+)', raw)
    return int(m.group(1)) if m else 0


def bound(s, default):
    s = (s or '').strip().replace('T', ' ')
    if not s or s == 'all':
        return default
    for f in ('%Y-%m-%d %H:%M', '%Y-%m-%d'):
        try:
            return dt.datetime.strptime(s, f).timestamp()
        except ValueError:
            pass
    raise SystemExit('bad datetime ' + s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--since', default='2026-10-14 00:00')
    ap.add_argument('--until', default='')
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--root', default=ROOT)
    ap.add_argument('agents', nargs='+')
    a = ap.parse_args()
    lo, hi = bound(a.since, 0.0), bound(a.until, 4e9)
    with open(os.path.join(HERE, 'prices.json'), encoding='utf-8') as f:
        pr = {k: v for k, v in json.load(f).items() if not k.startswith('_')}
    lines = ['agent\tinput\toutput\tcache_write\tcache_read\tusd\tn_messages']
    for key in a.agents:
        sess, ag = key.split('/', 1)
        path = os.path.join(a.root, sess + '.jsonl') if ag == 'main' else os.path.join(a.root, sess, 'subagents', 'agent-' + ag + '.jsonl')
        best = {}
        with open(path, 'rb') as f:
            for raw in f:
                if b'"type":"assistant"' not in raw or b'"usage":{' not in raw:
                    continue
                m = ID.search(raw) or ID2.search(raw)
                t = TS.search(raw)
                if not m or not t:
                    continue
                ep = dt.datetime.strptime(t.group(1).decode(), '%Y-%m-%dT%H:%M:%S').replace(tzinfo=dt.timezone.utc).timestamp()
                if ep < lo or ep > hi:
                    continue
                u = raw[raw.index(b'"usage":{'):]
                i, o, cr, cwt = num(u, b'input_tokens'), num(u, b'output_tokens'), num(u, b'cache_read_input_tokens'), num(u, b'cache_creation_input_tokens')
                c1 = num(u, b'ephemeral_1h_input_tokens')
                c5m = re.search(rb'"ephemeral_5m_input_tokens":(\d+)', u)
                c5 = int(c5m.group(1)) if c5m else cwt - c1
                mm = MODEL.search(raw)
                model = mm.group(1).decode().lower() if mm else ''
                if m.group(1) not in best or o > best[m.group(1)][1]:
                    best[m.group(1)] = (i, o, cr, c5, c1, model)
        ti = to = tr = tw = n = 0
        usd = 0.0
        for (i, o, cr, c5, c1, model) in best.values():
            fam = next((x for x in ('haiku', 'sonnet', 'opus') if x in model), None)
            n += 1
            ti += i
            to += o
            tr += cr
            tw += c5 + c1
            if not fam:
                continue
            r = pr['haiku_over_100k' if (fam == 'haiku' and i + cr + c5 + c1 > 100000) else fam]
            usd += (i * r['input'] + o * r['output'] + cr * r['cache_read'] + c5 * r['cache_write_5m'] + c1 * r['cache_write_1h']) / 1e6
        lines.append('%s\t%d\t%d\t%d\t%d\t%.4f\t%d' % (key, ti, to, tw, tr, usd, n))
    with open(a.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    sys.exit(main())
