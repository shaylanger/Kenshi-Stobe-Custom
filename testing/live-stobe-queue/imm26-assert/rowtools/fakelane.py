#!/usr/bin/env python3
"""fakelane.py <kind h|w|sql> <body>   OFFLINE lane simulator for rowtools/selftest.sh (lt_fake). Never touches a game, ssh or DB.
Scenario JSON (env FAKE_SCEN) + state (env FAKE_STATE, json file). Scenario keys: dist, backend_down, ctxpush, npc_missing, follow (list of
state strings, one per stobe_state call), inv0 {"SHAY": {item: n}, "CIND": {...}}, steps [one per stobe_say, in order:
{reply, prompt, server, events [[type,data]], full [[type,data]], give [items moved NPC->Shay]}]."""
import json
import os
import re
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE']
st = json.load(open(sp)) if os.path.isfile(sp) else {'cur': -1, 'follow_calls': 0, 'time_calls': 0, 'inv': scen.get('inv0', {'SHAY': {}, 'CIND': {}})}
steps = scen.get('steps', [])
cur = steps[st['cur']] if 0 <= st['cur'] < len(steps) else {}


def save():
    json.dump(st, open(sp, 'w'))


def inv_line(who):
    d = st['inv'].get(who, {})
    return ' '.join(f'{{"name":"{k}","count":{v}}}'.replace('{', '').replace('}', '') for k, v in d.items())


out = []
if kind == 'h':
    if 'stobe_say' in body:
        st['cur'] += 1
        s = steps[st['cur']] if st['cur'] < len(steps) else {}
        for it in s.get('give', []):
            st['inv']['CIND'][it] = st['inv']['CIND'].get(it, 1) - 1
            if st['inv']['CIND'][it] <= 0:
                del st['inv']['CIND'][it]
            st['inv']['SHAY'][it] = st['inv']['SHAY'].get(it, 0) + 1
        out.append('ok')
    elif 'stobe_ctxpush' in body:
        out.append(scen.get('ctxpush', 'ok observed_unix=1'))
    elif 'stobe-auto status' in body:
        out.append('phase=world speed=0.5 paused=0 save=sim' if not scen.get('game_down') else 'ERROR no answer')
    elif 'stobe-auto where' in body:
        m = re.search(r"where '?([^'\n]+?)'? </dev/null", body)
        if scen.get('npc_missing'):
            out.append('ERROR not found')
        else:
            out.append(f"Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=-50970.0,1533.0,2965.0 dist={scen.get('dist', 9.0)}")
    elif 'unconscious' in body:
        out.append('"unconscious":false')
    elif 'stobe-auto inv' in body:
        who = 'SHAY' if 'inv ' + "'Shay'" in body else 'CIND'
        out.append(inv_line(who))
    elif 'stobe_state' in body:
        f = scen.get('follow', ['{}'])
        out.append(f[min(st['follow_calls'], len(f) - 1)]); st['follow_calls'] += 1
    elif 'stobe-auto time' in body:
        out.append(f"time {100 + 24 * st['time_calls']}.0 day"); st['time_calls'] += 1 if 'speed' not in body else 0
    elif 'stobe-auto chars' in body:
        out.append("3 within 600.0: Shay #1/1 [Nameless] pos=0,0,0 dist=0.0 | Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=1,1,1 dist=9.0 | Rethar Dax #5/1 [Outlaw Watch] pos=2,2,2 dist=30.0 race=x")
    elif "grep -a -E 'FOLLOW'" in body:   # 23-b native follow evidence: scenario key follow_log = [lines before expiry, lines after]
        fl = scen.get('follow_log', [[]]); out.extend(fl[min(st.get('follow_log_calls', 0), len(fl) - 1)]); st['follow_log_calls'] = st.get('follow_log_calls', 0) + 1
    elif 'ACTION_EXEC' in body and 'tail -n +' in body:
        if cur:
            out.append('resolved_speaker=Shay')
            out.append(f"ACTION_EXEC: SAY [Cind]: {cur.get('reply', '')} (NPC)")
    elif 'wc -l' in body:
        out.append(str(100 + st['cur']))
    elif 'stobe-auto speed' in body:
        st['time_calls'] += 1
elif kind == 'w':
    if 'curl' in body:
        if not scen.get('backend_down'):
            out.append('{"status":"ok"}')
    elif 'stat -c' in body:
        out.append('1000')
    elif 'wc -l' in body:
        out.append('10')
    elif 'tail -c +' in body:
        out.append(cur.get('prompt', ''))
    elif 'stobeserver.log' in body:
        out.append(cur.get('server', ''))
    elif 'haff.php' in body:
        out.append('{"npc":"Cind","before":[],"after":[{"aff":1}]}')
elif kind == 'sql':
    if "id='PLAYER_NAME'" in body and 'select value' in body:
        out.append('Shay')
    elif 'stobe_social_contract where status' in body:
        out.append('0/0')
    elif 'max(rowid)' in body:
        out.append('100')
    elif 'count(*) from social_effect' in body:
        out.append('5')
    elif 'from eventlog where rowid>' in body:
        key = 'full' if 'in (' in body else 'events'
        for i, (t, d) in enumerate(cur.get(key, [])):
            out.append(f'{101 + i}|{t}|{d}' + ('|' if key == 'events' else ''))
    elif 'from social_effect' in body:
        out.append('1|sim|row')
save()
print('\n'.join(out))
