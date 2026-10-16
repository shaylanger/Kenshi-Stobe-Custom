#!/usr/bin/env python3
"""rowcheck_trip.py: trip-family row assertions (13-b 20-a 20-b 23-a 23-c 23-d 24-a), registered into rowcheck.CHECKS by
`register(rowcheck_module, CHECKS)` (a 4-line hook at the bottom of rowcheck.py). Same philosophy as rowcheck.py: the mechanical parts decide
the verdict, R~ (reply wording) points are listed as evidence, a missing required file is FAIL, an unmet precondition is SETUP-FAIL, a row
that can only be forced by a method the table does not name is GATED (never PASS). No assertion of the manual recipes was dropped.
Evidence files (written by tripdefs.sh): s<N>/* bundles (N may be 1b/2b), agr_*.txt = `rowid|status|phase|reason|owned_work_released|agreement_id|destination`
(newest first), state_*.txt = stobe_state JSON, npc.txt = resolved NPC name.
"""
import re


def register(rc, CHECKS):
    V, rd, full_rows, first_reply, need = rc.V, rc.rd, rc.full_rows, rc.first_reply, rc.need
    STEPS = ('s1', 's1b', 's2', 's2b')

    def agr(ev, name):
        out = []
        for ln in (rd(ev, name) or '').splitlines():
            p = ln.strip().split('|')
            if len(p) >= 7 and p[0].isdigit():
                out.append(dict(rowid=int(p[0]), status=p[1], phase=p[2], reason=p[3], released=p[4], aid=p[5], dest='|'.join(p[6:])))
        return out

    def latest(rows):
        seen = {}
        for r in rows:                      # newest first
            seen.setdefault(r['aid'], r)
        return seen

    def accepted(ev):
        """ACCEPTED travel_agreement rows found while proposing/accepting (s1..s2b); newest last"""
        rows = []
        for st in STEPS:
            rows += [r for r in full_rows(ev, st, {'travel_agreement'}) if r[2].get('status') == 'ACCEPTED']
        return rows

    def orig(ev):
        a = accepted(ev)
        if not a:
            return None
        js = a[-1][2]
        return dict(aid=js.get('agreement_id', ''), dest=js.get('destination', ''), rowid=a[-1][0])

    def speaker_lines(ev, step, who):
        pre = (who or '').split(' [')[0].split()[0].lower() if (who or '').strip() else ''
        out = []
        for sp, tx in re.findall(r'ACTION_EXEC: SAY \[(.+?)\]: (.*?) \(NPC\)', rd(ev, step, 'reply.txt') or ''):
            if not pre or sp.lower().startswith(pre):
                out.append(tx.strip())
        return out

    def ai(ev, name):
        t = rd(ev, name)
        if t is None:
            return None

        def g(k):
            m = re.search(r'"%s"\s*:\s*"([^"]*)"' % k, t)
            return m.group(1) if m else None
        pj = re.search(r'"permajobs"\s*:\s*\[([^\]]*)\]', t)
        return dict(first=g('first_order'), goal=g('current_goal'), faction=g('faction'), jobs=(pj.group(1).strip() if pj else None))

    def pre_ok(v, ev):
        """a trip must have been ACCEPTED before the row's own leg is testable"""
        if not orig(ev):
            v.setup_fail('no ACCEPTED travel_agreement while setting up the trip (propose/accept legs failed; see s1/s1b/s2/s2b, same defect as 19-a/14-a)')
            return False
        return True

    # ---------------------------------------------------------------- 23-a
    def c_23a(v, ev):
        if not pre_ok(v, ev):
            return
        if not need(v, ev, 's3/ev_full.txt', 's3/reply.txt', 'state_after.txt', 'state_shay.txt', 'agr_final.txt'):
            return
        o = orig(ev)
        fin = latest(agr(ev, 'agr_final.txt')).get(o['aid'])
        v.ck('agreement_COMPLETED', bool(fin) and fin['status'] == 'COMPLETED', (fin or {}).get('status', 'row not found'))
        v.ck('owned_work_released_true', bool(fin) and fin['released'].lower() == 'true', (fin or {}).get('released', '?'))
        a = ai(ev, 'state_after.txt')
        v.ck('no_follow_or_travel_controller', a['first'] == 'none' and a['goal'] == 'NULL_TASK', f"first_order={a['first']} current_goal={a['goal']}")
        sh = ai(ev, 'state_shay.txt')
        v.ck('npc_not_in_squad', bool(a['faction']) and a['faction'] != sh['faction'], f"npc={a['faction']} shay={sh['faction']}")
        acks = speaker_lines(ev, 's3', (rd(ev, 'npc.txt') or '').strip())
        v.ck('one_completion_acknowledgement', len(acks) == 1, f'n={len(acks)}')
        v.note = f'R~ ack: {acks[0][:140]!r}' if acks else ''

    # ---------------------------------------------------------------- 20-a
    def c_20a(v, ev):
        if not pre_ok(v, ev):
            return
        if not need(v, ev, 's3/ev_full.txt', 's3/reply.txt', 's4/ev_full.txt'):
            return
        o = orig(ev)
        alt = (rd(ev, 'alt.txt') or '').strip()
        core = re.sub(r'^the\s+', '', alt, flags=re.I).lower()
        s3 = full_rows(ev, 's3', {'travel_agreement'})
        moved = [r for r in s3 if core and core in str(r[2].get('destination', '')).lower() and r[2].get('status') in ('PROPOSED', 'ACCEPTED')]
        ended = [r for r in s3 if r[2].get('agreement_id') == o['aid'] and r[2].get('status') in ('ENDED', 'CANCELLED', 'FAILED')]
        v.ck('destination_unchanged_until_confirmed', not moved and not ended, f'moved={len(moved)} ended={len(ended)}')
        r3 = first_reply(ev, 's3')
        v.ck('npc_replied_to_change', bool(r3))
        s4 = full_rows(ev, 's4', {'travel_agreement'})
        done = [r for r in s4 if r[2].get('agreement_id') == o['aid'] and r[2].get('status') in ('ENDED', 'CANCELLED')] \
            or [r for r in s4 if core and core in str(r[2].get('destination', '')).lower() and r[2].get('status') in ('PROPOSED', 'ACCEPTED')]
        v.ck('after_confirm_old_row_ended_or_replaced', bool(done), 'rows=' + ','.join(f"{r[0]}:{r[2].get('status')}" for r in s4)[:120])
        v.note = f'R~ original referenced? {r3[:150]!r} | confirm: {first_reply(ev, "s4")[:100]!r}'

    # ---------------------------------------------------------------- 20-b
    def c_20b(v, ev):
        if not pre_ok(v, ev):
            return
        if not need(v, ev, 'agr_after.txt', 's3/reply.txt', 'forced.txt'):
            return
        o = orig(ev)
        fin = latest(agr(ev, 'agr_after.txt')).get(o['aid'])
        v.ck('row_FAILED_after_forced_failure', bool(fin) and fin['status'] == 'FAILED', (fin or {}).get('status', 'row not found'))
        reason = (fin or {}).get('reason', '')
        v.ck('failure_reason_recorded', bool(reason), reason or 'empty')
        r3 = ' '.join(speaker_lines(ev, 's3', (rd(ev, 'npc.txt') or '').strip()))
        v.ck('reply_names_original_destination', bool(o['dest']) and o['dest'].lower() in r3.lower(), f"dest={o['dest']}")
        v.note = f"R~ grounded reason? forced={(rd(ev, 'forced.txt') or '').strip()[:60]} reply: {r3[:150]!r}"
        if not v.bad and 'native_path_or_actor_failure' not in reason:
            v.gated(f"all mechanical checks pass but the failure reason is '{reason}', not native_path_or_actor_failure: a true path failure needs "
                    "TRIP_TRAP='x y z' (unreachable spot) or a human; order replacement only proves the reconcile")

    # ---------------------------------------------------------------- 23-c
    def c_23c(v, ev):
        if not pre_ok(v, ev):
            return
        if not need(v, ev, 's3/reply.txt', 's4/reply.txt', 'state_cind_before.txt', 'state_cind_after_leave.txt', 'state_malzin_before.txt',
                    'state_malzin_after_leave.txt', 'state_malzin_after_end.txt', 'agr_s3.txt', 'agr_final.txt'):
            return
        o = orig(ev)
        cb, ca = ai(ev, 'state_cind_before.txt'), ai(ev, 'state_cind_after_leave.txt')
        mb, ml, me = ai(ev, 'state_malzin_before.txt'), ai(ev, 'state_malzin_after_leave.txt'), ai(ev, 'state_malzin_after_end.txt')

        def tok(s):
            return bool(re.search(r'ACTION_EXEC:\s*LEAVE', rd(ev, s, 'reply.txt') or ''))
        a3 = latest(agr(ev, 'agr_s3.txt')).get(o['aid'])
        v.ck('leave_to_nonsquad_does_nothing', not tok('s3') and cb['faction'] == ca['faction'] and bool(a3) and a3['status'] == 'ACCEPTED',
             f"leave_action={tok('s3')} faction={cb['faction']}->{ca['faction']} trip={(a3 or {}).get('status')}")
        v.ck('leave_to_squad_member_works', bool(ml['faction']) and mb['faction'] != ml['faction'], f"faction={mb['faction']}->{ml['faction']} leave_action={tok('s4')}")
        fin = latest(agr(ev, 'agr_final.txt')).get(o['aid'])
        v.ck('end_ends_only_the_temporary_npc_trip', bool(fin) and fin['status'] == 'ENDED', (fin or {}).get('status', 'row not found'))
        v.ck('end_does_not_touch_squad_member', ml['faction'] == me['faction'], f"faction after leave={ml['faction']} after END={me['faction']}")
        v.note = f"R~ leave(Cind): {first_reply(ev, 's3')[:80]!r} leave(Malzin): {first_reply(ev, 's4')[:80]!r} (unrelated-job control: evidenced by 23-d)"

    # ---------------------------------------------------------------- 23-d
    def c_23d(v, ev):
        if not pre_ok(v, ev):
            return
        if not need(v, ev, 'job_set.txt', 's3/reply.txt', 'state_after.txt', 'agr_final.txt'):
            return
        o = orig(ev)
        fin = latest(agr(ev, 'agr_final.txt')).get(o['aid'])
        v.ck('agreement_ENDED', bool(fin) and fin['status'] == 'ENDED', (fin or {}).get('status', 'row not found'))
        blob = (rd(ev, 's3', 'reply.txt') or '') + (rd(ev, 's3', 'events.txt') or '') + (rd(ev, 's3', 'server.txt') or '')
        m = re.search(r'owned_order_removed\w*|owned_order_cancel\w*', blob)
        v.ck('owned_order_cancelled_with_receipt_reason', bool(m), m.group(0) if m else 'no receipt reason in the withdraw turn')
        a = ai(ev, 'state_after.txt')
        v.ck('trip_order_gone', a['first'] == 'none', f"first_order={a['first']}")
        v.ck('unrelated_job_intact', bool(a['jobs']), f"permajobs=[{a['jobs']}]")
        v.note = f'R~ reply: {first_reply(ev, "s3")[:140]!r}'

    # ---------------------------------------------------------------- 24-a
    def c_24a(v, ev):
        if not need(v, ev, 's1/prompt.txt', 's1/ev_full.txt', 's2/ev_full.txt'):
            return
        p = rd(ev, 's1', 'prompt.txt')
        m = re.search(r'Grounded named-place choices|Known places you can name', p)
        v.ck('prompt_named_place_choices', bool(m), m.group(0) if m else 'absent')
        kp = re.search(r'Known places you can name:\s*([^\n]+)', p)
        places = [x.strip() for x in kp.group(1).split(',')] if kp else []
        trip = full_rows(ev, 's1', {'travel_agreement'})
        v.ck('no_trip_row_for_mood_question', not trip, f"n={len(trip)} statuses={sorted({r[2].get('status', '?') for r in trip})}")
        v.ck('control_no_region_plan_for_what_is_Vain_like', not full_rows(ev, 's2', {'region_plan'}))
        cand = re.search(r'candidate[^\n]{0,80}|places=\d+', (rd(ev, 's1', 'reply.txt') or '') + (rd(ev, 's1', 'server.txt') or ''))
        r1 = first_reply(ev, 's1')
        hit = [x for x in places if x and x.lower() in r1.lower()]
        v.note = f"R~ names a listed place? {hit or 'none'} of {places[:5]} | candidate log: {cand.group(0)[:60] if cand else 'none'} | reply: {r1[:120]!r}"

    # ---------------------------------------------------------------- 13-b
    def c_13b(v, ev):
        if not need(v, ev, 'n2_armed.txt', 'n2_control.txt', 'se_base.txt', 'se_armed.txt', 'se_control.txt', 'partner.txt'):
            return
        partner = (rd(ev, 'partner.txt') or '').strip().split(' [')[0].split()[0]
        na, nc = rd(ev, 'n2_armed.txt'), rd(ev, 'n2_control.txt')
        if not re.search(r'N2_(PROXIMITY|ABANDON)', na) and not re.search(r'N2_(PROXIMITY|ABANDON)', nc):
            return v.setup_fail('no N2_PROXIMITY/N2_ABANDON lines at all: the N2 watch is not running (install the NC6 DLL 3ADDE488, see NC6/NOTES.md)')
        ab = re.search(r'N2_ABANDON:[^\n]*partner=%s[^\n]*state=knocked_out[^\n]*' % re.escape(partner), na) \
            or re.search(r'N2_ABANDON:[^\n]*state=knocked_out[^\n]*partner=%s[^\n]*' % re.escape(partner), na)
        v.ck('armed_N2_ABANDON_logged', bool(ab), ab.group(0)[:110] if ab else 'none')

        def n(f):
            return len([x for x in (rd(ev, f) or '').splitlines() if x.strip()])
        base, arm, ctl = n('se_base.txt'), n('se_armed.txt'), n('se_control.txt')
        rows = [x for x in (rd(ev, 'se_armed.txt') or '').splitlines() if partner.lower() in x.lower()]
        v.ck('armed_abandoned_in_danger_effect_row', arm > base and bool(rows) and bool(re.search(r'[,(|]-\d', rows[0])), f'rows base={base} armed={arm} partner_rows={len(rows)}')
        v.ck('control_healthy_partner_no_N2_ABANDON', 'N2_ABANDON' not in nc, 'none' if 'N2_ABANDON' not in nc else 'FIRED on a healthy partner')
        v.ck('control_healthy_partner_no_new_effect_row', ctl == arm, f'armed={arm} control={ctl}')
        v.note = f'R~ phases: {(rd(ev, "phases.txt") or "").strip()[:200]!r}'

    CHECKS.update({'13-b': c_13b, '20-a': c_20a, '20-b': c_20b, '23-a': c_23a, '23-c': c_23c, '23-d': c_23d, '24-a': c_24a})
