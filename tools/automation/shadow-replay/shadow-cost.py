# Tokens + API-equivalent cost of the live coordinator shadow arms (H, S) -> live-grading/cost.json
# Usage (Windows python): python -I shadow-cost.py [--out C:\KenshiTestRuns\shadow\live-grading\cost.json]
# Prices: tools/automation/prices.json (same banding as cost-audit.py: Haiku prompt > 100k uses haiku_over_100k).
import json, os, sys, collections, datetime as dt
HERE = os.path.dirname(os.path.abspath(__file__))
PRICES = json.load(open(os.path.join(HERE, '..', 'prices.json'), encoding='utf-8'))
PROJ = r'C:\Users\Shay\.claude\projects\C--KenshiModding\05c6207d-b5b1-49c2-904b-6c32d15536f1\subagents'
ARMS = {'H': ['af9f21f9c0492e955', 'a49b5c25aaee31caf'], 'S': ['a96de4460d50d23cf']}
FAM = {'H': 'haiku', 'S': 'sonnet'}
LEDGER = r'C:\KenshiTestRuns\shadow\ledger-%s.jsonl'
BAND = 100000

def usd(r, i, o, cr, c5, c1):
    return (i*r['input'] + o*r['output'] + cr*r['cache_read'] + c5*r['cache_write_5m'] + c1*r['cache_write_1h'])/1e6

def load(arm):
    msgs = {}
    for aid in ARMS[arm]:
        for raw in open(os.path.join(PROJ, 'agent-%s.jsonl' % aid), 'rb'):
            if b'"type":"assistant"' not in raw: continue
            d = json.loads(raw)
            if d.get('type') != 'assistant': continue
            m = d.get('message') or {}
            u = m.get('usage'); mid = m.get('id') or d.get('requestId')
            if not u or not mid: continue
            i = u.get('input_tokens') or 0; o = u.get('output_tokens') or 0
            cr = u.get('cache_read_input_tokens') or 0; cwt = u.get('cache_creation_input_tokens') or 0
            cc = u.get('cache_creation') or {}
            c1 = cc.get('ephemeral_1h_input_tokens') or 0
            c5 = cc.get('ephemeral_5m_input_tokens')
            if c5 is None: c5 = cwt - c1
            chars = 0
            for c in m.get('content') or []:
                if c.get('type') == 'text': chars += len(c.get('text') or '')
                elif c.get('type') == 'tool_use': chars += len(json.dumps(c.get('input')))
            fam = FAM[arm]; model = m.get('model') or ''
            assert fam in model.lower(), (arm, model)
            prompt = i + cr + cwt
            r = PRICES['haiku_over_100k' if (fam == 'haiku' and prompt > BAND) else fam]
            oe = max(o, int(chars/3.5))  # logged output_tokens is a stream placeholder (~15/msg); estimate from content chars
            rec = dict(ts=d['timestamp'], oe=oe, usd_oe=usd(r, i, oe, cr, c5, c1), i=i, o=o, cr=cr, c5=c5, c1=c1, prompt=prompt, usd=usd(r, i, o, cr, c5, c1))
            prev = msgs.get(mid)
            if prev is None or oe > prev['oe']: msgs[mid] = rec
    return sorted(msgs.values(), key=lambda x: x['ts'])

def tot(recs):
    t = dict(msgs=len(recs), input=0, output=0, cache_read=0, cache_write=0, usd=0.0, output_est=0, usd_output_est=0.0)
    for r in recs:
        t['input'] += r['i']; t['output'] += r['o']; t['cache_read'] += r['cr']; t['cache_write'] += r['c5'] + r['c1']; t['usd'] += r['usd']; t['output_est'] += r['oe']; t['usd_output_est'] += r['usd_oe']
    t['total_tokens'] = t['input'] + t['output'] + t['cache_read'] + t['cache_write']
    t['usd'] = round(t['usd'], 4); t['usd_output_est'] = round(t['usd_output_est'], 4)
    t['total_tokens_output_est'] = t['input'] + t['output_est'] + t['cache_read'] + t['cache_write']
    return t

def local_hour(ts):
    t = dt.datetime.strptime(ts[:19], '%Y-%m-%dT%H:%M:%S').replace(tzinfo=dt.timezone.utc).astimezone()
    return t.strftime('%Y-%m-%d %H:00')

def main():
    out = r'C:\KenshiTestRuns\shadow\live-grading\cost.json'
    if '--out' in sys.argv: out = sys.argv[sys.argv.index('--out') + 1]
    res = {'_note': 'output_est = max(logged output_tokens, content chars/3.5): the transcript logs only ~15 output tokens per message so the logged output is a floor. API-equivalent USD from prices.json; messages de-duplicated by message id; H = af9f21f9 (first spawn) + a49b5c25 (resume), S = a96de446; agent jsonl under 05c6207d subagents',
           'prices': {k: v for k, v in PRICES.items() if not k.startswith('_')}}
    for arm in 'HS':
        recs = load(arm)
        # decision windows: last ledger line ts per batch
        last = {}
        for ln in open(LEDGER % arm, encoding='utf-8'):
            if ln.strip():
                e = json.loads(ln); last[e['batch_id']] = e['ts']
        bids = sorted(last); ends = [last[b] for b in bids]
        wins = collections.defaultdict(list)
        for r in recs:
            k = next((b for b, e in zip(bids, ends) if r['ts'] <= e), None)
            wins[k].append(r)   # None = after last decision (END handling)
        t = tot(recs); nd = len([b for b in bids if b <= 38])  # 38 graded batches (S also answered batch 39)
        t0, t1 = recs[0]['ts'], recs[-1]['ts']
        span = (dt.datetime.fromisoformat(t1.replace('Z', '+00:00')) - dt.datetime.fromisoformat(t0.replace('Z', '+00:00'))).total_seconds()/3600
        byh = collections.defaultdict(list)
        for r in recs: byh[local_hour(r['ts'])].append(r)
        res[arm] = dict(model=FAM[arm], agents=ARMS[arm], first_ts=t0, last_ts=t1, active_hours=round(span, 3),
                        decisions=nd, totals=t,
                        usd_per_decision=round(t['usd']/nd, 4), usd_per_decision_output_est=round(t['usd_output_est']/nd, 4), usd_per_active_hour=round(t['usd']/span, 4), usd_per_active_hour_output_est=round(t['usd_output_est']/span, 4),
                        tokens_per_decision=round(t['total_tokens']/nd),
                        output_per_decision=round(t['output_est']/nd),
                        per_hour={h: tot(v) for h, v in sorted(byh.items())},
                        per_decision={str(b): tot(wins[b]) for b in bids if wins.get(b)},
                        trailing_after_last_decision=tot(wins[None]) if wins.get(None) else None,
                        context=dict(first_prompt=recs[0]['prompt'], last_prompt=recs[-1]['prompt'], max_prompt=max(r['prompt'] for r in recs),
                                     msgs_over_100k=sum(1 for r in recs if r['prompt'] > BAND)))
    json.dump(res, open(out, 'w', encoding='utf-8'), indent=1)
    for a in 'HS':
        x = res[a]; t = x['totals']
        print(a, t, 'dec', x['decisions'], 'usd/dec', x['usd_per_decision'], 'usd/h', x['usd_per_active_hour'], x['context'], x['active_hours'])
        for h, v in x['per_hour'].items(): print('  ', h, v['msgs'], v['total_tokens'], v['usd'])
main()
