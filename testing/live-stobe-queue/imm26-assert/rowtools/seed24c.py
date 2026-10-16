#!/usr/bin/env python3
"""seed24c.py <agr-dump> <outdir> [--region Vain]   (imm26-sfE2)  Build the SEEDED area-goal state for row 24-c recipe A.

Input : a `rowid|travel_agreement|travel-v1:<actor>:<speaker>:{json}` dump (rd19_dump) taken AFTER an ordinary native trip is ACCEPTED/requested/running.
Output: <outdir>/seed.sql (INSERT of a clone of the newest agreement row with the area-goal shape), <outdir>/seed_row.json (the new state), stdout
        `SEED-OK rowid=<src> agreement=<id> region=<R>` (exit 0) or `SEED-BAD <why>` (exit 3).

What the clone changes (the rest of the row, incl. execution/request_id/session_generation, stays byte-for-byte the native trip's):
  kind guide|detour -> same_route (the only kind stobeAreaGoalTripStateValid accepts for an area trip) with plan_hash recomputed the way
  stobeTravelPlanHash does (actor_serial, speaker_serial, purpose, leader, destination{source,label,[id,actor_serial],x,y,z}); the original hash is
  recomputed first and must equal the stored one, otherwise the algorithm no longer matches the server and the seed is refused.
  + regional_goal block, honestly marked (endpoint_source seeded_resume_fixture, seeded=true): it proves ONLY the save/load resume leg of an area trip,
  NOT the natural 24-b chat path (SUGGEST -> consent -> route_ready), which cannot be reached on the lanes.
"""
import hashlib
import json
import os
import re
import sys


def plan_hash(actor, speaker, purpose, leader, point):
    dest = {'source': point.get('source'), 'label': str(point.get('label', '')).strip()}
    if point.get('source') == 'native_local':
        dest['id'] = str(point.get('id', ''))
        dest['actor_serial'] = int(point.get('actor_serial', 0))
    for a in 'xyz':
        dest[a] = float(point[a])
    canon = {'actor_serial': int(actor), 'speaker_serial': int(speaker), 'purpose': purpose, 'leader': leader, 'destination': dest}
    return hashlib.sha256(json.dumps(canon, ensure_ascii=False, separators=(',', ':')).encode('utf-8')).hexdigest()


def bad(why):
    print('SEED-BAD ' + why)
    sys.exit(3)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    dump, outdir = argv[1], argv[2]
    region = 'Vain'
    if '--region' in argv:
        region = argv[argv.index('--region') + 1]
    rows = []
    for ln in open(dump, encoding='utf-8', errors='replace').read().splitlines():
        p = ln.split('|', 2)
        if len(p) != 3 or not p[0].strip().isdigit() or p[1] != 'travel_agreement':
            continue
        i = p[2].find('{')
        if i < 0:
            continue
        try:
            js = json.loads(p[2][i:])
        except ValueError:
            continue
        rows.append((int(p[0]), p[2][:i], js))
    if not rows:
        bad('no travel_agreement rows in the dump (the ordinary trip never reached the database)')
    rid, key, js = rows[-1]
    m = re.fullmatch(r'travel-v1:(\d+):(\d+):', key)
    if not m:
        bad('unexpected agreement key %r' % key[:60])
    actor, speaker = m.group(1), m.group(2)
    ex = js.get('execution') if isinstance(js.get('execution'), dict) else {}
    if js.get('status') not in ('ACCEPTED', 'RUNNING') or ex.get('phase') not in ('accepted', 'requested', 'running'):
        bad('newest row is not an active native trip (status=%s phase=%s)' % (js.get('status'), ex.get('phase')))
    if js.get('leader') != 'npc':
        bad('trip is not NPC-led (leader=%s)' % js.get('leader'))
    pt = js.get('destination_point')
    if not isinstance(pt, dict):
        bad('row has no destination_point')
    try:
        orig = plan_hash(actor, speaker, str(js.get('kind')), 'npc', pt)
    except (KeyError, TypeError, ValueError):
        bad('destination_point is not a finite x/y/z point')
    if orig != js.get('plan_hash'):
        bad('plan_hash recompute mismatch (stored %s, computed %s): stobeTravelPlanHash changed, refusing to seed' % (str(js.get('plan_hash'))[:12], orig[:12]))
    new = dict(js)
    new['kind'] = 'same_route'
    new['plan_hash'] = plan_hash(actor, speaker, 'same_route', 'npc', pt)
    new['execution'] = dict(ex)
    if 'plan_hash' in new['execution']:
        new['execution']['plan_hash'] = new['plan_hash']
    gam = int(js.get('accepted_gamets') or js.get('created_gamets') or 0)
    scope = {'actor_id': int(actor), 'speaker_id': int(speaker)}
    new['regional_goal'] = {
        'region': region, 'goal_type': 'regional_outing',
        'endpoint_id': str(pt.get('id') or pt.get('label') or ''), 'endpoint_label': str(pt.get('label') or ''),
        'endpoint_source': 'seeded_resume_fixture', 'endpoint_actor_serial': int(actor), 'endpoint_region_evidence': 'seeded_not_proven',
        'trip_read_succeeded': True, 'trip_read_scope': scope,
        'trip_read_scope_hash': hashlib.sha256(json.dumps(scope, separators=(',', ':')).encode()).hexdigest(),
        'trip_read_actor_serial': int(actor), 'trip_read_speaker_serial': int(speaker), 'trip_read_gamets': gam,
        'prior_trip_status': 'none', 'checked_gamets': gam, 'ordinary_order_validation': 'passed', 'order_validation_gamets': gam,
        'seeded': True, 'seeded_by': 'imm26-sfE2'}
    data = key + json.dumps(new, ensure_ascii=False, separators=(',', ':'))
    if '$imm26seed$' in data:
        bad('data contains the dollar-quote tag')
    os.makedirs(outdir, exist_ok=True)
    cols = 'sess,gamets,localts,ts,people,location,geo,utterance_id,delivery_state'
    sql = ("insert into eventlog(type,data,%s) select type,$imm26seed$%s$imm26seed$,%s from eventlog where rowid=%d and type='travel_agreement'"
           % (cols, data, cols, rid))
    open(os.path.join(outdir, 'seed.sql'), 'w', encoding='utf-8').write(sql)
    open(os.path.join(outdir, 'seed_row.json'), 'w', encoding='utf-8').write(json.dumps(new, ensure_ascii=False))
    print('SEED-OK rowid=%d agreement=%s region=%s kind=%s->same_route plan_hash=%s->%s' % (rid, js.get('agreement_id'), region, js.get('kind'), orig[:10], new['plan_hash'][:10]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
