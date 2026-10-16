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


def c_24b(v, ev):
    if not need(v, ev, 's1/ev_full.txt'):
        return
    rows = full_rows(ev, 's1', {'region_plan'})
    v.ck('region_plan_row', bool(rows), f'n={len(rows)}')
    st = {m for _, _, _, raw in rows for m in re.findall(r'awaiting_route|route_ready|cannot_route_yet|blocked_by_existing_trip', raw)}
    v.ck('stage_valid', bool(st & {'awaiting_route', 'route_ready', 'cannot_route_yet'}), ','.join(sorted(st)) or 'none')
    if 'blocked_by_existing_trip' in st:
        v.ck('not_blocked_by_trip', False, 'active trip blocks the region plan: preflight left a trip?')
    v.note = f'R~ reply: {first_reply(ev, "s1")[:140]!r}'


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


def c_19a(v, ev):
    if not need(v, ev, 's2/ev_full.txt'):
        return
    rows = [r for r in full_rows(ev, 's2', {'travel_agreement'}) if r[2].get('status') == 'ACCEPTED']
    v.ck('agreement_ACCEPTED', bool(rows), f'n={len(rows)}')
    if rows:
        js = rows[-1][2]; raw = rows[-1][3]
        for k in ('plan_hash', 'expires_gamets', 'accepted_by', 'leader'):
            v.ck(k, bool(js.get(k)) or bool(re.search(r'"%s": ?"?[^,"\]\s]' % k, raw)), str(js.get(k))[:40])
    if not v.bad:
        v.gated('reload leg (save/reload keeps agreement_id, "Where were we going?" recalls destination) is NOT automated: accept leg PASSED, run the reload leg by hand')


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


CHECKS = {'12-a': c_12a, '12-b': c_12b, '12-d': c_12d, '08-a': c_08a, '24-b': c_24b, '14-a': c_14a, '19-a': c_19a, '23-b': c_23b,
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
