#!/usr/bin/env python3
"""sfxfake.py <kind h|w|sql> <body>   OFFLINE lane simulator for sfx_selftest.sh (12-d v2): fakelane.py plus, for the per-step stobe.log grep of rl_bundle, the lines a real step writes:
  [stale NPC line of the PREVIOUS step (step key `stale`)] + CHAT_SEND_STAGE: begin + resolved_speaker=Shay + the PC line + the NPC reply (+ step `log` lines).
Everything else is delegated to fakelane.py (steps: reply, prompt, server, give, stale, log; inv0).  Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
if kind == 'h' and 'stobe_say' not in body and 'ACTION_EXEC' in body and 'tail -n +' in body:
    scen = json.load(open(os.environ['FAKE_SCEN']))
    sp = os.environ['FAKE_STATE']
    st = json.load(open(sp)) if os.path.isfile(sp) else {'cur': -1}
    steps = scen.get('steps', [])
    cur = steps[st['cur']] if 0 <= st['cur'] < len(steps) else {}
    out = []
    if cur:
        if cur.get('stale'):
            out.append('[2026-10-16 10:55:04.546] [Stobe] ACTION_EXEC: SAY [Cind [Hungry Bandit]]: %s (NPC)' % cur['stale'])
        out.append('[2026-10-16 10:55:04.754] [Stobe] CHAT_SEND_STAGE: begin mode=chat request_mode=talk target_name=Cind [Hungry Bandit] text_len=32')
        out.append('[2026-10-16 10:55:04.755] [Stobe] CHAT_SEND_STAGE: resolved_speaker=Shay dist_to_target=9.0')
        out.append('[2026-10-16 10:55:04.773] [Stobe] ACTION_EXEC: SAY [Shay]: asked (PC)')
        out.append('[2026-10-16 10:55:09.244] [Stobe] ACTION_EXEC: SAY [Cind [Hungry Bandit]]: %s (NPC)' % cur.get('reply', ''))
        out.extend(cur.get('log', []))
    print('\n'.join(out))
    sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fakelane.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
sys.stderr.write(r.stderr)
sys.exit(r.returncode)
