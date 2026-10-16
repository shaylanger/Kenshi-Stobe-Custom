#!/usr/bin/env python3
"""reloadcheck_a.py <ROW> <evidence-dir>   assertions for the save+load RESUME rows, set A (imm26-reloadrows-A); prints exactly ONE line
`RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence>` (exit 0/1/2/3) like rowcheck.py, whose helpers it reuses (V, rd, full_rows, first_reply, need, agr_dump,
resume_chain, ...). Rows: 26-d 26-dx 26-e 26-f 24-c 23-e 27-a 08-e 20-d. Definitions + evidence writers: reloaddefs_a.sh. Strict like rowcheck.py: a missing
required file is FAIL, an unmet precondition (no offer / accept did not land / order never applied) is SETUP-FAIL with `needs: ...`, R~ wording is listed only.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rowcheck as rc  # noqa: E402

V, rd, full_rows, first_reply, need = rc.V, rc.rd, rc.full_rows, rc.first_reply, rc.need
ACTIVE = ('proposed', 'accepted')
BG_NEAR = float(os.environ.get('RW_BG_NEAR', '100'))   # 27A-FIX: bodyguard end-of-chase limit (u). The native Bodyguard package keeps a stand-off of ~50-67 u, so the legacy-FOLLOW 35 u never fits; a non-follower stays ~RW_AWAY_BG (200) u away


def recs(ev, name):
    """[dict] of an activity dump (reloaddefs_a.sh rw_act_dump): id|world|actor|requester|revision|status|kind|resourceId|quantity|resume.state|of|continuedAs|count|agreedTargets|campZone"""
    keys = ['id', 'world', 'actor', 'req', 'rev', 'status', 'kind', 'res', 'qty', 'rstate', 'rof', 'rcont', 'rcount', 'targets', 'camp']
    out = []
    for ln in (rd(ev, name) or '').splitlines():
        p = ln.rstrip('\r').split('|')
        if len(p) >= 15 and p[0].strip():
            out.append(dict(zip(keys, [p[0].strip()] + p[1:14] + ['|'.join(p[14:])])))
    return out


def outbox(ev, name):
    """[(agreement_id, revision, ack, world)]"""
    out = []
    for ln in (rd(ev, name) or '').splitlines():
        p = ln.strip().split('|')
        if len(p) >= 4 and p[0]:
            out.append(tuple(p[:4]))
    return out


def jrows(ev, name):
    """[(rowid:int, type, dict)] of a `rowid|type|data` eventlog dump"""
    out = []
    for ln in (rd(ev, name) or '').splitlines():
        p = ln.split('|', 2)
        if len(p) == 3 and p[0].strip().isdigit():
            m = re.search(r'\{.*\}', p[2])
            try:
                js = json.loads(m.group(0)) if m else {}
            except ValueError:
                js = {}
            out.append((int(p[0]), p[1], js))
    return out


def same_terms(a, b):
    bad = []
    for k in ('kind', 'res', 'qty', 'targets', 'camp'):
        if (a.get(k) or b.get(k)) and a.get(k) != b.get(k):
            bad.append(f'{k}:{a.get(k)}->{b.get(k)}')
    return bad


def chk_ctx(v, ev, label):
    st = rc.state_ai(ev, 'state_post.txt')[0] if os.path.isfile(os.path.join(ev, 'state_post.txt')) else None
    v.note = f"R~ resume-turn reply {first_reply(ev, 's3')[:140]!r}; post-load first_order={st}"


# ---------------------------------------------------------------- 26-d / 26-f (accepted job), 26-dx (cancelled stays cancelled)
def c_job(v, ev):
    kind = (rd(ev, 'kind.txt') or 'Hunt').strip(); mode = (rd(ev, 'mode.txt') or 'run').strip()
    if not need(v, ev, 'act_s1.txt', 'kind.txt', 'mode.txt'):
        return
    s1 = [r for r in recs(ev, 'act_s1.txt') if r['kind'] == kind and r['status'] == 'proposed']
    if not s1:
        return v.setup_fail(f'no {kind} proposal after the offer (s1): nothing to accept or resume (needs: recipe, see 25-a for the Hunt offer fixture / 14-d for ClearGroup)')
    if not need(v, ev, 'act_pre.txt', 'act_log_pre.txt'):
        return
    pre = recs(ev, 'act_pre.txt')
    logpre = rd(ev, 'act_log_pre.txt') or ''
    if mode == 'nc':
        c = [r for r in pre if r['kind'] == kind and r['status'] == 'cancelled']
        if not c:
            return v.setup_fail('"Cancel that." did not leave a cancelled record (26-b precondition; needs: native/recipe, see 26-a/26-b)')
        old = c[-1]
    else:
        a = [r for r in pre if r['kind'] == kind and r['status'] == 'accepted']
        if not a:
            bad = [ln for ln in logpre.splitlines() if re.search(r'rejected|refused|requester_now_hostile', ln)]
            return v.setup_fail('accept did not produce an accepted record (known blocker 26-a: ACTIVITY start rejected requester_now_hostile; needs: native/recipe)'
                                + (f': {bad[0][:160]}' if bad else ''))
        old = a[-1]
    if not need(v, ev, 'act_post.txt', 'out_post.txt', 'act_log_post.txt', 's3/reply.txt'):
        return
    post = recs(ev, 'act_post.txt')
    logpost = rd(ev, 'act_log_post.txt') or ''
    byid = {r['id']: r for r in post}
    o = byid.get(old['id'])
    if mode == 'nc':
        v.ck('cancelled_record_still_cancelled', bool(o) and o['status'] == 'cancelled', (o or {}).get('status', 'row missing'))
        v.ck('no_continuation_of_cancelled', not [r for r in post if r['rof'] == old['id']], [r['id'] for r in post if r['rof'] == old['id']])
        v.ck('no_active_record_after_reload', not [r for r in post if r['status'] in ACTIVE], [r['status'] for r in post if r['status'] in ACTIVE])
        pre_ids = {x[:2] for x in outbox(ev, 'out_pre.txt')}
        v.ck('no_new_grant_in_outbox', {x[:2] for x in outbox(ev, 'out_post.txt')} <= pre_ids, len(outbox(ev, 'out_post.txt')) - len(pre_ids))
        chk_ctx(v, ev, kind)
        return
    v.ck('pre_world_known', bool(old['world']), old['world'])
    v.ck('old_record_superseded', bool(o) and o['status'] == 'superseded', (o or {}).get('status', 'row missing'))
    cont = (o or {}).get('rcont', '')
    n = byid.get(cont) if cont else None
    if n is None:
        n = next((r for r in post if r['rof'] == old['id'] and r['id'] != old['id']), None)
    v.ck('continuation_record_exists', n is not None, cont or 'resume.continuedAs empty')
    if n is None:
        chk_ctx(v, ev, kind)
        return
    v.ck('new_agreement_id', n['id'] != old['id'], f"{old['id']}->{n['id']}")
    v.ck('old_continuedAs_names_new_id', cont == n['id'], cont)
    v.ck('chained_via_resume.of', n['rof'] == old['id'], n['rof'])
    v.ck('continuation_world_is_new_epoch', bool(n['world']) and n['world'] != old['world'], f"{old['world']}->{n['world']}")
    v.ck('continuation_active_or_done', n['status'] in ('accepted', 'completed'), n['status'])
    v.ck('resume_state_resumed', n['rstate'] == 'resumed', n['rstate'])
    v.ck('resume_count_1', n['rcount'] == '1', n['rcount'])
    v.ck('terms_identical', not same_terms(old, n), same_terms(old, n) or f"{n['kind']} {n['res']} qty={n['qty']}")
    act = [r for r in post if r['world'] == n['world'] and r['actor'] == n['actor'] and r['status'] in ACTIVE]
    v.ck('exactly_one_active_record_for_actor_in_new_world', len(act) == 1 or n['status'] == 'completed', len(act))
    ob = [x for x in outbox(ev, 'out_post.txt') if x[0] == n['id']]
    v.ck('grant_re_emitted_in_outbox', bool(ob) and all(x[3] == n['world'] for x in ob), f'rows={len(ob)}')
    rej = [ln for ln in logpost.splitlines() if re.search(r'start rejected|ACTIVITY_REJECT', ln)]
    v.ck('resume_start_not_rejected', not rej, rej[0][:140] if rej else 'none')
    if os.path.isfile(os.path.join(ev, 'act_final.txt')):
        fin = {r['id']: r for r in recs(ev, 'act_final.txt')}.get(n['id'])
        v.ck('hand_over_completed', bool(fin) and fin['status'] == 'completed', (fin or {}).get('status', 'row missing'))
    chk_ctx(v, ev, kind)
    if not os.path.isfile(os.path.join(ev, 'act_final.txt')):
        v.note += ' | completion leg not run (set RW_COMPLETE=1)'


# ---------------------------------------------------------------- 26-e (proposal)
def c_26e(v, ev):
    if not need(v, ev, 'act_pre.txt', 'kind.txt'):
        return
    pre = [r for r in recs(ev, 'act_pre.txt') if r['kind'] == 'Hunt' and r['status'] == 'proposed']
    if not pre:
        return v.setup_fail('no Hunt proposal before the save: nothing to resume (needs: recipe, see 25-a: 3 fresh wild goats within 7 u of the NPC + the offer wording)')
    if not need(v, ev, 'act_post_s2.txt', 'act_post_s3.txt', 'act_log_post.txt', 's2/reply.txt', 's3/reply.txt'):
        return
    old = pre[-1]
    p2 = {r['id']: r for r in recs(ev, 'act_post_s2.txt')}
    r2 = p2.get(old['id'])
    v.ck('proposal_record_survives', r2 is not None, 'row missing' if r2 is None else old['id'])
    if r2 is not None:
        v.ck('rebound_to_new_world', bool(r2['world']) and r2['world'] != old['world'], f"{old['world']}->{r2['world']}")
        v.ck('still_proposed_after_rebind', r2['status'] == 'proposed', r2['status'])
        v.ck('resume_state_recorded', r2['rstate'] in ('pending', 'resumed'), r2['rstate'])
        v.ck('terms_identical', not same_terms(old, r2), same_terms(old, r2) or f"{r2['kind']} {r2['res']}")
    v.ck('no_orphan_proposal_in_old_world', not [r for r in p2.values() if r['world'] == old['world'] and r['status'] in ACTIVE], [r['status'] for r in p2.values() if r['world'] == old['world'] and r['status'] in ACTIVE])
    p3 = recs(ev, 'act_post_s3.txt')
    acc = [r for r in p3 if r['kind'] == 'Hunt' and r['status'] == 'accepted' and r['world'] == (r2 or {}).get('world', '')]
    rej = [ln for ln in (rd(ev, 'act_log_post.txt') or '').splitlines() if re.search(r'start rejected|requester_now_hostile', ln)]
    if not acc and rej:
        return v.setup_fail('"Yes" after the re-proposal reached the native start and was rejected (known blocker 26-a requester_now_hostile; needs: native): ' + rej[0][:140])
    v.ck('yes_accepts_after_repropose', bool(acc), [r['status'] for r in p3] or 'no records')
    v.note = f"R~ s2 (re-propose?) {first_reply(ev, 's2')[:120]!r} | s3 {first_reply(ev, 's3')[:80]!r}"


# ---------------------------------------------------------------- 24-c
def c_24c(v, ev):
    orig = rc.accepted_row(ev)
    if not orig:
        return v.setup_fail('no ACCEPTED area-goal trip before the save (region plan -> native route -> accept never completed; needs: recipe, see 24-b / P-REGION)')
    if not rc.owned_travel_lines(ev, 's2', 's3', 's3b'):
        return v.setup_fail('no pre-load OWNED_TRAVEL accepted=1 (the native trip never started)')
    if not isinstance(orig.get('regional_goal'), dict) or not orig.get('regional_goal'):
        return v.setup_fail('the accepted trip carries no regional_goal block: not an area-goal trip (needs: recipe, 24-b region route)')
    if not need(v, ev, 's4/reply.txt', 's5/reply.txt', 'agr_pre.txt', 'agr_all.txt', 'load_rowid.txt', 'post_s5.txt'):
        return
    aid = orig.get('agreement_id', '')
    pre_rows = [j for _, j in rc.agr_dump(ev, 'agr_pre.txt') if j.get('agreement_id') == aid]
    pre = rc.ex_of(pre_rows[-1]) if pre_rows else {}
    v.ck('pre_load_execution_known', bool(pre.get('request_id')), f"request_id={pre.get('request_id')} gen={pre.get('session_generation')}")
    rows = rc.post_rows(ev)
    rc.resume_chain(v, rows, aid, pre, orig)
    mine = [j for _, j in rows if j.get('agreement_id') == aid]
    v.ck('post_load_regional_goal_kept', bool(mine) and all(isinstance(j.get('regional_goal'), dict) and j['regional_goal'] for j in mine), len(mine))
    ot = rc.owned_travel_lines(ev, 's4', 's5')
    v.ck('exactly_one_post_load_OWNED_TRAVEL_accepted', len(ot) == 1, f'n={len(ot)}')
    xyz = rc.dest_xyz(orig)
    fo, dst = rc.state_ai(ev, 'post_s5.txt')
    v.ck('post_s5_first_order_MOVE_CUS_ORDERED', fo == 'MOVE_CUS_ORDERED', fo)
    v.ck('post_s5_destination_within_0.5', bool(xyz and dst) and max(abs(a - b) for a, b in zip(xyz, dst)) <= 0.5, f'stored={xyz} state={dst}')
    v.note = f"R~ s4 {first_reply(ev, 's4')[:140]!r}; region {orig.get('regional_goal', {}).get('region', '?')}"


# ---------------------------------------------------------------- 23-e / 27-a (chase legs)
def chase(ev, name):
    t = (rd(ev, name) or '').strip().split('|')
    try:
        return float(t[0]), float(t[1])
    except (ValueError, IndexError):
        return None, None


def c_23e(v, ev):
    if not need(v, ev, 'follow_log_pre.txt'):
        return
    if 'FOLLOW target resolved' not in (rd(ev, 'follow_log_pre.txt') or ''):
        return v.setup_fail('native FOLLOW never started on "Follow me." (no FOLLOW target resolved; needs the NC DLL, see 23-b)')
    if not need(v, ev, 'chase_pre.txt', 'chase_post.txt', 'follow_log_post.txt'):
        return
    a0, a1 = chase(ev, 'chase_pre.txt')
    if a0 is None or a0 < 60 or a1 is None or a1 > 35:
        return v.setup_fail(f'follow did not work BEFORE the save (dist after teleporting Shay away {a0} -> {a1} after the chase): nothing to resume (needs: recipe)')
    b0, b1 = chase(ev, 'chase_post.txt')
    lp = rd(ev, 'follow_log_post.txt') or ''
    ticks = len(re.findall(r'FOLLOW_TICK', lp))
    v.ck('follow_ticks_after_load', ticks > 0, f'FOLLOW_TICK lines={ticks}')
    v.ck('not_expired_early', 'FOLLOW_EXPIRED' not in lp, 'FOLLOW_EXPIRED present' if 'FOLLOW_EXPIRED' in lp else 'none')
    v.ck('no_stale_hand', 'setDestination failed' not in lp, 'FOLLOW: setDestination failed' if 'setDestination failed' in lp else 'none')
    v.ck('post_load_precondition_Shay_away', b0 is not None and b0 >= 60, f'dist after teleport={b0}')
    v.ck('post_load_follower_closes_distance', b1 is not None and b0 is not None and b1 <= 35 and b1 < b0, f'{b0} -> {b1}')
    v.note = f'R~ pre-load chase {a0}->{a1}; verdict FAIL with no ticks and a far NPC = the legacy follow is LOST on load (native fix: see wpR3 report section 3)'


def _bg_ok(t):
    """Drop harness error lines (an `unknown command: contract-bodyguard` / `no character named` answer contains 'bodyguard' but proves nothing)."""
    return '\n'.join(l for l in t.splitlines() if not re.search(r'ERROR|unknown command|no character named', l, re.I))


def _bg_has(t):
    """A real order proof: the harness hire/status answer `has_contract=1 package=Bodyguard ...`, a BODYGUARD word, or a BODYGUARD goal in the stobe state."""
    return bool(re.search(r'BODYGUARD|has_contract=1', _bg_ok(t), re.I))


def _bg_status_err(t):
    """True when the status query only produced harness error lines (no has_contract= answer at all)."""
    return bool(re.search(r'ERROR|unknown command|no character named', t, re.I)) and 'has_contract=' not in t


def c_27a(v, ev):
    pre_raw = (rd(ev, 'state_pre.txt') or '') + (rd(ev, 'bg_pre.txt') or '') + (rd(ev, 'bg_set.txt') or '')   # bg_set.txt: the hire answer `has_contract=1 package=Bodyguard` is pre-load proof
    if not need(v, ev, 'state_pre.txt', 'bg_pre.txt', 'bg_set.txt'):
        return
    if not _bg_has(pre_raw):
        errs = ' | '.join(' '.join(l.split())[:100] for l in pre_raw.splitlines() if re.search(r'ERROR|unknown command|no character named', l, re.I))[:240]
        return v.setup_fail('no BODYGUARD order/contract visible after contract-bodyguard (no has_contract=1 in bg_set.txt, no BODYGUARD in state_pre.txt / bg_pre.txt)'
                            + (f'; harness answered: {errs}' if errs else '') + ' (needs: recipe; try RW_BG_ARGS)')
    if not need(v, ev, 'bg_post.txt', 'state_post.txt', 'chase_ctrl.txt', 'chase_pre.txt', 'chase_post.txt', 'state_after_chase.txt'):
        return
    # 27A-FIX negative control: the SAME chase before the hire (no contract). If that NPC approaches Shay anyway, 'closes the distance' proves nothing.
    c0, c1 = chase(ev, 'chase_ctrl.txt')
    if c0 is None or c1 is None or c0 < 60 or c1 < 0.8 * c0:
        return v.setup_fail(f'NPC approaches Shay without a contract (control chase {c0} -> {c1}; needs end >= 0.8 x start and start >= 60) - the bodyguard chase cannot discriminate (needs: recipe)')
    a0, a1 = chase(ev, 'chase_pre.txt')
    v.ck('pre_load_bodyguard_follows', a0 is not None and a1 is not None and a1 <= BG_NEAR, f'{a0} -> {a1} (limit {BG_NEAR:g}; control {c0} -> {c1})')
    b0, b1 = chase(ev, 'chase_post.txt')
    closes = b1 is not None and b0 is not None and b1 <= BG_NEAR and b1 < b0
    post_raw = (rd(ev, 'state_post.txt') or '') + (rd(ev, 'bg_post.txt') or '')
    present, how = _bg_has(post_raw), 'present'
    if not present and _bg_status_err(rd(ev, 'bg_post.txt') or '') and not re.search(r'has_contract=0', post_raw):
        present = closes
        how = 'status query unavailable (harness ERROR): proved by the post-load bodyguard chase instead' if closes else 'status query unavailable (harness ERROR) and the NPC did not close the distance'
    v.ck('order_present_after_load', present, how if (present or how != 'present') else 'absent: the engine/STOBE kept no record')
    v.ck('post_load_precondition_Shay_away', b0 is not None and b0 >= 60, f'dist after teleport={b0}')
    v.ck('post_load_bodyguard_closes_distance', closes, f'{b0} -> {b1}')
    v.note = 'R~ bg_set ' + ' '.join((rd(ev, 'bg_set.txt') or '').split())[:120] + ' | bg_pre ' + ' '.join((rd(ev, 'bg_pre.txt') or '').split())[:100] + ' | bg_post ' + ' '.join((rd(ev, 'bg_post.txt') or '').split())[:100]


# ---------------------------------------------------------------- 08-e
def newest_by_topic(rows):
    d = {}
    for _, _, js in rows:
        if js.get('topic_id'):
            d[js['topic_id']] = js
    return d


def c_08e(v, ev):
    if not need(v, ev, 'fu_pre.txt'):
        return
    pre = [js for js in newest_by_topic(jrows(ev, 'fu_pre.txt')).values() if js.get('kind') == 'personal_plan' and js.get('status') == 'open']
    if not pre:
        return v.setup_fail('no open personal_plan social_followup after the topic line (s1): nothing to resume (needs: recipe; the Hub deflects the Hub-trip wording, use RW_FU_SAY)')
    if not need(v, ev, 'fu_post.txt', 'fu_final.txt', 'claim.txt', 'bored_chance.txt'):
        return
    tid = pre[-1]['topic_id']
    post = newest_by_topic(jrows(ev, 'fu_post.txt')).get(tid)
    v.ck('topic_survives_load', bool(post) and post.get('status') in ('open', 'snoozed'), (post or {}).get('status', 'row missing'))
    if not post or post.get('status') not in ('open', 'snoozed'):
        return
    claims = [js for _, _, js in jrows(ev, 'claim.txt') if re.fullmatch(r'followup:%s:\d+' % re.escape(tid), str(js.get('event_id', '')))]
    chance = (rd(ev, 'bored_chance.txt') or '').strip()
    if not claims:
        chunks = (rd(ev, 'chunks.txt') or '?').strip()
        try:
            ticks = int((rd(ev, 'cind_ticks.txt') or '').strip() or '-1')
        except ValueError:
            ticks = -1
        if ticks == 0:
            return v.setup_fail(f'topic still open after the reload but no bored tick claimed it in {chunks} advance chunks: the lane server log shows NO tick with the NPC as speaker after the load '
                                f'(speaker lottery in a crowd; BORED_EVENT_CHANCE={chance} is not the cause; needs: recipe, quieter scene / more chunks, see cind_ticks_log.txt)')
        if ticks > 0:
            return v.setup_fail(f'topic still open after the reload but no bored tick claimed it in {chunks} advance chunks although {ticks} tick(s) had the NPC as speaker (server-side claim gate: social attention / situated_remark cooldown; '
                                f'BORED_EVENT_CHANCE={chance} is not the cause; needs: server-fix, Shay decides, see cind_ticks_log.txt)')
        return v.setup_fail(f'topic still open after the reload but no bored tick claimed it in {chunks} advance chunks (NPC-speaker ticks not counted; BORED_EVENT_CHANCE={chance} is not the usual cause; needs: recipe, see 08-b)')
    n1 = [c for c in claims if str(c.get('event_id')).endswith(':1')]
    v.ck('claimed_once_after_reload', len(n1) == 1, f'claims={[c.get("event_id") for c in claims]}')
    v.ck('no_second_claim_same_day', not [c for c in claims if str(c.get('event_id')).endswith(':2')], len(claims))
    fin = newest_by_topic(jrows(ev, 'fu_final.txt')).get(tid) or {}
    v.ck('ask_count_1_after_claim', str(fin.get('ask_count')) == '1', fin.get('ask_count'))
    v.note = f'R~ BORED_EVENT_CHANCE={chance}; claim rowid(s) {[r[0] for r in jrows(ev, "claim.txt")]}'


# ---------------------------------------------------------------- 20-d
def c_20d(v, ev):
    orig = rc.accepted_row(ev)
    if not orig:
        return v.setup_fail('no ACCEPTED trip before the change request (needs: recipe, see 20-a / 23-a trip setup)')
    if not rc.owned_travel_lines(ev, 's2', 's2b'):
        return v.setup_fail('no pre-load OWNED_TRAVEL accepted=1 (the native trip never started)')
    if not need(v, ev, 'alt_pre.txt'):
        return
    aid = orig.get('agreement_id', '')
    alt_pre = rd(ev, 'alt_pre.txt') or ''
    if 'pending_change' not in alt_pre:
        return v.setup_fail('the NPC never recorded a pending plan change for the change request (no pending_change in travel_alternatives; needs: recipe, 20-a first leg)')
    if not need(v, ev, 'alt_post.txt', 'alt_after_yes.txt', 's4/ev_full.txt', 's4/reply.txt', 'alt.txt', 'agr_final.txt'):
        return
    v.ck('pending_change_names_old_agreement', aid != '' and aid in alt_pre, aid)
    v.ck('pending_change_survives_load', 'pending_change' in (rd(ev, 'alt_post.txt') or ''), 'present' if 'pending_change' in (rd(ev, 'alt_post.txt') or '') else 'lost')
    alt = (rd(ev, 'alt.txt') or '').strip()
    core = re.sub(r'^the\s+', '', alt, flags=re.I).lower()
    s4 = full_rows(ev, 's4', {'travel_agreement'})
    done = [r for r in s4 if r[2].get('agreement_id') == aid and r[2].get('status') in ('ENDED', 'CANCELLED')] \
        or [r for r in s4 if core and core in str(r[2].get('destination', '')).lower() and r[2].get('status') in ('PROPOSED', 'ACCEPTED')]
    v.ck('bare_yes_after_reload_ends_old_or_replaces', bool(done), 'rows=' + ','.join(f"{r[0]}:{r[2].get('status')}" for r in s4)[:140])
    first = ((rd(ev, 'alt_after_yes.txt') or '').splitlines() or [''])[0]
    v.ck('pending_change_cleared_after_confirm', 'pending_change' not in first, 'newest travel_alternatives row')
    v.note = f'R~ s4 {first_reply(ev, "s4")[:140]!r}; alt={alt}'


CHECKS = {'26-d': c_job, '26-dx': c_job, '26-f': c_job, '26-e': c_26e, '24-c': c_24c, '23-e': c_23e, '27-a': c_27a, '08-e': c_08e, '20-d': c_20d}


def main(argv):
    if len(argv) < 3 or rc.norm(argv[1]) not in CHECKS:
        print(f'usage: reloadcheck_a.py <ROW> <evidence-dir>   rows: {" ".join(sorted(CHECKS))}', file=sys.stderr)
        return 2
    v = V(argv[1])
    CHECKS[rc.norm(argv[1])](v, argv[2])
    if v.note:
        v.good.append(v.note)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
