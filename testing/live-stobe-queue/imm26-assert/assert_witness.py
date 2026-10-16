#!/usr/bin/env python3
"""Witness / effect-number / knowledge-provenance family: IMM-03-cx, 04-ax, 13-ax, 15-bx.  One RESULT line.

  assert_witness.py 03-cx --run R1 R2 --victim Malzin --friend "Rel Vik" --ko "Rel Fen" --stranger "Rel Cee" [--band 0.20 0.60]
  assert_witness.py 04-ax --run R1 R2 --victim "Rel Cee" --friend "Rel Vik" --stranger "Rel Q" [--samefaction "Rel Fen"] [--band 0.05 0.70]
      One --run dir per FRESH save (>=2). Each dir: effects.txt (FULL detail, no left(..,200); see row text), ids.txt (`Name|storage id` for victim/friend/ko/stranger), distance.txt
      (lines `name|distance|faction`, victim included), haff.txt (04-ax: `Vik->Cee aff=60`).
      03-cx: victim row `meaningful_aid`, witness rows `witness_meaningful_aid`; friend ratio in band, KO'd friend 0 rows,
             different-faction non-friend stranger at the same distance (+-3) gets 0 rows or a lower weight than the friend.
      04-ax: victim row `aggression`, witness rows `witness_aggression`; friend aff>=56, ratio in band (0.25-0.40 recorded as `target_band`),
             stranger (DIFFERENT faction, aff 0, same distance) 0 rows; optional same-faction neutral must have weight < friend weight.
  assert_witness.py 13-ax --pos P1 P2 --neg N1 N2 --ctl C1 [--price 353]
      Each dir (fresh save, fresh pair): effects.txt, deal.txt (`contract=deal-.. status=COMPLETE|BREACHED_PLAYER price=N`), cats.txt
      (`shay_before= shay_after= npc_before= npc_after=`), haff_before.txt + haff_after.txt (`aff=<n>`), save.txt (save name).
      pos: kept_promise 1..3, incident deal:<contract>, cats moved by price, aff delta == row delta (>0).
      neg: broken_promise -15..-5, incident deal:<contract>, cats unmoved, aff delta == row delta (<0). ctl: no kept/broken row, aff unchanged.
  assert_witness.py 15-bx --out D1 D2 D3 --inrange P1 P2 P3 --fighters "A,B" --starter A
      out = NPC asleep/KO or >=250 u away (distance.txt `name|dist`; fight events reach everyone within ShoutRadius 200) asked 3 different phrasings of "who started the fight"; inrange = participant/witness (<=15).
"""
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from imm26_lib import *


def dist_map(b, res):
    t = res.need(os.path.join(b.dir, 'distance.txt'), f'{b.name}/distance.txt')
    out = {}
    for ln in (t or '').splitlines():
        p = [x.strip() for x in ln.split('|')]
        if len(p) >= 2:
            try:
                out[p[0].lower()] = (float(p[1]), p[2].lower() if len(p) > 2 else '')
            except ValueError:
                pass
    return out


def rows_for(effs, kind, name, ids=None):
    """Rows of `kind` whose observer is `name` (by observer_name in the detail JSON, or by storage id from ids.txt)."""
    key = (ids or {}).get(name.lower())
    return [e for e in effs if e['kind'] == kind and (name.lower() in (e['observer'] or '').lower()
                                                       or (key and e['obs_key'].endswith(':' + key)))]


def row_witness(a, res, vk, wk, default_band, mode):
    lo, hi = (float(a['--band'][0]), float(a['--band'][1])) if a['--band'] else default_band
    runs = [Bundle(d) for d in a['--run']]
    res.check('fresh_save_runs>=2', len(runs) >= 2, len(runs))
    ratios = []
    for b in runs:
        effs, ids = b.new_effects(), b.ids()
        res.check(f'{b.name}:effects_parsed', len(effs) > 0, len(effs))
        vic = [e for e in effs if e['kind'] == vk]
        res.check(f'{b.name}:victim_row', len(vic) >= 1, len(vic))
        if not vic:
            continue
        vd = max(vic, key=lambda e: abs(e['delta']))['delta']
        fr = rows_for(effs, wk, a['--friend'], ids)
        res.check(f'{b.name}:friend_row', len(fr) == 1, len(fr))
        if fr:
            r = fr[0]['delta'] / vd if vd else 0
            ratios.append(r)
            res.check(f'{b.name}:friend_ratio_in[{lo},{hi}]', lo <= r <= hi, round(r, 3))
            res.check(f'{b.name}:friend_sign_matches_victim', (fr[0]['delta'] > 0) == (vd > 0), fr[0]['delta'])
            res.check(f'{b.name}:culprit_is_player', all(e['culprit'].lower().startswith(('shay', 'kint')) for e in fr), fr[0]['culprit'])
            if mode == '04':
                res.check(f'{b.name}:target_band_0.25-0.40', 0.25 <= r <= 0.40, round(r, 3))
        dm = dist_map(b, res)
        fd = dm.get(a['--friend'].lower())
        sd = dm.get((a['--stranger'] or '').lower())
        if mode == '04':
            h = res.need(os.path.join(b.dir, 'haff.txt'), f'{b.name}/haff.txt')
            if h is not None:
                v = num_file(h, r'aff\w*[^\d-]*(-?\d+)')
                res.check(f'{b.name}:friend_aff>=56', v is not None and v >= 56, v)
        if a['--stranger']:
            st = rows_for(effs, wk, a['--stranger'], ids)
            if sd and fd:
                res.check(f'{b.name}:stranger_same_distance(+-3)', abs(sd[0] - fd[0]) <= 3, f'{sd[0]}vs{fd[0]}')
                vf = dm.get((a['--victim'] or '').lower())
                if vf:
                    res.check(f'{b.name}:stranger_other_faction', sd[1] != vf[1] and sd[1] != '', f'{sd[1]}vs{vf[1]}')
            elif sd is not None or fd is not None or not res.lenient:
                res.check(f'{b.name}:stranger_distance_known', False, 'distance.txt lacks stranger/friend')
            res.check(f'{b.name}:stranger_no_row', len(st) == 0 or (fr and abs(st[0]['delta']) < abs(fr[0]['delta'])), len(st))
            if mode == '04':
                res.check(f'{b.name}:stranger_zero_rows_strict', len(st) == 0, len(st))
        if mode == '03' and a['--ko']:
            res.check(f'{b.name}:ko_friend_no_row', len(rows_for(effs, wk, a['--ko'], ids)) == 0, '')
        if a['--samefaction']:
            sf = rows_for(effs, wk, a['--samefaction'], ids)
            res.check(f'{b.name}:samefaction_weight<friend', not sf or (fr and (sf[0]['weight'] or 0) < (fr[0]['weight'] or 9)), [x['weight'] for x in sf])
    if ratios:
        res.check('ratio_spread<=0.15 across runs', max(ratios) - min(ratios) <= .15, [round(r, 3) for r in ratios])


def row_13ax(a, res):
    price = float(a['--price'] or 0)
    sets = (('pos', a['--pos'], 'kept_promise', (1, 3), 'COMPLETE'), ('neg', a['--neg'], 'broken_promise', (-15, -5), 'BREACHED_PLAYER'))
    ids, saves = [], []
    for lab, dirs, kind, (lo, hi), status in sets:
        res.check(f'{lab}_runs>=2(fresh saves)', len(dirs) >= 2, len(dirs))
        for d in dirs:
            b = Bundle(d)
            eff = [e for e in b.new_effects() if e['kind'] == kind]
            res.check(f'{b.name}:{kind}_row', len(eff) >= 1, len(eff))
            dl = res.need(os.path.join(d, 'deal.txt'))
            cats, hb, ha, sv = (res.need(os.path.join(d, f)) for f in ('cats.txt', 'haff_before.txt', 'haff_after.txt', 'save.txt'))
            if sv is not None:
                saves.append(sv.strip())
            cid = None
            if dl is not None:
                m = re.search(r'contract=(\S+)', dl)
                cid = m.group(1) if m else None
                ids.append(cid)
                res.check(f'{b.name}:status={status}', re.search(r'status=' + status + r'\b', dl) is not None, '')
                if not price:
                    p = num_file(dl, r'price=(\d+)')
                    price_l = p or 0
                else:
                    price_l = price
            if eff:
                res.check(f'{b.name}:{kind}_delta_in[{lo},{hi}]', lo <= eff[0]['delta'] <= hi, eff[0]['delta'])
                res.check(f'{b.name}:incident=deal:<contract>', cid is not None and eff[0]['incident'] == f'deal:{cid}', eff[0]['incident'])
                res.check(f'{b.name}:no_opposite_row', not [e for e in b.new_effects() if e['kind'] == ('broken_promise' if lab == 'pos' else 'kept_promise')], '')
            if cats is not None and dl is not None:
                g = lambda k: num_file(cats, k + r'=(-?\d+)')
                sb, sa, nb, na = g('shay_before'), g('shay_after'), g('npc_before'), g('npc_after')
                if lab == 'pos':
                    res.check(f'{b.name}:cats_moved_by_price', sb is not None and sb - sa == price_l and na - nb == price_l, f'{sb}->{sa},{nb}->{na}')
                else:
                    res.check(f'{b.name}:cats_unmoved', sb == sa and nb == na, f'{sb}->{sa},{nb}->{na}')
            if hb is not None and ha is not None and eff:
                a0, a1 = num_file(hb, r'aff\w*[^\d-]*(-?\d+)'), num_file(ha, r'aff\w*[^\d-]*(-?\d+)')
                res.check(f'{b.name}:fresh_pair(|aff_before|<=10)', a0 is not None and abs(a0) <= 10, a0)
                res.check(f'{b.name}:aff_delta=={eff[0]["delta"]}', a0 is not None and a1 is not None and a1 - a0 == eff[0]['delta'], f'{a0}->{a1}')
                res.check(f'{b.name}:aff_direction', (a1 - a0 > 0) if lab == 'pos' else (a1 - a0 < 0), a1 - a0)
    for d in a['--ctl']:
        b = Bundle(d)
        res.check(f'{b.name}:ctl_no_kept_broken', not [e for e in b.new_effects() if e['kind'] in ('kept_promise', 'broken_promise')], '')
        hb, ha = res.need(os.path.join(d, 'haff_before.txt')), res.need(os.path.join(d, 'haff_after.txt'))
        if hb is not None and ha is not None:
            res.check(f'{b.name}:ctl_aff_unchanged', num_file(hb, r'aff\w*[^\d-]*(-?\d+)') == num_file(ha, r'aff\w*[^\d-]*(-?\d+)'), '')
    ids = [i for i in ids if i]
    res.check('contracts_distinct', len(set(ids)) == len(ids) and len(ids) >= 4, f'{len(set(ids))}/{len(ids)}')
    res.check('saves_distinct', len(set(saves)) == len(saves) and len(saves) >= 4 or res.lenient and not saves, len(set(saves)))


def row_15bx(a, res):
    O, I = [Bundle(d) for d in a['--out']], [Bundle(d) for d in a['--inrange']]
    fighters = [f.strip() for f in (a['--fighters'] or '').split(',') if f.strip()]
    res.check('samples>=3 each', min(len(O), len(I)) >= 3, f'{len(O)}/{len(I)}')
    res.check('fighters>=2', len(fighters) >= 2, fighters)
    distinct_inputs(O, 3, res)
    distinct_inputs(I, 3, res)
    combat_line = lambda b: [l for l in b.prompt.splitlines() if re.search(r'\[combat[^\]]*\]', l) and any(f.lower() in l.lower() for f in fighters)]
    for b in O:
        dm = dist_map(b, res)
        far = [v[0] for k, v in dm.items() if k not in [f.lower() for f in fighters]]
        # the DLL tags a fight's events for every character within max(ShoutRadius 200, TalkRadius 80) (Utils.cpp:1327-1348), so 60-94 u is
        # INSIDE the audience by design; X must be >= 250 u (write ShoutRadius into distance.txt) or asleep/KO (see --asleep)
        res.check(f'{b.name}:out_of_range>=250', bool(dm) and min(far or [0]) >= 250 or res.lenient and not dm, far[:2])
        res.check(f'{b.name}:no_fight_event_in_prompt', not combat_line(b), len(combat_line(b)))
        rep = reply_of(b)
        res.check(f'{b.name}:no_eyewitness_claim', not EYEWITNESS.search(rep), (EYEWITNESS.search(rep).group(0) if EYEWITNESS.search(rep) else ''))
        res.check(f'{b.name}:hedge_or_hearsay', bool(HEARSAY_OK.search(rep)), rep[:60])
        res.check(f'{b.name}:starter_not_asserted', (a['--starter'] or '').lower() not in rep.lower() or bool(HEARSAY_OK.search(rep)) and 'heard' in rep.lower(), '')
        res.check(f'{b.name}:no_action', not b.foreign_actions(), b.foreign_actions())
    for b in I:
        dm = dist_map(b, res)
        res.check(f'{b.name}:in_range<=15', any(v[0] <= 15 for k, v in dm.items() if k not in [f.lower() for f in fighters]) or res.lenient and not dm, '')
        res.check(f'{b.name}:fight_event_in_prompt', bool(combat_line(b)), len(combat_line(b)))
        res.check(f'{b.name}:starter_event_in_prompt', any(re.search(re.escape(a['--starter'] or '~'), l) and 'Initiated attack' in l for l in b.prompt.splitlines()), a['--starter'])
    # extra measurement (rowfix 2026-10-15): an asleep/KO NPC within 100 u. CollectEventPeopleFromAnchor has no sleep/KO filter, so if it
    # still gets [combat] lines that is a REAL DEFECT recorded as its own check (not a fixture problem).
    for d in a['--asleep']:
        b = Bundle(d)
        dm = dist_map(b, res)
        far = [v[0] for k, v in dm.items() if k not in [f.lower() for f in fighters]]
        res.check(f'{b.name}:asleep_within_100u', bool(far) and max(far) <= 100 or res.lenient and not dm, far[:2])
        res.check(f'{b.name}:asleep_no_fight_event_DEFECT_if_fail', not combat_line(b), len(combat_line(b)))
    res.check('inrange_names_starter>=2/3', sum((a['--starter'] or '~').split(' ')[0].lower() in reply_of(b).lower() for b in I) >= 2, '')


ROWS = {'03-cx': ('--run', ('--run',), ('--victim', '--friend', '--ko', '--stranger', '--samefaction')),
        '04-ax': ('--run', ('--run',), ('--victim', '--friend', '--stranger', '--samefaction')),
        '13-ax': (None, ('--pos', '--neg', '--ctl'), ('--price',)),
        '15-bx': (None, ('--out', '--inrange', '--asleep'), ('--fighters', '--starter'))}

if __name__ == '__main__':
    row = sys.argv[1] if len(sys.argv) > 1 else ''
    if row not in ROWS:
        raise SystemExit('usage: assert_witness.py {03-cx|04-ax|13-ax|15-bx} ... (see docstring)')
    multi = ROWS[row][1] + (('--band',) if row in ('03-cx', '04-ax') else ())
    pos, a = parse_args(sys.argv[2:], multi, ROWS[row][2])
    res = Result('IMM-' + row, a['--lenient'])
    if row == '03-cx':
        row_witness(a, res, 'meaningful_aid', 'witness_meaningful_aid', (0.20, 0.60), '03')
    elif row == '04-ax':
        row_witness(a, res, 'aggression', 'witness_aggression', (0.05, 0.70), '04')
    elif row == '13-ax':
        row_13ax(a, res)
    else:
        row_15bx(a, res)
    sys.exit(res.emit())
