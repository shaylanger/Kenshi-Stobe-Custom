#!/usr/bin/env python3
"""sfrfake.py <kind h|w|sql> <body>   OFFLINE lane simulator for sfr_selftest.sh and `sfrrun.sh --dry` (rows 23-b / 22-b / 20-a recipe v2). Answers the sfR-specific calls
(body markers set by sfrdefs.sh) and delegates the rest: the targeted bored tick (u:stream / u:srvn / u:tlog) to unblockfake_a.py, everything else to unblockfake_sfk.py
(-> unblockfake_f.py when the scenario key chain == 'f' -> ... -> fakelane.py). Counters/state in FAKE_STATE + '.sfr'. Never touches a game, ssh or DB.
Scenario keys (env FAKE_SCEN json):
  clock0 (game hours at start, 77.0)  rate (game hours per real second at speed 10, 0.08)  stall (bool: game time never advances)
  ini_missing (bool: no StobeCustom.ini on the lane)  ini_stuck (bool: the key does not stick)  ini_was (the ini's current FollowExpiryGameHours line, 24)
  no_follow (bool: no 'FOLLOW target resolved')  no_expiry (bool: the follow never expires)  early_expiry (bool: expires after 25% of the limit)  ticks_after_expiry (int, 0)
  sit_by_tick ([[rowid|type|json lines] per bored request (u:stream call), the last repeats])
  drift (int: after this many stobe_say calls the NPC is far (300 u) until `teleport Shay <npc>`)  stuck (bool: `teleport Shay <npc>` never brings Shay near)
  far_at_say (float: dist_to_target logged for says number >= 3, whatever the placement said)  The ACTION_EXEC reply query gets a CHAT_SEND_STAGE dist_to_target line when drift is set."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.sfr'
here = os.path.dirname(os.path.abspath(__file__))
st = json.load(open(sp)) if os.path.isfile(sp) else {'clock': float(scen.get('clock0', 77.0)), 'fs': None, 'limit': None, 'ticks': 0, 'far': False, 'say_dist': 8.0, 'nsay': 0}
SER = '2529907200'


def save():
    json.dump(st, open(sp, 'w'))


def out(lines):
    save()
    if lines:
        print('\n'.join(lines))
    sys.exit(0)


def delegate(mod, extra=None):
    save()
    r = subprocess.run([sys.executable, os.path.join(here, mod), kind, body], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    if extra:
        print('\n'.join(extra))
    sys.exit(0)


def limit_h():
    return float(st['limit']) if st['limit'] is not None else 24.0


def expiry_age_h():
    return limit_h() * (0.25 if scen.get('early_expiry') else 1.0)


def expired():
    return st['fs'] is not None and not scen.get('no_expiry') and st['clock'] - st['fs'] >= expiry_age_h()


if kind == 'h':
    m = re.search(r'# sr:iniset h=(\d+)', body)
    if m:
        if scen.get('ini_missing'):
            out(['NO-INI /fake/mods/Stobe/StobeCustom.ini'])
        was = scen.get('ini_was', 24)
        if scen.get('ini_stuck'):
            out(['was: FollowExpiryGameHours=%s' % was, 'now: FollowExpiryGameHours=%s' % was])
        st['limit'] = int(m.group(1))
        out(['was: FollowExpiryGameHours=%s' % was, 'now: FollowExpiryGameHours=%s' % m.group(1)])
    if '# sr:inirestore' in body:
        if scen.get('ini_missing') or st['limit'] is None:
            out(['no-backup (nothing to restore)'])
        st['limit'] = None
        out(['restored; key now: [FollowExpiryGameHours=%s] (empty = unset)' % scen.get('ini_was', 24)])
    if 'stobe-auto time' in body and 'sleep' not in body:
        out(['game_hours=%.4f day=3 time=05:15 speed=0.5 paused=0' % st['clock']])
    if 'speed 10' in body and 'sleep' in body:
        s = re.search(r'sleep (\d+)', body)
        if s and not scen.get('stall'):
            st['clock'] += int(s.group(1)) * float(scen.get('rate', 0.08))
        out([])
    if '# sr:follow' in body:
        lines = []
        if not scen.get('no_follow'):
            lines.append('[10:00:00] FOLLOW target resolved follower=%s target=Shay' % SER)
            lines.append('[10:00:01] FOLLOW order assigned follower=%s' % SER)
        if expired():
            fs = int((st['fs'] or 0) * 3600)
            lines.append('[10:09:00] FOLLOW_EXPIRED: follower=%s started_gamets=%d now_gamets=%d' % (SER, fs, fs + int(expiry_age_h() * 3600) + 40))
        lines.append('# ticks=%d' % (5 if st['fs'] is not None else 0))
        lines.append('[10:00:20] FOLLOW_TICK: follower=%s dist=6.1' % SER)
        lines.append('[10:00:30] FOLLOW_TICK: follower=%s dist=5.8' % SER)
        lines.append('# ticks_after_expiry=%d' % (int(scen.get('ticks_after_expiry', 0)) if expired() else 0))
        out(lines)
    if 'stobe_say' in body:
        st['nsay'] += 1
        st['say_dist'] = float(scen['far_at_say']) if scen.get('far_at_say') and st['nsay'] >= 3 else (300.0 if st['far'] else 8.0)
        if 'Follow me.' in body:
            st['fs'] = st['clock']
        if scen.get('drift') is not None and st['nsay'] >= int(scen['drift']):
            st['far'] = True      # the native order keeps walking: she is away again after the turn
        delegate('unblockfake_sfk.py')
    if re.search(r"teleport Shay '[^']*'", body):
        if not scen.get('stuck'):
            st['far'] = False
        save()
    if "where 'Cind" in body and not scen.get('npc_missing'):
        out(['Cind [Hungry Bandit] #%s/2 [Traders Guild] pos=-50970.0,1533.0,2965.0 dist=%s' % (SER, 300.0 if st['far'] else 8.0)])
    if "grep -E 'ACTION_EXEC|resolved_speaker" in body and 'tail -n +' in body and scen.get('drift') is not None:
        delegate('unblockfake_sfk.py', ['CHAT_SEND_STAGE: resolved_speaker=Shay dist_to_target=%.1f' % st['say_dist']])
elif kind == 'w':
    if 'u:stream' in body:
        st['ticks'] += 1
        delegate('unblockfake_a.py')
    if 'u:srvn' in body or 'u:tlog' in body:
        delegate('unblockfake_a.py')
elif kind == 'sql':
    if '-- sr:sit' in body:
        seq = scen.get('sit_by_tick', [[]])
        out([] if st['ticks'] == 0 else seq[min(st['ticks'] - 1, len(seq) - 1)])
delegate('unblockfake_sfk.py')
