#!/usr/bin/env python3
"""reloadcheck_sfe.py <ROW> <evidence-dir>   (imm26-sfE2) checker for the corrected recipes of rows 24-c (SEEDED, resume leg only) and 26-f (ClearGroup one-call).
Reuses reloadcheck_a.py's assertions unchanged (nothing is weakened); adds only precondition checks (SETUP-FAIL) and the SEEDED marker.
24-c : every RESULT line starts with `SEEDED regional_goal (resume leg only, row stays PARTIAL, natural 24-b path NOT proven)`; a PASS means only that an area-goal-shaped
       trip (regional_goal block cloned onto a real native trip by seed24c.py) resumes after a save+load. The `accepted_row` of the set-A checker is taken from the seeded
       row (seed_row.json) because the seed is not in any step's ev_full.
26-f : SETUP-FAIL unless scene.txt ends SCENE-OK and the accepted pre-save record carries a campZone.candidateId and agreedTargets; then reloadcheck_a.c_job unchanged
       (continuation chain + identical agreedTargets; campZone PRESENT with a NEW world-scoped id/digest = camp_zone_rebound; fix26fcamp). SETUP-FAIL when reseat.txt has SCENE-LOST.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import reloadcheck_a as ra  # noqa: E402

rc = ra.rc
SEED_TAG = 'SEEDED regional_goal (resume leg only; row stays PARTIAL, natural 24-b path NOT proven)'


class SeededV(rc.V):
    def emit(self, evdir):
        kind = self.kind or ('PASS' if not self.bad else 'FAIL')
        ev = '; '.join(self.bad + self.good)
        print(f'RESULT {self.row} {kind} {SEED_TAG}: {ev}'[:1700] + f' [evidence={evdir}]')
        return {'PASS': 0, 'FAIL': 1, 'SETUP-FAIL': 2, 'GATED': 3}[kind]


def c_24c_seeded(v, ev):
    seeded = rc.rd(ev, 'seeded.txt')
    if not seeded or not seeded.startswith('SEEDED'):
        why = (rc.rd(ev, 'seed_py.txt') or 'seed step never ran (the ordinary native trip did not reach OWNED_TRAVEL accepted=1)').strip()[:240]
        return v.setup_fail('regional_goal seed missing (nothing to resume): ' + why)
    try:
        row = json.loads(rc.rd(ev, 'seed_row.json') or '{}')
    except ValueError:
        row = {}
    if not row.get('agreement_id') or not isinstance(row.get('regional_goal'), dict):
        return v.setup_fail('seed_row.json has no agreement_id / regional_goal')
    pre = [j for _, j in rc.agr_dump(ev, 'agr_pre.txt')] if rc.rd(ev, 'agr_pre.txt') else []
    v.ck('seeded_row_is_newest_pre_load', bool(pre) and pre[-1].get('agreement_id') == row['agreement_id'] and bool((pre[-1].get('regional_goal') or {}).get('seeded')),
         f'rows={len(pre)}')
    rc.accepted_row = lambda e: row          # c_24c reads the accept leg from s2/s3 ev_full, where the seeded row is not
    ra.c_24c(v, ev)


def c_26f(v, ev):
    sc = (rc.rd(ev, 'scene.txt') or '').strip().splitlines()
    if not sc or not sc[-1].startswith('SCENE-OK'):
        return v.setup_fail('ClearGroup scene not ready: ' + (sc[-1][:200] if sc else 'scene.txt missing') + ' (needs: lane in Rebirth, 4 pinned Dust Bandits seen by Cind)')
    if rc.rd(ev, 'act_pre.txt') is not None:
        acc = [r for r in ra.recs(ev, 'act_pre.txt') if r['kind'] == 'ClearGroup' and r['status'] == 'accepted']
        if acc and not ('candidateId' in acc[-1]['camp'] and acc[-1]['targets'].strip('[] ')):
            return v.setup_fail('accepted ClearGroup carries no campZone.candidateId / agreedTargets (camp variant not staged): camp=%r targets=%r' % (acc[-1]['camp'][:80], acc[-1]['targets'][:60]))
    lost = [ln for ln in (rc.rd(ev, 'reseat.txt') or '').splitlines() if ln.startswith('SCENE-LOST')]   # fix26fcamp: the recipe probe after the load found the bandit scene gone
    if lost:
        return v.setup_fail('scene lost across the save/load (not a product result; the exact agreedTargets cannot match): ' + lost[0][:220])
    ra.c_job(v, ev)


def main(argv):
    if len(argv) < 3 or rc.norm(argv[1]) not in ('24-c', '26-f'):
        print('usage: reloadcheck_sfe.py <24-c|26-f> <evidence-dir>', file=sys.stderr)
        return 2
    row = rc.norm(argv[1])
    v = SeededV(argv[1]) if row == '24-c' else rc.V(argv[1])
    (c_24c_seeded if row == '24-c' else c_26f)(v, argv[2])
    if v.note:
        v.good.append(v.note)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
