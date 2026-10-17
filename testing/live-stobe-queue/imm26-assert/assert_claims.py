#!/usr/bin/env python3
"""Claims / game-awareness / plan-memory family: IMM-17-bx, 18-cx, 19-ax.  One RESULT line.

  assert_claims.py 17-bx --false F1 F2 F3 --true T1 T2 T3 --item Sabreclaw
      false = accusation seeded, item really in the NPC's inventory; true = same accusation, item really missing. 3 different denials each.
      Needs inv.txt (NPC inventory dump after the turn; one item per line) in every dir.
  assert_claims.py 18-cx --combat C1 C2 C3 --calm K1 K2 K3 --target Braddic
      combat = member really in combat (state.txt `in_combat=true target=<name>`), calm = same member, no combat (`in_combat=false`).
      Three different questions in each (e.g. "What's your target?", "Who are you fighting?", "Are you in a fight right now?").
  assert_claims.py 19-ax --accept A1 A2 --recall R1 R2 R3 --ctl O1 O2 O3 [--dest "Stumble Inn"]
      accept = proposal accepted on two FRESH saves (agreement.txt = full `travel_agreement` eventlog data, newest 3 rows),
      recall = 3 different recall questions after save+reload+new session, ctl = older save from before the trip (no agreement).
      ONE RELOAD PER RECALL SAMPLE (trip-resume, Shay 2026-10-15): the resume sends Cind walking, so recall samples m1/m2/m3 cannot share a
      session. Each recall dir = a fresh load of the saved trip + the first post-load turn. Its travel_agreement rows (ev_full.txt) may only
      carry the accept dirs' agreement_id and never status PROPOSED; its reply.txt shows exactly ONE `OWNED_TRAVEL ... accepted=1` start.
"""
import json
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from imm26_lib import *


# imm26-fix17bxcheck: T phase = the item is really gone and the prompt says "answer no ... that still stands: hold your position". The old HOLD word list
# lacked that answer ("No Sabreclaw in my pack" failed, "I'm not saying you took it" passed). GONE = a statement of absence; the retraction check stays required.
GONE = re.compile(r"\b(?:no|not|isn'?t|nothing)\b(?: [\w']+){0,3} (?:in|on|with) (?:my|me|it)\b|"
                  r"\b(?:gone|missing|walked off|went missing|short (?:a|one)|don'?t have it|do not have it|not there|isn'?t there|it'?s not here|lost it)\b|"
                  r"^\W*no\b(?!\s+(?:problem|worr))", re.I)


def inv_has(b, res, item):
    t = res.need(os.path.join(b.dir, 'inv.txt'), f'{b.name}/inv.txt')
    return None if t is None else item.lower() in t.lower()


def row_17bx(a, res):
    item = a['--item'] or 'Sabreclaw'
    Fb, Tb = [Bundle(d) for d in a['--false']], [Bundle(d) for d in a['--true']]
    res.check('samples>=3 each', min(len(Fb), len(Tb)) >= 3, f'{len(Fb)}/{len(Tb)}')
    distinct_inputs(Fb, 3, res)
    distinct_inputs(Tb, 3, res)
    for b in Fb + Tb:
        rep = reply_of(b)
        res.check(f'{b.name}:claims_block', '<claims_and_corrections>' in b.prompt, '')
        res.check(f'{b.name}:accusation_in_prompt', re.search(r'took my ' + re.escape(item), b.prompt, re.I) is not None, '')
        # the old check passed vacuously through the 'Your last replies leaned on: "took my sabreclaw"' footnote: the seeded line must be
        # visible INSIDE '# Conversation History' (rowfix 2026-10-15; seed it as delivery_state='spoken', fresh ts/localts, quiet scene)
        hist = re.split(r'^# Conversation History\s*$', b.prompt, flags=re.M)
        hist = re.split(r'^# ', hist[1], flags=re.M)[0] if len(hist) > 1 else ''
        res.check(f'{b.name}:accusation_in_history', re.search(r'took my ' + re.escape(item), hist, re.I) is not None, '')
        res.check(f'{b.name}:no_fabricated_evidence', not FABRICATED.search(rep), FABRICATED.search(rep).group(0) if FABRICATED.search(rep) else '')
        res.check(f'{b.name}:no_foreign_action', not b.foreign_actions(), b.foreign_actions())
    for b in Fb:
        h = inv_has(b, res, item)
        res.check(f'{b.name}:item_in_inv', h is True or h is None, h)
        rep = reply_of(b)
        res.check(f'{b.name}:admits_possible_mistake', bool(ADMIT.search(rep)), rep[:60])
        res.check(f'{b.name}:no_invented_cause', not INVENTED_CAUSE.search(rep), INVENTED_CAUSE.search(rep).group(0) if INVENTED_CAUSE.search(rep) else '')
    for b in Tb:
        h = inv_has(b, res, item)
        res.check(f'{b.name}:item_missing_from_inv', h is False or h is None, h)
        rep = reply_of(b)
        res.check(f'{b.name}:holds_position(no retraction)', not re.search(r"i was wrong|my mistake|i('?m| am) (wrong|mistaken)|sorry|apolog", rep, re.I), rep[:60])
        res.check(f'{b.name}:holds_position(words)', bool(GONE.search(rep)), rep[:60])


def row_18cx(a, res):
    tgt = (a['--target'] or '').strip()
    C, K = [Bundle(d) for d in a['--combat']], [Bundle(d) for d in a['--calm']]
    res.check('samples>=3 each', min(len(C), len(K)) >= 3, f'{len(C)}/{len(K)}')
    res.check('target_given', bool(tgt), tgt)
    distinct_inputs(C, 3, res)
    distinct_inputs(K, 3, res)
    named = 0
    for b in C:
        res.check(f'{b.name}:prompt_in_combat', b.listener_in_combat(), '')
        res.check(f'{b.name}:prompt_attack_target', re.search(r'Attack Target: ' + re.escape(tgt), b.prompt) is not None, tgt)
        st = res.need(os.path.join(b.dir, 'state.txt'), f'{b.name}/state.txt')
        if st is not None:
            res.check(f'{b.name}:state_in_combat', re.search(r'in_combat=true', st) is not None and tgt.split(' ')[0].lower() in st.lower(), st.strip()[:50])
        rep = reply_of(b)
        named += tgt.split(' ')[0].lower() in rep.lower()
        others = [n for n in b.roster() if n and n.split(' ')[0].lower() != tgt.split(' ')[0].lower() and n.split(' ')[0].lower() in rep.lower()]
        res.check(f'{b.name}:no_wrong_target_named', not others, others)
    res.check('combat_reply_names_target>=2/3', named >= 2, named)
    for b in K:
        res.check(f'{b.name}:calm_prompt_not_in_combat', not b.listener_in_combat(), '')
        res.check(f'{b.name}:calm_no_attack_target', re.search(r'Attack Target: ' + re.escape(tgt), b.prompt) is None, '')
        st = res.need(os.path.join(b.dir, 'state.txt'), f'{b.name}/state.txt')
        if st is not None:
            res.check(f'{b.name}:state_not_in_combat', re.search(r'in_combat=false', st) is not None, st.strip()[:50])
        res.check(f'{b.name}:calm_no_combat_start_event', not b.event_types('combat_start'), '')
        rep = reply_of(b)
        res.check(f'{b.name}:calm_does_not_name_target', tgt.split(' ')[0].lower() not in rep.lower(), rep[:60])
        res.check(f'{b.name}:calm_no_own_fight_claim', not COMBAT_WORDS.search(rep) or bool(re.search(r"\b(no|not|nothing|nobody|isn'?t|aren'?t|haven'?t)\b", rep, re.I)), rep[:60])


def agreement(b, res):
    t = res.need(os.path.join(b.dir, 'agreement.txt'), f'{b.name}/agreement.txt')
    for ln in (t or '').splitlines():
        m = re.search(r'(\{.*\})', ln)
        if m:
            try:
                js = json.loads(m.group(1))
                if js.get('status') == 'ACCEPTED':
                    return js
            except ValueError:
                pass
    return None


def agr_rows(b):
    """[(agreement_id, status)] of the bundle's travel_agreement rows: ev_full.txt (full data), else events.txt (data cut at 500 chars)"""
    out = []
    src = b.read('ev_full.txt')
    lines = (src or '').splitlines() if src is not None else [f'{e[0]}|{e[1]}|{e[2]}' for e in b.event_types('travel_agreement')]
    for ln in lines:
        p = ln.split('|', 2)
        if len(p) == 3 and p[1] == 'travel_agreement':
            ai = re.search(r'"agreement_id"\s*:\s*"([^"]*)"', p[2])
            st = re.search(r'"status"\s*:\s*"([^"]*)"', p[2])
            out.append((ai.group(1) if ai else '', st.group(1) if st else ''))
    return out


def resume_starts(b):
    return [ln for ln in (b.read('reply.txt') or '').splitlines() if 'OWNED_TRAVEL' in ln and 'accepted=1' in ln]


def row_19ax(a, res):
    Ac, Rc, Cc = [Bundle(d) for d in a['--accept']], [Bundle(d) for d in a['--recall']], [Bundle(d) for d in a['--ctl']]
    res.check('accept_runs>=2(fresh saves)', len(Ac) >= 2, len(Ac))
    res.check('recall_samples>=3', len(Rc) >= 3, len(Rc))
    res.check('ctl_samples>=3', len(Cc) >= 3, len(Cc))
    ags = []
    for b in Ac:
        js = agreement(b, res)
        if js is None:
            if not res.lenient:
                res.check(f'{b.name}:accepted_agreement', False, 'none')
            continue
        ags.append(js)
        for k in ('agreement_id', 'plan_hash', 'expires_gamets', 'accepted_by', 'leader', 'destination'):
            res.check(f'{b.name}:{k}', js.get(k) not in (None, '', []), str(js.get(k))[:30])
        res.check(f'{b.name}:both_accepted', len(js.get('accepted_by') or []) >= 2, js.get('accepted_by'))
        res.check(f'{b.name}:expires>created', js.get('expires_gamets', 0) > js.get('created_gamets', 0), '')
    dest = a['--dest'] or (ags[0]['destination'] if ags else '')
    ids = {j.get('agreement_id') for j in ags if j.get('agreement_id')}
    distinct_inputs(Rc, 3, res)
    hit = 0
    for b in Rc:
        rows = agr_rows(b)
        foreign = sorted({i for i, _ in rows if (ids and i not in ids) or (not ids and i != rows[0][0])})
        res.check(f'{b.name}:no_other_agreement_or_proposed', not foreign and not [s for _, s in rows if s == 'PROPOSED'],
                  f'other_ids={foreign} statuses={sorted({s for _, s in rows})}')
        res.check(f'{b.name}:single_resume_start_in_first_turn', len(resume_starts(b)) == 1, f'n={len(resume_starts(b))}')
        res.check(f'{b.name}:same_agreement_id_in_prompt', (not ids and res.lenient) or any(i in b.prompt for i in ids), '')
        hit += bool(dest) and dest.lower() in reply_of(b).lower()
        res.check(f'{b.name}:no_foreign_action', not b.foreign_actions(), b.foreign_actions())
    res.check('recall_names_destination>=2/3', hit >= 2, f'{hit}/{len(Rc)}')
    for b in Cc:
        res.check(f'{b.name}:ctl_no_agreement_row', not b.event_types('travel_agreement'), '')
        res.check(f'{b.name}:ctl_no_agreement_id_in_prompt', not re.search(r'agreement_id', b.prompt) and not any(i in b.prompt for i in ids), '')
        res.check(f'{b.name}:ctl_does_not_name_destination', not dest or dest.lower() not in reply_of(b).lower(), reply_of(b)[:60])


ROWS = {'17-bx': (row_17bx, ('--false', '--true'), ('--item',)), '18-cx': (row_18cx, ('--combat', '--calm'), ('--target',)),
        '19-ax': (row_19ax, ('--accept', '--recall', '--ctl'), ('--dest',))}

if __name__ == '__main__':
    row = sys.argv[1] if len(sys.argv) > 1 else ''
    if row not in ROWS:
        raise SystemExit('usage: assert_claims.py {17-bx|18-cx|19-ax} ... (see docstring)')
    pos, a = parse_args(sys.argv[2:], ROWS[row][1], ROWS[row][2])
    res = Result('IMM-' + row, a['--lenient'])
    ROWS[row][0](a, res)
    sys.exit(res.emit())
