#!/usr/bin/env python3
"""unblockcheck_b.py <ROW> <evidence-dir>   verdicts for the imm26-u-rowsB rows: 13-c 13-c-neg 10-e 10-e-inproc 27-a.
Prints exactly ONE line `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence> [evidence=<dir>]` (exit 0/1/2/3), same shape as rowcheck.py.
`unblockcheck_b.py --has <ROW>` exits 0 when the row belongs to this file (pywrap_ub.sh). The mechanical assertions are NOT copied: the existing checks are called
(rowcheck_trip c_13c via rowcheck.CHECKS, reloadcheck_b.c_10e, reloadcheck_a.c_27a); this file only adds the pre-conditions that turn a silent timeout into a named cause:
  13-c      walk ended FAILED native_order_ended_before_goal -> SETUP-FAIL naming the arrival defect (and how far from the gate Cind stopped)
  10-e      the game must really have been restarted (restart.txt `restart=ok`), else SETUP-FAIL; then reloadcheck_b.c_10e (needs the session id to change)
  10-e-inproc  RECORD-ONLY: never PASS/FAIL, prints what the server did (epoch, session id, case statuses) as SETUP-FAIL RECORD-ONLY
  27-a      harness DLL gate (`unknown command`) -> SETUP-FAIL with the install hint; then reloadcheck_a.c_27a (hire proof / state / chase) + the status form that answered"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rowcheck as rc  # noqa: E402
import reloadcheck_a as ra  # noqa: E402
import reloadcheck_b as rb  # noqa: E402

V, rd, need = rc.V, rc.rd, rc.need


def c_13c(v, ev):
    t = rd(ev, 'arrival.txt') or ''
    if 'end=FAILED' in t or re.search(r'\|FAILED\|.*native_order_ended_before_goal', rd(ev, 'agr_final.txt') or ''):
        d = re.search(r'last_progress=\d+\|[^|]*\|(\d+|\?)\|', t)
        return v.setup_fail('arrival defect: the walked trip ended FAILED (native_order_ended_before_goal), so no COMPLETED endpoint and no participation award; Cind stopped '
                            + (f'{d.group(1)} u' if d else '? u') + ' from the gate (walk_progress.txt). Same defect as 23-a / 19-d: needs a grounded TRIP_GATE/TRIP_13C_STAGE or the native arrival fix')
    return rc.CHECKS['13-c'](v, ev)


def c_10e(v, ev):
    t = rd(ev, 'restart.txt') or ''
    if 'restart=ok' not in t:
        return v.setup_fail('the real game restart did not complete (restart.txt has no restart=ok): ' + ' '.join(t.split())[:160])
    return rb.c_10e(v, ev)


def c_10einproc(v, ev):
    if not need(v, ev, 'probe_pre.json', 'probe_eval.json'):
        return
    pre, evl = rb.pj(ev, 'probe_pre.json'), rb.pj(ev, 'probe_eval.json')
    if not pre or not evl or pre.get('error') or evl.get('error'):
        return v.setup_fail('probe unusable: ' + ' '.join((rd(ev, 'probe_eval.json') or '').split())[:160])
    s0, s1 = pre['scope'], evl['live']
    cases = '; '.join(f"{k}={c.get('status')}/{c.get('note')}" for k, c in (evl.get('cases') or {}).items())
    return v.setup_fail(f"RECORD-ONLY in-process load (not a row verdict): epoch {s0.get('timeline_epoch')}->{s1.get('timeline_epoch')}, session "
                        f"{'CHANGED' if s0.get('native_session_id') != s1.get('native_session_id') else 'SAME'}, campaign {'same' if s0.get('campaign_id') == s1.get('campaign_id') else 'DIFFERENT'}; {cases}")


def c_27a(v, ev):
    g = rd(ev, 'dll_gate.txt') or ''
    if re.search(r'unknown command', g, re.I):
        return v.setup_fail('harness DLL has no contract-bodyguard (answer: ' + ' '.join(g.split())[:60] + '): install eeed8c93 with install-harness-4080-i4.ps1 (game stopped), relaunch, rerun')
    ra.c_27a(v, ev)
    forms = [ln for ln in (rd(ev, 'status_forms.txt') or '').splitlines() if 'has_contract=' in ln]
    v.note = (v.note + ' | ' if v.note else '') + 'status read-back: ' + (f'{len(forms)} answer(s), first form: ' + ' '.join(forms[0].split())[:80] if forms else 'no form answered has_contract= (hire proof / chase used)')


CHECKS = {'13-c': c_13c, '13-c-neg': c_13c, '10-e': c_10e, '10-e-inproc': c_10einproc, '27-a': c_27a}


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if rc.norm(argv[2]) in CHECKS else 1
    if len(argv) < 3 or rc.norm(argv[1]) not in CHECKS:
        print(f'usage: unblockcheck_b.py <ROW> <evidence-dir>   rows: {" ".join(sorted(CHECKS))}', file=sys.stderr)
        return 2
    v = V(argv[1])
    CHECKS[rc.norm(argv[1])](v, argv[2])
    if v.note:
        v.good.append(v.note)
    if os.environ.get('UNBLOCK_B_DEBUG'):   # selftest hook (stderr -> run.log)
        print("BADCHECKS n=%d :: " % len(v.bad) + ' ## '.join(v.bad), file=sys.stderr)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
