#!/usr/bin/env python3
"""unblockcheck_f3.py <ROW> <evidence-dir>   13-c / 13-c-neg verdicts = unblockcheck_f.py + the NATIVE PARTICIPATION state (imm26-sfFixB). Nothing of the f checks is weakened:
  13-c     : unblockcheck_f.c_pos unchanged. If it ends FAIL only because no sharedexp row appeared AND the native proof says participation_bound=0 or participation_qualified=0,
             the verdict becomes SETUP-FAIL naming the cause (an unbound/unqualified walk is a recipe/DLL defect, not a disproof of the award path).
  13-c-neg : unblockcheck_f.c_neg unchanged. A PASS additionally needs the proof to be BOUND (participation_bound=1) and NOT qualified (participation_qualified=0), i.e. the
             award path was really exercised and refused because Shay was away; otherwise SETUP-FAIL (the 'no row' would be true on any DLL without NC21 / on any failed bind).
Same output shape as unblockcheck_f.py (exactly one RESULT line, exit 0/1/2). `--has <ROW>` exits 0 for 13-c 13-c-neg."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rowcheck as rc  # noqa: E402
import unblockcheck_f as uf  # noqa: E402

V, rd = rc.V, rc.rd


def part(ev):
    """(bound '1'|'0'|None, qualified '1'|'0'|None, diag str) from native_travel.txt"""
    nat = rd(ev, 'native_travel.txt') or ''
    b = re.search(r'NATIVE_TRAVEL_START.*?participation_bound=(\d)', nat)
    qs = re.findall(r'participation_qualified=(\d)', nat)
    ds = re.findall(r'participation_diag=(\S+)', nat)
    why = re.search(r'participation_why=(\S+)', nat)
    return (b.group(1) if b else None), (qs[-1] if qs else None), (ds[-1] if ds else ''), (why.group(1) if why else '')


def c_pos(v, ev):
    uf.c_pos(v, ev)
    if not any(('sharedexp' in x or 'Participation award' in x) for x in v.bad):   # PASS, or a failure unrelated to the missing award/row
        return
    b, q, d, why = part(ev)
    msg = None
    if b == '0':
        msg = f'native participation proof NOT BOUND (participation_bound=0 why={why or "?"}): the lane DLL lacks NC21 (hand_<serial> identity) or the bind failed; native_travel.txt'
    elif q == '0':
        msg = 'native participation proof bound but NOT QUALIFIED (the keeper walk did not hold Shay within 35 u of the NPC for the last window; need samples>=4, span>=30, actor_d/partner_d/progress>=30): ' + (d or 'no diag')[:220]
    if msg:   # an unbound / unqualified walk is a recipe or DLL defect, not a disproof of the award path: name it first
        v.bad.insert(0, msg)
        v.kind = 'SETUP-FAIL'


def c_neg(v, ev):
    uf.c_neg(v, ev)
    if v.kind is not None or v.bad:
        return
    b, q, d, why = part(ev)
    if b != '1':
        v.setup_fail(f'negative leg passed with an unbound proof (participation_bound={b} why={why or "?"}): "no row" would be true on any DLL without NC21; nothing was disproven')
    elif q == '1':
        v.setup_fail('negative leg: the proof QUALIFIED although Shay was held behind (recipe defect: TRIP_13C_NEG_GAP too small or Shay was teleported onto the NPC): ' + d[:200])
    elif q is None:
        v.setup_fail('negative leg: no terminal NATIVE_TRAVEL participation_qualified line in native_travel.txt, so the refusal of the award cannot be shown')


uf.CHECKS = {'13-c': c_pos, '13-c-neg': c_neg}

if __name__ == '__main__':
    sys.exit(uf.main(sys.argv))
