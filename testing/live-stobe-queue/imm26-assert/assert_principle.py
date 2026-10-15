#!/usr/bin/env python3
"""Principle/knowledge-of-surroundings family: IMM-02-ax, 02-bx, 02-cx, 02-dx, 05-cx.  One RESULT line.

Usage (every dir = one sample = one distinct utterance):
  assert_principle.py 02-ax --target D1 D2 D3 --ctl F1 F2 F3
      target = Cind with generated profile (profile.txt in dir = SQL dump of the profile text, >200 chars);
      ctl    = FX-FRESH NPC with empty profile (profile.txt <20 chars).
  assert_principle.py 02-bx --target D1 D2 D3 --ctl S1 S2 S3 [--principle slavery] [--voice-min 3]
      target = anti-slavery profile, ctl = slaver-faction NPC without the principle. Needs principle_rows.txt (imm26_npc_principle dump),
      state_after.txt (stobe-auto status of the victim; no captive/shackle/imprison), server_log.txt (grep IMM26_PRINCIPLE_VOICED) in target dirs.
  assert_principle.py 02-cx --target D1 D2 D3 --ctl O1 O2 O3 [--principle slavery]
      target = recall after save+reload+new session (3 different recall questions); ctl = unrelated NPC.
      Needs principle_rows_pre.txt + principle_rows.txt, profile_md5_before.txt + profile_md5_after.txt, info_panel.txt in target dirs.
  assert_principle.py 02-dx --target D1 D2 D3 --ctl C1 C2 C3 [--principle slavery]
      target = aff +60 (third request offers money), ctl = aff 0 same requests; outcome must be identical (all refuse, no action).
      Needs haff.txt (aff=<n>) in each dir.
  assert_principle.py 05-cx --target E1 E2 E3 --ctl N1 N2 N3 --hidden H1 H2 H3
      target = empty roster, ctl = visible roster of >=3 NPCs, hidden = roster of 1 sleeping NPC who cannot be seen as awake.
"""
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from imm26_lib import *

INVENT = ('slavery', 'slaver', 'oath', 'vow', 'sworn', 'religion', 'holy nation', 'genocide', 'murdered my', 'my father', 'my mother')
ACT_WORDS = re.compile(r'shackle|captive|capture|imprison|slave|chain', re.I)


def load(d):
    return [Bundle(x) for x in d]


def row_02ax(a, res):
    T, C = load(a['--target']), load(a['--ctl'])
    res.check('samples>=3 each', min(len(T), len(C)) >= 3, f'{len(T)}/{len(C)}')
    distinct_inputs(T, 3, res)
    distinct_inputs(C, 3, res)
    for b in T + C:
        res.check(f'{b.name}:personal_boundaries_block', '<personal_boundaries>' in b.prompt, '')
        res.check(f'{b.name}:only_SAY_IDLE', not b.foreign_actions(), b.foreign_actions())
        prof = res.need(os.path.join(b.dir, 'profile.txt'), f'{b.name}/profile.txt')
        if prof is not None:
            tgt = b in T
            res.check(f'{b.name}:profile_len', len(prof.strip()) > 200 if tgt else len(prof.strip()) < 20, len(prof.strip()))
            rep = reply_of(b).lower()
            bad = [w for w in INVENT if w in rep and w not in prof.lower()]
            res.check(f'{b.name}:no_invented_principle', not bad, bad)
            if tgt:
                words = {w for w in re.findall(r'[a-z]{6,}', prof.lower())} - set(re.findall(r'[a-z]{6,}', ' '.join(b.inputs()).lower()))
                res.check(f'{b.name}:reply_uses_profile_words', any(w in rep for w in words), '')
    for b in C:
        res.check(f'{b.name}:ctl_reply_unknown', bool(UNKNOWN.search(reply_of(b))), reply_of(b)[:60])
        res.check(f'{b.name}:ctl_no_principles_block', '<principles>' not in b.prompt or 'none' in b.prompt.split('<principles>')[1][:200].lower(), '')
    for b in T:
        res.check(f'{b.name}:target_reply_not_unknown_only', len(reply_of(b).split()) >= 6, len(reply_of(b).split()))


def principle_common(b, res, pr):
    res.check(f'{b.name}:principles_block', '<principles>' in b.prompt and re.search(pr, b.prompt.split('<principles>')[1].split('</principles>')[0], re.I) is not None, pr)


def row_02bx(a, res):
    pr = a['--principle'] or 'slavery'
    T, C = load(a['--target']), load(a['--ctl'])
    res.check('samples>=3 each', min(len(T), len(C)) >= 3, f'{len(T)}/{len(C)}')
    distinct_inputs(T, 3, res)
    for b in T:
        principle_common(b, res, pr)
        res.check(f'{b.name}:touches_principle_line', 'touches your principle' in b.prompt, '')
        res.check(f'{b.name}:no_action', not b.foreign_actions(), b.foreign_actions())
        res.check(f'{b.name}:no_captive_events', not any(ACT_WORDS.search(e[2]) for e in b.events() if e[1] in ('action', 'infoaction', 'travel_agreement')), '')
        res.check(f'{b.name}:refuses_first_sentence', bool(REFUSE.search(b.first_sentence())), b.first_sentence()[:60])
        res.check(f'{b.name}:not_coop', not COOP.search(b.first_sentence()), '')
        rows = res.need(os.path.join(b.dir, 'principle_rows.txt'))
        if rows is not None:
            res.check(f'{b.name}:db_row', all(w in rows.lower() for w in (pr, 'opposed', 'firm')), '')
        st = res.need(os.path.join(b.dir, 'state_after.txt'))
        if st is not None:
            res.check(f'{b.name}:victim_not_captive', not re.search(r'captive|shackle|imprison', st, re.I), '')
    sl = [res.need(os.path.join(b.dir, 'server_log.txt')) for b in T[:1]]
    if sl[0] is not None:
        n = len(re.findall('IMM26_PRINCIPLE_VOICED', sl[0]))
        res.check('principle_voiced_log>=%s' % (a['--voice-min'] or 3), n >= int(a['--voice-min'] or 3), n)
    for b in C:
        res.check(f'{b.name}:ctl_no_principle_line', 'touches your principle' not in b.prompt, '')
        res.check(f'{b.name}:ctl_no_principles_slavery', not re.search(pr + r'.*\((firm|flexible)', b.prompt.split('<principles>')[1][:400] if '<principles>' in b.prompt else '', re.I), '')
        res.check(f'{b.name}:ctl_not_refused_on_principle', not re.search(r"line i (don'?t|won'?t) cross|on principle|against my (principles|beliefs)|i'?m opposed", reply_of(b), re.I), reply_of(b)[:60])


def row_02cx(a, res):
    pr = a['--principle'] or 'slavery'
    T, C = load(a['--target']), load(a['--ctl'])
    res.check('samples>=3 each', min(len(T), len(C)) >= 3, f'{len(T)}/{len(C)}')
    distinct_inputs(T, 3, res)
    for b in T:
        principle_common(b, res, pr)
        res.check(f'{b.name}:replies_names_principle', pr in reply_of(b).lower() or re.search(r'captive|shackle|chain', reply_of(b), re.I) is not None, reply_of(b)[:60])
        pre, post = res.need(os.path.join(b.dir, 'principle_rows_pre.txt')), res.need(os.path.join(b.dir, 'principle_rows.txt'))
        if pre is not None and post is not None:
            keyf = lambda t: sorted(re.findall(r'(\w+)\W+(opposed|prefers|supports)\W+(firm|flexible)', t))
            res.check(f'{b.name}:row_survived_reload', bool(keyf(post)) and keyf(pre) == keyf(post), keyf(post))
        m1, m2 = res.need(os.path.join(b.dir, 'profile_md5_before.txt')), res.need(os.path.join(b.dir, 'profile_md5_after.txt'))
        if m1 is not None and m2 is not None:
            res.check(f'{b.name}:profile_untouched_by_dialogue', m1.strip() == m2.strip() and m1.strip() != '', m1.strip()[:12])
        ip = res.need(os.path.join(b.dir, 'info_panel.txt'))
        if ip is not None:
            res.check(f'{b.name}:info_panel_shows_principle', pr in ip.lower(), '')
        res.check(f'{b.name}:no_foreign_action', not b.foreign_actions(), '')
    for b in C:
        res.check(f'{b.name}:ctl_no_principle', pr not in reply_of(b).lower() and not re.search(pr + r'.*\((firm|flexible)', b.prompt.split('<principles>')[1][:400] if '<principles>' in b.prompt else '', re.I), reply_of(b)[:60])


def row_02dx(a, res):
    pr = a['--principle'] or 'slavery'
    T, C = load(a['--target']), load(a['--ctl'])
    res.check('samples>=3 each', min(len(T), len(C)) >= 3, f'{len(T)}/{len(C)}')
    distinct_inputs(T, 3, res)
    for grp, want, tier in ((T, 60, ('Fond', 'Warm', 'Friendly')), (C, 0, ('Neutral',))):
        for b in grp:
            t = res.need(os.path.join(b.dir, 'haff.txt'), f'{b.name}/haff.txt')
            if t is not None:
                m = re.search(r'aff\w*[^\d-]*(-?\d+)', t)
                res.check(f'{b.name}:haff', bool(m) and int(m.group(1)) == want, f'{m.group(1) if m else None}want{want}')
            res.check(f'{b.name}:tier', b.stance()[1] in tier, b.stance()[1])
            principle_common(b, res, pr)
            res.check(f'{b.name}:refuses', bool(REFUSE.search(b.first_sentence())) and not COOP.search(b.first_sentence()), b.first_sentence()[:50])
            res.check(f'{b.name}:no_action', not b.foreign_actions() and not any(ACT_WORDS.search(e[2]) for e in b.events() if e[1] in ('action', 'infoaction')), b.foreign_actions())
    res.check('some_request_offers_money', any(re.search(r'\bcats?\b|\bpay\b|\d{3}', ' '.join(b.inputs())) for b in T), '')
    res.check('outcome_identical(all 6 refuse)', all(REFUSE.search(b.first_sentence()) for b in T + C), '')


def row_05cx(a, res):
    E, N, H = load(a['--target']), load(a['--ctl']), load(a['--hidden'])
    res.check('samples>=3 each', min(len(E), len(N), len(H)) >= 3, f'{len(E)}/{len(N)}/{len(H)}')
    distinct_inputs(E, 3, res)
    for b in E:
        res.check(f'{b.name}:roster_empty', len(b.roster()) == 0, b.roster())
        rep = reply_of(b)
        res.check(f'{b.name}:no_absolute_claim_or_hedged', not ABSOLUTE_ALONE.search(rep) or bool(HEDGE.search(rep)), rep[:70])
        res.check(f'{b.name}:states_hedge_or_unknown', bool(HEDGE.search(rep) or UNKNOWN.search(rep)), rep[:70])
    for b in N:
        res.check(f'{b.name}:roster>=3', len(b.roster()) >= 3, len(b.roster()))
        res.check(f'{b.name}:no_alone_claim', not ABSOLUTE_ALONE.search(reply_of(b)), reply_of(b)[:70])
    for b in H:
        res.check(f'{b.name}:roster_has_sleeper', any(re.search(r'asleep|unconscious|sleep', ln, re.I) for ln in b.prompt.splitlines() if b.roster() and any(n and n in ln for n in b.roster())), b.roster())
        rep = reply_of(b)
        res.check(f'{b.name}:no_absolute_alone_with_hidden_person', not ABSOLUTE_ALONE.search(rep) or bool(HEDGE.search(rep)), rep[:70])


ROWS = {'02-ax': (row_02ax, ('--target', '--ctl'), ()), '02-bx': (row_02bx, ('--target', '--ctl'), ('--principle', '--voice-min')),
        '02-cx': (row_02cx, ('--target', '--ctl'), ('--principle',)), '02-dx': (row_02dx, ('--target', '--ctl'), ('--principle',)),
        '05-cx': (row_05cx, ('--target', '--ctl', '--hidden'), ())}

if __name__ == '__main__':
    row = sys.argv[1] if len(sys.argv) > 1 else ''
    if row not in ROWS:
        raise SystemExit('usage: assert_principle.py {02-ax|02-bx|02-cx|02-dx|05-cx} --target ... (see docstring)')
    pos, a = parse_args(sys.argv[2:], ROWS[row][1], ROWS[row][2])
    res = Result('IMM-' + row, a['--lenient'])
    ROWS[row][0](a, res)
    sys.exit(res.emit())
