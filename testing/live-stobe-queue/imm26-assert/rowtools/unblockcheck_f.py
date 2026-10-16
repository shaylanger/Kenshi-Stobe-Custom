#!/usr/bin/env python3
"""unblockcheck_f.py <ROW> <evidence-dir>   verdicts for 13-c and 13-c-neg run by unblockrun_f.sh (NC18 arrival turn; evidence written by unblockdefs_f.sh).
Prints exactly ONE line `RESULT <ROW> PASS|FAIL|SETUP-FAIL ...` (exit 0/1/2), same shape as rowcheck.py. `--has <ROW>` exits 0 when the row belongs to this file.
Nothing of the mechanical assertions is copied or weakened: the COMPLETED path calls unblockcheck_b.c_13c (-> rowcheck_trip c_13c: positive = a new `sharedexp:` kept_promise
row with delta > 0; negative = no new sharedexp row). This file adds only the named causes in front of it:
  * end=TIMEOUT and no NATIVE_TRAVEL line at all -> SETUP-FAIL: the lane does not run the NC18 Stobe.dll (D54D0268).
  * end=TIMEOUT otherwise -> SETUP-FAIL: no native arrival within the walk tries (no 'We're here' turn was sent).
  * 13-c-neg only: the trip did NOT reach COMPLETED (Shay held behind: native FAILED / expired) -> the agreement is terminal and there is NO new sharedexp row = PASS
    (`no_sharedexp_row_when_trip_not_completed`); a new row is FAIL; still not terminal after the arrival turn -> SETUP-FAIL (the server never reconciled: nothing was
    disproven); FAILED with native_order_ended_before_goal -> SETUP-FAIL (arrival defect, not a disproof)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rowcheck as rc  # noqa: E402
import unblockcheck_b as ub  # noqa: E402

V, rd = rc.V, rc.rd
TERMINAL = ('COMPLETED', 'FAILED', 'ENDED', 'EXPIRED', 'CANCELLED')


def native_gate(v, ev):
    """True when the walk reached a native end; else records SETUP-FAIL with the named cause"""
    arr = rd(ev, 'arrival.txt') or ''
    nat = rd(ev, 'native_travel.txt') or ''
    if 'end=TIMEOUT' in arr:
        if 'NATIVE_TRAVEL' not in nat:
            v.setup_fail('no NATIVE_TRAVEL line in the lane stobe.log during the walk: the lane does not run the NC18 Stobe.dll (D54D0268) or the order never started (native_travel.txt, s2/reply.txt)')
        else:
            v.setup_fail('no native arrival (NATIVE_TRAVEL_FINISH / phase=completed|failed / ORDER_ENDED) within the walk tries, so no "We\'re here" turn was sent: ' + ' '.join(nat.split())[:200])
        return False
    return True


def agr_rows(ev, name):
    out = []
    for ln in (rd(ev, name) or '').splitlines():
        p = ln.strip().split('|')
        if len(p) >= 7 and p[0].isdigit():
            out.append(dict(rowid=int(p[0]), status=p[1], phase=p[2], reason=p[3], aid=p[5]))
    return out   # newest first


def native_note(ev):
    arr = rd(ev, 'arrival.txt') or ''
    m1, m2 = re.search(r'native_start=(\S*)', arr), re.search(r'native_finish=(\S*)', arr)
    return 'native: start=' + ((m1.group(1) if m1 else '') or 'none')[:90] + ' finish=' + ((m2.group(1) if m2 else '') or 'none')[:90]


def c_pos(v, ev):
    if not native_gate(v, ev):
        return
    ub.c_13c(v, ev)
    v.note = (v.note + ' | ' if v.note else '') + native_note(ev)


def c_neg(v, ev):
    if not native_gate(v, ev):
        return
    if not rc.need(v, ev, 'agr_trip.txt', 'agr_final.txt', 'se_before.txt', 'se_after.txt', 'neg.txt'):
        return
    trip = agr_rows(ev, 'agr_trip.txt')
    if not trip:
        return v.setup_fail('no travel_agreement row while setting up the trip (propose/accept legs failed; see s1/s2)')
    aid = trip[0]['aid']
    fin = [r for r in agr_rows(ev, 'agr_final.txt') if r['aid'] == aid]
    st = fin[0] if fin else None
    if st and st['status'] == 'COMPLETED':
        ub.c_13c(v, ev)   # original negative assertion: no_sharedexp_row_when_shay_far
        v.note = (v.note + ' | ' if v.note else '') + 'trip COMPLETED, ' + native_note(ev)
        return
    if not st or st['status'] not in TERMINAL:
        return v.setup_fail('the agreement is still ' + (st['status'] if st else 'not found') + ' after the arrival turn: the server never reconciled the native receipt, so nothing was disproven (s3/ prompt, native_travel.txt)')
    if 'native_order_ended_before_goal' in st['reason']:
        return v.setup_fail('arrival defect: FAILED native_order_ended_before_goal is not a participation disproof (Cind stopped short of the gate); ' + native_note(ev))

    def sx(name):
        return {ln.split('|')[0] for ln in (rd(ev, name) or '').splitlines() if ln.startswith('sharedexp:')}
    new = sx('se_after.txt') - sx('se_before.txt')
    v.ck('no_sharedexp_row_when_trip_not_completed', not new, f'agreement={st["status"]}/{st["reason"] or "-"} new_rows={len(new)}')
    v.note = 'R~ negative leg (Shay held behind): trip not completed; ' + native_note(ev)


CHECKS = {'13-c': c_pos, '13-c-neg': c_neg}


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if rc.norm(argv[2]) in CHECKS else 1
    if len(argv) < 3 or rc.norm(argv[1]) not in CHECKS:
        print('usage: unblockcheck_f.py <ROW> <evidence-dir>   rows: 13-c 13-c-neg', file=sys.stderr)
        return 2
    v = V(argv[1])
    CHECKS[rc.norm(argv[1])](v, argv[2])
    if v.note:
        v.good.append(v.note)
    if os.environ.get('UNBLOCK_B_DEBUG'):
        print("BADCHECKS n=%d :: " % len(v.bad) + ' ## '.join(v.bad), file=sys.stderr)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
