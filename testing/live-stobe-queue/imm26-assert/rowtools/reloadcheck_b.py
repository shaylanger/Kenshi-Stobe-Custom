#!/usr/bin/env python3
"""reloadcheck_b.py <ROW> <evidence-dir>   save/load RESUME rows, set B (imm26-reloadrows-B): 14-e 13-f 13-g 10-e 19-e 19-f.
Prints exactly ONE line `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence> [evidence=<dir>]` (exit 0/1/2/3), same shape as rowcheck.py.
`reloadcheck_b.py --has <ROW>` exits 0 when the row belongs to this file (used by pywrap_b.sh). Evidence layout: see reloaddefs_b.sh.
Strict: a missing required file is FAIL, never PASS. R~ wording is listed for a human and never decides. Reuses rowcheck.py helpers (V, rd, need,
full_rows, first_reply, agr_dump, ex_of, dest_xyz, state_ai, owned_travel_lines, accepted_row, post_rows, resume_chain)."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rowcheck as rc  # noqa: E402

V, rd, need = rc.V, rc.rd, rc.need
BAD_FINAL = ('EXPIRED', 'IMPOSSIBLE', 'CANCELLED', 'REJECTED')


def deal(ev, tag):
    """dict of deal_<tag>.txt ('contract_id|status|shift_total|age_s|KIND:STATUS,..|shifts-json') or None"""
    t = (rd(ev, f'deal_{tag}.txt') or '').strip().splitlines()
    p = t[0].split('|', 5) if t else []
    if len(p) < 5 or not p[0].strip() or not p[2].strip().lstrip('-').isdigit():
        return None
    terms = {}
    for x in p[4].split(','):
        if ':' in x:
            k, s = x.split(':', 1)
            terms.setdefault(k, s)
    try:
        shifts = json.loads(p[5]) if len(p) > 5 and p[5].strip() else []
    except ValueError:
        shifts = []
    return {'id': p[0], 'status': p[1], 'shift': int(p[2]), 'age': int(p[3]) if p[3].strip().lstrip('-').isdigit() else -1, 'terms': terms, 'shifts': shifts if isinstance(shifts, list) else [], 'raw': t[0]}


def num(ev, name):
    t = re.sub(r'\D', '', rd(ev, name) or '')
    return int(t) if t else None


def inv_gain(ev, who, item):
    b, a = rc.inv(ev, 'before').get(who, {}), rc.inv(ev, 'after').get(who, {})
    return a.get(item, 0) - b.get(item, 0)


def pause_checks(v, d, label, cap_single=1200):
    v.ck(f'{label}_resume_shift_recorded(resume_shifts has >=1 entry)', bool(d['shifts']), len(d['shifts']))
    v.ck(f'{label}_pause_0<shift<={cap_single}(min(gap,1200) per reload)', 0 < d['shift'] <= cap_single, d['shift'])
    v.ck(f'{label}_pause_total_le_3600_cap', d['shift'] <= 3600, d['shift'])


def fired_two(v, ev):
    b, a = num(ev, 'fired_before.txt'), num(ev, 'fired_after.txt')
    v.ck('inject_fired_exactly_2_steps(offer + accept)', b is not None and a is not None and a - b == 2, f'before={b} after={a}')


# ---------------------------------------------------------------- 14-e
def c_14e(v, ev):
    """counter-offer open, reload, accept after the reload: the offer was NOT expired by the reload (clock paused) and the deal performs"""
    if not need(v, ev, 'deal_s1.txt', 'deal_backdated.txt', 'deal_post.txt', 'deal_end.txt', 's2/reply.txt', 'fired_before.txt', 'fired_after.txt', 't_backdate.txt', 't_accept.txt'):
        return
    s1, bd, post, end = (deal(ev, t) for t in ('s1', 'backdated', 'post', 'end'))
    if not s1:
        return v.setup_fail(f"no contract row after the offer turn: {rd(ev, 'deal_s1.txt')!r}")
    if s1['status'] not in ('PROPOSED', 'COUNTERED'):
        return v.setup_fail(f"counter-offer not open after s1 (status {s1['status']}): nothing to carry over a reload")
    v.ck('offer_open_before_save(PROPOSED|COUNTERED)', True, s1['status'])
    v.ck('backdated_age_>=_500s(offer is near its 10 min window)', bool(bd) and bd['age'] >= 500, bd['age'] if bd else None)
    if not (post and end):
        v.ck('post_and_end_snapshots_parse', False, f"post={bool(post)} end={bool(end)}")
        return
    v.ck('same_contract_id_before_and_after_reload', s1['id'] == post['id'] == end['id'], f"{s1['id']} {post['id']} {end['id']}")
    v.ck('offer_not_expired_by_the_reload(status after load)', post['status'] not in BAD_FINAL, post['status'])
    v.ck('accept_after_reload_worked(ACCEPTED|AWAITING_PERFORMANCE|COMPLETE)', end['status'] in ('ACCEPTED', 'AWAITING_PERFORMANCE', 'COMPLETE'), end['status'])
    v.ck('deal_performs_after_reload(NPC leg GIVE_ITEM VERIFIED)', end['terms'].get('GIVE_ITEM') == 'VERIFIED' or end['status'] == 'COMPLETE', end['terms'])
    v.ck('bread_reached_the_player(inventory delta >= 1)', inv_gain(ev, 'SHAY', 'Bread') >= 1, inv_gain(ev, 'SHAY', 'Bread'))
    pause_checks(v, end, 'deal')
    fired_two(v, ev)
    t0, t1 = num(ev, 't_backdate.txt'), num(ev, 't_accept.txt')
    if t0 is not None and t1 is not None and bd:
        need_s = 600 - bd['age']
        if t1 - t0 <= need_s:   # the accept would have worked without the pause: the row does not prove it
            return v.setup_fail(f'row does not prove the pause: accept came {t1 - t0}s after the backdate, the 10 min window needed more than {need_s}s (raise ROW_BACKDATE_S)')
        v.note = f'pause was needed: age at backdate {bd["age"]}s + {t1 - t0}s until accept > 600s; R~ ' + repr(rc.first_reply(ev, 's2')[:110])
    else:
        v.ck('timing_files_parse', False, f'{t0} {t1}')


# ---------------------------------------------------------------- 13-g / 13-f
def effects(ev, rid):
    rows = []
    for ln in (rd(ev, 'effects_deal.txt') or '').splitlines():
        p = ln.split('|')
        if len(p) >= 5 and p[3] == f'deal:{rid}':
            try:
                rows.append((p[1], int(float(p[2])), p[3], p[4]))
            except ValueError:
                pass
    return rows


def pending_common(v, ev):
    """pre-save state shared by 13-f / 13-g; returns (pre, post, end) or None"""
    if not need(v, ev, 'deal_s1.txt', 'deal_pre.txt', 'deal_post.txt', 'deal_end.txt', 'effects_deal.txt', 'clock_pre.txt', 'clock_post.txt'):
        return None
    pre, post, end = deal(ev, 'pre'), deal(ev, 'post'), deal(ev, 'end')
    if not pre:
        v.setup_fail(f"no deal row after the accept: {rd(ev, 'deal_pre.txt')!r}")
        return None
    if pre['status'] != 'AWAITING_PERFORMANCE' or pre['terms'].get('GIVE_ITEM') != 'VERIFIED':
        v.setup_fail(f"deal not pending before the save (status {pre['status']}, terms {pre['terms']}): the NPC leg never completed")
        return None
    v.ck('pending_before_save(AWAITING_PERFORMANCE, NPC GIVE_ITEM VERIFIED)', True, pre['id'])
    if not (post and end):
        v.ck('post_and_end_snapshots_parse', False, f'post={bool(post)} end={bool(end)}')
        return None
    v.ck('same_contract_id_across_the_reload', pre['id'] == post['id'] == end['id'], f"{pre['id']} {post['id']} {end['id']}")
    v.ck('deal_alive_after_load(AWAITING_PERFORMANCE, not expired/impossible/cancelled)', post['status'] == 'AWAITING_PERFORMANCE', post['status'])
    cp, cq = ((rd(ev, 'clock_pre.txt') or '').strip().splitlines() or [''])[0].rsplit('|', 1)[0], ((rd(ev, 'clock_post.txt') or '').strip().splitlines() or [''])[0].rsplit('|', 1)[0]  # load_token itself contains '|'
    v.ck('negotiation_clock_saw_a_new_load_token', bool(cp) and bool(cq) and cp != cq, f'{cp[-24:]} -> {cq[-24:]}')
    pause_checks(v, end, 'deal')
    return pre, post, end


def c_13g(v, ev):
    """pay-later deal, reload, pay -> COMPLETE, kept_promise 1..3 on incident deal:<id>"""
    r = pending_common(v, ev)
    if not r:
        return
    pre, post, end = r
    price = num(ev, 'price.txt')
    v.ck('price_known(GIVE_CATS amount)', bool(price), price)
    v.ck('deal_COMPLETE_after_paying_post_reload', end['status'] == 'COMPLETE', end['status'])
    v.ck('player_leg_GIVE_CATS_VERIFIED', end['terms'].get('GIVE_CATS') == 'VERIFIED', end['terms'])
    ef = effects(ev, pre['id'])
    kp = [e for e in ef if e[0] == 'kept_promise']
    v.ck('kept_promise_row_delta_1..3_incident_deal:<id>', len(kp) == 1 and 1 <= kp[0][1] <= 3, [(e[0], e[1]) for e in ef])
    v.ck('no_broken_promise_for_this_deal', not [e for e in ef if e[0] == 'broken_promise'], [e[0] for e in ef])


def c_13f(v, ev):
    """pay-later deal, reload, no payment, deadline past -> BREACHED_PLAYER + broken_promise -5..-15 (the obligation survived the reload)"""
    r = pending_common(v, ev)
    if not r:
        return
    pre, post, end = r
    v.ck('deal_BREACHED_PLAYER_when_deadline_passes', end['status'] == 'BREACHED_PLAYER', end['status'])
    ef = effects(ev, pre['id'])
    bp = [e for e in ef if e[0] == 'broken_promise']
    v.ck('broken_promise_row_delta_-15..-5_incident_deal:<id>', len(bp) == 1 and -15 <= bp[0][1] <= -5, [(e[0], e[1]) for e in ef])
    v.ck('no_kept_promise_for_this_deal', not [e for e in ef if e[0] == 'kept_promise'], [e[0] for e in ef])


# ---------------------------------------------------------------- 10-e
def pj(ev, name):
    t = (rd(ev, name) or '').strip()
    i = t.find('{')
    try:
        return json.loads(t[i:t.rfind('}') + 1]) if i >= 0 else None
    except ValueError:
        return None


def c_10e(v, ev):
    """restitution scope across a REAL reload (seeded in-memory agreements frozen at the pre-load scope; wpR2 gate)"""
    if not need(v, ev, 'probe_pre.json', 'probe_eval.json'):
        return
    pre, evl = pj(ev, 'probe_pre.json'), pj(ev, 'probe_eval.json')
    for n, j in (('pre', pre), ('eval', evl)):
        if not j or j.get('error'):
            return v.setup_fail(f"probe {n} unusable: {(j or {}).get('error') or rd(ev, f'probe_{n}.json')!r:.200}")
    s0, s1 = pre['scope'], evl['live']
    try:   # imm26 sfC (10-e): after a REAL restart the native epoch restarts at 1; the server's load_seq (when present in both) orders the loads
        if s0.get('load_seq') is not None and s1.get('load_seq') is not None:
            later = int(s1['load_seq']) > int(s0['load_seq'])
        else:
            later = int(s1['timeline_epoch']) > int(s0['timeline_epoch'])
    except (KeyError, TypeError, ValueError):
        later = False
    if not (later and s1.get('native_session_id') != s0.get('native_session_id') and s1.get('campaign_id') == s0.get('campaign_id')):
        return v.setup_fail(f"no later load of the same campaign observed (pre {s0}, live {s1}): the game did not reload or the lane has no playthrough session")
    v.ck('real_later_load_same_campaign(load order up, session changed)', True, f"epoch {s0['timeline_epoch']}->{s1['timeline_epoch']} load_seq {s0.get('load_seq')}->{s1.get('load_seq')}")
    if evl.get('ingest_mode') != 'enabled':
        return v.setup_fail(f"SOCIAL_RELATIONSHIP_MODE is {evl.get('ingest_mode')!r}, the term gate returns null (set it to enabled on the lane)")
    v.ck('rescope_kill_switch_on(STOBE_REPAIR_RESCOPE_ENABLED)', evl.get('rescope_enabled') is True, evl.get('rescope_enabled'))
    c = evl['cases']
    a = c['same_campaign_later_load']
    v.ck('later_load_same_campaign_keeps_term_alive(not scope_changed, not IMPOSSIBLE)', a['note'] != 'exact_restitution_scope_changed' and a['status'] != 'IMPOSSIBLE', a)
    for k in ('other_save', 'older_epoch'):
        v.ck(f'{k}_IMPOSSIBLE_exact_restitution_scope_changed', c[k]['status'] == 'IMPOSSIBLE' and c[k]['note'] == 'exact_restitution_scope_changed', c[k])
    u = c['unprovable_after_reload']
    v.ck('unprovable_after_reload_IMPOSSIBLE_not_UNMET(no broken-promise penalty)', u['status'] == 'IMPOSSIBLE' and u['note'] == 'exact_restitution_unprovable_after_reload', u)
    k = c['same_load_deadline_control']
    v.ck('control_same_load_deadline_stays_UNMET(old behaviour)', k['status'] == 'UNMET' and k['note'] == 'exact_receipt_deadline_passed', k)
    v.note = 'banked-VERIFIED-proof-kept leg NOT covered (needs a real exact return = row 10-f, needs: native durable item id); the seeded agreements carry no DB state'


# ---------------------------------------------------------------- 19-e
def c_19e(v, ev):
    """visited-town trip, LAZY resume (Shay 2026-10-15): nothing resumes before a chat turn (control: no OWNED_TRAVEL, no requested/running row in the quiet window),
    then ONE chat line resumes the SAME agreement (OWNED_TRAVEL accepted=1 on that turn, resume chain, native order to the stored destination)"""
    if not need(v, ev, 's2/ev_full.txt', 'agr_pre.txt', 'agr_ctl.txt', 'agr_all.txt', 'load_rowid.txt', 'quiet.txt', 's4/reply.txt', 'post_s4.txt'):
        return
    orig = rc.accepted_row(ev)
    v.ck('agreement_ACCEPTED', bool(orig), 'none' if not orig else orig.get('agreement_id'))
    if not orig:
        return
    if not rc.owned_travel_lines(ev, 's2', 's3'):
        return v.setup_fail('no pre-load OWNED_TRAVEL accepted=1 in s2/s3 (the native trip never started; nothing to resume)')
    aid = orig.get('agreement_id', '')
    pre_rows = [j for _, j in rc.agr_dump(ev, 'agr_pre.txt') if j.get('agreement_id') == aid]
    pre = rc.ex_of(pre_rows[-1]) if pre_rows else {}
    q = rd(ev, 'quiet.txt') or ''
    m = re.search(r'owned_travel_accepted=(\d+)', q)
    v.ck('control_no_OWNED_TRAVEL_before_any_chat(lazy resume is the CORRECT state)', bool(m) and int(m.group(1)) == 0, m.group(0) if m else 'no summary line')
    try:
        mark = int((rd(ev, 'load_rowid.txt') or '0').strip() or 0)
    except ValueError:
        mark = 0
    moved = [(r, rc.ex_of(j).get('phase')) for r, j in rc.agr_dump(ev, 'agr_ctl.txt') if r > mark and j.get('agreement_id') == aid and rc.ex_of(j).get('phase') in ('requested', 'running')]
    v.ck('control_agreement_not_moved_before_any_chat(no requested/running row after the load)', not moved, moved)
    ot = rc.owned_travel_lines(ev, 's4')
    v.ck('chat_turn_resumes_exactly_one_OWNED_TRAVEL_accepted', len(ot) == 1, f'n={len(ot)}')
    rc.resume_chain(v, rc.post_rows(ev), aid, pre, orig)
    fo, dst = rc.state_ai(ev, 'post_s4.txt')
    xyz = rc.dest_xyz(orig)
    v.ck('final_first_order_MOVE_CUS_ORDERED', fo == 'MOVE_CUS_ORDERED', fo)
    v.ck('final_destination_within_0.5', bool(xyz and dst) and max(abs(a - b) for a, b in zip(xyz, dst)) <= 0.5, f'stored={xyz} state={dst}')
    v.note = f'lazy resume: {q.strip()}; resume turn reply R~ ' + repr(rc.first_reply(ev, 's4')[:110])


# ---------------------------------------------------------------- 19-f
def last_row(ev, name, aid):
    rows = [(r, j) for r, j in rc.agr_dump(ev, name) if j.get('agreement_id') == aid]
    return rows[-1][1] if rows else None


def c_19f(v, ev):
    """N reloads in ONE trip (target: all resume, still ACCEPTED/running; cap: reload cap+1 ends FAILED resume_failure=resume_count, honestly)"""
    if not need(v, ev, 's2/ev_full.txt', 'mode.txt', 'n.txt', 'agr_all.txt', 'load_rowid.txt'):
        return
    mode, n = (rd(ev, 'mode.txt') or '').strip(), int((rd(ev, 'n.txt') or '0').strip() or 0)
    cap = (rd(ev, 'cap.txt') or '').strip()
    orig = rc.accepted_row(ev)
    v.ck('agreement_ACCEPTED', bool(orig), 'none' if not orig else orig.get('agreement_id'))
    if not orig or n < 2:
        return
    if not rc.owned_travel_lines(ev, 's2', 's3'):
        return v.setup_fail('no pre-load OWNED_TRAVEL accepted=1 in s2/s3 (the native trip never started)')
    aid = orig.get('agreement_id', '')
    v.note = f'mode={mode} reloads={n}' + (f' cap={cap}' if cap else ' cap=default 3')
    limit = int(cap) if cap.isdigit() else 3
    for i in range(1, n + 1):
        if not need(v, ev, f'agr_r{i}.txt', f'sr{i}/reply.txt', f'post_r{i}.txt'):
            return
        row = last_row(ev, f'agr_r{i}.txt', aid)
        ex = rc.ex_of(row or {})
        ot = rc.owned_travel_lines(ev, f'sr{i}')
        st, ph = (row or {}).get('status'), ex.get('phase')
        capped = mode == 'cap' and i > limit
        if capped:
            v.ck(f'reload{i}_FAILED_honestly_resume_count(terminal after the cap)', st == 'FAILED' and ex.get('resume_failure') == 'resume_count', f"{st}/{ph}/{ex.get('resume_failure')}")
            v.ck(f'reload{i}_no_new_OWNED_TRAVEL', not ot, len(ot))
            # only PROPOSED rows written AFTER the trip was accepted count (the original pre-accept PROPOSED row is in every agr_r dump)
            dump = rc.agr_dump(ev, f'agr_r{i}.txt')
            acc_ids = [r for r, j in dump if j.get('agreement_id') == aid and j.get('status') == 'ACCEPTED']
            first_acc = min(acc_ids) if acc_ids else 0
            v.ck(f'reload{i}_no_new_PROPOSED_row(no re-proposal loop)', not [r for r, j in dump if j.get('status') == 'PROPOSED' and r > first_acc], 'rows')
            break
        v.ck(f'reload{i}_still_ACCEPTED_and_resumed(requested|running)', st == 'ACCEPTED' and ph in ('requested', 'running'), f'{st}/{ph}/{ex.get("resume_failure")}')
        v.ck(f'reload{i}_exactly_one_OWNED_TRAVEL_accepted', len(ot) == 1, len(ot))
        v.ck(f'reload{i}_resume_count_is_{i}', int(ex.get('resume_count', 0) or 0) == i, ex.get('resume_count'))
        fo, dst = rc.state_ai(ev, f'post_r{i}.txt')
        xyz = rc.dest_xyz(orig)
        v.ck(f'reload{i}_native_order_to_stored_destination', fo == 'MOVE_CUS_ORDERED' and bool(xyz and dst) and max(abs(a - b) for a, b in zip(xyz, dst)) <= 0.5, f'{fo} {dst}')
    v.ck('one_agreement_id_throughout(no new trip)', {j.get('agreement_id') for _, j in rc.agr_dump(ev, 'agr_all.txt')} == {aid}, sorted({j.get('agreement_id', '?') for _, j in rc.agr_dump(ev, 'agr_all.txt')}))
    if mode == 'target':
        v.note += ' | expected FAIL on a build with the resume cap of 3 (audit gap (b)); mode=cap verifies the honest terminal instead'


CHECKS = {'14-e': c_14e, '13-g': c_13g, '13-f': c_13f, '10-e': c_10e, '19-e': c_19e, '19-f': c_19f}


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if rc.norm(argv[2]) in CHECKS else 1
    if len(argv) < 3 or rc.norm(argv[1]) not in CHECKS:
        print(f'usage: reloadcheck_b.py <ROW> <evidence-dir>   rows: {" ".join(sorted(CHECKS))}', file=sys.stderr)
        return 2
    v = V(argv[1])
    CHECKS[rc.norm(argv[1])](v, argv[2])
    if v.note:
        v.good.append(v.note)
    if os.environ.get('RELOAD_B_DEBUG'):   # selftest hook (stderr -> run.log): which assertions failed, one per entry
        print(f"BADCHECKS n={len(v.bad)} :: " + ' ## '.join(v.bad), file=sys.stderr)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
