#!/usr/bin/env python3
r"""compact-audit.py - what a context compaction and an overlap handoff really cost (read-only, aggregates only).

Usage (Windows python):
  python -I tools/automation/compact-audit.py compacts [--session ID] [--out DIR]   every compact_boundary in a session
  python -I tools/automation/compact-audit.py handoff --new ID --old ID [--turns N] [--out DIR]
        cost of a fresh session's startup (first N assistant turns) and of the old (tail) session after the new one started

Method (Shay 2026-10-16, "know the actual cost of a compact at 150k"):
  - The summarizer call is NOT written to the transcript as an assistant message, so it is reconstructed: its prompt is the
    whole pre-compact context (compactMetadata.preTokens) billed at cache-read if the cache was warm (last assistant message
    before the boundary shows cache_read >= 80% of preTokens) else at cache-write; output = summary text length / 3.6 chars
    per token (estimate). durationMs comes from the boundary record. Marked ESTIMATE.
  - The first assistant message after the boundary is MEASURED (its usage shows what the new prefix cost to cache and read).
  - Per-turn cost before vs after = mean cost of the 15 assistant turns before / after (MEASURED from usage fields),
    and the break-even = how many turns until compact cost is repaid by the cheaper turns.
  - Prices: tools/automation/prices.json, per message model; 1h cache writes for cache_creation unless split says 5m.
  - Dedupe: one count per message id, the record with the largest output_tokens.
Output: <out>\compact-audit.md + compact-audit.jsonl (default C:\KenshiTestRuns\compact-audit).
"""
import argparse, json, os, sys, glob, datetime

ROOT = r'C:\Users\Shay\.claude\projects\C--KenshiModding'
PRICES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'prices.json')
P = json.load(open(PRICES, encoding='utf-8'))


def fam(model):
    m = (model or '').lower()
    if 'haiku' in m: return 'haiku'
    if 'opus' in m: return 'opus'
    return 'sonnet'


def cost(u, model):
    f = fam(model)
    tot_in = (u.get('input_tokens') or 0) + (u.get('cache_read_input_tokens') or 0) + (u.get('cache_creation_input_tokens') or 0)
    r = P['haiku_over_100k'] if (f == 'haiku' and tot_in > 100000) else P[f]
    cc = u.get('cache_creation') or {}
    w5 = cc.get('ephemeral_5m_input_tokens'); w1 = cc.get('ephemeral_1h_input_tokens')
    cw = u.get('cache_creation_input_tokens') or 0
    if w5 is None and w1 is None: w5, w1 = cw, 0
    usd = ((u.get('input_tokens') or 0) * r['input'] + (u.get('output_tokens') or 0) * r['output']
           + (u.get('cache_read_input_tokens') or 0) * r['cache_read'] + (w5 or 0) * r['cache_write_5m'] + (w1 or 0) * r['cache_write_1h']) / 1e6
    return usd


def load(sid):
    path = os.path.join(ROOT, sid + '.jsonl')
    recs = []
    best = {}
    with open(path, encoding='utf-8') as f:
        for n, line in enumerate(f):
            line = line.strip()
            if not line: continue
            try: d = json.loads(line)
            except Exception: continue
            m = d.get('message')
            if d.get('type') == 'assistant' and isinstance(m, dict) and m.get('usage'):
                mid = m.get('id') or d.get('uuid')
                o = (m['usage'].get('output_tokens') or 0)
                if mid in best and best[mid][1] >= o:
                    continue
                best[mid] = (n, o)
                recs.append(('A', n, mid, d.get('timestamp'), m.get('model'), m['usage']))
            elif d.get('type') == 'system' and d.get('subtype') == 'compact_boundary':
                recs.append(('B', n, None, d.get('timestamp'), None, d.get('compactMetadata') or {}))
            elif d.get('isCompactSummary'):
                c = d.get('message', {}).get('content')
                txt = c if isinstance(c, str) else json.dumps(c)
                recs.append(('S', n, None, d.get('timestamp'), None, {'chars': len(txt)}))
    # keep only the final record per message id
    keep = []
    for r in recs:
        if r[0] == 'A' and best[r[2]][0] != r[1]: continue
        keep.append(r)
    keep.sort(key=lambda r: r[1])
    return keep


def ts(s):
    return datetime.datetime.fromisoformat(s.replace('Z', '+00:00')) if s else None


def mean(xs):
    return sum(xs) / len(xs) if xs else 0.0


def compacts(sid, out):
    recs = load(sid)
    rows = []
    for i, r in enumerate(recs):
        if r[0] != 'B': continue
        meta = r[5]
        pre = meta.get('preTokens') or 0; post = meta.get('postTokens') or 0
        before = [x for x in recs[:i] if x[0] == 'A']
        after = [x for x in recs[i + 1:] if x[0] == 'A']
        summ = next((x for x in recs[max(0, i - 3):i + 4] if x[0] == 'S'), None)
        last = before[-1] if before else None
        warm = bool(last and (last[5].get('cache_read_input_tokens') or 0) >= 0.8 * pre)
        model = last[4] if last else 'sonnet'
        f = fam(model); pr = P[f]
        in_usd = pre * (pr['cache_read'] if warm else pr['cache_write_1h']) / 1e6
        out_tok = int((summ[5]['chars'] if summ else 30000) / 3.6)
        out_usd = out_tok * pr['output'] / 1e6
        first = after[0] if after else None
        first_usd = cost(first[5], first[4]) if first else None
        b15 = [cost(x[5], x[4]) for x in before[-15:]]
        a15 = [cost(x[5], x[4]) for x in after[:15]]
        pb, pa = mean(b15), mean(a15)
        saving = pb - pa
        rows.append({
            'session': sid, 'at': r[3], 'trigger': meta.get('trigger'), 'preTokens': pre, 'postTokens': post, 'durationMs': meta.get('durationMs'),
            'cache_warm_before': warm, 'summary_in_usd_ESTIMATE': round(in_usd, 4), 'summary_out_tokens_ESTIMATE': out_tok,
            'summary_out_usd_ESTIMATE': round(out_usd, 4), 'summary_total_usd_ESTIMATE': round(in_usd + out_usd, 4),
            'first_turn_after_usd_MEASURED': None if first_usd is None else round(first_usd, 4),
            'first_turn_after_usage': None if not first else {k: first[5].get(k) for k in ('input_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens', 'output_tokens')},
            'turns_before_n': len(b15), 'mean_turn_usd_before_MEASURED': round(pb, 4), 'turns_after_n': len(a15), 'mean_turn_usd_after_MEASURED': round(pa, 4),
            'one_off_usd': round(in_usd + out_usd + (first_usd or 0), 4),
            'break_even_turns': None if saving <= 0 else round((in_usd + out_usd + (first_usd or 0)) / saving, 1),
        })
    return rows


def handoff(new, old, nturns, out):
    rn = [x for x in load(new) if x[0] == 'A']
    ro = [x for x in load(old) if x[0] == 'A']
    t0 = ts(rn[0][3])
    start = rn[:nturns]
    start_usd = sum(cost(x[5], x[4]) for x in start)
    first_usd = cost(start[0][5], start[0][4])
    tail = [x for x in ro if ts(x[3]) >= t0]
    tail_usd = sum(cost(x[5], x[4]) for x in tail)
    tail_ctx = mean([(x[5].get('cache_read_input_tokens') or 0) + (x[5].get('cache_creation_input_tokens') or 0) + (x[5].get('input_tokens') or 0) for x in tail])
    return {
        'new_session': new, 'new_first_turn_at': rn[0][3], 'startup_turns': len(start), 'startup_usd_MEASURED': round(start_usd, 4),
        'startup_first_turn_usd_MEASURED': round(first_usd, 4),
        'startup_context_after_turns': (start[-1][5].get('cache_read_input_tokens') or 0) + (start[-1][5].get('cache_creation_input_tokens') or 0) + (start[-1][5].get('input_tokens') or 0),
        'old_session': old, 'old_turns_after_new_started': len(tail), 'old_usd_after_new_started_MEASURED': round(tail_usd, 4),
        'old_mean_context_tokens': int(tail_ctx), 'old_last_turn_at': tail[-1][3] if tail else None,
        'total_handoff_usd': round(start_usd + tail_usd, 4),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['compacts', 'handoff'])
    ap.add_argument('--session'); ap.add_argument('--new'); ap.add_argument('--old')
    ap.add_argument('--turns', type=int, default=25); ap.add_argument('--out', default=r'C:\KenshiTestRuns\compact-audit')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    if a.mode == 'compacts':
        sids = [a.session] if a.session else [os.path.basename(p)[:-6] for p in sorted(glob.glob(os.path.join(ROOT, '*.jsonl')), key=os.path.getmtime)[-3:]]
        res = []
        for s in sids: res += compacts(s, a.out)
    else:
        res = [handoff(a.new, a.old, a.turns, a.out)]
    jl = os.path.join(a.out, 'compact-audit.jsonl')
    seen = set()
    if os.path.exists(jl):
        for l in open(jl, encoding='utf-8'):
            try:
                o = json.loads(l); seen.add((o.get('mode'), o.get('session') or o.get('new_session'), o.get('at') or o.get('new_first_turn_at'), o.get('turns_after_n')))
            except Exception: pass
    if a.mode == 'compacts' and res:
        r = res[-1]
        nl = chr(10)
        fmt = nl.join([
            '# latest compact audit (%s)', '',
            'compact at %s (%s), %s -> %s tokens, summarizer %s s', '',
            '- one-off cost: $%s = summarizer ESTIMATE $%s (in $%s %s cache, out ~%s tokens $%s) + first turn after MEASURED $%s',
            '- mean turn cost: before $%s (n=%s) -> after $%s (n=%s); break-even after %s turns', ''])
        open(os.path.join(a.out, 'latest.md'), 'w', encoding='utf-8').write(fmt % (
                r['session'], r['at'], r['trigger'], r['preTokens'], r['postTokens'], round((r['durationMs'] or 0) / 1000),
                r['one_off_usd'], r['summary_total_usd_ESTIMATE'], r['summary_in_usd_ESTIMATE'], 'warm' if r['cache_warm_before'] else 'COLD',
                r['summary_out_tokens_ESTIMATE'], r['summary_out_usd_ESTIMATE'], r['first_turn_after_usd_MEASURED'],
                r['mean_turn_usd_before_MEASURED'], r['turns_before_n'], r['mean_turn_usd_after_MEASURED'], r['turns_after_n'], r['break_even_turns']))
    with open(jl, 'a', encoding='utf-8') as f:
        for r in res:
            if (a.mode, r.get('session') or r.get('new_session'), r.get('at') or r.get('new_first_turn_at'), r.get('turns_after_n')) in seen: continue
            r['audited_at'] = datetime.datetime.now().isoformat(timespec='seconds'); r['mode'] = a.mode
            f.write(json.dumps(r) + '\n')
    for r in res: print(json.dumps(r, indent=1))


if __name__ == '__main__':
    main()
