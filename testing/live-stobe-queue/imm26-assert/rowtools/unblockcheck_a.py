#!/usr/bin/env python3
"""unblockcheck_a.py <ROW> <evidence-dir>   assertions for the imm26 unblock rows 08-e 08-d 11-b (imm26-u-rowsA); prints exactly ONE line
`RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence>` (exit 0/1/2/3) like rowcheck.py, whose helpers it reuses. Definitions + evidence writers: unblockdefs_a.sh.
  08-e : reloadcheck_a.c_08e (topic survives the load, exactly one followup:<id>:1 claim, no :2, ask_count 1) + targeted-tick evidence: a request that never reached the
         server is a SETUP-FAIL about the request, never the old 'speaker lottery' text; ticks delivered but no claim = SETUP-FAIL 'server-fix B, Shay decides'.
  08-d : rowcheck_trip.c_08d (topic closed outcome_completed after a REALLY WALKED trip, no situated_remark_claim, no NPC ask); U08D_NEG=1 (neg.txt neg=1) = negative control:
         trip not completed -> the topic stays open after the tick.
  11-b : topic open -> NPC in proven combat -> tick WITHOUT snapshot and tick WITH snapshot: no followup claim, ask_count unchanged -> combat over -> tick with snapshot:
         exactly one claim followup:<id>:1, ask_count +1.
A precondition that was not met (no topic, NPC gone, combat not proven, request failed, trip not completed) is SETUP-FAIL with `needs: ...`; never a PASS."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import reloadcheck_a as ra  # noqa: E402

rc = ra.rc
V, rd, need = rc.V, rc.rd, rc.need
jrows, newest_by_topic = ra.jrows, ra.newest_by_topic


def res(ev, tag):
    return (rd(ev, 'bored_%s.res' % tag) or '').strip() or 'missing'


def topic_pre(ev):
    pre = [js for js in newest_by_topic(jrows(ev, 'fu_pre.txt')).values() if js.get('kind') == 'personal_plan' and js.get('status') == 'open']
    return pre[-1] if pre else None


def ask_count(ev, name, tid):
    t = newest_by_topic(jrows(ev, name)).get(tid) or {}
    try:
        return int(t.get('ask_count') or 0)
    except ValueError:
        return -1


def claims(ev, name, tid):
    """event ids followup:<tid>:<n> in a rowid|type|data claim dump (raw regex: the data column is cut at 400 chars)"""
    return re.findall(r'followup:%s:\d+' % re.escape(tid), rd(ev, name) or '')


# ---------------------------------------------------------------- 08-e
def c_08e(v, ev):
    ra.c_08e(v, ev)
    if v.kind == 'SETUP-FAIL' and any('NO tick with the NPC as speaker' in b for b in v.bad):
        tags = ', '.join('%s=%s' % (f[6:-4], (rd(ev, f) or '').strip()) for f in sorted(os.listdir(ev)) if re.fullmatch(r'bored_08e\d+\.res', f))
        v.bad = ['topic still open after the reload and the targeted autochat request never reached the server (HTTP != 200 / no response): '
                 '%s; needs: recipe, check the lane backend port / stream.php (bored_08e1.txt)' % (tags or 'no bored_08e*.res')]
    elif v.kind == 'SETUP-FAIL' and any('server-side claim gate' in b for b in v.bad):
        v.good.append('R~ targeted ticks: ' + ', '.join(res(ev, '08e%d' % i) for i in range(1, 6) if os.path.isfile(os.path.join(ev, 'bored_08e%d.res' % i))))


# ---------------------------------------------------------------- 08-d
def c_08d(v, ev):
    walk = ' '.join((rd(ev, 'walk_done.txt') or 'no walk_done.txt').split())
    neg = 'neg=1' in (rd(ev, 'neg.txt') or '')
    if not neg:
        rc.CHECKS['08-d'](v, ev)
        if v.kind == 'SETUP-FAIL' and any('did not reach COMPLETED' in b for b in v.bad):
            v.bad = [(b + ' [walk: %s; needs: recipe (longer TRIP_WALK_TRIES / other TRIP_WALK_BACK) or server-fix, 23-a owner]' % walk) if 'did not reach COMPLETED' in b else b for b in v.bad]
        elif v.kind is None and res(ev, '08d') == 'http_err':
            v.bad = []
            v.good = []
            v.setup_fail('trip COMPLETED but the targeted bored request failed (bored_08d.txt has no HTTP=200): the claim path never ran')
        else:
            v.good.append('R~ walk: %s; tick=%s' % (walk, res(ev, '08d')))
        return
    # negative control: the trip stays unfinished, so the topic must stay open
    if not need(v, ev, 'agr_final.txt', 'fu_before.txt', 'fu_after.txt'):
        return
    topic = None
    for st in ('s0', 's0b'):
        for r in rc.full_rows(ev, st, {'social_followup'}):
            js = r[2]
            if js.get('kind') == 'personal_plan' and js.get('status') == 'open' and 'furs' in str(js.get('source_quote', '')).lower():
                topic = js
    if not topic:
        return v.setup_fail('negative control: no open personal_plan topic was created from the plain sentence (s0/s0b)')
    if re.search(r'^\d+\|COMPLETED\|', rd(ev, 'agr_final.txt') or '', re.M):
        return v.setup_fail('negative control: the trip reached COMPLETED although nothing walked it (needs: recipe, the control is void)')
    if res(ev, '08d') == 'http_err':
        return v.setup_fail('negative control: the targeted bored request failed (no HTTP=200), the claim path never ran')
    tid = topic.get('topic_id', '')
    after = [r for r in jrows(ev, 'fu_after.txt') if r[2].get('topic_id') == tid]
    last = max(after, key=lambda r: r[0])[2] if after else {}
    v.ck('negative_trip_not_completed_topic_stays_open', last.get('status') == 'open', 'status=%s closed_reason=%s' % (last.get('status'), last.get('closed_reason')))
    v.good.append('R~ negative control; tick=%s' % res(ev, '08d'))


# ---------------------------------------------------------------- 11-b
def c_11b(v, ev):
    if not need(v, ev, 'fu_pre.txt', 'mark_rowid.txt', 'state_combat_pre.txt', 'state_combat.txt', 'claim_c1b.txt', 'claim_c1a.txt', 'fu_combat.txt', 'state_calm.txt',
                'claim_after.txt', 'fu_final.txt'):
        return
    t = topic_pre(ev)
    if not t:
        return v.setup_fail('no open personal_plan social_followup after the topic line (s1): nothing to claim (needs: recipe, RW_FU_SAY)')
    tid = t['topic_id']
    st = dict((k, (rd(ev, 'state_%s.txt' % k) or '').strip()) for k in ('combat_pre', 'combat', 'calm'))
    if any('gone' in s for s in st.values()):
        return v.setup_fail('the NPC vanished/died during the fight (%s): the scene is not isolated enough (needs: recipe, protect both, fewer enemies)' % st)
    rows = (rd(ev, 'combat_rows.txt') or '').strip()
    proven = 'in_combat=true' in st['combat'] or ('in_combat=unknown' in st['combat'] and rows.isdigit() and int(rows) > 0)
    if not proven:
        return v.setup_fail('the NPC was not in proven combat at the tick (state_combat %s, combat rows %s): the combat leg is untestable (needs: recipe, longer U11B_FIGHT_S / closer enemy)'
                            % (st['combat'], rows or '?'))
    bad = [tg for tg in ('c1b', 'c1a', 'c2') if res(ev, tg) in ('http_err', 'missing')]
    if bad:
        return v.setup_fail('targeted bored request failed for %s (no HTTP=200; see bored_<tag>.txt): the claim path never ran (needs: recipe, lane backend)' % bad)
    a0 = ask_count(ev, 'fu_pre.txt', tid)
    cb, ca = claims(ev, 'claim_c1b.txt', tid), claims(ev, 'claim_c1a.txt', tid)
    v.ck('no_claim_in_combat_without_snapshot', not cb, '%s (tick %s)' % (cb, res(ev, 'c1b')))
    v.ck('no_claim_in_combat_with_fresh_snapshot', not ca, '%s (tick %s)' % (ca, res(ev, 'c1a')))
    v.ck('ask_count_unchanged_in_combat', ask_count(ev, 'fu_combat.txt', tid) == a0, '%s->%s' % (a0, ask_count(ev, 'fu_combat.txt', tid)))
    v.note = 'R~ in-combat state %s, calm state %s, combat rows %s, ticks c1b=%s c1a=%s c2=%s' % (st['combat'], st['calm'], rows, res(ev, 'c1b'), res(ev, 'c1a'), res(ev, 'c2'))
    if cb or ca:
        v.note += (' | claim in combat: the after-combat leg is skipped (expected per code when the NPC has no/unknown combat state; '
                   'server fix = treat in-combat NPCs as ineligible, lib/social_attention.php:41 + bored.php)')
        return
    if 'in_combat=false' not in st['calm']:
        return v.setup_fail('combat did not end before the after-combat tick (%s): the second leg is untestable (needs: recipe, longer U11B_CALM_S)' % st['calm'])
    after = claims(ev, 'claim_after.txt', tid)
    v.ck('exactly_one_claim_after_combat', len(after) == 1 and after[0].endswith(':1'), '%s (tick %s)' % (after, res(ev, 'c2')))
    v.ck('ask_count_plus_1_after_claim', ask_count(ev, 'fu_final.txt', tid) == a0 + 1, '%s->%s' % (a0, ask_count(ev, 'fu_final.txt', tid)))


CHECKS = {'08-e': c_08e, '08-d': c_08d, '11-b': c_11b}


def main(argv):
    if len(argv) < 3 or rc.norm(argv[1]) not in CHECKS:
        print('usage: unblockcheck_a.py <ROW> <evidence-dir>   rows: %s' % ' '.join(sorted(CHECKS)), file=sys.stderr)
        return 2
    v = V(argv[1])
    CHECKS[rc.norm(argv[1])](v, argv[2])
    if v.note:
        v.good.append(v.note)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
