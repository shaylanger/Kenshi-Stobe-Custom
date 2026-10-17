#!/usr/bin/env python3
"""unblockscen_14d.py <name>   scenario JSON (for unblockfake_14d.py) used by unblock_14d_selftest.sh. Base = `pass`: 6 bandits spawned (5 near + 1 distant), probe round 1 sees 3 of 5, round 2 sees 5,
the ask yields a proposed ClearGroup with the 5 near serials, the accept moves it to accepted then completed, one outbox row has status accepted, attack lines name near members only,
the distant bandit stays alive. The selftest mutates the keys for every failure cause."""
import json
import sys

NEAR = ['111938480/2', '3344848640/3', '2773071360/4', '187011712/5', '2656128000/6']
FAR = '901000001/7'
ns = [n.split('/')[0] for n in NEAR]
SPAWN = 'spawned 6/6 Dust Bandit: ' + ', '.join('Dust Bandit #%s race=Greenlander' % n for n in NEAR + [FAR])
NM = ['Wulf', 'Doran', 'Prenn', 'Othra', 'Falt']


def member(i, sel=1, vis=1, prot=0, reason='', owner=None, slave=0, chained=0, prison=0, setn=5):
    ln = ('[2026-10-16 11:05:19.331] [Stobe] ACTIVITY_CLEARGROUP_MEMBER actor=3035888640 serial=%s name=%s [Dust Bandit] set=%d/5 selected=%d visible=%d hostile=1 protected=%d protReason=%s '
          'active=1 dead=0 ko=0 finite=1 pathExists=%s memberY=705 actorY=723.7 ' % (ns[i], NM[i], setn, sel, vis, prot, reason, '1' if sel else '99(not_evaluated)'))
    if owner is not None:
        ln += 'ownerSerial=%s slaveState=%d chained=%d prison=%d animal=0 ' % (owner, slave, chained, prison)
    return ln + 'dist2d=32.3 dist3d=37.3'


def prompt(arr):
    return 'PROMPT ... "agreedTargets":[%s] ... end' % ','.join(arr)


def rec(status, kind='ClearGroup', targets=None, rid='act-0001', rev=1):
    return '%s|%d|%s|%s|v1:cand|[%s]' % (rid, rev, status, kind, ','.join(ns if targets is None else targets))


def base():
    return {
        'where_nameless': True, 'spawn': SPAWN,
        'steps': [{'reply': 'I can see them.', 'prompt': prompt(ns[:3])}, {'reply': 'Five of them.', 'prompt': prompt(ns)},
                  {'reply': 'Right, I will hunt them with you.', 'prompt': prompt(ns)}, {'reply': 'Lets go.', 'prompt': prompt(ns)}],
        'members': [[member(i, sel=1 if i < 3 else 0, prot=0 if i < 3 else 1, reason='' if i < 3 else 'owned_target', owner=0 if i < 3 else 77, setn=3) for i in range(5)],
                    [member(i) for i in range(5)]],
        'recs': [[rec('proposed')], [rec('accepted', rev=2)], [rec('completed', rev=3)]],
        'outbox': ['1|1|true|{"status":"proposed","kind":"ClearGroup"}', '2|2|true|{"status":"accepted","kind":"ClearGroup"}', '3|3|true|{"status":"completed","kind":"ClearGroup"}'],
        'atkpre': [], 'atkpost': ['[t] UNPROVOKED_FOCUSED_MELEE_ATTACK actor=3035888640 target=%s' % ns[0], '[t] ACTIVITY_PROGRESS_DIAG reset=target_damage target=%s' % ns[1]],
        'actlines': ['[t] ACTIVITY_PROGRESS_DIAG reset=target_damage id=act-0001 target=%s' % ns[1]],
        'alive': ['2 within 400: Dust Bandit #%s [Dust Bandits] | Dust Bandit #%s [Dust Bandits] | Dust Bandit #%s [Dust Bandits] | Dust Bandit #%s [Dust Bandits]' % (NEAR[0], NEAR[3], FAR, NEAR[4])],
    }


if __name__ == '__main__':
    n = sys.argv[1]
    if n != 'pass':
        raise SystemExit('unknown scenario ' + n)
    print(json.dumps(base()))
