#!/usr/bin/env python3
"""rowcheck.py <ROW> <evidence-dir>   row assertions over a go-row.sh evidence dir; prints exactly ONE line
`RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence>` (exit 0 PASS, 1 FAIL, 2 usage/SETUP-FAIL, 3 GATED).
Evidence layout (rowlib.sh): s<N>/{events,ev_full,prompt,reply,server,effects,meta,utterance}.txt, inv_<tag>.txt, haff-*.txt, follow*.txt, time.txt.
Strict: a missing required file is FAIL (never PASS). R~ (reply-wording) points are listed as evidence for a human; the mechanical
parts (rows written, prompt blocks, inventory changes, states) decide the verdict, same philosophy as assert_*.py.
"""
import difflib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
from imm26_lib import Bundle  # noqa: E402


class V:
    def __init__(self, row):
        self.row, self.bad, self.good, self.kind, self.note = row, [], [], None, ''

    def ck(self, name, cond, detail=''):
        (self.good if cond else self.bad).append(name + (f'={detail}' if detail != '' else ''))
        return bool(cond)

    def setup_fail(self, why):
        self.kind = 'SETUP-FAIL'; self.bad.append(why)

    def gated(self, why):
        self.kind = 'GATED'; self.bad.append(why)

    def emit(self, evdir):
        kind = self.kind or ('PASS' if not self.bad else 'FAIL')
        ev = '; '.join(self.bad + self.good)
        print(f'RESULT {self.row} {kind} {ev[:1500]} [evidence={evdir}]')
        return {'PASS': 0, 'FAIL': 1, 'SETUP-FAIL': 2, 'GATED': 3}[kind]


def rd(ev, *p):
    f = os.path.join(ev, *p)
    return open(f, encoding='utf-8', errors='replace').read() if os.path.isfile(f) else None


def full_rows(ev, step, types):
    """[(rowid, type, dict|{}, raw)] of ev_full.txt rows of the given types"""
    out = []
    for ln in (rd(ev, step, 'ev_full.txt') or '').splitlines():
        p = ln.split('|', 2)
        if len(p) == 3 and p[1] in types:
            m = re.search(r'\{.*\}', p[2])
            js = {}
            if m:
                try:
                    js = json.loads(m.group(0))
                except ValueError:
                    pass
            out.append((p[0], p[1], js, p[2]))
    return out


def first_reply(ev, step):
    t = ''.join((rd(ev, step, 'reply.txt') or '').splitlines(True))
    m = re.findall(r'ACTION_EXEC: SAY \[.+?\]: (.*?) \(NPC\)', t)
    return m[0].strip() if m else ''


def inv(ev, tag):
    """{'SHAY': {item: count}, 'CIND ...': {...}} from inv_<tag>.txt"""
    res = {}
    for ln in (rd(ev, f'inv_{tag}.txt') or '').splitlines():
        if not ln.strip():
            continue
        who = ln.split(' ', 1)[0].upper()
        res[who] = {}
        for n, c in re.findall(r'"name":"(.*?)","count":(\d+)', ln):
            res[who][n] = res[who].get(n, 0) + int(c)
    return res


def gained(before, after, who):
    b, a = before.get(who, {}), after.get(who, {})
    return {k: a[k] - b.get(k, 0) for k in a if a[k] > b.get(k, 0)}


def need(v, ev, *names):
    ok = True
    for n in names:
        if not os.path.isfile(os.path.join(ev, n)):
            v.ck(f'file:{n}', False, 'missing'); ok = False
    return ok


# ---------------------------------------------------------------- rows
def c_12a(v, ev):
    if not need(v, ev, 's1/prompt.txt', 'inv_before.txt', 'inv_after.txt'):
        return
    p = rd(ev, 's1', 'prompt.txt')
    if not re.search(r'broken promise', p, re.I):
        return v.setup_fail('no recorded broken promise for this pair in the PROMPT (breach a deal as in 13-a first)')
    v.ck('prompt_experience_block', bool(re.search(r'recorded_experiences_with_addressee|Recorded experience', p)))
    v.ck('prompt_reliability_entry', bool(re.search(r'broken promise|kept promise', p, re.I)))
    b, a = inv(ev, 'before'), inv(ev, 'after')
    v.ck('inv_no_transfer', b == a and bool(b), 'unchanged' if b == a else f'changed {gained(b, a, "SHAY")}')
    r = first_reply(ev, 's1'); v.ck('npc_replied', bool(r))
    v.note = f'R~ reply: {r[:160]!r}'


def c_12b(v, ev):
    if not need(v, ev, 's1/prompt.txt', 's2/prompt.txt'):
        return
    dom = ['promises', 'property', 'safety', 'fighting beside', 'secrets']
    p = rd(ev, 's1', 'prompt.txt').lower()
    found = [d for d in dom if d in p]
    v.ck('prompt_domains', len(found) >= 3 and bool(re.search(r'recorded[_ ]experience', p)), ','.join(found))
    r1, r2 = first_reply(ev, 's1'), first_reply(ev, 's2')
    v.ck('two_replies', bool(r1 and r2))
    sim = difflib.SequenceMatcher(None, r1.lower(), r2.lower()).ratio() if r1 and r2 else 1
    v.ck('replies_differ', sim < 0.6, f'sim={sim:.2f}')
    v.note = f'R~ secret: {r1[:90]!r} | raid: {r2[:90]!r}'


def c_12d(v, ev):
    if not need(v, ev, 's1/reply.txt', 's2/reply.txt', 'inv_before1.txt', 'inv_after1.txt', 'inv_before2.txt', 'inv_after2.txt'):
        return
    b1, a1, b2, a2 = inv(ev, 'before1'), inv(ev, 'after1'), inv(ev, 'before2'), inv(ev, 'after2')
    v.ck('aff40_refused_no_transfer', b1 == a1 and bool(b1), 'unchanged' if b1 == a1 else f'gained {gained(b1, a1, "SHAY")}')
    gate = ((rd(ev, 's1', 'server.txt') or '') + (rd(ev, 's1', 'reply.txt') or ''))
    v.ck('aff40_gate_reason_in_log', bool(re.search(r'gate|threshold|relationship_trading|min_affinity', gate, re.I)),
         'found' if re.search(r'gate|threshold|relationship_trading', gate, re.I) else 'none (reason only in model reply?)')
    g = gained(b2, a2, 'SHAY')
    v.ck('aff75_transferred', bool(g), f'shay_gained={g}' if g else 'no item moved to Shay')
    v.note = f'R~ aff40: {first_reply(ev, "s1")[:100]!r} aff75: {first_reply(ev, "s2")[:100]!r}'


def c_08a(v, ev):
    if not need(v, ev, 's1/ev_full.txt'):
        return
    rows = full_rows(ev, 's1', {'social_followup'})
    v.ck('followup_row_created', bool(rows), f'n={len(rows)}')
    if rows:
        js = rows[-1][2]; raw = rows[-1][3]
        v.ck('status_open', js.get('status') == 'open', js.get('status'))
        v.ck('kind_personal_plan', js.get('kind') == 'personal_plan', js.get('kind'))
        v.ck('ask_count_0', js.get('ask_count', 0) == 0, js.get('ask_count', 'absent=0'))
        v.ck('not_before_set', bool(re.search(r'"not_before[a-z_]*": ?[0-9]', raw)))
        v.ck('expires_set', bool(re.search(r'"expires[a-z_]*": ?[0-9]', raw)))
    for i in (2, 3, 4):
        if os.path.isdir(os.path.join(ev, f's{i}')):
            n = len(full_rows(ev, f's{i}', {'social_followup'}))
            v.ck(f'neg{i - 1}_no_followup', n == 0, f'n={n}: {(rd(ev, f"s{i}", "utterance.txt") or "").strip()[:50]}')


BAD_24B_REPLY = re.compile(r"don'?t have a current offer|do not have a current offer|confirmed reachable point|do not have a confirmed|cannot route", re.I)
_DEST_KEYS = ('endpoint_candidate_id', 'native_candidate_id', 'candidate_id', 'endpoint_label', 'destination_label', 'destination_name',
              'endpoint_town', 'town', 'town_name', 'place')


def _point_ok(p):
    try:
        return isinstance(p, dict) and all(float(p[k]) == float(p[k]) for k in ('x', 'y', 'z'))
    except (KeyError, TypeError, ValueError):
        return False


def grounded_dest(js):
    """(label|None, ok): a grounded destination = native candidate id or a named town (label) or a real x/y/z point, in the row or its regional_goal"""
    for src in (js, js.get('regional_goal') if isinstance(js.get('regional_goal'), dict) else {}):
        for k in _DEST_KEYS:
            if isinstance(src.get(k), str) and src[k].strip():
                return src[k].strip(), True
        for k in ('endpoint_point', 'endpoint', 'destination_point', 'point'):
            if _point_ok(src.get(k)):
                return src.get('endpoint_label') or src.get('destination_label') or k, True
    return None, False


def c_24b(v, ev):
    """24-b (amended 2026-10-16): the NPC must OFFER A FIRST LEG with a grounded destination (native candidate id if in range, else the nearest
    known town in the region): a route_ready region_plan row or a PROPOSED travel_agreement with regional_goal{Vain}; then the s2 'Yes' must start
    a real trip (ACCEPTED agreement + OWNED_TRAVEL accepted=1). awaiting_route / cannot_route_yet / blocked_by_existing_trip alone, or the
    'no current offer' fallback reply, can never pass."""
    if not need(v, ev, 's1/ev_full.txt', 's1/reply.txt', 's2/ev_full.txt', 's2/reply.txt'):
        return
    rows = [r for st in ('s1', 's2') for r in full_rows(ev, st, {'region_plan'})]
    v.ck('region_plan_row', bool(rows), f'n={len(rows)}')
    st = {m for _, _, _, raw in rows for m in re.findall(r'awaiting_route|route_ready|cannot_route_yet|blocked_by_existing_trip', raw)}
    if 'blocked_by_existing_trip' in st:
        v.ck('not_blocked_by_trip', False, 'active trip blocks the region plan: preflight left a trip?')
    r1 = first_reply(ev, 's1')
    v.ck('reply_not_fallback', bool(r1) and not BAD_24B_REPLY.search(r1), r1[:80] if r1 else 'no NPC reply')
    ready = [js for _, _, js, raw in rows if js.get('stage') == 'route_ready' or ('route_ready' in raw and not js)]
    prop = [js for _, _, js, _ in full_rows(ev, 's1', {'travel_agreement'})
            if js.get('status') == 'PROPOSED' and isinstance(js.get('regional_goal'), dict) and js['regional_goal']
            and 'vain' in json.dumps(js['regional_goal']).lower()]
    v.ck('first_leg_offered', bool(ready or prop), f'stages={",".join(sorted(st)) or "none"} proposed_with_regional_goal={len(prop)}')
    label, ok = None, False
    for js in ready + prop:
        label, ok = grounded_dest(js)
        if ok:
            break
    v.ck('grounded_destination', ok, label or 'no candidate id / town name / x,y,z point in the route_ready row or PROPOSED agreement')
    if ok and label and label not in _DEST_KEYS and label not in ('endpoint', 'endpoint_point', 'destination_point', 'point'):
        v.ck('reply_names_destination', label.lower() in r1.lower(), label)
    acc = accepted_row(ev)
    v.ck('yes_accepted_with_regional_goal', bool(acc) and isinstance(acc.get('regional_goal'), dict) and bool(acc.get('regional_goal')),
         'no ACCEPTED travel_agreement with regional_goal after the Yes' if not acc else 'ok')
    n = len(owned_travel_lines(ev, 's2', 's3'))
    v.ck('trip_started_OWNED_TRAVEL', n >= 1, f'OWNED_TRAVEL accepted=1 lines={n}')
    v.note = f'R~ reply1: {r1[:140]!r} reply2: {first_reply(ev, "s2")[:100]!r}'


def c_14a(v, ev):
    if not need(v, ev, 's1/ev_full.txt', 's1/reply.txt'):
        return
    rows = [r for r in full_rows(ev, 's1', {'travel_agreement'})]
    prop = [r for r in rows if r[2].get('status') == 'PROPOSED']
    v.ck('agreement_PROPOSED', bool(prop), f'n={len(rows)} statuses={sorted({r[2].get("status", "?") for r in rows})}')
    v.ck('destination_point', any(r[2].get('destination_point') for r in prop), str(prop[0][2].get('destination_point') if prop else None)[:80])
    logs = (rd(ev, 's1', 'reply.txt') or '') + (rd(ev, 's1', 'server.txt') or '') + (rd(ev, 's1', 'events.txt') or '')
    v.ck('no_rejected_before_speech', 'Travel agreement rejected before speech' not in logs)
    p = rd(ev, 's1', 'prompt.txt') or ''
    v.ck('prompt_consistent_destinations', not ('NO GROUNDED DESTINATION IS AVAILABLE' in p and re.search(r'Known places you can name: \S', p)),
         'contradiction' if 'NO GROUNDED DESTINATION IS AVAILABLE' in p else 'ok')
    v.note = f'R~ alternative named? reply: {first_reply(ev, "s1")[:160]!r}'


def agr_dump(ev, name):
    """[(rowid:int, json)] of a `rowid|type|data` travel_agreement dump (rd19_dump), oldest first"""
    out = []
    for ln in (rd(ev, name) or '').splitlines():
        p = ln.split('|', 2)
        if len(p) == 3 and p[0].strip().isdigit() and p[1] == 'travel_agreement':
            m = re.search(r'\{.*\}', p[2])
            try:
                js = json.loads(m.group(0)) if m else {}
            except ValueError:
                js = {}
            out.append((int(p[0]), js))
    return out


def ex_of(js):
    return js.get('execution') if isinstance(js.get('execution'), dict) else {}


def world_of(ex):
    return ex.get('world_id') or ex.get('dispatch_world_id') or ''


def dest_xyz(js):
    p = js.get('destination_point') or {}
    try:
        return tuple(float(p[k]) for k in ('x', 'y', 'z'))
    except (KeyError, TypeError, ValueError):
        return None


def accepted_row(ev):
    """agreement json of the last ACCEPTED travel_agreement row of s2/s3 (the accept leg)"""
    rows = [r for st in ('s2', 's3') for r in full_rows(ev, st, {'travel_agreement'}) if r[2].get('status') == 'ACCEPTED']
    return rows[-1][2] if rows else None


def state_ai(ev, name):
    """(first_order, destination [x,y,z] | None) from a stobe_state dump"""
    t = rd(ev, name) or ''
    i = t.find('"ai"')
    t = t[i:] if i >= 0 else t
    fo = re.search(r'"first_order"\s*:\s*"([^"]*)"', t)
    d = re.search(r'"destination"\s*:\s*\[\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)', t)
    cg = re.search(r'"current_goal"\s*:\s*"([^"]*)"', t)
    first = fo.group(1) if fo else None
    if first == 'present' and cg:   # newer harness stobe_state: first_order is a presence flag, the order name is current_goal
        first = cg.group(1)
    return first, ([float(x) for x in d.groups()] if d else None)


def owned_travel_lines(ev, *steps):
    return [ln for st in steps for ln in (rd(ev, st, 'reply.txt') or '').splitlines() if 'OWNED_TRAVEL' in ln and 'accepted=1' in ln]


def post_rows(ev):
    """travel_agreement rows written after the load (rowid > load_rowid.txt) from agr_all.txt"""
    try:
        mark = int((rd(ev, 'load_rowid.txt') or '0').strip() or 0)
    except ValueError:
        mark = 0
    return [r for r in agr_dump(ev, 'agr_all.txt') if r[0] > mark]


def resume_chain(v, rows, aid, pre, orig):
    """interrupted_by_load -> requested (NEW request_id, generation > pre, same plan_hash/destination) -> running, all the same agreement_id"""
    phases = [ex_of(js).get('phase', '') for _, js in rows]
    v.ck('post_load_rows_present', bool(rows), f'n={len(rows)}')
    v.ck('post_load_same_agreement_id_only', bool(rows) and all(js.get('agreement_id') == aid for _, js in rows),
         sorted({js.get('agreement_id', '?') for _, js in rows}))
    bad = [js.get('status') for _, js in rows if js.get('status') in ('PROPOSED', 'FAILED', 'ENDED')]
    v.ck('post_load_no_PROPOSED_FAILED_ENDED', not bad, bad)
    ii = phases.index('interrupted_by_load') if 'interrupted_by_load' in phases else -1
    v.ck('phase_interrupted_by_load', ii >= 0, phases)
    req = [i for i, p in enumerate(phases) if p == 'requested' and i > ii] if ii >= 0 else []
    v.ck('phase_requested_after_interrupt', bool(req), phases)
    if req:
        # the session_generation / world_id of the new dispatch land in a LATER 'requested' update (the first requested row only has the new request_id)
        js = rows[req[-1]][1]
        ex = ex_of(js)
        v.ck('requested_new_request_id', bool(ex.get('request_id')) and ex.get('request_id') != pre.get('request_id'), f"{pre.get('request_id')}->{ex.get('request_id')}")
        try:
            gen_ok = int(ex.get('session_generation', 0)) > int(pre.get('session_generation', 0))
        except (TypeError, ValueError):
            gen_ok = False
        v.ck('requested_session_generation_up', gen_ok, f"{pre.get('session_generation')}->{ex.get('session_generation')}")
        v.ck('requested_world_changed', bool(world_of(ex)) and world_of(ex) != world_of(pre), f'{world_of(pre)}->{world_of(ex)}')
        v.ck('requested_same_plan_hash', bool(js.get('plan_hash')) and js.get('plan_hash') == orig.get('plan_hash'), str(js.get('plan_hash'))[:12])
        v.ck('requested_same_destination', js.get('destination') == orig.get('destination') and dest_xyz(js) is not None and dest_xyz(js) == dest_xyz(orig),
             f"{js.get('destination')} {dest_xyz(js)}")
        run = [i for i, p in enumerate(phases) if p == 'running' and i > req[0]]
        v.ck('phase_running_after_requested', bool(run), phases)
        if run:
            v.ck('running_keeps_request_id', ex_of(rows[run[0]][1]).get('request_id') == ex.get('request_id'), ex_of(rows[run[0]][1]).get('request_id'))


def c_19a(v, ev):
    """trip-resume (option B): accept leg as before, then a save/load CONTINUES the same agreement (rd_19a evidence files, see rowdefs.sh)"""
    if not need(v, ev, 's2/ev_full.txt', 's4/reply.txt', 's5/reply.txt', 'agr_pre.txt', 'agr_all.txt', 'load_rowid.txt', 'post_s5.txt'):
        return
    rows = [r for st in ('s2', 's3') for r in full_rows(ev, st, {'travel_agreement'}) if r[2].get('status') == 'ACCEPTED']   # the accept lands in s2, or in s3 ("Lead the way.")
    v.ck('agreement_ACCEPTED', bool(rows), f'n={len(rows)}')
    if not rows:
        return
    js = rows[-1][2]
    raw = rows[-1][3]
    for k in ('plan_hash', 'expires_gamets', 'accepted_by', 'leader'):
        v.ck(k, bool(js.get(k)) or bool(re.search(r'"%s": ?"?[^,"\]\s]' % k, raw)), str(js.get(k))[:40])
    orig = accepted_row(ev) or js
    aid = orig.get('agreement_id', '')
    if not owned_travel_lines(ev, 's2', 's3'):
        return v.setup_fail('no pre-load OWNED_TRAVEL accepted=1 in s2/s3 (the native trip never started; nothing to resume)')
    pre_rows = [j for _, j in agr_dump(ev, 'agr_pre.txt') if j.get('agreement_id') == aid]
    pre = ex_of(pre_rows[-1]) if pre_rows else {}
    v.ck('pre_load_execution_known', bool(pre.get('request_id')), f"request_id={pre.get('request_id')} world={world_of(pre)} gen={pre.get('session_generation')}")
    resume_chain(v, post_rows(ev), aid, pre, orig)
    ot = owned_travel_lines(ev, 's4', 's5')
    v.ck('exactly_one_post_load_OWNED_TRAVEL_accepted', len(ot) == 1, f'n={len(ot)}')
    v.ck('post_load_start_reason', len(ot) == 1 and 'reason=native_owned_order_assigned' in ot[0], (ot[0][:120] if ot else 'none'))
    xyz = dest_xyz(orig)
    fo, dst = state_ai(ev, 'post_s5.txt')
    v.ck('post_s5_first_order_MOVE_CUS_ORDERED', fo == 'MOVE_CUS_ORDERED', fo)
    v.ck('post_s5_destination_within_0.5', bool(xyz and dst) and max(abs(a - b) for a, b in zip(xyz, dst)) <= 0.5, f'stored={xyz} state={dst}')
    fo4, _ = state_ai(ev, 'post_s4.txt')
    r4 = first_reply(ev, 's4')
    dn = (orig.get('destination') or '').lower()
    v.note = f"R~ s4 names {orig.get('destination')!r}: {'yes' if dn and dn in r4.lower() else 'no'}; reply {r4[:140]!r} (post_s4 first_order={fo4})"
    if os.path.isdir(os.path.join(ev, 's6')):                      # NC: older save from before the trip
        if need(v, ev, 's6/ev_full.txt', 's6/prompt.txt', 's6/reply.txt'):
            p6 = rd(ev, 's6', 'prompt.txt') or ''
            v.ck('NC_no_travel_agreement_row', not full_rows(ev, 's6', {'travel_agreement'}), len(full_rows(ev, 's6', {'travel_agreement'})))
            v.ck('NC_no_agreement_id_in_prompt', 'agreement_id' not in p6 and not (aid and aid in p6))
            v.ck('NC_no_OWNED_TRAVEL', not owned_travel_lines(ev, 's6'), len(owned_travel_lines(ev, 's6')))
    else:
        v.note += ' | NC leg not run (ROW_19A_NC=0)'


def c_19anc2(v, ev):
    """NC2: NPC 120 u away after the load -> the trip is NOT resumed (no requested/running row, no OWNED_TRAVEL), no new agreement id"""
    if not need(v, ev, 's2/ev_full.txt', 's4/reply.txt', 'agr_pre.txt', 'agr_all.txt', 'load_rowid.txt', 'post_s4.txt'):
        return
    orig = accepted_row(ev)
    v.ck('agreement_ACCEPTED', bool(orig), 'none' if not orig else orig.get('agreement_id'))
    if not orig:
        return
    if not owned_travel_lines(ev, 's2', 's3'):
        return v.setup_fail('no pre-load OWNED_TRAVEL accepted=1 in s2/s3 (the native trip never started)')
    aid = orig.get('agreement_id', '')
    rows = post_rows(ev)
    phases = [ex_of(js).get('phase', '') for _, js in rows]
    v.ck('no_resume_rows(requested/running)', not [p for p in phases if p in ('requested', 'running')], phases)
    v.ck('no_new_agreement_id', all(js.get('agreement_id') == aid for _, js in rows), sorted({js.get('agreement_id', '?') for _, js in rows}))
    v.ck('no_PROPOSED_FAILED_ENDED', not [js.get('status') for _, js in rows if js.get('status') in ('PROPOSED', 'FAILED', 'ENDED')],
         [js.get('status') for _, js in rows])
    v.ck('no_OWNED_TRAVEL_accepted', not owned_travel_lines(ev, 's4'), len(owned_travel_lines(ev, 's4')))
    v.note = f"phases after load={phases or 'no new rows (no transition while the NPC is out of range)'}; R~ reply {first_reply(ev, 's4')[:120]!r}"


def c_19d(v, ev):
    """19-d: resumed trip, NPC teleported to the destination gate (23-a recipe) -> COMPLETED + owned_work_released true"""
    if not need(v, ev, 's2/ev_full.txt', 's4/reply.txt', 's5/reply.txt', 'agr_pre.txt', 'agr_all.txt', 'load_rowid.txt', 'agr_final.txt'):
        return
    orig = accepted_row(ev)
    v.ck('agreement_ACCEPTED', bool(orig), 'none' if not orig else orig.get('agreement_id'))
    if not orig:
        return
    if not owned_travel_lines(ev, 's2', 's3'):
        return v.setup_fail('no pre-load OWNED_TRAVEL accepted=1 in s2/s3 (the native trip never started)')
    aid = orig.get('agreement_id', '')
    phases = [ex_of(js).get('phase', '') for _, js in post_rows(ev) if js.get('agreement_id') == aid]
    v.ck('trip_was_resumed_first', 'interrupted_by_load' in phases and ('requested' in phases or 'running' in phases), phases)
    fin = None
    for ln in (rd(ev, 'agr_final.txt') or '').splitlines():       # newest first: rowid|status|phase|reason|owned_work_released|agreement_id|destination
        p = ln.strip().split('|')
        if len(p) >= 7 and p[0].isdigit() and p[5] == aid:
            fin = p
            break
    v.ck('agreement_COMPLETED', bool(fin) and fin[1] == 'COMPLETED', fin[1] if fin else 'row not found')
    v.ck('owned_work_released_true', bool(fin) and fin[4].lower() == 'true', fin[4] if fin else '?')
    v.note = f"R~ ack: {first_reply(ev, 's5')[:140]!r}"


def c_23b(v, ev):
    # the native follow is a controller, not a Kenshi order: evidence is the DLL's stobe.log FOLLOW lines (imm26-inv-23b item 8)
    if not need(v, ev, 'follow_log.txt'):
        return
    st = rd(ev, 'follow_log.txt')
    if 'FOLLOW target resolved' not in st:
        return v.setup_fail('no follow order after "Follow me." (no "FOLLOW target resolved" in the stobe.log slice): expiry untestable')
    after = rd(ev, 'follow_log_after.txt')
    if after is None:
        return v.ck('file:follow_log_after.txt', False, 'missing')
    ser = (re.search(r'#(\d+)', rd(ev, 'follow_npc.txt') or '') or [None, ''])[1]
    v.ck('follow_ticking', bool(re.search(r'FOLLOW_TICK: follower=', st + after)), 'no FOLLOW_TICK line')
    t0, t1 = rd(ev, 'time0.txt') or '', rd(ev, 'time1.txt') or ''
    n0 = re.findall(r'[0-9]+(?:\.[0-9]+)?', t0); n1 = re.findall(r'[0-9]+(?:\.[0-9]+)?', t1)
    v.ck('game_time_advanced', bool(n0 and n1) and float(n1[0]) > float(n0[0]), f'{n0[:1]}->{n1[:1]}')
    v.ck('follow_ended_by_expiry', bool(re.search(r'FOLLOW_EXPIRED: follower=' + (re.escape(ser) if ser else r'\d+'), after)), 'no FOLLOW_EXPIRED line for ' + (ser or 'any follower'))


def c_04c(v, ev):
    if not need(v, ev, 's1/prompt.txt'):
        return
    p = rd(ev, 's1', 'prompt.txt'); b = (rd(ev, 'tie_target.txt') or '').strip()
    v.ck('tie_target_known', bool(b), b[:40])
    v.ck('prompt_ties_line', 'Your ties to people just named' in p)
    if b:
        v.ck('tie_line_names_B', bool(re.search(r'Your ties to people just named[^\n]*(\n[^\n]*){0,6}' + re.escape(b.split(' [')[0].split()[0]), p)))
    v.note = f'R~ reply cites the tie? {first_reply(ev, "s1")[:160]!r}'


def c_06c(v, ev):
    if not need(v, ev, 's2/ev_full.txt', 's3/ev_full.txt'):
        return

    def addr(step):
        out = []
        for _, _, js, raw in full_rows(ev, step, {'social_preferences'}):
            e = (js.get('entries') or {}).get('personal:address')
            if e is not None:
                out.append(e)
        return out
    a2, a3 = addr('s2'), addr('s3')
    v.ck('call_me_Jax_replaced_row', any(e.get('value') == 'Jax' and e.get('status') == 'active' for e in a2), f'{[(e.get("value"), e.get("status")) for e in a2]}')
    v.ck('forget_wrote_tombstone', any(e.get('status') == 'deleted' for e in a3), f'{[(e.get("value"), e.get("status")) for e in a3]}')
    if os.path.isfile(os.path.join(ev, 's4', 'prompt.txt')):
        blk = [ln for ln in (rd(ev, 's4', 'prompt.txt') or '').splitlines() if re.search(r'preferred name|address (you|me|him|her)|call (you|me) ', ln, re.I)
               and re.search(r'\b(Boss|Jax)\b', ln)]
        v.ck('prompt_block_gone', not blk, 'present: ' + blk[0][:80] if blk else 'gone')
    v.note = f'R~ later replies must not say Boss/Jax: {first_reply(ev, "s4")[:120]!r}'


CHECKS = {'12-a': c_12a, '12-b': c_12b, '12-d': c_12d, '08-a': c_08a, '24-b': c_24b, '14-a': c_14a, '19-a': c_19a, '19-a-nc2': c_19anc2, '19-d': c_19d, '23-b': c_23b,
          '04-c': c_04c, '06-c': c_06c}


try:  # trip-family rows (13-b 20-a 20-b 23-a 23-c 23-d 24-a): rowtools/rowcheck_trip.py registers into CHECKS
    import rowcheck_trip
    rowcheck_trip.register(sys.modules[__name__], CHECKS)
except ImportError:
    pass


def norm(row):
    return re.sub(r'^IMM-', '', row)


def main(argv):
    if len(argv) < 3 or norm(argv[1]) not in CHECKS:
        print(f'usage: rowcheck.py <ROW> <evidence-dir>   rows: {" ".join(sorted(CHECKS))}', file=sys.stderr)
        return 2
    v = V(argv[1])
    CHECKS[norm(argv[1])](v, argv[2])
    if v.note:
        v.good.append(v.note)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
